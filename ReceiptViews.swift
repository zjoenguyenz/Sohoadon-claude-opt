import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
import VisionKit

// MARK: - Huy hiệu phân loại: 4 tín hiệu cùng lúc (màu + icon + chữ + badge đuôi thẻ)

struct ClassificationBadge: View {
    var kind: Classification
    var cardLast4: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: kind.iconName)
            Text(kind.label)
            if let cardLast4, !cardLast4.isEmpty {
                Text("•• \(cardLast4)")
            }
        }
        .font(.caption.bold())
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(kind.color)
        .background(kind.color.opacity(0.15))
        .clipShape(Capsule())
    }
}

// MARK: - Cửa chẩn đoán F3 (WP1): xem văn bản đọc thô — bằng chứng gốc khi đọc sai
//
// Một component dùng chung cho cả 2 màn (Kiểm Lại + Chi Tiết) để hành vi
// không lệch nhau: DisclosureGroup mặc định THU GỌN (không truyền
// isExpanded), chữ monospaced cỡ caption, chọn/copy được để anh gửi
// nguyên văn khi báo lỗi. `title` là tham số để WP3 (đường PDF) chỉ cần
// truyền nhãn "Văn bản trong PDF" ở 2 điểm gọi — không dựng lại viewer.
// WP1 chỉ có đường OCR nên cả 2 điểm gọi đều dùng nhãn OCR (mặc định).

/// WP3 bước 2 — QUYẾT NHÃN F3 (chốt ở cổng WP3): nhãn phải nói đúng
/// ĐƯỜNG nào sinh ra chữ (CODE-AUDIT F3 mục 3), không chỉ nguồn nạp:
/// lớp chữ PDF -> "Văn bản trong PDF"; PDF render->OCR -> "Văn bản OCR
/// gốc (từ PDF)"; mọi đường ảnh -> "Văn bản OCR gốc". Một helper dùng
/// chung cho Kiểm Lại (theo draft) và Chi Tiết (theo bản ghi đã lưu).
func rawTextTitle(sourceType: SourceType, isPDFTextLayer: Bool) -> String {
    if isPDFTextLayer { return "Văn bản trong PDF" }
    if sourceType == .pdfImport { return "Văn bản OCR gốc (từ PDF)" }
    return "Văn bản OCR gốc"
}

struct RawTextDisclosure: View {
    var text: String
    var title: String = "Văn bản OCR gốc"

    var body: some View {
        DisclosureGroup(title) {
            Text(text)
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
    }
}

// MARK: - WP2 bước 2: dấu phiên bản bộ đọc (ACCOUNTING-SPEC F4, mức tối thiểu)
//
// Mọi hoá đơn lưu qua ReviewView.save() đều đóng dấu này vào
// Receipt.parserVersion, để sau này biết bản ghi nào do bộ đọc nào sinh ra
// khi đối chiếu lỗi đọc. Giá trị hiện tại = bộ đọc Build 1 (ReceiptParser
// chưa đổi ở WP2); WP4 (thi đấu engine) thắng/thua xong thì cập nhật
// hằng này cùng lúc thay engine — không sửa ngược bản ghi cũ.
//
// REPARSE (2026-11-10): hằng này THỰC SỰ được nâng lần đầu — các engine
// WP4/WP5/M1-FIX đã thay nhau trên main mà dấu vẫn nằm ở "build1-parser"
// (nợ ghi nhận ở cổng WP5), nên MỌI bản ghi hiện có (kể cả bản ghi do
// bản M1 lưu) đều mang dấu cũ hoặc rỗng. Giá trị mới "m1fix-reparse-1"
// là mã duy nhất của thế hệ bộ đọc WP5 + M1-FIX + điểm vào reparse;
// nút "Đọc lại" ở màn Chi Tiết dùng phép so parserVersion != hằng này
// (cộng điều kiện status == needsReview) để nhận diện tờ "cũ". Đọc lại
// một tờ đã mang dấu hiện hành cho kết quả số y hệt (cùng bộ đọc) —
// phép so chỉ quyết định nút có hiện hay không, không đổi số.

// IMGFIX (2026-11-10): từ bản này, hằng này là DẤU BẢN BUILD trong app —
// mỗi bản giao cho anh mang một mã duy nhất, in ngay trong màn Chi Tiết
// (dòng "Bản bộ đọc của app") để ảnh chụp tự khai đang chạy bản nào.
// IMGFIX = "m1fix-reparse-3".
//
// SCANPRO (2026-11-10): cộng nút chụp lại bản gốc bằng máy quét tài
// liệu (VNDocumentCamera) ngay trong màn Chi Tiết — mã mới
// "m1fix-reparse-4".
//
// INTEGRATE-V2 (2026-11-11): đưa kết quả chấm lại buổi đo vào app
// chính — mặt trước quay về đọc đơn kiểu A0/OCRFIX, Parser cộng
// nhánh trích món cùng-dòng + vá tầng totals/ngày (xem Parser.swift).
// Mã mới "core-v2-1". Gói này KHÔNG đổi gì ở file này ngoài dấu bản:
// nút Đọc lại, mục Ảnh gốc và nút Chụp lại bản gốc giữ nguyên.
//
// CORE-V3 (Pha 4): tem lấy từ NGUỒN DUY NHẤT ReadCoreVersion trong
// ReadPipeline.swift — cùng giá trị được ghi vào hồ sơ chẩn đoán
// v2 (identity.parserVersion) của mọi lần đọc, nên tem trong app
// và tem trong hồ sơ không thể lệch nhau. Mã "core-v3-1".

let currentParserVersion = ReadCoreVersion.parserVersion

// MARK: - WP5 bước 3: nhãn nguồn tên tiệm (WP5-SPEC mục 3/4)
//
// ParseResult.vendorSource là mã máy của identifyVendor ("tier1-exact" |
// "tier1-fuzzy" | "tier2-anchor"); màn Kiểm Lại dịch ra chữ cho anh biết
// tên tiệm đến từ bằng chứng nào. Giá trị lạ/không có -> nil (không hiện
// nhãn bịa). Chỉ hiển thị — không nơi nào ghi nhãn này xuống model (model
// WP2 không có trường nguồn tiệm; độ tin cậy đã nằm ở vendorConfidence
// và kỷ luật Hộp Chờ đi qua warnings như cũ).

func vendorSourceText(_ source: String?) -> String? {
    switch source {
    case "tier1-exact":
        return "Nguồn tên tiệm: khớp tên in trên hoá đơn."
    case "tier1-fuzzy":
        return "Nguồn tên tiệm: khớp mờ tên in trên hoá đơn — anh kiểm tra giúp."
    case "tier2-anchor":
        return "Nguồn tên tiệm: nhận qua địa chỉ/số điện thoại — anh kiểm tra giúp."
    default:
        return nil
    }
}

/// V3 (Pha 4): chú thích provenance một trường cho tầng hiển thị —
/// trả nil cho "đọc thẳng" (không cần nói), còn lại nói rõ số đó
/// đến từ đâu để anh cân nhắc khi duyệt (luật §3.7: số suy luận
/// không bao giờ trông giống hệt số đọc thẳng).
func provenanceCaption(_ provenance: FieldProvenance) -> String? {
    switch provenance.kind {
    case "read":
        return nil
    case "inferred":
        return "Số này do đối chiếu số học suy ra (kênh \(provenance.detail ?? "?")) — anh kiểm tra giúp."
    case "roiRecovered":
        return "Số này khôi phục nhờ đọc lại vùng ảnh (vòng \(provenance.detail ?? "?"))."
    case "domainCorrected":
        return "Chữ đã sửa theo từ điển lĩnh vực (bản \(provenance.detail ?? "?")) — chỉ sửa chữ, không sửa số."
    case "anchored":
        return "Số này là neo số học của tờ."
    default:
        return "Nguồn gốc số: \(provenance.kind)."
    }
}

/// (missingPurposeFlagText đã chuyển sang ReceiptLogic.swift ở
/// gói G1 — cùng module nên điểm dùng ở dưới không đổi.)

/// L-2026-11-13-21 — SỬA DỨT KHOÁT theo lệnh anh ("Sao phải
/// ghi chữ khi hệ thống cho chọn rồi"): mục đích business là
/// DANH SÁCH CHỌN có sẵn — chọn một mục là trường được điền,
/// cờ tự tắt sau khi lưu; "Tự ghi…" chỉ dành cho ca lạ. Giá
/// trị lưu vẫn là businessPurpose nguyên văn (KHÔNG đổi
/// model dữ liệu): chọn mục nào thì câu đó là mục đích.
struct BusinessPurposeField: View {
    @Binding var text: String

    static let options = [
        "Mua cho khách trong tiệm",
        "Mua cho nhân viên trong tiệm",
        "Mua cho khách và nhân viên",
        "Dùng cho hoạt động của tiệm",
        "Mua nguyên liệu, hàng hoá cho tiệm",
    ]

    @State private var customMode = false

    private var selection: Binding<String> {
        Binding(
            get: {
                if customMode { return "__custom__" }
                if text.isEmpty { return "" }
                if Self.options.contains(text) { return text }
                return "__custom__"
            },
            set: { newValue in
                if newValue == "__custom__" {
                    customMode = true
                } else {
                    customMode = false
                    text = newValue
                }
            })
    }

    var body: some View {
        Picker("Mục đích business", selection: selection) {
            Text("— Chọn mục đích —").tag("")
            ForEach(Self.options, id: \.self) { option in
                Text(option).tag(option)
            }
            Text("Tự ghi…").tag("__custom__")
        }
        if selection.wrappedValue == "__custom__" {
            TextField("Mục đích business (mua để làm gì)",
                      text: $text, axis: .vertical)
        }
    }
}

// MARK: - Cờ kiểm tra lại trên 1 hoá đơn đã lưu (chỉ hiển thị, không sửa số)

/// IMGFIX: tờ còn file ảnh gốc nào tải được trong kho bằng chứng không.
/// Bằng chứng gộp cả imageFileName (Build 1) lẫn originalImageFileNames
/// (WP2/WP3 — vd file PDF nguyên byte) qua allOriginalImageFileNames:
/// chỉ cần MỘT file còn tải được là bằng chứng còn. ImageStore.load với
/// tên .pdf tự render trang 1 nên PDF gốc cũng tính là còn bằng chứng.
///
/// G1: thân logic "chỉ cần một file tải được" đã tách sang
/// ReceiptLogic.hasLoadableOriginal (ReceiptLogic.swift, thuần
/// Foundation) để harness kiểm bằng Swift thật; hàm này chỉ còn
/// là tầng bọc cấp hàm nạp thật của app.
func receiptHasOriginalImage(_ receipt: Receipt) -> Bool {
    ReceiptLogic.hasLoadableOriginal(
        fileNames: receipt.allOriginalImageFileNames,
        isLoadable: { ImageStore.load(fileName: $0) != nil })
}

/// G1: thân bộ cờ đã tách sang ReceiptLogic.flags (ReceiptLogic
/// .swift, thuần Foundation, harness kiểm bằng Swift thật). Tầng
/// bọc này trích đúng các trường bản gốc đã đọc: subtotalCents,
/// amountCents từng dòng, totalCents, taxCents (KHÔNG đổi sang
/// taxTotalCents), classification, businessPurpose, và kết quả
/// receiptHasOriginalImage — thứ tự sinh cờ giữ nguyên ở tầng
/// thuần.
func receiptFlags(_ receipt: Receipt) -> [String] {
    let kind: ReceiptKindTag
    switch receipt.classification {
    case .personal: kind = .personal
    case .business: kind = .business
    case .unknown: kind = .unknown
    }
    return ReceiptLogic.flags(for: ReceiptFlagInput(
        subtotalCents: receipt.subtotalCents,
        itemAmountCents: receipt.items.map { $0.amountCents },
        totalCents: receipt.totalCents,
        taxCents: receipt.taxCents,
        kind: kind,
        businessPurpose: receipt.businessPurpose,
        hasOriginalImage: receiptHasOriginalImage(receipt),
        // P2-0 mục 19: màn đã lưu luôn CÓ tên tiệm để phán.
        vendor: receipt.vendor))
}

/// P2-0 (C-7/C-8): suy lại trạng thái duyệt từ bộ cờ trên số
/// ĐÃ LƯU hiện tại của tờ — cờ trống -> .reviewed (đóng dấu
/// reviewedAt khi tờ CHUYỂN sang đã duyệt), còn cờ ->
/// .needsReview. Mọi đường sửa bản ghi đã lưu (Lưu thay đổi
/// ở Chi Tiết, xếp lại theo thẻ) đi qua đây thay vì giữ
/// nguyên trạng thái cũ bất chấp số mới.
func refreshReceiptStatusFromFlags(_ receipt: Receipt) {
    let wasReviewed = receipt.status == .reviewed
    receipt.status = receiptFlags(receipt).isEmpty ? .reviewed : .needsReview
    if receipt.status == .reviewed && !wasReviewed {
        receipt.reviewedAt = Date()
    }
}

/// P2-0/C-1 (sửa bởi L-2026-11-18-32): cờ LỆCH SỐ HỌC
/// (V1/V2). G1: thân phân lớp đã tách sang ReceiptLogic
/// (thuần Foundation, harness kiểm bằng Swift thật); hàm này
/// chỉ còn là tầng bọc mỏng giữ tên cũ cho tầng view. Hành vi
/// CỔNG duyệt theo lớp cờ nay do ReceiptLogic.approvalGate
/// quyết: từ L-32, cờ thiếu trường (thiếu tổng / chưa rõ
/// tiệm / thiếu mục đích / chưa phân loại) KHÔNG còn chặn
/// nút duyệt — đi đường duyệt-kèm-cờ như V1/V2; chỉ cờ thiếu
/// ảnh gốc còn giữ khoá kèm đường gỡ tại nút.
func isArithmeticDiscrepancyFlag(_ flag: String) -> Bool {
    ReceiptLogic.isArithmeticDiscrepancyFlag(flag)
}

// MARK: - Dòng hoá đơn trong danh sách

struct ReceiptRowView: View {
    var receipt: Receipt
    /// P2-0 (mục nối duplicateOf): true khi có tờ khác đang
    /// trỏ duplicateOfStableID vào tờ này (tờ này là bản GỐC
    /// của ít nhất một bản trùng). Nơi gọi tính từ toàn sổ.
    var hasDuplicates: Bool = false

    var body: some View {
        // UI-2026-11-13: hàng chuẩn DesignSystem — thumbnail bo
        // 10 + viền tóc; không có ảnh thì monogram tiệm (màu ổn
        // định theo tên); "Chờ duyệt" thành chip trạng thái.
        HStack(spacing: DS.spaceM) {
            // OPT-1 (audit #1): ảnh nhỏ đã thu cho ô 46×58 thay vì
            // giải mã cả ảnh gốc mỗi dòng — hình hiển thị không đổi.
            if let firstOriginal = receipt.allOriginalImageFileNames.first,
               let image = ImageStore.loadThumbnail(fileName: firstOriginal) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 46, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: DS.radiusThumb))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.radiusThumb)
                            .strokeBorder(DS.cardStroke, lineWidth: 1)
                    )
            } else {
                VendorMonogram(vendor: receipt.vendor.isEmpty ? "?" : receipt.vendor, size: 46)
                    .frame(width: 46, height: 58)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(receipt.vendor.isEmpty ? "(Chưa rõ tiệm)" : receipt.vendor)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(receipt.date, format: .dateTime.day().month().year())
                    if !receipt.category.isEmpty {
                        Text("·")
                        Text(receipt.category)
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ClassificationBadge(kind: receipt.classification, cardLast4: receipt.cardLast4)
                    if receipt.status == .needsReview {
                        StatusChip(text: "CHỜ DUYỆT", color: DS.warning)
                    }
                    // P2-0 (mục nối duplicateOf): bản trùng
                    // hiện dấu riêng, KHÔNG chỉ im lặng biến
                    // khỏi tổng.
                    if receipt.duplicateOfStableID != nil {
                        StatusChip(text: "TRÙNG — LOẠI KHỎI TỔNG", color: .gray)
                    } else if hasDuplicates {
                        StatusChip(text: "CÓ BẢN TRÙNG", color: .gray)
                    }
                }
            }
            Spacer()
            MoneyAmount(cents: receipt.totalCents)
        }
        .padding(.vertical, DS.spaceXS)
    }
}

// MARK: - Danh sách hoá đơn (gom theo tháng, có tổng chạy theo bộ lọc)

struct ReceiptListView: View {
    var onlyNeedsReview: Bool = false

    @Query(sort: \Receipt.date, order: .reverse) private var receipts: [Receipt]
    @State private var searchText = ""
    @State private var kindFilter: Classification? = nil

    private var filtered: [Receipt] {
        receipts.filter { receipt in
            if onlyNeedsReview && receipt.status != .needsReview { return false }
            if let kindFilter, receipt.classification != kindFilter { return false }
            if !searchText.isEmpty {
                let needle = searchText.lowercased()
                let inVendor = receipt.vendor.lowercased().contains(needle)
                let inCategory = receipt.category.lowercased().contains(needle)
                let inItems = receipt.items.contains { $0.name.lowercased().contains(needle) }
                let inText = receipt.ocrRawText.lowercased().contains(needle)
                if !(inVendor || inCategory || inItems || inText) { return false }
            }
            return true
        }
    }

    /// OPT-1 (audit #3): nhận tập đã lọc từ body thay vì tự gọi lại
    /// `filtered` — thân gom nhóm giữ nguyên.
    private func monthGroups(_ filtered: [Receipt]) -> [(key: String, title: String, items: [Receipt])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filtered) { receipt -> DateComponents in
            calendar.dateComponents([.year, .month], from: receipt.date)
        }
        return grouped.keys
            .sorted { a, b in
                if (a.year ?? 0) != (b.year ?? 0) { return (a.year ?? 0) > (b.year ?? 0) }
                return (a.month ?? 0) > (b.month ?? 0)
            }
            .map { comps in
                let items = (grouped[comps] ?? []).sorted { $0.date > $1.date }
                let title = "Tháng \(comps.month ?? 0)/\(comps.year ?? 0)"
                let key = "\(comps.year ?? 0)-\(comps.month ?? 0)"
                return (key: key, title: title, items: items)
            }
    }

    /// P2-0/C-2: tổng CHÍNH THỨC = chỉ tờ đã duyệt và không
    /// bị loại khỏi tổng (bản trùng), tính theo số ĐÃ TRẢ
    /// (tổng in + tip). Trước gói này tổng chạy tính cả tờ
    /// đang chờ duyệt và dùng totalCents trơn.
    private func sum(of kind: Classification, in items: [Receipt]) -> Int {
        items.filter {
            $0.classification == kind && $0.status == .reviewed
                && !$0.excludedFromTotals
        }.reduce(0) { $0 + ($1.amountPaidCents ?? 0) }
    }

    /// P2-0/C-2: tiền đang CHỜ duyệt (mọi loại) — hiện riêng
    /// một dòng minh bạch, không trộn vào tổng chính thức.
    private func pendingSum(in items: [Receipt]) -> Int {
        items.filter {
            $0.status == .needsReview && !$0.excludedFromTotals
        }.reduce(0) { $0 + ($1.amountPaidCents ?? 0) }
    }

    /// P2-0 (mục nối duplicateOf): tập stableID đang bị ít
    /// nhất một bản trùng trỏ vào — hàng gốc hiện chip
    /// "CÓ BẢN TRÙNG".
    private var duplicateTargetIDs: Set<String> {
        Set(receipts.compactMap { $0.duplicateOfStableID })
    }

    var body: some View {
        // OPT-1 (audit #3): tính bộ lọc và tập bản-trùng MỘT lần mỗi
        // lần vẽ. Bản trước gọi `filtered` 9 lần trong thân (mỗi lần
        // hạ chữ thường toàn bộ ocrRawText khi đang tìm) và dựng lại
        // `duplicateTargetIDs` cho TỪNG dòng. Cùng đầu vào, cùng
        // điều kiện, cùng hàm cộng — số hiển thị không đổi.
        let filtered = self.filtered
        let duplicateTargetIDs = self.duplicateTargetIDs
        NavigationStack {
            List {
                // Running total của đúng tập đang lọc/tìm (chuẩn Copilot Money).
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tổng \(filtered.count) hoá đơn đang hiện")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 14) {
                            Label(formatMoney(cents: sum(of: .personal, in: filtered)), systemImage: "person.fill")
                                .foregroundStyle(Theme.personalColor)
                            Label(formatMoney(cents: sum(of: .business, in: filtered)), systemImage: "briefcase.fill")
                                .foregroundStyle(Theme.businessColor)
                        }
                        .font(.callout.weight(.semibold))
                        .monospacedDigit()
                        if sum(of: .unknown, in: filtered) != 0 {
                            Text("Chưa rõ: \(formatMoney(cents: sum(of: .unknown, in: filtered)))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if pendingSum(in: filtered) != 0 {
                            Text("Đang chờ duyệt: \(formatMoney(cents: pendingSum(in: filtered))) — chưa tính vào tổng chính thức ở trên")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                ForEach(monthGroups(filtered), id: \.key) { group in
                    Section {
                        ForEach(group.items) { receipt in
                            NavigationLink {
                                ReceiptDetailView(receipt: receipt)
                            } label: {
                                ReceiptRowView(
                                    receipt: receipt,
                                    hasDuplicates: !receipt.stableID.isEmpty
                                        && duplicateTargetIDs.contains(receipt.stableID))
                            }
                        }
                    } header: {
                        HStack {
                            Text(group.title)
                            Spacer()
                            Text("\(formatMoney(cents: sum(of: .personal, in: group.items))) · \(formatMoney(cents: sum(of: .business, in: group.items)))")
                                .monospacedDigit()
                        }
                    }
                }
            }
            .overlay {
                if filtered.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: onlyNeedsReview ? "checkmark.circle" : "doc.text.magnifyingglass")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text(onlyNeedsReview ? "Đã phân loại xong hết ✓" : "Chưa có hoá đơn nào khớp")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(onlyNeedsReview ? "Hộp Chờ Duyệt" : "Hoá Đơn")
            .dsListBackground()
            .searchable(text: $searchText, prompt: "Tìm tiệm, món, mục…")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Tất cả") { kindFilter = nil }
                        Button("Cá nhân") { kindFilter = .personal }
                        Button("Business") { kindFilter = .business }
                        Button("Chưa rõ") { kindFilter = .unknown }
                    } label: {
                        Label("Lọc", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
    }
}

// MARK: - Lưu SwiftData trung thực (N2-FIX, FULL-REVIEW 2026-11-12)

/// Lưu context và trả kết quả THẬT: true = đã lưu xuống máy.
/// false = lỗi — caller PHẢI báo cho anh và KHÔNG đi tiếp đường
/// thành công (không đóng màn, không hiện "Đã lưu ✓", không xoá
/// file, không gắn cờ đã duyệt). Luật cứng sau FULL-REVIEW:
/// mọi điểm lưu trong tầng app đi qua hàm này hoặc do/catch
/// tường minh — cấm quay lại `try?` nuốt lỗi lưu.
func saveContextOrFalse(_ context: ModelContext) -> Bool {
    do { try context.save(); return true } catch { return false }
}

// MARK: - Chi tiết hoá đơn

struct ReceiptDetailView: View {
    var receipt: Receipt

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    // REPARSE: cần danh sách đuôi thẻ để áp gợi ý phân loại đúng như
    // ReviewView.save() khi tờ CHƯA từng có quyết định phân loại.
    @Query private var cardTails: [CardTail]
    // P2-0 (mục nối duplicateOf): toàn sổ để hiển thị quan hệ
    // trùng của tờ này (bản gốc của nó / các bản trùng của nó).
    @Query private var allReceipts: [Receipt]
    /// P2-0/C-1 (mở rộng bởi L-2026-11-18-32): hộp xác nhận
    /// "duyệt kèm cờ" — nay phủ mọi lớp cờ trừ thiếu ảnh gốc;
    /// pendingConfirmFlags chụp đúng bộ cờ lúc bấm để hộp nêu
    /// rõ từng cờ anh đang xác nhận.
    @State private var showConfirmWithFlag = false
    @State private var pendingConfirmFlags: [String] = []
    @State private var selectedKind: Classification
    @State private var selectedCategory: String
    @State private var purposeText: String
    /// L-2026-11-18-32: tên tiệm sửa tay ngay trong Chi Tiết
    /// — trước gói này Chi Tiết KHÔNG có ô sửa tiệm nào (mục
    /// "Thông tin" chỉ hiện chữ), nên cờ "Chưa rõ tiệm" không
    /// đường nào tự gỡ được trong màn này.
    @State private var vendorText: String
    @State private var showDeleteConfirm = false
    @State private var savedNote = false
    /// N2-FIX: lỗi lưu gần nhất ở màn này (nil = không lỗi) —
    /// hiện chữ đỏ trong form, thay cho việc nuốt lỗi lặng lẽ.
    @State private var saveError: String? = nil
    @State private var reparsedNote = false
    /// V3 (Pha 4): hồ sơ chẩn đoán v2 tải theo yêu cầu (nút trong
    /// mục "Chẩn đoán lần đọc") — không đọc file ở mọi lần vẽ.
    @State private var loadedDiagnostics: ReadDiagnostics? = nil
    @State private var diagnosticsMissing = false
    // IMGFIX: gắn lại ảnh gốc cho tờ bị mất file bằng chứng (mục "Ảnh
    // gốc" chỉ hiện khi tờ không còn file gốc nào tải được).
    @State private var showReattachPicker = false
    @State private var reattachPickerItem: PhotosPickerItem? = nil
    @State private var reattachError: String? = nil
    // SCANPRO: chụp lại bản gốc bằng máy quét tài liệu ngay tại màn
    // Chi Tiết — dùng cho cả tờ đã có ảnh (muốn bản quét phẳng, rõ
    // chữ hơn) lẫn tờ đang thiếu ảnh (nút nằm cạnh 2 nút gắn lại).
    @State private var showRescanCamera = false
    @State private var rescanError: String? = nil

    init(receipt: Receipt) {
        self.receipt = receipt
        _selectedKind = State(initialValue: receipt.classification)
        _selectedCategory = State(initialValue: receipt.category)
        _purposeText = State(initialValue: receipt.businessPurpose)
        _vendorText = State(initialValue: receipt.vendor)
    }

    private var categoryOptions: [String] {
        var options = Categories.list(for: selectedKind)
        if !selectedCategory.isEmpty && !options.contains(selectedCategory) {
            options.append(selectedCategory)
        }
        return options
    }

    // REPARSE: nút "Đọc lại" hiện khi tờ còn văn bản thô đã lưu —
    // cổng thế hệ/trạng thái cũ đã gỡ (L-2026-11-13-17, xem
    // canReparse).
    // SCANPRO: máy ảo / máy không có camera quét tài liệu thì nút
    // chụp lại bị khoá (đúng luật ScanView đang áp ở tab CHỤP).
    private var documentCameraSupported: Bool {
        VNDocumentCameraViewController.isSupported
    }

    /// P2-0 (mục nối duplicateOf): tờ GỐC mà tờ này là bản
    /// trùng của nó (nil khi tờ này không phải bản trùng hoặc
    /// bản gốc đã bị xoá).
    private var duplicateOriginal: Receipt? {
        guard let target = receipt.duplicateOfStableID, !target.isEmpty
        else { return nil }
        return allReceipts.first { $0.stableID == target }
    }

    /// P2-0 (mục nối duplicateOf): các bản trùng đang trỏ
    /// vào tờ này.
    private var duplicateCopies: [Receipt] {
        guard !receipt.stableID.isEmpty else { return [] }
        return allReceipts.filter {
            $0.duplicateOfStableID == receipt.stableID
                && $0.stableID != receipt.stableID
        }
    }

    private var canReparse: Bool {
        // L-2026-11-13-17: cổng cũ (dấu bộ đọc khác bản hiện hành
        // HOẶC còn ở Hộp Chờ) là di sản thời di trú một lần — tờ
        // đã duyệt + dấu hiện hành thì nút biến mất, hoá ra "Đọc
        // lại chỉ bấm được 1 lần" (anh báo 2026-11-13). Đọc lại
        // nay là đường sửa số đứng (Điều 2 B2): còn văn bản đã
        // lưu là còn bấm được, không cổng thế hệ/trạng thái nữa.
        // G1: điều kiện thuần đã tách sang ReceiptLogic.canReparse
        // để harness kiểm bằng Swift thật (khoá ca L-17).
        ReceiptLogic.canReparse(ocrRawText: receipt.ocrRawText)
    }

    var body: some View {
        List {
            // UI-2026-11-13: thẻ hero đầu màn Chi Tiết (chuẩn app
            // tài chính top: monogram tiệm + TỔNG thật lớn + chip
            // trạng thái). Thuần hiển thị, cộng thêm — không đụng
            // bất kỳ mục chức năng nào bên dưới.
            Section {
                VStack(spacing: DS.spaceM) {
                    // PASS 2 (mẫu anh duyệt 2026-11-13): có ảnh gốc
                    // thì dải ảnh phủ đầu trang — tên tiệm + ngày +
                    // TỔNG đặt trên dải tối cuối ảnh (đúng mẫu);
                    // chạm vào ảnh ở mục "Ảnh gốc" bên dưới để xem
                    // toàn màn hình. Không tải được ảnh nào thì
                    // quay về khối monogram của pass 1.
                    if let firstOriginal = receipt.allOriginalImageFileNames.first,
                       let image = ImageStore.load(fileName: firstOriginal) {
                        ZStack(alignment: .bottomLeading) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 190)
                                .frame(maxWidth: .infinity)
                                .clipped()
                            LinearGradient(colors: [Color.clear, Color.black.opacity(0.85)],
                                           startPoint: .center, endPoint: .bottom)
                            HStack(alignment: .bottom, spacing: DS.spaceM) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(receipt.vendor.isEmpty ? "(Chưa rõ tiệm)" : receipt.vendor)
                                        .font(.title3.weight(.bold))
                                        .foregroundStyle(.white)
                                        .lineLimit(2)
                                    Text(receipt.date, format: .dateTime.weekday().day().month().year().hour().minute())
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.85))
                                }
                                Spacer()
                                Text(formatMoney(optionalCents: receipt.totalCents))
                                    .font(.system(size: 26, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .monospacedDigit()
                            }
                            .padding(DS.spaceL)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    } else {
                        VStack(spacing: DS.spaceS) {
                            VendorMonogram(vendor: receipt.vendor.isEmpty ? "?" : receipt.vendor, size: 56)
                            Text(receipt.vendor.isEmpty ? "(Chưa rõ tiệm)" : receipt.vendor)
                                .font(.title3.weight(.bold))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                            Text(receipt.date, format: .dateTime.weekday().day().month().year().hour().minute())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(formatMoney(optionalCents: receipt.totalCents))
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .padding(.top, 2)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    HStack(spacing: 6) {
                        ClassificationBadge(kind: receipt.classification, cardLast4: receipt.cardLast4)
                        if receipt.status == .needsReview {
                            StatusChip(text: "CHỜ DUYỆT", color: DS.warning)
                        } else {
                            StatusChip(text: "ĐÃ DUYỆT", color: DS.brand)
                        }
                        if receipt.totalConfidence > 0 {
                            StatusChip(text: "ĐỘ TIN CẬY \(Int((receipt.totalConfidence * 100).rounded()))%", color: DS.brand)
                        }
                    }
                }
                .padding(.vertical, DS.spaceS)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
            .listRowBackground(Color.clear)

            if let firstOriginal = receipt.allOriginalImageFileNames.first,
               let image = ImageStore.load(fileName: firstOriginal) {
                Section("Ảnh gốc (bằng chứng)") {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 320)
                        .frame(maxWidth: .infinity)
                    // SCANPRO: tờ giấy còn trong tay thì chụp lại thành
                    // bản quét phẳng, tương phản cao, rõ chữ (như máy
                    // scan chuyên nghiệp) ngay tại đây — thay cho ảnh
                    // đang hiển thị. File cũ không bị xoá: nó lùi vào
                    // originalImageFileNames giữ dấu vết bằng chứng
                    // (xem applyRescannedOriginal).
                    Button {
                        rescanError = nil
                        showRescanCamera = true
                    } label: {
                        Label("Chụp lại bản gốc (quét như máy scan)", systemImage: "doc.viewfinder")
                    }
                    .disabled(!documentCameraSupported)
                    Text("Chụp lại chỉ thay ẢNH bằng chứng — số liệu của tờ giữ nguyên (muốn đọc lại số, anh dùng nút Đọc lại ở mục Bộ đọc).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !documentCameraSupported {
                        Text("Máy này không hỗ trợ quét tài liệu (thường là máy ảo) — anh dùng các nút gắn lại ảnh có sẵn.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let rescanError {
                        Text(rescanError)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
            } else if !receiptHasOriginalImage(receipt) {
                // IMGFIX: trước đây thiếu ảnh là app IM LẶNG (không mục
                // ảnh, không cờ). Nay hiện mục gắn lại tại đúng vị trí
                // của mục ảnh, kèm cờ trong "Cần kiểm lại" (receiptFlags).
                // Điều kiện dùng receiptHasOriginalImage (mọi file gốc
                // đều không tải được) — không chỉ imageFileName — để tờ
                // còn PDF gốc trong originalImageFileNames không bị báo
                // thiếu oan. Gắn xong, imageFileName tải được -> thân
                // màn tự vẽ lại thành mục "Ảnh gốc (bằng chứng)".
                Section("Ảnh gốc") {
                    Text("Tờ này đang thiếu file ảnh gốc. Hoá đơn cần ảnh gốc làm bằng chứng (để trình accountant) — anh gắn lại ảnh chụp / file tải về của đúng tờ này:")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button {
                        reattachError = nil
                        showReattachPicker = true
                    } label: {
                        Label("Gắn lại ảnh gốc từ thư viện ảnh", systemImage: "photo.on.rectangle.angled")
                    }
                    Button {
                        reattachError = nil
                        // L-2026-11-20-45: trình picker bằng
                        // UIKit thuần ở chế độ SAO CHÉP qua
                        // ReceiptFilePickerPresenter (dùng chung
                        // với tab CHỤP) — .fileImporter của
                        // SwiftUI (mở tại chỗ) chết ở nút Open
                        // trên bản ký lại KravaSigner y hệt nút
                        // nạp file ở ScanView (L-2026-11-20-43).
                        DiagLog.log(.app, "GẮN LẠI: mở bộ chọn file gắn lại ảnh gốc")
                        ReceiptFilePickerPresenter.present(
                            onPick: { urls in
                                if let url = urls.first {
                                    DiagLog.log(.app, "GẮN LẠI: đã chọn file \(url.lastPathComponent)")
                                    attachReattachedFile(url: url)
                                }
                            },
                            onCancel: {
                                // Huỷ chọn: giữ nguyên hành vi
                                // cũ của .fileImporter — không
                                // báo lỗi, không đổi trạng thái
                                // (lượt chọn đã có dòng log
                                // "NẠP FILE:" ở presenter).
                            },
                            onFailure: { error in
                                reattachError = "Không nạp được file: \(error.localizedDescription)"
                            },
                            allowsMultiple: false)
                    } label: {
                        Label("Gắn lại từ Files (ảnh / PDF)", systemImage: "folder")
                    }
                    // SCANPRO: tờ giấy còn trong tay thì chụp lại ngay
                    // bằng máy quét tài liệu — bản quét phẳng, rõ chữ
                    // thành file gốc mới, cờ "Thiếu ảnh gốc" tự mất.
                    Button {
                        rescanError = nil
                        showRescanCamera = true
                    } label: {
                        Label("Chụp lại bản gốc (quét như máy scan)", systemImage: "doc.viewfinder")
                    }
                    .disabled(!documentCameraSupported)
                    if let rescanError {
                        Text(rescanError)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                    if let reattachError {
                        Text(reattachError)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
            }

            // S2: bản scan phẳng (sản phẩm phụ của lần chụp/quét —
            // xem FlatScan) hiển thị để xem cho rõ chữ; ảnh gốc
            // phía trên vẫn là bằng chứng của tờ, không thay thế.
            if let flatImage = FlatScan.loadFlatImage(
                forOriginal: receipt.imageFileName) {
                Section("Bản scan phẳng") {
                    Image(uiImage: flatImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 320)
                        .frame(maxWidth: .infinity)
                    Text("Bản này do app làm phẳng từ ảnh gốc khi chụp — để xem cho rõ chữ. Ảnh gốc phía trên vẫn là bằng chứng của tờ.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Thông tin") {
                LabeledContent("Tiệm", value: receipt.vendor.isEmpty ? "—" : receipt.vendor)
                // WP5 bước 3: bằng chứng liên hệ tiệm ĐÃ LƯU (model WP2) —
                // chỉ hiện khi có dữ liệu; bản ghi cũ (trước WP5) để trống
                // nên không đổi hành vi hiển thị.
                if !receipt.vendorAddress.isEmpty {
                    LabeledContent("Địa chỉ tiệm", value: receipt.vendorAddress)
                }
                if let phone = receipt.vendorPhone {
                    LabeledContent("Điện thoại tiệm", value: phone)
                }
                if let store = receipt.storeNumber {
                    LabeledContent("Mã cửa hàng", value: store)
                }
                LabeledContent("Ngày") {
                    Text(receipt.date, format: .dateTime.day().month().year().hour().minute())
                }
                LabeledContent("Subtotal") { moneyText(receipt.subtotalCents) }
                // WP2 bước 2: có dòng thuế riêng (taxLines) thì hiện TỪNG dòng
                // như in trên giấy (nhãn + thuế suất) + dòng tổng thuế lấy từ
                // helper taxTotalCents; chưa có thì giữ nguyên dòng thuế gộp
                // của Build 1 (bản ghi cũ không đổi hành vi hiển thị).
                if receipt.taxLines.isEmpty {
                    LabeledContent("Thuế") { moneyText(receipt.taxCents) }
                } else {
                    ForEach(receipt.taxLines.sorted { $0.sortIndex < $1.sortIndex }) { line in
                        LabeledContent(line.label + (line.rateText.map { " (\($0)%)" } ?? "")) {
                            moneyText(line.amountCents)
                        }
                    }
                    LabeledContent("Thuế (tổng)") { moneyText(receipt.taxTotalCents) }
                }
                LabeledContent("TỔNG") { moneyText(receipt.totalCents).bold() }
                // P2-0/C-9: tờ có tip thì TỔNG trên là tổng IN
                // trên giấy; số đã trả thật = tổng in + tip.
                if let tip = receipt.tipAmountCents {
                    LabeledContent("Tip") { moneyText(tip) }
                    LabeledContent("Đã trả (tổng in + tip)") {
                        moneyText(receipt.amountPaidCents).bold()
                    }
                }
                // P2-0 mục 18 (F4): độ tin cậy tiệm/ngày hiện
                // cạnh các trường (độ tin cậy TỔNG đã có chip ở
                // thẻ hero) — 0 nghĩa là không có bằng chứng
                // chấm điểm thì không hiện.
                if receipt.vendorConfidence > 0 {
                    LabeledContent("Độ tin cậy tiệm",
                                   value: "\(Int((receipt.vendorConfidence * 100).rounded()))%")
                }
                if receipt.dateConfidence > 0 {
                    LabeledContent("Độ tin cậy ngày",
                                   value: "\(Int((receipt.dateConfidence * 100).rounded()))%")
                }
                if let last4 = receipt.cardLast4 {
                    LabeledContent("Thẻ", value: "\(receipt.cardBrand ?? "Thẻ") •• \(last4)")
                }
                if let key = receipt.dedupeKey {
                    LabeledContent("Mã chống trùng") {
                        Text(key).font(.caption).foregroundStyle(.secondary)
                    }
                }
                // P2-0 (mục nối duplicateOf): quan hệ trùng
                // hiện rõ ở Chi Tiết, hai chiều.
                if let original = duplicateOriginal {
                    LabeledContent("Bản trùng của tờ") {
                        Text("\(original.vendor.isEmpty ? "(Chưa rõ tiệm)" : original.vendor) — \(original.date.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                    }
                    LabeledContent("Tính vào tổng", value: "Không — đã loại khỏi tổng")
                }
                if !duplicateCopies.isEmpty {
                    LabeledContent("Bản trùng của tờ này",
                                   value: "\(duplicateCopies.count) bản — đã loại khỏi tổng")
                }
                LabeledContent("Bản bộ đọc của app") {
                    Text(currentParserVersion).font(.caption).foregroundStyle(.secondary)
                }
            }

            // REPARSE: đọc lại tờ cũ bằng bộ đọc hiện hành, cập nhật số
            // TẠI CHỖ trên chính bản ghi này (xem reparseReceipt()).
            if canReparse {
                Section("Bộ đọc") {
                    Button { reparseReceipt() } label: {
                        Label("Đọc lại bằng bộ đọc hiện tại", systemImage: "arrow.clockwise")
                    }
                    Text("Tờ này do \(receipt.parserVersion.isEmpty ? "bộ đọc đời đầu" : "bộ đọc \(receipt.parserVersion)") sinh ra; bộ đọc hiện tại là \(currentParserVersion). Đọc lại chạy bộ đọc hiện tại trên văn bản đã lưu và cập nhật số tại chỗ. Phân loại anh đã chọn và ghi chú mục đích được giữ nguyên.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if reparsedNote {
                        Text("Đã đọc lại ✓ — số đã cập nhật theo bộ đọc hiện tại")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }

            // V3 (Pha 4, M12): hồ sơ chẩn đoán v2 của lần đọc gần
            // nhất sinh ra tờ này (file phụ cạnh ảnh gốc). Tải theo
            // yêu cầu; tờ đọc trước bản v3 thì chưa có hồ sơ — ghi
            // rõ như vậy, không dựng hồ sơ ngược từ số đã lưu.
            Section("Chẩn đoán lần đọc") {
                if let diag = loadedDiagnostics {
                    LabeledContent("Bộ đọc sinh hồ sơ") {
                        Text(diag.identity.parserVersion)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    LabeledContent("Nguồn nạp", value: diag.input.source)
                    LabeledContent("Engine") {
                        Text("\(diag.config.engineManifest.family) \(diag.config.engineManifest.revision)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    LabeledContent("Ứng viên thắng") {
                        Text(diag.candidates.first(where: { $0.winner })?.kind ?? "—")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    LabeledContent("Đối chiếu (F5)", value: diag.reconcile.status)
                    if !diag.roiRounds.isEmpty {
                        LabeledContent("Vòng đọc lại vùng (ROI)",
                                       value: "\(diag.roiRounds.count)")
                    }
                    ForEach(nonReadProvenanceRows(diag), id: \.0) { row in
                        LabeledContent(row.0) {
                            Text(row.1).font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    if let exportURL = diagnosticsExportURL(diag) {
                        ShareLink(item: exportURL) {
                            Label("Xuất hồ sơ chẩn đoán (JSON)",
                                  systemImage: "square.and.arrow.up")
                        }
                    }
                } else if diagnosticsMissing {
                    Text("Tờ này chưa có hồ sơ chẩn đoán — nó được đọc trước bản v3, hoặc lần đọc gần nhất ghi hồ sơ thất bại (tờ khi đó đã bị ép vào Kiểm Lại).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button { loadDiagnostics() } label: {
                        Label("Tải hồ sơ chẩn đoán", systemImage: "waveform.path.ecg")
                    }
                }
            }

            // F3 (WP1): văn bản đọc thô đã lưu — chỉ hiện khi có chữ (CODE-AUDIT
            // F3 mục 2). WP3 đóng F3 mục 3: nhãn trung thực theo nguồn —
            // hoá đơn nạp từ PDF lớp chữ thì ghi "Văn bản trong PDF", còn
            // lại là "Văn bản OCR gốc" (mặc định của component).
            if !receipt.ocrRawText.isEmpty {
                Section {
                    RawTextDisclosure(text: receipt.ocrRawText,
                                      title: rawTextTitle(sourceType: receipt.sourceType,
                                                           isPDFTextLayer: receipt.rawTextFromPDFTextLayer))
                }
            }

            let flags = receiptFlags(receipt)
            if !flags.isEmpty {
                Section("Cần kiểm lại") {
                    ForEach(flags, id: \.self) { flag in
                        Label(flag, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.orange)
                        // L-2026-11-13-20: cờ thiếu mục đích phải TỰ
                        // PHỤC VỤ — ô nhập + nút lưu nằm ngay dưới
                        // cảnh báo, dùng chung state với mục Phân
                        // loại. Trước đây cờ chỉ báo mà không chỉ
                        // đường sửa; anh bấm "Lưu thay đổi" ở mục
                        // dưới trong lúc ô này trống thì app lưu
                        // trống và cờ còn mãi (anh báo 2 lần).
                        if flag == missingPurposeFlagText {
                            BusinessPurposeField(text: $purposeText)
                            Button("Lưu mục đích") { saveChanges() }
                        }
                        // L-2026-11-18-32: cờ "Chưa rõ tiệm" cũng
                        // phải TỰ PHỤC VỤ như cờ mục đích — ô gõ
                        // tên tiệm + nút lưu ngay dưới cảnh báo.
                        // Trước gói này Chi Tiết không có ô sửa
                        // tiệm nào, cờ này là án treo vĩnh viễn
                        // (tờ Hobby Lobby của anh, bản #143).
                        // Lưu xong bộ cờ tính lại trên bản ghi:
                        // tên tiệm có chữ -> cờ tự tắt.
                        if flag == missingVendorFlagText {
                            TextField("Tên tiệm", text: $vendorText)
                            Button("Lưu tên tiệm") { saveChanges() }
                        }
                    }
                }
            }

            Section("Phân loại") {
                ClassificationBadge(kind: receipt.classification, cardLast4: receipt.cardLast4)
                if !receipt.classificationReason.isEmpty {
                    Text(receipt.classificationReason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                // L-2026-11-18-32: ô sửa tên tiệm trong khối
                // sửa của Chi Tiết (dùng chung state với ô tự
                // phục vụ dưới cờ "Chưa rõ tiệm") — sửa được cả
                // khi tên đọc SAI (không có cờ) chứ không chỉ
                // khi thiếu tên. Lưu qua nút "Lưu thay đổi"
                // chung của khối, như loại/mục/mục đích.
                TextField("Tiệm", text: $vendorText)
                Picker("Loại", selection: $selectedKind) {
                    Text("CÁ NHÂN").tag(Classification.personal)
                    Text("BUSINESS").tag(Classification.business)
                    Text("CHƯA RÕ").tag(Classification.unknown)
                }
                .pickerStyle(.segmented)
                Picker("Mục", selection: $selectedCategory) {
                    ForEach(categoryOptions, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                if selectedKind == .business {
                    BusinessPurposeField(text: $purposeText)
                }
                Button("Lưu thay đổi") { saveChanges() }
                if savedNote {
                    Text("Đã lưu ✓").font(.caption).foregroundStyle(.green)
                }
                if let saveError {
                    Text(saveError).font(.caption).foregroundStyle(.red)
                }
            }

            if !receipt.items.isEmpty {
                Section("Từng món (\(receipt.items.count))") {
                    ForEach(receipt.items.sorted { $0.sortIndex < $1.sortIndex }) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).font(.callout)
                                Text("SL \(item.qty)" + (item.taxFlag.map { " · cờ \($0)" } ?? ""))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(formatMoney(optionalCents: item.amountCents))
                                .font(.callout)
                                .monospacedDigit()
                        }
                    }
                }
            }

            Section {
                if receipt.status == .needsReview {
                    // Cổng duyệt theo LỚP cờ — phán quyết thuần
                    // ở ReceiptLogic.approvalGate (L-2026-11-18
                    // -32, thay luật chặn của P2-0/C-1): không
                    // cờ -> duyệt thẳng; còn cờ lệch số học /
                    // thiếu trường -> duyệt kèm cờ qua hộp xác
                    // nhận nêu rõ từng cờ (WP6-SPEC §5: dấu
                    // confirmedWithFlag); CHỈ cờ thiếu ảnh gốc
                    // còn giữ khoá — bằng chứng bắt buộc — và
                    // nút phải nói rõ lý do + đường gỡ ngay tại
                    // nút. Nguyên tắc anh chốt: chủ app không
                    // bao giờ bị khoá duyệt với tờ đã tự kiểm.
                    switch ReceiptLogic.approvalGate(flags: flags) {
                    case .approveDirectly:
                        Button { approveReceipt(confirmedWithFlag: false) } label: {
                            Label("Duyệt — đã kiểm, cho vào sổ chính thức", systemImage: "checkmark.circle.fill")
                        }
                    case .approveWithFlagConfirmation(let confirmFlags):
                        Button {
                            pendingConfirmFlags = confirmFlags
                            showConfirmWithFlag = true
                        } label: {
                            Label("Duyệt kèm cờ — anh xác nhận đã kiểm", systemImage: "checkmark.circle.fill")
                        }
                        Text("Tờ còn cờ: \(confirmFlags.joined(separator: "; ")). Bấm duyệt sẽ hỏi anh xác nhận đã tự kiểm với giấy; các cờ vẫn hiện nguyên để accountant thấy.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case .blockedByMissingImage(let allFlags):
                        Button {} label: {
                            Label("Duyệt — đã kiểm, cho vào sổ chính thức", systemImage: "checkmark.circle.fill")
                        }
                        .disabled(true)
                        Text("Chưa duyệt được — tờ đang thiếu ảnh gốc, là bằng chứng bắt buộc phải có. Anh gắn lại ảnh ở mục \"Ảnh gốc\" phía trên (chọn từ thư viện ảnh / Files, hoặc chụp lại bản gốc) — gắn xong nút duyệt mở ngay. Cờ đang có: \(allFlags.joined(separator: "; ")).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Label("Đã duyệt ✓", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    // L-1 (WP6-SPEC §5): dấu xác nhận kèm cờ
                    // hiện rõ sau khi duyệt — các cờ VẪN tính
                    // trực tiếp từ số đã lưu ở mục "Cần kiểm
                    // lại" phía trên, dấu này không nuốt cờ.
                    if receipt.confirmedWithFlag {
                        Text("Đã xác nhận kèm cờ: tờ còn cờ chưa xử lý, anh đã tự kiểm với giấy và duyệt.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Button(role: .destructive) { showDeleteConfirm = true } label: {
                    Label("Xoá hoá đơn này", systemImage: "trash")
                }
            }
        }
        .dsListBackground()
        .navigationTitle("Chi Tiết Hoá Đơn")
        .navigationBarTitleDisplayMode(.inline)
        // P2-0/C-1 (WP6-SPEC §5) mở rộng bởi L-2026-11-18-32:
        // xác nhận tường minh trước khi duyệt một tờ còn cờ —
        // hộp nêu rõ TỪNG cờ đang có (chụp ở pendingConfirmFlags
        // lúc bấm nút), không chỉ riêng lớp lệch số học như cũ.
        .confirmationDialog("Tờ còn cờ chưa xử lý — anh đã kiểm với giấy chưa?",
                            isPresented: $showConfirmWithFlag,
                            titleVisibility: .visible) {
            Button("Đã kiểm với giấy — duyệt kèm cờ") {
                approveReceipt(confirmedWithFlag: true)
            }
            Button("Chưa — để kiểm lại", role: .cancel) {}
        } message: {
            Text("Tờ còn các cờ: \(pendingConfirmFlags.joined(separator: "; ")). Duyệt kèm cờ ghi dấu anh đã tự xác nhận; các cờ vẫn hiện nguyên để accountant thấy.")
        }
        .confirmationDialog("Xoá hẳn hoá đơn này và ảnh gốc?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Xoá", role: .destructive) {
                // C9-FIX (FULL-REVIEW): bản cũ xoá FILE TRƯỚC,
                // lưu SAU — lưu hỏng là bản ghi còn mà ảnh gốc
                // (bằng chứng) đã mất vĩnh viễn; và chỉ xoá file
                // theo tên hiện tại, để mồ côi các ảnh gốc phụ.
                // Nay: chụp tên file TRƯỚC, xoá bản ghi + LƯU
                // trước; lưu được mới xoá file (gồm mọi ảnh gốc
                // phụ trong originalImageFileNames); lưu hỏng
                // thì rollback — mọi thứ còn nguyên — và báo thật.
                let mainName = receipt.imageFileName
                let extraNames = receipt.originalImageFileNames
                    .filter { $0 != mainName }
                let deletedID = receipt.stableID.isEmpty
                    ? "(chưa có stableID)" : receipt.stableID
                modelContext.delete(receipt)
                if saveContextOrFalse(modelContext) {
                    // L-2026-11-20-42: xoá file bằng chứng
                    // qua cổng kiểm tra tham chiếu chéo — tờ
                    // vừa xoá đã ra khỏi sổ nên fetch lúc này
                    // cho đúng tập hoá đơn CÒN LẠI; file nào
                    // còn tờ khác tham chiếu thì GIỮ (bỏ qua),
                    // file nào hết tham chiếu mới xoá thật
                    // (kèm bản kho an toàn + .ocrdiag + -flat).
                    // Mọi lần xoá/bỏ qua đều ghi log integrity
                    // trong deleteReceiptEvidence. Đọc sổ lỗi
                    // -> coi như còn tham chiếu ở mọi file
                    // (hướng an toàn: giữ bằng chứng, lượt kiểm
                    // kê sau tự đối chiếu lại).
                    var stillReferenced: Set<String>
                    do {
                        let remaining = try modelContext.fetch(
                            FetchDescriptor<Receipt>())
                        stillReferenced = Set(remaining.flatMap {
                            $0.allOriginalImageFileNames })
                    } catch {
                        stillReferenced = Set([mainName] + extraNames)
                    }
                    // L-2026-11-20-42 (rà soát R1 ghế A-2):
                    // bản chụp NHÁP còn sống cũng là một tham
                    // chiếu — hoá đơn nhận THẲNG tên file của
                    // nháp lúc lưu (save(): imageFileName =
                    // draft.imageFileName, originalImage
                    // FileNames = draft.originalFileNames),
                    // và bản chụp chỉ bị xoá qua onDone của
                    // ReviewView nên app bị giết giữa chừng là
                    // bản chụp sống lại CÙNG tên với tờ đã lưu.
                    // Tên nào nháp còn giữ thì KHÔNG xoá file:
                    // nháp khôi phục không được trỏ vào hư vô.
                    // Accessor đồng bộ có sẵn PendingDraftStore
                    // .load() (ScanView/CardsView vẫn gọi vậy).
                    if let snapshot = PendingDraftStore.load() {
                        stillReferenced.insert(snapshot.imageFileName)
                        stillReferenced.formUnion(
                            snapshot.originalFileNames)
                    }
                    ImageIntegrity.deleteReceiptEvidence(
                        mainName: mainName,
                        extraNames: extraNames,
                        receiptID: deletedID,
                        stillReferenced: stillReferenced)
                    // P2-1: kích lượt gương — tờ vừa xoá khỏi
                    // kho sẽ được đối chiếu manifest và chuyển
                    // bản gương vào _deleted/ (không xoá cứng).
                    MirrorSync.requestSync(using: modelContext)
                    DriveSync.requestSync(using: modelContext)
                    dismiss()
                } else {
                    modelContext.rollback()
                    saveError = "Xoá chưa thành công — hoá đơn và ảnh gốc vẫn còn nguyên. Anh thử lại giúp."
                }
            }
            Button("Huỷ", role: .cancel) {}
        }
        // IMGFIX: hai ngõ gắn lại ảnh gốc — bám đúng mẫu ScanView đang
        // dùng (PhotosPicker cho ảnh; ReceiptFilePickerPresenter chọn
        // FILE ở nút bấm phía trên, không chọn thư mục — bài học
        // Test 0 ở TEAM.md; presenter thay .fileImporter từ
        // L-2026-11-20-45).
        .photosPicker(isPresented: $showReattachPicker, selection: $reattachPickerItem, matching: .images)
        .onChange(of: reattachPickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    attachReattachedImage(image)
                } else {
                    reattachError = "Không mở được ảnh đã chọn."
                }
                reattachPickerItem = nil
            }
        }
        // SCANPRO: mở máy quét tài liệu toàn màn hình — bám đúng mẫu
        // tab CHỤP (DocumentCameraView của ScanView, fullScreenCover +
        // ignoresSafeArea). Huỷ quét = đóng, KHÔNG đổi gì trên bản ghi.
        .fullScreenCover(isPresented: $showRescanCamera) {
            DocumentCameraView(
                onScan: { scan in
                    showRescanCamera = false
                    applyRescannedOriginal(scan: scan)
                },
                onCancel: { showRescanCamera = false },
                onError: { error in
                    showRescanCamera = false
                    rescanError = "Quét thất bại: \(error.localizedDescription)"
                }
            )
            .ignoresSafeArea()
        }
    }

    private func moneyText(_ cents: Int?) -> Text {
        Text(formatMoney(optionalCents: cents)).monospacedDigit()
    }

    // IMGFIX: hạ cánh file gắn lại vào CHÍNH bản ghi này. imageFileName
    // luôn trỏ tới file vừa gắn (đó là file màn Chi Tiết hiển thị qua
    // ImageStore.load — kể cả .pdf, load tự render trang 1 như tờ nạp
    // PDF từ đầu). originalImageFileNames chỉ được nạp khi đang rỗng
    // (tờ đời cũ chưa có danh sách); đã có danh sách thì KHÔNG chắp
    // thêm — allOriginalImageFileNames đã gộp imageFileName vào đầu
    // danh sách bằng chứng, và giữ nguyên danh sách cũ là giữ nguyên
    // lịch sử bằng chứng của tờ. Lưu context xong, thân màn tự vẽ lại:
    // mục "Ảnh gốc" nhường chỗ cho mục "Ảnh gốc (bằng chứng)" và cờ
    // "Thiếu ảnh gốc" tự mất (receiptFlags tính lại theo file mới).
    private func attachReattachedOriginal(named name: String) {
        receipt.imageFileName = name
        if receipt.originalImageFileNames.isEmpty {
            receipt.originalImageFileNames = [name]
        }
        // N2-FIX: gắn ảnh chỉ xong khi ghi nhận vào hoá đơn đã
        // LƯU được; bản cũ nuốt lỗi rồi xoá thông báo lỗi cũ,
        // trông như đã gắn thành công.
        if saveContextOrFalse(modelContext) {
            reattachError = nil
            // P2-1: bằng chứng vừa đổi — kích lượt gương.
            MirrorSync.requestSync(using: modelContext)
            DriveSync.requestSync(using: modelContext)
        } else {
            reattachError = "Ảnh đã lưu vào máy nhưng ghi nhận vào hoá đơn không thành công — anh thử gắn lại giúp."
        }
    }

    /// Đường ảnh (thư viện ảnh, hoặc file ảnh từ Files): lưu JPEG qua
    /// đúng ImageStore.saveJPEG như mọi đường nạp — lưu hỏng thì báo
    /// lỗi thật, không gán tên file ma vào bản ghi.
    private func attachReattachedImage(_ image: UIImage) {
        guard let name = ImageStore.saveJPEG(image) else {
            reattachError = "Không lưu được ảnh gốc vào máy — anh kiểm tra dung lượng trống giúp."
            return
        }
        attachReattachedOriginal(named: name)
    }

    /// Đường file từ Files: bám kỷ luật đường nạp file của ScanView —
    /// mở quyền truy cập bảo mật, đọc ĐỒNG BỘ trong cùng lượt gọi, đóng
    /// ngay. PDF lưu NGUYÊN BYTE qua ImageStore.saveFile (như đường nạp
    /// PDF của WP3) để bằng chứng giữ đúng dạng file mà màn Chi Tiết
    /// render được; ảnh thì rẽ sang đường JPEG ở trên.
    private func attachReattachedFile(url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            reattachError = "Không đọc được file \(url.lastPathComponent)."
            return
        }
        if url.pathExtension.lowercased() == "pdf" {
            guard let name = ImageStore.saveFile(data: data, fileExtension: "pdf") else {
                reattachError = "Không lưu được file PDF gốc vào máy — anh kiểm tra dung lượng trống giúp."
                return
            }
            attachReattachedOriginal(named: name)
        } else if let image = UIImage(data: data) {
            attachReattachedImage(image)
        } else {
            reattachError = "File \(url.lastPathComponent) không phải PDF hay ảnh đọc được."
        }
    }

    // SCANPRO: hạ cánh bản quét lại vào CHÍNH bản ghi này. GIỚI HẠN
    // CÓ CHỦ ĐÍCH: chụp lại CHỈ thay bằng chứng ảnh — KHÔNG chạy OCR,
    // KHÔNG đổi số liệu, ocrRawText giữ nguyên (nút "Đọc lại" ở mục
    // Bộ đọc là đường duy nhất đổi số, và nó đọc từ ocrRawText đó).
    //
    // - Trang 1 -> ImageStore.saveJPEG(quality: 0.9) -> imageFileName
    //   MỚI (màn Chi Tiết hiển thị file này).
    // - File chính cũ (khác rỗng) KHÔNG bị xoá: đưa vào
    //   originalImageFileNames giữ dấu vết bằng chứng; các trang
    //   quét thêm (2+) nối tiếp vào đó.
    // - Toàn vẹn: mọi trang phải lưu thành công mới hạ cánh; trang
    //   nào lưu hỏng -> xoá các file vừa lưu dở, bản ghi giữ nguyên
    //   bộ bằng chứng cũ, báo lỗi thật — không để bản ghi trỏ tới
    //   bộ bằng chứng nửa vời.
    private func applyRescannedOriginal(scan: VNDocumentCameraScan) {
        guard scan.pageCount > 0 else {
            rescanError = "Chưa chụp được trang nào — anh thử lại giúp."
            return
        }
        var newNames: [String] = []
        for page in 0..<scan.pageCount {
            guard let name = ImageStore.saveJPEG(scan.imageOfPage(at: page), quality: 0.9) else {
                for saved in newNames { ImageStore.delete(fileName: saved) }
                rescanError = "Không lưu được bản quét vào máy — anh kiểm tra dung lượng trống giúp."
                return
            }
            newNames.append(name)
        }
        var evidence = receipt.originalImageFileNames
        let oldMain = receipt.imageFileName
        if !oldMain.isEmpty && !evidence.contains(oldMain) {
            evidence.append(oldMain)
        }
        for name in newNames.dropFirst() where !evidence.contains(name) {
            evidence.append(name)
        }
        receipt.originalImageFileNames = evidence
        receipt.imageFileName = newNames[0]
        // N2-FIX: như các điểm lưu khác — chỉ xoá lỗi cũ khi
        // việc ghi nhận bản quét mới đã LƯU được thật.
        if saveContextOrFalse(modelContext) {
            rescanError = nil
            // P2-1: bằng chứng vừa đổi — kích lượt gương.
            MirrorSync.requestSync(using: modelContext)
            DriveSync.requestSync(using: modelContext)
            // S2: bộ bằng chứng vừa đổi — sinh bản scan phẳng
            // cho các trang quét mới ở nền (chỉ để hiển thị;
            // trang nào không có góc tin cậy thì không có bản
            // phẳng, màn Chi Tiết tự lùi về ảnh gốc).
            let flatTargets = newNames
            DispatchQueue.global(qos: .utility).async {
                for name in flatTargets {
                    guard let original = ImageStore.load(fileName: name),
                          let cg = ReceiptReader.uprightCGImage(
                            from: original),
                          let flat = FlatScan.makeFlatImage(from: cg)
                    else { continue }
                    _ = FlatScan.saveFlatImage(flat, forOriginal: name)
                }
            }
        } else {
            rescanError = "Bản quét đã lưu vào máy nhưng ghi nhận vào hoá đơn không thành công — anh thử lại giúp."
        }
    }

    // REPARSE: hạ cánh kết quả đọc lại vào CHÍNH bản ghi này, theo đúng
    // ánh xạ ReviewView.save() dùng cho hoá đơn mới — trừ các điểm giữ
    // nguyên quyết định/bằng chứng của người dùng (ghi rõ từng điểm):
    //
    // CẬP NHẬT (máy đọc): vendor + địa chỉ/điện thoại/mã cửa hàng, ngày
    // (chỉ khi bộ đọc tìm thấy — save() ghi ngày anh chốt trên lịch;
    // đọc lại không có lịch nên KHÔNG bao giờ ghi đè ngày đã lưu bằng
    // "hôm nay" khi bộ đọc trượt), subtotal/thuế/tổng, items và
    // taxLines (thay cả cụm), thẻ + paymentMethod, 3 độ tin cậy,
    // dedupeKey (chỉ khi bộ đọc sinh được khoá mới — không xoá khoá cũ
    // khi bộ đọc trượt), parserVersion -> bản hiện hành, status tính
    // lại đúng công thức save().
    //
    // GIỮ NGUYÊN (người dùng/bằng chứng): stableID, createdAt,
    // imageFileName + originalImageFileNames (ảnh gốc), sourceType +
    // sourceFileName, transactionRef (save() suy nó từ dedupeKey cho
    // bản ghi MỚI; bản ghi cũ giữ mã giao dịch đã lưu, không suy lại),
    // ocrRawText (chính là đầu vào của lần đọc này — bằng chứng gốc,
    // không ghi đè bằng bản đã chuẩn hoá của parser), businessPurpose,
    // và phân loại + mục nếu anh ĐÃ có quyết định (xem dưới).

    /// V3 (Pha 4): tải file phụ chẩn đoán của tờ này (nil -> ghi
    /// nhận thiếu để mục Chẩn đoán nói thật lý do).
    private func loadDiagnostics() {
        if let diag = DiagnosticsStore.load(
            directory: ImageStore.directory,
            imageFileName: receipt.imageFileName) {
            loadedDiagnostics = diag
            diagnosticsMissing = false
        } else {
            diagnosticsMissing = true
        }
    }

    /// Các dòng provenance KHÁC "đọc thẳng" trong snapshot của hồ
    /// sơ (suy luận/ROI/sửa chữ) — trình ở mức dữ liệu cho anh đối
    /// chiếu; trường đọc thẳng không liệt kê (mặc định im lặng).
    private func nonReadProvenanceRows(_ diag: ReadDiagnostics)
        -> [(String, String)] {
        diag.parse.provenance
            .filter { $0.value.kind != "read" }
            .sorted { $0.key < $1.key }
            .map { ($0.key, provenanceCaption($0.value) ?? $0.value.kind) }
    }

    /// Ghi JSON hồ sơ ra file tạm để ShareLink xuất (xuất đúng
    /// exportJSON của giản đồ v2 — không định dạng lại ở UI).
    private func diagnosticsExportURL(_ diag: ReadDiagnostics) -> URL? {
        guard let data = try? diag.exportJSON() else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                DiagnosticsStore.fileName(
                    forImageFileName: receipt.imageFileName))
        do {
            try data.write(to: url, options: [.atomic])
            return url
        } catch {
            return nil
        }
    }

    /// P2-0/C-1: duyệt tờ — đường thẳng (không cờ) hoặc kèm
    /// cờ sau xác nhận tường minh. N2-FIX giữ nguyên: chỉ
    /// thành công khi LƯU được; hỏng thì trả mọi trường về
    /// cũ và báo thật.
    private func approveReceipt(confirmedWithFlag: Bool) {
        let oldStatus = receipt.status
        let oldConfirmed = receipt.confirmedWithFlag
        let oldReviewedAt = receipt.reviewedAt
        receipt.status = .reviewed
        if confirmedWithFlag {
            receipt.confirmedWithFlag = true
        }
        // P2-0 mục 16 (F4): đóng dấu thời điểm duyệt.
        receipt.reviewedAt = Date()
        if saveContextOrFalse(modelContext) {
            saveError = nil
            // P2-1: trạng thái duyệt vừa đổi — kích lượt gương.
            MirrorSync.requestSync(using: modelContext)
            DriveSync.requestSync(using: modelContext)
        } else {
            receipt.status = oldStatus
            receipt.confirmedWithFlag = oldConfirmed
            receipt.reviewedAt = oldReviewedAt
            saveError = "Duyệt chưa lưu được — trên máy tờ này vẫn đang chờ duyệt. Anh thử lại giúp."
        }
    }

    private func reparseReceipt() {
        // L-2026-11-13-18: CHỐT các sửa tay đang chờ trong màn này
        // (loại/mục/mục đích anh vừa gõ mà chưa bấm "Lưu thay đổi")
        // vào bản ghi TRƯỚC khi đọc lại. Trước đây bước áp số mới
        // đồng bộ ngược state từ bản ghi, nuốt mất phần anh vừa
        // gõ — ghi chú mục đích là ca anh vấp (báo 2026-11-13:
        // đã nhập mục đích business mà app vẫn báo thiếu). Chốt
        // trước = các sửa đó thành "quyết định của anh" và được
        // luật giữ nguyên của bước áp bảo vệ như thường.
        let kindChanged = selectedKind != receipt.classification
        // P2-0 mục 16 (F5): chụp giá trị TRƯỚC khi chốt sửa
        // tay, để biết trường nào là anh vừa sửa (ghi vào
        // userEnteredFieldNames ở cuối hàm).
        let categoryBeforeCommit = receipt.category
        let purposeBeforeCommit = receipt.businessPurpose
        let vendorBeforeCommit = receipt.vendor
        receipt.classification = selectedKind
        if kindChanged {
            receipt.classificationReason = "Anh đổi tay trong chi tiết hoá đơn"
        }
        receipt.category = selectedCategory
        receipt.businessPurpose = purposeText
        // L-2026-11-18-32: chốt cả tên tiệm anh vừa gõ (cùng
        // luật L-2026-11-13-18 cho loại/mục/mục đích) — tên
        // gõ tay là quyết định của anh, bước áp số đọc ở dưới
        // không được ghi đè (xem vendorHandEntered).
        receipt.vendor = vendorText.trimmingCharacters(
            in: .whitespacesAndNewlines)
        let vendorHandEntered = !receipt.vendor.isEmpty
            && (receipt.userEnteredFieldNames.contains("vendor")
                || receipt.vendor != vendorBeforeCommit)
        // V3 (Pha 4): Đọc lại đi qua ĐƯỜNG ĐỌC DUY NHẤT
        // (ReceiptReader, nguồn storedText — cùng F4+F5 như lần
        // quét mới, kèm hồ sơ chẩn đoán v2 cho lần đọc này);
        // ReceiptParser.reparse (đường tắt chỉ-F4 của các bản
        // trước) không còn được UI gọi nữa. Độ tin cậy dòng 0.5
        // giữ đúng ngữ nghĩa của đường reparse di sản.
        let outcome = ReceiptReader.read(ReadRequest(
            source: .storedText,
            imageFileName: receipt.imageFileName,
            textLines: receipt.ocrRawText
                .split(separator: "\n")
                .map { OCRLine(text: String($0),
                               confidence: ReceiptParser
                                   .recoveredLineConfidence) },
            diagnosticsDirectory: receipt.imageFileName.isEmpty
                ? nil : ImageStore.directory,
            taxLandingContext: TaxLandingContextBuilder.make()))
        let result = outcome.result

        // --- Trường máy đọc, ánh xạ như save() ---
        // L-2026-11-18-32: tên tiệm gõ tay (vendorHandEntered)
        // thì GIỮ NGUYÊN — bản cũ ghi đè vô điều kiện bằng
        // kết quả đọc, bộ đọc trượt (Hobby Lobby) là xoá mất
        // tên anh vừa gõ về rỗng. Địa chỉ/điện thoại/mã cửa
        // hàng vẫn áp theo máy đọc như save() (bằng chứng liên
        // hệ đọc từ giấy, không suy từ tên gõ tay).
        if !vendorHandEntered {
            receipt.vendor = result.vendor ?? ""
        }
        receipt.vendorAddress = result.vendorAddress ?? ""
        receipt.vendorPhone = result.vendorPhone
        receipt.storeNumber = result.storeNumber
        if let date = result.date {
            receipt.date = date
        }
        receipt.subtotalCents = result.subtotalCents
        receipt.totalCents = result.totalCents
        // Dòng thuế riêng theo đúng luật WP2 của save(): chỉ lưu chi
        // tiết dòng khi tổng thuế "đã duyệt" khớp Σ dòng máy đọc. Đọc
        // lại không có tay anh sửa giữa chừng, nên tổng đã duyệt chính
        // là Σ dòng của bộ đọc -> có dòng thuế thì lưu cả cụm và
        // taxCents = Σ dòng; không có dòng nào thì taxCents = nil
        // (chưa đọc được) như save() khi ô thuế để trống — không gộp
        // hai nghĩa nil/0.
        let persistTaxLines = !result.taxes.isEmpty
        receipt.taxCents = persistTaxLines ? result.taxTotalCents : nil
        let oldTaxLines = receipt.taxLines
        for line in oldTaxLines { modelContext.delete(line) }
        if persistTaxLines {
            for (index, parsedTax) in result.taxes.enumerated() {
                let line = TaxLine()
                line.label = parsedTax.label
                line.rateText = parsedTax.rateText
                line.amountCents = parsedTax.amountCents
                line.sortIndex = index
                line.receipt = receipt
                modelContext.insert(line)
            }
        }
        // Items: thay cả cụm như taxLines (bản ghi cũ giữ items của bộ
        // đọc cũ sẽ lẫn hai thế hệ số trong cùng một tờ).
        let oldItems = receipt.items
        for item in oldItems { modelContext.delete(item) }
        for (index, parsed) in result.items.enumerated() {
            let item = LineItem()
            item.name = parsed.name
            item.qty = parsed.qty
            item.unitPriceCents = parsed.unitPriceCents
            item.amountCents = parsed.amountCents
            item.taxFlag = parsed.taxFlag
            item.itemCode = parsed.itemCode
            item.sortIndex = index
            item.receipt = receipt
            modelContext.insert(item)
        }
        receipt.cardLast4 = result.cardLast4
        receipt.cardBrand = result.cardBrand
        // Như save(): có đuôi thẻ -> trả bằng thẻ, không có -> .unknown,
        // không bao giờ đoán tiền mặt.
        receipt.paymentMethod = (result.cardLast4?.isEmpty == false) ? .card : .unknown
        if let key = result.dedupeKey {
            receipt.dedupeKey = key
        }
        // L-2026-11-18-32: giữ tên gõ tay thì cũng giữ độ tin
        // cậy đã lưu — ghi độ tin cậy của lần đọc trượt lên
        // tên của anh là số vô nghĩa.
        if !vendorHandEntered {
            receipt.vendorConfidence = result.vendorConfidence
        }
        receipt.dateConfidence = result.dateConfidence
        receipt.totalConfidence = result.totalConfidence

        // --- Phân loại: quyết định của anh thắng gợi ý ---
        // Đã có quyết định (loại khác "chưa rõ", hoặc chính tay anh đổi
        // trong màn này) thì giữ nguyên loại + lý do + mục: snapshot
        // phân loại là của anh, kể cả khi sổ thẻ đã đổi về sau. Chưa có
        // quyết định nào thì áp gợi ý theo thẻ đúng như save() (kèm
        // chỉnh mục về mặc định của loại mới nếu mục cũ không thuộc
        // danh sách của loại đó — cùng luật applySuggestionOnce).
        let userDecided = receipt.classification != .unknown
            || receipt.classificationReason == "Anh đổi tay trong chi tiết hoá đơn"
        if !userDecided {
            let suggestion = suggestClassification(cardLast4: result.cardLast4,
                                                   cardBrand: result.cardBrand,
                                                   tails: cardTails)
            receipt.classification = suggestion.0
            receipt.classificationReason = suggestion.1
            if !Categories.list(for: receipt.classification).contains(receipt.category) {
                receipt.category = Categories.defaultValue(for: receipt.classification)
            }
        }

        // --- Trạng thái: đúng công thức Hộp Chờ của save() ---
        // V3 (Pha 4): cộng outcome.requiresReview của pipeline —
        // trọng tài F5 đòi kiểm lại, hoặc ghi chẩn đoán thất bại
        // (ReadOutcome.requiresReview đã gồm cả hai) thì tờ ở lại
        // Kiểm Lại dù các số có vẻ đủ.
        // L-2026-11-18-29: cả hai hạng tử suy từ cảnh báo đều
        // qua hoà giải sổ thẻ (như ReviewView): đuôi khớp ĐÚNG
        // thẻ đã đăng ký thì cờ nghi ngờ đuôi thẻ không còn là
        // lý do giữ tờ. outcome.requiresReview chỉ được tính
        // lại khi đọc đã khép (report.status == .ok — nơi
        // requiresReview suy thuần từ warnings) và cảnh báo
        // hiệu lực đã rỗng; ghi chẩn đoán thất bại luôn giữ tờ.
        let effectiveWarnings = warningsClearingRegisteredCardFlags(
            result.warnings,
            cardLast4: result.cardLast4,
            registeredTails: Set(cardTails.map { $0.last4 }))
        let readRequiresReview = outcome.diagnosticsWriteFailed
            || (outcome.report.requiresReview
                && !(outcome.report.status == .ok
                     && effectiveWarnings.isEmpty))
        let stillNeedsReview = receipt.classification == .unknown
            || receipt.totalCents == nil
            || !effectiveWarnings.isEmpty
            || readRequiresReview
            || (receipt.classification == .business
                && receipt.businessPurpose.trimmingCharacters(in: .whitespaces).isEmpty)
        receipt.status = stillNeedsReview ? .needsReview : .reviewed
        // P2-0 mục 15 (§2.2(5)): đóng dấu dòng Schedule C
        // theo mục CUỐI CÙNG sau gợi ý — trước gói này không
        // đường nào từng ghi trường này.
        receipt.scheduleCLine = Categories.scheduleCLine(
            forCategory: receipt.category)
        // P2-0 mục 16 (F4/F5): duyệt qua Đọc lại cũng đóng
        // dấu thời điểm; các sửa tay vừa chốt ghi tên trường.
        if receipt.status == .reviewed {
            receipt.reviewedAt = Date()
        }
        var enteredNames = receipt.userEnteredFieldNames
        if kindChanged && !enteredNames.contains("classification") {
            enteredNames.append("classification")
        }
        if selectedCategory != categoryBeforeCommit
            && !enteredNames.contains("category") {
            enteredNames.append("category")
        }
        if purposeText != purposeBeforeCommit
            && !enteredNames.contains("businessPurpose") {
            enteredNames.append("businessPurpose")
        }
        // L-2026-11-18-32: so Ô GÕ với giá trị trước chốt
        // (không so bản ghi sau áp số đọc — tên máy đọc đổi
        // không phải tay anh sửa).
        if vendorText.trimmingCharacters(in: .whitespacesAndNewlines)
            != vendorBeforeCommit
            && !enteredNames.contains("vendor") {
            enteredNames.append("vendor")
        }
        receipt.userEnteredFieldNames = enteredNames
        receipt.parserVersion = currentParserVersion

        // N2-FIX: chỉ đồng bộ state + hiện ghi chú "đã đọc lại"
        // khi hạ cánh đã LƯU được; bản cũ nuốt lỗi mà vẫn báo
        // thành công trong khi số trên máy vẫn là số cũ.
        if saveContextOrFalse(modelContext) {
            // P2-1: số liệu vừa đọc lại — kích lượt gương.
            MirrorSync.requestSync(using: modelContext)
            DriveSync.requestSync(using: modelContext)
            // Vẽ lại theo số mới: đồng bộ 3 state của khối Phân loại về đúng
            // giá trị vừa hạ cánh (kể cả khi gợi ý vừa đổi loại/mục).
            selectedKind = receipt.classification
            selectedCategory = receipt.category
            purposeText = receipt.businessPurpose
            vendorText = receipt.vendor
            reparsedNote = true
            saveError = nil
        } else {
            saveError = "Đọc lại xong nhưng LƯU không thành công — số trên máy vẫn là số cũ. Anh bấm Đọc lại lần nữa giúp."
        }
    }

    private func saveChanges() {
        let kindChanged = selectedKind != receipt.classification
        let categoryBefore = receipt.category
        let purposeBefore = receipt.businessPurpose
        let vendorBefore = receipt.vendor
        receipt.classification = selectedKind
        if kindChanged {
            receipt.classificationReason = "Anh đổi tay trong chi tiết hoá đơn"
        }
        receipt.category = selectedCategory
        // P2-0/C-7: đổi loại mà mục đang chọn KHÔNG thuộc
        // danh sách của loại mới -> chỉnh về mục mặc định
        // của loại mới (đúng mẫu bước Đọc lại) thay vì lưu
        // một mục không thuộc loại.
        if !Categories.list(for: receipt.classification)
            .contains(receipt.category) {
            receipt.category = Categories.defaultValue(
                for: receipt.classification)
            selectedCategory = receipt.category
        }
        receipt.businessPurpose = purposeText
        // L-2026-11-18-32: ghi tên tiệm anh gõ trong Chi Tiết
        // (cắt trắng hai đầu như bộ cờ phán rỗng). refresh-
        // ReceiptStatusFromFlags ở cuối hàm tính lại cờ trên
        // bản ghi vừa ghi: tên tiệm có chữ -> cờ "Chưa rõ
        // tiệm" tự tắt; đó là cờ duy nhất thì tờ tự chuyển
        // .reviewed như cơ chế C-7 vẫn làm cho các lớp khác.
        receipt.vendor = vendorText.trimmingCharacters(
            in: .whitespacesAndNewlines)
        // P2-0 mục 15 (§2.2(5)): đóng dấu dòng Schedule C.
        receipt.scheduleCLine = Categories.scheduleCLine(
            forCategory: receipt.category)
        // P2-0 mục 16 (F5): ghi tên các trường anh vừa sửa
        // tay (hợp nhất với tên đã ghi trước đó).
        var enteredNames = receipt.userEnteredFieldNames
        if kindChanged && !enteredNames.contains("classification") {
            enteredNames.append("classification")
        }
        if receipt.category != categoryBefore
            && !enteredNames.contains("category") {
            enteredNames.append("category")
        }
        if purposeText != purposeBefore
            && !enteredNames.contains("businessPurpose") {
            enteredNames.append("businessPurpose")
        }
        if receipt.vendor != vendorBefore
            && !enteredNames.contains("vendor") {
            enteredNames.append("vendor")
        }
        receipt.userEnteredFieldNames = enteredNames
        // P2-0/C-7: trạng thái được SUY LẠI bằng bộ cờ trên
        // số đã sửa — trước gói này tờ .reviewed sửa thành
        // trạng thái bị cấm vẫn giữ .reviewed.
        refreshReceiptStatusFromFlags(receipt)
        // N2-FIX: "Đã lưu ✓" chỉ khi lưu được thật; hỏng thì
        // báo đỏ và giữ nguyên thay đổi trong bộ nhớ để anh
        // bấm Lưu lại là ghi tiếp, không phải nhập lại.
        if saveContextOrFalse(modelContext) {
            savedNote = true
            saveError = nil
            // P2-1: thay đổi vừa lưu — kích lượt gương.
            MirrorSync.requestSync(using: modelContext)
            DriveSync.requestSync(using: modelContext)
        } else {
            savedNote = false
            saveError = "Lưu thay đổi không thành công — số trên máy chưa đổi. Anh bấm Lưu lại giúp."
        }
    }
}

// MARK: - Màn Review sau khi quét (kiểm / sửa / lưu)

struct ReviewView: View {
    var draft: ScanDraft
    var onDone: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query private var cardTails: [CardTail]

    @State private var vendorText: String
    @State private var dateValue: Date
    @State private var subtotalText: String
    @State private var taxText: String
    @State private var totalText: String
    @State private var selectedKind: Classification = .unknown
    @State private var reasonText: String = ""
    @State private var selectedCategory: String
    @State private var purposeText: String = ""
    /// P2-0/C-9: ô nhập TIP — chỉ hiện khi tờ có dấu hiệu
    /// nhà hàng (TIP / GRATUITY in trên giấy). TỔNG giữ
    /// nguyên là tổng IN; tip lưu riêng, số đã trả suy ra.
    @State private var tipText: String = ""
    @State private var suggestionApplied = false
    /// PHA 2 (L-2026-11-21-47): hạ cánh bằng thuế — các trường
    /// đang là số ƯỚC TÍNH ("subtotal" | "taxes" | "total"), mô tả
    /// phép suy, loại hàng đang áp và khu vực đã áp (picker tính
    /// lại tại chỗ khi anh đổi loại).
    @State private var landingFields: Set<String> = []
    @State private var landingDetail: String = ""
    @State private var landingCategory: TaxCategory = .general
    @State private var landingAreaText: String = ""
    /// Chữ tiền hạ cánh GẦN NHẤT theo trường — mốc để reland biết
    /// ô nào anh đã gõ tay đè (không tính lại đè, luật §3.7) và để
    /// save() đối chiếu userEnteredFieldNames đúng mốc.
    @State private var landingTexts: [String: String] = [:]
    /// Loại hàng THẬT SỰ đã áp (nil = chưa áp loại nào — hạ cánh
    /// Pha A không cần suất); hồ sơ tiệm chỉ học giá trị này, không
    /// học giá trị mặc định hiển thị của picker.
    @State private var landingAppliedCategory: TaxCategory? = nil
    @State private var showDuplicateAlert = false
    @State private var duplicateCount = 0
    /// N2-FIX: kiểm tra trùng THẤT BẠI (fetch lỗi) — khác hẳn
    /// "không trùng": tờ vẫn lưu được nhưng bị ép chờ duyệt.
    @State private var duplicateCheckFailed = false
    /// N2-FIX: lưu thất bại — hiện alert, KHÔNG đóng màn Kiểm Lại.
    @State private var saveFailed = false
    /// C8-FIX: bộ đọc không tìm thấy ngày trên tờ này — ngày
    /// đang hiện chỉ là ngày tạm (hôm nay), không phải ngày đọc.
    @State private var dateWasMissing = false
    /// Giá trị ngày ban đầu (để nhận biết anh có sửa ngày hay
    /// không khi ngày là ngày tạm).
    private let dateDefault: Date
    /// G3: tác vụ chống dội đang chờ ghi lớp sửa dở xuống đĩa
    /// (xem scheduleReviewEditsSave) — huỷ mỗi khi có sửa mới,
    /// và huỷ hẳn khi màn này đã kết thúc (finished).
    @State private var editSaveTask: Task<Void, Never>? = nil
    /// G3: màn Kiểm Lại đã kết thúc TƯỜNG MINH (lưu thành công
    /// hoặc bấm Huỷ) — từ đây persistReviewEdits là cấm: bản
    /// chụp nháp đã bị ScanView xoá ở onDone, ghi lại sẽ làm
    /// sống lại một bản nháp đã xử lý xong.
    @State private var finished = false
    @Environment(\.scenePhase) private var scenePhase

    /// G3: `restoredEdits` là lớp sửa dở khôi phục từ bản chụp
    /// nháp (nil với bản nháp mới) — các ô dựng từ lớp này thay
    /// vì kết quả đọc gốc, và suggestionApplied lấy đúng giá
    /// trị đã lưu (trong thực tế luôn là true vì lớp sửa chỉ
    /// được ghi sau khi gợi ý đã áp) để applySuggestionOnce
    /// không ghi đè lựa chọn anh đã sửa (kiểm trùng vẫn chạy
    /// lại ở attemptSave như thường).
    init(draft: ScanDraft, restoredEdits: ReviewEditsDTO? = nil,
         onDone: @escaping () -> Void) {
        self.draft = draft
        self.onDone = onDone
        let r = draft.result
        _vendorText = State(initialValue: r.vendor ?? "")
        // C8-FIX: một mốc ngày DUY NHẤT cho cả ô ngày lẫn mốc
        // đối chiếu "anh có sửa ngày tạm không" — hai lần gọi
        // Date() riêng lẻ sẽ lệch nhau vài phần nghìn giây.
        let initialDate = r.date ?? Date()
        _dateValue = State(initialValue: initialDate)
        self.dateDefault = initialDate
        _dateWasMissing = State(initialValue: r.date == nil)
        _subtotalText = State(initialValue: centsToDollarsText(r.subtotalCents))
        _taxText = State(initialValue: r.taxes.isEmpty ? "" : centsToDollarsText(r.taxTotalCents))
        _totalText = State(initialValue: centsToDollarsText(r.totalCents))
        _selectedCategory = State(initialValue: Categories.defaultValue(for: .unknown))
        // PHA 2: trạng thái hạ cánh suy từ provenance của bản đọc
        // (kind "tax-landing"); loại/khu đang áp tính lại bằng
        // chính lõi TaxLanding trên bản đọc đã bóc đỉnh ước tính,
        // để picker ở dưới khớp đúng phép suy đã chạy.
        let prov = draft.provenance
        let derivedKeys = prov.filter { $0.value.kind == "tax-landing" }
            .map { $0.key }
        var fields0 = Set<String>()
        if derivedKeys.contains("subtotal") { fields0.insert("subtotal") }
        if derivedKeys.contains("total") { fields0.insert("total") }
        if derivedKeys.contains(where: { $0.hasPrefix("tax[") }) {
            fields0.insert("taxes")
        }
        _landingFields = State(initialValue: fields0)
        _landingDetail = State(initialValue:
            prov.values.first { $0.kind == "tax-landing" }?.detail ?? "")
        var texts0: [String: String] = [:]
        if fields0.contains("subtotal") {
            texts0["subtotal"] = centsToDollarsText(r.subtotalCents)
        }
        if fields0.contains("taxes") {
            texts0["taxes"] = r.taxes.isEmpty
                ? "" : centsToDollarsText(r.taxTotalCents)
        }
        if fields0.contains("total") {
            texts0["total"] = centsToDollarsText(r.totalCents)
        }
        _landingTexts = State(initialValue: texts0)
        if !fields0.isEmpty {
            let base = ReviewView.strippedForRelanding(r, provenance: prov)
            let ctx = TaxLandingContextBuilder.make()
            if let out = TaxLanding.evaluate(base, context: ctx),
               out.report.attempted,
               let cat = out.report.category {
                _landingCategory = State(initialValue: cat)
                _landingAppliedCategory = State(initialValue: cat)
                if let areaID = out.report.areaID,
                   let area = ctx.table.portion(id: areaID),
                   let rate = out.report.ratePct {
                    _landingAreaText = State(initialValue:
                        "\(area.displayName) · \(TaxLanding.formatPct(rate))%")
                }
            }
        }
        if let edits = restoredEdits {
            _vendorText = State(initialValue: edits.vendorText)
            _dateValue = State(initialValue: edits.dateValue)
            _subtotalText = State(initialValue: edits.subtotalText)
            _taxText = State(initialValue: edits.taxText)
            _totalText = State(initialValue: edits.totalText)
            _selectedKind = State(initialValue: Classification(rawValue: edits.kindRaw) ?? .unknown)
            _selectedCategory = State(initialValue: edits.category)
            _purposeText = State(initialValue: edits.purposeText)
            _reasonText = State(initialValue: edits.reasonText)
            _suggestionApplied = State(initialValue: edits.suggestionApplied)
            // PHA 2: khôi phục đúng MỐC hạ cánh đã chụp cùng lớp
            // sửa (nếu có) — thay mốc suy từ draft gốc, để reland
            // sau khôi phục không làm rơi nhãn "ước tính" của các
            // số đã tính lại trước khi chụp.
            if let lt = edits.landingTexts {
                _landingTexts = State(initialValue: lt)
            }
            if let raw = edits.landingAppliedCategoryRaw,
               let cat = TaxCategory(rawValue: raw) {
                _landingAppliedCategory = State(initialValue: cat)
                _landingCategory = State(initialValue: cat)
            }
            // Chú thích hạ cánh khôi phục theo đúng bản chụp —
            // khớp với số/loại vừa khôi phục ở trên.
            if let detail = edits.landingDetail {
                _landingDetail = State(initialValue: detail)
            }
            if let areaText = edits.landingAreaText {
                _landingAreaText = State(initialValue: areaText)
            }
        }
    }

    private var categoryOptions: [String] {
        var options = Categories.list(for: selectedKind)
        if !options.contains(selectedCategory) { options.append(selectedCategory) }
        return options
    }

    /// PASS 2: cổng sổ cái dạng HIỂN THỊ ở đầu màn Kiểm Lại
    /// (đúng mẫu anh duyệt) — cùng luật SCORECARD Ledger Gate:
    /// Σ dòng món (kể cả dòng giảm giá âm) == tạm tính ±2¢ và
    /// tạm tính + thuế == tổng ±2¢. Chỉ ĐỌC draft.result của
    /// bộ đọc, không sửa bất kỳ số nào.
    private var ledgerVerdict: (closed: Bool, text: String) {
        let r = draft.result
        guard let subtotal = r.subtotalCents, let total = r.totalCents else {
            return (false, "Chưa đủ số để khớp sổ — thiếu tạm tính hoặc tổng, anh kiểm tra giúp.")
        }
        let itemsSum = r.items.reduce(0) { $0 + ($1.amountCents ?? 0) }
        let itemsOK = abs(itemsSum - subtotal) <= 2
        let totalOK = abs(subtotal + r.taxTotalCents - total) <= 2
        if itemsOK && totalOK {
            return (true, "Sổ khớp — \(r.items.count) dòng món cộng đúng tạm tính; tạm tính + thuế = tổng.")
        }
        var reasons: [String] = []
        if !itemsOK { reasons.append("tổng các món lệch tạm tính \(formatMoney(cents: abs(itemsSum - subtotal)))") }
        if !totalOK { reasons.append("tạm tính + thuế lệch tổng \(formatMoney(cents: abs(subtotal + r.taxTotalCents - total)))") }
        return (false, "Sổ chưa khớp: " + reasons.joined(separator: "; ") + " — anh kiểm tra các trường bên dưới giúp em.")
    }

    private var ledgerBanner: some View {
        let verdict = ledgerVerdict
        return HStack(alignment: .top, spacing: DS.spaceM) {
            Image(systemName: verdict.closed ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(verdict.closed ? DS.brand : DS.warning)
            Text(verdict.text)
                .font(.callout.weight(.medium))
        }
        .padding(.vertical, DS.spaceXS)
    }

    /// Tổng lớn giữa màn Kiểm Lại (theo mẫu) — đọc từ ô tổng
    /// ĐANG SỬA (totalText) để đổi ngay khi anh gõ.
    private var bigTotalText: String {
        if let cents = dollarsTextToCents(totalText) { return formatMoney(cents: cents) }
        return totalText.isEmpty ? "—" : totalText
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ledgerBanner
                }
                .listRowBackground((ledgerVerdict.closed ? DS.brand : DS.warning).opacity(0.10))

                Section {
                    VStack(spacing: 2) {
                        Text("TỔNG CỘNG")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .tracking(0.6)
                        Text(bigTotalText)
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.spaceS)
                }
                .listRowBackground(Color.clear)
                // S2: ưu tiên bản scan phẳng khi có (đúng ảnh bộ
                // đọc đã đọc); không có thì ảnh gốc như trước.
                if let image = FlatScan.displayImage(
                    forOriginal: draft.imageFileName) {
                    Section {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 220)
                            .frame(maxWidth: .infinity)
                    }
                }

                // F3 (WP1): văn bản đọc thô ngay dưới bằng chứng gốc (CODE-AUDIT
                // F3 mục 1). Đường OCR luôn có chữ mới tạo được draft; đường PDF
                // lớp chữ cũng luôn có chữ (không có chữ thì đã rẽ render->OCR).
                // Vẫn giữ guard rỗng cho đối xứng với màn Chi Tiết.
                // WP3 đóng F3 mục 3: nhãn theo nguồn nạp như màn Chi Tiết.
                if !draft.result.rawText.isEmpty {
                    Section {
                        RawTextDisclosure(text: draft.result.rawText,
                                          title: rawTextTitle(sourceType: draft.sourceType,
                                                               isPDFTextLayer: draft.rawTextIsPDFTextLayer))
                    }
                }

                if !visibleWarnings.isEmpty {
                    Section("Anh kiểm tra giúp") {
                        ForEach(visibleWarnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle.fill")
                                .font(.callout)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                // V3 (Pha 4, §7): pill hiện diện trường — mức dữ
                // liệu tối thiểu để anh thấy ngay trường nào bộ đọc
                // KHÔNG tìm thấy trên tờ này (không suy, không điền).
                Section("Trường đọc được") {
                    HStack(spacing: 6) {
                        presencePill("Tiệm", draft.result.vendor != nil)
                        presencePill("Ngày", draft.result.date != nil)
                        presencePill("Tạm tính", draft.result.subtotalCents != nil)
                        presencePill("Thuế", !draft.result.taxes.isEmpty)
                        presencePill("Tổng", draft.result.totalCents != nil)
                        presencePill("Thẻ", draft.result.cardLast4 != nil)
                    }
                }

                // V3 (Pha 4): gợi ý đối chiếu của F5 — bộ đọc KHÔNG
                // tự áp các tổ hợp này (luật không bịa số); trình để
                // anh cân nhắc khi sửa tay ở mục Thông tin dưới.
                if let report = draft.reconcileReport,
                   !report.suggestions.isEmpty {
                    Section("Gợi ý đối chiếu (chưa áp dụng)") {
                        ForEach(Array(report.suggestions.enumerated()),
                                id: \.offset) { _, solution in
                            ForEach(Array(solution.enumerated()),
                                    id: \.offset) { _, fix in
                                Text("Món #\(fix.itemIndex + 1): \(fix.field.rawValue) \(fix.oldValue.map { formatMoney(cents: $0) } ?? "—") → \(formatMoney(cents: fix.newValue)) [kênh \(fix.channel.rawValue)]")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Thông tin đọc được") {
                    TextField("Tiệm / Vendor", text: $vendorText)
                    DatePicker("Ngày", selection: $dateValue, displayedComponents: [.date, .hourAndMinute])
                    if dateWasMissing {
                        // C8-FIX: nói thẳng ngày đang hiện là
                        // ngày TẠM — bản cũ im lặng lưu ngày hôm
                        // nay như ngày hoá đơn thật.
                        Text("⚠ Bộ đọc không tìm thấy ngày trên tờ này — ngày đang để tạm là hôm nay. Anh sửa lại đúng ngày trên tờ; nếu cứ để vậy thì khi lưu, hoá đơn sẽ nằm ở trạng thái chờ duyệt.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    HStack {
                        Text("Subtotal")
                        if landingFields.contains("subtotal") {
                            estimateChip
                        }
                        Spacer()
                        moneyField($subtotalText)
                    }
                    HStack {
                        Text("Thuế (Tax)")
                        if landingFields.contains("taxes") {
                            estimateChip
                        }
                        Spacer()
                        moneyField($taxText)
                    }
                    HStack {
                        Text("TỔNG (Total)").bold()
                        if landingFields.contains("total") {
                            estimateChip
                        }
                        Spacer()
                        moneyField($totalText)
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DS.brand)
                    // P2-0/C-9: ô TIP chỉ hiện với tờ nhà
                    // hàng (giấy có TIP / GRATUITY / SUGGESTED
                    // TIP) — trước gói này app không có đường
                    // nào ghi tip, tổng đã trả luôn thiếu tip.
                    if showsTipField {
                        HStack {
                            Text("Tip (anh ghi thêm)")
                            Spacer()
                            moneyField($tipText)
                        }
                        Text("Ô TỔNG giữ nguyên tổng IN trên giấy; số đã trả của tờ = tổng in + tip.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if draft.result.totalConfidence > 0 {
                        Text("Độ tin cậy của tổng tiền: \(Int(draft.result.totalConfidence * 100))%")
                            .font(.caption)
                            .foregroundStyle(draft.result.totalConfidence < 0.85 ? .orange : .secondary)
                    }
                    // PHA 2 (L-47): khối hạ cánh bằng thuế — nói rõ
                    // số nào là ước tính, phép suy đã dùng, và cho
                    // anh đổi loại hàng để tính lại tại chỗ (tiệm
                    // chỉ gợi ý; anh chốt ở đây).
                    if !landingFields.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Một số số trên tờ này là ƯỚC TÍNH bằng cơ chế thuế (tờ khó đọc): \(landingDetail)")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            if !landingAreaText.isEmpty {
                                Text("Khu vực áp thuế: \(landingAreaText)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Picker("Loại hàng", selection: $landingCategory) {
                                Text("Hàng thường").tag(TaxCategory.general)
                                Text("Thực phẩm").tag(TaxCategory.grocery)
                                Text("Đồ ăn chế biến").tag(TaxCategory.prepared)
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: landingCategory) { _, newValue in
                                reland(category: newValue)
                            }
                            Text("Đổi loại hàng chỉ tính lại các số ƯỚC TÍNH; số đọc từ giấy không đổi.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    // WP5 bước 3: nguồn tên tiệm + gợi ý nấc 3 (WP5-SPEC mục
                    // 3/5/6) — nhãn nhỏ dưới các số tiền, KHÔNG che số; cảnh
                    // báo chữ vẫn đi qua mục "Anh kiểm tra giúp" ở trên như
                    // cũ, khối này chỉ cho anh thấy tên tiệm ĐẾN TỪ ĐÂU và
                    // bằng chứng liên hệ trích được để đối chiếu khi sửa tay.
                    if let sourceText = vendorSourceText(draft.result.vendorSource) {
                        Text(sourceText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if draft.result.vendor == nil, let suggestion = draft.result.vendorSuggestion {
                        Text("Chưa rõ tiệm — gợi ý từ món đặc trưng: \(suggestion) (chưa tự điền; đúng thì anh gõ vào ô Tiệm ở trên).")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if let address = draft.result.vendorAddress {
                        LabeledContent("Địa chỉ đọc được", value: address)
                    }
                    if let phone = draft.result.vendorPhone {
                        LabeledContent("Điện thoại đọc được", value: phone)
                    }
                    if let store = draft.result.storeNumber {
                        LabeledContent("Mã cửa hàng", value: store)
                    }
                    if let last4 = draft.result.cardLast4 {
                        LabeledContent("Thẻ đọc được", value: "\(draft.result.cardBrand ?? "Thẻ") •• \(last4)")
                    } else {
                        LabeledContent("Thẻ đọc được", value: "Không thấy dòng thẻ")
                    }
                    // V3 (Pha 4): provenance của các trường tiền —
                    // chỉ hiện khi số KHÔNG phải đọc thẳng (suy
                    // luận F5 / đọc lại vùng), để anh biết số nào
                    // cần mắt người xác nhận trước khi lưu.
                    ForEach(["subtotal", "taxes", "total"], id: \.self) { key in
                        if let prov = draft.provenance[key],
                           let caption = provenanceCaption(prov) {
                            Text("\(key == "subtotal" ? "Tạm tính" : key == "taxes" ? "Thuế" : "Tổng"): \(caption)")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Section("Phân loại — gợi ý theo thẻ, anh đổi được") {
                    if !reasonText.isEmpty {
                        Text(reasonText)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Picker("Loại", selection: $selectedKind) {
                        Text("CÁ NHÂN").tag(Classification.personal)
                        Text("BUSINESS").tag(Classification.business)
                        Text("CHƯA RÕ").tag(Classification.unknown)
                    }
                    .pickerStyle(.segmented)
                    Picker("Mục", selection: $selectedCategory) {
                        ForEach(categoryOptions, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    if selectedKind == .business {
                        BusinessPurposeField(text: $purposeText)
                    }
                }

                if !draft.result.items.isEmpty {
                    Section("Từng món đọc được (\(draft.result.items.count))") {
                        ForEach(Array(draft.result.items.enumerated()), id: \.offset) { index, item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name).font(.callout.weight(.medium))
                                    Text("SL \(item.qty)" + (item.taxFlag.map { " · cờ \($0)" } ?? ""))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    // V3 (Pha 4): provenance mức món
                                    // (tên bị sửa chữ theo từ điển /
                                    // tiền suy luận / khôi phục ROI).
                                    if let prov = draft.provenance["items[\(index)].name"],
                                       let caption = provenanceCaption(prov) {
                                        Text(caption)
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                    }
                                    if let prov = draft.provenance["items[\(index)].amount"],
                                       let caption = provenanceCaption(prov) {
                                        Text(caption)
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                    }
                                }
                                Spacer()
                                Text(formatMoney(optionalCents: item.amountCents))
                                    .font(.callout.weight(.semibold))
                                    .monospacedDigit()
                            }
                        }
                    }
                }

                Section {
                    // UI-2026-11-13: nút Lưu theo DesignSystem
                    // (xanh ngọc thương hiệu, full-width, bo 14)
                    // thay borderedProminent xanh dương mặc định.
                    // Hành động attemptSave() giữ nguyên.
                    Button { attemptSave() } label: {
                        Text("Lưu hoá đơn")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    Button("Huỷ, không lưu") {
                        // G3: kết thúc tường minh — cấm mọi lần
                        // ghi lớp sửa dở từ đây (kể cả tác vụ
                        // chống dội đang chờ), vì onDone xoá bản
                        // chụp nháp ngay sau đây.
                        finished = true
                        editSaveTask?.cancel()
                        // P2-0/B-7: huỷ TƯỜNG MINH thì xoá
                        // luôn file bằng chứng của bản nháp
                        // này (ảnh chính + file gốc kèm + hồ
                        // sơ chẩn đoán) — trước gói này chúng
                        // thành file mồ côi vĩnh viễn trong
                        // thư mục bằng chứng.
                        ImageStore.delete(fileName: draft.imageFileName)
                        ImageStore.delete(fileName: DiagnosticsStore.fileName(
                            forImageFileName: draft.imageFileName))
                        for name in draft.originalFileNames
                        where name != draft.imageFileName {
                            ImageStore.delete(fileName: name)
                        }
                        // S2: bản scan phẳng của bản nháp này
                        // cũng dọn cùng.
                        FlatScan.deleteFlat(forOriginal: draft.imageFileName)
                        for name in draft.originalFileNames {
                            FlatScan.deleteFlat(forOriginal: name)
                        }
                        onDone()
                    }
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.secondary)
                }
            }
            .dsListBackground()
            .navigationTitle("Kiểm Lại Hoá Đơn")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { applySuggestionOnce() }
            // G3 (luật bền hoá): MỌI thay đổi ở các ô sửa đều
            // lên lịch ghi lớp sửa dở vào bản chụp nháp — chốt
            // theo sự kiện rời rạc qua chống dội 0,6 giây yên
            // lặng (không ghi theo từng ký tự), cộng một lần
            // ghi ngay khi app vào nền. Từ đây sửa dở của anh
            // sống trên đĩa cùng bản nháp, khôi phục là dựng
            // lại đúng những gì anh đã sửa.
            .onChange(of: vendorText) { _, _ in scheduleReviewEditsSave() }
            .onChange(of: dateValue) { _, _ in scheduleReviewEditsSave() }
            .onChange(of: subtotalText) { _, _ in scheduleReviewEditsSave() }
            .onChange(of: taxText) { _, _ in scheduleReviewEditsSave() }
            .onChange(of: totalText) { _, _ in scheduleReviewEditsSave() }
            .onChange(of: selectedKind) { _, _ in scheduleReviewEditsSave() }
            .onChange(of: selectedCategory) { _, _ in scheduleReviewEditsSave() }
            .onChange(of: purposeText) { _, _ in scheduleReviewEditsSave() }
            .onChange(of: reasonText) { _, _ in scheduleReviewEditsSave() }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .background {
                    editSaveTask?.cancel()
                    persistReviewEdits()
                }
            }
            .alert("Có vẻ hoá đơn này đã có trong sổ", isPresented: $showDuplicateAlert) {
                Button("Vẫn lưu thêm") { save(ignoreDuplicate: true) }
                Button("Huỷ, không lưu", role: .cancel) {}
            } message: {
                // P2-0/C-6: chữ cảnh báo nói đúng LOẠI khoá
                // thực tế đã khớp (TC# / khoá yếu) — bản cũ
                // luôn nói "cùng mã TC#" kể cả khi khớp bằng
                // khoá yếu suy từ tiệm + ngày + tổng.
                Text("Mã chống trùng của tờ này khớp \(duplicateCount) hoá đơn đã lưu (\(dedupeKeyKindText(currentDedupeKey()))). Anh kiểm tra kẻo tính trùng 2 lần.")
            }
            .alert("Lưu không thành công", isPresented: $saveFailed) {
                Button("Đã hiểu", role: .cancel) {}
            } message: {
                Text("Hoá đơn CHƯA được lưu vào máy. Anh kiểm tra dung lượng trống rồi bấm Lưu lại — đừng rời màn này kẻo mất bản nháp.")
            }
        }
    }

    /// V3 (Pha 4): pill hiện diện trường đọc được — ✓ xanh khi bộ
    /// đọc tìm thấy trường, — xám khi không (không suy diễn).
    private func presencePill(_ label: String, _ present: Bool) -> some View {
        Text("\(present ? "✓" : "—") \(label)")
            .font(.caption2)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(present
                    ? Color.green.opacity(0.18)
                    : Color.gray.opacity(0.15)))
            .foregroundStyle(present ? .green : .secondary)
    }

    // MARK: - Pha 2: hạ cánh bằng thuế ở Kiểm Lại

    private var estimateChip: some View {
        Text("ước tính")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.15))
            .foregroundStyle(.orange)
            .clipShape(Capsule())
    }

    /// Bản đọc THÔ: bóc các đỉnh đã hạ cánh (theo provenance) để
    /// tính lại phép suy từ đúng các số đọc thật.
    static func strippedForRelanding(
        _ r: ParseResult, provenance: [String: FieldProvenance]
    ) -> ParseResult {
        var base = r
        if provenance["subtotal"]?.kind == "tax-landing" {
            base.subtotalCents = nil
        }
        if provenance["total"]?.kind == "tax-landing" {
            base.totalCents = nil
        }
        base.taxes = r.taxes.enumerated().compactMap { idx, line in
            provenance["tax[\(idx)]"]?.kind == "tax-landing" ? nil : line
        }
        return base
    }

    /// Mốc đối chiếu "anh có sửa tay không" cho một trường tiền:
    /// trường đang là ước tính → số hạ cánh GẦN NHẤT; còn lại →
    /// số máy đọc. Ước tính tính lại theo picker không bị ghi
    /// thành số anh nhập trong userEnteredFieldNames.
    private func landedBaselineCents(field: String,
                                     readValue: Int?) -> Int? {
        if landingFields.contains(field),
           let text = landingTexts[field] {
            return dollarsTextToCents(text)
        }
        return readValue
    }

    /// Anh đổi loại hàng → tính lại CHỈ các số ước tính từ neo đọc
    /// thật (số đọc từ giấy không bao giờ bị hàm này chạm tới, vì
    /// bản thô giữ nguyên chúng và lõi chỉ điền đỉnh thiếu).
    private func reland(category: TaxCategory) {
        let base = ReviewView.strippedForRelanding(
            draft.result, provenance: draft.provenance)
        var ctx = TaxLandingContextBuilder.make()
        ctx.forcedCategory = category
        guard let out = TaxLanding.evaluate(base, context: ctx),
              out.report.attempted else { return }
        let rep = out.report
        var fields = Set<String>()
        // Luật §3.7: số anh đã GÕ TAY đè lên ước tính thì KHÔNG
        // tính lại đè — ô nào còn giữ đúng chữ hạ cánh gần nhất
        // mới được viết lại; ô đã sửa tay rời khỏi landingFields
        // (từ đây là số của anh, hết nhãn ước tính).
        if rep.filledFields.contains("subtotal") {
            let newText = centsToDollarsText(out.result.subtotalCents)
            if subtotalText == landingTexts["subtotal"] {
                subtotalText = newText
                landingTexts["subtotal"] = newText
                fields.insert("subtotal")
            }
        }
        if rep.filledFields.contains(where: { $0.hasPrefix("tax[") }) {
            let newText = out.result.taxes.isEmpty
                ? ""
                : centsToDollarsText(out.result.taxTotalCents)
            if taxText == landingTexts["taxes"] {
                taxText = newText
                landingTexts["taxes"] = newText
                fields.insert("taxes")
            }
        }
        if rep.filledFields.contains("total") {
            let newText = centsToDollarsText(out.result.totalCents)
            if totalText == landingTexts["total"] {
                totalText = newText
                landingTexts["total"] = newText
                fields.insert("total")
            }
        }
        landingFields = fields
        landingTexts = landingTexts.filter { fields.contains($0.key) }
        landingDetail = rep.detail
        landingAppliedCategory = category
        if let areaID = rep.areaID,
           let area = ctx.table.portion(id: areaID),
           let rate = rep.ratePct {
            landingAreaText =
                "\(area.displayName) · \(TaxLanding.formatPct(rate))%"
        }
        DiagLog.log(.read, "THUẾ: Kiểm Lại đổi loại → "
            + "\(category.labelVI) — " + rep.detail)
    }

    private func moneyField(_ binding: Binding<String>) -> some View {
        TextField("0.00", text: binding)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .frame(width: 110)
    }

    /// G3: lên lịch ghi lớp sửa dở — chống dội 0,6 giây: mỗi
    /// thay đổi mới huỷ lần chờ trước, chỉ khi anh ngừng sửa
    /// đủ lâu mới ghi đĩa một lần. Các sự kiện rời rạc (đổi
    /// loại/mục bằng Picker, chọn ngày) cũng đi qua đường này
    /// nên tự thành "chốt theo sự kiện" sau 0,6 giây; app vào
    /// nền thì body ghi NGAY, không chờ hết giờ chống dội.
    private func scheduleReviewEditsSave() {
        guard !finished else { return }
        editSaveTask?.cancel()
        editSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            persistReviewEdits()
        }
    }

    /// G3: ghi lớp sửa dở hiện tại vào bản chụp nháp — bản
    /// chụp dựng lại từ `draft` gốc (không đổi) cộng lớp phủ
    /// là trạng thái các ô NGAY LÚC NÀY, ghi qua đúng kho
    /// PendingDraftStore nguyên tử. Sau khi màn đã kết thúc
    /// tường minh (finished) thì KHÔNG ghi nữa: bản chụp đã
    /// bị xoá ở onDone, ghi lại là làm sống lại việc đã xong.
    private func persistReviewEdits() {
        guard !finished else { return }
        var snapshot = PendingDraftSnapshot(draft: draft)
        snapshot.reviewEdits = ReviewEditsDTO(
            vendorText: vendorText,
            dateValue: dateValue,
            subtotalText: subtotalText,
            taxText: taxText,
            totalText: totalText,
            kindRaw: selectedKind.rawValue,
            category: selectedCategory,
            purposeText: purposeText,
            reasonText: reasonText,
            suggestionApplied: suggestionApplied,
            landingTexts: landingTexts,
            landingAppliedCategoryRaw: landingAppliedCategory?.rawValue,
            landingDetail: landingDetail,
            landingAreaText: landingAreaText)
        PendingDraftStore.save(snapshot)
    }

    /// L-2026-11-18-29: cảnh báo HIỂN THỊ và dùng để chốt
    /// trạng thái = cảnh báo của bộ đọc SAU hoà giải với sổ
    /// thẻ: đuôi khớp ĐÚNG một thẻ đã đăng ký thì cờ nghi ngờ
    /// đuôi thẻ bị gỡ (logic thuần ở ReceiptLogic — bộ đọc ở
    /// tầng dưới không biết sổ thẻ). Cảnh báo gốc trong
    /// draft.result KHÔNG bị sửa (hồ sơ chẩn đoán giữ nguyên).
    private var visibleWarnings: [String] {
        warningsClearingRegisteredCardFlags(
            draft.result.warnings,
            cardLast4: draft.result.cardLast4,
            registeredTails: Set(cardTails.map { $0.last4 }))
    }

    /// L-2026-11-18-29: requiresReview của báo cáo trọng tài
    /// (đọc "closed") được ReadPipeline suy từ warnings CHƯA
    /// hoà giải sổ thẻ (report.requiresReview = !warnings
    /// .isEmpty ở arbiterReport). Nếu sau hoà giải tờ không
    /// còn cảnh báo nào thì lý do giữ tờ ở Kiểm Lại đã mất —
    /// tính lại tại đây; các trạng thái khác (.ambiguous /
    /// .noSolution / .tooComplex / .partial) giữ nguyên phán
    /// quyết của pipeline.
    private var reportRequiresReview: Bool {
        guard let report = draft.reconcileReport,
              report.requiresReview else { return false }
        if report.status == .ok && visibleWarnings.isEmpty {
            return false
        }
        return true
    }

    private func applySuggestionOnce() {
        guard !suggestionApplied else { return }
        suggestionApplied = true
        let suggestion = suggestClassification(cardLast4: draft.result.cardLast4,
                                               cardBrand: draft.result.cardBrand,
                                               tails: cardTails)
        selectedKind = suggestion.0
        reasonText = suggestion.1
        if !Categories.list(for: selectedKind).contains(selectedCategory) {
            selectedCategory = Categories.defaultValue(for: selectedKind)
        }
        checkDuplicate()
    }

    /// P2-0/C-9: tờ có dấu hiệu nhà hàng không — giấy in
    /// TIP / GRATUITY / SUGGESTED TIP / TIP: thì hiện ô tip.
    private var showsTipField: Bool {
        let text = draft.result.rawText.uppercased()
        return text.contains("GRATUITY")
            || text.contains("SUGGESTED TIP")
            || text.contains("TIP:")
            || text.contains(" TIP ")
    }

    /// P2-0/C-6: khoá chống trùng HIỆU LỰC của tờ đang kiểm:
    /// khoá máy đọc (TC#) nếu có; chưa có thì khoá yếu
    /// GEN|tiệm|ngày|tổng dựng từ ĐÚNG các ô anh đang sửa
    /// (luật khoá yếu của bộ đọc cũ) — chỉ khi có cả tiệm và
    /// tổng. Kiểm trùng và lưu dùng chung khoá này.
    private func currentDedupeKey() -> String? {
        if let key = draft.result.dedupeKey { return key }
        let vendor = vendorText.trimmingCharacters(in: .whitespaces)
        guard !vendor.isEmpty,
              let total = dollarsTextToCents(totalText) else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "GEN|\(vendor)|\(formatter.string(from: dateValue))|\(total)"
    }

    /// P2-0/C-6: mô tả loại khoá cho chữ cảnh báo trùng.
    private func dedupeKeyKindText(_ key: String?) -> String {
        guard let key else { return "cùng mã chống trùng" }
        if key.hasPrefix("GEN|") {
            return "khoá yếu: cùng tiệm + ngày + tổng tiền — có thể là hai lần mua giống hệt"
        }
        if key.hasPrefix("SAMS-TC-") || key.hasPrefix("TC-") {
            return "cùng mã TC#"
        }
        return "cùng mã chống trùng của tiệm"
    }

    private func checkDuplicate() {
        guard let key = currentDedupeKey() else { duplicateCount = 0; return }
        // Lọc trong bộ nhớ thay cho #Predicate so sánh String? — loại bỏ điểm
        // rủi ro biên dịch với macro predicate trên cột optional (đã xử lý khi duyệt).
        // N2-FIX: bản cũ `(try? fetch) ?? []` biến lỗi đọc sổ
        // thành "không trùng" — cảnh báo trùng TC# biến mất
        // lặng lẽ. Nay lỗi được ghi cờ riêng: save() ép tờ vào
        // chờ duyệt thay vì giả vờ đã kiểm.
        do {
            let all = try modelContext.fetch(FetchDescriptor<Receipt>())
            duplicateCount = all.filter { $0.dedupeKey == key }.count
            duplicateCheckFailed = false
        } catch {
            duplicateCount = 0
            duplicateCheckFailed = true
        }
    }

    private func attemptSave() {
        checkDuplicate()
        if duplicateCount > 0 {
            showDuplicateAlert = true
        } else {
            save(ignoreDuplicate: false)
        }
    }

    private func save(ignoreDuplicate: Bool) {
        let receipt = Receipt()
        receipt.vendor = vendorText.trimmingCharacters(in: .whitespaces)
        receipt.date = dateValue
        receipt.subtotalCents = dollarsTextToCents(subtotalText)
        receipt.taxCents = dollarsTextToCents(taxText)
        receipt.totalCents = dollarsTextToCents(totalText)
        receipt.cardLast4 = draft.result.cardLast4
        receipt.cardBrand = draft.result.cardBrand
        receipt.classification = selectedKind
        receipt.classificationReason = reasonText
        receipt.category = selectedCategory
        receipt.businessPurpose = purposeText
        // P2-0/C-6: lưu khoá HIỆU LỰC (TC# của bộ đọc, hoặc
        // khoá yếu GEN| dựng từ các ô đã sửa khi bộ đọc
        // không có khoá) — trước gói này dedupeKey trên
        // đường v4 luôn nil.
        let effectiveKey = currentDedupeKey()
        receipt.dedupeKey = effectiveKey
        // P2-0/C-9: tip anh ghi -> lưu riêng; totalPrintedCents
        // chốt = tổng IN (ô TỔNG hiện tại) để amountPaidCents
        // = tổng in + tip đúng nghĩa.
        if let tip = dollarsTextToCents(tipText), tip > 0 {
            receipt.tipAmountCents = tip
            receipt.totalPrintedCents = receipt.totalCents
        }
        // P2-0 mục 15 (§2.2(5)): đóng dấu dòng Schedule C.
        receipt.scheduleCLine = Categories.scheduleCLine(
            forCategory: selectedCategory)
        receipt.vendorConfidence = draft.result.vendorConfidence
        receipt.dateConfidence = draft.result.dateConfidence
        receipt.totalConfidence = draft.result.totalConfidence
        receipt.imageFileName = draft.imageFileName
        receipt.ocrRawText = draft.result.rawText
        // --- WP2 bước 2: nối dây các trường mới (WP2-GATE, việc còn lại #1) ---
        receipt.stableID = UUID().uuidString
        receipt.sourceType = draft.sourceType
        // Có đuôi thẻ đọc được -> trả bằng thẻ; không có -> .unknown.
        // TUYỆT ĐỐI không đoán .cash: "không thấy dòng thẻ" khác hẳn "trả tiền mặt".
        receipt.paymentMethod = (draft.result.cardLast4?.isEmpty == false) ? .card : .unknown
        // Mã giao dịch tách khỏi khoá chống trùng: dedupeKey dạng "SAMS-TC-<số>"
        // hoặc "TC-<số>" thì phần số chính là transactionRef; khoá yếu dạng
        // "GEN|..." không chứa mã giao dịch -> để nil, không bịa.
        if let key = effectiveKey {
            if key.hasPrefix("SAMS-TC-") {
                receipt.transactionRef = String(key.dropFirst("SAMS-TC-".count))
            } else if key.hasPrefix("TC-") {
                receipt.transactionRef = String(key.dropFirst("TC-".count))
            }
        }
        receipt.parserVersion = currentParserVersion
        // --- WP3: nối dây nguồn nạp file ---
        // Tên file gốc anh đã chọn (chỉ đường Files mới có) + danh sách file
        // bằng chứng gốc: PDF nạp vào giữ file PDF nguyên byte trong
        // ReceiptImages và tên của nó nằm ở đây (kèm imageFileName khi lớp
        // chữ đọc thẳng). Đường camera/Photos: cả hai để trống/nil như cũ.
        receipt.sourceFileName = draft.sourceFileName
        receipt.originalImageFileNames = draft.originalFileNames
        receipt.rawTextFromPDFTextLayer = draft.rawTextIsPDFTextLayer
        // --- WP5 bước 3: nối dây hạ cánh tiệm (WP5-SPEC mục 4) ---
        // Địa chỉ/điện thoại/mã cửa hàng là bằng chứng TRÍCH NGUYÊN VĂN từ
        // giấy (extractVendorContact ở Parser) — lưu đúng như đọc được,
        // không suy từ tên tiệm anh sửa tay ở ô "Tiệm / Vendor" phía trên:
        // anh đổi tên tiệm thì địa chỉ trên giấy vẫn là địa chỉ trên giấy.
        // Model WP2: vendorAddress là String (mặc định "") nên nil của
        // ParseResult hạ cánh thành ""; hai trường còn lại optional khớp.
        receipt.vendorAddress = draft.result.vendorAddress ?? ""
        receipt.vendorPhone = draft.result.vendorPhone
        receipt.storeNumber = draft.result.storeNumber
        // Dòng thuế riêng: CHỈ lưu khi tổng thuế anh đã duyệt ở màn Kiểm Lại còn
        // khớp Σ dòng thuế máy đọc. Anh sửa lệch đi thì giữ tổng gộp (taxCents
        // ở trên) và KHÔNG lưu chi tiết dòng — lưu chi tiết cũ cạnh tổng mới sẽ
        // bịa ra cơ cấu thuế không còn đúng với số anh đã chốt.
        let persistTaxLines = !draft.result.taxes.isEmpty
            && dollarsTextToCents(taxText) == draft.result.taxTotalCents
        if persistTaxLines {
            // Đồng bộ ngược chân tương thích cho màn cũ: taxCents = Σ taxLines
            // (bằng đúng số anh đã duyệt theo điều kiện ở trên).
            receipt.taxCents = draft.result.taxTotalCents
        }
        // P2-0 (mục nối duplicateOf): anh chọn "Vẫn lưu
        // thêm" một tờ trùng -> tờ mới thành BẢN TRÙNG có
        // danh tính: trỏ về bản gốc SỚM NHẤT cùng khoá và
        // bị loại khỏi tổng. Đọc sổ lỗi ở bước này thì gắn
        // cờ ép chờ duyệt (như duplicateCheckFailed) — tờ
        // vẫn lưu nhưng không giả vờ đã nối xong.
        var duplicateLinkFailed = false
        if ignoreDuplicate && duplicateCount > 0, let effectiveKey {
            do {
                let all = try modelContext.fetch(FetchDescriptor<Receipt>())
                let original = all
                    .filter { $0.dedupeKey == effectiveKey && !$0.stableID.isEmpty }
                    .sorted { $0.createdAt < $1.createdAt }
                    .first
                if let original {
                    receipt.duplicateOfStableID = original.stableID
                    receipt.excludedFromTotals = true
                }
            } catch {
                duplicateLinkFailed = true
            }
        }
        // P2-0 mục 16 (F5): tên các trường ANH SỬA TAY so
        // với kết quả máy đọc (phân biệt số máy đọc / số anh
        // nhập cho accountant truy vết).
        var enteredNames: [String] = []
        if vendorText.trimmingCharacters(in: .whitespaces)
            != (draft.result.vendor ?? "") {
            enteredNames.append("vendor")
        }
        if dateValue != dateDefault { enteredNames.append("date") }
        // PHA 2: trường đang mang ước tính hạ cánh thì mốc đối
        // chiếu là số hạ cánh gần nhất (landedBaselineCents).
        if receipt.subtotalCents != landedBaselineCents(
            field: "subtotal", readValue: draft.result.subtotalCents) {
            enteredNames.append("subtotal")
        }
        if receipt.taxCents != landedBaselineCents(
            field: "taxes",
            readValue: draft.result.taxes.isEmpty
                ? nil : draft.result.taxTotalCents) {
            enteredNames.append("tax")
        }
        if receipt.totalCents != landedBaselineCents(
            field: "total", readValue: draft.result.totalCents) {
            enteredNames.append("total")
        }
        let kindSuggestion = suggestClassification(
            cardLast4: draft.result.cardLast4,
            cardBrand: draft.result.cardBrand,
            tails: cardTails)
        if selectedKind != kindSuggestion.0 {
            enteredNames.append("classification")
        }
        if selectedCategory != Categories.defaultValue(for: selectedKind) {
            enteredNames.append("category")
        }
        if selectedKind == .business
            && !purposeText.trimmingCharacters(in: .whitespaces).isEmpty {
            enteredNames.append("businessPurpose")
        }
        receipt.userEnteredFieldNames = enteredNames
        // Kỷ luật Hộp Chờ: còn cờ trên SỐ ĐÃ SỬA -> chờ duyệt.
        // P2-0/C-3: điều kiện cũ "!draft.result.warnings
        // .isEmpty" đo cảnh báo của BẢN ĐỌC GỐC — anh sửa
        // xong hết ở Kiểm Lại mà tờ vẫn bị giữ oan ở Hộp
        // Chờ. Nay trạng thái suy từ BỘ CỜ chạy trên đúng
        // các số anh vừa chốt (cùng bộ cờ của tờ đã lưu:
        // lệch món/tổng, thiếu tổng, thiếu mục đích,
        // chưa phân loại, thiếu ảnh gốc, chưa rõ tiệm).
        // V3 (Pha 4): cộng hai điều kiện của đường đọc mới — trọng
        // tài F5 đòi kiểm lại, hoặc ghi chẩn đoán thất bại (hợp
        // đồng fail-closed: không hồ sơ = không "sạch").
        // C8-FIX: ngày đang lưu là ngày TẠM (bộ đọc trượt ngày
        // và anh không sửa) — ngày đó không phải bằng chứng;
        // tờ phải chờ duyệt để anh chốt lại ngày đúng sau.
        let dateIsUntouchedDefault = dateWasMissing && dateValue == dateDefault
        let kindTag: ReceiptKindTag
        switch selectedKind {
        case .personal: kindTag = .personal
        case .business: kindTag = .business
        case .unknown: kindTag = .unknown
        }
        let editedFlags = ReceiptLogic.flags(for: ReceiptFlagInput(
            subtotalCents: receipt.subtotalCents,
            itemAmountCents: draft.result.items.map { $0.amountCents },
            totalCents: receipt.totalCents,
            taxCents: receipt.taxCents,
            kind: kindTag,
            businessPurpose: purposeText,
            hasOriginalImage: ReceiptLogic.hasLoadableOriginal(
                fileNames: [draft.imageFileName] + draft.originalFileNames,
                isLoadable: { ImageStore.load(fileName: $0) != nil }),
            vendor: vendorText.trimmingCharacters(in: .whitespaces)))
        let stillNeedsReview = !editedFlags.isEmpty
            || reportRequiresReview
            || draft.diagnosticsWriteFailed
            || dateIsUntouchedDefault
            || duplicateCheckFailed
            || duplicateLinkFailed
        receipt.status = stillNeedsReview ? .needsReview : .reviewed
        // P2-0 mục 16 (F4): đóng dấu thời điểm duyệt.
        if receipt.status == .reviewed {
            receipt.reviewedAt = Date()
        }

        modelContext.insert(receipt)
        for (index, parsed) in draft.result.items.enumerated() {
            let item = LineItem()
            item.name = parsed.name
            item.qty = parsed.qty
            item.unitPriceCents = parsed.unitPriceCents
            item.amountCents = parsed.amountCents
            item.taxFlag = parsed.taxFlag
            item.itemCode = parsed.itemCode
            item.sortIndex = index
            item.receipt = receipt
            modelContext.insert(item)
        }
        // WP2 bước 2: ghi các dòng thuế riêng (TaxLine) cùng quan hệ cascade
        // như LineItem — chỉ khi persistTaxLines đã chốt ở trên.
        if persistTaxLines {
            for (index, parsedTax) in draft.result.taxes.enumerated() {
                let line = TaxLine()
                line.label = parsedTax.label
                line.rateText = parsedTax.rateText
                line.amountCents = parsedTax.amountCents
                line.sortIndex = index
                line.receipt = receipt
                modelContext.insert(line)
            }
        }
        // N2-FIX (điểm tệ nhất của FULL-REVIEW): bản cũ
        // `try? save` rồi đóng màn vô điều kiện — lưu hỏng là
        // mất bản nháp mà anh tưởng đã lưu xong. Nay: lưu hỏng
        // -> rollback (dọn bản ghi chưa lưu để bấm Lưu lại
        // không sinh tờ trùng ma) + alert + Ở LẠI màn Kiểm Lại.
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            saveFailed = true
            return
        }
        // G3: lưu thành công = kết thúc tường minh — đóng cổng
        // ghi lớp sửa dở TRƯỚC onDone (nơi ScanView xoá bản
        // chụp), kẻo tác vụ chống dội đang chờ ghi lại bản chụp
        // của một tờ đã lưu xong.
        finished = true
        editSaveTask?.cancel()
        // PHA 2 (L-47): học hồ sơ tiệm từ tờ vừa duyệt — ZIP từ
        // địa chỉ đã lưu; loại hàng = loại đang chốt ở Kiểm Lại
        // (picker hạ cánh khi có hạ cánh, không thì phân loại từ
        // món đọc được; không chắc thì để trống, không bịa).
        StoreProfiles.learn(
            key: TaxLanding.profileKey(
                vendorKey: draft.result.vendorKey,
                vendor: receipt.vendor),
            zip: TaxLanding.extractZIP(from: receipt.vendorAddress),
            category: landingAppliedCategory
                ?? TaxLanding.classifyCategory(items: draft.result.items))
        onDone()
        // P2-1: gương thư mục Files chạy nền sau mỗi lần lưu
        // hoá đơn mới thành công (lớp phụ — không chặn luồng
        // lưu, không ném lỗi về màn Kiểm Lại).
        MirrorSync.requestSync(using: modelContext)
        DriveSync.requestSync(using: modelContext)
    }
}
