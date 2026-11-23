// ExportViews.swift — A2 + A3 (vòng 2): tầng app của đường XUẤT.
//
// - A2: gói file gốc cho kế toán — lọc theo loại + khoảng ngày -> một
//   ZIP gồm file gốc NGUYÊN BYTE + muc-luc.csv. Chỉ ĐỌC dữ liệu đã lưu.
// - A3: Tax Pack theo năm — PDF tóm tắt + CSV chi tiết Schedule C, đóng
//   gói chung kiểu ZIP của A2 (kèm file gốc + mục lục của tờ chính thức
//   trong năm). Thay dòng "sẽ có ở bản sau" ở Báo Cáo Thuế.
//
// Mọi con số đi qua TaxReportMath (ExportKit.swift) — cùng hàm màn Báo
// Cáo Thuế dùng — và CSV vừa sinh được CỘNG LẠI so với tổng màn hình
// trước khi đưa cho anh (lệch là không xuất). ZIP vừa ghi được ĐỌC LẠI
// (CRC từng mục + so byte với file gốc) trước khi mở phiếu chia sẻ.

import Foundation
import SwiftUI
import SwiftData
import UIKit

// MARK: - Dựng đầu vào xuất từ bản ghi (main)

enum ExportInputBuilder {
    /// Năm theo ĐÚNG luật màn Báo Cáo Thuế hiện hành (năm của ngày mua).
    static func reportYear(_ r: Receipt) -> Int {
        Calendar.current.component(.year, from: r.date)
    }

    /// Bản nhẹ (không đọc file) — dùng cho màn Báo Cáo.
    static func light(_ r: Receipt) -> ExportReceiptInput {
        ExportReceiptInput(
            id: MirrorReceiptSnapshot.folderID(for: r),
            date: r.date,
            reportYear: reportYear(r),
            vendor: r.vendor,
            kindRaw: r.classificationRaw,
            kindNormalized: r.classification.rawValue,
            isOfficial: r.isOfficialRecord,
            isPending: r.isPendingRecord,
            isNeedsReview: r.status == .needsReview,
            category: r.category,
            scheduleCLine: r.scheduleCLine,
            subtotalCents: r.subtotalCents,
            taxCents: r.taxTotalCents,
            totalCents: r.totalCents,
            countedCents: r.countedAmountCents,
            tipCents: r.tipAmountCents,
            cardLast4: r.cardLast4,
            businessPurpose: r.businessPurpose,
            estimatedFields: [],
            provenanceKnown: false,
            originals: r.allOriginalImageFileNames.map {
                ExportFileRef(localName: $0, data: nil)
            })
    }

    /// Bổ sung phần đọc ĐĨA (chạy nền): byte file gốc + nguồn số từ hồ
    /// sơ đọc. `userEntered` theo thứ tự tương ứng.
    static func loadFiles(_ inputs: [ExportReceiptInput],
                          diagnosticsKeys: [String],
                          userEntered: [[String]],
                          directory: URL) -> [ExportReceiptInput] {
        var out = inputs
        for i in out.indices {
            out[i].originals = out[i].originals.map { ref in
                let url = directory.appendingPathComponent(ref.localName)
                return ExportFileRef(localName: ref.localName,
                                     data: try? Data(contentsOf: url, options: .alwaysMapped))
            }
            let key = diagnosticsKeys[i]
            if !key.isEmpty,
               let diag = DiagnosticsStore.load(directory: directory, imageFileName: key) {
                out[i].estimatedFields = EstimateRule.estimatedFields(
                    landingFlag: diag.outcome.flags.contains("tax-landing"),
                    rawSubtotalMissing: diag.parse.subtotalCents == nil,
                    rawTaxMissing: diag.parse.taxes.isEmpty,
                    rawTotalMissing: diag.parse.totalCents == nil,
                    userEntered: userEntered[i])
                out[i].provenanceKnown = true
            }
        }
        return out
    }
}

// MARK: - Dựng gói (nền)

enum ExportBuilder {
    enum Failure: Error { case text(String) }

    static func exportsDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("glkeeper-exports", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Đọc lại ZIP vừa ghi: mọi mục CRC đúng; mọi file gốc khớp byte
    /// nguồn; đủ số mục mong đợi.
    static func roundTrip(zipURL: URL, expected: [String: Data],
                          expectedNames: Set<String>) throws {
        let zip = try Data(contentsOf: zipURL, options: .alwaysMapped)
        var seen = Set<String>()
        try ZipReader.forEachEntry(of: zip) { name, data in
            seen.insert(name)
            if let src = expected[name], src != data {
                throw Failure.text("mục \(name) khác byte bản gốc")
            }
        }
        guard seen == expectedNames else {
            throw Failure.text("ZIP thiếu/thừa mục (\(seen.count) / \(expectedNames.count))")
        }
    }

    /// A2: gói file gốc cho kế toán.
    static func accountantZip(_ inputs: [ExportReceiptInput], label: String)
        throws -> (url: URL, summary: AccountantExport.Summary) {
        let url = try exportsDirectory()
            .appendingPathComponent("GL-Keeper-goc-\(label).zip")
        let zip = try ZipWriter(url: url)
        let summary = try AccountantExport.write(inputs, into: zip)
        try zip.finish()
        var expected: [String: Data] = [:]
        for r in inputs {
            for (k, f) in r.originals.enumerated() {
                if let d = f.data {
                    expected[AccountantExport.entryName(folder: "goc", receipt: r,
                                                        index: k, localName: f.localName)] = d
                }
            }
        }
        try roundTrip(zipURL: url, expected: expected,
                      expectedNames: Set(expected.keys).union([AccountantExport.indexName]))
        return (url, summary)
    }

    /// A3: Tax Pack của một năm.
    static func taxPack(_ all: [ExportReceiptInput], year: Int) throws -> URL {
        let yearRows = TaxReportMath.yearRows(all, year: year)
        let totals = TaxReportMath.totals(yearRows)
        let (csv, official) = TaxPackCSV.document(yearRows)
        guard TaxPackCSV.verify(csv, against: totals) else {
            throw Failure.text("CSV không khớp tổng màn Báo Cáo — KHÔNG xuất")
        }
        let pdf = TaxPackPDF.render(year: year, totals: totals,
                                    categories: TaxReportMath.categoryRows(yearRows),
                                    official: official)
        let url = try exportsDirectory()
            .appendingPathComponent("GL-Keeper-TaxPack-\(year).zip")
        let zip = try ZipWriter(url: url)
        let pdfName = "TaxPack-\(year)/tom-tat-\(year).pdf"
        let csvName = "TaxPack-\(year)/chi-tiet-schedule-c-\(year).csv"
        let indexName = "TaxPack-\(year)/\(AccountantExport.indexName)"
        try zip.add(name: pdfName, data: pdf)
        try zip.add(name: csvName, data: csv)
        try AccountantExport.write(official, into: zip,
                                   folder: "TaxPack-\(year)/goc", indexPath: indexName)
        try zip.finish()
        var expected: [String: Data] = [pdfName: pdf, csvName: csv]
        for r in official {
            for (k, f) in r.originals.enumerated() {
                if let d = f.data {
                    expected[AccountantExport.entryName(folder: "TaxPack-\(year)/goc", receipt: r,
                                                        index: k, localName: f.localName)] = d
                }
            }
        }
        try roundTrip(zipURL: url, expected: expected,
                      expectedNames: Set(expected.keys).union([indexName]))
        return url
    }
}

// MARK: - PDF tóm tắt (A3)

enum TaxPackPDF {
    static func render(year: Int, totals: TaxReportMath.Totals,
                       categories: [TaxReportMath.CategoryRow],
                       official: [ExportReceiptInput]) -> Data {
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)   // US Letter
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        let margin: CGFloat = 48
        let body = UIFont.systemFont(ofSize: 11)
        let bold = UIFont.boldSystemFont(ofSize: 11)
        let title = UIFont.boldSystemFont(ofSize: 18)
        let mono = UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let sched = TaxPackCSV.scheduleCSummary(official)
        let estimateCount = official.filter { !$0.estimatedFields.isEmpty }.count
        let unknownSource = official.filter { !$0.provenanceKnown }.count
        let missingFiles = official.reduce(0) { $0 + $1.originals.filter { $0.data == nil }.count }
            + official.filter { $0.originals.isEmpty }.count
        func money(_ c: Int) -> String { "$" + ExportCSV.dollars(c) }

        var lines: [(String, UIFont, String?)] = []   // (trái, font, phải)
        lines.append(("GL-Keeper — Tax Pack \(year)", title, nil))
        lines.append(("Tạo lúc \(AccountantExport.isoDay(Date())) · chỉ tính tờ CHÍNH THỨC (đã duyệt, không bị loại khỏi tổng)", body, nil))
        lines.append(("", body, nil))
        lines.append(("Tổng năm \(year)", bold, nil))
        lines.append(("Cá nhân", body, money(totals.personal)))
        lines.append(("Business", body, money(totals.business)))
        if totals.unknown != 0 { lines.append(("Chưa rõ loại", body, money(totals.unknown))) }
        lines.append(("\(totals.count) hoá đơn trong năm · \(totals.needsReviewCount) tờ đang chờ duyệt (\(money(totals.pending))) — chưa tính vào tổng", body, nil))
        lines.append(("", body, nil))
        lines.append(("Schedule C — theo dòng ĐÃ LƯU trên từng tờ business", bold, nil))
        for l in sched.lines {
            lines.append(("\(l.line) · \(l.count) tờ", body, money(l.total)))
        }
        lines.append(("Chưa gán dòng Schedule C · \(sched.unassignedCount) tờ", body, money(sched.unassignedTotal)))
        lines.append(("(Tờ chưa có dòng Schedule C được để riêng — app không tự gán dòng.)", body, nil))
        lines.append(("", body, nil))
        lines.append(("Theo mục (giống màn Báo Cáo Thuế)", bold, nil))
        for c in categories {
            lines.append(("\(c.kindNormalized == "business" ? "Business" : "Cá nhân") · \(c.name) · \(c.count) tờ", body, money(c.total)))
        }
        lines.append(("", body, nil))
        lines.append(("Ghi chú nguồn số", bold, nil))
        lines.append(("\(estimateCount) tờ có số \(EstimateRule.label) (hạ cánh thuế) — cột nguon_* trong CSV ghi rõ trường nào.", body, nil))
        if unknownSource > 0 {
            lines.append(("\(unknownSource) tờ không còn hồ sơ đọc — nguồn số ghi \"khong_ro_nguon\".", body, nil))
        }
        lines.append(("File gốc thiếu: \(missingFiles) — liệt kê tên trong muc-luc.csv.", body, nil))

        return renderer.pdfData { ctx in
            var y = page.maxY   // ép mở trang đầu
            for (left, font, right) in lines {
                let attrs: [NSAttributedString.Key: Any] = [.font: font]
                let width = page.width - margin * 2 - (right == nil ? 0 : 110)
                let rect = (left as NSString).boundingRect(
                    with: CGSize(width: width, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin], attributes: attrs, context: nil)
                let h = max(ceil(rect.height), font.lineHeight) + 4
                if y + h > page.maxY - margin {
                    ctx.beginPage()
                    y = margin
                }
                (left as NSString).draw(in: CGRect(x: margin, y: y, width: width, height: h),
                                        withAttributes: attrs)
                if let right {
                    let ra: [NSAttributedString.Key: Any] = [.font: mono]
                    let size = (right as NSString).size(withAttributes: ra)
                    (right as NSString).draw(at: CGPoint(x: page.maxX - margin - size.width, y: y),
                                             withAttributes: ra)
                }
                y += h
            }
        }
    }
}

// MARK: - Phiếu chia sẻ file

enum ExportSharePresenter {
    static func share(_ url: URL) {
        DispatchQueue.main.async {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
            guard var top = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
            else { return }
            while let next = top.presentedViewController { top = next }
            let controller = UIActivityViewController(activityItems: [url],
                                                      applicationActivities: nil)
            controller.popoverPresentationController?.sourceView = top.view
            top.present(controller, animated: true)
        }
    }
}

// MARK: - Màn A2: gói file gốc cho kế toán

struct AccountantExportView: View {
    @Query(sort: \Receipt.date) private var receipts: [Receipt]
    @State private var kind: String = "all"
    @State private var from: Date = Calendar.current.date(
        from: DateComponents(year: Calendar.current.component(.year, from: Date()), month: 1, day: 1)) ?? Date()
    @State private var to: Date = Date()
    @State private var officialOnly = false
    @State private var working = false
    @State private var result: String? = nil
    @State private var errorText: String? = nil

    private var selected: [Receipt] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: from)
        let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: to)) ?? to
        return receipts.filter { r in
            (kind == "all" || r.classification.rawValue == kind)
                && r.date >= start && r.date < end
                && (!officialOnly || r.isOfficialRecord)
        }
    }

    var body: some View {
        let picked = selected
        Form {
            Section("Lọc") {
                Picker("Loại", selection: $kind) {
                    Text("Tất cả").tag("all")
                    Text("Cá nhân").tag(Classification.personal.rawValue)
                    Text("Business").tag(Classification.business.rawValue)
                    Text("Chưa rõ").tag(Classification.unknown.rawValue)
                }
                DatePicker("Từ ngày", selection: $from, displayedComponents: .date)
                DatePicker("Đến ngày", selection: $to, displayedComponents: .date)
                Toggle("Chỉ tờ chính thức", isOn: $officialOnly)
            }
            Section {
                Text("\(picked.count) tờ khớp bộ lọc")
                Button(working ? "Đang tạo ZIP…" : "Tạo ZIP file gốc + mục lục") {
                    build(picked)
                }
                .disabled(working || picked.isEmpty)
                if let result {
                    Text(result).font(.callout)
                }
                if let errorText {
                    Text(errorText).font(.callout).foregroundStyle(.red)
                }
            } footer: {
                Text("File gốc vào ZIP NGUYÊN BYTE. Tờ thiếu file gốc vẫn có dòng THIẾU trong muc-luc.csv và được đếm ở dòng TỔNG. App chỉ đọc dữ liệu — không sửa tờ nào.")
            }
        }
        .navigationTitle("Gói file gốc cho kế toán")
    }

    private func build(_ picked: [Receipt]) {
        working = true
        result = nil
        errorText = nil
        let light = picked.map(ExportInputBuilder.light)
        let keys = picked.map(\.imageFileName)
        let entered = picked.map(\.userEnteredFieldNames)
        let dir = ImageStore.directory
        let label = "\(AccountantExport.isoDay(from))_\(AccountantExport.isoDay(to))_\(kind)"
        DispatchQueue.global(qos: .userInitiated).async {
            let full = ExportInputBuilder.loadFiles(light, diagnosticsKeys: keys,
                                                    userEntered: entered, directory: dir)
            let outcome = Result { try ExportBuilder.accountantZip(full, label: label) }
            DispatchQueue.main.async {
                working = false
                switch outcome {
                case .success(let out):
                    let url = out.url, s = out.summary
                    result = "\(s.receipts) tờ · \(s.filesIncluded) file gốc trong ZIP · \(s.filesMissing) file THIẾU (\(s.receiptsWithMissing.count) tờ) — đã đọc lại ZIP, khớp byte."
                    DiagLog.log(.app, "XUẤT kế toán: \(s.receipts) tờ, \(s.filesIncluded) file, \(s.filesMissing) thiếu")
                    ExportSharePresenter.share(url)
                case .failure(let e):
                    errorText = "Không tạo được ZIP: \(e)"
                    DiagLog.log(.app, "XUẤT kế toán THẤT BẠI: \(e)")
                }
            }
        }
    }
}

// MARK: - Mục A3 ở Báo Cáo Thuế

struct TaxPackExportSection: View {
    let year: Int
    let receipts: [Receipt]
    @State private var working = false
    @State private var message: String? = nil
    @State private var errorText: String? = nil

    var body: some View {
        Section {
            Button(working ? "Đang tạo Tax Pack…" : "Xuất Tax Pack \(String(year)) (PDF + CSV + ZIP)") {
                build()
            }
            .disabled(working)
            NavigationLink {
                AccountantExportView()
            } label: {
                Label("Gói file gốc cho kế toán", systemImage: "doc.zipper")
            }
            if let message { Text(message).font(.callout) }
            if let errorText { Text(errorText).font(.callout).foregroundStyle(.red) }
        } header: {
            Text("Xuất hồ sơ thuế")
        } footer: {
            Text("Tax Pack chỉ gồm tờ CHÍNH THỨC; tổng trong PDF/CSV được kiểm khớp từng cent với bảng trên trước khi xuất. Số hạ cánh thuế giữ nhãn ƯỚC TÍNH. Tờ chưa có dòng Schedule C để riêng, app không tự gán.")
        }
    }

    private func build() {
        working = true
        message = nil
        errorText = nil
        let light = receipts.map(ExportInputBuilder.light)
        let keys = receipts.map(\.imageFileName)
        let entered = receipts.map(\.userEnteredFieldNames)
        let dir = ImageStore.directory
        let year = self.year
        DispatchQueue.global(qos: .userInitiated).async {
            let full = ExportInputBuilder.loadFiles(light, diagnosticsKeys: keys,
                                                    userEntered: entered, directory: dir)
            let outcome = Result { try ExportBuilder.taxPack(full, year: year) }
            DispatchQueue.main.async {
                working = false
                switch outcome {
                case .success(let url):
                    message = "Đã tạo Tax Pack \(year) — tổng khớp màn Báo Cáo, ZIP đã đọc lại khớp byte."
                    DiagLog.log(.app, "XUẤT Tax Pack \(year): xong")
                    ExportSharePresenter.share(url)
                case .failure(let e):
                    errorText = "Không tạo được Tax Pack: \(e)"
                    DiagLog.log(.app, "XUẤT Tax Pack \(year) THẤT BẠI: \(e)")
                }
            }
        }
    }
}
