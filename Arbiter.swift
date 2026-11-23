import Foundation

// =====================================================================
//  Arbiter.swift — CORE-V4 · GÓI V4-1 (DESIGN-V4 §3)
//
//  TRỌNG TÀI khối tổng/thuế: gán vai trò subtotal/taxes/total cho
//  ứng viên tiền bằng ĐẲNG THỨC SỔ, không bằng cổng hình dạng.
//
//   Pha 0 — neo cứng theo nhãn (§3.2) + LUẬT ĐỔI NEO: neo KHÔNG
//     tuyệt đối; nghiệm khép duy nhất thắng neo, trường bị đổi
//     mang provenance anchorOverriddenByClosure. Họ TENDER không
//     bao giờ là neo (§4.4(c) — bẫy "TOTAL DEBIT PURCHASE").
//   Pha 1 — cửa sổ khối: bắt đầu ở dòng nhãn SUBTOTAL/TOTAL đầu
//     tiên (dự phòng TAX; nữa: toàn luồng), lùi lên trên qua các
//     dòng CHỈ-CÓ-TIỀN liên tiếp ngay trước đó (dạng cột của
//     Costco: "125.48"/"9.38" đứng trước dòng "**** TOTAL …").
//   Pha 2 — tập con thuế: cần = total − subtotal; bể = ứng viên
//     khả-thuế trong cửa sổ CÓ BẰNG CHỨNG thuế (dòng họ TAX,
//     hoặc suất đỡ cùng dòng/dòng kề, hoặc nằm giữa hai neo của
//     cặp); tập con ≤4 phần tử khép cần trong dung sai E2. Cặp
//     neo phải đúng thứ tự in (tạm tính trước tổng). Mọi tìm
//     kiếm nằm trong NGÂN SÁCH §3.3 — chạm trần thì fail-closed
//     về nhánh không-nghiệm kèm cờ searchBudgetExceeded, KHÔNG
//     BAO GIỜ chọn nghiệm "gần nhất" vì hết ngân sách.
//
//  Luật nghiệm (§3.4 + khung §6):
//   - Duy nhất theo GIÁ TRỊ → chốt kèm provenance từng trường.
//     (Hai cách gán chỉ khác token trùng giá trị là MỘT nghiệm.)
//   - Còn ≥2 nghiệm khác giá trị sau THANG PHÂN ĐỊNH dưới đây
//     → trường nào khác nhau giữa các nghiệm thì ĐỂ TRỐNG (§6
//     thắng cách đọc "trình bày tạm" của §3.4 đối với trường
//     tiền chính); trường mọi nghiệm đồng ý thì chốt với
//     provenance ambiguousConsensus; toàn bộ nghiệm cạnh tranh
//     ghi vào disputedSolutions cho hồ sơ chẩn đoán.
//   - 0 nghiệm → (§3.5) giữ bản đọc neo/nhãn tốt nhất với
//     provenance hintOnlyUnclosed + thâm hụt δ2 định vị khối.
//
//  THANG PHÂN ĐỊNH (mỗi bậc chỉ LỌC khi còn ≥2 nghiệm khác giá
//  trị và bậc đó còn giữ lại ≥1 nghiệm — không bậc nào tự nó
//  bịa ra nghiệm): (1) khép tuyệt đối (δ=0) thắng khép mức
//  giấy (≤2¢); (2) tập thuế được SUẤT ĐỠ TRỌN (khác rỗng, mọi
//  token có suất cùng dòng/dòng kề — bằng chứng in của dòng
//  phân rã thuế) thắng tập không được đỡ trọn; (3) tổng được
//  CHỨNG THỰC LẶP (giá trị xuất hiện ≥2 lần trên tờ — §3.8
//  "corroboration") thắng tổng xuất hiện một lần; (4) tổng LỚN
//  NHẤT (tổng của tờ ≥ mọi sổ con in lại ở đuôi); (5) token
//  tổng SỚM NHẤT (khối tổng chính đứng trước phần đuôi).
//  Thang này là diễn giải thi công của §3.4 bằng bằng chứng in,
//  rút ra từ ca L-R01 — đã khai trong CHECKS.md để Leader phán.
//
//  Thuế hàm ý (§3.6): hiệu total − subtotal − Σthuế CHỈ là tín
//  hiệu (cờ qua validate() sẵn có) — không bao giờ thành dòng
//  thuế, không vào tổng thuế, không hiển thị như đã đọc.
//
//  Phạm vi V4-1: trọng tài này chỉ phán khối tổng. E1 (Σmón) và
//  E3 (số lượng) được ĐO và ghi thâm hụt/vết — món là của v3 ở
//  gói này; khép E1/E3 thuộc V4-2 (§3.2 pha 3/4).
// =====================================================================

/// Kết quả trọng tài khối tổng — đầu vào duy nhất mà parseV4
/// dùng để thay khối tổng/thuế của v3.
struct TotalsArbitration {
    var subtotalCents: Int? = nil
    var taxes: [ParsedTaxLine] = []
    var totalCents: Int? = nil
    /// Confidence của dòng chứa token tổng đã chốt (0 nếu không có).
    var totalLineConfidence: Double = 0
    /// closed | ambiguous | unclosed | budgetExceeded
    var status: String = "unclosed"
    /// Provenance từng trường khối tổng (§3.7) — khoá "subtotal",
    /// "tax[0]"…, "total"; ghi vào ngăn provenance của chẩn đoán.
    var provenance: [String: FieldProvenance] = [:]
    /// Mô tả các nghiệm cạnh tranh khi ambiguous (§3.4).
    var disputedSolutions: [String] = []
    /// δ1 = Σmón − tạm tính trên bản gán đã chốt/tốt nhất (nil nếu
    /// thiếu một phía) — định vị thâm hụt sang khối món.
    var deficitE1: Int? = nil
    /// δ2 = tạm tính + Σthuế − tổng trên bản gán tốt nhất.
    var deficitE2: Int? = nil
    /// Gợi ý vùng đọc lại (§3.5): "items-block/…" | "totals-block/…".
    var regionHint: String? = nil
    var evaluationsUsed: Int = 0
    /// Vết quyết định ngắn gọn (đưa vào chẩn đoán qua selectionTrace).
    var trace: [String] = []
    /// Bản đồ ứng viên cửa sổ → vai trò phán quyết (P1-CANDIDATES).
    var totalCandidates: [TotalCandidate] = []
    // V4-2 (THUẦN CỘNG THÊM): chỉ số dòng bắt đầu cửa sổ khối
    // tổng — pha món dùng để neo cửa sổ khối món (§4.5).
    var windowStart: Int = 0
    /// V4-2 (THUẦN CỘNG THÊM): tập nghiệm SAU thang phân định,
    /// mỗi giá trị phân biệt một đại diện token — pha món dùng
    /// để phân định liên khối khi khối tổng MƠ HỒ (§3.2 pha 3).
    var effectiveSolutions: [TotalsSolutionView] = []
}

/// Một nghiệm khối tổng nhìn từ ngoài trọng tài (V4-2): bộ giá
/// trị + token đại diện để dựng lại dòng thuế khi E1 phân định.
struct TotalsSolutionView {
    var subtotalCents: Int
    var taxTokens: [MoneyCandidate]
    var totalCents: Int
    var subtotalToken: MoneyCandidate
    var totalToken: MoneyCandidate
    var describe: String {
        "S=\(subtotalCents) taxes=\(taxTokens.map { $0.cents }) T=\(totalCents)"
    }
}

enum TotalsArbiter {

    // Ngân sách tìm kiếm §3.3 — hằng số cứng, chạm là fail-closed.
    static let maxTaxSubsetSize = 4
    static let maxSubsetTrials = 10_000
    static let maxEvaluations = 50_000
    static let maxWindowCandidatesPerRole = 64
    /// Số ứng viên tối đa cho mỗi vai trò khi dựng cặp neo (neo
    /// trước, dự phòng theo điểm gợi ý lấp tới trần này).
    static let maxRoleCandidates = 6
    /// Số cặp neo tối đa được thử.
    static let maxAnchorPairs = 36
    /// Dung sai E2 mức giấy (SCORECARD): khép trong ±2¢ vẫn là khép.
    static let e2ToleranceCents = 2
    /// Cửa sổ lùi qua tối đa ngần này dòng chỉ-có-tiền (pha 1).
    static let maxWindowLookback = 4

    /// Một nghiệm khép theo GIÁ TRỊ (token chỉ để dựng dòng thuế
    /// + provenance; danh tính nghiệm là bộ giá trị).
    private struct Solution {
        var subtotal: Int
        var taxTokens: [MoneyCandidate]   // theo thứ tự dòng
        var total: Int
        var totalToken: MoneyCandidate
        var subtotalToken: MoneyCandidate
        var diff: Int                     // |Σthuế − cần| (0 = khép tuyệt đối)
        var key: String {
            let tv = taxTokens.map { $0.cents }.sorted()
            return "\(subtotal)|\(tv.map(String.init).joined(separator: ","))|\(total)"
        }
        var describe: String {
            let tv = taxTokens.map { $0.cents }
            return "S=\(subtotal) taxes=\(tv) T=\(total)"
        }
    }

    static func arbitrate(lines: [OCRLine], itemsSumCents: Int?,
                          vendorVariants: [String: String]? = nil) -> TotalsArbitration {
        var out = TotalsArbitration()
        let (allMoney, rates, labels) = CandidateFactory.generate(
            lines: lines, vendorVariants: vendorVariants)
        // G2: lượt chính chạy CHỈ trên hồ primary — khi không
        // có alternate, allMoney == money và hành vi y hệt
        // trước G2. Hồ biến thể (ocrVariant) chỉ vào TẦNG CỨU
        // khi lượt chính cho 0 nghiệm (xem rescueSearch).
        let money = allMoney.filter { $0.tier == "primary" }
        let variantMoney = allMoney.filter { $0.tier == "ocrVariant" }
        var evaluations = 0
        var budgetHit = false

        // ---- Pha 1: cửa sổ khối tổng ----
        // L1-REPAIR: dòng tiêu đề cột (chỉ-nhãn + ≥2 từ tiêu
        // đề) không mở cửa sổ — xem isColumnHeaderLine.
        var windowStart: Int? = nil
        for (i, l) in labels.enumerated()
        where (l.family == "SUBTOTAL" || l.family == "TOTAL"
            || TotalsArbiter.isFuzzySubtotalLine(
                text: lines[i].text, family: l.family))
            && !TotalsArbiter.isColumnHeaderLine(
                text: lines[i].text, family: l.family,
                labelOnly: l.labelOnly) {
            windowStart = i; break
        }
        if windowStart == nil {
            for (i, l) in labels.enumerated() where l.family == "TAX" {
                windowStart = i; break
            }
        }
        var wStart = windowStart ?? 0
        // Lùi qua các dòng CHỈ-CÓ-TIỀN liên tiếp ngay trước dòng
        // nhãn đầu tiên (cột tiền không nhãn của Costco).
        var back = 0
        while wStart - back - 1 >= 0 && back < maxWindowLookback {
            let j = wStart - back - 1
            let toks = money.filter { $0.lineIndex == j }
            let hasLetters = lines[j].text.contains { $0.isLetter }
            if toks.count == 1 && !hasLetters { back += 1 } else { break }
        }
        wStart -= back
        let window = money.filter { $0.lineIndex >= wStart }
        out.trace.append("window-start=\(wStart) candidates=\(window.count)")

        // ---- Pha 0: neo nhãn ----
        // Token trên dòng nhãn; dòng nhãn KHÔNG token → token đầu
        // tiên của dòng kế KHI dòng kế không có nhãn riêng (dạng
        // in tách nhãn/tiền hai dòng).
        func anchorTokens(_ family: String) -> [MoneyCandidate] {
            var result: [MoneyCandidate] = []
            for (i, l) in labels.enumerated() where l.family == family {
                let onLine = money.filter { $0.lineIndex == i }
                if let first = onLine.first {
                    result.append(first)
                } else if l.labelOnly, i + 1 < lines.count,
                          labels[i + 1].family == "NONE",
                          let next = money.filter({ $0.lineIndex == i + 1 }).first {
                    result.append(next)
                }
            }
            return result
        }
        let subAnchors = anchorTokens("SUBTOTAL")
        let totAnchors = anchorTokens("TOTAL")

        // Danh sách ứng viên cho một vai trò: NEO TRƯỚC, dự phòng
        // (ứng viên khả-vai trong cửa sổ, điểm gợi ý giảm dần rồi
        // thứ tự dòng) lấp tới trần. Ứng viên dòng TENDER/CHANGE/
        // TAXSUM không bao giờ vào: feasibleRoles của chúng không
        // chứa subtotal/total (luật §4.4(c) ở cả hai tầng).
        // F1 (hồ sơ GATE100-R41, ca 01-walmart-1): token 0¢
        // KHÔNG BAO GIỜ vào danh sách subtotal/total — kể cả
        // khi là token neo. Tổng hoá đơn 0.00 không phải neo
        // tổng; khép hình thức 0+0=0 là khép rác (nó từng
        // chặn ROI chạy và thắng điểm ứng viên). Token 0 giữ
        // nguyên các vai trò khác qua feasibleRoles ở tầng
        // sinh (change/item/tender).
        func roleCandidates(_ role: String, anchors: [MoneyCandidate]) -> [MoneyCandidate] {
            var result: [MoneyCandidate] = []
            var seen = Set<Int>()
            for c in anchors where !seen.contains(c.id) && c.cents != 0 {
                seen.insert(c.id); result.append(c)
            }
            let pool = window.filter { $0.feasibleRoles.contains(role) }
                .sorted { a, b in
                    if a.hintScore != b.hintScore { return a.hintScore > b.hintScore }
                    return a.lineIndex < b.lineIndex
                }
            for c in pool where result.count < maxRoleCandidates {
                if !seen.contains(c.id) && c.cents != 0 {
                    seen.insert(c.id); result.append(c)
                }
            }
            return result
        }
        let subCands = roleCandidates(MoneyRole.subtotal, anchors: subAnchors)
        let totCands = roleCandidates(MoneyRole.total, anchors: totAnchors)
        // Cặp neo: đúng thứ tự in (tạm tính không sau tổng), hai
        // đầu không dùng chung một token.
        var pairs: [(MoneyCandidate, MoneyCandidate)] = []
        for s in subCands { for t in totCands
        where s.id != t.id && s.lineIndex <= t.lineIndex {
            pairs.append((s, t))
        } }
        if pairs.count > maxAnchorPairs { pairs = Array(pairs.prefix(maxAnchorPairs)) }
        out.trace.append("pairs=\(pairs.count) subAnchors=\(subAnchors.count) totAnchors=\(totAnchors.count)")

        // F3 (hồ sơ GATE100-R41, lớp T1): TAXSUM DỰ PHÒNG —
        // khi cửa sổ KHÔNG có token nào trên dòng họ TAX và
        // KHÔNG token nào được suất đỡ, dòng TỔNG THUẾ
        // (TAXSUM, vd "TOTAL TAX: 0.36" của Lowe's) là bằng
        // chứng thuế duy nhất còn lại trên tờ: token của nó
        // được vào bể thuế, mang provenance riêng
        // taxSummaryFallback (khôi phục ngữ nghĩa dự phòng
        // INTEGRATE-V2 của Parser.swift: "TOTAL TAX" chỉ
        // dùng khi không có dòng thuế thành phần). Có token
        // họ TAX thật thì dự phòng KHÔNG kích hoạt — tránh
        // đếm thuế hai lần, đúng lý do V4 hạ TAXSUM xuống
        // giá trị kiểm.
        let taxFallbackActive = !window.contains {
            labels[$0.lineIndex].family == "TAX"
        } && !window.contains {
            CandidateFactory.rateSupported(lineIndex: $0.lineIndex, rates: rates)
        }
        let taxFallbackIDs: Set<Int> = taxFallbackActive
            ? Set(window.filter {
                labels[$0.lineIndex].family == "TAXSUM"
            }.map { $0.id })
            : []

        // ---- Pha 2: tập con thuế trong ngân sách ----
        var solutions: [Solution] = []
        var seenKeys = Set<String>()
        var trials = 0

        pairLoop: for (sTok, tTok) in pairs {
            guard let need = SafeMoney.checkedSubtract(tTok.cents, sTok.cents),
                  need >= 0 else { continue }
            // Bể thuế: khả-thuế trong cửa sổ, trừ chính hai token
            // neo của cặp, trừ token 0 (§3.1 — nghiệm suy biến) và
            // token âm (thuế in không âm); và phải CÓ BẰNG CHỨNG
            // thuế: dòng họ TAX, suất đỡ, hoặc nằm giữa hai neo.
            let lo = min(sTok.lineIndex, tTok.lineIndex)
            let hi = max(sTok.lineIndex, tTok.lineIndex)
            let pool = window.filter {
                ($0.feasibleRoles.contains(MoneyRole.tax)
                    || taxFallbackIDs.contains($0.id))
                    && $0.id != sTok.id && $0.id != tTok.id
                    && $0.cents > 0
                    && (labels[$0.lineIndex].family == "TAX"
                        || taxFallbackIDs.contains($0.id)
                        || CandidateFactory.rateSupported(lineIndex: $0.lineIndex, rates: rates)
                        || (lo <= $0.lineIndex && $0.lineIndex <= hi))
            }.sorted { $0.lineIndex < $1.lineIndex }
            if pool.count > maxWindowCandidatesPerRole {
                budgetHit = true
                out.trace.append("searchBudgetExceeded:pool=\(pool.count)")
                break pairLoop
            }
            // Liệt kê tập con ≤4 phần tử theo thứ tự chỉ số dòng
            // (xác định, không phụ thuộc thứ tự băm). Mọi nút của
            // cây liệt kê = một tập con, gồm cả tập rỗng ở gốc.
            let n = pool.count
            let maxK = min(maxTaxSubsetSize, n)
            var chosen: [Int] = []
            func enumerate(_ start: Int, _ depth: Int) {
                if budgetHit { return }
                do {
                    trials += 1; evaluations += 1
                    if trials > maxSubsetTrials || evaluations > maxEvaluations {
                        budgetHit = true
                        out.trace.append("searchBudgetExceeded:trials=\(trials)")
                        return
                    }
                    var sum = 0
                    var ok = true
                    for idx in chosen {
                        if let v = SafeMoney.checkedAdd(sum, pool[idx].cents) {
                            sum = v
                        } else { ok = false; break }
                    }
                    if ok {
                        let diff = Swift.abs(sum - need)
                        // LUẬT BẰNG CHỨNG THUẾ (Leader, tích hợp
                        // V4-1): bể thuế có bằng chứng mà tập thuế
                        // RỖNG là không thể chấp nhận — token thuế
                        // đã in phải được tính tới (§3.6). Giết
                        // nghiệm suy biến S==T/bỏ thuế (L-R05/06).
                        if diff <= e2ToleranceCents
                            && !(chosen.isEmpty && !pool.isEmpty) {
                            let sol = Solution(
                                subtotal: sTok.cents,
                                taxTokens: chosen.map { pool[$0] },
                                total: tTok.cents,
                                totalToken: tTok, subtotalToken: sTok,
                                diff: diff)
                            if !seenKeys.contains(sol.key) {
                                seenKeys.insert(sol.key)
                                solutions.append(sol)
                            }
                        }
                    }
                }
                guard depth < maxK else { return }
                var i = start
                while i < n {
                    chosen.append(i)
                    enumerate(i + 1, depth + 1)
                    chosen.removeLast()
                    if budgetHit { return }
                    i += 1
                }
            }
            enumerate(0, 0)
            if budgetHit { break pairLoop }
        }
        out.evaluationsUsed = evaluations

        // F2 (hồ sơ GATE100-R41, lớp T5): luật bằng chứng
        // thuế áp TOÀN CỤC — tồn tại ≥1 nghiệm có tập thuế
        // KHÁC RỖNG thì MỌI nghiệm tập-rỗng bị loại TRƯỚC
        // thang phân định. Luật cũ chỉ áp trong từng cặp
        // neo: cặp có bể thuế rỗng vẫn đẻ nghiệm suy biến
        // S==T, và nó cạnh tranh ngang nghiệm thật của cặp
        // khác (ca 40-mcdonalds-4: (529,[],529) hoà với
        // (499,[30],529) tới mơ hồ). Tờ không thuế thật —
        // mọi nghiệm đều tập-rỗng — luật không đổi hành vi.
        if solutions.contains(where: { !$0.taxTokens.isEmpty }) {
            solutions = solutions.filter { !$0.taxTokens.isEmpty }
        }

        // ---- Thang phân định nghiệm (đầu file) ----
        func distinctKeys(_ sols: [Solution]) -> Set<String> { Set(sols.map { $0.key }) }
        var effective = solutions
        let exact = effective.filter { $0.diff == 0 }
        if !exact.isEmpty { effective = exact }
        if distinctKeys(effective).count > 1 {
            // Bậc 2: tập thuế được suất đỡ trọn — đòi tập KHÁC
            // RỖNG (tập rỗng "đỡ trọn" theo nghĩa chân không sẽ
            // giết mọi ca thuế không in suất).
            let supported = effective.filter {
                !$0.taxTokens.isEmpty && $0.taxTokens.allSatisfy {
                    CandidateFactory.rateSupported(lineIndex: $0.lineIndex, rates: rates)
                }
            }
            if !supported.isEmpty { effective = supported }
        }
        if distinctKeys(effective).count > 1 {
            // Bậc 2b (F4, hồ sơ GATE100-R41, ca 03-target-1):
            // NEO NHÃN CỨNG — nghiệm dùng token neo SUBTOTAL
            // cứng (subAnchors) thắng nghiệm không dùng. Chỉ
            // phá hoà giữa các nghiệm ĐÃ khép còn sót sau bậc
            // suất đỡ (nghiệm gương của ca 03 dùng hai token
            // trên CÙNG dòng thuế nên suất đỡ không tách
            // được); chỉ chạy khi còn ≥2 nghiệm khác giá trị
            // nên luật Pha 0 (nghiệm duy nhất thắng neo) và
            // các ca khép duy nhất không bị chạm.
            let hardAnchored = effective.filter { sol in
                subAnchors.contains { $0.id == sol.subtotalToken.id }
            }
            if !hardAnchored.isEmpty { effective = hardAnchored }
        }
        if distinctKeys(effective).count > 1 {
            // Bậc 3: tổng được chứng thực lặp trên toàn tờ.
            let corro = effective.filter { sol in
                money.filter { $0.cents == sol.total }.count >= 2
            }
            if !corro.isEmpty { effective = corro }
        }
        // Bậc 4–5 (tổng lớn nhất / token tổng sớm nhất) là
        // heuristic thuần tuý, KHÔNG phải bằng chứng in: theo
        // phán quyết Leader khi tích hợp V4-1 (thi hành §3.4
        // "không chọn thầm"), nếu sau bậc 3 vẫn còn >1 nghiệm
        // khác giá trị thì kết cục là MƠ HỒ — bậc 4/5 bị vô
        // hiệu hoá cho mục đích chốt, tập nghiệm giữ nguyên
        // như sau bậc 3 để nhánh mơ hồ trình bày đầy đủ.
        if distinctKeys(effective).count > 1 {
            out.trace.append("ladder: post-evidence rivals=\(distinctKeys(effective).count) -> ambiguous (§3.4)")
        }
        out.trace.append("solutions=\(solutions.count) effective=\(distinctKeys(effective).count)")

        // V4-2 (THUẦN CỘNG THÊM): cửa sổ + tập nghiệm sau thang
        // cho pha món — KHÔNG đổi bất kỳ quyết định nào ở trên.
        out.windowStart = wStart
        var seenEff = Set<String>()
        for sol in effective where !seenEff.contains(sol.key) {
            seenEff.insert(sol.key)
            out.effectiveSolutions.append(TotalsSolutionView(
                subtotalCents: sol.subtotal, taxTokens: sol.taxTokens,
                totalCents: sol.total, subtotalToken: sol.subtotalToken,
                totalToken: sol.totalToken))
        }

        // ---- Dựng dòng thuế từ token của một nghiệm ----
        func buildTaxes(_ toks: [MoneyCandidate]) -> [ParsedTaxLine] {
            buildTaxLines(tokens: toks, labels: labels, rates: rates)
        }
        func prov(_ kind: String, _ detail: String) -> FieldProvenance {
            FieldProvenance(kind: kind, detail: detail)
        }
        // Luật provenance cho trường neo: đúng token neo → hardAnchor;
        // có neo khác bị nghiệm khép lật → anchorOverriddenByClosure;
        // không có neo → closureUnique.
        func anchorRule(chosen: MoneyCandidate, anchors: [MoneyCandidate]) -> (String, String) {
            if anchors.contains(where: { $0.id == chosen.id }) {
                return ("anchored", "hardAnchor")
            }
            if !anchors.isEmpty {
                return ("anchored", "anchorOverriddenByClosure")
            }
            return ("read", "closureUnique")
        }
        func deficits(subtotal: Int?, taxes: [ParsedTaxLine], total: Int?) {
            if let s = subtotal, let isum = itemsSumCents {
                out.deficitE1 = SafeMoney.checkedSubtract(isum, s)
            }
            if let s = subtotal, let t = total,
               let taxSum = SafeMoney.sumCents(taxes.map { $0.amountCents }),
               let st = SafeMoney.checkedAdd(s, taxSum) {
                out.deficitE2 = SafeMoney.checkedSubtract(st, t)
            }
        }
        func candidateMap(chosenTaxIDs: Set<Int>, subtotalID: Int?, totalID: Int?) {
            out.totalCandidates = window.map { c in
                var role = MoneyRole.unassigned
                var chosen = false
                if let sid = subtotalID, c.id == sid {
                    role = MoneyRole.subtotal; chosen = true
                } else if let tid = totalID, c.id == tid {
                    role = MoneyRole.total; chosen = true
                } else if chosenTaxIDs.contains(c.id) {
                    role = MoneyRole.tax; chosen = true
                } else if c.feasibleRoles.count == 1 {
                    role = c.feasibleRoles.first ?? MoneyRole.unassigned
                }
                return TotalCandidate(lineIndex: c.lineIndex, cents: c.cents,
                                      role: role, chosen: chosen)
            }
        }

        if budgetHit {
            // Fail-closed: về nhánh không-nghiệm, gắn cờ ngân sách.
            out.status = "budgetExceeded"
            applyBestEffort(&out, lines: lines, labels: labels, money: money,
                            window: window, subAnchors: subAnchors,
                            totAnchors: totAnchors, rates: rates,
                            buildTaxes: buildTaxes, prov: prov)
            deficits(subtotal: out.subtotalCents, taxes: out.taxes, total: out.totalCents)
            out.regionHint = "totals-block/search-budget-exceeded"
            candidateMap(chosenTaxIDs: [], subtotalID: nil, totalID: nil)
            return out
        }

        if distinctKeys(effective).count == 1, let sol = effective.first {
            // L1 ca WR-dollartree-1 (phụ lục DFIX của hồ sơ
            // Gate D): dòng tiêu đề cột "DESCRIPTION QTY PRICE
            // TOTAL" mang họ TOTAL → cửa sổ mở TRƯỚC khối món
            // và thừa kế neo biến token món đầu tiên (1.00) thành
            // neo tổng; hồ chính khép suy biến (100, [], 100)
            // bằng hai token món. Nghiệm ĐÚNG (500, [25], 525)
            // chỉ tồn tại ở hồ biến thể (tiền in gãy khoảng
            // trắng "$5. 00" / "$0 25" / "$5 25") — mà luật vào
            // tầng cứu hiện hành (chỉ khi hồ chính 0 nghiệm)
            // không bao giờ cho nó chạy. Đây là luật bằng chứng
            // thuế (INT-V4-01) mở rộng qua tầng: khi nghiệm
            // chính khép với tập thuế RỖNG trong khi tờ CÓ bằng
            // chứng thuế in ở tầng biến thể (token biến thể
            // trên dòng họ TAX mà dòng đó không có token chính
            // nào), nghiệm chính phải đối mặt phép tìm gộp.
            // Nhận kết quả gộp CHỈ khi nó khép duy nhất, có
            // thuế khác rỗng, và khác giá trị với nghiệm chính;
            // mọi trường hợp còn lại nghiệm chính đứng nguyên
            // từng trường — kỷ luật "biến thể không lật khép có
            // sẵn" chỉ nới đúng tại điểm bằng chứng thuế này.
            if sol.taxTokens.isEmpty, !variantMoney.isEmpty,
               variantMoney.contains(where: { v in
                   labels[v.lineIndex].family == "TAX"
                       && v.lineIndex >= wStart
                       && !money.contains { $0.lineIndex == v.lineIndex }
               }),
               var rescued = rescueSearch(
                   lines: lines, primaries: money, variants: variantMoney,
                   rates: rates, labels: labels,
                   itemsSumCents: itemsSumCents,
                   evaluationsSoFar: evaluations, trialsSoFar: trials),
               rescued.status == "closed", !rescued.taxes.isEmpty,
               rescued.subtotalCents != sol.subtotal
                   || rescued.totalCents != sol.total {
                rescued.trace.append(
                    "challenge: primary closure had empty taxes while "
                    + "variant-tier tax evidence exists — combined "
                    + "closure wins")
                return rescued
            }
            // ---- DUY NHẤT theo giá trị → chốt (§3.4) ----
            out.status = "closed"
            out.subtotalCents = sol.subtotal
            out.taxes = buildTaxes(sol.taxTokens)
            out.totalCents = sol.total
            out.totalLineConfidence = lines[sol.totalToken.lineIndex].confidence
            let (sk, sd) = anchorRule(chosen: sol.subtotalToken, anchors: subAnchors)
            out.provenance["subtotal"] = prov(sk, sd)
            let (tk, td) = anchorRule(chosen: sol.totalToken, anchors: totAnchors)
            out.provenance["total"] = prov(tk, td)
            for (i, tok) in sol.taxTokens.enumerated() {
                // F3: token thuế đến từ dòng TAXSUM dự phòng
                // mang provenance riêng để truy vết được nó
                // không phải dòng thuế thành phần.
                out.provenance["tax[\(i)]"] = taxFallbackIDs.contains(tok.id)
                    ? prov("read", "taxSummaryFallback")
                    : prov("read", "closureUnique")
            }
            out.trace.append("solution=\(sol.describe) diff=\(sol.diff)")
            deficits(subtotal: out.subtotalCents, taxes: out.taxes, total: out.totalCents)
            if let d1 = out.deficitE1, d1 != 0 {
                out.regionHint = "items-block/e1-deficit:\(d1)"
            }
            candidateMap(chosenTaxIDs: Set(sol.taxTokens.map { $0.id }),
                         subtotalID: sol.subtotalToken.id, totalID: sol.totalToken.id)
            return out
        }

        if distinctKeys(effective).count > 1 {
            // ---- MƠ HỒ (§3.4 + §6): trường tranh chấp để trống ----
            out.status = "ambiguous"
            out.disputedSolutions = effective.map { $0.describe }
            out.trace.append("ambiguous solutions=\(effective.count)")
            let subValues = Set(effective.map { $0.subtotal })
            let totValues = Set(effective.map { $0.total })
            let taxKeys = Set(effective.map {
                $0.taxTokens.map { $0.cents }.sorted()
            })
            if subValues.count == 1, let s = subValues.first {
                out.subtotalCents = s
                out.provenance["subtotal"] = prov("read", "ambiguousConsensus")
            }
            if totValues.count == 1, let t = totValues.first,
               let sol = effective.first(where: { $0.total == t }) {
                out.totalCents = t
                out.totalLineConfidence = lines[sol.totalToken.lineIndex].confidence
                out.provenance["total"] = prov("read", "ambiguousConsensus")
            }
            if taxKeys.count == 1, let sol = effective.first {
                out.taxes = buildTaxes(sol.taxTokens)
                for (i, _) in out.taxes.enumerated() {
                    out.provenance["tax[\(i)]"] = prov("read", "ambiguousConsensus")
                }
            }
            deficits(subtotal: out.subtotalCents, taxes: out.taxes, total: out.totalCents)
            out.regionHint = "totals-block/ambiguous"
            candidateMap(chosenTaxIDs: [], subtotalID: nil, totalID: nil)
            return out
        }

        // ---- 0 nghiệm (§3.5) ----
        // G2 — TẦNG CỨU bằng hồ alternate (§2.6): chỉ chạy khi
        // hồ chính cho ĐÚNG 0 nghiệm (không chạy khi mơ hồ —
        // mơ hồ nghĩa là hồ chính ĐÃ khép được, biến thể không
        // bao giờ lật một khép có sẵn) và ngân sách chưa chạm.
        // Nhận kết quả cứu chỉ khi nó cho nghiệm khép DUY NHẤT
        // theo giá trị; ngoài ra kết cục chính đứng nguyên
        // từng trường, không trộn.
        if !variantMoney.isEmpty,
           let rescued = rescueSearch(
               lines: lines, primaries: money, variants: variantMoney,
               rates: rates, labels: labels, itemsSumCents: itemsSumCents,
               evaluationsSoFar: evaluations, trialsSoFar: trials) {
            return rescued
        }
        // Bản đọc neo/nhãn tốt nhất + thâm hụt.
        out.status = "unclosed"
        applyBestEffort(&out, lines: lines, labels: labels, money: money,
                        window: window, subAnchors: subAnchors,
                        totAnchors: totAnchors, rates: rates,
                        buildTaxes: buildTaxes, prov: prov)
        // L1 ca 06-kroger-1 (hồ sơ GATE100-R41, lớp T6): ca
        // TRẢ TÁCH hai phương tiện — tờ không in tạm tính,
        // tổng thật chỉ nằm trên dòng BALANCE và được trả
        // bằng hai tender cộng lại đúng bằng nó (EBT 4.18 +
        // thẻ 6.47 = 10.65). Best-effort vừa trình neo tổng
        // cuối (phần thẻ 6.47 — xem luật mặt nạ EMV ở
        // labelFamily) làm tổng; nếu phép phân rã tender
        // DUY NHẤT theo giá trị tồn tại, ghi đè tổng bằng
        // token BALANCE đó với provenance riêng. Trạng thái
        // GIỮ "unclosed": không có tạm tính in nên E2 không
        // kiểm chứng được — trình "closed" là nói quá bằng
        // chứng. Thuế giữ nguyên bản thu hoạch của
        // best-effort (dòng TAX đọc đúng 0.49).
        let tenderSum = splitTenderBalance(lines: lines, labels: labels,
                                           money: money)
        if let tenderSum {
            out.totalCents = tenderSum.cents
            out.totalLineConfidence = lines[tenderSum.lineIndex].confidence
            out.provenance["total"] = prov("read", "tenderSumClosure")
            out.trace.append(
                "tender-sum: balance token \(tenderSum.cents)@line "
                + "\(tenderSum.lineIndex + 1) is the unique split-tender sum")
        }
        deficits(subtotal: out.subtotalCents, taxes: out.taxes, total: out.totalCents)
        if let d2 = out.deficitE2, d2 != 0 {
            out.regionHint = "totals-block/e2-deficit:\(d2)"
        } else {
            out.regionHint = "totals-block/no-closure"
        }
        if tenderSum != nil {
            out.regionHint = "totals-block/tender-sum-closure"
        }
        candidateMap(chosenTaxIDs: [], subtotalID: nil,
                     totalID: tenderSum?.id)
        return out
    }

    /// L1 ca 06-kroger-1: tìm token TỔNG-THẬT kiểu trả tách.
    /// Một token trên dòng chứa "BALANCE" là tổng thật khi nó
    /// phân rã DUY NHẤT theo giá trị thành tổng của 2–4 token
    /// phân biệt: các token nằm từ dòng BALANCE đầu tiên trở
    /// đi, không nằm trên dòng BALANCE, dương, và không thuộc
    /// khối tổng/thuế (họ SUBTOTAL/TAX/TAXSUM bị loại — token
    /// thuế không phải mảnh tender). "Duy nhất" tính theo ĐA
    /// TẬP GIÁ TRỊ: nhiều token cùng giá trị hoán đổi nhau
    /// vẫn là một phân rã. Đúng một token BALANCE đủ điều
    /// kiện mới trả về; mơ hồ (0 hoặc ≥ 2 token đủ điều
    /// kiện, hoặc ≥ 2 đa tập phân rã) → nil, fail-closed.
    /// Phân rã một mảnh (tender == tổng, ca trả thường) bị
    /// loại bởi luật ≥ 2 mảnh. Trần hồ 12 token giữ phép
    /// liệt kê hữu hạn (2^12 mặt nạ).
    private static func splitTenderBalance(lines: [OCRLine],
                                           labels: [LineLabel],
                                           money: [MoneyCandidate])
        -> MoneyCandidate? {
        func isBalanceLine(_ i: Int) -> Bool {
            lines[i].text.uppercased().contains("BALANCE")
        }
        let balanceTokens = money.filter { isBalanceLine($0.lineIndex) }
        guard let firstBalanceLine = balanceTokens.map({ $0.lineIndex }).min()
        else { return nil }
        var qualifying: [MoneyCandidate] = []
        for b in balanceTokens {
            let pool = money.filter { c in
                c.lineIndex >= firstBalanceLine
                    && !isBalanceLine(c.lineIndex)
                    && c.cents > 0 && c.id != b.id
                    && !["SUBTOTAL", "TAX", "TAXSUM"]
                        .contains(labels[c.lineIndex].family)
            }
            if pool.count > 12 { continue }
            var multisets = Set<[Int]>()
            let n = pool.count
            var mask = 0
            while mask < (1 << n) {
                let bits = mask.nonzeroBitCount
                if bits >= 2 && bits <= 4 {
                    var sum = 0
                    var values: [Int] = []
                    for j in 0..<n where mask & (1 << j) != 0 {
                        sum += pool[j].cents
                        values.append(pool[j].cents)
                    }
                    if sum == b.cents {
                        multisets.insert(values.sorted())
                    }
                }
                mask += 1
            }
            if multisets.count == 1 { qualifying.append(b) }
        }
        return qualifying.count == 1 ? qualifying[0] : nil
    }

    // MARK: - L1: nhãn tạm tính mờ cho cửa sổ Pha 1 (ca F3/28)

    /// L1 ca F3/28 (hồ sơ GATE100-R41 §1.3, đòn bẩy hồ sơ ghi
    /// "consider"): nhãn tạm tính sai ĐÚNG MỘT ký tự (vd
    /// "SUBTUTAL") trượt contains("SUBTOTAL") → họ NONE →
    /// cửa sổ Pha 1 mở muộn tại dòng TOTAL đầu tiên, token
    /// tạm tính + thuế nằm NGOÀI cửa sổ và khối tổng không
    /// khép được (ca 28: cửa sổ mở tại INVOICE TOTAL, best-
    /// effort trình 0.32 của dòng TOTAL DISCOUNT làm tổng).
    /// Nấc mờ này CHỈ mở cửa sổ: dòng vẫn họ NONE, KHÔNG
    /// thành neo, KHÔNG tự chốt số — khép vẫn phải qua liệt
    /// kê nghiệm duy nhất như thường (fail-closed). Điều
    /// kiện chặt: họ NONE + từ chữ đầu tiên của dòng (đã ép
    /// khoảng trắng) dài ≥ 7 và lệch đúng 1 phép sửa so với
    /// "SUBTOTAL". Quét toàn corpus đóng băng 116 luồng:
    /// ngoài ca 28 không dòng nào chạm điều kiện này.

    // MARK: - L1-REPAIR: dòng tiêu đề cột không mở cửa sổ Pha 1

    /// L1-REPAIR (WR-dollartree-1): dòng TIÊU ĐỀ CỘT của khối
    /// món ("DESCRIPTION CTY PRICE TOTAL") chứa chữ "TOTAL"
    /// → họ TOTAL → cửa sổ Pha 1 mở ngay tại đó, TRƯỚC toàn
    /// bộ khối món; tầng món lấy cửa sổ theo windowStart nên
    /// mọi dòng món nằm NGOÀI cửa sổ → 0 món ở cả hai bản
    /// trước/sau L1 (bằng chứng: stream dump run #44, 10/10
    /// set đều items=0). Khi L1 sửa đúng khối tổng (100 →
    /// 500), hạng tử |Σmón − tạm tính| phình 100 → 500 và
    /// cổng roigate tính hồi quy so với làn cũ (400). Luật
    /// hẹp: dòng mở cửa sổ bị BỎ QUA khi nó là dòng chỉ-nhãn
    /// (labelOnly — không token tiền) VÀ mang ≥ 2 từ tiêu đề
    /// cột (DESCRIPTION/QTY/CTY/PRICE/AMOUNT/ITEM/CODE) —
    /// dòng nhãn tổng thật ("TOTAL" đứng một mình, tiền ở
    /// dòng sau) không mang chữ tiêu đề cột nên không chạm.
    /// Bỏ qua = quét tiếp xuống dòng SUBTOTAL/TOTAL sau;
    /// không có dòng sau thì giữ nguyên đường fallback cũ.
    /// Quét sim 116 luồng đóng băng: luật chỉ đổi 2 luồng —
    /// dollartree (món 0 → vào cửa sổ) và 40-mcdonalds-4
    /// (món δ −499 → 0); 28/29-lowes và 06-kroger không đổi.
    /// (Bản rộng "bỏ mọi dòng chỉ-nhãn" đổi 12 luồng, có ca
    /// xấu đi rõ — ĐÃ LOẠI, xem L1-REPAIR-DOSSIER.)
    private static let columnHeaderWords = ["DESCRIPTION", "QTY", "CTY",
                                            "PRICE", "AMOUNT", "ITEM",
                                            "CODE"]
    static func isColumnHeaderLine(text: String, family: String,
                                   labelOnly: Bool) -> Bool {
        guard labelOnly, family == "SUBTOTAL" || family == "TOTAL"
        else { return false }
        let upper = text.uppercased()
        var hits = 0
        for w in columnHeaderWords where upper.contains(w) {
            hits += 1
            if hits >= 2 { return true }
        }
        return false
    }

    private static func isFuzzySubtotalLine(text: String,
                                                family: String) -> Bool {
        guard family == "NONE" else { return false }
        let squashed = text.uppercased().filter { !$0.isWhitespace }
        var lead = ""
        for ch in squashed {
            if ch.isLetter { lead.append(ch) } else { break }
        }
        guard lead.count >= 7 else { return false }
        return editDistanceIsOne(lead, "SUBTOTAL")
    }

    /// Hai chuỗi lệch nhau đúng MỘT phép sửa (thay một ký tự,
    /// hoặc thêm/bớt một ký tự) hay không.
    private static func editDistanceIsOne(_ a: String, _ b: String) -> Bool {
        let x = Array(a), y = Array(b)
        if abs(x.count - y.count) > 1 { return false }
        if x.count == y.count {
            var diffs = 0
            for i in x.indices where x[i] != y[i] {
                diffs += 1
                if diffs > 1 { return false }
            }
            return diffs == 1
        }
        let (s, l) = x.count < y.count ? (x, y) : (y, x)
        var i = 0, j = 0, skipped = false
        while i < s.count && j < l.count {
            if s[i] == l[j] {
                i += 1; j += 1
            } else {
                if skipped { return false }
                skipped = true
                j += 1
            }
        }
        return true
    }

    // MARK: - G2: tầng cứu bằng hồ alternate (§2.6)

    /// Tìm khép sổ trên hồ GỘP (primary + ocrVariant) — chỉ
    /// được gọi khi hồ chính cho 0 nghiệm và ngân sách chưa
    /// chạm. Luật nhận: nghiệm khép DUY NHẤT theo giá trị sau
    /// thang bằng chứng (khớp tuyệt đối > suất đỡ > chứng
    /// thực lặp — chứng thực đếm trên token CHÍNH, vì biến thể
    /// là bản đọc khác của cùng một lần in, không phải lần in
    /// thứ hai). Một nghiệm không dùng hai ứng viên cùng nhóm
    /// xung đột (hai bản đọc của cùng một token in). Trường
    /// chốt bằng token biến thể mang provenance
    /// "closureVariant" (§2.6 + ví dụ §3.9). Ngân sách §3.3
    /// dùng CHUNG với lượt chính (đếm tiếp từ
    /// evaluationsSoFar/trialsSoFar); chạm ngân sách → nil.
    /// Không có nghiệm duy nhất → nil: kết cục chính đứng
    /// nguyên từng trường.
    private static func rescueSearch(
        lines: [OCRLine], primaries: [MoneyCandidate],
        variants: [MoneyCandidate], rates: [RateCandidate],
        labels: [LineLabel], itemsSumCents: Int?,
        evaluationsSoFar: Int, trialsSoFar: Int) -> TotalsArbitration? {
        let combined = primaries + variants
        var out = TotalsArbitration()
        out.trace.append("rescue: variant pool size=\(variants.count)")
        var evaluations = evaluationsSoFar
        var trials = trialsSoFar
        var budgetHit = false

        // Cửa sổ: cùng phép như lượt chính (lùi qua dòng
        // chỉ-có-tiền đếm trên token CHÍNH; dòng tiêu đề cột
        // không mở cửa sổ — L1-REPAIR, xem isColumnHeaderLine).
        var windowStart: Int? = nil
        for (i, l) in labels.enumerated()
        where (l.family == "SUBTOTAL" || l.family == "TOTAL"
            || TotalsArbiter.isFuzzySubtotalLine(
                text: lines[i].text, family: l.family))
            && !TotalsArbiter.isColumnHeaderLine(
                text: lines[i].text, family: l.family,
                labelOnly: l.labelOnly) {
            windowStart = i; break
        }
        if windowStart == nil {
            for (i, l) in labels.enumerated() where l.family == "TAX" {
                windowStart = i; break
            }
        }
        var wStart = windowStart ?? 0
        var back = 0
        while wStart - back - 1 >= 0 && back < maxWindowLookback {
            let j = wStart - back - 1
            let toks = primaries.filter { $0.lineIndex == j }
            let hasLetters = lines[j].text.contains { $0.isLetter }
            if toks.count == 1 && !hasLetters { back += 1 } else { break }
        }
        wStart -= back
        out.windowStart = wStart
        let window = combined.filter { $0.lineIndex >= wStart }

        // Neo: trên hồ GỘP — dòng nhãn không có token chính
        // vẫn có thể có token biến thể (dòng TOTAL in gãy).
        func anchorTokens(_ family: String) -> [MoneyCandidate] {
            var result: [MoneyCandidate] = []
            for (i, l) in labels.enumerated() where l.family == family {
                let onLine = combined.filter { $0.lineIndex == i }
                if let first = onLine.first {
                    result.append(first)
                } else if l.labelOnly, i + 1 < lines.count,
                          labels[i + 1].family == "NONE",
                          let next = combined.filter({ $0.lineIndex == i + 1 }).first {
                    result.append(next)
                }
            }
            return result
        }
        let subAnchors = anchorTokens("SUBTOTAL")
        let totAnchors = anchorTokens("TOTAL")

        // Liệt kê nghiệm trên một HỒ ứng viên cho trước:
        // hồ gộp nguyên trạng (lượt cứu thường) hoặc hồ đã
        // nới vai trò trong khối (tầng F7 ở dưới). Thân liệt
        // kê là MỘT — hai lượt chỉ khác hồ đưa vào. Ngân
        // sách §3.3 dùng CHUNG (evaluations/trials đếm tiếp
        // ở hàm ngoài); chạm ngân sách trả nil.
        func enumerateSolutions(_ tokens: [MoneyCandidate]) -> [Solution]? {
            let win = tokens.filter { $0.lineIndex >= wStart }
            let winPrim = tokens.filter {
                $0.tier == "primary" && $0.lineIndex >= wStart
            }
            // Danh sách vai: phần chính y hệt lượt chính (neo
            // trước, hồ chính tới trần), biến thể NỐI SAU — token
            // chính không bao giờ bị biến thể đẩy khỏi danh sách.
            func roleCandidates(_ role: String, anchors: [MoneyCandidate]) -> [MoneyCandidate] {
                var result: [MoneyCandidate] = []
                var seen = Set<Int>()
                for c in anchors where !seen.contains(c.id) && c.cents != 0 {
                    seen.insert(c.id); result.append(c)
                }
                let pool = winPrim.filter { $0.feasibleRoles.contains(role) }
                    .sorted { a, b in
                        if a.hintScore != b.hintScore { return a.hintScore > b.hintScore }
                        return a.lineIndex < b.lineIndex
                    }
                for c in pool where result.count < maxRoleCandidates {
                    if !seen.contains(c.id) && c.cents != 0 {
                        seen.insert(c.id); result.append(c)
                    }
                }
                let vpool = win.filter {
                    $0.tier == "ocrVariant" && $0.feasibleRoles.contains(role)
                }.sorted { $0.lineIndex < $1.lineIndex }
                for c in vpool where result.count < maxRoleCandidates + 6 {
                    if !seen.contains(c.id) && c.cents != 0 {
                        seen.insert(c.id); result.append(c)
                    }
                }
                return result
            }
            let subCands = roleCandidates(MoneyRole.subtotal, anchors: subAnchors)
            let totCands = roleCandidates(MoneyRole.total, anchors: totAnchors)
            var pairs: [(MoneyCandidate, MoneyCandidate)] = []
            for s in subCands { for t in totCands
            where s.id != t.id && s.lineIndex <= t.lineIndex
                && s.conflictGroup != t.conflictGroup {
                pairs.append((s, t))
            } }
            if pairs.count > maxAnchorPairs { pairs = Array(pairs.prefix(maxAnchorPairs)) }

            var solutions: [Solution] = []
            var seenKeys = Set<String>()
            pairLoop: for (sTok, tTok) in pairs {
                guard let need = SafeMoney.checkedSubtract(tTok.cents, sTok.cents),
                      need >= 0 else { continue }
                let lo = min(sTok.lineIndex, tTok.lineIndex)
                let hi = max(sTok.lineIndex, tTok.lineIndex)
                let pool = win.filter {
                    $0.feasibleRoles.contains(MoneyRole.tax)
                        && $0.id != sTok.id && $0.id != tTok.id
                        && $0.conflictGroup != sTok.conflictGroup
                        && $0.conflictGroup != tTok.conflictGroup
                        && $0.cents > 0
                        && (labels[$0.lineIndex].family == "TAX"
                            || CandidateFactory.rateSupported(lineIndex: $0.lineIndex, rates: rates)
                            || (lo <= $0.lineIndex && $0.lineIndex <= hi))
                }.sorted { a, b in
                    if (a.tier == "primary") != (b.tier == "primary") {
                        return a.tier == "primary"
                    }
                    return a.lineIndex < b.lineIndex
                }
                if pool.count > maxWindowCandidatesPerRole {
                    budgetHit = true
                    out.trace.append("rescueBudgetExceeded:pool=\(pool.count)")
                    break pairLoop
                }
                let n = pool.count
                let maxK = min(maxTaxSubsetSize, n)
                var chosen: [Int] = []
                func enumerate(_ start: Int, _ depth: Int) {
                    if budgetHit { return }
                    do {
                        trials += 1; evaluations += 1
                        if trials > maxSubsetTrials || evaluations > maxEvaluations {
                            budgetHit = true
                            out.trace.append("rescueBudgetExceeded:trials=\(trials)")
                            return
                        }
                        var sum = 0
                        var ok = true
                        var usedGroups = Set<Int>()
                        for idx in chosen {
                            let g = pool[idx].conflictGroup
                            if usedGroups.contains(g) { ok = false; break }
                            usedGroups.insert(g)
                            if let v = SafeMoney.checkedAdd(sum, pool[idx].cents) {
                                sum = v
                            } else { ok = false; break }
                        }
                        if ok {
                            let diff = Swift.abs(sum - need)
                            // Luật bằng chứng thuế như lượt chính:
                            // bể có bằng chứng thì tập rỗng bị cấm.
                            if diff <= e2ToleranceCents
                                && !(chosen.isEmpty && !pool.isEmpty) {
                                let sol = Solution(
                                    subtotal: sTok.cents,
                                    taxTokens: chosen.map { pool[$0] },
                                    total: tTok.cents,
                                    totalToken: tTok, subtotalToken: sTok,
                                    diff: diff)
                                if !seenKeys.contains(sol.key) {
                                    seenKeys.insert(sol.key)
                                    solutions.append(sol)
                                }
                            }
                        }
                    }
                    guard depth < maxK else { return }
                    var i = start
                    while i < n {
                        chosen.append(i)
                        enumerate(i + 1, depth + 1)
                        chosen.removeLast()
                        if budgetHit { return }
                        i += 1
                    }
                }
                enumerate(0, 0)
                if budgetHit { break pairLoop }
            }
            return budgetHit ? nil : solutions
        }

        guard let solutions = enumerateSolutions(combined) else {
            out.evaluationsUsed = evaluations
            return nil
        }
        out.evaluationsUsed = evaluations

        // Thang bằng chứng — như lượt chính, trừ bậc chứng
        // thực lặp đếm trên hồ CHÍNH (xem đầu hàm).
        func distinctKeys(_ sols: [Solution]) -> Set<String> {
            Set(sols.map { $0.key })
        }
        var effective = solutions
        let exact = effective.filter { $0.diff == 0 }
        if !exact.isEmpty { effective = exact }
        if distinctKeys(effective).count > 1 {
            let supported = effective.filter {
                !$0.taxTokens.isEmpty && $0.taxTokens.allSatisfy {
                    CandidateFactory.rateSupported(lineIndex: $0.lineIndex, rates: rates)
                }
            }
            if !supported.isEmpty { effective = supported }
        }
        if distinctKeys(effective).count > 1 {
            let corro = effective.filter { sol in
                primaries.filter { $0.cents == sol.total }.count >= 2
            }
            if !corro.isEmpty { effective = corro }
        }
        var sol: Solution? = nil
        if distinctKeys(effective).count == 1 {
            sol = effective.first
        }
        if sol == nil {
            // F7 (hồ sơ GATE100-R41, lớp T3): TẦNG CỨU HOÁN
            // VỊ TRONG KHỐI — lượt cứu thường không cho nghiệm
            // duy nhất thì thử lại với các token thuộc các
            // dòng nhãn khối tổng LIỀN KỀ (họ SUBTOTAL/TAX/
            // TOTAL/TAXSUM trong cửa sổ) được phép hoán cả ba
            // vai trò của khối: lệch hàng cột tiền trói mỗi số
            // tiền vào nhãn của hàng dưới (ca 33-dunkin:
            // 244 + 9 = 253). Chốt chặn của hồ sơ là DUY NHẤT
            // theo giá trị sau khi ưu tiên khép tuyệt đối —
            // ≥2 nghiệm khác giá trị thì KHÔNG nhận (AMD-V4-01
            // nguyên vẹn: mơ hồ đứng yên, không sai thầm).
            let blockFamilies: Set<String> =
                ["SUBTOTAL", "TAX", "TOTAL", "TAXSUM"]
            var widened: [MoneyCandidate] = []
            widened.reserveCapacity(combined.count)
            for c in combined {
                var cc = c
                if blockFamilies.contains(labels[c.lineIndex].family) {
                    cc.feasibleRoles.formUnion(
                        [MoneyRole.subtotal, MoneyRole.tax, MoneyRole.total])
                }
                widened.append(cc)
            }
            if let sols = enumerateSolutions(widened) {
                var eff = sols
                let exactP = eff.filter { $0.diff == 0 }
                if !exactP.isEmpty { eff = exactP }
                if distinctKeys(eff).count == 1 {
                    sol = eff.first
                    out.trace.append(
                        "rescue-permutation: unique closure \(eff[0].describe)")
                } else {
                    out.trace.append(
                        "rescue-permutation: no unique closure (solutions=\(sols.count))")
                }
            }
            out.evaluationsUsed = evaluations
        }
        guard let sol = sol else {
            out.trace.append("rescue: no unique closure (solutions=\(solutions.count))")
            return nil
        }

        // Dựng kết quả cứu.
        out.status = "closed"
        out.subtotalCents = sol.subtotal
        out.taxes = buildTaxLines(tokens: sol.taxTokens, labels: labels, rates: rates)
        out.totalCents = sol.total
        out.totalLineConfidence = lines[sol.totalToken.lineIndex].confidence
        func prov(_ kind: String, _ detail: String) -> FieldProvenance {
            FieldProvenance(kind: kind, detail: detail)
        }
        func fieldProv(chosen: MoneyCandidate, anchors: [MoneyCandidate]) -> FieldProvenance {
            if chosen.tier == "ocrVariant" { return prov("read", "closureVariant") }
            if anchors.contains(where: { $0.id == chosen.id }) {
                return prov("anchored", "hardAnchor")
            }
            if !anchors.isEmpty {
                return prov("anchored", "anchorOverriddenByClosure")
            }
            return prov("read", "closureUnique")
        }
        out.provenance["subtotal"] = fieldProv(chosen: sol.subtotalToken, anchors: subAnchors)
        out.provenance["total"] = fieldProv(chosen: sol.totalToken, anchors: totAnchors)
        for (i, tok) in sol.taxTokens.enumerated() {
            out.provenance["tax[\(i)]"] = tok.tier == "ocrVariant"
                ? prov("read", "closureVariant") : prov("read", "closureUnique")
        }
        out.trace.append("rescue: unique closure \(sol.describe) diff=\(sol.diff)")
        out.effectiveSolutions = [TotalsSolutionView(
            subtotalCents: sol.subtotal, taxTokens: sol.taxTokens,
            totalCents: sol.total, subtotalToken: sol.subtotalToken,
            totalToken: sol.totalToken)]
        if let isum = itemsSumCents {
            out.deficitE1 = SafeMoney.checkedSubtract(isum, sol.subtotal)
        }
        if let taxSum = SafeMoney.sumCents(out.taxes.map { $0.amountCents }),
           let st = SafeMoney.checkedAdd(sol.subtotal, taxSum) {
            out.deficitE2 = SafeMoney.checkedSubtract(st, sol.total)
        }
        if let d1 = out.deficitE1, d1 != 0 {
            out.regionHint = "items-block/e1-deficit:\(d1)"
        }
        out.totalCandidates = window.map { c in
            var role = MoneyRole.unassigned
            var chosen = false
            if c.id == sol.subtotalToken.id {
                role = MoneyRole.subtotal; chosen = true
            } else if c.id == sol.totalToken.id {
                role = MoneyRole.total; chosen = true
            } else if sol.taxTokens.contains(where: { $0.id == c.id }) {
                role = MoneyRole.tax; chosen = true
            } else if c.feasibleRoles.count == 1 {
                role = c.feasibleRoles.first ?? MoneyRole.unassigned
            }
            return TotalCandidate(lineIndex: c.lineIndex, cents: c.cents,
                                  role: role, chosen: chosen)
        }
        return out
    }

    /// Dựng dòng thuế từ token của một nghiệm — bản TĨNH dùng
    /// chung (V4-2: pha món dựng lại dòng thuế của nghiệm được
    /// E1 chọn khi phân định liên khối). Thân hàm là nguyên văn
    /// closure buildTaxes của arbitrate() trước V4-2.
    static func buildTaxLines(tokens: [MoneyCandidate],
                              labels: [LineLabel],
                              rates: [RateCandidate]) -> [ParsedTaxLine] {
        tokens.map { tok in
            let lab = labels[tok.lineIndex]
            let labelLine: Int? = lab.family == "TAX" ? tok.lineIndex
                : (tok.lineIndex > 0 && labels[tok.lineIndex - 1].family == "TAX"
                    && labels[tok.lineIndex - 1].labelOnly
                    ? tok.lineIndex - 1 : nil)
            let rank = lab.family == "TAX" ? lab.rank
                : (labelLine != nil ? labels[labelLine!].rank : nil)
            return ParsedTaxLine(
                label: rank != nil ? "TAX \(rank!)" : "TAX",
                rateText: CandidateFactory.rateText(
                    forTaxLine: tok.lineIndex, labelLine: labelLine, rates: rates),
                amountCents: tok.cents,
                lineIndex: tok.lineIndex)
        }
    }

    /// Bản đọc tốt nhất khi không khép: neo nhãn CUỐI theo vai
    /// (tạm tính/tổng in cuối khối là bản cuối của tờ) + dòng thuế
    /// thu hoạch từ bằng chứng in (token trên dòng TAX — thừa kế
    /// tách dòng chỉ khi dòng kế không nhãn riêng — cộng token
    /// không-nhãn nhưng có suất đỡ nằm giữa hai neo: khối thuế
    /// thật của T-Johnnys in không có chữ TAX). Tất cả mang
    /// provenance hintOnlyUnclosed, khử trùng theo id token.
    private static func applyBestEffort(
        _ out: inout TotalsArbitration, lines: [OCRLine], labels: [LineLabel],
        money: [MoneyCandidate], window: [MoneyCandidate],
        subAnchors: [MoneyCandidate], totAnchors: [MoneyCandidate],
        rates: [RateCandidate],
        buildTaxes: ([MoneyCandidate]) -> [ParsedTaxLine],
        prov: (String, String) -> FieldProvenance) {
        if let s = subAnchors.last {
            out.subtotalCents = s.cents
            out.provenance["subtotal"] = prov("read", "hintOnlyUnclosed")
        }
        if let t = totAnchors.last {
            out.totalCents = t.cents
            out.totalLineConfidence = lines[t.lineIndex].confidence
            out.provenance["total"] = prov("read", "hintOnlyUnclosed")
        }
        var taxTokens: [MoneyCandidate] = []
        var used = Set<Int>()
        for (i, l) in labels.enumerated() where l.family == "TAX" {
            var cand: MoneyCandidate? = nil
            if let tok = money.first(where: { $0.lineIndex == i }) {
                cand = tok
            } else if l.labelOnly, i + 1 < lines.count,
                      labels[i + 1].family == "NONE" {
                cand = money.first(where: { $0.lineIndex == i + 1 })
            }
            if let c = cand, !used.contains(c.id) {
                used.insert(c.id)
                taxTokens.append(c)
            }
        }
        if let sLast = subAnchors.last, let tLast = totAnchors.last {
            for c in window
            where !used.contains(c.id) && c.cents > 0
                && sLast.lineIndex < c.lineIndex && c.lineIndex < tLast.lineIndex
                && CandidateFactory.rateSupported(lineIndex: c.lineIndex, rates: rates) {
                used.insert(c.id)
                taxTokens.append(c)
            }
        }
        taxTokens.sort { $0.lineIndex < $1.lineIndex }
        out.taxes = buildTaxes(taxTokens)
        for (i, _) in out.taxes.enumerated() {
            out.provenance["tax[\(i)]"] = prov("read", "hintOnlyUnclosed")
        }
    }
}


// =====================================================================
//  ItemsArbiter — CORE-V4 · GÓI V4-2 (DESIGN-V4 §3.2 pha 3/4,
//  §3.5, §4)
//
//  Nhận khối tổng ĐÃ phán của TotalsArbiter (V4-1) và:
//   Pha 3 — GÁN MÓN: lắp ứng viên món (ItemCandidates.swift),
//     gán TẤT CẢ món trong bể cho mỗi món phương án tiền tốt
//     nhất theo |δ| tại chỗ (tinh thần §4.1: dòng trong khối
//     món LÀ món cho tới khi số học nói khác), kiểm E1 chống
//     lại subtotal đã trình. Lệch E1 → tối đa 3 nước sửa ĐÚNG
//     BA LOẠI của §3.5 — (i) loại món yếu nhất, (ii) nhận một
//     ứng viên ngoài cửa sổ (chỉ từ phía TRÊN cửa sổ: món in
//     trước khối tổng; dòng dưới cửa sổ là vùng tender/tổng),
//     (iii) nhận một ứng viên bị họ nhãn loại trừ trong cửa sổ
//     — mỗi nước thử mọi ứng viên của loại nước đó theo thứ tự
//     xác định và chốt nước tốt nhất; vẫn lệch → trình BẢN GÁN
//     TỐT NHẤT đã thấy kèm δ1 định vị khối món + cờ. TUYỆT ĐỐI
//     không subset-sum trên khối món (§3.2): phép gán là tuyến
//     tính theo dòng + tối đa 3 nước sửa, mỗi nước ≤ cỡ bể lượt
//     gán lại — bị chặn cứng, xác định, truy vết được.
//     Luật "mỗi bước gán giảm |dư|" của §10.1(c) thuộc về tìm
//     kiếm tập con của KHỐI TỔNG — áp nó vào tầng món thì chết
//     ở L-R01 (món dương cộng dồn 15498 vượt subtotal trước
//     khi 8 dòng INST SV −2950 kéo về; bằng chứng mô phỏng ở
//     v4-2/sim + CHECKS.md — diễn giải đã khai, chờ Leader).
//   Phân định liên khối (§3.2 pha 3 + AMD-V4-01): E1 CHỈ phân
//     định khi khối tổng đang MƠ HỒ — đúng một nghiệm sau thang
//     mà E1 khép được → chuyển khối tổng sang nghiệm đó
//     (provenance closureUnique, vết "e1-discriminated"). Khối
//     tổng đã CHỐT duy nhất thì E1 lệch → cờ ở khối món, KHÔNG
//     lật tổng đã có bằng chứng thang (thứ tự pha của §3.2).
//   Pha 4 — E3: đóng góp soldContribution (dữ liệu tiệm của
//     v3: onePerLine đếm dòng dương; byQuantity cộng qty của
//     món dương) so với neo ITEMS SOLD. Lệch → MỘT nước sửa
//     của thiết kế: khoảng lệch đúng bằng qty của đúng một
//     liên kết N@ chưa nối được → gắn nó vào món gần nhất.
// =====================================================================

struct ItemArbitration {
    var items: [ParsedLineItem] = []
    /// Provenance từng món (§3.7) — khoá "item[j]".
    var provenance: [String: FieldProvenance] = [:]
    /// Khối tổng CUỐI (sau phân định liên khối — có thể đã
    /// chuyển nghiệm so với bản TotalsArbiter đưa vào).
    var totals: TotalsArbitration = TotalsArbitration()
    /// δ1 = Σmón − subtotal đã trình (nil khi thiếu một phía).
    var deficitE1: Int? = nil
    var sumItemsCents: Int? = nil
    var e3Contribution: Int? = nil
    var e3Mismatch: Bool = false
    var switched: Bool = false
    var trace: [String] = []
}

enum ItemsArbiter {

    static let e1ToleranceCents = 2
    static let linkWindow = ItemCandidateFactory.linkWindow

    /// Một lượt gán: mọi món trong bể, theo thứ tự dòng, nhận
    /// phương án tiền tối thiểu hoá |δ| tại chỗ (hoà → số
    /// chính). Trả (bản gán theo dòng, Σ).
    /// G2: `options` là nhà cung cấp phương án — lượt chính
    /// dùng amountOptions (mặc định, hành vi cũ); lượt cứu
    /// dùng amountOptions + variantOptions.
    private static func assignPass(
        pool: [ItemCandidate], target: Int,
        options: (ItemCandidate) -> [Int] = { $0.amountOptions }
    ) -> (chosen: [Int: Int], sigma: Int) {
        var sigma = 0
        var chosen: [Int: Int] = [:]
        for it in pool.sorted(by: { $0.line < $1.line }) {
            let opts = options(it)
            guard !opts.isEmpty else { continue }
            let primary = it.primaryCents
            let best = opts.min { a, b in
                let ka = (abs(sigma + a - target), a == primary ? 0 : 1)
                let kb = (abs(sigma + b - target), b == primary ? 0 : 1)
                return ka < kb
            }
            if let best {
                chosen[it.line] = best
                sigma += best
            }
        }
        return (chosen, sigma)
    }

    /// Thứ tự "yếu nhất trước" cho nước loại (§3.5 nước i):
    /// mảnh không tên → biến thể hậu tố → chưa có liên kết đỡ →
    /// dòng muộn.
    /// V4-3 (§2.7): món mang mã khớp HÌNH DẠNG MÃ của tiệm đã
    /// nhận diện (dữ liệu gợi ý vendors.json, truyền qua
    /// `codeShapes`) được cộng sức mạnh — xếp SAU, loại muộn
    /// hơn. Đây là điểm gợi ý duy nhất của tiệm vào pha món:
    /// mã không khớp vẫn là món bình thường, chỉ yếu hơn một
    /// bậc ở đúng nước loại này — không phải cổng.
    private static func weakKey(_ it: ItemCandidate,
                                chosen: [Int: Int],
                                codeShapes: [String] = []) -> (Int, Int, Int, Int, Int) {
        var shaped = 0
        if !codeShapes.isEmpty, let code = it.itemCode {
            for shape in codeShapes {
                if let re = try? NSRegularExpression(
                    pattern: "^(?:\(shape))$"),
                   re.firstMatch(in: code,
                                 range: NSRange(location: 0,
                                                length: (code as NSString).length)) != nil {
                    shaped = 1
                    break
                }
            }
        }
        return (it.kind == "fragment" ? 0 : 1,
                shaped,
                chosen[it.line] != it.primaryCents ? 0 : 1,
                (!it.qtyLocked && it.weightLb == nil) ? 0 : 1,
                -it.line)
    }

    /// L1 ca tách dòng món (bằng chứng thiết bị 2026-11-17,
    /// tờ L-R09 + luồng DEVICE-A0 của cùng tờ): OCR/assembler
    /// tách MỘT dòng in thành hai dòng kề nhau cùng mã + cùng
    /// giá, cả hai thành món → món bị tính hai lần (CORN 5.26
    /// hiện hai lần trong chi tiết hoá đơn trên máy anh).
    /// Gộp về một món khi dòng sau là bản sao SUY BIẾN của
    /// dòng trước:
    ///   (a) dòng sau CHỈ-MÃ: khung chữ ≤ 2 ký tự (vd
    ///       "077512701330 5.26 R" — đúng hình bản chụp thiết
    ///       bị). Dòng in thật của máy tính tiền luôn mang
    ///       tên; dòng chỉ-mã + tiền không phải một dòng in.
    ///   (b) dòng sau mang tên bị NHIỄU 1–2 ký tự so với dòng
    ///       trước sau khi bỏ hậu tố cờ in (vd "CORN RKGD"
    ///       của luồng A0): CHỈ gộp khi số học chứng minh
    ///       được — Σ gán hiện tại VƯỢT đích E1 và bỏ dòng
    ///       sao làm Σ tiến gần đích hơn.
    /// Cặp song sinh GIỐNG HỆT (lệch 0) KHÔNG bao giờ gộp:
    /// đó là hình hai lần quét thật của cùng một món (ca
    /// L-R03: hai gói ngô in hai dòng giống hệt nhau, Σ món
    /// khép đúng 6760 của GT — gộp sẽ phá khép đúng).
    /// Điều kiện chung: hai dòng LIỀN KỀ (sau = trước + 1),
    /// giá nằm trên chính dòng (amountLine == line — món
    /// treo đã lấp bị loại), giá bằng nhau, dãy số dài nhất
    /// ≥ 7 ký tự trong văn bản hai dòng bằng nhau (mã món),
    /// dòng sau không mang liên kết nào. Giữ dòng đầy đủ
    /// đứng trước, bỏ dòng sao; mỗi lần gộp ghi trace.
    private static func mergeAdjacentDuplicates(
        items: [ItemCandidate], links: [ItemLink], lines: [OCRLine],
        target: Int?, trace: inout [String]
    ) -> [ItemCandidate] {
        let linkedLines = Set(links.flatMap {
            [$0.line, $0.fromItemLine].compactMap { $0 }
        })
        // Σ gán hiện tại của bể trình (cổng số học của (b)) —
        // đúng phép lọc dựng `pool` trong assign.
        var sigma: Int? = nil
        if let target {
            let pool0 = items.filter {
                $0.kind != "broken" && ($0.kind != "hang" || $0.filled)
            }
            sigma = assignPass(pool: pool0, target: target).sigma
        }
        var kept: [ItemCandidate] = []
        for it in items {
            var merged = false
            if let prev = kept.last,
               it.line == prev.line + 1,
               let amount = it.primaryCents,
               amount == prev.primaryCents,
               it.amountLine == it.line, prev.amountLine == prev.line,
               !linkedLines.contains(it.line) {
                let codeA = longestDigitRun(lines[prev.line].text)
                let codeB = longestDigitRun(lines[it.line].text)
                if codeA.count >= 7 && codeA == codeB {
                    let skelB = letterSkeleton(lines[it.line].text)
                    if skelB.count <= 2 {
                        merged = true
                    } else if let target, let s = sigma, s > target,
                              abs(s - amount - target) < abs(s - target) {
                        let skelA = letterSkeleton(lines[prev.line].text)
                        let d = levenshtein(strippedPrintFlags(skelA),
                                            strippedPrintFlags(skelB),
                                            cap: 2)
                        if d >= 1 && d <= 2 { merged = true }
                    }
                    if merged {
                        trace.append(
                            "dup-merge: line \(it.line + 1) into line "
                            + "\(prev.line + 1) (code \(codeA))")
                        if let s = sigma { sigma = s - amount }
                    }
                }
            }
            if !merged { kept.append(it) }
        }
        return kept
    }

    /// Dãy chữ số liên tiếp dài nhất trong văn bản dòng
    /// (mã món in trên dòng — ItemCandidate.itemCode chỉ bắt
    /// mã ở ĐẦU dòng nên dòng tên-trước không có mã ở đó).
    private static func longestDigitRun(_ text: String) -> String {
        var best = ""
        var cur = ""
        for ch in text {
            if ch.isNumber {
                cur.append(ch)
                if cur.count > best.count { best = cur }
            } else {
                cur = ""
            }
        }
        return best
    }

    /// Khung chữ của dòng: chỉ ký tự chữ, đã hoa hoá.
    private static func letterSkeleton(_ text: String) -> String {
        String(text.uppercased().filter { $0.isLetter })
    }

    /// Bỏ hậu tố cờ in lẻ (F/R/X/A/T) ở cuối khung chữ,
    /// giữ tối thiểu 3 ký tự — trước khi so tên hai dòng.
    private static func strippedPrintFlags(_ skeleton: String) -> String {
        var s = skeleton
        while s.count > 3, let last = s.last, "FRXAT".contains(last) {
            s.removeLast()
        }
        return s
    }

    /// Khoảng cách Levenshtein có trần (trả cap + 1 khi vượt
    /// trần — chỉ cần phân biệt 0 / 1–2 / hơn nữa).
    private static func levenshtein(_ a: String, _ b: String,
                                    cap: Int) -> Int {
        let x = Array(a), y = Array(b)
        if abs(x.count - y.count) > cap { return cap + 1 }
        var prev = Array(0...y.count)
        for i in x.indices {
            var cur = [i + 1]
            for j in y.indices {
                cur.append(min(prev[j + 1] + 1, cur[j] + 1,
                               prev[j] + (x[i] == y[j] ? 0 : 1)))
            }
            prev = cur
        }
        return prev[y.count]
    }

    static func assign(lines: [OCRLine], totals: TotalsArbitration,
                       soldAnchor: Int?,
                       contribution: String,
                       vendorVariants: [String: String]? = nil,
                       codeShapes: [String] = []) -> ItemArbitration {
        var out = ItemArbitration()
        var finalTotals = totals
        let (_, rates, labels) = CandidateFactory.generate(
            lines: lines, vendorVariants: vendorVariants)
        let classified = lines.enumerated().map { i, line in
            ItemLineClassifier.classify(text: line.text,
                                        family: labels[i].family,
                                        alternates: line.alternates)
        }
        let window = ItemLineClassifier.itemsWindow(
            lines: lines, classified: classified,
            totalsStart: totals.windowStart)
        out.trace.append("items-window=\(window.start)..<\(window.end)")
        var (items, links) = ItemCandidateFactory.buildItems(
            lines: lines, classified: classified, window: window)

        // Đích E1 + tập subtotal ứng viên cho phân định (§3.2).
        let presentedSub = totals.subtotalCents
        var candSubs = Set(totals.effectiveSolutions.map { $0.subtotalCents })
        if let s = presentedSub { candSubs.insert(s) }
        let target = presentedSub ?? candSubs.min()

        // L1 ca tách dòng món: gộp cặp dòng sao suy biến
        // (một dòng in bị OCR tách hai) TRƯỚC khi dựng bể —
        // xem mergeAdjacentDuplicates. Lượt gộp chỉ bỏ ứng
        // viên khỏi `items`; đích/các bể phụ tính sau đó như
        // thường.
        items = mergeAdjacentDuplicates(items: items, links: links,
                                        lines: lines, target: target,
                                        trace: &out.trace)

        // Bể ngoài cửa sổ (CHỈ phía trên — xem đầu mục) + bể bị
        // họ loại trừ trong cửa sổ (hai nước sửa ii/iii).
        var oowPool: [ItemCandidate] = []
        var exclPool: [ItemCandidate] = []
        for (i, c) in classified.enumerated() {
            if i < window.start,
               c.kind == .itemLine || c.kind == .fragment {
                let it = ItemCandidate(line: i, name: "", kind: "oow")
                it.amountOptions = c.amountOptions
                it.primaryCents = c.primaryCents
                it.primaryTokenText = c.primaryTokenText
                oowPool.append(it)
            }
            if i >= window.start && i < window.end, c.kind == .excluded,
               c.family == "TENDER" || c.family == "CHANGE",
               let last = c.tokens.last {
                let it = ItemCandidate(line: i, name: "", kind: "excl")
                it.amountOptions = [last.cents]
                it.primaryCents = last.cents
                it.primaryTokenText = last.text
                exclPool.append(it)
            }
        }

        let pool = items.filter {
            $0.kind != "broken" && ($0.kind != "hang" || $0.filled)
        }
        let broken = items.filter { $0.kind == "broken" }

        var chosen: [Int: Int] = [:]
        var sigma = 0
        var finalPool = pool
        if let target {
            // Một lượt gán ĐẦY ĐỦ (lượt đầu + các nước sửa)
            // trên một bể + một nhà cung cấp phương án. Lượt
            // chính và lượt cứu G2 dùng chung thân này — thân
            // là nguyên văn khối gán trước G2, chỉ tổng quát
            // hoá bể + phương án.
            func runAssignment(_ poolX: [ItemCandidate],
                               _ options: (ItemCandidate) -> [Int])
                -> (chosen: [Int: Int], sigma: Int, finalPool: [ItemCandidate]) {
                let first = assignPass(pool: poolX, target: target, options: options)
                var chosen = first.chosen
                var sigma = first.sigma
                var best = (abs: abs(sigma - target), chosen: chosen,
                            sigma: sigma, pool: poolX)
                var deficit = sigma - target
                var excludedLines = Set<Int>()
                var statePool = poolX
                var moveTypes = ["exclude", "admitOOW", "admitExcluded"]
                var mv = 0
                while abs(deficit) > e1ToleranceCents && mv < 3
                        && !moveTypes.isEmpty {
                    let mtype = moveTypes.removeFirst()
                    mv += 1
                    let basePool = statePool.filter {
                        !excludedLines.contains($0.line)
                    }
                    var trials: [(absDef: Int, order: Int,
                                   chosen: [Int: Int], sigma: Int,
                                   pool: [ItemCandidate], desc: String)] = []
                    if mtype == "exclude" {
                        let assigned = basePool.filter {
                            chosen[$0.line] != nil && !options($0).isEmpty
                        }.sorted { weakKey($0, chosen: chosen, codeShapes: codeShapes)
                                   < weakKey($1, chosen: chosen, codeShapes: codeShapes) }
                        for (order, cand) in assigned.enumerated() {
                            let tp = basePool.filter { $0.line != cand.line }
                            let r = assignPass(pool: tp, target: target, options: options)
                            trials.append((abs(r.sigma - target), order,
                                           r.chosen, r.sigma, tp,
                                           "exclude line \(cand.line + 1)"))
                        }
                    } else if mtype == "admitOOW" {
                        let baseLines = Set(basePool.map { $0.line })
                        let rest = oowPool.filter {
                            !baseLines.contains($0.line)
                        }
                        for (order, cand) in rest.enumerated() {
                            let tp = basePool + [cand]
                            let r = assignPass(pool: tp, target: target, options: options)
                            trials.append((abs(r.sigma - target), order,
                                           r.chosen, r.sigma, tp,
                                           "admitOOW line \(cand.line + 1)"))
                        }
                    } else {
                        let baseLines = Set(basePool.map { $0.line })
                        let rest = exclPool.filter {
                            !baseLines.contains($0.line)
                        }
                        for (order, cand) in rest.enumerated() {
                            let tp = basePool + [cand]
                            let r = assignPass(pool: tp, target: target, options: options)
                            trials.append((abs(r.sigma - target), order,
                                           r.chosen, r.sigma, tp,
                                           "admitExcluded line \(cand.line + 1)"))
                        }
                    }
                    if trials.isEmpty { continue }
                    trials.sort { ($0.absDef, $0.order) < ($1.absDef, $1.order) }
                    let t = trials[0]
                    out.trace.append("move\(mv):\(t.desc) (trials=\(trials.count))")
                    statePool = t.pool
                    if mtype == "exclude" {
                        excludedLines.formUnion(
                            Set(basePool.map { $0.line })
                                .subtracting(t.pool.map { $0.line }))
                    }
                    chosen = t.chosen
                    sigma = t.sigma
                    deficit = sigma - target
                    if abs(deficit) < best.abs {
                        best = (abs(deficit), chosen, sigma, t.pool)
                    }
                }
                let finalPool: [ItemCandidate]
                if best.abs < abs(sigma - target) {
                    chosen = best.chosen
                    sigma = best.sigma
                    finalPool = best.pool
                } else {
                    finalPool = statePool.filter {
                        !excludedLines.contains($0.line)
                    }
                }
                return (chosen, sigma, finalPool)
            }

            // Lượt chính: phương án primary (hành vi trước G2).
            let primaryRun = runAssignment(pool, { $0.amountOptions })
            chosen = primaryRun.chosen
            sigma = primaryRun.sigma
            finalPool = primaryRun.finalPool

            // G2 — LƯỢT CỨU món (§2.6): chỉ khi E1 chưa khép
            // quá dung sai VÀ có phương án alternate ở đâu đó
            // (món trong cửa sổ, hoặc món GÃY mang biến thể —
            // món gãy có biến thể được vào bể cứu). Nhận lượt
            // cứu CHỈ khi nó khép E1 trong dung sai; ngoài ra
            // lượt chính đứng nguyên từng trường.
            let rescuableBroken = broken.filter { !$0.variantOptions.isEmpty }
            let anyVariant = !rescuableBroken.isEmpty
                || pool.contains { !$0.variantOptions.isEmpty }
            if abs(sigma - target) > e1ToleranceCents, anyVariant {
                let rescueRun = runAssignment(pool + rescuableBroken, { it in
                    var seen = Set<Int>()
                    return (it.amountOptions + it.variantOptions).filter {
                        seen.insert($0).inserted
                    }
                })
                if abs(rescueRun.sigma - target) <= e1ToleranceCents {
                    chosen = rescueRun.chosen
                    sigma = rescueRun.sigma
                    finalPool = rescueRun.finalPool
                    out.trace.append("items-rescue: E1 closed via ocrVariant pool")
                } else {
                    out.trace.append("items-rescue: no E1 closure — primary stands")
                }
            }
        } else {
            for it in pool {
                if let first = it.amountOptions.first {
                    chosen[it.line] = first
                    sigma += first
                }
            }
            finalPool = pool
        }

        // Trình bày: món gãy luôn trình (tiền nil); món có tiền
        // trình khi được gán. Σ/δ1 tính trên đúng bản trình này.
        // G2: món gãy ĐÃ vào bể cứu (nằm trong finalPool) không
        // được trình hai lần.
        let extraBroken = broken.filter { b in
            !finalPool.contains { $0 === b }
        }
        let presented = (finalPool + extraBroken).sorted { $0.line < $1.line }
            .filter { $0.kind == "broken" || chosen[$0.line] != nil }
        let sumItems = presented.reduce(0) { $0 + (chosen[$1.line] ?? 0) }
        out.sumItemsCents = sumItems
        var deficitE1: Int? = nil
        if let target {
            deficitE1 = sumItems - target
        }
        out.deficitE1 = deficitE1
        let closingSubs = candSubs.filter {
            abs(sumItems - $0) <= e1ToleranceCents
        }

        // ---- Pha 4: E3 + một nước sửa (§3.2 pha 4) ----
        func contributionOf(_ pres: [ItemCandidate]) -> Int {
            if contribution == "onePerLine" {
                return pres.filter { (chosen[$0.line] ?? 0) > 0 }.count
            }
            return pres.reduce(0) {
                $0 + ((chosen[$1.line] ?? 0) > 0 ? $1.qty : 0)
            }
        }
        var e3 = contributionOf(presented)
        var e3Mismatch = false
        if let sold = soldAnchor, e3 != sold {
            let gap = sold - e3
            let unlinked = links.filter {
                $0.kind == "qty" && $0.state == "unlinked" && $0.qty == gap
            }
            var fixed = false
            if unlinked.count == 1, gap > 0 {
                let lk = unlinked[0]
                let cands = presented.filter {
                    chosen[$0.line] != nil && !$0.qtyLocked
                        && abs($0.line - lk.line) <= linkWindow
                }
                if let tgt = cands.min(by: { a, b in
                    let da = abs(a.line - lk.line)
                    let db = abs(b.line - lk.line)
                    if da != db { return da < db }
                    let pa = a.line < lk.line ? 0 : 1
                    let pb = b.line < lk.line ? 0 : 1
                    if pa != pb { return pa < pb }
                    return a.line < b.line
                }) {
                    tgt.qty = lk.qty
                    tgt.qtyLocked = true
                    e3 = contributionOf(presented)
                    fixed = e3 == sold
                    if fixed {
                        out.trace.append("e3Repair: qty \(lk.qty) "
                            + "gắn dòng \(tgt.line + 1)")
                    }
                }
            }
            e3Mismatch = !fixed
        }
        out.e3Contribution = e3
        out.e3Mismatch = e3Mismatch

        // ---- Phân định liên khối: CHỈ khi mơ hồ (§3.2 pha 3) ----
        if finalTotals.status == "ambiguous", !closingSubs.isEmpty {
            var seen = Set<String>()
            var fulls: [TotalsSolutionView] = []
            for sol in finalTotals.effectiveSolutions
            where closingSubs.contains(sol.subtotalCents) {
                let key = "\(sol.subtotalCents)|"
                    + sol.taxTokens.map { $0.cents }.sorted()
                        .map(String.init).joined(separator: ",")
                    + "|\(sol.totalCents)"
                if !seen.contains(key) {
                    seen.insert(key)
                    fulls.append(sol)
                }
            }
            if fulls.count == 1 {
                let sol = fulls[0]
                finalTotals.status = "closed"
                finalTotals.subtotalCents = sol.subtotalCents
                finalTotals.taxes = TotalsArbiter.buildTaxLines(
                    tokens: sol.taxTokens, labels: labels, rates: rates)
                finalTotals.totalCents = sol.totalCents
                finalTotals.totalLineConfidence =
                    lines[sol.totalToken.lineIndex].confidence
                var prov: [String: FieldProvenance] = [
                    "subtotal": FieldProvenance(kind: "read",
                                                detail: "closureUnique"),
                    "total": FieldProvenance(kind: "read",
                                             detail: "closureUnique"),
                ]
                for (i, _) in finalTotals.taxes.enumerated() {
                    prov["tax[\(i)]"] = FieldProvenance(
                        kind: "read", detail: "closureUnique")
                }
                finalTotals.provenance = prov
                finalTotals.disputedSolutions = []
                out.switched = true
                out.trace.append("e1-discriminated: \(sol.describe)")
            }
        }

        // δ2 + gợi ý vùng trên khối tổng CUỐI.
        if let s = finalTotals.subtotalCents,
           let t = finalTotals.totalCents,
           let taxSum = SafeMoney.sumCents(
               finalTotals.taxes.map { $0.amountCents }),
           let st = SafeMoney.checkedAdd(s, taxSum) {
            finalTotals.deficitE2 = SafeMoney.checkedSubtract(st, t)
        }
        finalTotals.deficitE1 = deficitE1
        if finalTotals.status == "closed",
           let d = deficitE1, abs(d) > e1ToleranceCents {
            finalTotals.regionHint = "items-block/e1-deficit:\(d)"
        }
        out.totals = finalTotals

        // ---- Vật hoá món + provenance ----
        let e1Closed = target != nil && deficitE1 != nil
            && abs(deficitE1!) <= e1ToleranceCents
        for (j, it) in presented.enumerated() {
            // G2-fix (cổng #33, VT05): món gãy ĐÃ được lượt cứu
            // gán số khép E1 phải vật hoá đúng số đó — bản G2
            // ép nil vô điều kiện cho mọi món gãy nên số cứu
            // bị vứt ở bước vật hoá dù lượt cứu đã nhận. Món
            // gãy không được gán vẫn nil như cũ: lượt chính
            // không bao giờ gán cho món gãy (amountOptions
            // rỗng), nên chosen[dòng gãy] khác nil ⟺ lượt
            // cứu đã chốt nó.
            let amount = chosen[it.line]
            out.items.append(ParsedLineItem(
                name: it.name, qty: it.qty,
                unitPriceCents: it.unitPriceCents,
                amountCents: amount,
                taxFlag: it.taxFlag, itemCode: it.itemCode,
                weightLb: it.weightLb,
                weightUnitCents: it.weightUnitCents,
                lineIndex: it.line))
            let detail: String
            if let amount, !it.amountOptions.contains(amount),
               it.variantOptions.contains(amount) {
                // G2: số chốt đến từ bản đọc THAY THẾ (alternate)
                // và chỉ được nhận vì nó khép E1 (§2.6).
                detail = "closureVariant"
            } else if it.kind == "broken" {
                detail = "brokenMoney"
            } else if let amount, amount != it.primaryCents {
                detail = "suffixVariantOf:\(it.primaryTokenText)"
            } else if e1Closed {
                detail = "closureUnique"
            } else {
                detail = "hintOnlyUnclosed"
            }
            out.provenance["item[\(j)]"] = FieldProvenance(
                kind: "read", detail: detail)
        }
        out.trace.append("items=\(out.items.count) sumItems=\(sumItems) "
            + "deficitE1=\(deficitE1.map(String.init) ?? "nil") "
            + "e3=\(e3) e3Mismatch=\(e3Mismatch)")
        return out
    }
}
