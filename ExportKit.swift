// ExportKit.swift — A2 + A3 (vòng 2): lõi XUẤT thuần Foundation.
//
// Harness biên dịch file này để kiểm bằng Swift thật:
// - ZipWriter / ZipReader: ZIP phương thức STORED (không nén — ảnh JPEG
//   và PDF vốn đã nén), byte của file vào ZIP NGUYÊN VẸN; CRC-32 kiểm
//   từng mục. Harness còn đối chiếu bằng /usr/bin/unzip của macOS.
// - CSV theo RFC 4180, tiền in bằng PHÉP NGUYÊN trên cent (không
//   Double), luôn có 2 chữ số lẻ.
// - Mục lục file gốc cho kế toán (muc-luc.csv): tờ THIẾU file gốc được
//   ĐẾM và ĐỌC TÊN ngay trong mục lục, không bao giờ bị bỏ im lặng.
// - TaxReportMath: phép tính của màn Báo Cáo Thuế (một nguồn — màn
//   Báo Cáo và Tax Pack cùng gọi), dựa trên luật tờ chính thức A7.
//
// Không file nào trong đây đọc/ghi SwiftData; tầng app dựng các giá
// trị đầu vào (ExportReceiptInput) từ bản ghi rồi giao xuống đây.

import Foundation

// MARK: - CRC-32 (IEEE 802.3, đa thức 0xEDB88320)

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 {
            c = (c & 1) != 0 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1)
        }
        return c
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            for b in buf {
                crc = table[Int((crc ^ UInt32(b)) & 0xFF)] ^ (crc >> 8)
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}

// MARK: - ZIP (STORED)

enum ZipError: Error, Equatable {
    case tooLarge          // vượt giới hạn ZIP cổ điển (4 GiB / 65535 mục)
    case duplicateName(String)
    case badName(String)
    case io(String)
    case malformed(String)
}

/// Ghi ZIP ra FILE từng mục một (không giữ cả gói trong bộ nhớ).
final class ZipWriter {
    private struct Central {
        var name: Data
        var crc: UInt32
        var size: UInt32
        var offset: UInt32
    }
    private let handle: FileHandle
    private var offset: UInt64 = 0
    private var centrals: [Central] = []
    private var names = Set<String>()
    private let dosTime: UInt16
    private let dosDate: UInt16
    private var closed = false

    /// - Parameter date: mốc ghi vào mục ZIP (giờ địa phương kiểu DOS).
    init(url: URL, date: Date = Date()) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        guard let h = try? FileHandle(forWritingTo: url) else {
            throw ZipError.io("không mở được file ZIP để ghi")
        }
        handle = h
        let cal = Calendar(identifier: .gregorian)
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year: Int = max(1980, min(2107, c.year ?? 1980))
        let month: Int = c.month ?? 1
        let day: Int = c.day ?? 1
        let hour: Int = c.hour ?? 0
        let minute: Int = c.minute ?? 0
        let second: Int = c.second ?? 0
        let datePart: Int = ((year - 1980) << 9) | (month << 5) | day
        let timePart: Int = (hour << 11) | (minute << 5) | (second / 2)
        dosDate = UInt16(truncatingIfNeeded: datePart)
        dosTime = UInt16(truncatingIfNeeded: timePart)
    }

    deinit { if !closed { try? handle.close() } }

    static func isSafeEntryName(_ name: String) -> Bool {
        !name.isEmpty && !name.hasPrefix("/") && !name.contains("\\")
            && !name.split(separator: "/", omittingEmptySubsequences: false)
                .contains(where: { $0 == ".." || $0.isEmpty })
    }

    func add(name: String, data: Data) throws {
        guard ZipWriter.isSafeEntryName(name) else { throw ZipError.badName(name) }
        guard names.insert(name).inserted else { throw ZipError.duplicateName(name) }
        let nameData = Data(name.utf8)
        let header = 30 + UInt64(nameData.count)
        guard centrals.count < 65_535,
              data.count < Int(UInt32.max),
              offset + header + UInt64(data.count) < UInt64(UInt32.max) else {
            throw ZipError.tooLarge
        }
        let crc = CRC32.checksum(data)
        var h = Data()
        h.appendLE(UInt32(0x0403_4B50))
        h.appendLE(UInt16(20))            // version needed
        h.appendLE(UInt16(0x0800))        // bit 11: tên UTF-8
        h.appendLE(UInt16(0))             // STORED
        h.appendLE(dosTime)
        h.appendLE(dosDate)
        h.appendLE(crc)
        h.appendLE(UInt32(data.count))
        h.appendLE(UInt32(data.count))
        h.appendLE(UInt16(nameData.count))
        h.appendLE(UInt16(0))
        h.append(nameData)
        do {
            try handle.write(contentsOf: h)
            try handle.write(contentsOf: data)
        } catch {
            throw ZipError.io("ghi mục \(name) thất bại")
        }
        centrals.append(Central(name: nameData, crc: crc,
                                size: UInt32(data.count), offset: UInt32(offset)))
        offset += header + UInt64(data.count)
    }

    func finish() throws {
        var cd = Data()
        for c in centrals {
            cd.appendLE(UInt32(0x0201_4B50))
            cd.appendLE(UInt16(20))       // version made by
            cd.appendLE(UInt16(20))       // version needed
            cd.appendLE(UInt16(0x0800))
            cd.appendLE(UInt16(0))
            cd.appendLE(dosTime)
            cd.appendLE(dosDate)
            cd.appendLE(c.crc)
            cd.appendLE(c.size)
            cd.appendLE(c.size)
            cd.appendLE(UInt16(c.name.count))
            cd.appendLE(UInt16(0))        // extra
            cd.appendLE(UInt16(0))        // comment
            cd.appendLE(UInt16(0))        // disk
            cd.appendLE(UInt16(0))        // internal attr
            cd.appendLE(UInt32(0))        // external attr
            cd.appendLE(c.offset)
            cd.append(c.name)
        }
        guard offset + UInt64(cd.count) < UInt64(UInt32.max) else { throw ZipError.tooLarge }
        var end = Data()
        end.appendLE(UInt32(0x0605_4B50))
        end.appendLE(UInt16(0))
        end.appendLE(UInt16(0))
        end.appendLE(UInt16(centrals.count))
        end.appendLE(UInt16(centrals.count))
        end.appendLE(UInt32(cd.count))
        end.appendLE(UInt32(offset))
        end.appendLE(UInt16(0))
        do {
            try handle.write(contentsOf: cd)
            try handle.write(contentsOf: end)
            try handle.close()
            closed = true
        } catch {
            throw ZipError.io("đóng file ZIP thất bại")
        }
    }
}

/// Đọc ZIP STORED do ZipWriter ghi — để KIỂM KHỨ HỒI ngay sau khi xuất
/// (đọc lại từng mục, so CRC + byte) trước khi đưa file cho anh.
enum ZipReader {
    struct Entry: Equatable { var name: String; var data: Data }

    static func entries(of zip: Data) throws -> [Entry] {
        var out: [Entry] = []
        try forEachEntry(of: zip) { out.append(Entry(name: $0, data: $1)) }
        return out
    }

    /// Duyệt từng mục (CRC đã kiểm) — chỉ giữ MỘT mục trong bộ nhớ
    /// mỗi lần; zip nên được nạp kiểu ánh xạ (.alwaysMapped).
    static func forEachEntry(of zip: Data,
                             _ body: (String, Data) throws -> Void) throws {
        try zip.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Void in
            let n = raw.count
            func u16(_ i: Int) -> Int { Int(raw[i]) | Int(raw[i + 1]) << 8 }
            func u32(_ i: Int) -> Int { u16(i) | u16(i + 2) << 16 }
            guard n >= 22 else { throw ZipError.malformed("quá ngắn") }
            var eocd = -1
            var i = n - 22
            while i >= max(0, n - 22 - 65_535) {
                if u32(i) == 0x0605_4B50 { eocd = i; break }
                i -= 1
            }
            guard eocd >= 0 else { throw ZipError.malformed("không thấy EOCD") }
            let count = u16(eocd + 10)
            var p = u32(eocd + 16)
            for _ in 0..<count {
                guard p + 46 <= n, u32(p) == 0x0201_4B50 else {
                    throw ZipError.malformed("thư mục trung tâm hỏng")
                }
                let method = u16(p + 10)
                let crc = UInt32(truncatingIfNeeded: u32(p + 16))
                let csize = u32(p + 20)
                let nlen = u16(p + 28), xlen = u16(p + 30), klen = u16(p + 32)
                let local = u32(p + 42)
                guard method == 0, p + 46 + nlen <= n else {
                    throw ZipError.malformed("mục không phải STORED")
                }
                let name = String(decoding: UnsafeRawBufferPointer(
                    rebasing: raw[(p + 46)..<(p + 46 + nlen)]), as: UTF8.self)
                guard local + 30 <= n, u32(local) == 0x0403_4B50 else {
                    throw ZipError.malformed("header cục bộ hỏng: \(name)")
                }
                let start = local + 30 + u16(local + 26) + u16(local + 28)
                guard start + csize <= n else { throw ZipError.malformed("cắt cụt: \(name)") }
                let data = Data(UnsafeRawBufferPointer(rebasing: raw[start..<(start + csize)]))
                guard CRC32.checksum(data) == crc else { throw ZipError.malformed("sai CRC: \(name)") }
                try body(name, data)
                p += 46 + nlen + xlen + klen
            }
        }
    }
}

extension Data {
    mutating func appendLE(_ v: UInt16) {
        append(UInt8(v & 0xFF)); append(UInt8(v >> 8))
    }
    mutating func appendLE(_ v: UInt32) {
        appendLE(UInt16(v & 0xFFFF)); appendLE(UInt16(v >> 16))
    }
}

// MARK: - CSV + tiền

enum ExportCSV {
    /// RFC 4180: bọc nháy kép khi có , " CR LF; nháy kép nhân đôi.
    static func field(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") || s.contains("\r") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }

    static func row(_ cells: [String]) -> String {
        cells.map(field).joined(separator: ",")
    }

    /// Cent -> "1234.05" / "-0.50" bằng phép NGUYÊN. nil -> "".
    static func dollars(_ cents: Int?) -> String {
        guard let cents else { return "" }
        let sign = cents < 0 ? "-" : ""
        let m = cents.magnitude
        let frac = m % 100
        return "\(sign)\(m / 100).\(frac < 10 ? "0" : "")\(frac)"
    }

    /// Ngược của dollars (để kiểm khứ hồi tổng). "" -> nil.
    static func cents(fromDollars s: String) -> Int? {
        guard !s.isEmpty else { return nil }
        let neg = s.hasPrefix("-")
        let body = neg ? String(s.dropFirst()) : s
        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[1].count == 2,
              let whole = Int(parts[0]), let frac = Int(parts[1]) else { return nil }
        let v = whole * 100 + frac
        return neg ? -v : v
    }

    /// Tài liệu CSV: BOM UTF-8 (Excel đọc đúng dấu tiếng Việt) + CRLF.
    static func document(header: [String], rows: [[String]]) -> Data {
        var text = "\u{FEFF}" + row(header) + "\r\n"
        for r in rows { text += row(r) + "\r\n" }
        return Data(text.utf8)
    }

    /// Tách tài liệu do document(...) sinh (bỏ BOM, tôn trọng nháy kép).
    static func parse(_ data: Data) -> [[String]] {
        var text = String(decoding: data, as: UTF8.self)
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        var rows: [[String]] = []
        var row: [String] = []
        var cell = ""
        var quoted = false
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if quoted {
                if ch == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" { cell.append("\""); i += 1 }
                    else { quoted = false }
                } else { cell.append(ch) }
            } else if ch == "\"" {
                quoted = true
            } else if ch == "," {
                row.append(cell); cell = ""
            } else if ch == "\r\n" || ch == "\n" || ch == "\r" {
                row.append(cell); rows.append(row); row = []; cell = ""
            } else {
                cell.append(ch)
            }
            i += 1
        }
        if !cell.isEmpty || !row.isEmpty { row.append(cell); rows.append(row) }
        return rows
    }
}

// MARK: - Đầu vào xuất (giá trị thuần, tầng app dựng từ Receipt)

struct ExportFileRef: Equatable {
    /// Tên file trong kho ảnh trên máy.
    var localName: String
    /// Byte của file; nil = file KHÔNG có / không đọc được trên máy.
    var data: Data?
}

struct ExportReceiptInput: Equatable {
    var id: String                 // danh tính thư mục gương (ổn định)
    var date: Date
    var reportYear: Int            // năm theo ĐÚNG luật màn Báo Cáo
    var vendor: String
    var kindRaw: String            // classificationRaw nguyên văn
    var kindNormalized: String     // "personal" | "business" | "unknown"
    var isOfficial: Bool           // luật A7
    var isPending: Bool            // luật A7
    var isNeedsReview: Bool
    var category: String
    var scheduleCLine: String?     // CHỈ giá trị đã lưu — không suy
    var subtotalCents: Int?
    var taxCents: Int?
    var totalCents: Int?
    var countedCents: Int          // luật A7 (amountPaidCents ?? 0)
    var tipCents: Int?
    var cardLast4: String?
    var businessPurpose: String
    /// Trường đang là số ƯỚC TÍNH hạ cánh thuế ("subtotal"/"tax"/"total").
    var estimatedFields: Set<String>
    /// false = không còn hồ sơ đọc để biết nguồn số.
    var provenanceKnown: Bool
    var originals: [ExportFileRef]
}

// MARK: - Luật nhãn ƯỚC TÍNH (A3)

enum EstimateRule {
    /// Hồ sơ đọc (.ocrdiag) KHÔNG ghi trường nào được hạ cánh: nó giữ
    /// bản đọc TRƯỚC hạ cánh (diag.parse) + cờ "tax-landing" ở outcome.
    /// Luật THẬN TRỌNG: tờ có cờ hạ cánh -> mọi trường trong bộ ba
    /// (subtotal/tax/total) mà bản đọc thô KHÔNG có và anh KHÔNG gõ
    /// tay là ƯỚC TÍNH. Có thể dán nhãn thừa (trường suy bằng đối
    /// chiếu), KHÔNG BAO GIỜ dán thiếu cho số hạ cánh.
    static func estimatedFields(landingFlag: Bool,
                                rawSubtotalMissing: Bool,
                                rawTaxMissing: Bool,
                                rawTotalMissing: Bool,
                                userEntered: [String]) -> Set<String> {
        guard landingFlag else { return [] }
        var out = Set<String>()
        if rawSubtotalMissing { out.insert("subtotal") }
        if rawTaxMissing { out.insert("tax") }
        if rawTotalMissing { out.insert("total") }
        return out.subtracting(userEntered)
    }

    static let label = "ƯỚC TÍNH"
}

// MARK: - A2: gói file gốc cho kế toán

enum AccountantExport {
    static let indexName = "muc-luc.csv"

    static let indexHeader = [
        "stt", "ma_to", "ngay", "tiem", "phan_loai", "trang_thai", "chinh_thuc",
        "tong_in", "so_da_tra", "the", "schedule_c", "file_goc_tren_may",
        "file_trong_zip", "tinh_trang_file",
    ]

    struct Summary: Equatable {
        var receipts = 0
        var filesIncluded = 0
        var filesMissing = 0
        var receiptsWithMissing: [String] = []
    }

    /// Tên an toàn ASCII cho đường dẫn trong ZIP.
    static func slug(_ s: String, max: Int = 24) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive],
                               locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "đ", with: "d")
        var out = ""
        for ch in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(ch) && ch.isASCII { out.unicodeScalars.append(ch) }
            else if !out.hasSuffix("-") { out.append("-") }
        }
        let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let cut = String(trimmed.prefix(max))
        return cut.isEmpty ? "khong-ro" : cut.uppercased()
    }

    static func isoDay(_ d: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    static func entryName(folder: String, receipt: ExportReceiptInput,
                          index: Int, localName: String) -> String {
        let ext = (localName as NSString).pathExtension.lowercased()
        let short = String(receipt.id.replacingOccurrences(of: "pre2-", with: "").prefix(8))
        return "\(folder)/\(isoDay(receipt.date))_\(slug(receipt.vendor))_\(short)_\(index + 1)."
            + (ext.isEmpty ? "jpg" : ext)
    }

    /// Ghi mục lục + mọi file gốc CÓ vào `zip` dưới `folder/`.
    /// File thiếu: một dòng THIẾU trong mục lục + đếm ở dòng TỔNG.
    @discardableResult
    static func write(_ receipts: [ExportReceiptInput], into zip: ZipWriter,
                      folder: String = "goc", indexPath: String = indexName) throws -> Summary {
        var s = Summary()
        var rows: [[String]] = []
        for (n, r) in receipts.enumerated() {
            s.receipts += 1
            let base = [String(n + 1), r.id, isoDay(r.date), r.vendor, r.kindNormalized,
                        r.isNeedsReview ? "cho_duyet" : "da_duyet",
                        r.isOfficial ? "co" : "khong",
                        ExportCSV.dollars(r.totalCents), ExportCSV.dollars(r.countedCents),
                        r.cardLast4 ?? "", r.scheduleCLine ?? ""]
            if r.originals.isEmpty {
                s.filesMissing += 1
                s.receiptsWithMissing.append(r.id)
                rows.append(base + ["", "", "THIEU — to khong ghi ten file goc nao"])
                continue
            }
            var missingHere = false
            for (k, f) in r.originals.enumerated() {
                if let data = f.data {
                    let name = entryName(folder: folder, receipt: r, index: k, localName: f.localName)
                    try zip.add(name: name, data: data)
                    s.filesIncluded += 1
                    rows.append(base + [f.localName, name, "co"])
                } else {
                    s.filesMissing += 1
                    missingHere = true
                    rows.append(base + [f.localName, "", "THIEU — khong co tren may"])
                }
            }
            if missingHere { s.receiptsWithMissing.append(r.id) }
        }
        rows.append(["TONG", "", "", "\(s.receipts) to", "", "", "",
                     "", "", "", "", "",
                     "\(s.filesIncluded) file trong zip",
                     "\(s.filesMissing) file THIEU (\(s.receiptsWithMissing.count) to)"])
        try zip.add(name: indexPath, data: ExportCSV.document(header: indexHeader, rows: rows))
        return s
    }
}

// MARK: - A3: phép tính màn Báo Cáo Thuế (MỘT nguồn) + Tax Pack CSV

enum TaxReportMath {
    struct Totals: Equatable {
        var personal = 0
        var business = 0
        var unknown = 0
        var pending = 0
        var count = 0
        var needsReviewCount = 0
    }

    struct CategoryRow: Equatable {
        var key: String
        var name: String
        var kindNormalized: String
        var total: Int
        var count: Int
    }

    static func yearRows(_ all: [ExportReceiptInput], year: Int) -> [ExportReceiptInput] {
        all.filter { $0.reportYear == year }
    }

    static func totals(_ rows: [ExportReceiptInput]) -> Totals {
        var t = Totals()
        t.count = rows.count
        for r in rows {
            if r.isOfficial {
                switch r.kindNormalized {
                case "personal": t.personal += r.countedCents
                case "business": t.business += r.countedCents
                default: t.unknown += r.countedCents
                }
            }
            if r.isPending { t.pending += r.countedCents }
            if r.isNeedsReview { t.needsReviewCount += 1 }
        }
        return t
    }

    /// A12(iii) (vòng 2, WP9 §4.13): số tờ còn THIẾU để năm thuế
    /// "sẵn sàng" = tờ chờ duyệt (luật A7, không tính tờ đã loại khỏi
    /// tổng) + tờ chính thức chưa phân loại Cá nhân/Business. Hai tập
    /// rời nhau (chính thức ≠ chờ duyệt). Chỉ để CẢNH BÁO.
    static func readinessGapCount(_ rows: [ExportReceiptInput]) -> Int {
        rows.filter { $0.isPending || ($0.isOfficial && $0.kindNormalized == "unknown") }.count
    }

    /// Đúng thuật toán categoryRows cũ của ReportsView: chỉ tờ chính
    /// thức, bỏ loại "unknown"; khoá "<classificationRaw>|<mục|Khác>";
    /// business lên trước, rồi tổng giảm dần.
    static func categoryRows(_ rows: [ExportReceiptInput]) -> [CategoryRow] {
        var grouped: [String: (String, Int, Int)] = [:]
        for r in rows where r.kindNormalized != "unknown" && r.isOfficial {
            let key = "\(r.kindRaw)|\(r.category.isEmpty ? "Khác" : r.category)"
            let old = grouped[key] ?? (r.kindNormalized, 0, 0)
            grouped[key] = (r.kindNormalized, old.1 + r.countedCents, old.2 + 1)
        }
        return grouped
            .map { CategoryRow(key: $0.key,
                               name: $0.key.components(separatedBy: "|").last ?? $0.key,
                               kindNormalized: $0.value.0, total: $0.value.1, count: $0.value.2) }
            .sorted { a, b in
                if a.kindNormalized != b.kindNormalized { return a.kindNormalized == "business" }
                return a.total > b.total
            }
    }
}

enum TaxPackCSV {
    static let header = [
        "stt", "ma_to", "ngay", "tiem", "phan_loai", "muc", "schedule_c",
        "tam_tinh", "thue", "tong_in", "tip", "so_da_tra",
        "nguon_tam_tinh", "nguon_thue", "nguon_tong", "the", "muc_dich_business",
    ]

    /// Dòng nguồn số cho từng trường: "ƯỚC TÍNH" khi hạ cánh thuế,
    /// "doc/nhap" khi số đọc từ giấy hoặc anh nhập, "khong_ro_nguon"
    /// khi mất hồ sơ đọc (không khẳng định điều không biết).
    static func source(_ r: ExportReceiptInput, field: String) -> String {
        if r.estimatedFields.contains(field) { return EstimateRule.label }
        return r.provenanceKnown ? "doc/nhap" : "khong_ro_nguon"
    }

    /// CSV chi tiết: CHỈ tờ chính thức của năm. Schedule C = đúng giá
    /// trị đã lưu trên tờ; trống thì để TRỐNG (không bịa dòng).
    static func document(_ yearRows: [ExportReceiptInput]) -> (data: Data, officialRows: [ExportReceiptInput]) {
        let official = yearRows.filter { $0.isOfficial }
            .sorted { ($0.date, $0.id) < ($1.date, $1.id) }
        var rows: [[String]] = []
        for (n, r) in official.enumerated() {
            rows.append([
                String(n + 1), r.id, AccountantExport.isoDay(r.date), r.vendor,
                r.kindNormalized, r.category, r.scheduleCLine ?? "",
                ExportCSV.dollars(r.subtotalCents), ExportCSV.dollars(r.taxCents),
                ExportCSV.dollars(r.totalCents), ExportCSV.dollars(r.tipCents),
                ExportCSV.dollars(r.countedCents),
                source(r, field: "subtotal"), source(r, field: "tax"), source(r, field: "total"),
                r.cardLast4 ?? "", r.businessPurpose,
            ])
        }
        return (ExportCSV.document(header: header, rows: rows), official)
    }

    /// KIỂM KHÉP (fail-closed): cộng lại cột so_da_tra của CSV vừa sinh
    /// theo loại — phải bằng ĐÚNG tổng màn Báo Cáo. Lệch -> không xuất.
    static func verify(_ csv: Data, against totals: TaxReportMath.Totals) -> Bool {
        let rows = ExportCSV.parse(csv)
        guard let head = rows.first, let kindCol = head.firstIndex(of: "phan_loai"),
              let paidCol = head.firstIndex(of: "so_da_tra") else { return false }
        var p = 0, b = 0, u = 0
        for r in rows.dropFirst() {
            guard r.count == head.count, let c = ExportCSV.cents(fromDollars: r[paidCol]) else {
                return false
            }
            switch r[kindCol] {
            case "personal": p += c
            case "business": b += c
            default: u += c
            }
        }
        return p == totals.personal && b == totals.business && u == totals.unknown
    }

    /// Tóm tắt theo dòng Schedule C (chỉ tờ business chính thức có
    /// dòng ĐÃ LƯU); tờ business không có dòng nằm ở mục riêng.
    static func scheduleCSummary(_ official: [ExportReceiptInput])
        -> (lines: [(line: String, total: Int, count: Int)], unassignedTotal: Int, unassignedCount: Int) {
        var acc: [String: (Int, Int)] = [:]
        var ut = 0, uc = 0
        for r in official where r.kindNormalized == "business" {
            if let line = r.scheduleCLine, !line.isEmpty {
                let o = acc[line] ?? (0, 0)
                acc[line] = (o.0 + r.countedCents, o.1 + 1)
            } else {
                ut += r.countedCents; uc += 1
            }
        }
        let lines = acc.map { (line: $0.key, total: $0.value.0, count: $0.value.1) }
            .sorted { $0.line < $1.line }
        return (lines, ut, uc)
    }
}
