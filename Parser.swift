import Foundation

// MARK: - Parser v3 — TẦNG PHÂN TÍCH F4 (Pha 1, DESIGN-FINAL đã duyệt)
//
// Bản này là F4 của kiến trúc core-v3, xây trên nền integrate-v2
// (tem core-v2-1) — mọi hành vi không đánh dấu PHA-1 đều giữ nguyên
// văn của bản nền đã kiểm chứng. Các thay đổi của Pha 1 (bản gương
// Python port_f4_mirror.py là cùng một logic, bộ kiểm
// v3-phase1/test_f4.py):
//  P1-SAFEMONEY: mọi phép tính tiền qua SafeMoney (Money.swift của
//    Pha 0) — hàm moneyToCents cũ (trả 0 giả + nhân trần có thể
//    trap) bị XOÁ; trích tiền ngoài miền -> nil, không số giả.
//  P1-VENDOR-DATA: vendor = dữ liệu vendors.json nạp qua
//    VendorData.swift (M7); bảng cứng trong file này bị xoá.
//    printSemantics đi cùng vendor (P1-E3 ở validate).
//  P1-QTYFLAG: dòng số lượng Sam's chấp nhận ký tự rác OCR ở ô cờ
//    cuối dòng (fixture N-002).
//  P1-CARD-TENDER: đuôi thẻ ở dòng thanh toán '<hãng> DEBIT/CREDIT-
//    NNNN' (fixture L-R04/L-R11/S-0).
//  P1-DATE-MERGE: ngày-không-giờ ghép giờ trong ±3 dòng (fixture
//    L-R03).
//  P1-MONEY-BOUNDARY: token tiền phải có biên phải (không cắt
//    '3.91' khỏi suất '3.9170' — fixture L-R03). Áp ở
//    lastMoneyInLine/totalCandidates/columnModel của file này;
//    việc gấp vào SafeMoney.tokenRegex là việc nối tiếp đã ghi ở
//    AFTER.md (Money.swift của Pha 0 không sửa trong pha này).
//  P1-GLYPH: mẫu nhãn tổng cùng-dòng chấp nhận ký hiệu tiền bị OCR
//    vỡ ($ -> ฿/£/€) ở ô ký hiệu (fixture L-R05).
//  P1-FLAG-MISSING: validate() cờ tường minh khi subtotal vắng
//    mặt mà tổng có mặt, và khi nhãn số-món có mặt mà token số
//    chết (fixture S-0, L-R05/L-R06).
//  P1-DOMAINCORR: DomainCorrection sửa token CHỮ (tên món, nhãn
//    thuế) theo lexicon.json — không bao giờ chạm token số; mọi
//    sửa ghi vào result.corrections (DiagCorrection của Pha 0).
//  P1-CANDIDATES: result.totalCandidates + result.selectionTrace
//    (ứng viên-trước-chọn-sau cho totals; F5 nối thật ở Pha 3).
//  P1-GEOMETRY: khung hình học thống nhất khi có hộp dòng (cột
//    tiền = điểm mốt cạnh phải; các dạng cặp mang tên fixture
//    FX-SAMELINE/FX-SPLIT-NEXT/FX-BEFORE-LABEL); trọng tài: chỉ
//    thay kết quả trích món khi hình học khép E1 còn đường chữ
//    không khép.
// Phần Reconcile ở cuối file GIỮ NGUYÊN VĂN của bản nền (tách
// module M8 + nối vào parse() là điều kiện nghiệm thu của Pha 3,
// không thuộc Pha 1) — ngoại lệ duy nhất: điểm gọi tiền trong
// Reconcile cũng qua SafeMoney như mọi điểm gọi khác.

// MARK: - Kết quả đọc 1 dòng OCR

struct OCRLine {
    var text: String
    /// Độ tin cậy 0.0–1.0 của dòng này (từ Vision).
    var confidence: Double
    /// G2 (tầng cứu, DESIGN-V4 §2.6): các bản đọc THAY THẾ của
    /// đúng dòng này — Fragment.alternates của Vision
    /// (topCandidates) cộng dòng tương ứng của các lượt đọc
    /// ảnh khác, do ReadPipeline mang sang. Rỗng ở mọi đường
    /// không có OCR (chữ đã lưu / lớp chữ PDF): khi rỗng, hồ
    /// ứng viên KHÔNG sinh biến thể và hành vi của bộ đọc
    /// không đổi một ly so với trước G2.
    var alternates: [AltText] = []
}

// MARK: - Kết quả bóc tách 1 hoá đơn (bản nháp, chưa lưu)

struct ParsedLineItem {
    var name: String
    var qty: Int = 1
    var unitPriceCents: Int? = nil
    var amountCents: Int? = nil
    var taxFlag: String? = nil
    var itemCode: String? = nil
    // INTEGRATE-V2 (thuần cộng thêm, mặc định nil): metadata dòng cân
    // "W lb @ $U/lb" gắn kèm món bởi nhánh cùng-dòng — CHỈ là thông
    // tin phụ (kiểm chứng số học W x U ≈ tiền món khi gắn), không
    // tham gia cổng sổ của validate() và không phải trường model.
    var weightLb: Double? = nil
    var weightUnitCents: Int? = nil
    // PHA 1: chỉ số dòng nguồn của món (phục vụ corrections[] +
    // chẩn đoán v2; thuần cộng thêm, mặc định nil).
    var lineIndex: Int? = nil
}

struct ParsedTaxLine {
    var label: String
    var rateText: String? = nil
    var amountCents: Int
    // PHA 1: chỉ số dòng nguồn của dòng thuế (như lineIndex của món).
    var lineIndex: Int? = nil
}

/// PHA 1 (P1-CANDIDATES): một ứng viên tiền cho các trường neo —
/// F4 xuất TOÀN BỘ ứng viên kèm vai trò đã chọn/chưa chọn; việc
/// chọn cuối cùng phối hợp với F5 ở Pha 3.
struct TotalCandidate {
    var lineIndex: Int
    var cents: Int
    var role: String        // subtotal | tax | total | taxSummaryCandidate | unassigned
    var chosen: Bool
}

struct ParseResult {
    var vendor: String? = nil
    var vendorKey: String = "generic"   // "sams" khi nhận diện Sam's Club
    var date: Date? = nil
    var items: [ParsedLineItem] = []
    var subtotalCents: Int? = nil
    var taxes: [ParsedTaxLine] = []
    var totalCents: Int? = nil
    var cardLast4: String? = nil
    var cardBrand: String? = nil
    // PHA 3 (khoản treo Pha 1 — ca L-R09 đuôi "2580"): độ tin cậy
    // của DÒNG sinh ra đuôi thẻ + dấu hiệu dòng bị gộp với dòng
    // tổng. validate() dùng hai trường này để gắn cờ bất thường;
    // giá trị thẻ đọc được KHÔNG bị sửa (sửa số là việc của người
    // duyệt). 0 = không rõ (đường cũ / không có dòng thẻ).
    var cardConfidence: Double = 0
    var cardLineContaminated: Bool = false
    var dedupeKey: String? = nil
    var itemsSold: Int? = nil
    var warnings: [String] = []
    var vendorConfidence: Double = 0
    var dateConfidence: Double = 0
    var totalConfidence: Double = 0
    // WP5 (thuần cộng thêm): hạ cánh các trường model WP2 ĐÃ CÓ sẵn +
    // nguồn/gợi ý của hàm nhận diện tiệm. ParseResult là struct nháp,
    // không phải SwiftData model — không có rủi ro di trú.
    var vendorAddress: String? = nil
    var vendorPhone: String? = nil
    var storeNumber: String? = nil
    var vendorSource: String? = nil   // "tier1-exact" | "tier1-fuzzy" | "tier2-anchor"
    var vendorSuggestion: String? = nil   // nấc 3: CHỈ gợi ý, không bao giờ tự điền
    var vendorAnchorDisputed: Bool = false
    var rawText: String = ""
    // PHA 1 (thuần cộng thêm): vết + ứng viên + sửa chữ + ngữ nghĩa
    // in — phục vụ chẩn đoán v2 và cổng kiểm; không phải trường
    // model SwiftData.
    var corrections: [DiagCorrection] = []
    var selectionTrace: [String] = []
    var totalCandidates: [TotalCandidate] = []
    // CORE-V4 (gói V4-1, THUẦN CỘNG THÊM): kết quả trọng tài khối
    // tổng (Candidates.swift + Arbiter.swift, DESIGN-V4 §2/§3) —
    // chỉ parseV4 điền; parse() của v3 để mặc định. totalsProvenance
    // được ReadPipeline.finalize ghi vào ngăn provenance sẵn có
    // của hồ sơ chẩn đoán (tiền lệ cộng thêm, không đổi schema).
    var totalsProvenance: [String: FieldProvenance] = [:]
    /// CORE-V4 (gói V4-2, THUẦN CỘNG THÊM): provenance từng món
    /// của pha 3/4 (ItemsArbiter) — khoá "item[j]"; ReadPipeline
    /// .finalize ghi vào ngăn provenance của chẩn đoán cùng cách
    /// với totalsProvenance (schema giữ v2).
    var itemsProvenance: [String: FieldProvenance] = [:]
    var arbiterStatus: String? = nil   // closed|ambiguous|unclosed|budgetExceeded
    var arbiterDisputed: [String] = []
    var arbiterDeficitE1: Int? = nil
    var arbiterDeficitE2: Int? = nil
    var arbiterRegionHint: String? = nil
    var geometricCandidates: [ParsedLineItem] = []
    var itemsSoldLabelSeen: Bool = false
    var soldContribution: String = "byQuantity"  // printSemantics của vendor
    var vendorDataVersion: String = ""           // dataVersion của vendors.json đã dùng

    var taxTotalCents: Int { SafeMoney.sumCents(taxes.map { $0.amountCents }) ?? 0 }
}

// MARK: - Bộ bóc tách hoá đơn
//
// Luật toàn cục (VENDOR-FORMATS.md — không được phá):
// 1. Luôn đối chiếu chéo: Σ món ≈ subtotal; subtotal + thuế ≈ total.
//    Không khớp -> gắn cờ vào Hộp Chờ, TUYỆT ĐỐI không tự sửa số.
// 2. Đuôi thẻ CHỈ lấy từ dòng thanh toán có ký tự che (****2586...).
//    Mã ở chân hoá đơn kết thúc bằng 4 số KHÔNG phải đuôi thẻ (bẫy Home Depot).
// 3. Vùng loại trừ (Suggested Tip, Return Policy, MAX REFUND VALUE...) bị cắt
//    trước khi trích tổng/món.
// Sam's Club: cổng nguyên luật đã kiểm chứng ở parser-prototype v0.1/v0.2
// (Mẫu 001: 10 dòng món, subtotal 203.30, thuế 9.60+3.90, total 216.80, thẻ 2586).
// Tiệm khác: đường generic (vendor/ngày/thẻ/tổng) — tách từng món để bản sau.
//
// WP4 bước 2 (bản wp4-prep): F2b — parser chịu được nhãn/tiền TÁCH DÒNG
// (CODE-AUDIT F2b): máy trạng thái "nhãn chờ đúng 1 dòng" ở vòng tổng của
// cả hai nhánh + dòng chỉ-có-tiền hoàn tất món đang chờ ở nhánh Sam's.
// F2b chỉ đổi NƠI tìm tiền, không đổi CÁCH phán xét: validate() NGUYÊN VĂN.
//
// WP5 bước 2 (bản wp5-prep, nền wp4-prep): nhận diện tiệm 3 nấc theo
// WP5-SPEC — hàm identifyVendor chung chạy TRƯỚC rẽ nhánh (khớp tên
// toàn-bộ-dòng exact-trước-mờ-sau · neo phụ mạnh/yếu · món đặc trưng
// chỉ-gợi ý với bảng seed RỖNG); ĐƯỜNG RƠI DÒNG-ĐẦU của parseGeneric
// ĐÃ BỎ về mặt cấu trúc; validate() MỞ RỘNG kỷ luật C-11 cho tiệm/ngày
// (phần số học của validate() giữ nguyên văn). Bản Swift này là bản
// dịch của wp5-fixtures/vendor_port.py (đã kiểm chứng 19/19 ở bước 1)
// + extract_port.py cho phần trích địa chỉ/điện thoại/mã cửa hàng.
//
// M1-FIX (bản m1fix, nền wp5-prep): sửa hazard G4 + trích món generic.
// (a) Vòng tổng generic nhận dạng TIỀN-Ở-DÒNG-TRƯỚC: dòng chỉ-có-tiền
// mà dòng ngay sau là nhãn tổng trống thì tiền thuộc về nhãn đó, nhãn
// bị bỏ qua 1 nhịp để máy nhãn-chờ F2b không gán lệch tiếp. (b) Nhánh
// generic có đường trích món riêng (khối UPC, giá kề hai chiều, dòng
// "N@X") — trước đây generic không trích món nào. (c) Neo phụ cộng
// loại cụm-chữ: slogan Home Depot (bằng chứng luồng 003 thật).
// validate() KHÔNG đổi — phần số học nguyên văn như mọi bản trước.
// Port kiểm chứng: m1fix/port.py + m1fix/run_port.py (13/13).
//
// REPARSE (bản reparse, nền m1fix): cộng điểm vào reparse(storedText:)
// — chạy lại ĐÚNG parse(lines:) hiện hành trên văn bản thô ĐÃ LƯU của
// một hoá đơn cũ (nút "Đọc lại" ở màn Chi Tiết, xem ReceiptViews).
// Trước gói này engine mới chỉ áp cho lần quét mới; hoá đơn lưu từ
// Build 1 giữ số của bộ đọc cũ mãi mãi. Không fork logic: reparse chỉ
// khôi phục [OCRLine] từ chữ đã lưu rồi gọi parse(lines:) nguyên văn.
// validate() vẫn KHÔNG đổi. Port kiểm chứng: reparse/port_check.py.
//
// INTEGRATE-V2 (bản này, nền p2-fix = reparse + khối Reconcile ở cuối
// file — khối Reconcile giữ NGUYÊN, không lời gọi mới nào từ parse()):
// đưa kết quả chấm lại buổi đo 2026-11-11 vào đường generic:
// (1) Trích món v2: đường khối UPC cũ (cộng 2 vá có điều kiện + chặn
//     dòng '<mã> / <mã>' mở khối) + NHÁNH MÓN CÙNG-DÒNG cho hoá đơn
//     kiểu "tên ... tiền cùng dòng" (Pan-Asia/Walmart/Costco/Clover)
//     + đọc nhãn số món ở đường generic. Bản thiết kế đã chứng minh
//     ở bench-prep/port_v2.py (chấm lại buổi đo: ca thật A0 trọn sổ
//     0/15 -> 3/15, Σ món khép 8/11 ca L-R) — bản Swift này chép
//     trung thực thuật toán đó; bản gương kiểm chứng là
//     integrate-v2/port_swift_mirror.py (chép từ CHÍNH bản Swift
//     này), KHÔNG chép từ port_v2.
// (2) Vá tầng totals/ngày theo bằng chứng buổi đo (mới, ngoài
//     port_v2): dòng thuế mang SUẤT mà nhãn không bắt đầu bằng TAX
//     ("Coweta sales tax 10.05% $16.53"); ngày tháng chữ kiểu Clover
//     ("20-May-2026 1:11:30P") + giờ đứng riêng dòng; neo tổng bằng
//     số học theo tinh thần Reconcile khi nhãn vỡ/mất (chỉ nhận số
//     ĐÃ IN trên bill và chỉ khi phương trình khép DUY NHẤT — không
//     nặn số, không ghi thuế suy diễn ngoài một dòng tiền đã in mà
//     vai trò của nó được phương trình chứng minh).
// Đường Sam's + validate() giữ nguyên văn như bản nền.

// MARK: - DomainCorrector (P1-DOMAINCORR) — sửa CHỮ bằng tri
// thức miền (DESIGN-FINAL §3.4(b))
//
// Lexicon đóng băng + có phiên bản nạp từ lexicon.json (kèm app;
// bản ở staging: v3-phase1/lexicon.json). LUẬT CỨNG: tầng này chỉ
// chạm TOKEN TOÀN CHỮ CÁI trong trường CHỮ (tên món "itemName",
// nhãn thuế "taxLabel") — token số (tiền, qty, ngày, đuôi thẻ,
// mã) không bao giờ qua đây; số là lãnh địa của F5. Hai cơ chế:
//  (A) known-variant: token trùng một biến thể đã biết của một
//      mục -> thay bằng canonical của mục đó;
//  (B) edit-distance-1: token dài ≥5, cách đúng MỘT biến thể đã
//      biết của đúng MỘT mục duy nhất đúng 1 phép sửa -> canonical.
// Mọi lần sửa ghi vào corrections[] với provenance
// .domainCorrected(lexiconVersion) (DiagCorrection của Pha 0).
// Nạp lexicon hỏng -> tầng TRƠ (không sửa gì): fail-closed.

private struct LexiconFile: Decodable {
    var lexiconVersion: String
    var entries: [Entry]
    struct Entry: Decodable {
        var canonical: String
        var field: String
        var variants: [String]
    }
}

enum DomainCorrector {
    private static let store: (version: String, variantMap: [String: (canonical: String, field: String)]) = {
        guard let url = Bundle.main.url(forResource: "lexicon", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(LexiconFile.self, from: data) else {
            return ("unloaded", [:])
        }
        var map: [String: (String, String)] = [:]
        for e in file.entries {
            for v in e.variants {
                map[v.uppercased()] = (e.canonical, e.field)
            }
        }
        return (file.lexiconVersion, map)
    }()

    static var lexiconVersion: String { store.version }

    private static func caseLike(token: String, canonical: String) -> String {
        if token == token.uppercased() { return canonical.uppercased() }
        if let first = token.first, first.isUppercase {
            let lower = canonical.lowercased()
            return lower.prefix(1).uppercased() + lower.dropFirst()
        }
        return canonical.lowercased()
    }

    /// Sửa các token chữ của `text` thuộc `field`; ghi mỗi lần sửa
    /// vào `corrections`. Trả text đã sửa.
    static func correct(_ text: String, field: String, lineIndex: Int?,
                        corrections: inout [DiagCorrection]) -> String {
        guard !store.variantMap.isEmpty else { return text }
        var out = ""
        var i = text.startIndex
        while i < text.endIndex {
            if text[i].isLetter && text[i].isASCII {
                var j = i
                while j < text.endIndex, text[j].isLetter, text[j].isASCII {
                    j = text.index(after: j)
                }
                let token = String(text[i..<j])
                out += correctToken(token, field: field, lineIndex: lineIndex,
                                    corrections: &corrections)
                i = j
            } else {
                out.append(text[i])
                i = text.index(after: i)
            }
        }
        return out
    }

    private static func correctToken(_ token: String, field: String, lineIndex: Int?,
                                     corrections: inout [DiagCorrection]) -> String {
        guard token.count >= 4 else { return token }
        let upper = token.uppercased()
        if let hit = store.variantMap[upper], hit.field == field {
            let canonical = hit.canonical
            if canonical.uppercased() != upper {
                corrections.append(DiagCorrection(
                    field: field, itemIndex: lineIndex, from: token, to: canonical,
                    lexiconVersion: store.version, rule: "known-variant"))
                return caseLike(token: token, canonical: canonical)
            }
            return token
        }
        if token.count >= 5 {
            var candidates: Set<String> = []
            for (variant, hit) in store.variantMap
            where hit.field == field && variant != upper
                    && VendorData.levenshtein(upper, variant) == 1 {
                candidates.insert(hit.canonical)
            }
            if candidates.count == 1, let canonical = candidates.first {
                corrections.append(DiagCorrection(
                    field: field, itemIndex: lineIndex, from: token, to: canonical,
                    lexiconVersion: store.version, rule: "edit-distance-1"))
                return caseLike(token: token, canonical: canonical)
            }
        }
        return token
    }
}

enum ReceiptParser {

    // V4-4 (D-V4-3 + DESIGN-V4 §8.2): đường đọc v3 — parse()
    // ở ngay dưới + parseSams/parseGeneric và toàn bộ helper
    // chỉ phục vụ chúng — bị biên dịch LOẠI khỏi bản giao
    // (target app khai GLKEEPER_V4_ONLY trong project.yml).
    // Nguồn giữ nguyên một bản duy nhất: bench + harness
    // không khai điều kiện nên vẫn biên dịch đủ đường v3 làm
    // làn đối chứng đo (§0/§8.1). Các vùng #if trong file
    // này đều mang cùng điều kiện và cùng lý do.
#if !GLKEEPER_V4_ONLY
    static func parse(lines input: [OCRLine], boxes: [CGRect?]? = nil) -> ParseResult {
        let lines = input
            .map { OCRLine(text: $0.text.trimmingCharacters(in: .whitespaces), confidence: $0.confidence) }
            .filter { !$0.text.isEmpty }
        var result = ParseResult()
        result.rawText = lines.map { $0.text }.joined(separator: "\n")

        // WP5: nhận diện tiệm 3 nấc chạy TRƯỚC, một hàm chung cho mọi
        // đường — kết quả quyết định rẽ nhánh Sam's/generic (thay isSams
        // khớp-chuỗi cũ) và là nguồn tên tiệm DUY NHẤT của cả parser.
        // PHA 1: nhận diện nay đọc DỮ LIỆU vendors.json qua
        // VendorData (M7); rẽ nhánh theo parserPath của mục dữ liệu.
        let identification = identifyVendor(lines: lines)
        if identification.parserPath == "sams" {
            result = parseSams(lines: lines)
        } else {
            result = parseGeneric(lines: lines, identifiedVendor: identification.vendor, boxes: boxes)
        }
        result.vendor = identification.vendor
        result.vendorKey = identification.vendorKey
        result.vendorConfidence = identification.confidence
        result.vendorSource = identification.source
        result.vendorSuggestion = identification.suggestion
        result.vendorAnchorDisputed = identification.anchorDisputed
        result.soldContribution = identification.entry?.soldContribution ?? "byQuantity"
        result.vendorDataVersion = VendorData.shared.dataVersion
        let contact = extractVendorContact(lines: lines)
        result.vendorAddress = contact.address
        result.vendorPhone = contact.phone
        result.storeNumber = contact.storeNumber
        result.rawText = lines.map { $0.text }.joined(separator: "\n")
        // P1-FLAG-MISSING: bill có in nhãn số món nhưng không đọc
        // được con số -> ghi nhận để validate() sinh cờ (không đoán).
        if result.itemsSold == nil,
           lines.contains(where: { $0.text.uppercased().contains("ITEMS SOLD") || $0.text.uppercased().contains("ITEM COUNT") }) {
            result.itemsSoldLabelSeen = true
        }
        // P1-DOMAINCORR: sửa CHỮ sau trích xuất, trước validate —
        // tên món + nhãn thuế; token số không qua tầng này.
        for i in result.items.indices {
            result.items[i].name = DomainCorrector.correct(
                result.items[i].name, field: "itemName",
                lineIndex: result.items[i].lineIndex,
                corrections: &result.corrections)
        }
        for i in result.taxes.indices {
            result.taxes[i].label = DomainCorrector.correct(
                result.taxes[i].label, field: "taxLabel",
                lineIndex: result.taxes[i].lineIndex,
                corrections: &result.corrections)
        }
        result.warnings = validate(result)
        return result
    }
#endif

    // MARK: - CORE-V4 (V4-1 + V4-2 + V4-3 + V4-4): ứng viên + trọng tài
    //
    // parseV4 là ĐƯỜNG ĐỌC DUY NHẤT VỀ CẤU TRÚC từ gói V4-3
    // (DESIGN-V4 §5/§9): KHÔNG gọi parse() của v3, KHÔNG đọc
    // parserPath — parseSams/parseGeneric không còn được gọi
    // từ đường v4. Mọi trường đều sinh từ ứng viên trên cùng
    // một đường: tên tiệm (identifyVendor — nguồn tên duy
    // nhất, 3 nấc như cũ), ngày (DateCandidateFactory §2.3(g)),
    // thẻ (CardCandidateFactory §2.3(f)), neo số món
    // (findItemsSoldGeneric — tập mẫu hợp nhất của hai nhánh
    // cũ, chạy cho mọi tiệm), khối tổng (TotalsArbiter §3),
    // khối món (ItemsArbiter §4). Tri thức tiệm chỉ còn ba
    // dạng DỮ LIỆU: tên + printSemantics (soldContribution) +
    // hints của vendors.json (biến thể nhãn + hình dạng mã —
    // chấm điểm, không phải cổng; xem VendorData.Hints).
    // parse() của v3 GIỮ NGUYÊN làm đối chứng đo ở cổng luồng
    // (bench/harness biên dịch không điều kiện); từ gói V4-4
    // app mặc định v4 qua ReadPipeline, tem nâng core-v4-1,
    // và đường v3 bị loại khỏi bản giao bằng điều kiện biên
    // dịch (xem chú thích ở parse() + project.yml).
    static func parseV4(lines input: [OCRLine], boxes: [CGRect?]? = nil) -> ParseResult {
        // Cùng phép chuẩn hoá dòng mà parse() áp ở đầu vào —
        // lineIndex phải khớp giữa mọi tầng của đường v4.
        let lines = input
            .map { OCRLine(text: $0.text.trimmingCharacters(in: .whitespaces),
                           confidence: $0.confidence,
                           alternates: $0.alternates) }
            .filter { !$0.text.isEmpty }
        var result = ParseResult()
        result.rawText = lines.map { $0.text }.joined(separator: "\n")

        // Tiệm: CHỈ cho trường tên (nguồn tên duy nhất) + dữ
        // liệu đi kèm (printSemantics, hints). parserPath của
        // mục dữ liệu KHÔNG được đọc ở đây nữa.
        let identification = identifyVendor(lines: lines)
        result.vendor = identification.vendor
        result.vendorKey = identification.vendorKey
        result.vendorConfidence = identification.confidence
        result.vendorSource = identification.source
        result.vendorSuggestion = identification.suggestion
        result.vendorAnchorDisputed = identification.anchorDisputed
        result.soldContribution = identification.entry?.soldContribution ?? "byQuantity"
        result.vendorDataVersion = VendorData.shared.dataVersion
        let hints = identification.entry?.hints
        let contact = extractVendorContact(lines: lines)
        result.vendorAddress = contact.address
        result.vendorPhone = contact.phone
        result.storeNumber = contact.storeNumber

        // Ngày/giờ: ứng viên (§2.3(g)).
        let dateEx = DateCandidateFactory.extract(lines: lines)
        result.date = dateEx.date
        result.dateConfidence = dateEx.confidence

        // Thẻ: ứng viên (§2.3(f)). Tranh chấp đuôi → thẻ trống
        // + cờ riêng ở cuối hàm (không chọn thầm).
        let cardEx = CardCandidateFactory.extract(lines: lines)
        result.cardLast4 = cardEx.last4
        result.cardBrand = cardEx.brand
        result.cardConfidence = cardEx.confidence

        // Neo số món đã bán: một bộ mẫu hợp nhất cho mọi tiệm.
        result.itemsSold = findItemsSoldGeneric(lines: lines)
        // P1-FLAG-MISSING (giữ kỷ luật của parse()): bill có in
        // nhãn số món mà không đọc được số → validate() sinh cờ.
        if result.itemsSold == nil,
           lines.contains(where: { $0.text.uppercased().contains("ITEMS SOLD") || $0.text.uppercased().contains("ITEM COUNT") }) {
            result.itemsSoldLabelSeen = true
        }

        // Khối tổng + khối món: trọng tài (V4-1/V4-2). Σmón của
        // v3 KHÔNG còn tồn tại trong đường này — trọng tài
        // tổng chạy với itemsSumCents = nil; δ1 do pha món tự
        // tính trên món v4 (ItemsArbiter ghi đè deficitE1).
        let arb = TotalsArbiter.arbitrate(
            lines: lines, itemsSumCents: nil,
            vendorVariants: hints?.labelVariants)
        let itemPhase = ItemsArbiter.assign(
            lines: lines, totals: arb,
            soldAnchor: result.itemsSold,
            contribution: result.soldContribution,
            vendorVariants: hints?.labelVariants,
            codeShapes: hints?.itemCodeShapes ?? [])
        let finalTotals = itemPhase.totals
        result.items = itemPhase.items
        result.itemsProvenance = itemPhase.provenance
        result.subtotalCents = finalTotals.subtotalCents
        result.taxes = finalTotals.taxes
        result.totalCents = finalTotals.totalCents
        result.totalConfidence = finalTotals.totalLineConfidence
        result.totalsProvenance = finalTotals.provenance
        result.arbiterStatus = finalTotals.status
        result.arbiterDisputed = finalTotals.disputedSolutions
        result.arbiterDeficitE1 = itemPhase.deficitE1
        result.arbiterDeficitE2 = finalTotals.deficitE2
        result.arbiterRegionHint = finalTotals.regionHint
        if !finalTotals.totalCandidates.isEmpty {
            result.totalCandidates = finalTotals.totalCandidates
        }
        result.selectionTrace = ["arbiter-v4/\(finalTotals.status)"]
            + arb.trace + itemPhase.trace + cardEx.trace
        // P1-DOMAINCORR (như parse() áp cho đường v3): sửa CHỮ
        // trên tên món + nhãn thuế của đường v4 trước validate —
        // token số không qua tầng này. Ở V4-1/V4-2 bước này vô
        // tình rơi mất vì parseV4 thay món/thuế SAU khi parse()
        // đã sửa trên bản v3 bị bỏ; V4-3 khôi phục đúng thiết
        // kế (§2.3(c)) trên đúng dữ liệu v4.
        for i in result.items.indices {
            result.items[i].name = DomainCorrector.correct(
                result.items[i].name, field: "itemName",
                lineIndex: result.items[i].lineIndex,
                corrections: &result.corrections)
        }
        for i in result.taxes.indices {
            result.taxes[i].label = DomainCorrector.correct(
                result.taxes[i].label, field: "taxLabel",
                lineIndex: result.taxes[i].lineIndex,
                corrections: &result.corrections)
        }
        // P2-0/C-6: sinh khoá chống trùng TRÊN ĐƯỜNG V4 (đường
        // app thật). Trước gói này mọi điểm sinh khoá nằm trong
        // parseSams/parseGeneric ở vùng #if !GLKEEPER_V4_ONLY
        // nên dedupeKey luôn nil và cảnh báo trùng không bao
        // giờ cháy. Luật giữ nguyên hệt luật cũ: dòng TC# có
        // 16–24 chữ số -> "SAMS-TC-" (Sam's) / "TC-" (tiệm
        // khác); khoá yếu GEN| KHÔNG sinh ở đây mà sinh lúc
        // lưu từ số anh đã sửa (ReviewView.save).
        for line in lines {
            if let groups = matchGroups(line.text,
                                        pattern: #"^TC#\s+([\d ]+)$"#),
               let raw = groups.first ?? nil {
                let digits = raw.replacingOccurrences(of: " ", with: "")
                if digits.count >= 16 && digits.count <= 24 {
                    result.dedupeKey =
                        (result.vendorKey == "sams" ? "SAMS-TC-" : "TC-") + digits
                }
                break
            }
        }
        result.warnings = validate(result)
        if finalTotals.status == "ambiguous" {
            result.warnings.append(
                "Trọng tài khối tổng: có \(finalTotals.disputedSolutions.count) cách khép sổ khác nhau — trường tranh chấp để trống, anh kiểm tra giúp.")
        }
        if finalTotals.status == "budgetExceeded" {
            result.warnings.append(
                "Trọng tài khối tổng: vượt ngân sách tìm kiếm — khối tổng chưa khép sổ.")
        }
        if cardEx.disputed {
            result.warnings.append(
                "Thẻ: có hai đuôi thẻ khác nhau cùng bằng chứng mạnh — chưa chọn đuôi nào, anh kiểm tra giúp.")
        }
        if dateEx.distinctDays > 1 {
            result.warnings.append(
                "Ngày: có \(dateEx.distinctDays) ngày khác nhau trên tờ — app lấy ngày in đầu tiên, anh kiểm tra giúp.")
        }
        if let d1 = itemPhase.deficitE1, abs(d1) > ItemsArbiter.e1ToleranceCents {
            result.warnings.append(
                "Khối món chưa khép: tổng tiền món lệch tạm tính \(d1) xu (δ1) — thâm hụt nằm ở khối món.")
        }
        // FL-299 (vòng 3, PHƯƠNG ÁN DỰ PHÒNG): thuế nhận CHỈ bằng vị
        // trí trên một tờ KHÔNG in nhãn hay % thuế nào thì không được
        // khép lặng — gắn cờ "chưa chắc". Chỉ THÊM cờ: không đổi số,
        // không đổi trạng thái trọng tài (cờ không vào thang điểm §3.6
        // hay quyết định ROI).
        for t in unsupportedPositionalTaxes(lines: lines, taxes: result.taxes,
                                            vendorVariants: hints?.labelVariants) {
            result.warnings.append(
                "Thuế \(warningMoney(t.amountCents)) chỉ suy từ VỊ TRÍ trên tờ — tờ không in nhãn hay % thuế nào. Chưa chắc: anh kiểm lại với giấy giúp.")
        }
        return result
    }

    /// FL-299 (vòng 3): các dòng thuế cuối KHÔNG có bằng chứng in —
    /// cả tờ không có dòng họ TAX/TAXSUM nào (kể cả dòng chỉ-nhãn, kể
    /// cả ngoài khối tổng) VÀ dòng của token thuế không có % in (đúng
    /// phép rateSupported trọng tài dùng khi nhận thuế). Thuế không có
    /// dòng (ước tính) không thuộc diện này — đã mang nhãn ƯỚC TÍNH.
    /// Không tồn tại quy tắc sạch tách thuế thật khỏi thuế ma ở diện
    /// này (25-exxon-1: 7.00 là tiền rửa xe; 19-mcdonalds-2: 0.07 là
    /// thuế thật, cùng chữ ký) — nên chỉ GẮN CỜ, không bỏ thuế.
    static func unsupportedPositionalTaxes(lines: [OCRLine], taxes: [ParsedTaxLine],
                                           vendorVariants: [String: String]?) -> [ParsedTaxLine] {
        guard !taxes.isEmpty else { return [] }
        let (_, rates, labels) = CandidateFactory.generate(lines: lines,
                                                           vendorVariants: vendorVariants)
        if labels.contains(where: { $0.family == "TAX" || $0.family == "TAXSUM" }) { return [] }
        return taxes.filter { t in
            guard let li = t.lineIndex, li >= 0, li < labels.count else { return false }
            return !CandidateFactory.rateSupported(lineIndex: li, rates: rates)
        }
    }

    // MARK: - REPARSE: đọc lại hoá đơn đã lưu từ văn bản thô đã lưu
    //
    // OCRLine.confidence KHÔNG được lưu cùng hoá đơn (chỉ lưu chữ), nên
    // dòng khôi phục phải gán một độ tin cậy thay thế. Truy vết mọi nơi
    // Parser dùng confidence của dòng: nó chỉ chảy vào đúng 3 trường
    // phái sinh — totalConfidence (mọi điểm gán TỔNG ở hai nhánh),
    // vendorConfidence (nấc 1 của identifyVendor: exact = conf,
    // fuzzy = conf × 0.8; nấc 2 neo phụ tự gán 0.5, không dùng tới),
    // dateConfidence (findDateTime / findDateOnly) — và validate() đọc
    // 3 trường đó qua ngưỡng 0.60/0.85, mọi điều kiện đều kèm "> 0".
    // Hệ quả của từng lựa chọn: 1.0 -> validate() câm mọi cảnh báo độ
    // tin cậy (YẾU hơn đường quét); 0.0 -> cũng câm vì vướng điều kiện
    // "> 0" (yếu nhất); 0.5 -> nằm dưới ngưỡng 0.60 nên cả 3 trường
    // đều nhận cảnh báo MẠNH NHẤT ("độ tin cậy THẤP — bắt buộc kiểm
    // tra lại với giấy") — thà thêm cờ còn hơn mất cờ, đúng kỷ luật
    // Hộp Chờ. 0.5 cũng là mức parser tự gán cho bằng chứng nấc 2
    // ("không phải tên in trên giấy") — cùng một nghĩa: bằng chứng
    // không còn kiểm chứng trực tiếp được. Số trích ra (tiền/món/
    // tiệm/ngày/thẻ) không phụ thuộc confidence ở bất kỳ nhánh nào.

    /// Độ tin cậy gán cho dòng khôi phục từ văn bản đã lưu (xem trên).
    static let recoveredLineConfidence: Double = 0.5

#if !GLKEEPER_V4_ONLY
    // MARK: - SAM'S CLUB (cổng từ prototype v0.1 đã đạt Mẫu 001)

    private static func parseSams(lines: [OCRLine]) -> ParseResult {
        var r = ParseResult()
        r.vendorKey = "sams"
        // Tên tiệm + vendorConfidence: parse() gắn từ identifyVendor
        // (WP5) sau khi hàm này trả về — ở đây KHÔNG tự đặt tên tiệm.

        // Ngày + giờ: MM/DD/YY(YY) HH:MM
        if let found = findDateTime(in: lines) {
            r.date = found.date
            r.dateConfidence = found.confidence
        }

        // --- Dòng món ---
        var pending: ParsedLineItem? = nil
        for (index, line) in lines.enumerated() {
            let text = line.text

            // Dòng số lượng: "2 AT 1 FOR 19.48 38.96 Y"
            if let q = matchQtyLine(text), var p = pending {
                p.qty = q.qty
                p.unitPriceCents = q.unitCents
                p.amountCents = q.amountCents
                if let flag = q.flag { p.taxFlag = flag }
                r.items.append(p)
                pending = nil
                continue
            }

            // F2b: dòng CHỈ có tiền ("19.48 Y") hoàn tất món đang chờ —
            // tiền của món rớt xuống dòng thị giác ngay sau khi hàng bị xé
            // dù đã ráp (ảnh lệch). Không có món chờ thì dòng tiền lẻ rơi
            // tiếp xuống các luật dưới (không luật nào nhận) như cũ.
            if var p = pending,
               let m = matchGroups(text, pattern: #"^\$?(\d[\d,]*\.\d{2})(-)?\s*([YT])?$"#), m.count == 3,
               let cents = SafeMoney.parseCents(m[0] ?? "", negative: m[1] != nil) {
                p.amountCents = cents
                p.unitPriceCents = cents
                if let flag = m[2] { p.taxFlag = flag }
                r.items.append(p)
                pending = nil
                continue
            }

            // Dòng giảm giá Instant Savings: "INST SV <tên> [tiền] [cờ]"
            if let rest = matchPrefix(text, pattern: #"^INST SV\s+(.+)$"#) {
                if let tail = trailingAmount(in: rest) {
                    var item = ParsedLineItem(name: "INST SV " + tail.name)
                    item.amountCents = tail.cents
                    item.unitPriceCents = tail.cents
                    item.taxFlag = tail.flag
                    item.lineIndex = index
                    r.items.append(item)
                } else {
                    var item = ParsedLineItem(name: "INST SV " + rest)
                    item.lineIndex = index
                    pending = item
                }
                continue
            }

            // Dòng món thường: mã 10 số + phần còn lại
            if let m = matchGroups(text, pattern: #"^(\d{10})\s+(.+)$"#), m.count == 2 {
                let code = m[0]
                let rest = m[1] ?? ""
                if let tail = trailingAmount(in: rest), !tail.name.isEmpty {
                    var item = ParsedLineItem(name: tail.name)
                    item.itemCode = code
                    item.amountCents = tail.cents
                    item.unitPriceCents = tail.cents
                    item.taxFlag = tail.flag
                    item.lineIndex = index
                    r.items.append(item)
                } else {
                    var item = ParsedLineItem(name: rest)
                    item.itemCode = code
                    item.lineIndex = index
                    pending = item
                }
                continue
            }
            // Dòng khác: bỏ qua (qty line lạc khi không có pending cũng rơi xuống đây).
        }
        if let p = pending { r.items.append(p) }

        // --- Tổng / thuế / thẻ / TC# ---
        // F2b: máy trạng thái nhãn-chờ (đúng đặc tả CODE-AUDIT F2b).
        // pendingKind: "SUBTOTAL" | "TOTAL" | "TAX"; với TAX giữ thêm
        // nhãn hiển thị ("TAX 1") + tỉ lệ đọc được trên dòng nhãn để
        // dòng thuế tách không thua thông tin so với đường cùng-dòng.
        var pendingKind: String? = nil
        var pendingTaxLabel: String? = nil
        var pendingTaxRate: String? = nil
        for (index, line) in lines.enumerated() {
            let text = line.text
            // Dòng chỉ-có-tiền hoàn tất nhãn đang chờ.
            if let kind = pendingKind,
               let m = matchGroups(text, pattern: #"^\$?(\d[\d,]*\.\d{2})(-)?$"#), m.count == 2,
               let cents = SafeMoney.parseCents(m[0] ?? "", negative: m[1] != nil) {
                switch kind {
                case "SUBTOTAL":
                    r.subtotalCents = cents
                case "TOTAL":
                    r.totalCents = cents
                    r.totalConfidence = line.confidence
                default:
                    r.taxes.append(ParsedTaxLine(label: pendingTaxLabel ?? "TAX",
                                                  rateText: pendingTaxRate,
                                                  amountCents: cents,
                                                  lineIndex: index))
                }
                pendingKind = nil
                pendingTaxLabel = nil
                pendingTaxRate = nil
                continue
            }
            // Dòng chỉ-có-nhãn (TAX được kèm thứ hạng + tỉ lệ, chưa có tiền).
            if let lm = matchGroups(text, pattern: #"^(SUBTOTAL|TOTAL|TAX\s+(\d)(?:\s+([\d.]+)\s*%)?)$"#), lm.count == 3 {
                let head = lm[0] ?? ""
                if head == "SUBTOTAL" || head == "TOTAL" {
                    pendingKind = head
                    pendingTaxLabel = nil
                    pendingTaxRate = nil
                } else {
                    pendingKind = "TAX"
                    pendingTaxLabel = "TAX \(lm[1] ?? "")"
                    pendingTaxRate = lm[2]
                }
                continue
            }
            // Mọi dòng khác: nhãn chờ HẾT HẠN — đúng 1 dòng ân hạn, không
            // bao giờ vươn qua một dòng chữ để vớ số ở xa (CODE-AUDIT F2b).
            pendingKind = nil
            pendingTaxLabel = nil
            pendingTaxRate = nil
            if let m = matchGroups(text, pattern: #"^SUBTOTAL\s+\$?(\d[\d,]*\.\d{2})(-)?$"#),
               let cents = SafeMoney.parseCents(m[0] ?? "", negative: m[1] != nil) {
                r.subtotalCents = cents
                continue
            }
            if let m = matchGroups(text, pattern: #"^TAX\s+(\d)\s+([\d.]+)\s*%\s+\$?(\d[\d,]*\.\d{2})(-)?$"#), m.count == 4,
               let amount = SafeMoney.parseCents(m[2] ?? "", negative: m[3] != nil) {
                r.taxes.append(ParsedTaxLine(label: "TAX \(m[0] ?? "")", rateText: m[1], amountCents: amount, lineIndex: index))
                continue
            }
            if let m = matchGroups(text, pattern: #"^TOTAL\s+\$?(\d[\d,]*\.\d{2})(-)?$"#),
               let cents = SafeMoney.parseCents(m[0] ?? "", negative: m[1] != nil) {
                r.totalCents = cents
                r.totalConfidence = line.confidence
                continue
            }
            if let m = matchGroups(text, pattern: #"^#\s*ITEMS SOLD\s+(\d+)$"#) {
                r.itemsSold = SafeMoney.parseQty(m[0] ?? "")
                continue
            }
            if let tc = matchPrefix(text, pattern: #"^TC#\s+([\d ]+)$"#) {
                let digits = tc.replacingOccurrences(of: " ", with: "")
                if digits.count >= 16 && digits.count <= 24 {
                    r.dedupeKey = "SAMS-TC-" + digits
                }
                continue
            }
        }
        let card = findCard(lines: lines)
        r.cardLast4 = card.last4
        r.cardBrand = card.brand
        r.cardConfidence = card.confidence
        r.cardLineContaminated = card.contaminated
        return r
    }

    // MARK: - GENERIC (mọi tiệm khác — Build 1 chỉ lấy trường cốt lõi)

    private static func parseGeneric(lines: [OCRLine], identifiedVendor: String?, boxes: [CGRect?]? = nil) -> ParseResult {
        var r = ParseResult()
        r.vendorKey = "generic"

        // Vendor: WP5 — tên tiệm CHỈ từ identifyVendor (nấc 1 khớp tên /
        // nấc 2 neo phụ). Đường rơi dòng-đầu của Build 1 (nguồn lỗi
        // "How doers" trên Mẫu 003) ĐÃ BỎ về mặt cấu trúc: không khớp
        // thì để trống, validate() gắn cảnh báo, anh nhập tay.
        r.vendor = identifiedVendor

        // Ngày — INTEGRATE-V2: findDateTime/findDateOnly đã cộng mẫu
        // tháng chữ (xem dưới). Đường GHÉP GIỜ: hoá đơn thật có ca
        // ngày và giờ bị OCR tách thành hai dòng rời thì ngày-không-
        // giờ được ghép với giờ tìm được quanh dòng ngày.
        // PHA 1 (P1-DATE-MERGE, DESIGN-FINAL §3.4): ghép trong ±3
        // dòng quanh dòng ngày, chỉ xét dòng KHÔNG chứa ngày (không
        // có ngày cạnh tranh); ưu tiên khoảng cách nhỏ nhất, cùng
        // khoảng cách thì dòng chỉ-có-giờ thắng dòng giờ-nhúng (vd
        // dòng TERMINAL của L-R03); độ tin cậy giảm một nấc (×0.9)
        // và ghi vết vào selectionTrace. Đường Sam's không đổi.
        if let found = findDateTime(in: lines) {
            r.date = found.date
            r.dateConfidence = found.confidence
        } else if let found = findDateOnlyIndexed(in: lines) {
            if let t = findTimeNear(in: lines, dateIndex: found.index),
               let merged = mergingTime(into: found.date, hour: t.hour, minute: t.minute) {
                r.date = merged
                r.dateConfidence = min(found.confidence, t.confidence) * 0.9
                r.selectionTrace.append("date := ngày dòng \(found.index) + giờ dòng \(t.index) (\(t.standalone ? "chỉ-có-giờ" : "giờ nhúng trong dòng không-ngày"), ±3 dòng, P1-DATE-MERGE)")
            } else {
                r.date = found.date
                r.dateConfidence = found.confidence
            }
        }

        // Tổng: cắt vùng loại trừ TRƯỚC (Suggested Tip chứa tổng giả).
        // F2b: cùng máy trạng thái nhãn-chờ như nhánh Sam's, theo pattern
        // của nhánh generic; TOTAL vẫn tôn trọng vùng loại trừ
        // (ignoreTotals) y như đường cùng-dòng.
        var ignoreTotals = false
        var pendingKind: String? = nil   // "SUBTOTAL" | "TOTAL" | "TAX"
        var skipNext = false   // M1-FIX: nhãn đã được dòng tiền ngay trước nhận
        // INTEGRATE-V2: sổ theo dõi cho tầng neo tổng (anchorTotals)
        // và luật dòng thuế mang suất.
        var claimedIndices = Set<Int>()   // dòng đã sinh giá trị tổng/thuế
        var claimedRoles: [Int: String] = [:]   // PHA 1: vai trò ứng viên theo dòng (P1-CANDIDATES)
        var taxLineIndices: [Int] = []    // chỉ số dòng nguồn của r.taxes (song song)
        var totalsSeen = false            // đã gặp bất kỳ neo vùng tổng nào
        var totalTaxSummary: (index: Int, cents: Int)? = nil
        for (index, line) in lines.enumerated() {
            let text = line.text
            let upper = text.uppercased()
            // M1-FIX: dòng nhãn đã có tiền từ dòng ngay trước (xem
            // khối tiền-trước-nhãn ở dưới) -> bỏ qua, không cho máy
            // nhãn-chờ F2b dựng chờ mới trên nhãn đã xong.
            if skipNext {
                skipNext = false
                pendingKind = nil
                continue
            }
            // F2b: dòng chỉ-có-tiền hoàn tất nhãn đang chờ.
            if let kind = pendingKind,
               let m = matchGroups(text, pattern: #"^\$?(\d[\d,]*\.\d{2})(-)?$"#), m.count == 2,
               let cents = SafeMoney.parseCents(m[0] ?? "", negative: m[1] != nil) {
                switch kind {
                case "SUBTOTAL":
                    if r.subtotalCents == nil {
                        r.subtotalCents = cents
                        r.selectionTrace.append("subtotal := dòng \(index) (tiền sau nhãn trống)")
                    }
                    claimedRoles[index] = "subtotal"
                case "TOTAL":
                    if !ignoreTotals, r.totalCents == nil {
                        r.totalCents = cents
                        r.totalConfidence = line.confidence
                        r.selectionTrace.append("total := dòng \(index) (tiền sau nhãn trống)")
                    }
                    claimedRoles[index] = "total"
                default:
                    r.taxes.append(ParsedTaxLine(label: "TAX", rateText: nil, amountCents: cents, lineIndex: index))
                    taxLineIndices.append(index)
                    claimedRoles[index] = "tax"
                    r.selectionTrace.append("tax[\(r.taxes.count - 1)] := dòng \(index) (tiền sau nhãn thuế trống)")
                }
                claimedIndices.insert(index)
                totalsSeen = true
                pendingKind = nil
                continue
            }
            // M1-FIX (tiền-trước-nhãn): dòng CHỈ có tiền mà dòng NGAY
            // SAU là nhãn tổng trống -> tiền thuộc về nhãn đó (dạng
            // Mẫu 003 thật: "96.91 / SUBTOTAL", "$105.16 / TOTAL").
            // Chỉ nhận đúng 1 dòng kề — không vươn xa; nhãn đã nhận
            // được đánh dấu bỏ qua (skipNext) để không bị gán tiền
            // của nhãn kế tiếp, đúng gốc hazard G4. TOTAL vẫn tôn
            // trọng vùng loại trừ như đường cùng-dòng.
            if let m = matchGroups(text, pattern: #"^\$?(\d[\d,]*\.\d{2})(-)?$"#), m.count == 2,
               let cents = SafeMoney.parseCents(m[0] ?? "", negative: m[1] != nil),
               index + 1 < lines.count {
                let next = lines[index + 1].text
                let nextUpper = next.uppercased()
                var claimed = false
                if matchGroups(next, pattern: #"^SUBTOTAL\s*:?$"#) != nil {
                    if r.subtotalCents == nil {
                        r.subtotalCents = cents
                        r.selectionTrace.append("subtotal := dòng \(index) (tiền trước nhãn SUBTOTAL)")
                    }
                    claimedRoles[index] = "subtotal"
                    claimed = true
                } else if (nextUpper.hasPrefix("TAX") || nextUpper.hasPrefix("SALES TAX")),
                          lastMoneyInLine(next) == nil {
                    r.taxes.append(ParsedTaxLine(label: "TAX", rateText: nil, amountCents: cents, lineIndex: index))
                    taxLineIndices.append(index)
                    claimedRoles[index] = "tax"
                    r.selectionTrace.append("tax[\(r.taxes.count - 1)] := dòng \(index) (tiền trước nhãn thuế)")
                    claimed = true
                } else if !ignoreTotals,
                          matchGroups(next, pattern: #"^(TOTAL|TOTAL DUE|AMOUNT DUE|BALANCE DUE)\s*:?$"#) != nil {
                    if r.totalCents == nil {
                        r.totalCents = cents
                        r.totalConfidence = line.confidence
                        r.selectionTrace.append("total := dòng \(index) (tiền trước nhãn TOTAL)")
                    }
                    claimedRoles[index] = "total"
                    claimed = true
                }
                if claimed {
                    claimedIndices.insert(index)
                    claimedIndices.insert(index + 1)
                    claimedRoles[index + 1] = "label"
                    totalsSeen = true
                    skipNext = true
                    continue
                }
            }
            // F2b: dòng chỉ-có-nhãn -> ghi nhớ cho đúng dòng ngay sau.
            if matchGroups(text, pattern: #"^SUBTOTAL\s*:?$"#) != nil {
                pendingKind = "SUBTOTAL"
                totalsSeen = true
                continue
            }
            if !ignoreTotals,
               matchGroups(text, pattern: #"^(TOTAL|TOTAL DUE|AMOUNT DUE|BALANCE DUE)\s*:?$"#) != nil {
                pendingKind = "TOTAL"
                totalsSeen = true
                continue
            }
            if (upper.hasPrefix("TAX") || upper.hasPrefix("SALES TAX")),
               lastMoneyInLine(text) == nil {
                pendingKind = "TAX"
                totalsSeen = true
                continue
            }
            // Mọi dòng khác (kể cả dòng bật vùng loại trừ và RETURN
            // POLICY ở dưới): nhãn chờ hết hạn sau đúng 1 dòng.
            pendingKind = nil
            if upper.contains("SUGGESTED TIP") || upper.contains("TIP GUIDE") {
                ignoreTotals = true
            }
            if upper.contains("RETURN POLICY") || upper.contains("MAX REFUND VALUE") {
                continue
            }
            // P1-GLYPH: ô ký hiệu tiền chấp nhận ký hiệu bị OCR vỡ
            // ($ -> ฿/£/€); các chữ số vẫn là số đã in (fixture L-R05).
            if let m = matchGroups(text, pattern: #"^SUBTOTAL\s*:?\s*[$฿£€]?(\d[\d,]*\.\d{2})(-)?$"#),
               let cents = SafeMoney.parseCents(m[0] ?? "", negative: m[1] != nil) {
                if r.subtotalCents == nil {
                    r.subtotalCents = cents
                    r.selectionTrace.append("subtotal := dòng \(index) (nhãn SUBTOTAL cùng dòng)")
                }
                claimedIndices.insert(index)
                claimedRoles[index] = "subtotal"
                totalsSeen = true
                continue
            }
            let isTaxLine = upper.hasPrefix("TAX") || upper.hasPrefix("SALES TAX")
            if isTaxLine, let cents = lastMoneyInLine(text) {
                r.taxes.append(ParsedTaxLine(label: "TAX", rateText: nil, amountCents: cents, lineIndex: index))
                taxLineIndices.append(index)
                claimedIndices.insert(index)
                claimedRoles[index] = "tax"
                r.selectionTrace.append("tax[\(r.taxes.count - 1)] := dòng \(index) (dòng bắt đầu TAX)")
                totalsSeen = true
                continue
            }
            // INTEGRATE-V2: dòng TỔNG THUẾ tóm tắt ("TOTAL TAX 9.38")
            // — không cộng chồng lên các dòng thuế thành phần: chỉ
            // giữ làm ứng viên dự phòng, dùng sau vòng lặp khi không
            // có dòng thuế thành phần nào.
            if upper.contains("TOTAL TAX"), let cents = lastMoneyInLine(text) {
                if totalTaxSummary == nil {
                    totalTaxSummary = (index, cents)
                }
                claimedIndices.insert(index)
                claimedRoles[index] = "taxSummaryCandidate"
                totalsSeen = true
                continue
            }
            // INTEGRATE-V2: dòng thuế mang SUẤT mà nhãn không bắt đầu
            // bằng TAX — "Coweta sales tax 10.05% $16.53" (chữ TAX ở
            // giữa nhãn), "F 4.0107% TAXÙ 1.16" (chữ TAX ở từ đệm sau
            // suất), "Oklahoma Grocery 5.55% $1.33" (không có chữ
            // TAX: chỉ nhận khi vùng tổng đã bắt đầu — totalsSeen —
            // để không vớ phải dòng món mang suất lạ).
            if let rt = matchTaxRateLine(text) {
                if rt.taxLabeled || totalsSeen {
                    r.taxes.append(ParsedTaxLine(label: rt.label, rateText: rt.rate, amountCents: rt.cents, lineIndex: index))
                    taxLineIndices.append(index)
                    claimedIndices.insert(index)
                    claimedRoles[index] = "tax"
                    r.selectionTrace.append("tax[\(r.taxes.count - 1)] := dòng \(index) (dòng thuế mang suất, nhãn tự do)")
                    totalsSeen = true
                    continue
                }
            }
            if !ignoreTotals, r.totalCents == nil,
               let m = matchGroups(text, pattern: #"^(TOTAL|TOTAL DUE|AMOUNT DUE|BALANCE DUE)\s*:?\s*[$฿£€]?(\d[\d,]*\.\d{2})(-)?$"#),
               m.count == 3,
               let cents = SafeMoney.parseCents(m[1] ?? "", negative: m[2] != nil) {
                r.totalCents = cents
                r.totalConfidence = line.confidence
                claimedIndices.insert(index)
                claimedRoles[index] = "total"
                r.selectionTrace.append("total := dòng \(index) (nhãn TOTAL cùng dòng)")
                totalsSeen = true
                continue
            }
            if r.dedupeKey == nil, let tc = matchPrefix(text, pattern: #"^TC#\s+([\d ]+)$"#) {
                let digits = tc.replacingOccurrences(of: " ", with: "")
                if digits.count >= 16 && digits.count <= 24 {
                    r.dedupeKey = "TC-" + digits
                }
                continue
            }
        }

        // INTEGRATE-V2: dòng TỔNG THUẾ tóm tắt chỉ được dùng khi
        // không có bất kỳ dòng thuế thành phần nào đọc được — trong
        // trường hợp đó nó LÀ dòng thuế duy nhất của bill, không
        // cộng chồng lên các thành phần.
        if r.taxes.isEmpty, let summary = totalTaxSummary {
            r.taxes.append(ParsedTaxLine(label: "TAX", rateText: nil, amountCents: summary.cents, lineIndex: summary.index))
            taxLineIndices.append(summary.index)
            claimedRoles[summary.index] = "tax"
            r.selectionTrace.append("tax[\(r.taxes.count - 1)] := dòng \(summary.index) (dòng TỔNG THUẾ tóm tắt — không có thuế thành phần)")
        }

        // INTEGRATE-V2: trích món generic v2 — khối UPC + nhánh
        // cùng-dòng, xem parseGenericItemsV2 ở dưới (thay
        // parseGenericItems của M1-FIX).
        let extracted = parseGenericItemsV2(lines: lines)
        r.items = extracted.items

        // PHA 1 (P1-GEOMETRY): trọng tài khung hình học khi có hộp
        // — chỉ thay món khi hình học khép E1 còn đường chữ không;
        // cả hai cùng khép -> giữ đường chữ; không bên nào khép ->
        // giữ đường chữ + ứng viên hình học vào geometricCandidates.
        if let boxes = boxes {
            let geo = geometricItems(lines: lines, boxes: boxes, stop: totalsBoundary(lines: lines))
            if !geo.isEmpty {
                let legacySum = SafeMoney.sumCents(r.items.map { $0.amountCents ?? 0 })
                let geoSum = SafeMoney.sumCents(geo.map { $0.amountCents ?? 0 })
                if let subtotal = r.subtotalCents, let ls = legacySum, let gs = geoSum {
                    let legacyOK = abs(ls - subtotal) <= 2
                    let geoOK = abs(gs - subtotal) <= 2
                    if geoOK && !legacyOK {
                        r.items = geo
                        r.selectionTrace.append("items := KHUNG HÌNH HỌC (E1 khép; đường chữ lệch \(ls) vs subtotal \(subtotal))")
                    } else if !geoOK {
                        r.geometricCandidates = geo
                    }
                } else {
                    r.geometricCandidates = geo
                }
            }
        }

        if r.itemsSold == nil {
            r.itemsSold = findItemsSoldGeneric(lines: lines)
        }

        // INTEGRATE-V2: neo tổng bằng số học khi nhãn vỡ/mất (chỉ
        // điền trường còn trống, chỉ bằng số đã in, chỉ khi khép
        // duy nhất) — xem anchorTotals.
        anchorTotals(result: &r, lines: lines, claimedIndices: claimedIndices,
                     claimedRoles: &claimedRoles,
                     taxLineIndices: &taxLineIndices, lastItemIndex: extracted.lastItemIndex)

        // P1-CANDIDATES: toàn bộ token tiền trong vùng tổng kèm vai
        // trò — ứng viên cho F5 (Pha 3) và cho chẩn đoán.
        let zoneStart = (extracted.lastItemIndex ?? -1) + 1
        if zoneStart < lines.count {
            for i in zoneStart..<lines.count {
                for c in moneyTokensWithBoundary(in: lines[i].text) {
                    let role = claimedRoles[i] ?? "unassigned"
                    r.totalCandidates.append(TotalCandidate(
                        lineIndex: i, cents: c, role: role,
                        chosen: role != "unassigned"))
                }
            }
        }

        let card = findCard(lines: lines)
        r.cardLast4 = card.last4
        r.cardBrand = card.brand
        r.cardConfidence = card.confidence
        r.cardLineContaminated = card.contaminated

        // Khoá chống trùng yếu cho tiệm generic: tiệm + ngày + tổng.
        if r.dedupeKey == nil, let total = r.totalCents, let date = r.date, let vendor = r.vendor {
            let day = DateFormatter()
            day.calendar = Calendar(identifier: .gregorian)
            day.locale = Locale(identifier: "en_US_POSIX")
            day.dateFormat = "yyyy-MM-dd"
            r.dedupeKey = "GEN|\(vendor)|\(day.string(from: date))|\(total)"
        }
        return r
    }

    // MARK: - INTEGRATE-V2: món cho tiệm generic v2 (khối UPC + cùng-dòng)
    //
    // Thay parseGenericItems của M1-FIX. Thiết kế đã chứng minh ở
    // bench-prep/port_v2.py (gói PARSER-GAP, chấm lại buổi đo
    // 2026-11-11 trên dòng-cuối A0: ca thật trọn sổ 0/15 -> 3/15,
    // Σ món khép 8/11 ca L-R) — bản Swift dưới đây chép TRUNG THỰC
    // thuật toán đó, gồm: đường khối UPC cũ + 2 vá có điều kiện
    // (tiền ở cuối dòng mã / cuối dòng mô tả gán cho chính món đó
    // khi món chưa có tiền; dòng '<mã coupon> / <mã món>' KHÔNG mở
    // khối) + NHÁNH CÙNG-DÒNG cho các dòng khối chưa dùng. Món trả
    // về sắp theo vị trí dòng xuất hiện. Mọi món vẫn qua cổng sổ
    // validate() như cũ — trích ra mà tổng không khép thì giữ kết
    // quả + cờ, không sửa số. Dòng tiền bị OCR phá được trích với
    // amount = nil: TUYỆT ĐỐI không nặn số từ mảnh vỡ.

    /// Một món kèm chỉ số dòng nguồn (để sắp lại theo thứ tự in và
    /// để tầng neo tổng biết vùng món kết thúc ở đâu).
    private struct IndexedItem {
        var index: Int
        var item: ParsedLineItem
    }

    private static func parseGenericItemsV2(lines: [OCRLine]) -> (items: [ParsedLineItem], lastItemIndex: Int?) {
        var tagged: [IndexedItem] = []
        var consumed = Set<Int>()
        var open: ParsedLineItem? = nil
        var openIndex: Int? = nil
        var openHasDescription = false
        var prevLineWasBlock = false
        var lastBareMoney: (index: Int, cents: Int)? = nil
        var bareMoneyConsumed = Set<Int>()
        var stop = lines.count

        func closeOpen() {
            if let o = open, let oi = openIndex {
                tagged.append(IndexedItem(index: oi, item: o))
            }
            open = nil
            openIndex = nil
            openHasDescription = false
            prevLineWasBlock = false
        }

        // Đường khối UPC (sao trung thực vòng lặp gốc + 2 vá).
        for (index, line) in lines.enumerated() {
            let text = line.text
            let upper = text.uppercased()
            if upper.hasPrefix("SUBTOTAL") || upper.hasPrefix("TOTAL")
                || upper.hasPrefix("SALES TAX") || upper.hasPrefix("TAX")
                || upper.contains("RETURN POLICY") || upper.contains("MAX REFUND VALUE")
                || upper.contains("SUGGESTED TIP") || upper.contains("TIP GUIDE") {
                stop = index
                break
            }
            // Dòng số lượng kiểu Home Depot: "2@34.98".
            if let m = matchGroups(text, pattern: #"^(\d+)\s*@\s*(\d[\d,]*\.\d{2})$"#), m.count == 2,
               var o = open, let q = SafeMoney.parseQty(m[0] ?? ""),
               let u = SafeMoney.parseCents(m[1] ?? "") {
                o.qty = q
                o.unitPriceCents = u
                open = o
                consumed.insert(index)
                prevLineWasBlock = true
                continue
            }
            // Dòng chỉ-có-tiền: giá kề SAU khối cho món đang mở.
            if let cents = bareMoneyCents(text) {
                lastBareMoney = (index, cents)
                if var o = open, o.amountCents == nil, prevLineWasBlock {
                    o.amountCents = cents
                    if o.unitPriceCents == nil { o.unitPriceCents = cents }
                    open = o
                    bareMoneyConsumed.insert(index)
                    consumed.insert(index)
                }
                prevLineWasBlock = false
                continue
            }
            // Dòng mã món: >= 9 số liền + phần tên. Dòng '<mã> / <mã>'
            // (INST SV của Costco) KHÔNG mở khối — nếu mở, khối sẽ
            // nuốt dòng món thật ngay sau làm "mô tả" và gán tiền trần
            // của vùng tổng làm giá món (đo được trên final L-R01:
            // món rác amount = subtotal 12548). Để nhánh cùng-dòng xử.
            if let m = matchGroups(text, pattern: #"^(\d{9,})\s+(.+)$"#), m.count == 2,
               !((m[1] ?? "").trimmingCharacters(in: .whitespaces).hasPrefix("/")) {
                closeOpen()
                var item = ParsedLineItem(name: "")
                item.itemCode = m[0]
                item.lineIndex = index
                var rest = m[1] ?? ""
                if let fm = matchGroups(rest, pattern: #"^(.*?)\s*<([A-Z])>$"#),
                   let cleaned = fm[0] {
                    rest = cleaned
                    item.taxFlag = fm[1]
                }
                item.name = rest
                if let lb = lastBareMoney, lb.index == index - 1,
                   !bareMoneyConsumed.contains(lb.index) {
                    item.amountCents = lb.cents
                    item.unitPriceCents = lb.cents
                    consumed.insert(lb.index)
                }
                // VÁ (i): tiền ở cuối chính dòng mã thuộc về món này
                // (bản final trên máy thật gộp tiền vào dòng mã, khác
                // luồng thô đóng băng — luồng thô không có tiền cuối
                // dòng mã nên vá không đổi hành vi trên corpus đó).
                if item.amountCents == nil, let tail = trailingAmount(in: rest), !tail.name.isEmpty {
                    item.amountCents = tail.cents
                    if item.unitPriceCents == nil { item.unitPriceCents = tail.cents }
                }
                open = item
                openIndex = index
                openHasDescription = false
                prevLineWasBlock = true
                consumed.insert(index)
                continue
            }
            // Dòng mô tả ngay sau dòng mã — tên đầy đủ của món.
            if var o = open, !openHasDescription, prevLineWasBlock,
               text.contains(where: { $0.isLetter }),
               matchGroups(text, pattern: #"(\d{1,2})/(\d{1,2})/(\d{2,4})"#) == nil {
                // VÁ (ii): tiền ở cuối dòng mô tả thuộc về món đang mở.
                if let tail = trailingAmount(in: text), o.amountCents == nil {
                    o.amountCents = tail.cents
                    if o.unitPriceCents == nil { o.unitPriceCents = tail.cents }
                    o.name = tail.name
                } else {
                    o.name = text
                }
                open = o
                openHasDescription = true
                prevLineWasBlock = true
                consumed.insert(index)
                continue
            }
            prevLineWasBlock = false
        }
        closeOpen()

        tagged += extractSamelineItems(lines: lines, consumed: consumed, stop: stop)
        tagged.sort { $0.index < $1.index }
        return (tagged.map { $0.item }, tagged.map { $0.index }.max())
    }

    // MARK: - INTEGRATE-V2: nhánh món CÙNG-DÒNG

    /// Tiền tố / cụm nhãn KHÔNG bao giờ là món cùng-dòng (thanh toán,
    /// quản trị quầy, chân bill) — lớp phòng thủ thứ hai sau điểm
    /// dừng vùng tổng trong vòng trích xuất.
    private static let samelineExcludePrefixes: [String] = [
        "ST#", "OP#", "TE#", "TR#", "TC#", "REF #", "REF#", "AID",
        "TERMINAL", "AUTH", "NETWORK", "APPR", "SEQ#", "STATION", "ORDER",
        "TRANSACTION", "CASHIER", "MEMBER", "DC MEMBER", "SALE", "DEBIT",
        "CREDIT", "EFT", "VISA", "MASTERCARD", "MASTER CARD", "AMEX",
        "DISCOVER", "FSA", "PAYMENT", "AMOUNT", "CHANGE", "CASH", "ENTRY",
        "CONTACTLESS", "RETAIN", "THANK", "GET FREE", "SCAN TO",
        "LOW PRICES", "POLICY", "CONTACT", "ITEM COUNT", "ITEMS SOLD",
        "# ITEMS",
    ]
    private static let samelineExcludeContains: [String] = [
        "CASH BACK", "CASH ", "PURCHASE", "TOTAL", "HTTP", ".COM",
        "SURVEY", "FEEDBACK", "RETURN POLICY", "STORE RETUR",
    ]

    private static func samelineExcluded(upper: String) -> Bool {
        if upper.contains("%") { return true }
        if samelineExcludePrefixes.contains(where: { upper.hasPrefix($0) }) { return true }
        if samelineExcludeContains.contains(where: { upper.contains($0) }) { return true }
        return false
    }

    private static func hasAlphaToken(_ name: String) -> Bool {
        matchGroups(name, pattern: #"[A-Za-z]{2,}"#) != nil
    }

    /// Tiền sạch ở CUỐI dòng (nhánh cùng-dòng): (tên, cents, đuôi).
    /// Đuôi = cờ/rác tối đa 3 ký tự không-phải-số sau tiền (R, FT,
    /// ł...); dấu trừ dính ngay sau tiền (kiểu '4.50-A' của dòng
    /// giảm giá Costco) cho số âm.
    private static func lastCleanMoney(_ text: String) -> (name: String, cents: Int, tail: String)? {
        guard let m = matchGroups(text, pattern: #"^(.*?)\s*\$?\s*(\d[\d,]*\.\d{2})(-)?\s*([^\d\s]{0,3})$"#),
              m.count == 4,
              let cents = SafeMoney.parseCents(m[1] ?? "", negative: m[2] != nil) else { return nil }
        return ((m[0] ?? "").trimmingCharacters(in: .whitespaces), cents,
                (m[3] ?? "").trimmingCharacters(in: .whitespaces))
    }

    /// Tiền thập-phân-PHẨY sau $ ở cuối dòng (rác OCR '$2,79' thay
    /// '$2.79'): chỉ nhận khi có $ ngay trước và token không chứa
    /// dấu chấm — không lẫn với phân cách nghìn (luôn đi cùng chấm).
    private static func lastCommaMoney(_ text: String) -> (name: String, cents: Int, tail: String)? {
        guard let m = matchGroups(text, pattern: #"^(.*?)\s*\$\s*(\d+,\d{2})\s*([^\d\s]{0,3})$"#),
              m.count == 3, let money = m[1] else { return nil }
        let parts = money.split(separator: ",")
        guard parts.count == 2 else { return nil }
        // P1-SAFEMONEY: dạng phẩy qua SafeMoney.parseCommaCents
        // (miền 12 chữ số như mọi token tiền; trước đây nhân trần).
        let whole = String(parts[0])
        let frac = String(parts[1])
        guard let cents = SafeMoney.parseCommaCents(whole: whole, frac: frac) else { return nil }
        return ((m[0] ?? "").trimmingCharacters(in: .whitespaces), cents,
                (m[2] ?? "").trimmingCharacters(in: .whitespaces))
    }

    /// Dòng có tiền nhưng OCR phá mất dạng tiền ('$131 57', token
    /// '3.€8', ':,68'): trả PHẦN TÊN để trích món amount = nil — số
    /// tiền KHÔNG được nặn lại từ mảnh vỡ. nil nếu không khớp.
    private static func brokenMoneyName(_ text: String) -> String? {
        if let m = matchGroups(text, pattern: #"^(.*?)\s*\$\s*([\d\s]+)$"#), m.count == 2,
           let name = m[0], let junk = m[1] {
            if junk.filter({ $0.isNumber }).count >= 4, hasAlphaToken(name) {
                return name.trimmingCharacters(in: .whitespaces)
            }
        }
        if let m = matchGroups(text, pattern: #"^(.*?)\s+([0-9.,:€$£¥฿]{3,})\s*([^\d\s]{0,3})$"#),
           m.count == 3, let name = m[0], let tok = m[1] {
            if tok.filter({ $0.isNumber }).count >= 2,
               tok.contains(".") || tok.contains(",") || tok.contains(":"),
               hasAlphaToken(name) {
                return name.trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    /// Dòng cân 'W lb @ $U/lb' (chịu rác OCR: '1b'/'Tb', đơn giá mất
    /// $): (weightLb, unitCents?) hoặc nil. Trọng lượng KHÔNG phải
    /// qty đếm món — chỉ là metadata gắn kèm (xem extract).
    private static func weightLine(_ text: String) -> (lb: Double, unit: Int?)? {
        guard text.contains("/lb") || text.contains("/1b") else { return nil }
        guard let m = matchGroups(text, pattern: #"(\d+(?:\.\d+)?)\s*(?:lb|1b|Tb)\b"#),
              let w = Double(m[0] ?? "") else { return nil }
        // TRAP-FIX T1 (FULL-REVIEW): token cân không chặn độ dài
        // -> Double có thể là inf (token >= 309 chữ số) hoặc vô
        // lý; cân hoá đơn thật không quá 1e6 lb. Ngoài miền ->
        // không phải dòng cân.
        guard w.isFinite, w >= 0, w <= 1_000_000 else { return nil }
        var unit: Int? = nil
        if let mu = matchGroups(text, pattern: #"\$\s*\*?\s*(\d[\d,]*\.\d{2})"#) {
            unit = SafeMoney.parseCents(mu[0] ?? "", negative: false)
        } else if let mu = matchGroups(text, pattern: #"(\d[\d,]*\.\d{2})\s*/l"#) {
            unit = SafeMoney.parseCents(mu[0] ?? "", negative: false)
        }
        return (w, unit)
    }

    /// Như matchQtyLine của đường Sam's nhưng cờ cuối dòng nhận 1–2
    /// chữ cái bất kỳ (Walmart in cờ R/T thay Y/T của Sam's).
    private static func matchQtyLineGeneric(_ text: String) -> (qty: Int, unitCents: Int, amountCents: Int, flag: String?)? {
        guard let m = matchGroups(text, pattern: #"^(\d+)\s+AT\s+1\s+FOR\s+(\d[\d,]*\.\d{2})(-)?\s+(\d[\d,]*\.\d{2})(-)?\s*([A-Z]{1,2})?$"#),
              m.count == 6, let qty = SafeMoney.parseQty(m[0] ?? ""),
              let unit = SafeMoney.parseCents(m[1] ?? "", negative: m[2] != nil),
              let amount = SafeMoney.parseCents(m[3] ?? "", negative: m[4] != nil) else { return nil }
        return (qty, unit, amount, m[5])
    }

#endif

    /// Nhãn số món đọc TRỰC TIẾP từ bill ở đường generic (bản gốc chỉ
    /// đọc các nhãn này ở đường Sam's nên hoá đơn generic luôn mất
    /// itemsSold — cổng E3 không kiểm được). nil khi không nhãn nào
    /// đọc được; mẫu "Item Count:" đứng riêng thì nhận số nguyên
    /// trần ở dòng ngay sau (số lượng là số nguyên, subtotal luôn
    /// có phần thập phân nên không lẫn).
    private static func findItemsSoldGeneric(lines: [OCRLine]) -> Int? {
        for (index, line) in lines.enumerated() {
            let text = line.text
            if let m = matchGroups(text, pattern: #"TOTAL NUMBER OF ITEMS SOLD\s*=\s*(\d+)"#) { return SafeMoney.parseQty(m[0] ?? "") }
            if let m = matchGroups(text, pattern: #"#\s*ITEMS SOLD\s+(\d+)"#) { return SafeMoney.parseQty(m[0] ?? "") }
            if let m = matchGroups(text, pattern: #"^ITEMS SOLD:?\s+(\d+)$"#) { return SafeMoney.parseQty(m[0] ?? "") }
            if let m = matchGroups(text, pattern: #"^ITEM COUNT:?\s+(\d+)$"#) { return SafeMoney.parseQty(m[0] ?? "") }
            if matchGroups(text, pattern: #"^ITEM COUNT:?$"#) != nil,
               index + 1 < lines.count,
               matchGroups(lines[index + 1].text, pattern: #"^\d{1,3}$"#) != nil {
                return SafeMoney.parseQty(lines[index + 1].text)
            }
        }
        return nil
    }

#if !GLKEEPER_V4_ONLY
    /// Kiểm nhãn số món trên ĐÚNG một dòng (cho vòng cùng-dòng bỏ qua
    /// dòng nhãn — tương đương findItemsSoldGeneric trên danh sách
    /// 1 dòng, nơi luật dòng-kế không áp dụng được).
    private static func findItemsSoldInLine(_ text: String) -> Int? {
        if let m = matchGroups(text, pattern: #"TOTAL NUMBER OF ITEMS SOLD\s*=\s*(\d+)"#) { return SafeMoney.parseQty(m[0] ?? "") }
        if let m = matchGroups(text, pattern: #"#\s*ITEMS SOLD\s+(\d+)"#) { return SafeMoney.parseQty(m[0] ?? "") }
        if let m = matchGroups(text, pattern: #"^ITEMS SOLD:?\s+(\d+)$"#) { return SafeMoney.parseQty(m[0] ?? "") }
        if let m = matchGroups(text, pattern: #"^ITEM COUNT:?\s+(\d+)$"#) { return SafeMoney.parseQty(m[0] ?? "") }
        return nil
    }

    /// Nhánh cùng-dòng: quét các dòng trong vùng món mà đường khối
    /// chưa dùng, trích món dạng 'tên ... [mã] ... [$]tiền [cờ]'.
    /// Thứ tự mẫu mỗi dòng: ranh giới vùng -> tiền trần (= đầu vùng
    /// tổng ở họ cùng-dòng) -> dòng cân -> dòng qty đi kèm món treo
    /// -> loại trừ nhãn -> tiền sạch cuối dòng -> tiền phẩy -> tiền
    /// vỡ (amount = nil) -> món treo (tên + mã dài, amount = nil).
    private static func extractSamelineItems(lines: [OCRLine], consumed: Set<Int>, stop: Int) -> [IndexedItem] {
        var out: [IndexedItem] = []
        var pendingHangPos: Int? = nil   // vị trí trong out của món treo chờ dòng qty
        var pendingWeight: (lb: Double, unit: Int?)? = nil
        var lastItemPos: Int? = nil

        func attachWeight(_ pos: Int, _ w: (lb: Double, unit: Int?)) {
            out[pos].item.weightLb = w.lb
            if let u = w.unit { out[pos].item.weightUnitCents = u }
        }

        let upperBound = min(stop, lines.count)
        for index in 0..<upperBound {
            if consumed.contains(index) { continue }
            let text = lines[index].text
            let upper = text.uppercased()
            // Nhãn SỐ MÓN không phải ranh giới vùng: Walmart in
            // '# ITEMS SOLD' ở ĐẦU bill (trước khối món), Pan-Asia
            // in 'Item Count:' ở cuối — cả hai chỉ là dòng bỏ qua.
            if findItemsSoldInLine(text) != nil || upper.hasPrefix("ITEM COUNT") { continue }
            // Dòng ngày (số hoặc tháng chữ) không bao giờ là món —
            // mẫu tiền-vỡ từng nuốt '20-May-2026 1:11:30P' thành món.
            if matchGroups(text, pattern: #"(\d{1,2})/(\d{1,2})/(\d{2,4})"#) != nil
                || matchGroups(upper, pattern: #"\d{1,2}-(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)"#) != nil { continue }
            if upper.hasPrefix("SUBTOTAL") || upper.hasPrefix("TOTAL")
                || upper.hasPrefix("SALES TAX") || upper.hasPrefix("TAX") { break }
            if bareMoneyCents(text) != nil {
                // Tiền trần chưa được khối dùng = đầu vùng tổng ở họ
                // cùng-dòng (Costco in '125.48' / '9.38' trần liên tiếp).
                break
            }
            if let w = weightLine(text) {
                // TRAP-FIX T1 (FULL-REVIEW): chuyển Double->Int
                // PHẢI kiểm miền trước — tích cân x đơn giá ngoài
                // [0, 2^63) là trap cứng của Swift. Ngoài miền ->
                // không kiểm chứng được, coi như không có kỳ vọng.
                let expected = w.unit.flatMap { u -> Int? in
                    let p = (w.lb * Double(u)).rounded()
                    guard p.isFinite, p >= 0, p < 9_223_372_036_854_775_808.0
                    else { return nil }
                    return Int(p)
                }
                if let exp = expected, let lp = lastItemPos,
                   let amt = out[lp].item.amountCents, abs(exp - amt) <= 2,
                   out[lp].item.weightLb == nil {
                    // Kiểm chứng số học: W x U khớp tiền món NGAY
                    // TRƯỚC (họ in cân SAU nhãn — T-Johnnys) -> gắn về trước.
                    attachWeight(lp, w)
                } else {
                    // Mặc định: họ in cân TRƯỚC nhãn (Pan-Asia) ->
                    // chờ món tiếp theo. Liên kết cân là metadata,
                    // KHÔNG tham gia cổng sổ.
                    pendingWeight = w
                }
                continue
            }
            if let q = matchQtyLineGeneric(text) {
                if let hp = pendingHangPos {
                    out[hp].item.qty = q.qty
                    out[hp].item.unitPriceCents = q.unitCents
                    out[hp].item.amountCents = q.amountCents
                    if let f = q.flag { out[hp].item.taxFlag = f }
                    pendingHangPos = nil
                }
                continue
            }
            if samelineExcluded(upper: upper) { continue }
            // Cờ trái 1 chữ cái (Costco in cờ thực phẩm ở cột trái).
            var leftFlag: String? = nil
            var body = text
            if let fm = matchGroups(text, pattern: #"^([A-Z])\s+(?=\d{6,}\s)"#), let f = fm[0] {
                leftFlag = f
                body = String(text.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }

            var item: ParsedLineItem? = nil
            var isHang = false
            if let got = lastCleanMoney(body) {
                let name = got.name
                // Tên còn chứa một số thập phân khác -> dòng thuế/tỷ
                // lệ lọt lưới, không phải món.
                if !name.isEmpty,
                   hasAlphaToken(name) || matchGroups(name, pattern: #"\d{7,}"#) != nil,
                   matchGroups(name, pattern: #"\d+\.\d{2}"#) == nil {
                    var it = ParsedLineItem(name: name)
                    it.amountCents = got.cents
                    it.unitPriceCents = got.cents
                    if !got.tail.isEmpty, matchGroups(got.tail, pattern: #"^[A-Z]{1,2}$"#) != nil {
                        it.taxFlag = got.tail
                    }
                    item = it
                }
            }
            if item == nil, let got = lastCommaMoney(body) {
                let name = got.name
                if !name.isEmpty, hasAlphaToken(name),
                   matchGroups(name, pattern: #"\d+\.\d{2}"#) == nil {
                    var it = ParsedLineItem(name: name)
                    it.amountCents = got.cents
                    it.unitPriceCents = got.cents
                    if !got.tail.isEmpty, matchGroups(got.tail, pattern: #"^[A-Z]{1,2}$"#) != nil {
                        it.taxFlag = got.tail
                    }
                    item = it
                }
            }
            if item == nil, let broken = brokenMoneyName(body), !broken.isEmpty {
                item = ParsedLineItem(name: broken)   // amount = nil: không nặn số
            }
            if item == nil,
               matchGroups(body, pattern: #"(?<!\d)\d{9,}(?!\d)"#) != nil,
               matchGroups(body, pattern: #"[A-Za-z]{3,}"#) != nil {
                // Món treo: tên + mã dài nhưng tiền không nằm trên
                // dòng (Walmart in tiền ở dòng qty ngay sau, hoặc
                // tiền bị rơi).
                item = ParsedLineItem(name: body)
                isHang = true
            }
            guard var it = item else { continue }
            it.lineIndex = index

            // Chuẩn hoá tên: dòng giảm giá Costco '<mã coupon> /
            // <mã món> ...' -> tên INST SV + mã đối ứng (số âm đã
            // nằm trong amount); số thứ tự quầy Clover (không phải
            // qty) chỉ tách khi dòng không chứa mã dài nào; mã dài
            // trong tên -> itemCode.
            var name = it.name
            if let im = matchGroups(name, pattern: #"^(\d{7,})\s*/\s*(\d{7,})"#), im.count == 2,
               (it.amountCents ?? 0) < 0 {
                it.name = "INST SV " + (im[1] ?? "")
                name = it.name
            } else if !name.uppercased().contains("INST SV") {
                if let sm = matchGroups(name, pattern: #"^(\d{1,2})\s+([A-Za-z].*)$"#), sm.count == 2,
                   matchGroups(body, pattern: #"(?<!\d)\d{7,}(?!\d)"#) == nil,
                   let cleaned = sm[1] {
                    it.name = cleaned
                    name = cleaned
                }
                // CRASH-FIX (run #16/#18 harness, 2026-11-12):
                // pattern PHẢI có nhóm bắt quanh dãy số. matchGroups
                // chỉ trả các NHÓM BẮT (không gồm toàn khớp): pattern
                // không nhóm khớp thành công sẽ trả mảng RỖNG (không
                // phải nil) — bản cũ subscript cm[0] trên mảng rỗng
                // = SIGTRAP, chính là crash trên mọi dòng món có mã
                // >= 7 chữ số kèm tiền sạch (vd dòng Costco L-R01).
                if let cm = matchGroups(name, pattern: #"(?<!\d)(\d{7,})(?!\d)"#), cm.count == 1,
                   let code = cm[0] {
                    it.itemCode = code
                }
            }
            if it.taxFlag == nil, let lf = leftFlag { it.taxFlag = lf }
            out.append(IndexedItem(index: index, item: it))
            let pos = out.count - 1
            if isHang { pendingHangPos = pos }
            if let pw = pendingWeight {
                attachWeight(pos, pw)
                pendingWeight = nil
            }
            lastItemPos = pos
        }

        if let pw = pendingWeight, let lp = lastItemPos, out[lp].item.weightLb == nil {
            out[lp].item.weightLb = pw.lb
            if let u = pw.unit { out[lp].item.weightUnitCents = u }
        }
        return out
    }

    // MARK: - INTEGRATE-V2: dòng thuế mang suất + neo tổng bằng số học

    /// Dòng thuế mang SUẤT mà nhãn không bắt đầu bằng TAX:
    /// "<nhãn> <suất>% [một từ đệm] <tiền>" — "Coweta sales tax
    /// 10.05% $16.53", "F 4.0107% TAXÙ 1.16" (từ đệm chứa TAX),
    /// "Oklahoma Grocery 5.55% $1.33", "A 8.517% 8.22". Trả nhãn +
    /// suất + tiền + cờ "có chữ TAX" (ở nhãn hoặc ở từ đệm).
    private static func matchTaxRateLine(_ text: String) -> (label: String, rate: String, cents: Int, taxLabeled: Bool)? {
        guard let m = matchGroups(text, pattern: #"^(.+?)\s+([\d.]+)\s*%\s+(?:(\S+)\s+)?\$?(\d[\d,]*\.\d{2})(-)?$"#),
              m.count == 5, let label = m[0], let rate = m[1], let amountText = m[3],
              let cents = SafeMoney.parseCents(amountText, negative: m[4] != nil) else { return nil }
        let taxLabeled = label.uppercased().contains("TAX")
            || (m[2]?.uppercased().contains("TAX") ?? false)
        return (label.trimmingCharacters(in: .whitespaces), rate,
                cents, taxLabeled)
    }

    /// NEO TỔNG BẰNG SỐ HỌC khi nhãn tổng/thuế vỡ hoặc mất — theo
    /// tinh thần lớp Reconcile (thiết kế RECONCILE): số neo không
    /// bao giờ bị BỊA; hàm này chỉ gán VAI TRÒ cho những số ĐÃ IN
    /// trên bill, và chỉ khi vai trò đó được phương trình chứng
    /// minh DUY NHẤT. Chỉ điền trường còn TRỐNG (không bao giờ ghi
    /// đè số đã đọc theo nhãn), chỉ xét vùng tổng (các dòng sau
    /// dòng món cuối), bỏ qua dòng đã được vòng tổng chính nhận.
    /// Ba bước, theo thứ tự phụ thuộc:
    ///  1. SUBTOTAL: đúng một số tiền trần trong vùng tổng khớp
    ///     Σ món ±2 xu (hoặc khớp total - Σ thuế khi không có món).
    ///  2. TOTAL: ứng viên là số trên dòng thanh toán (TEND /
    ///     AMOUNT: / EFT / CARD SALE / PAYMENT) hoặc trên dòng chứa
    ///     TOTAL mà nhãn đã vỡ; nhận khi subtotal + Σ thuế khớp ±2,
    ///     hoặc thuế hàm ý (total - subtotal) nằm trong dải hợp lý
    ///     0–15% như kiểm tra hợp lý §5.3 của Reconcile — và đúng
    ///     MỘT giá trị ứng viên qua được. (Bẫy "TOTAL DEBIT
    ///     PURCHASE 92.24" gồm rút tiền mặt của L-R09 bị loại bởi
    ///     chính phương trình này.)
    ///  3. THUẾ còn thiếu: phần chênh total - subtotal - Σ thuế đã
    ///     có phải bằng đúng một dòng tiền đã in chưa ai nhận trong
    ///     vùng tổng — dòng đó được ghi là dòng thuế với vai trò đã
    ///     được phương trình chứng minh (không phải thuế suy diễn:
    ///     số tiền là số in nguyên văn, chỉ vai trò là được suy).
    private static func anchorTotals(result r: inout ParseResult, lines: [OCRLine],
                                     claimedIndices: Set<Int>,
                                     claimedRoles: inout [Int: String],
                                     taxLineIndices: inout [Int],
                                     lastItemIndex: Int?) {
        let zoneStart = (lastItemIndex ?? -1) + 1
        guard zoneStart < lines.count else { return }
        var bareZone: [(index: Int, cents: Int)] = []
        var zoneAmounts: [(index: Int, cents: Int)] = []
        for i in zoneStart..<lines.count where !claimedIndices.contains(i) {
            let text = lines[i].text
            if let c = bareMoneyCents(text) {
                bareZone.append((i, c))
                zoneAmounts.append((i, c))
            } else if let c = lastMoneyInLine(text) {
                zoneAmounts.append((i, c))
            }
        }
        // 1) SUBTOTAL — số học qua SafeMoney (P1-SAFEMONEY).
        if r.subtotalCents == nil, !r.items.isEmpty {
            if let sum = SafeMoney.sumCents(r.items.map { $0.amountCents ?? 0 }) {
                let hits = Set(bareZone.filter { abs($0.cents - sum) <= 2 }.map { $0.cents })
                if hits.count == 1, let v = hits.first {
                    r.subtotalCents = v
                    if let src = bareZone.first(where: { $0.cents == v }) {
                        claimedRoles[src.index] = "subtotal"
                    }
                    r.selectionTrace.append("subtotal := anchorTotals(Σ món) — số đã in khớp tổng món duy nhất trong vùng tổng")
                }
            }
        }
        if r.subtotalCents == nil, r.items.isEmpty, let total = r.totalCents, !r.taxes.isEmpty {
            let taxSum = r.taxTotalCents
            let hits = bareZone.filter { cand in
                guard let v = SafeMoney.checkedAdd(cand.cents, taxSum) else { return false }
                return abs(v - total) <= 2
            }
            let values = Set(hits.map { $0.cents })
            if values.count == 1, let v = values.first {
                r.subtotalCents = v
                if let src = hits.first(where: { $0.cents == v }) {
                    claimedRoles[src.index] = "subtotal"
                }
                r.selectionTrace.append("subtotal := anchorTotals(total − thuế) — khớp duy nhất trong vùng tổng")
            }
        }
        // 2) TOTAL
        if r.totalCents == nil, let s = r.subtotalCents {
            var candidates: [(index: Int, cents: Int)] = []
            for i in zoneStart..<lines.count where !claimedIndices.contains(i) {
                let text = lines[i].text
                let upper = text.uppercased()
                let isTend = upper.contains("TEND") || upper.contains("AMOUNT:")
                    || upper.hasPrefix("EFT") || upper.contains("CARD SALE")
                    || upper.hasPrefix("PAYMENT")
                let isDamagedTotal = upper.contains("TOTAL") && !upper.contains("SUBTOTAL")
                    && !upper.contains("TAX")
                if (isTend || isDamagedTotal), let c = lastMoneyInLine(text) {
                    candidates.append((i, c))
                }
            }
            let taxSum = r.taxTotalCents
            let passing = Set(candidates.filter { cand in
                if !r.taxes.isEmpty,
                   let v = SafeMoney.checkedAdd(s, taxSum),
                   abs(v - cand.cents) <= 2 { return true }
                guard let implied = SafeMoney.checkedSubtract(cand.cents, s) else { return false }
                return SafeMoney.withinPercent(implied: implied, ofBase: s, percent: 15)
            }.map { $0.cents })
            if passing.count == 1, let v = passing.first,
               let src = candidates.first(where: { $0.cents == v }) {
                r.totalCents = v
                r.totalConfidence = lines[src.index].confidence
                claimedRoles[src.index] = "total"
                r.selectionTrace.append("total := anchorTotals(dòng thanh toán \(src.index)) — khớp subtotal + thuế duy nhất")
            }
        }
        // 3) THUẾ còn thiếu
        if let s = r.subtotalCents, let total = r.totalCents,
           let afterSub = SafeMoney.checkedSubtract(total, s),
           let missing = SafeMoney.checkedSubtract(afterSub, r.taxTotalCents) {
            if missing > 0 {
                let hits = zoneAmounts.filter { abs($0.cents - missing) <= 2 }
                let distinct = Set(hits.map { $0.cents })
                if distinct.count == 1, let hit = hits.first {
                    r.taxes.append(ParsedTaxLine(label: "TAX", rateText: nil, amountCents: hit.cents, lineIndex: hit.index))
                    taxLineIndices.append(hit.index)
                    claimedRoles[hit.index] = "tax"
                    r.selectionTrace.append("taxes += anchorTotals(dòng \(hit.index)) — phần thuế còn thiếu khớp đúng một số đã in")
                    // Thuế giữ thứ tự in trên bill: sắp lại theo
                    // chỉ số dòng nguồn.
                    let paired = zip(r.taxes, taxLineIndices).sorted { $0.1 < $1.1 }
                    r.taxes = paired.map { $0.0 }
                    taxLineIndices = paired.map { $0.1 }
                }
            }
        }
    }

    // MARK: - INTEGRATE-V2: ngày tháng chữ + giờ đứng riêng dòng

    private static let monthNames: [String: Int] = [
        "JAN": 1, "FEB": 2, "MAR": 3, "APR": 4, "MAY": 5, "JUN": 6,
        "JUL": 7, "AUG": 8, "SEP": 9, "OCT": 10, "NOV": 11, "DEC": 12,
    ]

    private static func monthNumber(_ s: String?) -> Int? {
        guard let s = s else { return nil }
        return monthNames[s.uppercased()]
    }

    private static func mergingTime(into date: Date, hour: Int, minute: Int) -> Date? {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        comps.hour = hour
        comps.minute = minute
        return Calendar.current.date(from: comps)
    }
#endif

    // MARK: - WP5: Nhận diện tiệm 3 nấc — NAY LÀ DỮ LIỆU (PHA 1)
    //
    // Bảng cứng knownVendors/vendorAnchors/signatureItems và các
    // hàm khớp (normalizeForVendorMatch/vendorLineMatch/
    // tokenFuzzyEqual/levenshtein/anchorHits) của bản nền đã CHUYỂN
    // sang VendorData.swift + vendors.json (M7, DESIGN-FINAL
    // §3.4): hành vi phân giải 3 nấc giữ nguyên, tri thức về tiệm
    // nằm ở dữ liệu. Hàm dưới đây chỉ là lớp uỷ thác mỏng giữ
    // nguyên hình dạng VendorIdentification cho phần còn lại của
    // parser.

    struct VendorIdentification {
        var vendor: String? = nil
        var vendorKey: String = "generic"
        var parserPath: String = "generic"   // PHA 1: từ dữ liệu ("sams" | "generic")
        var confidence: Double = 0
        var source: String? = nil   // "tier1-exact" | "tier1-fuzzy" | "tier2-anchor"
        var suggestion: String? = nil
        var anchorDisputed: Bool = false
        var entry: VendorEntry? = nil        // PHA 1: mục dữ liệu đã phân giải (printSemantics...)
    }

    private static func identifyVendor(lines: [OCRLine]) -> VendorIdentification {
        let id = VendorData.shared.identify(lines: lines)
        return VendorIdentification(
            vendor: id.vendor, vendorKey: id.key, parserPath: id.parserPath,
            confidence: id.confidence, source: id.source,
            suggestion: id.suggestion, anchorDisputed: id.anchorDisputed,
            entry: id.entry)
    }

    // MARK: - WP5: Trích địa chỉ / điện thoại / mã cửa hàng (hạ cánh WP2)
    //
    // Chỉ trích NGUYÊN VĂN dòng thấy được trên hoá đơn, không ghép/suy
    // địa chỉ từ nhiều dòng rời (WP5-SPEC mục 4). Mẫu regex chốt ở đây
    // kèm bản port kiểm chứng wp5-fixtures/extract_port.py.

    private static func extractVendorContact(lines: [OCRLine]) -> (address: String?, phone: String?, storeNumber: String?) {
        var address: String? = nil
        var phone: String? = nil
        var storeNumber: String? = nil
        for line in lines {
            let text = line.text
            // Địa chỉ: dòng bắt đầu bằng số nhà + tên đường + hậu tố
            // đường (ST/AVE/BLVD...). Lấy nguyên văn dòng đầu tiên khớp.
            if address == nil,
               matchGroups(text.uppercased(), pattern: #"^\d{1,6}\s+[A-Z0-9 .'\-]+\s+(ST|STREET|AVE|AVENUE|BLVD|RD|ROAD|DR|DRIVE|LN|LANE|HWY|HIGHWAY|CT|COURT|WAY|CIR|CIRCLE|PL|PLACE|TER|TERRACE|TRL|TRAIL)\b"#) != nil {
                address = text
            }
            // Điện thoại 10 số có định dạng (dấu - . khoảng trắng hoặc
            // ngoặc mã vùng), hai đầu không dính số khác — tránh vớ
            // phải dãy số hoá đơn/TC#.
            if phone == nil,
               let m = matchGroups(text, pattern: #"(?<!\d)(\(?\d{3}\)?[-. ]\d{3}[-. ]\d{4})(?!\d)"#),
               let found = m.first ?? nil {
                phone = found
            }
            // Mã cửa hàng: "STORE #1234" / "ST# 1234" / "CLUB #1234".
            if storeNumber == nil,
               let m = matchGroups(text, pattern: #"\b(?:STORE|ST|CLUB)\s*#\s*(\d{3,6})\b"#),
               let found = m.first ?? nil {
                storeNumber = found
            }
        }
        return (address, phone, storeNumber)
    }

#if !GLKEEPER_V4_ONLY
    // MARK: - Thẻ: CHỈ từ dòng có ký tự che (luật toàn cục số 2)

    // PHA 3: trả kèm (confidence của dòng nguồn, contaminated).
    // contaminated = dòng dạng tender còn chứa từ khoá TOTAL sau
    // vị trí đuôi thẻ — bằng chứng dòng bị gộp với dòng tổng (cơ
    // chế xé/gộp dòng của F3), tức đuôi thẻ nằm trên một dòng
    // không sạch. Dạng che (****/XXX) neo đuôi bằng ký tự che nên
    // không tính nhiễm. Cả hai chỉ để validate() gắn cờ.
    private static func findCard(lines: [OCRLine]) -> (last4: String?, brand: String?,
                                                      confidence: Double, contaminated: Bool) {
        var last4: String? = nil
        var cardConf: Double = 0
        var contaminated = false
        for line in lines {
            let text = line.text
            if let m = matchGroups(text, pattern: #"\*{4}\s+\*{4}\s+\*{4}\s+(\d{4})"#) {
                last4 = m[0]
                cardConf = line.confidence
                break
            }
            if let m = matchGroups(text, pattern: #"\*{3,}\s*(\d{4})"#) {
                last4 = m[0]
                cardConf = line.confidence
                break
            }
            if let m = matchGroups(text, pattern: #"X{3,}\s*(\d{4})"#) {
                last4 = m[0]
                cardConf = line.confidence
                break
            }
        }
        if last4 == nil {
            // P1-CARD-TENDER: dạng dòng thanh toán '<hãng> DEBIT/
            // CREDIT- NNNN' của Walmart — dòng chỉ in 4 số cuối,
            // vẫn là dòng che theo luật toàn cục 2 (không bao giờ
            // nhận số thẻ dài). Fixture: L-R04 'US DEBIT- 2586',
            // L-R11 'VISA CREDIT- 7674', S-0 'US DEBIT- 2586'.
            for line in lines {
                if let m = matchGroups(line.text, pattern: #"\b(?:DEBIT|CREDIT)[\s\-–]*(\d{4})\b"#),
                   let tail = m[0] {
                    last4 = tail
                    cardConf = line.confidence
                    // Nhiễm gộp: phần dòng SAU lần xuất hiện cuối
                    // của đuôi còn chứa TOTAL (gồm cả SUBTOTAL).
                    if let r = line.text.range(of: tail, options: .backwards) {
                        let rest = line.text[r.upperBound...].uppercased()
                        contaminated = rest.contains("TOTAL")
                    }
                    break
                }
            }
        }
        guard last4 != nil else { return (nil, nil, 0, false) }
        // Brand: dòng chứa tên hãng thẻ (kèm "Debit" nếu in cùng dòng).
        let brands = ["MASTERCARD", "MASTER CARD", "VISA", "AMEX", "AMERICAN EXPRESS", "DISCOVER"]
        var brand: String? = nil
        for line in lines {
            let upper = line.text.uppercased()
            for b in brands where upper.contains(b) {
                var name = b == "MASTER CARD" ? "Mastercard" : b.capitalized
                if b == "AMEX" { name = "Amex" }
                if b == "AMERICAN EXPRESS" { name = "Amex" }
                if upper.contains("DEBIT") { name += " Debit" }
                brand = name
                break
            }
            if brand != nil { break }
        }
        return (last4, brand, cardConf, contaminated)
    }

    // MARK: - Ngày giờ

    private static func findDateTime(in lines: [OCRLine]) -> (date: Date, confidence: Double)? {
        for line in lines {
            if let m = matchGroups(line.text, pattern: #"(\d{1,2})/(\d{1,2})/(\d{2,4})\s+(\d{1,2}):(\d{2})\s*([AP]M)?"#), m.count == 6 {
                // Xử lý AM/PM: "5:49 PM" phải thành 17:49, kẻo giờ bị lệch 12 tiếng.
                var hour = Int(m[3] ?? "") ?? 0
                if let ampm = m[5]?.uppercased() {
                    if ampm == "PM" && hour < 12 { hour += 12 }
                    if ampm == "AM" && hour == 12 { hour = 0 }
                }
                if let d = makeDate(month: Int(m[0] ?? ""), day: Int(m[1] ?? ""), year: Int(m[2] ?? ""),
                                    hour: hour, minute: Int(m[4] ?? "") ?? 0) {
                    return (d, line.confidence)
                }
            }
            // INTEGRATE-V2: ngày tháng CHỮ kiểu Clover —
            // "20-May-2026 1:11:30P": hậu tố AM/PM một chữ cái dính
            // ngay sau giây (có thể có khoảng trắng + chữ M).
            if let m = matchGroups(line.text, pattern: #"(\d{1,2})-([A-Za-z]{3})-(\d{2,4})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([AP])M?"#), m.count == 7,
               let month = monthNumber(m[1]) {
                var hour = Int(m[3] ?? "") ?? 0
                let ampm = m[6]?.uppercased()
                if ampm == "P" && hour < 12 { hour += 12 }
                if ampm == "A" && hour == 12 { hour = 0 }
                if let d = makeDate(month: month, day: Int(m[0] ?? ""), year: Int(m[2] ?? ""),
                                    hour: hour, minute: Int(m[4] ?? "") ?? 0) {
                    return (d, line.confidence)
                }
            }
        }
        return nil
    }

    private static func findDateOnly(in lines: [OCRLine]) -> (date: Date, confidence: Double)? {
        guard let f = findDateOnlyIndexed(in: lines) else { return nil }
        return (f.date, f.confidence)
    }

    /// Như findDateOnly + trả kèm CHỈ SỐ DÒNG của ngày (P1-DATE-
    /// MERGE cần biết ngày nằm ở đâu để ghép giờ trong ±3 dòng).
    private static func findDateOnlyIndexed(in lines: [OCRLine]) -> (date: Date, confidence: Double, index: Int)? {
        for (index, line) in lines.enumerated() {
            if let m = matchGroups(line.text, pattern: #"(\d{1,2})/(\d{1,2})/(\d{2,4})"#), m.count == 3 {
                if let d = makeDate(month: Int(m[0] ?? ""), day: Int(m[1] ?? ""), year: Int(m[2] ?? "")) {
                    return (d, line.confidence, index)
                }
            }
            if let m = matchGroups(line.text, pattern: #"(\d{4})-(\d{2})-(\d{2})"#), m.count == 3 {
                // yyyy-MM-dd
                var comps = DateComponents()
                comps.year = Int(m[0] ?? "")
                comps.month = Int(m[1] ?? "")
                comps.day = Int(m[2] ?? "")
                if let d = Calendar.current.date(from: comps) {
                    return (d, line.confidence, index)
                }
            }
            // INTEGRATE-V2: ngày tháng chữ không kèm giờ
            // ("20-May-2026" đứng một mình).
            if let m = matchGroups(line.text, pattern: #"(\d{1,2})-([A-Za-z]{3})-(\d{2,4})"#), m.count == 3,
               let month = monthNumber(m[1]) {
                if let d = makeDate(month: month, day: Int(m[0] ?? ""), year: Int(m[2] ?? "")) {
                    return (d, line.confidence, index)
                }
            }
        }
        return nil
    }

    /// P1-DATE-MERGE: tìm giờ trong ±3 dòng quanh dòng ngày — chỉ
    /// xét dòng KHÔNG chứa ngày nào (không có ngày cạnh tranh).
    /// Ưu tiên: khoảng cách nhỏ nhất; cùng khoảng cách thì dòng
    /// chỉ-có-giờ thắng dòng chứa giờ-nhúng.
    private static func findTimeNear(in lines: [OCRLine], dateIndex: Int) -> (hour: Int, minute: Int, confidence: Double, index: Int, standalone: Bool)? {
        var best: (dist: Int, notStandalone: Int, index: Int, hour: Int, minute: Int, confidence: Double, standalone: Bool)? = nil
        for (j, line) in lines.enumerated() {
            if j == dateIndex || abs(j - dateIndex) > 3 { continue }
            let text = line.text
            if matchGroups(text, pattern: #"(\d{1,2})/(\d{1,2})/(\d{2,4})"#) != nil
                || matchGroups(text, pattern: #"(\d{4})-(\d{2})-(\d{2})"#) != nil
                || matchGroups(text.uppercased(), pattern: #"\d{1,2}-(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)"#) != nil {
                continue
            }
            var hourMinute: (hour: Int, minute: Int)? = nil
            var standalone = false
            if let m = matchGroups(text, pattern: #"^(\d{1,2}):(\d{2})(?::\d{2})?\s*([AP]M)?$"#), m.count == 3 {
                standalone = true
                var hour = Int(m[0] ?? "") ?? 0
                if let ampm = m[2]?.uppercased() {
                    if ampm == "PM" && hour < 12 { hour += 12 }
                    if ampm == "AM" && hour == 12 { hour = 0 }
                }
                hourMinute = (hour, Int(m[1] ?? "") ?? 0)
            } else if let m = matchGroups(text, pattern: #"(\d{1,2}):(\d{2})(?::\d{2})?\s*([AP]M)?"#), m.count == 3 {
                var hour = Int(m[0] ?? "") ?? 0
                if let ampm = m[2]?.uppercased() {
                    if ampm == "PM" && hour < 12 { hour += 12 }
                    if ampm == "AM" && hour == 12 { hour = 0 }
                }
                hourMinute = (hour, Int(m[1] ?? "") ?? 0)
            }
            guard let hm = hourMinute else { continue }
            let cand = (abs(j - dateIndex), standalone ? 0 : 1, j, hm.hour, hm.minute, line.confidence, standalone)
            if let b = best {
                if (cand.0, cand.1, cand.2) < (b.dist, b.notStandalone, b.index) {
                    best = cand
                }
            } else {
                best = cand
            }
        }
        guard let b = best else { return nil }
        return (b.hour, b.minute, b.confidence, b.index, b.standalone)
    }

    private static func makeDate(month: Int?, day: Int?, year: Int?, hour: Int = 0, minute: Int = 0) -> Date? {
        guard let month = month, let day = day, var year = year else { return nil }
        if year < 100 { year += 2000 }
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        return Calendar.current.date(from: comps)
    }

    // MARK: - Đối chiếu chéo (luật toàn cục số 1 — chỉ gắn cờ, không sửa số)

#endif

    /// PHA 4 (điểm nối, khuyết P4-D4): định dạng tiền cho CHUỖI
    /// CẢNH BÁO nội bộ của validate(). Trước Pha 4 hai điểm gọi
    /// dưới đây dùng formatMoney(cents:) của Models.swift (tầng
    /// app) — module M6 vì thế không biên dịch độc lập được
    /// (BenchShell chỉ liên kết tập module, luật 1.6). Helper này
    /// dùng ĐÚNG công thức NumberFormatter/USD/en_US của
    /// formatMoney gốc nên chuỗi cảnh báo ra y hệt từng ký tự;
    /// Models.swift giữ nguyên formatMoney cho tầng hiển thị.
    private static func warningMoney(_ cents: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: NSNumber(value: Double(cents) / 100.0)) ?? "$0.00"
    }

    // V4-1: bỏ `private` để parseV4 chạy lại đúng bộ phán xét này
    // trên khối tổng đã thay (không fork logic cảnh báo).
    static func validate(_ r: ParseResult) -> [String] {
        var warnings: [String] = []
        if r.totalCents == nil {
            warnings.append("Không đọc được TỔNG TIỀN — anh nhập tay giúp.")
        }
        // P1-FLAG-MISSING (fixture S-0): subtotal vắng mặt trong
        // khi tổng có mặt — cờ tường minh để E1/E2 không thành
        // "thiếu không cờ" (M9).
        if r.subtotalCents == nil, r.totalCents != nil {
            warnings.append("Không đọc được subtotal — không đối chiếu được subtotal + thuế với tổng tiền, anh kiểm tra giúp.")
        }
        // P1-FLAG-MISSING (fixture L-R06): bill CÓ in nhãn số món
        // nhưng token số chết trong luồng — cờ, không đoán.
        if r.itemsSoldLabelSeen, r.itemsSold == nil {
            warnings.append("Số lượng: hoá đơn có in nhãn số món nhưng không đọc được con số đó — anh kiểm tra giúp.")
        }
        if r.date == nil {
            warnings.append("Không đọc được ngày — anh chọn ngày giúp.")
        }
        if !r.items.isEmpty, let subtotal = r.subtotalCents {
            let sum = SafeMoney.sumCents(r.items.map { $0.amountCents ?? 0 })
            if sum == nil || abs((sum ?? 0) - subtotal) > 2 {
                warnings.append("Đối chiếu: tổng các món (\(warningMoney(sum ?? 0))) khác subtotal (\(warningMoney(subtotal))) — có thể đọc sót hoặc sai món.")
            }
        }
        if let subtotal = r.subtotalCents, let total = r.totalCents {
            let expect = SafeMoney.checkedAdd(subtotal, r.taxTotalCents)
            if expect == nil || abs((expect ?? 0) - total) > 2 {
                warnings.append("Đối chiếu: subtotal + thuế (\(warningMoney(expect ?? 0))) khác tổng tiền (\(warningMoney(total))).")
            }
        }
        if let sold = r.itemsSold {
            // P1-E3: tổng đối chiếu theo luật in của vendor
            // (printSemantics trong vendors.json) — Walmart
            // 'onePerLine': mỗi dòng món dương tính 1 (fixture
            // L-R04); mặc định 'byQuantity': cộng qty.
            let qtySum: Int
            if r.soldContribution == "onePerLine" {
                qtySum = r.items.filter { ($0.amountCents ?? 0) > 0 }.count
            } else {
                qtySum = r.items.filter { ($0.amountCents ?? 0) > 0 }.reduce(0) { $0 + $1.qty }
            }
            if qtySum != sold {
                warnings.append("Số lượng: đọc được \(qtySum) món, hoá đơn ghi \(sold) món.")
            }
        }
        if r.totalCents != nil {
            if r.totalConfidence > 0 && r.totalConfidence < 0.60 {
                warnings.append("Tổng tiền độ tin cậy THẤP — bắt buộc kiểm tra lại với giấy.")
            } else if r.totalConfidence >= 0.60 && r.totalConfidence < 0.85 {
                warnings.append("Tổng tiền chưa thật chắc — anh kiểm tra giúp.")
            }
        }
        // P3-FLAG-CARD (Pha 3 — khoản treo Pha 1): đuôi thẻ là
        // khoá phân loại Personal/Business; một chữ số chết ở đuôi
        // (ca L-R09 đọc "2580", đúng 2586) lọt qua các pha trước
        // KHÔNG một cờ nào. Kỷ luật như cờ tổng ở ngay trên: dòng
        // bị gộp với dòng tổng hoặc tin cậy < 0.60 -> cảnh báo
        // mạnh; 0.60..0.85 -> cảnh báo mềm. Cờ KHÔNG sửa giá trị
        // và KHÔNG khẳng định đuôi sai (fixture Pha 3: L-R01/S-0
        // bị cờ dù đuôi đọc đúng — chi phí đã ghi nhận).
        if let tail = r.cardLast4 {
            if r.cardLineContaminated {
                warnings.append("Đuôi thẻ \(tail) nằm trên dòng bị gộp với dòng tổng (đọc không sạch) — bắt buộc kiểm tra lại với giấy để phân loại đúng.")
            } else if r.cardConfidence > 0 && r.cardConfidence < 0.60 {
                warnings.append("Đuôi thẻ \(tail) độ tin cậy THẤP — bắt buộc kiểm tra lại với giấy để phân loại đúng.")
            } else if r.cardConfidence >= 0.60 && r.cardConfidence < 0.85 {
                warnings.append("Đuôi thẻ chưa thật chắc — anh kiểm tra giúp khi phân loại.")
            }
        }
        // WP5 — kỷ luật C-11 mở rộng cho TIỆM và NGÀY (WP5-SPEC mục 6):
        // cùng mẫu ngưỡng 0.60/0.85 với total ở trên (ngưỡng khởi điểm,
        // chưa hiệu chuẩn trên corpus — hiệu chuẩn thuộc bài chấm M1).
        // Phần số học của validate() ở trên giữ NGUYÊN VĂN. Cảnh báo
        // mới đi qua warnings -> ReviewView.save() ép Hộp Chờ như cũ.
        if r.vendor == nil {
            if let suggestion = r.vendorSuggestion {
                warnings.append("Chưa rõ tiệm — gợi ý từ món đặc trưng: \(suggestion) (chưa tự điền).")
            } else {
                warnings.append("Không đọc được tên tiệm — anh nhập tay giúp.")
            }
        } else {
            if r.vendorSource == "tier1-fuzzy" {
                warnings.append("Tên tiệm khớp mờ — anh kiểm tra giúp.")
            }
            if r.vendorSource == "tier2-anchor" {
                warnings.append("Tên tiệm nhận qua địa chỉ/số điện thoại — anh kiểm tra giúp.")
            }
            if r.vendorConfidence > 0 && r.vendorConfidence < 0.60 {
                warnings.append("Tên tiệm độ tin cậy THẤP — bắt buộc kiểm tra lại với giấy.")
            } else if r.vendorConfidence >= 0.60 && r.vendorConfidence < 0.85 {
                warnings.append("Tên tiệm chưa thật chắc — anh kiểm tra giúp.")
            }
        }
        if r.vendorAnchorDisputed {
            warnings.append("Nhiều tiệm cùng khớp neo phụ — không tự điền tên tiệm.")
        }
        if r.date != nil {
            if r.dateConfidence > 0 && r.dateConfidence < 0.60 {
                warnings.append("Ngày độ tin cậy THẤP — bắt buộc kiểm tra lại với giấy.")
            } else if r.dateConfidence >= 0.60 && r.dateConfidence < 0.85 {
                warnings.append("Ngày chưa thật chắc — anh kiểm tra giúp.")
            }
        }
        return warnings
    }

    // MARK: - Tiện ích regex / tiền

    /// Số tiền ở CUỐI một phần chữ: "POM TISSUE 2.00-T" -> (name: "POM TISSUE", -200, flag "T")
#if !GLKEEPER_V4_ONLY
    static func trailingAmount(in text: String) -> (name: String, cents: Int, flag: String?)? {
        guard let ns = matchWithRange(text, pattern: #"\s(\d[\d,]*\.\d{2})(-)?\s*([YT])?$"#),
              let cents = SafeMoney.parseCents(ns.groups[0] ?? "", negative: ns.groups[1] != nil) else { return nil }
        let name = String(text[..<ns.nameEnd])
        return (name.trimmingCharacters(in: .whitespaces), cents, ns.groups[2])
    }

    /// Dòng "N AT 1 FOR X Y" của Sam's. P1-QTYFLAG (fixture N-002:
    /// "2 AT 1 FOR 2.25- 4.50-1" — khe cờ nhận BẤT KỲ một ký tự
    /// đơn nào ("1" là cờ quét T bị đọc méo); cờ chỉ được GHI khi
    /// là Y/T, khớp kỷ luật cờ của đường cùng-dòng; qty/tiền qua
    /// SafeMoney, token ngoài miền -> nil.
    static func matchQtyLine(_ text: String) -> (qty: Int, unitCents: Int, amountCents: Int, flag: String?)? {
        guard let m = matchGroups(text, pattern: #"^(\d+)\s+AT\s+1\s+FOR\s+(\d[\d,]*\.\d{2})(-)?\s+(\d[\d,]*\.\d{2})(-)?\s*(\S)?$"#),
              m.count == 6, let qty = SafeMoney.parseQty(m[0] ?? ""),
              let unit = SafeMoney.parseCents(m[1] ?? "", negative: m[2] != nil),
              let amount = SafeMoney.parseCents(m[3] ?? "", negative: m[4] != nil) else { return nil }
        var flag: String? = nil
        if let f = m[5], f == "Y" || f == "T" { flag = f }
        return (qty, unit, amount, flag)
    }

    /// Số tiền cuối cùng xuất hiện trong dòng (cho dòng thuế generic: "TAX 1 8.517% 9.60").
    /// P1-MONEY-BOUNDARY: ranh giới phải (?!\d) — không cắt token
    /// tiền ma từ số thập phân 4 chữ số (fixture L-R03: suất
    /// "3.9170" từng sinh "3.91" rồi "391"); lấy token thô CUỐI
    /// CÙNG rồi mới qua SafeMoney — token cuối ngoài miền -> nil,
    /// KHÔNG lùi về token trước (đúng hành vi bản gương).
    private static func lastMoneyInLine(_ text: String) -> Int? {
        guard let re = regex(#"(\d[\d,]*\.\d{2})(?!\d)(-)?"#) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let last = re.matches(in: text, options: [], range: range).last,
              last.numberOfRanges >= 2,
              let r1 = Range(last.range(at: 1), in: text) else { return nil }
        let negative = last.numberOfRanges >= 3 && last.range(at: 2).location != NSNotFound
        return SafeMoney.parseCents(String(text[r1]), negative: negative)
    }

    /// Mọi token tiền trong dòng theo luật biên + SafeMoney
    /// (token ngoài miền bỏ qua — KHÔNG bao giờ giả số 0).
    private static func moneyTokensWithBoundary(in text: String) -> [Int] {
        guard let re = regex(#"(\d[\d,]*\.\d{2})(?!\d)(-)?"#) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var out: [Int] = []
        for match in re.matches(in: text, options: [], range: range) {
            guard match.numberOfRanges >= 2,
                  let r1 = Range(match.range(at: 1), in: text) else { continue }
            let negative = match.numberOfRanges >= 3 && match.range(at: 2).location != NSNotFound
            if let c = SafeMoney.parseCents(String(text[r1]), negative: negative) {
                out.append(c)
            }
        }
        return out
    }

    /// Dòng CHỈ chứa một số tiền ("203.30" / "$203.30" / "203.30-").
    private static func bareMoneyCents(_ text: String) -> Int? {
        guard let m = matchGroups(text, pattern: #"^\$?(\d[\d,]*\.\d{2})(-)?$"#),
              m.count == 2, let amountText = m[0] else { return nil }
        return SafeMoney.parseCents(amountText, negative: m[1] != nil)
    }

    // MARK: - PHA 1: ghép nhãn–tiền theo quan hệ hình học (§3.4 (a))
    //
    // Cột tiền = ĐIỂM MỐT của cạnh phải các token tiền cuối dòng
    // (gộp thùng 1% bề rộng, mốt = trung bình thùng đông nhất);
    // dải cột = [mode − 12% bề rộng, mode + 2%]. Ba dạng đã đo trên
    // corpus: FX-SAMELINE (nhãn + tiền cùng dòng), FX-SPLIT-NEXT
    // (tiền đứng dòng riêng NGAY DƯỚI nhãn), FX-BEFORE-LABEL (tiền
    // trần đứng dòng riêng NGAY TRÊN nhãn — luồng 003). Đường hình
    // học chỉ THAY đường chữ khi nó khép E1 trong khi đường chữ
    // không khép; nó không bao giờ viết đè một sổ đã khép, và tập
    // ứng viên của nó luôn được ghi lại (geometricCandidates) cho
    // F5. Dòng cân và dòng số lượng để đường chữ xử lý. Không có
    // boxes -> không chạy (kết quả giống hệt đường chữ, đã đo ở
    // cổng F của bộ kiểm).

    /// Ranh giới vùng tổng theo đúng điều kiện dừng của vòng trích
    /// món khối UPC — chỉ dùng cho khung hình học.
    private static func totalsBoundary(lines: [OCRLine]) -> Int {
        for (i, line) in lines.enumerated() {
            let upper = line.text.uppercased()
            if upper.hasPrefix("SUBTOTAL") || upper.hasPrefix("TOTAL")
                || upper.hasPrefix("SALES TAX") || upper.hasPrefix("TAX")
                || upper.contains("RETURN POLICY") || upper.contains("MAX REFUND VALUE")
                || upper.contains("SUGGESTED TIP") || upper.contains("TIP GUIDE") {
                return i
            }
        }
        return lines.count
    }

    /// (mode, lo, hi) của cột tiền; nil khi < 3 cạnh hoặc không hộp.
    private static func columnModel(lines: [OCRLine], boxes: [CGRect?]) -> (mode: Double, lo: Double, hi: Double)? {
        var edges: [Double] = []
        for (i, line) in lines.enumerated() {
            guard i < boxes.count, let b = boxes[i] else { continue }
            guard lastMoneyInLine(line.text) != nil else { continue }
            // TRAP-FIX (khoá bin): cạnh không hữu hạn (NaN/inf)
            // mà vào Int((e/0.01)...) ở vòng bin dưới là trap.
            let e = Double(b.maxX)
            guard e.isFinite else { continue }
            edges.append(e)
        }
        guard edges.count >= 3 else { return nil }
        var order: [Int] = []
        var buckets: [Int: [Double]] = [:]
        for e in edges {
            // TRAP-FIX (họ A, dạng hữu-hạn-khổng-lồ — ca fuzz
            // box-huge-maxx-moneyline chết ở run #20): chốt
            // isFinite ở vòng nạp cạnh KHÔNG chặn được cạnh
            // hữu hạn nhưng khổng lồ (maxX 1e17 -> khoá bin
            // 1e19 > Int64.max -> Int() trap). Kiểm MIỀN khoá
            // trước khi đổi: |khoá| < 2^63 mới vào bin; ngoài
            // miền -> bỏ cạnh đó (mô hình cột suy từ các cạnh
            // còn lại; rỗng hết thì bestKey nil -> nil ở dưới).
            let scaled = (e / 0.01).rounded()
            guard scaled.isFinite,
                  abs(scaled) < 9_223_372_036_854_775_808.0
            else { continue }
            let key = Int(scaled)
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(e)
        }
        var bestKey: Int? = nil
        var bestCount = -1
        for key in order {
            if buckets[key]!.count > bestCount {
                bestCount = buckets[key]!.count
                bestKey = key
            }
        }
        guard let bk = bestKey, let members = buckets[bk], !members.isEmpty else { return nil }
        let mode = members.reduce(0, +) / Double(members.count)
        return (mode, mode - 0.12, mode + 0.02)
    }

    private static func inBand(box: CGRect?, model: (mode: Double, lo: Double, hi: Double)?) -> Bool {
        guard let model = model else { return true }
        guard let box = box else { return false }
        let right = Double(box.maxX)
        return right >= model.lo && right <= model.hi
    }

    // CI-FIX-1 (lỗi 7, run #39): bản hasAlphaToken thứ hai từng
    // nằm ở đây (vòng lặp isLetter — lệch gương: đếm cả chữ
    // Unicode) đã XOÁ. Định nghĩa DUY NHẤT là bản regex
    // [A-Za-z]{2,} ở khối cùng-dòng — đúng _has_alpha_token của
    // gương port_f4_mirror mà CẢ hai đường (chữ + hình học) dùng
    // chung; điểm gọi trong geometricItems nối về bản đó.

    private static func geometricItems(lines: [OCRLine], boxes: [CGRect?], stop: Int) -> [ParsedLineItem] {
        let model = columnModel(lines: lines, boxes: boxes)
        var tagged: [(Int, ParsedLineItem)] = []
        var consumed: Set<Int> = []
        var pendingBefore: (index: Int, cents: Int)? = nil
        let n = min(stop, lines.count)
        for i in 0..<n {
            if consumed.contains(i) { continue }
            let text = lines[i].text
            let upper = text.uppercased()
            let hasDate = matchGroups(text, pattern: #"(\d{1,2})/(\d{1,2})/(\d{2,4})"#) != nil
                || matchGroups(text, pattern: #"(\d{4})-(\d{2})-(\d{2})"#) != nil
                || matchGroups(upper, pattern: #"\d{1,2}-(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)"#) != nil
            if matchWeightLine(text) != nil || matchQtyLineGeneric(text) != nil
                || isSamelineExcluded(upper) || hasDate {
                pendingBefore = nil
                continue
            }
            if let c = bareMoneyCents(text) {
                if inBand(box: i < boxes.count ? boxes[i] : nil, model: model) {
                    pendingBefore = (i, c)
                    consumed.insert(i)
                }
                continue
            }
            if let got = lastCleanMoney(text), !got.name.isEmpty,
               hasAlphaToken(got.name),
               matchGroups(got.name, pattern: #"\d+\.\d{2}"#) == nil {
                var item = ParsedLineItem(name: got.name, qty: 1, unitPriceCents: got.cents,
                                          amountCents: got.cents, taxFlag: nil, itemCode: nil)
                item.lineIndex = i
                tagged.append((i, item))
                consumed.insert(i)
                pendingBefore = nil
                continue
            }
            if text.contains(where: { $0.isLetter }) {
                if let pb = pendingBefore, pb.index == i - 1 {
                    var item = ParsedLineItem(name: text.trimmingCharacters(in: .whitespaces),
                                              qty: 1, unitPriceCents: pb.cents,
                                              amountCents: pb.cents, taxFlag: nil, itemCode: nil)
                    item.lineIndex = i
                    tagged.append((i, item))
                    consumed.insert(i)
                    pendingBefore = nil
                    continue
                }
                if i + 1 < n, let nc = bareMoneyCents(lines[i + 1].text),
                   inBand(box: i + 1 < boxes.count ? boxes[i + 1] : nil, model: model) {
                    var item = ParsedLineItem(name: text.trimmingCharacters(in: .whitespaces),
                                              qty: 1, unitPriceCents: nc,
                                              amountCents: nc, taxFlag: nil, itemCode: nil)
                    item.lineIndex = i
                    tagged.append((i, item))
                    consumed.insert(i)
                    consumed.insert(i + 1)
                    pendingBefore = nil
                    continue
                }
            }
            pendingBefore = nil
        }
        return tagged.sorted { $0.0 < $1.0 }.map { $0.1 }
    }

    /// Vùng loại trừ của nhánh cùng-dòng (như _sameline_excluded
    /// của đường chữ): tiền tố/đoạn chứa đã biết không phải món.
    private static let samelineExcludePrefix: [String] = [
        "ST#", "OP#", "TE#", "TR#", "TC#", "REF #", "REF#", "AID",
        "TERMINAL", "AUTH", "NETWORK", "APPR", "SEQ#", "STATION", "ORDER",
        "TRANSACTION", "CASHIER", "MEMBER", "DC MEMBER", "SALE", "DEBIT",
        "CREDIT", "EFT", "VISA", "MASTERCARD", "MASTER CARD", "AMEX",
        "DISCOVER", "FSA", "PAYMENT", "AMOUNT", "CHANGE", "CASH", "ENTRY",
        "CONTACTLESS", "RETAIN", "THANK", "GET FREE", "SCAN TO",
        "LOW PRICES", "POLICY", "CONTACT", "ITEM COUNT", "ITEMS SOLD",
        "# ITEMS",
    ]
    // CI-FIX-1 (lỗi 8, run #39): khai báo samelineExcludeContains
    // thứ hai từng nằm ở đây đã XOÁ — nội dung GIỐNG HỆT bản ở
    // khối cùng-dòng (đối chiếu từng phần tử + khớp gương);
    // isSamelineExcluded dùng chung bản đó.
    private static func isSamelineExcluded(_ upper: String) -> Bool {
        if upper.contains("%") { return true }
        if samelineExcludePrefix.contains(where: { upper.hasPrefix($0) }) { return true }
        if samelineExcludeContains.contains(where: { upper.contains($0) }) { return true }
        return false
    }

    /// Dòng cân 'W lb @ $U/lb' — trọng lượng KHÔNG phải qty đếm
    /// món, chỉ là tín hiệu "đây là dòng cân" cho khung hình học.
    /// Trả (lb, đơn giá?) — khung hình học chỉ cần biết có/không.
    private static func matchWeightLine(_ text: String) -> (lb: Double, unitCents: Int?)? {
        guard text.contains("/lb") || text.contains("/1b") else { return nil }
        guard let m = matchGroups(text, pattern: #"(\d+(?:\.\d+)?)\s*(?:lb|1b|Tb)\b"#),
              m.count == 1, let lb = Double(m[0] ?? "") else { return nil }
        var unit: Int? = nil
        if let mu = matchGroups(text, pattern: #"\$\s*\*?\s*(\d[\d,]*\.\d{2})"#) {
            unit = SafeMoney.parseCents(mu[0] ?? "")
        } else if let mu = matchGroups(text, pattern: #"(\d[\d,]*\.\d{2})\s*/l"#) {
            unit = SafeMoney.parseCents(mu[0] ?? "")
        }
        return (lb, unit)
    }

#endif

    private static func regex(_ pattern: String) -> NSRegularExpression? {
        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    /// Nhóm bắt được (nil cho nhóm không tham gia). nil nếu không khớp.
    static func matchGroups(_ text: String, pattern: String) -> [String?]? {
        guard let re = regex(pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = re.firstMatch(in: text, options: [], range: range) else { return nil }
        var groups: [String?] = []
        for i in 1..<match.numberOfRanges {
            let r = match.range(at: i)
            if r.location == NSNotFound {
                groups.append(nil)
            } else if let sr = Range(r, in: text) {
                groups.append(String(text[sr]))
            } else {
                groups.append(nil)
            }
        }
        return groups
    }

    /// Nhóm bắt đầu tiên — dùng khi cần tiền tố sau pattern (vd "INST SV ...").
#if !GLKEEPER_V4_ONLY
    private static func matchPrefix(_ text: String, pattern: String) -> String? {
        guard let groups = matchGroups(text, pattern: pattern), let first = groups.first else { return nil }
        return first
    }

    /// Như matchGroups nhưng thêm vị trí kết thúc của phần TRƯỚC số tiền (để cắt tên món).
    private static func matchWithRange(_ text: String, pattern: String) -> (groups: [String?], nameEnd: String.Index)? {
        guard let re = regex(pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = re.firstMatch(in: text, options: [], range: range),
              let whole = Range(match.range, in: text) else { return nil }
        var groups: [String?] = []
        for i in 1..<match.numberOfRanges {
            let r = match.range(at: i)
            if r.location == NSNotFound {
                groups.append(nil)
            } else if let sr = Range(r, in: text) {
                groups.append(String(text[sr]))
            } else {
                groups.append(nil)
            }
        }
        return (groups, whole.lowerBound)
    }
#endif
}

// MARK: - P2-3 — Lớp trọng tài ĐÃ TÁCH SANG Reconcile.swift (Pha 3)
// Khối reconcile giữ-nguyên-văn của Pha 1 (các dòng 2125-3057 của
// bản Pha 1) nay là module riêng Reconcile.swift + gia cố SafeMoney
// + nối luật in + kênh CANDIDATE. Ba helper dùng chung dưới đây ở
// mức internal để module đó gọi: matchGroups, matchQtyLine,
// trailingAmount. Mọi symbol khác của file này giữ nguyên.
