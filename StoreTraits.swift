// StoreTraits.swift — A10 (vòng 2): hồ sơ tiệm VƯỢT v1, THUẦN Foundation
// (harness biên dịch để kiểm bằng Swift thật).
//
// v1 (StoreProfiles.swift) học ZIP + loại hàng + số tờ. Gói này học
// thêm từ các tờ ANH ĐÃ DUYỆT của cùng tiệm:
// - nét bố cục: số dòng chữ, tỉ lệ dòng mang mã món đầu dòng;
// - nhãn thuế quen của tiệm;
// - vị trí khối tổng (dòng TOTAL cuối cùng, % chiều dài tờ);
// - suất thuế quan sát được (thuế / tạm tính, khi có cả hai);
// - mục chi + loại hàng thuế thường gặp.
//
// LUẬT: hồ sơ CHỈ GỢI Ý, không bao giờ đè số/chữ đọc trên giấy; mọi
// gợi ý mang nhãn "theo tiệm"; dữ liệu ở lại trên máy (JSON trong
// Application Support, không đổi schema SwiftData, không lên mây).

import Foundation

/// Quan sát từ MỘT tờ đã duyệt.
struct StoreTraitObservation: Equatable {
    var lineCount: Int
    var itemCodeLinePct: Int             // 0...100
    var totalLinePct: Int?               // 0...100, nil = không thấy TOTAL
    var taxLabels: [String]
    var taxRatePer100k: Int?             // 8517 = 8.517 %
    var category: String?                // mục chi anh chốt
    var taxCategoryRaw: String?          // TaxCategory.rawValue
}

/// Tích luỹ theo tiệm — mọi trường đều có giá trị mặc định nhưng cả
/// khối được lưu dưới dạng Optional trong StoreProfile, nên file hồ sơ
/// v1 cũ vẫn giải mã được (không mất dữ liệu đã học).
struct StoreTraitsSummary: Codable, Equatable {
    var observations: Int = 0
    var lineCounts: [Int] = []
    var itemCodeLinePcts: [Int] = []
    var totalLinePcts: [Int] = []
    var ratesPer100k: [Int] = []
    var taxLabelCounts: [String: Int] = [:]
    var categoryCounts: [String: Int] = [:]
    var taxCategoryCounts: [String: Int] = [:]
}

enum StoreTraits {
    /// Giữ tối đa chừng này quan sát gần nhất cho mỗi chuỗi số.
    static let window = 20
    /// Nhãn gắn mọi gợi ý (cờ "per-store" theo lệnh A10).
    static let flag = "theo tiệm"

    static func observe(rawText: String, subtotalCents: Int?, taxCents: Int?,
                        taxLabels: [String], category: String?,
                        taxCategoryRaw: String?) -> StoreTraitObservation {
        let lines = rawText.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let n = lines.count
        let codeLines = lines.filter { line in
            line.prefix { $0.isASCII && $0.isNumber }.count >= 6
        }.count
        var totalIdx: Int? = nil
        for (i, l) in lines.enumerated() {
            let sq = l.uppercased().filter { !$0.isWhitespace }
            if sq.contains("TOTAL") && !sq.contains("SUBTOTAL") && !sq.contains("TOTALTAX")
                && !sq.contains("ITEMS") {
                totalIdx = i
            }
        }
        var rate: Int? = nil
        if let s = subtotalCents, let t = taxCents, s > 0, t >= 0 {
            rate = Int((Double(t) * 100_000 / Double(s)).rounded())
        }
        return StoreTraitObservation(
            lineCount: n,
            itemCodeLinePct: n == 0 ? 0 : codeLines * 100 / n,
            totalLinePct: totalIdx.map { n <= 1 ? 100 : $0 * 100 / (n - 1) },
            taxLabels: taxLabels.map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty },
            taxRatePer100k: rate,
            category: (category?.isEmpty ?? true) ? nil : category,
            taxCategoryRaw: taxCategoryRaw)
    }

    static func merge(_ old: StoreTraitsSummary?, _ o: StoreTraitObservation)
        -> StoreTraitsSummary {
        var s = old ?? StoreTraitsSummary()
        func push(_ arr: inout [Int], _ v: Int?) {
            guard let v else { return }
            arr.append(v)
            if arr.count > window { arr.removeFirst(arr.count - window) }
        }
        s.observations += 1
        push(&s.lineCounts, o.lineCount)
        push(&s.itemCodeLinePcts, o.itemCodeLinePct)
        push(&s.totalLinePcts, o.totalLinePct)
        push(&s.ratesPer100k, o.taxRatePer100k)
        for l in Set(o.taxLabels) { s.taxLabelCounts[l, default: 0] += 1 }
        if let c = o.category { s.categoryCounts[c, default: 0] += 1 }
        if let c = o.taxCategoryRaw { s.taxCategoryCounts[c, default: 0] += 1 }
        return s
    }

    static func median(_ xs: [Int]) -> Int? {
        guard !xs.isEmpty else { return nil }
        let s = xs.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }

    /// Giá trị gặp nhiều nhất (hoà -> theo thứ tự chữ cái, xác định).
    static func mode(_ counts: [String: Int]) -> (String, Int)? {
        counts.max { a, b in a.value != b.value ? a.value < b.value : a.key > b.key }
            .map { ($0.key, $0.value) }
    }

    static func percentText(per100k v: Int) -> String {
        let whole = v / 1000
        let frac = v % 1000
        let fracText = String(format: "%03d", frac)
        return "\(whole).\(fracText)%"
    }

    /// Các dòng GỢI Ý để hiển thị — mỗi dòng mang nhãn `flag`. Cần ít
    /// nhất `minObservations` tờ đã duyệt mới gợi ý (một tờ chưa đủ
    /// làm "thói quen" của tiệm).
    static func suggestions(_ s: StoreTraitsSummary?, minObservations: Int = 2) -> [String] {
        guard let s, s.observations >= minObservations else { return [] }
        var out: [String] = []
        let tag = "(\(flag), \(s.observations) tờ đã duyệt)"
        if let (label, n) = mode(s.taxLabelCounts) {
            out.append("Nhãn thuế quen: \(label) — \(n)/\(s.observations) tờ \(tag)")
        }
        if let r = median(s.ratesPer100k) {
            out.append("Suất thuế quan sát: ~\(percentText(per100k: r)) \(tag)")
        }
        if let p = median(s.totalLinePcts) {
            out.append("Khối tổng thường ở ~\(p)% chiều dài tờ \(tag)")
        }
        if let lc = median(s.lineCounts), let ic = median(s.itemCodeLinePcts) {
            out.append("Bố cục: ~\(lc) dòng chữ, ~\(ic)% dòng mở bằng mã món \(tag)")
        }
        if let (cat, n) = mode(s.categoryCounts) {
            out.append("Mục chi thường gặp: \(cat) — \(n)/\(s.observations) tờ \(tag)")
        }
        if let (tc, n) = mode(s.taxCategoryCounts) {
            out.append("Loại hàng thuế thường gặp: \(tc) — \(n)/\(s.observations) tờ \(tag)")
        }
        return out
    }
}
