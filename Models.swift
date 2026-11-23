import SwiftUI
import SwiftData
import UIKit
import PDFKit
import ImageIO

// MARK: - Phân loại Cá nhân / Business / Chưa rõ

/// Phân loại của hoá đơn và của thẻ. Lưu trong SwiftData dưới dạng rawValue (String)
/// để tránh phụ thuộc vào kiểu enum trong tầng lưu trữ.
enum Classification: String, CaseIterable {
    case personal
    case business
    case unknown

    var label: String {
        switch self {
        case .personal: return "CÁ NHÂN"
        case .business: return "BUSINESS"
        case .unknown:  return "CHƯA RÕ"
        }
    }

    var iconName: String {
        switch self {
        case .personal: return "person.fill"
        case .business: return "briefcase.fill"
        case .unknown:  return "questionmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .personal: return Theme.personalColor
        case .business: return Theme.businessColor
        case .unknown:  return Color.gray
        }
    }
}

// MARK: - Màu theo DESIGN-V2 (4 tín hiệu: màu + icon + chữ + badge đuôi thẻ)

enum Theme {
    /// Cá nhân — xanh dương sáng #0A84FF (UI-2026-11-13: nâng
    /// độ sáng cho nền tối; bản cũ #005EB8 chìm trên nền đen).
    static let personalColor = Color(red: 10.0 / 255.0, green: 132.0 / 255.0, blue: 1.0)
    /// Business — cam hổ phách #FF9F0A (bản cũ #9A4A00 quá tối
    /// trên nền đen; cùng tông cam, chỉ nâng sáng).
    static let businessColor = Color(red: 1.0, green: 159.0 / 255.0, blue: 10.0 / 255.0)
}

// MARK: - Danh mục khởi điểm (BLUEPRINT mục 5 — bám Schedule C cho business)

enum Categories {
    static let business: [String] = [
        "Vật Tư (Supplies)",
        "Hàng Hoá/Giá Vốn (Inventory/COGS)",
        "Thiết Bị (Equipment)",
        "Ăn Uống (Meals)",
        "Đi Lại (Travel)",
        "Xe & Xăng (Vehicle/Fuel)",
        "Văn Phòng (Office)",
        "Phần Mềm (Software)",
        "Điện Nước/Internet (Utilities)",
        "Khác (Other)"
    ]
    static let personal: [String] = [
        "Đi Chợ",
        "Nhà Cửa",
        "Y Tế",
        "Khác"
    ]
    static func list(for kind: Classification) -> [String] {
        switch kind {
        case .business: return business
        case .personal: return personal
        case .unknown:  return business + personal
        }
    }
    static func defaultValue(for kind: Classification) -> String {
        switch kind {
        case .business: return "Khác (Other)"
        case .personal: return "Khác"
        case .unknown:  return "Khác (Other)"
        }
    }
}


// MARK: - WP2: Hình thức thanh toán (ACCOUNTING-SPEC D1)
// "unknown" là giá trị hợp lệ nhưng phải gắn cờ — phân biệt trả tiền mặt
// với "không đọc được thẻ", hai tình trạng bằng chứng hoàn toàn khác nhau.

enum PaymentMethod: String, CaseIterable {
    case card
    case cash
    case check
    case other
    case unknown
}

// MARK: - WP2: Nguồn nạp (ACCOUNTING-SPEC F3 — provenance)
// rawText của WP1 chỉ phân biệt được nhãn PDF khi nguồn nạp được lưu ở đây;
// WP3 (đường PDF) sẽ ghi .pdfImport khi nạp file.

enum SourceType: String, CaseIterable {
    case camera
    case photoLibrary
    case pdfImport
    case screenshot
    case unknown
    /// WP3: ảnh nạp từ app Files (không qua thư viện Photos) — tách khỏi
    /// .photoLibrary để dấu vết nguồn nạp trung thực. Thuần cộng thêm một
    /// case rawValue String mới: bản ghi cũ không đổi nghĩa, di trú nhẹ
    /// không bị ảnh hưởng (xem WP3-GATE.md).
    case fileImport
}

// MARK: - WP2: Cờ vốn hoá cho mục Thiết Bị (ACCOUNTING-SPEC E7)
// Thiết bị KHÔNG phải chi phí thường kỳ mặc định (§263(a)); app chỉ lưu
// trạng thái quyết định, việc chốt thuộc CPA của anh — xem WP2-GATE.md.

enum CapitalizationFlag: String, CaseIterable {
    case undecided
    case deMinimisExpense
    case depreciableAsset
}

// MARK: - WP2: Ánh xạ mục chi -> mã dòng Schedule C (ACCOUNTING-SPEC §3.2)
// Mã dòng lưu KÈM nhãn dưới dạng DỮ LIỆU SỬA ĐƯỢC (Master Plan §6: anh là
// LLC 1 thành viên -> Schedule C; hàng mua để dùng -> gợi ý Supplies).
// Bảng này chỉ là GỢI Ý MẶC ĐỊNH lúc xếp mục; mã đã lưu trên từng hoá đơn
// (Receipt.scheduleCLine) là snapshot và không bị bảng này ghi đè về sau.
// Dòng Phần Mềm ghi rõ unverified như ACCOUNTING-SPEC §3.2 đã ghi.

extension Categories {
    static func scheduleCLine(forCategory category: String) -> String? {
        switch category {
        case "Vật Tư (Supplies)": return "Sch C line 22"
        case "Hàng Hoá/Giá Vốn (Inventory/COGS)": return "Sch C Part III line 4 (COGS)"
        case "Thiết Bị (Equipment)": return "Form 4562 / Sch C line 13"
        case "Ăn Uống (Meals)": return "Sch C line 24b"
        case "Đi Lại (Travel)": return "Sch C line 24a"
        case "Xe & Xăng (Vehicle/Fuel)": return "Sch C line 9"
        case "Văn Phòng (Office)": return "Sch C line 18"
        case "Phần Mềm (Software)": return "Sch C line 18 or 27a (CPA unverified)"
        case "Điện Nước/Internet (Utilities)": return "Sch C line 25"
        case "Khác (Other)": return "Sch C line 27a"
        default: return nil
        }
    }
}

// MARK: - Trạng thái duyệt

enum ReceiptStatus: String {
    case needsReview
    case reviewed
}

// MARK: - Mô hình dữ liệu (SwiftData)
// Tiền lưu bằng CENT (Int) — chính xác tới từng cent, không dùng số thập phân lưu trữ.

@Model
final class Receipt {
    var vendor: String = ""
    var date: Date = Date()
    var subtotalCents: Int? = nil
    var taxCents: Int? = nil
    var totalCents: Int? = nil
    var cardLast4: String? = nil
    var cardBrand: String? = nil
    /// Classification.rawValue — phần phân loại RIÊNG của hoá đơn này (snapshot lúc xếp).
    /// Sửa thẻ về sau KHÔNG tự đổi giá trị này, trừ khi anh chọn "xếp lại hoá đơn cũ".
    var classificationRaw: String = Classification.unknown.rawValue
    /// Lý do gợi ý lúc phân loại, vd "Thẻ •• 2586 — đã đăng ký Business".
    var classificationReason: String = ""
    var category: String = ""
    /// Ghi chú mục đích business (sở thuế cần: mua để làm gì).
    var businessPurpose: String = ""
    /// Khoá chống trùng theo tiệm (Sam's = TC#). nil = chưa có khoá tin cậy.
    var dedupeKey: String? = nil
    /// Độ tin cậy OCR từng trường, 0.0–1.0 (0 = không có thông tin).
    var vendorConfidence: Double = 0
    var dateConfidence: Double = 0
    var totalConfidence: Double = 0
    /// Tên file ảnh gốc trong thư mục Documents/ReceiptImages của app.
    var imageFileName: String = ""
    var createdAt: Date = Date()
    /// ReceiptStatus.rawValue
    var statusRaw: String = ReceiptStatus.needsReview.rawValue
    /// Toàn văn OCR — phục vụ tìm kiếm full-text và kiểm tra lại khi cần.
    var ocrRawText: String = ""

    // MARK: WP2 — trường mới (ACCOUNTING-SPEC §5.2, theo thứ tự ưu tiên của
    // chuyên gia Kế toán). MỌI trường đều có giá trị mặc định hoặc optional
    // để kho Build 1 di trú nhẹ (lightweight) — xem WP2-GATE.md. Không
    // trường Build 1 nào bị xoá/đổi: taxCents và imageFileName GIỮ NGUYÊN
    // làm chân tương thích cho code hiện tại (ReceiptViews/HomeView).
    /// C3: các dòng thuế riêng (TAX 1 / TAX 2 / SALES TAX) — quan hệ ở dưới.
    /// C5: tiền tip nhà hàng, lưu RIÊNG — không bao giờ gộp vào total.
    var tipAmountCents: Int? = nil
    /// C6: tổng IN trên giấy khi cần phân biệt với số đã trả (total + tip).
    /// Build 1/2 chuyển tiếp: totalCents vẫn là tổng in; trường này chỉ
    /// được ghi khi bộ đọc cung cấp rõ, không tự suy ra.
    var totalPrintedCents: Int? = nil
    /// A2/A3: địa chỉ tiệm như in + điện thoại / mã cửa hàng.
    var vendorAddress: String = ""
    var vendorPhone: String? = nil
    var storeNumber: String? = nil
    /// A5/A6: mã giao dịch của tiệm + mã xác thực — trường riêng, tách khỏi
    /// dedupeKey (Build 1 nhét TC# chung vào dedupeKey).
    var transactionRef: String? = nil
    var authCode: String? = nil
    /// D1: hình thức thanh toán — PaymentMethod.rawValue.
    var paymentMethodRaw: String = PaymentMethod.unknown.rawValue
    /// F1/F2: danh sách MỌI ảnh gốc + ảnh phái sinh (tăng nét) lưu riêng.
    /// imageFileName (Build 1) vẫn là ảnh gốc đầu tiên; danh sách này là
    /// nguồn đầy đủ từ WP2 — helper allOriginalImageFileNames gộp cả hai.
    var originalImageFileNames: [String] = []
    var enhancedImageFileName: String? = nil
    /// E3: mã dòng Schedule C snapshot kèm mục chi (sửa được, xem trên).
    var scheduleCLine: String? = nil
    /// E5: ăn với ai / quan hệ business (chỉ bắt buộc khi mục Meals/Travel).
    var mealsAttendees: String = ""
    /// E7: cờ vốn hoá khi mục là Thiết Bị — CapitalizationFlag.rawValue.
    var capitalizationFlagRaw: String = CapitalizationFlag.undecided.rawValue
    /// E6: năm thuế anh sửa tay; nil = suy ra từ ngày mua (helper taxYear).
    var taxYearOverride: Int? = nil
    /// F3: nguồn nạp — SourceType.rawValue + tên file gốc nếu có.
    var sourceTypeRaw: String = SourceType.unknown.rawValue
    var sourceFileName: String? = nil
    /// WP3 bước 2 (F3 mục 3): true = ocrRawText trích thẳng từ lớp chữ
    /// PDF; false = chữ do OCR sinh ra (kể cả OCR trên ảnh render của
    /// PDF). Thuần cộng thêm, mặc định false: bản ghi cũ đọc là false —
    /// và chưa có bản ghi .pdfImport nào tồn tại trước WP3 nên không
    /// bản ghi cũ nào bị nhãn sai vì trường này.
    var rawTextFromPDFTextLayer: Bool = false
    /// F6: liên kết bản trùng — KHÔNG xoá bản trùng (điều cấm 3). stableID
    /// rỗng ở bản ghi cũ; bản ghi mới được cấp ở bước nối dây lưu (WP2 bước
    /// sau / WP6, nơi luật trùng được thực thi) — xem WP2-GATE.md.
    var stableID: String = ""
    var duplicateOfStableID: String? = nil
    var excludedFromTotals: Bool = false
    /// WP6-SPEC §5 / P2-0 L-1: anh đã TỰ XÁC NHẬN kiểm tra một tờ
    /// còn cờ LỆCH SỐ HỌC (V1/V2) và duyệt bất chấp. Cộng thêm
    /// thuần tuý có mặc định false -> di trú nhẹ SwiftData tự
    /// động, dữ liệu đã lưu không đổi nghĩa; các cờ vẫn tính
    /// trực tiếp từ số đã lưu mỗi lần hiển thị (không "nuốt"
    /// cờ) — dấu này chỉ ghi nhận quyết định của anh.
    var confirmedWithFlag: Bool = false
    /// F5 (mức tối thiểu): thời điểm anh duyệt + tên các trường anh nhập
    /// tay (phân biệt số-máy-đọc với số-anh-nhập — hai giá trị chứng minh
    /// khác nhau theo Rev. Proc. 97-22).
    var reviewedAt: Date? = nil
    var userEnteredFieldNames: [String] = []
    /// F4: phiên bản bộ đọc đã sinh ra bản ghi này.
    var parserVersion: String = ""
    /// F7: hạn giữ = năm thuế + 7 năm. App KHÔNG bao giờ tự xoá theo hạn
    /// này (điều cấm 4) — trường chỉ để báo danh sách đến hạn sau này.
    var retentionUntil: Date? = nil
    /// V8: hoá đơn trả hàng/refund — tổng âm chỉ hợp lệ khi cờ này bật.
    var isReturn: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \LineItem.receipt)
    var items: [LineItem] = []

    /// WP2/C3: danh sách dòng thuế riêng của hoá đơn này.
    @Relationship(deleteRule: .cascade, inverse: \TaxLine.receipt)
    var taxLines: [TaxLine] = []

    init() {}

    var classification: Classification {
        get { Classification(rawValue: classificationRaw) ?? .unknown }
        set { classificationRaw = newValue.rawValue }
    }
    var status: ReceiptStatus {
        get { ReceiptStatus(rawValue: statusRaw) ?? .needsReview }
        set { statusRaw = newValue.rawValue }
    }

    // MARK: WP2 — helper tính từ trường mới (computed, không lưu trữ)

    var paymentMethod: PaymentMethod {
        get { PaymentMethod(rawValue: paymentMethodRaw) ?? .unknown }
        set { paymentMethodRaw = newValue.rawValue }
    }
    var sourceType: SourceType {
        get { SourceType(rawValue: sourceTypeRaw) ?? .unknown }
        set { sourceTypeRaw = newValue.rawValue }
    }
    var capitalizationFlag: CapitalizationFlag {
        get { CapitalizationFlag(rawValue: capitalizationFlagRaw) ?? .undecided }
        set { capitalizationFlagRaw = newValue.rawValue }
    }
    /// C4: tổng thuế. Ưu tiên Σ taxLines khi có dòng thuế riêng; chưa có
    /// thì dùng taxCents của Build 1. nil (chưa đọc được) và 0 (miễn thuế
    /// thật) giữ NGUYÊN hai nghĩa khác nhau — không bao giờ gộp.
    var taxTotalCents: Int? {
        if !taxLines.isEmpty {
            return taxLines.reduce(0) { $0 + $1.amountCents }
        }
        return taxCents
    }
    /// C5/C6: số đã trả thực tế = tổng in + tip. nil khi chưa có tổng in.
    var amountPaidCents: Int? {
        guard let printed = totalPrintedCents ?? totalCents else { return nil }
        return printed + (tipAmountCents ?? 0)
    }
    /// F1: mọi ảnh gốc — gộp imageFileName (Build 1) + danh sách WP2,
    /// giữ thứ tự, bỏ trùng và bỏ chuỗi rỗng.
    var allOriginalImageFileNames: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for name in [imageFileName] + originalImageFileNames {
            if !name.isEmpty && seen.insert(name).inserted { out.append(name) }
        }
        return out
    }
    /// E6: năm thuế hiệu lực (anh sửa tay thắng suy ra từ ngày mua).
    var taxYear: Int {
        taxYearOverride ?? Calendar.current.component(.year, from: date)
    }
}

// MARK: - A7: truy cập luật tờ chính thức (bọc mỏng quanh OfficialReceiptRule)

extension Receipt {
    /// Tờ CHÍNH THỨC: đã duyệt và không bị loại khỏi tổng.
    var isOfficialRecord: Bool {
        OfficialReceiptRule.isOfficial(isReviewed: status == .reviewed,
                                       excludedFromTotals: excludedFromTotals)
    }
    /// Tờ CHỜ DUYỆT tính vào dòng "đang chờ" (không loại khỏi tổng).
    var isPendingRecord: Bool {
        OfficialReceiptRule.isPending(isNeedsReview: status == .needsReview,
                                      excludedFromTotals: excludedFromTotals)
    }
    /// Số tiền được cộng vào mọi tổng: số đã trả, thiếu thì 0.
    var countedAmountCents: Int {
        OfficialReceiptRule.countedCents(amountPaidCents)
    }

    /// A6: hạn lưu giữ suy từ năm thuế hiện tại (không ghi gì).
    var computedRetentionUntil: Date? {
        RetentionPolicy.retentionUntil(taxYear: taxYear)
    }
    /// A6: gán retentionUntil theo năm thuế — gọi tại điểm TẠO và
    /// điểm có thể ĐỔI ngày/năm thuế. Không bao giờ xoá gì.
    func applyRetentionPolicy() {
        retentionUntil = computedRetentionUntil
    }
}

extension Sequence where Element == Receipt {
    /// Tổng chính thức của một loại (cent).
    func officialTotalCents(kind: Classification) -> Int {
        filter { $0.classification == kind && $0.isOfficialRecord }
            .reduce(0) { $0 + $1.countedAmountCents }
    }
    /// Tổng đang chờ duyệt, mọi loại (cent).
    func pendingTotalCents() -> Int {
        filter { $0.isPendingRecord }
            .reduce(0) { $0 + $1.countedAmountCents }
    }
}

@Model
final class LineItem {
    var name: String = ""
    var qty: Int = 1
    var unitPriceCents: Int? = nil
    var amountCents: Int? = nil
    /// Cờ thuế cuối dòng hoá đơn (Sam's: Y / T). Chỉ là dữ kiện in trên giấy, không tự suy thuế.
    var taxFlag: String? = nil
    var itemCode: String? = nil
    var sortIndex: Int = 0
    /// WP2/B7: phân loại + mục Ở CẤP DÒNG — nền của tính năng tách hoá
    /// đơn theo dòng. Mặc định .unknown / rỗng = chưa tách, hành vi cấp
    /// hoá đơn như Build 1 giữ nguyên.
    var classificationRaw: String = Classification.unknown.rawValue
    var category: String = ""
    var scheduleCLine: String? = nil
    var receipt: Receipt? = nil

    init() {}

    /// WP2/B7: Classification của riêng dòng này (snapshot cấp dòng).
    var classification: Classification {
        get { Classification(rawValue: classificationRaw) ?? .unknown }
        set { classificationRaw = newValue.rawValue }
    }
}

// MARK: - WP2: Dòng thuế riêng (ACCOUNTING-SPEC C3)
// Một dòng TAX như in trên giấy: nhãn nguyên văn + thuế suất nếu có in +
// số tiền. Mẫu 001/002 cần 2 dòng: TAX 1 8.517% $9.60 và TAX 2 4.017% $3.90.

@Model
final class TaxLine {
    var label: String = ""
    var rateText: String? = nil
    var amountCents: Int = 0
    var sortIndex: Int = 0
    var receipt: Receipt? = nil

    init() {}
}

@Model
final class CardTail {
    /// Đúng 4 chữ số cuối. Không bao giờ lưu số thẻ đầy đủ.
    var last4: String = ""
    var brand: String = ""
    /// Classification.rawValue — chỉ dùng .personal / .business.
    var kindRaw: String = Classification.unknown.rawValue
    /// Thẻ ngưng dùng: giữ lại để hoá đơn cũ vẫn tra đúng, không xoá.
    var archived: Bool = false
    var createdAt: Date = Date()

    init() {}

    var kind: Classification {
        get { Classification(rawValue: kindRaw) ?? .unknown }
        set { kindRaw = newValue.rawValue }
    }
}

// MARK: - Gợi ý phân loại theo đuôi thẻ (gợi ý MẠNH, không phải phán quyết)

/// Trả về (loại gợi ý, câu lý do hiện cho anh thấy kèm nút Đổi).
/// Thẻ đã ngưng (archived) vẫn được tra — hoá đơn sót của thẻ cũ vẫn xếp đúng.
func suggestClassification(cardLast4: String?, cardBrand: String?, tails: [CardTail]) -> (Classification, String) {
    guard let last4 = cardLast4, !last4.isEmpty else {
        return (.unknown, "Không đọc được đuôi thẻ (tiền mặt hoặc dòng thẻ bị mờ) — anh chọn giúp")
    }
    // Ưu tiên thẻ đang dùng; không có thì tới thẻ đã ngưng.
    let active = tails.first { $0.last4 == last4 && !$0.archived }
    let archived = tails.first { $0.last4 == last4 && $0.archived }
    if let card = active ?? archived {
        let suffix = card.archived ? " (thẻ đã ngưng dùng)" : ""
        return (card.kind, "Thẻ •• \(last4) — đã đăng ký \(card.kind.label)\(suffix)")
    }
    let brandText = (cardBrand?.isEmpty == false) ? "\(cardBrand!) " : ""
    return (.unknown, "Thẻ \(brandText)•• \(last4) chưa đăng ký — anh chọn giúp")
}

// MARK: - Định dạng tiền
//
// G1: formatMoney(cents:) + formatMoney(optionalCents:) đã
// chuyển NGUYÊN VĂN sang ReceiptLogic.swift (thuần Foundation —
// Models.swift dính SwiftData/UIKit nên không vào được harness,
// mà bộ sinh cờ ở ReceiptLogic cần formatMoney để harness kiểm
// được bằng Swift thật). Cùng module nên mọi điểm gọi cũ không
// đổi.

/// "216.80" -> 21680 ; không đọc được -> nil
func dollarsTextToCents(_ text: String) -> Int? {
    let cleaned = text
        .replacingOccurrences(of: "$", with: "")
        .replacingOccurrences(of: ",", with: "")
        .trimmingCharacters(in: .whitespaces)
    guard !cleaned.isEmpty else { return nil }
    // TRAP/SIGN-FIX T2+N1 (FULL-REVIEW 2026-11-12):
    // - Dấu trừ áp cho TOÀN BỘ giá trị. Bản cũ tính
    //   dollars*100 + cents với dấu chỉ nằm ở phần đô-la:
    //   "-216.80" đọc lại thành -21520 (sai 160 xu) và
    //   "-0.50" thành +50 (lật dấu) — vòng khép kín với
    //   centsToDollarsText phá chính số âm của app trên
    //   đường Kiểm Lại -> Lưu.
    // - Phần đô-la chặn 12 chữ số như SafeMoney: bản cũ dán
    //   chuỗi 18-19 chữ số vào ô tiền là *100 tràn Int ->
    //   crash. Ngoài miền -> nil (ô nhập coi như không hợp lệ).
    var body = cleaned
    var negative = false
    if body.hasPrefix("-") { negative = true; body = String(body.dropFirst()) }
    else if body.hasPrefix("+") { body = String(body.dropFirst()) }
    guard !body.isEmpty else { return nil }
    let parts = body.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 1 || parts.count == 2 else { return nil }
    let dollarsText = parts[0]
    guard !dollarsText.isEmpty, dollarsText.count <= 12,
          dollarsText.allSatisfy({ $0.isNumber }),
          let dollars = Int(dollarsText) else { return nil }
    var cents = 0
    if parts.count == 2 {
        var frac = String(parts[1])
        if frac.isEmpty { frac = "00" }
        if frac.count == 1 { frac += "0" }
        // P2-0 mục 17 (§2.2(7)): phần thập phân dài hơn 2 chữ
        // số là chữ đọc lạ — bản cũ cắt cụt thầm lặng
        // (1.234 -> 123 cent), nay trả nil cho ô tiền đó
        // trống để bộ cờ lên tiếng thay vì ghi số sai.
        if frac.count > 2 { return nil }
        guard let c = Int(frac) else { return nil }
        cents = c
    }
    // dollars <= 999_999_999_999 nên * 100 + cents không tràn.
    let magnitude = dollars * 100 + cents
    return negative ? -magnitude : magnitude
}

/// 21680 -> "216.80" (để nạp vào ô sửa tiền)
func centsToDollarsText(_ cents: Int?) -> String {
    guard let cents = cents else { return "" }
    let sign = cents < 0 ? "-" : ""
    let absCents = abs(cents)
    return "\(sign)\(absCents / 100).\(String(format: "%02d", absCents % 100))"
}

// MARK: - Kho ảnh gốc (Documents/ReceiptImages — thư mục riêng của app)

/// Bằng chứng gốc lưu trong thư mục của app (hiện trong Files → Trên iPhone → Sổ Hóa Đơn
/// nhờ UIFileSharingEnabled). Cấm fileImporter CHỌN THƯ MỤC ngoài — trên máy anh
/// (iOS 27.2) đường đó tự huỷ im lặng khi chọn thư mục của chính app (Test 0 đã kiểm chứng).
/// WP3 dùng fileImporter CHỌN FILE (chế độ khác, xem ScanView) — vẫn cần bài kiểm
/// riêng trên máy anh ở mốc M1 như ghi ở WP3-GATE.md.
enum ImageStore {
    static var directory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("ReceiptImages", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func saveJPEG(_ image: UIImage, quality: CGFloat = 0.8) -> String? {
        guard let data = image.jpegData(compressionQuality: quality) else { return nil }
        let name = UUID().uuidString + ".jpg"
        let url = directory.appendingPathComponent(name)
        do {
            try data.write(to: url)
            // L-2026-11-20-42: phễu ghi ảnh gốc DUY NHẤT của
            // app (mọi đường quét/nhập/gắn lại đều qua đây) —
            // chép thêm một bản vào kho an toàn ở Application
            // Support. Best-effort: chép kho hỏng chỉ ghi log,
            // KHÔNG đổi kết quả của đường lưu chính.
            OriginalVault.backfill(fileName: name,
                                   mainDirectory: directory)
            return name
        } catch {
            return nil
        }
    }

    /// WP3: lưu file gốc NGUYÊN BYTE (PDF) vào cùng thư mục bằng chứng.
    /// Trả tên file đã lưu (UUID + đuôi) hoặc nil khi ghi lỗi — nơi gọi phải
    /// báo lỗi thật cho anh, không giả vờ đã lưu (luật B-2).
    static func saveFile(data: Data, fileExtension ext: String) -> String? {
        let name = UUID().uuidString + "." + ext
        let url = directory.appendingPathComponent(name)
        do {
            try data.write(to: url)
            // L-2026-11-20-42: như saveJPEG — bản sao kho an
            // toàn best-effort ngay tại phễu ghi.
            OriginalVault.backfill(fileName: name,
                                   mainDirectory: directory)
            return name
        } catch {
            return nil
        }
    }

    // MARK: OPT-1 — bộ đệm theo DANH TÍNH file (tên + kích thước + mtime)
    //
    // Màn Chi Tiết / Kiểm Lại gọi load() 3–4 lần cho CÙNG một file
    // trong MỖI lần vẽ thân view (mỗi phím gõ ở ô chữ là một lần
    // vẽ) — OPTIMIZATION-AUDIT mục #2. Bộ đệm này trả lại đúng ảnh
    // đã giải mã khi file trên đĩa CHƯA đổi. Ngữ nghĩa giữ nguyên:
    // - mỗi lần gọi vẫn stat file: file mất -> không có khoá -> đi
    //   đúng đường cũ (đọc hỏng -> nil), cổng thiếu-ảnh-gốc không
    //   bao giờ bị bộ đệm che;
    // - file bị thay (khôi phục từ kho an toàn, gắn lại) -> kích
    //   thước/mtime đổi -> khoá mới -> đọc lại thật;
    // - kết quả nil KHÔNG được đệm (lần sau thử lại như cũ).
    // NSCache tự thả khi máy thiếu bộ nhớ; trần chi phí theo pixel.
    private static let decodedCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 8
        cache.totalCostLimit = 96 * 1024 * 1024
        return cache
    }()

    /// Khoá danh tính của file: nil khi không stat được (khi đó
    /// nơi gọi đi thẳng đường cũ, không chạm bộ đệm).
    private static func identityKey(url: URL, fileName: String,
                                    variant: String) -> NSString? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int,
              let mtime = attrs[.modificationDate] as? Date else { return nil }
        return "\(variant)|\(fileName)|\(size)|\(mtime.timeIntervalSinceReferenceDate)" as NSString
    }

    /// Chi phí ước của một ảnh trong bộ đệm = số byte RGBA khi vẽ.
    private static func pixelCost(_ image: UIImage) -> Int {
        let w = Int(image.size.width * image.scale)
        let h = Int(image.size.height * image.scale)
        return max(1, w * h * 4)
    }

    static func load(fileName: String) -> UIImage? {
        guard !fileName.isEmpty else { return nil }
        let url = directory.appendingPathComponent(fileName)
        let key = identityKey(url: url, fileName: fileName, variant: "full")
        if let key, let cached = decodedCache.object(forKey: key) {
            return cached
        }
        let image = loadUncached(fileName: fileName, url: url)
        if let key, let image {
            decodedCache.setObject(image, forKey: key, cost: pixelCost(image))
        }
        return image
    }

    // MARK: OPT-1 — thumbnail cho dòng danh sách (OPTIMIZATION-AUDIT #1)

    private static let thumbnailCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 400
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()

    /// Ảnh nhỏ cho ô 46×58 pt của ReceiptRowView. Bản trước giải mã
    /// TOÀN BỘ ảnh gốc (trung vị BenchImages 2.3 MP ≈ 8.9 MB RGBA,
    /// lớn nhất 100 MP ≈ 382 MB) chỉ để vẽ ô này.
    ///
    /// Kích thước chọn để KHÔNG đổi hình: cạnh NGẮN của ảnh nhỏ ≥
    /// `minShortSidePixels` (mặc định 180 ≥ 58 pt × 3) nên với
    /// .scaledToFill vào khung 46×58 pt ở màn 3x ảnh vẫn được thu,
    /// không bao giờ bị phóng. Hướng EXIF áp như UIImage(data:)
    /// (kCGImageSourceCreateThumbnailWithTransform).
    /// Không thu nhỏ được (PDF, ảnh vốn đã nhỏ, ImageIO lỗi) -> trả
    /// đúng load(fileName:) như bản cũ — dòng hiện y như trước.
    static func loadThumbnail(fileName: String,
                              minShortSidePixels: Int = 180) -> UIImage? {
        guard !fileName.isEmpty else { return nil }
        if fileName.lowercased().hasSuffix(".pdf") {
            return load(fileName: fileName)
        }
        let url = directory.appendingPathComponent(fileName)
        guard let key = identityKey(url: url, fileName: fileName,
                                    variant: "thumb\(minShortSidePixels)")
        else { return load(fileName: fileName) }
        if let cached = thumbnailCache.object(forKey: key) {
            return cached
        }
        guard let thumb = downsample(url: url,
                                     minShortSidePixels: minShortSidePixels)
        else { return load(fileName: fileName) }
        thumbnailCache.setObject(thumb, forKey: key, cost: pixelCost(thumb))
        return thumb
    }

    /// Thu nhỏ bằng ImageIO, không giải mã ảnh toàn phân giải. nil
    /// khi không đọc được kích thước hoặc ảnh không lớn hơn đích.
    private static func downsample(url: URL,
                                   minShortSidePixels: Int) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { return nil }
        let shortSide = min(width, height)
        let longSide = max(width, height)
        guard shortSide > minShortSidePixels else { return nil }
        let maxPixel = Int((Double(longSide) * Double(minShortSidePixels)
                            / Double(shortSide)).rounded(.up))
        guard maxPixel < longSide else { return nil }
        let thumbOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions)
        else { return nil }
        return UIImage(cgImage: cg)
    }

    /// Thân nạp NGUYÊN VĂN của bản trước OPT-1 (chỉ đổi tên hàm).
    private static func loadUncached(fileName: String, url: URL) -> UIImage? {
        if fileName.lowercased().hasSuffix(".pdf") {
            // WP3 (CODE-AUDIT F1 mục 5): bằng chứng là PDF gốc — byte gốc giữ
            // nguyên trong thư mục, hiển thị bằng render trang 1 (PDFKit).
            // Mọi điểm gọi cũ (dòng danh sách / Chi Tiết / Kiểm Lại) dùng
            // chung hàm này nên tự chạy đúng mà không phải rẽ nhánh từng nơi.
            guard let doc = PDFDocument(url: url), let page = doc.page(at: 0) else { return nil }
            let bounds = page.bounds(for: .cropBox)
            guard bounds.width > 0, bounds.height > 0 else { return nil }
            let targetWidth: CGFloat = 1240
            let size = CGSize(width: targetWidth, height: targetWidth * bounds.height / bounds.width)
            return page.thumbnail(of: size, for: .cropBox)
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    static func delete(fileName: String) {
        guard !fileName.isEmpty else { return }
        let url = directory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
    }
}
