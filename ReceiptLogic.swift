import Foundation

// MARK: - G1: logic điều kiện THUẦN tách khỏi tầng giao diện
//
// Gói G1 (chương trình triệt để, LEADER-SYNTHESIS §3-G1): các
// hàm quyết định trước đây nằm trong ReceiptViews.swift (file
// SwiftUI) nên KHÔNG cổng kiểm chứng nào thực thi được — harness
// không biên dịch file view, kiểm tĩnh không chạy hành vi. Ba ca
// đã lọt ra máy anh vì đúng lỗ hổng này: L-2026-11-13-17 (nút Đọc
// lại chỉ bấm được 1 lần — điều kiện canReparse), L-2026-11-13-20
// (cờ mục đích không tắt được), ca "Thiếu ảnh gốc" (điều kiện
// receiptHasOriginalImage).
//
// File này CHỈ phụ thuộc Foundation: không SwiftUI, không
// SwiftData, không UIKit. ReceiptViews giữ các hàm bọc mỏng cùng
// tên cũ (receiptFlags / receiptHasOriginalImage / canReparse)
// để mọi điểm gọi trong app KHÔNG đổi; thân hàm thật nằm ở đây
// và được harness chạy bằng Swift thật ở chế độ `unittests`.
//
// KỶ LUẬT: tách NGUYÊN VĂN, không đổi hành vi — bảng đối chiếu
// trước/sau ở g1/BEHAVIOR-DIFF.md. Sửa logic ở đây từ nay phải
// qua cổng unittests trước khi giao.

// MARK: - Định dạng tiền (chuyển nguyên văn từ Models.swift)
//
// formatMoney ở đây vì receiptFlags cần nó để sinh chữ cờ, mà
// Models.swift (SwiftData/UIKit) không vào được harness. Cùng
// module app nên mọi điểm gọi cũ (HomeView / DesignSystem /
// ReceiptViews) không đổi một chữ.

/// 21680 -> "$216.80"
// P2-0 mục 17 (§2.2(7)): NumberFormatter dựng MỘT LẦN dùng
// chung — bản cũ cấp phát mới ở MỌI lần gọi (đường hiển thị
// gọi theo từng dòng hoá đơn). Cấu hình giữ nguyên hệt.
private let sharedMoneyFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "USD"
    formatter.locale = Locale(identifier: "en_US")
    return formatter
}()

func formatMoney(cents: Int) -> String {
    return sharedMoneyFormatter.string(from: NSNumber(value: Double(cents) / 100.0)) ?? "$0.00"
}

func formatMoney(optionalCents cents: Int?) -> String {
    guard let cents = cents else { return "—" }
    return formatMoney(cents: cents)
}

// MARK: - Chữ cờ dùng chung

/// L-2026-11-13-20: chữ cờ "thiếu mục đích" dùng chung giữa hàm
/// sinh cờ và màn Chi Tiết — màn Chi Tiết nhận ra đúng cờ này để
/// gắn Ô NHẬP MỤC ĐÍCH ngay dưới cảnh báo (cờ tự phục vụ), thay
/// vì bắt anh tự tìm ô nhập ở mục Phân loại phía dưới.
let missingPurposeFlagText = "Thiếu mục đích business — sở thuế hay soi điểm này"

/// Chữ cờ thiếu ảnh gốc (IMGFIX) — hằng số để test khoá đúng
/// nguyên văn như missingPurposeFlagText.
let missingOriginalImageFlagText = "Thiếu ảnh gốc — cần gắn lại để đủ bằng chứng"

/// P2-0 mục 19 (§2.2 gate): tờ không rõ tiệm mà vẫn có thể
/// thành .reviewed là lỗ hổng đóng cổng — chữ cờ dùng chung
/// như hai hằng trên.
let missingVendorFlagText = "Chưa rõ tiệm"

// MARK: - Cờ nghi ngờ đuôi thẻ ↔ sổ thẻ đã đăng ký (L-2026-11-18-29)
//
// Bộ đọc (Parser.validate, khối P3-FLAG-CARD) sinh cờ nghi ngờ
// đuôi thẻ THUẦN theo độ tin cậy Vision của dòng thẻ + dấu hiệu
// dòng bị gộp — tầng đọc không biết sổ thẻ đã đăng ký (sổ sống ở
// tầng app/SwiftData). Hệ quả trên máy anh (bản #143): đuôi đọc
// ĐÚNG 2586 nhưng mực in mờ -> confidence thấp -> cờ "độ tin cậy
// THẤP" vẫn bật, dù suggestClassification tra sổ và xếp Business
// chính xác — app vừa tin vừa nghi cùng một con số.
//
// Luật hoà giải ở tầng app (hai hàm thuần dưới đây, tầng view
// truyền vào tập đuôi đã đăng ký): đuôi đọc được khớp ĐÚNG MỘT
// đuôi đã đăng ký (bằng chuỗi tuyệt đối — cùng mức tin mà
// suggestClassification vẫn dùng để phân loại) thì cờ nghi ngờ
// đuôi thẻ bị gỡ: con số đã được chính hồ sơ của anh xác nhận,
// nghi ngờ không còn căn cứ. Không khớp -> giữ nguyên mọi cờ.
// TUYỆT ĐỐI không khớp mờ: đuôi đọc sai một số (2580, ca
// L-R09 trên luồng đóng băng) không được tự thành 2586.

/// Một cảnh báo có phải CỜ NGHI NGỜ ĐUÔI THẺ của
/// Parser.validate không — ba dạng chữ validate sinh ở khối
/// P3-FLAG-CARD (Parser.swift): dòng bị gộp với dòng tổng /
/// độ tin cậy THẤP / chưa thật chắc. Mọi cảnh báo khác (tổng,
/// tiệm, ngày, tranh chấp đuôi "Thẻ: có hai đuôi...") không
/// khớp mẫu này.
func isCardTailConfidenceWarning(_ warning: String) -> Bool {
    guard warning.hasPrefix("Đuôi thẻ ") else { return false }
    return warning.contains("độ tin cậy THẤP")
        || warning.contains("nằm trên dòng bị gộp với dòng tổng")
        || warning.contains("chưa thật chắc")
}

/// Gỡ cờ nghi ngờ đuôi thẻ khỏi danh sách cảnh báo KHI VÀ CHỈ
/// KHI đuôi đọc được nằm trong tập đuôi đã đăng ký (khớp chuỗi
/// tuyệt đối). Mọi trường hợp còn lại trả danh sách nguyên vẹn.
func warningsClearingRegisteredCardFlags(_ warnings: [String],
                                         cardLast4: String?,
                                         registeredTails: Set<String>)
    -> [String] {
    guard let tail = cardLast4, !tail.isEmpty,
          registeredTails.contains(tail) else { return warnings }
    return warnings.filter { !isCardTailConfidenceWarning($0) }
}

// MARK: - Đầu vào thuần cho bộ sinh cờ

/// Phân loại ở dạng thẻ thuần — ReceiptLogic không biết
/// Classification của Models.swift (file đó dính SwiftData);
/// tầng bọc ở ReceiptViews ánh xạ 1-1 sang thẻ này.
enum ReceiptKindTag: Equatable {
    case personal
    case business
    case unknown
}

/// Mọi dữ kiện receiptFlags cần, dạng giá trị thuần. Tầng bọc
/// trích từ Receipt (SwiftData) + kết quả kiểm file ảnh; bộ cờ
/// sinh ra chỉ phụ thuộc các trường này — test nạp trực tiếp
/// không cần SwiftData.
struct ReceiptFlagInput: Equatable {
    var subtotalCents: Int?
    /// amountCents của từng dòng món theo thứ tự bản ghi
    /// (nil = dòng không có tiền — tính 0 như bản gốc).
    var itemAmountCents: [Int?]
    var totalCents: Int?
    /// Đúng trường taxCents của bản ghi (KHÔNG phải
    /// taxTotalCents) — giữ nguyên văn lựa chọn của bản gốc.
    var taxCents: Int?
    var kind: ReceiptKindTag
    var businessPurpose: String
    var hasOriginalImage: Bool
    /// P2-0 mục 19 (§2.2 gate): tên tiệm của tờ. nil = nơi gọi
    /// KHÔNG cung cấp (các điểm dựng cũ / harness) -> bộ cờ
    /// không phán về tiệm; có giá trị mà rỗng hoặc toàn trắng
    /// -> cờ missingVendorFlagText.
    var vendor: String? = nil
}

// MARK: - Bộ logic thuần

enum ReceiptLogic {

    /// L-2026-11-13-17: Đọc lại là đường sửa số đứng (Điều 2
    /// B2) — còn văn bản thô đã lưu là còn bấm được; KHÔNG cổng
    /// tem bộ đọc, KHÔNG cổng trạng thái duyệt. Nguyên văn điều
    /// kiện cũ: `!receipt.ocrRawText.isEmpty` (không cắt trắng:
    /// chuỗi chỉ gồm ký tự xuống dòng vẫn tính là còn văn bản,
    /// đúng hành vi trước tách).
    static func canReparse(ocrRawText: String) -> Bool {
        !ocrRawText.isEmpty
    }

    /// IMGFIX: chỉ cần MỘT tên file trong danh sách gốc tải
    /// được là bằng chứng còn. Hàm nạp (ImageStore.load ở app /
    /// hàm giả ở test) do nơi gọi cấp — logic "contains" thuần
    /// nằm ở đây để kiểm được.
    static func hasLoadableOriginal(fileNames: [String],
                                    isLoadable: (String) -> Bool) -> Bool {
        fileNames.contains(where: isLoadable)
    }

    /// Bộ cờ "Cần kiểm lại" của một hoá đơn đã lưu — chuyển
    /// NGUYÊN VĂN từ receiptFlags trong ReceiptViews.swift,
    /// giữ đúng thứ tự cờ và đúng ngưỡng ±2 xu.
    static func flags(for input: ReceiptFlagInput) -> [String] {
        var flags: [String] = []
        if let subtotal = input.subtotalCents, !input.itemAmountCents.isEmpty {
            let sum = input.itemAmountCents.reduce(0) { $0 + ($1 ?? 0) }
            if abs(sum - subtotal) > 2 {
                flags.append("Tổng các món (\(formatMoney(cents: sum))) khác subtotal (\(formatMoney(cents: subtotal)))")
            }
        }
        if let subtotal = input.subtotalCents, let total = input.totalCents {
            let tax = input.taxCents ?? 0
            if abs(subtotal + tax - total) > 2 {
                flags.append("Subtotal + thuế khác tổng tiền")
            }
        }
        if input.totalCents == nil {
            flags.append("Thiếu tổng tiền")
        }
        // P2-0 mục 19 (§2.2 gate): chỉ phán khi nơi gọi CÓ
        // cung cấp tên tiệm (vendor != nil).
        if let vendor = input.vendor,
           vendor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            flags.append(missingVendorFlagText)
        }
        if input.kind == .business && input.businessPurpose.trimmingCharacters(in: .whitespaces).isEmpty {
            flags.append(missingPurposeFlagText)
        }
        if input.kind == .unknown {
            flags.append("Chưa phân loại Cá nhân / Business")
        }
        // IMGFIX: ảnh gốc là bằng chứng BẮT BUỘC (trình
        // accountant) — tờ không còn file gốc nào tải được phải
        // kêu thành cờ trong khu "Cần kiểm lại", không được im
        // lặng như trước (bài học tờ Home Depot 2026-11-10: số
        // đã đúng hết mà ảnh gốc mất không ai hay).
        if !input.hasOriginalImage {
            flags.append(missingOriginalImageFlagText)
        }
        return flags
    }

    // MARK: - Cổng duyệt theo lớp cờ (L-2026-11-18-32)

    /// Lớp của một cờ "Cần kiểm lại" — quyết định hành vi cổng
    /// duyệt ở Chi Tiết. Ba lớp:
    /// - arithmeticDiscrepancy: lệch số học V1/V2 (Σ món khác
    ///   subtotal; subtotal + thuế khác tổng).
    /// - missingField: cờ THIẾU TRƯỜNG (thiếu tổng tiền, chưa
    ///   rõ tiệm, thiếu mục đích business, chưa phân loại) —
    ///   tự tắt khi anh điền đúng trường đó; chưa điền thì vẫn
    ///   duyệt được kèm xác nhận (xem approvalGate).
    /// - missingOriginalImage: thiếu ảnh gốc — bằng chứng bắt
    ///   buộc, lớp DUY NHẤT còn giữ khoá (kèm đường gỡ tại nút).
    enum ReceiptFlagClass: Equatable {
        case arithmeticDiscrepancy
        case missingField
        case missingOriginalImage
    }

    static func flagClass(_ flag: String) -> ReceiptFlagClass {
        if flag == missingOriginalImageFlagText {
            return .missingOriginalImage
        }
        if isArithmeticDiscrepancyFlag(flag) {
            return .arithmeticDiscrepancy
        }
        return .missingField
    }

    /// Cờ LỆCH SỐ HỌC (V1/V2) — thân thuần của hàm cùng tên ở
    /// ReceiptViews.swift (tầng view chỉ còn là hàm bọc mỏng
    /// theo kỷ luật G1). Chuỗi khoá nguyên văn như bản gốc.
    static func isArithmeticDiscrepancyFlag(_ flag: String) -> Bool {
        flag.hasPrefix("Tổng các món (")
            || flag == "Subtotal + thuế khác tổng tiền"
    }

    /// Phán quyết cổng duyệt cho một bộ cờ.
    enum ApprovalGateDecision: Equatable {
        /// Không cờ — duyệt thẳng.
        case approveDirectly
        /// Còn cờ thuộc lớp lệch số học / thiếu trường — duyệt
        /// được qua "Duyệt kèm cờ" với hộp xác nhận nêu rõ từng
        /// cờ; việc duyệt ghi confirmedWithFlag.
        case approveWithFlagConfirmation(flags: [String])
        /// Còn cờ thiếu ảnh gốc — giữ khoá (bằng chứng bắt
        /// buộc); nút phải hiện lý do + đường gỡ cụ thể.
        case blockedByMissingImage(flags: [String])
    }

    /// L-2026-11-18-32 (anh báo trên bản #143, tờ Hobby
    /// Lobby): cổng cũ (P2-0/C-1) coi MỌI cờ ngoài V1/V2 là
    /// "chặn duyệt" — tờ chỉ có đúng một cờ "Chưa rõ tiệm" bị
    /// khoá cứng vĩnh viễn, dù Chi Tiết còn không có ô sửa tên
    /// tiệm để anh tự gỡ. Nguyên tắc anh chốt: chủ app không
    /// bao giờ bị khoá duyệt với tờ mình đã tự kiểm. Nay:
    /// thiếu ảnh gốc là lớp duy nhất còn khoá (bằng chứng bắt
    /// buộc — và tờ luôn có đường gắn lại ngay trong Chi
    /// Tiết); mọi lớp còn lại đi đường duyệt-kèm-cờ có xác
    /// nhận tường minh. Bộ cờ tự nó KHÔNG đổi: cờ vẫn sinh và
    /// hiện nguyên như trước để accountant thấy.
    static func approvalGate(flags: [String]) -> ApprovalGateDecision {
        if flags.isEmpty { return .approveDirectly }
        if flags.contains(where: { flagClass($0) == .missingOriginalImage }) {
            return .blockedByMissingImage(flags: flags)
        }
        return .approveWithFlagConfirmation(flags: flags)
    }
}

// MARK: - A7: luật "tờ chính thức" — NGUỒN DUY NHẤT

/// A7 (vòng 2): luật tờ CHÍNH THỨC trước đây được chép tay ở 5 chỗ
/// (Trang Chủ ×2, Báo Cáo ×2, danh sách ×1) và luật tờ CHỜ DUYỆT ở
/// 3 chỗ. Nay một nguồn duy nhất, thuần Foundation để harness kiểm
/// bằng Swift thật. Nguyên văn luật cũ:
/// - chính thức = status == .reviewed && !excludedFromTotals
/// - chờ duyệt  = status == .needsReview && !excludedFromTotals
/// - số được cộng = amountPaidCents ?? 0 (tổng in + tip; thiếu tổng = 0)
enum OfficialReceiptRule {
    static func isOfficial(isReviewed: Bool,
                           excludedFromTotals: Bool) -> Bool {
        isReviewed && !excludedFromTotals
    }

    static func isPending(isNeedsReview: Bool,
                          excludedFromTotals: Bool) -> Bool {
        isNeedsReview && !excludedFromTotals
    }

    static func countedCents(_ amountPaidCents: Int?) -> Int {
        amountPaidCents ?? 0
    }
}

// MARK: - A6: hạn lưu giữ 7 năm (tất định theo năm thuế)

/// A6 (vòng 2): `Receipt.retentionUntil` có sẵn trong model nhưng
/// chưa nơi nào gán. Luật tất định: hạn = 31/12 của (năm thuế + 7),
/// 00:00 UTC theo lịch Gregory — cùng năm thuế luôn ra cùng một hạn,
/// không phụ thuộc múi giờ máy. CHỈ để HIỂN THỊ: app không bao giờ
/// tự xoá hoá đơn hay file gốc vì hạn này.
enum RetentionPolicy {
    static let years = 7

    private static let utcCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    static func retentionUntil(taxYear: Int) -> Date? {
        utcCalendar.date(from: DateComponents(
            year: taxYear + years, month: 12, day: 31))
    }

    /// Tờ "tới ngưỡng lưu giữ": hạn đã qua hoặc rơi trong
    /// `windowDays` ngày tới tính từ `now`.
    static func reachesHorizon(retentionUntil: Date, now: Date,
                               windowDays: Int = 365) -> Bool {
        retentionUntil <= now.addingTimeInterval(Double(windowDays) * 86_400)
    }

    /// Năm (UTC) của một hạn — để hiển thị nhóm.
    static func year(of date: Date) -> Int {
        utcCalendar.component(.year, from: date)
    }
}

// MARK: - A12(iv): nhật ký hồ sơ — CHỈ ĐỌC dữ liệu đã ghi

/// A12 (vòng 2, WP9): xem lại dấu vết đã có sẵn trên bản ghi —
/// thời điểm tạo, nguồn nạp, bộ đọc, thời điểm duyệt (reviewedAt) và
/// các trường anh đã nhập tay (userEnteredFieldNames). KHÔNG ghi sự
/// kiện mới nào; thuần Foundation để harness kiểm.
enum AuditTrail {
    struct Row: Equatable {
        var label: String
        var value: String
    }

    /// Tên hiển thị của tên trường được ghi trong userEnteredFieldNames.
    /// Tên lạ (đời sau thêm) hiện nguyên văn — không giấu, không đoán.
    static func fieldLabel(_ name: String) -> String {
        switch name {
        case "vendor": return "Tên tiệm"
        case "date": return "Ngày"
        case "subtotal": return "Tạm tính"
        case "tax": return "Thuế"
        case "total": return "Tổng"
        case "classification": return "Loại (Cá nhân / Business)"
        case "category": return "Mục chi"
        case "businessPurpose": return "Mục đích business"
        default: return name
        }
    }

    /// Nhãn nguồn nạp theo SourceType.rawValue (giá trị lạ hiện
    /// nguyên văn).
    static func sourceLabel(_ raw: String) -> String {
        switch raw {
        case "camera": return "Chụp bằng camera"
        case "photoLibrary": return "Ảnh từ thư viện"
        case "pdfImport": return "File PDF"
        case "screenshot": return "Ảnh chụp màn hình"
        case "fileImport": return "File từ app Files"
        case "unknown": return "Không ghi nguồn"
        default: return raw
        }
    }

    static func rows(createdAt: Date,
                     sourceLabel: String,
                     sourceFileName: String?,
                     parserVersion: String,
                     isReviewed: Bool,
                     reviewedAt: Date?,
                     userEnteredFieldNames: [String],
                     duplicateOfStableID: String?,
                     formatDate: (Date) -> String) -> [Row] {
        var out: [Row] = []
        out.append(Row(label: "Tạo lúc", value: formatDate(createdAt)))
        let src = (sourceFileName?.isEmpty ?? true)
            ? sourceLabel : "\(sourceLabel) · \(sourceFileName!)"
        out.append(Row(label: "Nguồn nạp", value: src))
        out.append(Row(label: "Bộ đọc",
                       value: parserVersion.isEmpty ? "đời đầu (không ghi)" : parserVersion))
        if let reviewedAt {
            out.append(Row(label: "Duyệt lúc", value: formatDate(reviewedAt)))
        } else {
            out.append(Row(label: "Duyệt lúc",
                           value: isReviewed ? "đã duyệt — không có dấu thời điểm (tờ đời cũ)"
                                             : "chưa duyệt"))
        }
        // Giữ thứ tự đã ghi, bỏ tên lặp.
        var seen = Set<String>()
        let names = userEnteredFieldNames.filter { seen.insert($0).inserted }
        out.append(Row(label: "Anh nhập / sửa tay",
                       value: names.isEmpty ? "không trường nào"
                           : names.map(fieldLabel).joined(separator: ", ")))
        if let dup = duplicateOfStableID, !dup.isEmpty {
            out.append(Row(label: "Ghi nhận là bản trùng của", value: dup))
        }
        return out
    }
}

// MARK: - A11(iii): trường tin cậy thấp ở Kiểm Lại

/// A11 (vòng 2, WP8; DESIGN-AUDIT §4.7): trường nào cần tô cảnh báo.
/// Chỉ khi bộ đọc CÓ tín hiệu tin cậy (> 0) và tín hiệu đó < 0.85 —
/// 0 nghĩa là "không có tín hiệu" (màn cũ cũng ẩn % tổng khi = 0),
/// không phải "tin cậy thấp". Thứ tự cố định: tiệm, ngày, tổng.
enum ReviewConfidence {
    static let threshold = 0.85

    static func isLow(_ c: Double) -> Bool { c > 0 && c < threshold }

    static func lowFields(vendor: Double, date: Double, total: Double) -> [String] {
        var out: [String] = []
        if isLow(vendor) { out.append("vendor") }
        if isLow(date) { out.append("date") }
        if isLow(total) { out.append("total") }
        return out
    }

    /// Đích nhảy "cờ kế tiếp": khối cảnh báo (nếu có) rồi các trường
    /// tin cậy thấp. `after` = đích vừa nhảy tới (nil = bắt đầu).
    static func nextTarget(targets: [String], after current: String?) -> String? {
        guard !targets.isEmpty else { return nil }
        guard let current, let i = targets.firstIndex(of: current) else { return targets[0] }
        return targets[(i + 1) % targets.count]
    }
}
