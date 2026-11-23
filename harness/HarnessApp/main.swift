import Foundation
import CoreGraphics
import CoreImage
import ImageIO
import Vision

// MARK: - SoHoaDonHarness — driver tự chạy cốt lõi đọc (CI macOS)
//
// Thi hành LUẬT 2026-11-12 của anh (SỬA 2026-11-15: tối thiểu
// 10 lượt liên tiếp thành công — anh bỏ mức 100 vì các lượt
// 100x cũ đo SAI đường đọc): Muse TỰ CHẠY đường đọc Swift
// THẬT trên hạ tầng của mình trước khi bất kỳ bản nào tới tay
// anh test.
//
// Driver biên dịch NGUYÊN VĂN các file nguồn app vào cùng
// module (xem project-harness.yml): Money, ReadDiagnostics,
// CaptureIntake, OCREngine, LineAssembly, VendorData, Parser,
// Candidates, Arbiter, ItemCandidates, Reconcile,
// RegionReReader, PendingDraft, ReceiptLogic và — TỪ G5 —
// ReadPipeline (ReceiptReader + ReadPipeline.run + ROI).
// ReadPipeline chỉ chạm UIKit ở 3 điểm đã bọc
// #if canImport(UIKit) trong chính file nguồn, nên harness
// chạy ĐÚNG đường đọc của app chứ không tái lập nó nữa;
// HarnessShims.swift đã hưu (file rỗng giữ làm dấu tích).
//
// Chế độ:
//   probe
//       In ngôn ngữ engine hỗ trợ trên máy chạy (Rev3) + phiên
//       bản dữ liệu vendors/lexicon đã nạp. Harness CHỈ có giá
//       trị khi dataVersion != "unloaded".
//   images --dir DIR [--lang current|old|enus] [--topk 1|3]
//          [--sets N] [--dump DIR]
//       G5: chạy toàn bộ ảnh .jpg trong DIR qua
//       ReceiptReader.read — ĐÚNG điểm vào của app (chuỗi ứng
//       viên -> chọn winner -> thu hoạch alternates của G2 ->
//       ReadPipeline.run + vòng ROI), KHÔNG còn gọi thẳng
//       ReceiptParser.parse như bản trước G5 (đó là gốc của
//       vụ "100 lượt xanh giả": cổng Luật 3 cũ đo một đường
//       app không bao giờ chạy). Mặc định --lang old --topk 1
//       = đúng mặc định BenchShell run #46; --lang current
//       --topk 3 = cấu hình run #45. Mỗi ảnh in: điều tra hộp
//       (bao nhiêu hộp không-hữu-hạn — đầu mối ứng viên A của
//       HARNESS-REPRO) + tóm tắt parse + E1/E2 + số vòng ROI
//       thật (roi=). --dump ghi luồng mảnh + dòng ráp + kết
//       quả từng ảnh ra JSON.
//   roigate --dir DIR --gt FILE
//       G5: cổng ẢNH–ROI. Mỗi ảnh chạy HAI làn: làn CŨ (một
//       lượt engine -> ráp dòng -> ReceiptParser.parse, đúng
//       thân chế độ images trước G5) và làn APP
//       (ReceiptReader.read trọn đường). Khẳng định: (1) ca
//       nào làn cũ còn thâm hụt sổ mà làn app VẪN chưa khép
//       thì roiRounds > 0 (ROI phải thật sự chạy ở ca thâm
//       hụt); (2) ít nhất 1 ca lớp F2 (mất chữ số — tập tên
//       file đóng băng trong roiF2Files) được làn app khép
//       trong khi làn cũ không khép; (3) delta từng ca >= 0
//       (không ca nào làn app kém làn cũ theo thước khép sổ
//       + thâm hụt xu). In ROIGATE-CASE từng ca + ROIGATE-DONE
//       tổng kết; sạch thì khép "SURVIVED roigate", có vi
//       phạm thì thoát 1.
//   fixture FILE [--nobox]
//       Parse luồng ĐÃ GHI trong fixture JSON (ca kiểm chứng:
//       luồng L-R01 của engine cũ — audit đã minh oan; harness
//       phải tái xác nhận bằng Swift thật: SURVIVED).
//   fuzz FIXTURE --list | fuzz FIXTURE <id>
//       Bẫy đột biến trên luồng fixture: MỖI đột biến chạy như
//       MỘT process riêng (CI lặp lời gọi) để trap không giết
//       driver. In "SURVIVED <id>" ở cuối nếu parse trở về.
//   unittests
//       G1: test logic thuần (ReceiptLogic) + vòng đời kho
//       nháp (PendingDraftStore) bằng Swift thật — xem
//       UnitTests.swift. In UNITTEST PASS/FAIL từng ca +
//       UNITTESTS-DONE; thoát 1 nếu có FAIL, khép bằng
//       "SURVIVED unittests" khi sạch.
//   ocrprobe FILE [FILE...]
//       PHÉP ĐO LAYER-2 (2026-11-20): pin đọc thử trên ảnh
//       thật — toàn khung ở nhiều hệ số phóng, engine phụ
//       (sàn chiều cao chữ thấp), và CHIA DẢI NGANG có
//       chồng lấn (đọc từng dải, ghép mảnh về toạ độ toàn
//       khung, ráp dòng + parseV4 như app). In OCRPROBE /
//       OCRPROBE-PARSE từng chiến lược, khép bằng
//       "OCRPROBE-DONE". Chỉ ĐO — không phải cổng.
//
// Mọi chế độ chạm parse đều in dòng cuối "SURVIVED ..." — CI
// grep dòng này; thiếu nó + mã thoát/signal != 0 = tái hiện.

// stdout KHÔNG đệm: print() qua pipe mặc định bị đệm theo khối —
// process chết vì trap thì mọi dòng đã in mà chưa xả đều MẤT
// (bài học run #5: cổng control chết lặng không một dòng log).
// Mọi mốc giai đoạn phải chạm được log kể cả khi process chết.
setvbuf(stdout, nil, _IONBF, 0)

// Bẫy tín hiệu TỰ CHẨN ĐOÁN (run #13: macOS không để lại .ips nào
// cho process CLI trên runner CI — thư mục crashreports rỗng).
// Handler in số tín hiệu + ngăn xếp lời gọi ra stderr (không đệm)
// rồi thoát 128+sig, để log CI tự nói chết vì gì và chết ở đâu.
for sig in [SIGILL, SIGSEGV, SIGTRAP, SIGABRT, SIGBUS] {
    signal(sig, { s in
        let head = "HARNESS-SIGNAL sig=\(s)\n"
        FileHandle.standardError.write(Data(head.utf8))
        let stack = Thread.callStackSymbols.joined(separator: "\n") + "\n"
        FileHandle.standardError.write(Data(stack.utf8))
        _exit(128 + s)
    })
}

let args = Array(CommandLine.arguments.dropFirst())

func fail(_ msg: String, code: Int32 = 2) -> Never {
    FileHandle.standardError.write(Data("HARNESS-ERROR: \(msg)\n".utf8))
    exit(code)
}

func argValue(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}
func hasFlag(_ name: String) -> Bool { args.contains(name) }

// MARK: - Cấu hình engine (gương công tắc BenchShell CI-FIX-7)

func applyEngineConfig() {
    switch argValue("--lang") ?? "old" {
    case "old":
        LanguagePolicy.directLanguagesOverride = ["vi-VN", "en-US"]
    case "enus":
        LanguagePolicy.directLanguagesOverride = ["en-US"]
    case "current":
        LanguagePolicy.directLanguagesOverride = nil
    default:
        fail("--lang phải là current|old|enus")
    }
    switch argValue("--topk") ?? "1" {
    case "1": ClassicTextEngine.topCandidates = 1
    case "3": ClassicTextEngine.topCandidates = 3
    default: fail("--topk phải là 1|3")
    }
    ReceiptReader.stageBreadcrumb = { step in
        print("  [stage] \(step)")
    }
}

func requireDataLoaded() {
    // Harness im lặng mà mất dữ liệu = đo sai mà không biết:
    // VendorData rỗng thì identifyVendor rơi generic toàn bộ,
    // DomainCorrector trơ — kết quả vẫn "chạy được" nhưng vô
    // nghĩa. Chặn fail-closed ngay từ cửa.
    if VendorData.shared.dataVersion == "unloaded" {
        fail("vendors.json KHÔNG nạp được (dataVersion=unloaded) — đặt vendors.json cạnh binary harness", code: 3)
    }
    if DomainCorrector.lexiconVersion == "unloaded" {
        fail("lexicon.json KHÔNG nạp được (lexiconVersion=unloaded) — đặt lexicon.json cạnh binary harness", code: 3)
    }
}

// MARK: - Điều tra hộp (ứng viên A: hộp không-hữu-hạn)

func boxCensus(_ boxes: [CGRect]) -> String {
    var nonFinite = 0
    var maxAbsMaxX = 0.0
    for b in boxes {
        let comps = [b.origin.x, b.origin.y, b.width, b.height]
        if comps.contains(where: { !$0.isFinite }) { nonFinite += 1 }
        if b.maxX.isFinite { maxAbsMaxX = max(maxAbsMaxX, abs(Double(b.maxX))) }
    }
    return "boxes=\(boxes.count) nonFinite=\(nonFinite) maxAbsMaxX=\(String(format: "%.4f", maxAbsMaxX))"
}

// MARK: - Chấm E1/E2 + điểm ứng viên (bản driver của makeEvaluation)
//
// ReadPipeline.makeEvaluation là private trong file UIKit nên
// harness không gọi được; bản này tính CÙNG các đại lượng từ
// ParseResult bằng đúng CandidateScorer.score của app
// (CaptureIntake — biên dịch nguyên văn vào harness). integrity
// = tỉ lệ dòng tiền trước ranh giới vùng tổng có cạnh phải
// trong dải cột tiền (moneyColumnBand của app); band nil -> 1.0.
// Ghi nhãn trung thực: công thức integrity là bản driver, cổng
// LUẬT của harness là SỐNG + khép E1/E2, không phải khớp điểm
// tuyệt đối với BenchShell.

// Phase 0: the tuple also carries the evaluation and the full
// CandidateScorer.score result (read-only, for the stream dump's
// scoreComponents); the computed values are unchanged.
func evaluate(parsed: ParseResult, assembly: AssemblyResult)
    -> (e1: Bool, e2: Bool, score: Double, evaluation: CandidateEvaluation, breakdown: Any) {
    var e1 = false
    if let subtotal = parsed.subtotalCents,
       let sum = SafeMoney.sumCents(parsed.items.map { $0.amountCents ?? 0 }) {
        e1 = sum == subtotal
    }
    var e2 = false
    if let subtotal = parsed.subtotalCents, let total = parsed.totalCents {
        let implied = SafeMoney.checkedAdd(subtotal, parsed.taxTotalCents)
        e2 = implied.map { abs($0 - total) <= 2 } ?? false
    }
    var e3 = false
    if let sold = parsed.itemsSold {
        let positive = parsed.items.filter { ($0.amountCents ?? 0) > 0 }
        let counted = parsed.soldContribution == "onePerLine"
            ? positive.count
            : positive.reduce(0) { $0 + $1.qty }
        e3 = counted == sold
    }
    let boundary = CandidateScorer.totalsBoundary(assembly.lines)
    var integrity = 1.0
    if let band = CandidateScorer.moneyColumnBand(assembly.lines) {
        let pre = assembly.lines[..<boundary].filter {
            !SafeMoney.tokens(in: $0.text).isEmpty
        }
        if !pre.isEmpty {
            let inside = pre.filter {
                Double($0.box.maxX) >= band.lo && Double($0.box.maxX) <= band.hi
            }.count
            integrity = Double(inside) / Double(pre.count)
        }
    }
    let ev = CandidateEvaluation(
        e1Closed: e1, e2Within2c: e2, e3Closed: e3,
        integrity: integrity,
        hasSubtotal: parsed.subtotalCents != nil,
        hasTotal: parsed.totalCents != nil,
        hasTaxLine: !parsed.taxes.isEmpty,
        hasDate: parsed.date != nil,
        vendorResolved: parsed.vendor != nil,
        itemsMissingAmount: parsed.items.filter { $0.amountCents == nil }.count,
        alnumChars: assembly.lines.reduce(0) {
            $0 + $1.text.filter { $0.isLetter || $0.isNumber }.count
        },
        isOriginal: true)
    let scored = CandidateScorer.score(ev)
    // Phase 0 fix (review2-R1-A F1): the breakdown carried forward is the
    // components DICTIONARY, not the whole (total, components) tuple —
    // phase0Components can only flatten dict/struct shapes, so the tuple
    // degraded the top-level winner "scoreComponents" to {"total": …}.
    return (e1, e2, scored.total, ev, scored.components)
}

func parseSummary(_ p: ParseResult) -> String {
    let sum = SafeMoney.sumCents(p.items.map { $0.amountCents ?? 0 })
    return "vendor=\(p.vendor ?? "nil") subtotal=\(p.subtotalCents.map(String.init) ?? "nil") "
        + "tax=\(p.taxTotalCents) total=\(p.totalCents.map(String.init) ?? "nil") "
        + "items=\(p.items.count) sumItems=\(sum.map(String.init) ?? "nil") "
        + "sold=\(p.itemsSold.map(String.init) ?? "nil") card=\(p.cardLast4 ?? "nil") "
        + "warnings=\(p.warnings.count)"
}

// MARK: - Nạp ảnh (ImageIO — không UIKit)

func loadCGImage(_ url: URL) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
    return img
}

// MARK: - Một lượt đọc trên ảnh — ĐÚNG đường app (G5)
//
// Trước G5 hàm này tái lập thân runCandidate (recognize ->
// assemble -> ReceiptParser.parse) — đường v3 một lượt mà app
// KHÔNG bao giờ chạy khi quét thật; đó là gốc đo sai của các
// lượt Luật 3 cũ. Từ G5: gọi ReceiptReader.read như ScanView/
// BenchView của app (chuỗi ứng viên đầy đủ, winner, thu hoạch
// alternates G2, ReadPipeline.run + ROI của G2). ReceiptReader
// không ném lỗi: engine hỏng ở mọi ứng viên -> outcome rỗng
// có cờ (fail-closed như app) — cổng images vì thế chấm bằng
// SỐNG sót tiến trình + số khép sổ, và ca rỗng tự lộ ở điểm.

struct ImageRun {
    var outcome: ReadOutcome
    var assembly: AssemblyResult
    var e1: Bool
    var e2: Bool
    var score: Double
    // Phase 0 (dump only): driver evaluation + score breakdown.
    var evaluation: CandidateEvaluation? = nil
    var breakdown: Any? = nil
    var parsed: ParseResult { outcome.result }
    var fragBoxes: [CGRect] {
        outcome.diagnostics.fragments.map { $0.box.cgRect }
    }
    var asmBoxes: [CGRect] {
        outcome.diagnostics.assembly.lines.map { $0.box.cgRect }
    }
}

/// A5 (vòng 2): các ca in vết nguồn gốc ở chế độ images (set 1).
let traceCaseNames: Set<String> = ["25-exxon-1.jpg", "06-kroger-1.jpg",
                                     "39-publix-4.jpg", "37-cvs-pharmacy-3.jpg"]

func printCaseTrace(name: String, run: ImageRun) {
    let lines = run.outcome.diagnostics.assembly.lines
    print("TRACE-CASE \(name) BEGIN lines=\(lines.count)")
    for (i, l) in lines.enumerated() {
        let fam = CandidateFactory.labelFamily(
            of: l.text, hasMoney: l.text.contains { $0.isNumber }).family
        print("TRACE-LINE \(i) [\(fam)] \(l.text)")
    }
    let r = run.parsed
    print("TRACE-RESULT subtotal=\(r.subtotalCents.map(String.init) ?? "nil") "
        + "total=\(r.totalCents.map(String.init) ?? "nil") arb=\(r.arbiterStatus ?? "nil")")
    for t in r.taxes {
        print("TRACE-TAX label=\(t.label) amount=\(t.amountCents) line=\(t.lineIndex.map(String.init) ?? "nil")")
    }
    // Dòng CUỐI mà parse nhìn thấy (sau ROI) — chỉ số dòng của thuế ở
    // trên trỏ vào mảng này, không phải mảng dòng ráp ban đầu.
    for (i, t) in r.rawText.components(separatedBy: "\n").enumerated() {
        let fam = CandidateFactory.labelFamily(
            of: t, hasMoney: t.contains { $0.isNumber }).family
        print("TRACE-FINAL \(i) [\(fam)] \(t)")
    }
    for s in r.selectionTrace { print("TRACE-SEL \(s)") }
    for k in run.outcome.provenance.keys.sorted() {
        print("TRACE-PROV \(k) = \(String(describing: run.outcome.provenance[k]!))")
    }
    print("TRACE-ROI rounds=\(run.outcome.diagnostics.roiRounds.count)")
    print("TRACE-CASE \(name) END")
}

// MARK: - Vòng 3 Phần 1: trục phân biệt Exxon / Kroger (CHỈ ĐO)

/// Nguồn nhận của một dòng thuế cuối, suy từ CHÍNH bộ dòng cuối của
/// parse bằng các hàm công khai của lõi (CandidateFactory) — không
/// gọi vào nội bộ Arbiter.
func taxSource(_ t: ParsedTaxLine, labels: [LineLabel],
               rates: [RateCandidate]) -> String {
    guard let li = t.lineIndex, li >= 0, li < labels.count else {
        return t.label.contains("ước tính") ? "landing-estimate" : "no-line"
    }
    if labels[li].family == "TAX" { return "label-TAX" }
    if labels[li].family == "TAXSUM" { return "label-TAXSUM" }
    if CandidateFactory.rateSupported(lineIndex: li, rates: rates) { return "printed-rate" }
    return "POSITION-ONLY"
}

func finalLines(_ p: ParseResult) -> [OCRLine] {
    p.rawText.components(separatedBy: "\n").map { OCRLine(text: $0, confidence: 0.9) }
}

func printTaxSourceLine(name: String, run: ImageRun) {
    let p = run.parsed
    let lines = finalLines(p)
    let (_, rates, labels) = CandidateFactory.generate(lines: lines)
    let srcs = p.taxes.map { "\($0.amountCents)@\($0.lineIndex.map(String.init) ?? "nil"):"
        + taxSource($0, labels: labels, rates: rates) }
    let posOnly = p.taxes.contains { taxSource($0, labels: labels, rates: rates) == "POSITION-ONLY" }
    print("TAXSRC \(name) arb=\(p.arbiterStatus ?? "nil") e1=\(run.e1) e2=\(run.e2) "
        + "taxes=[\(srcs.joined(separator: ","))] positionOnly=\(posOnly ? "YES" : "no") "
        + "fl299Flag=\(p.warnings.contains { $0.contains("chỉ suy từ VỊ TRÍ") } ? "YES" : "no")")
}

func printAxisTrace(name: String, run: ImageRun) {
    let p = run.parsed
    let lines = finalLines(p)
    let (money, rates, labels) = CandidateFactory.generate(lines: lines)
    let winStart = p.selectionTrace.compactMap { s -> Int? in
        guard let r = s.range(of: "window-start=") else { return nil }
        return Int(s[r.upperBound...].prefix { $0.isNumber })
    }.first
    // (A) nhãn thuế in: ở đâu so với cửa sổ khối tổng.
    let taxLabelLines = labels.indices.filter { labels[$0].family == "TAX" || labels[$0].family == "TAXSUM" }
    let inWin = taxLabelLines.filter { l in winStart.map { l >= $0 } ?? false }
    print("AXIS-A \(name) windowStart=\(winStart.map(String.init) ?? "nil") "
        + "taxLabelLines=\(taxLabelLines) inWindow=\(inWin) beforeWindow=\(taxLabelLines.filter { !inWin.contains($0) }) "
        + "rateLines=\(rates.map { "\($0.lineIndex):\($0.text)" })")
    // (B) % suy ra = thuế / tạm tính; đối chiếu bảng DUY NHẤT trong repo
    // (TaxSeed — vùng Tulsa, OK). Ngoài OK: repo không có bảng -> không
    // kết luận được.
    let seedRates = Set(TaxTable.seed.portions.map {
        Int((($0.statePct + $0.countyPct + $0.cityPct) * 1000).rounded()) })
    if let sub = p.subtotalCents, sub > 0, p.taxTotalCents > 0 {
        let per100k = Int((Double(p.taxTotalCents) * 100_000 / Double(sub)).rounded())
        // khớp nếu thuế làm tròn của sub ở một suất seed == thuế đọc
        let match = TaxTable.seed.portions.contains { pt in
            let r = pt.statePct + pt.countyPct + pt.cityPct
            return Int((Double(sub) * r / 100).rounded()) == p.taxTotalCents
        }
        print("AXIS-B \(name) impliedRate=\(String(format: "%.3f", Double(per100k) / 1000))% "
            + "matchesTulsaSeedRateToTheCent=\(match ? "yes" : "no") seedRatesPct=\(seedRates.sorted().map { String(format: "%.3f", Double($0) / 1000) })")
    } else {
        print("AXIS-B \(name) impliedRate=n/a (sub=\(p.subtotalCents.map(String.init) ?? "nil") tax=\(p.taxTotalCents))")
    }
    // (C) phản thực: bỏ token thuế CHỈ-VỊ-TRÍ khỏi bộ dòng cuối, chạy lại
    // arbiter — còn nghiệm nào khép không, khép ra số gì.
    let base = TotalsArbiter.arbitrate(lines: lines, itemsSumCents: nil)
    print("AXIS-C \(name) asIs status=\(base.status) sub=\(base.subtotalCents.map(String.init) ?? "nil") "
        + "taxes=\(base.taxes.map { $0.amountCents }) total=\(base.totalCents.map(String.init) ?? "nil") "
        + "trace=\(base.trace.joined(separator: " | "))")
    // ứng viên thuế trong cửa sổ không có nhãn/% (cái mà luật vị trí có thể nhận)
    let posCands = money.filter { m in
        guard let w = winStart, m.lineIndex >= w, m.feasibleRoles.contains("tax") else { return false }
        return labels[m.lineIndex].family != "TAX" && labels[m.lineIndex].family != "TAXSUM"
            && !CandidateFactory.rateSupported(lineIndex: m.lineIndex, rates: rates)
    }
    print("AXIS-C \(name) positionalTaxFeasibleInWindow=\(posCands.map { "\($0.cents)@\($0.lineIndex)" })")
    for m in posCands {
        var cut = lines
        cut[m.lineIndex] = OCRLine(text: "", confidence: 0.9)
        let r = TotalsArbiter.arbitrate(lines: cut, itemsSumCents: nil)
        print("AXIS-C \(name) without \(m.cents)@\(m.lineIndex): status=\(r.status) "
            + "sub=\(r.subtotalCents.map(String.init) ?? "nil") taxes=\(r.taxes.map { $0.amountCents }) "
            + "total=\(r.totalCents.map(String.init) ?? "nil")")
    }
    // (D) hàng/khoảng cách: dòng của thuế cuối so với dòng tổng cuối.
    let totalLine = money.first { $0.cents == p.totalCents && $0.lineIndex >= (winStart ?? 0) }?.lineIndex
    for t in p.taxes {
        let d = (t.lineIndex ?? -1) - (totalLine ?? -1)
        print("AXIS-D \(name) tax=\(t.amountCents)@\(t.lineIndex.map(String.init) ?? "nil") "
            + "totalLine=\(totalLine.map(String.init) ?? "nil") rowsFromTotal=\(t.lineIndex == nil || totalLine == nil ? "n/a" : String(d)) "
            + "taxLineText=\(t.lineIndex.flatMap { $0 < lines.count ? lines[$0].text : nil } ?? "-")")
    }
}

func runImage(_ cg: CGImage) -> ImageRun {
    let outcome = ReceiptReader.read(ReadRequest(
        source: .photoLibrary,
        imageFileName: "harness-image.jpg",
        image: cg,
        diagnosticsDirectory: nil,
        // PHA 2: harness chạy hạ cánh bằng bảng hạt giống + khu
        // mặc định Tulsa, không hồ sơ tiệm (dữ liệu máy anh không
        // có trên CI) — khớp hành vi app trừ tầng học.
        taxLandingContext: TaxLandingContext(
            table: .seed,
            defaultAreaID: TaxTable.defaultSeedAreaID,
            profileHints: [:])))
    // AssemblyResult dựng lại từ ngăn assembly của hồ sơ chẩn
    // đoán (dòng của ỨNG VIÊN THẮNG — cùng dòng outcome mang)
    // để evaluate() của driver chấm như cũ.
    let d = outcome.diagnostics
    let assembly = AssemblyResult(
        lines: d.assembly.lines.map {
            AssembledLine(text: $0.text, confidence: $0.confidence,
                          box: $0.box.cgRect, spans: $0.spans,
                          passSources: $0.passSources,
                          contested: $0.contested,
                          alternates: $0.alternates,
                          columnBreaks: [])
        },
        dedupeDropped: d.assembly.dedupeDropped,
        invariantViolations: d.assembly.invariantViolations)
    let ev = evaluate(parsed: outcome.result, assembly: assembly)
    return ImageRun(outcome: outcome, assembly: assembly,
                    e1: ev.e1, e2: ev.e2, score: ev.score,
                    evaluation: ev.evaluation, breakdown: ev.breakdown)
}

func boxDict(_ b: CGRect) -> [String: Double] {
    // JSONSerialization NÉM LỖI trên Double không-hữu-hạn — mà
    // hộp không-hữu-hạn lại chính là bằng chứng săn ở ứng viên
    // A. Ánh xạ: NaN -> -999999, +/-inf -> +/-999999 (census ở
    // stdout giữ con số đếm chính xác; dump chỉ là phụ chứng).
    func fin(_ v: Double) -> Double {
        if v.isNaN { return -999999 }
        if v == .infinity { return 999999 }
        if v == -.infinity { return -999999 }
        return v
    }
    return ["x": fin(Double(b.origin.x)), "y": fin(Double(b.origin.y)),
            "w": fin(Double(b.width)), "h": fin(Double(b.height))]
}

func dumpImageRun(name: String, run: ImageRun, dir: URL) {
    let d = run.outcome.diagnostics
    // Phase 0: winner-side context for the additive per-candidate keys.
    let winnerCtx = Phase0WinnerContext(parsed: run.parsed, e1: run.e1, e2: run.e2,
                                        driverEvaluation: run.evaluation,
                                        driverBreakdown: run.breakdown)
    let obj: [String: Any] = [
        "image": name,
        // F8 (FL-317): census MỌI ứng viên của lượt đọc —
        // kind/biến đổi/điểm/thắng + số mảnh thô + số dòng ráp,
        // để kết án tầng sụp (OCR vs chọn ứng viên) trên đường
        // thật thay vì chỉ nhìn ứng viên thắng.
        "candidates": d.candidates.map { c -> [String: Any] in
            var entry: [String: Any] =
            ["kind": c.kind, "transform": c.transformDesc,
             "gate": c.gateVerdict ?? "",
             "score": c.scoreTotal ?? -999999,
             "winner": c.winner ? 1 : 0,
             "fragments": c.fragmentCount ?? -1,
             "lines": c.lineCount ?? -1]
            // Phase 0 (additive): scoreComponents + parseSummary
            // (+ scoreInputs on the winner, recordFields on all).
            for (k, v) in phase0CandidateFields(record: c, isWinner: c.winner,
                                                winner: winnerCtx) {
                entry[k] = v
            }
            return entry
        },
        "fragmentCensus": boxCensus(run.fragBoxes),
        "fragments": d.fragments.map {
            ["text": $0.text, "confidence": $0.confidence,
             "box": boxDict($0.box.cgRect), "alternates": $0.alternates.count]
        },
        "assembled": d.assembly.lines.map {
            ["text": $0.text, "confidence": $0.confidence, "box": boxDict($0.box.cgRect)]
        },
        "parse": parseSummary(run.parsed),
        "e1": run.e1, "e2": run.e2, "score": run.score,
        // G5: bằng chứng tầng cứu/ROI chạy thật ở cổng images.
        "roiRounds": d.roiRounds.count,
        "roiAccepted": d.roiRounds.filter { $0.accepted }.count,
        "arbiter": run.parsed.arbiterStatus ?? "nil",
        // Phase 0 (additive): schema tag, engine config of this run,
        // structured winner summary + driver score breakdown.
        "dumpSchema": phase0DumpSchema,
        "config": ["lang": argValue("--lang") ?? "old",
                   "topk": ClassicTextEngine.topCandidates] as [String: Any],
        "parseSummary": phase0ParseSummary(run.parsed, e1: run.e1, e2: run.e2,
                                           source: "readOutcome"),
        "scoreComponents": run.breakdown.map { phase0Components($0) } ?? [String: Any](),
        "scoreInputs": run.evaluation.map { phase0Flatten($0, includeStrings: false) }
            ?? [String: Any](),
    ]
    if let data = try? JSONSerialization.data(withJSONObject: obj,
                                              options: [.prettyPrinted, .sortedKeys]) {
        let out = dir.appendingPathComponent(
            name.replacingOccurrences(of: ".jpg", with: "") + ".stream.json")
        // Phase 0: a dump that is not written is logged (it used to be
        // dropped silently); stream_compare --expect also catches it.
        do { try data.write(to: out) } catch {
            print("DUMP-FAILED \(name): write \(error)")
        }
    } else {
        print("DUMP-FAILED \(name): JSON serialization")
    }
}

// MARK: - Fixture (luồng đã ghi)

struct FixtureData {
    var lines: [OCRLine]
    var boxes: [CGRect?]
}

func loadFixture(_ path: String) -> FixtureData {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let rawLines = obj["lines"] as? [[String: Any]] else {
        fail("không đọc được fixture \(path)")
    }
    var lines: [OCRLine] = []
    var boxes: [CGRect?] = []
    for raw in rawLines {
        let text = raw["text"] as? String ?? ""
        let conf = (raw["confidence"] as? NSNumber)?.doubleValue ?? 0.5
        lines.append(OCRLine(text: text, confidence: conf))
        if let b = raw["box"] as? [String: Any] {
            boxes.append(CGRect(
                x: (b["x"] as? NSNumber)?.doubleValue ?? 0,
                y: (b["y"] as? NSNumber)?.doubleValue ?? 0,
                width: (b["w"] as? NSNumber)?.doubleValue ?? 0,
                height: (b["h"] as? NSNumber)?.doubleValue ?? 0))
        } else {
            boxes.append(nil)
        }
    }
    return FixtureData(lines: lines, boxes: boxes)
}

// MARK: - Bẫy đột biến (mỗi id = một process riêng phía CI)
//
// Căn cứ thiết kế: hai điểm Double->Int DUY NHẤT trong
// Parser.swift mà dữ liệu OCR chạm tới được (điều tra tĩnh
// HARNESS-REPRO, grep Int( toàn file):
//   (A) Parser.swift:1999 columnModel — Int((maxX/0.01).rounded())
//       trên cạnh phải hộp của dòng CÓ TIỀN; maxX NaN/inf/>=9.2e16
//       -> TRAP. Luồng ghi: mọi maxX hữu hạn [0.42, 0.60] nên
//       không bao giờ kích hoạt ở đó.
//   (B) Parser.swift:1223 extractSamelineItems — Int(lb * unit)
//       trên dòng cân; lb từ regex số KHÔNG chặn chữ số ->
//       Double khổng lồ/inf -> TRAP. Điều kiện tới được: dòng
//       chứa "/lb" hoặc "/1b", lb KHÔNG đứng đầu dòng (đầu dòng
//       là số dài thì nhánh khối UPC nuốt trước), có đơn giá.
// Cộng các họ trong brief: kéo dài token số, trigger ở dòng
// cuối, hộp suy biến, nhân đôi dòng, token tiền lạ, cấu trúc.

func extendDigitRuns(_ text: String, toLength n: Int) -> String {
    guard let re = try? NSRegularExpression(pattern: #"\d+"#) else { return text }
    var out = text
    let matches = re.matches(in: text, options: [],
                             range: NSRange(text.startIndex..., in: text)).reversed()
    for m in matches {
        guard let r = Range(m.range, in: out) else { continue }
        let run = String(out[r])
        if run.count < n {
            out.replaceSubrange(r, with: run + String(repeating: "9", count: n - run.count))
        }
    }
    return out
}

typealias Mutation = (inout [OCRLine], inout [CGRect?]) -> Void

func mutationTable() -> [(id: String, body: Mutation)] {
    var table: [(id: String, body: Mutation)] = []
    func add(_ id: String, _ body: @escaping Mutation) { table.append((id, body)) }
    func insert(_ line: String, at pos: String) -> Mutation {
        { lines, boxes in
            let i = pos == "start" ? 0 : (pos == "end" ? lines.count : lines.count / 2)
            lines.insert(OCRLine(text: line, confidence: 0.9), at: i)
            boxes.insert(CGRect(x: 0.30, y: 0.50, width: 0.28, height: 0.015), at: i)
        }
    }
    func appendLine(_ line: String) -> Mutation {
        { lines, boxes in
            lines.append(OCRLine(text: line, confidence: 0.9))
            boxes.append(CGRect(x: 0.30, y: 0.03, width: 0.28, height: 0.015))
        }
    }

    add("base") { _, _ in }
    add("base-nobox") { _, boxes in boxes = boxes.map { _ in nil } }

    // (a) kéo dài token số
    for n in [13, 16, 19] {
        add("digits\(n)-all") { lines, _ in
            for i in lines.indices { lines[i].text = extendDigitRuns(lines[i].text, toLength: n) }
        }
    }
    add("digits25-longest") { lines, _ in
        // chỉ dãy số dài nhất (mã vạch 23 số của L-R01) -> 25 số
        var best: (line: Int, len: Int) = (0, 0)
        for (i, l) in lines.enumerated() {
            for run in l.text.split(whereSeparator: { !$0.isNumber }) where run.count > best.len {
                best = (i, run.count)
            }
        }
        if best.line < lines.count {
            lines[best.line].text = extendDigitRuns(lines[best.line].text, toLength: 25)
        }
    }

    // (b) dòng cân — họ (B): lb khổng lồ đứng SAU nhãn chữ
    add("weight-ok-mid", insert("CRAWFISH 1.69 lb @ $2.99/lb", at: "mid"))
    add("weight-tjohnnys-mid", insert("LIVE CRAWFISH 43 lb @ $3.99/lb", at: "mid"))
    add("weight-huge-mid", insert("CRAWFISH 99999999999999999999 lb @ $3.99/lb", at: "mid"))
    add("weight-huge-start", insert("CRAWFISH 99999999999999999999 lb @ $3.99/lb", at: "start"))
    add("weight-barcode-lb-mid", insert("CRAWFISH 21120720301342609141417 lb @ $3.99/lb", at: "mid"))
    add("weight-inf-mid", insert("CRAWFISH " + String(repeating: "9", count: 400) + " lb @ $3.99/lb", at: "mid"))

    // (c) trigger ở DÒNG CUỐI (săn index+1 thiếu chặn)
    add("last-baremoney", appendLine("125.48"))
    add("last-subtotal-label", appendLine("SUBTOTAL"))
    add("last-itemcount-label", appendLine("ITEM COUNT:"))
    add("last-money-then-total") { lines, boxes in
        lines.append(OCRLine(text: "134.86", confidence: 0.9))
        boxes.append(CGRect(x: 0.30, y: 0.03, width: 0.28, height: 0.015))
        lines.append(OCRLine(text: "TOTAL", confidence: 0.9))
        boxes.append(CGRect(x: 0.30, y: 0.02, width: 0.28, height: 0.015))
    }
    add("last-date", appendLine("09/14/2026"))
    add("last-instsv", appendLine("INST SV 4.50-"))

    // (d) hộp suy biến — họ (A): dòng 28 của fixture là "125.48"
    // (dòng tiền trần) — columnModel chỉ quét dòng CÓ TIỀN.
    add("box-nan-maxx-moneyline") { _, boxes in
        if boxes.count > 28 { boxes[28] = CGRect(x: CGFloat.nan, y: 0.47, width: 0.05, height: 0.013) }
    }
    add("box-inf-maxx-moneyline") { _, boxes in
        if boxes.count > 28 { boxes[28] = CGRect(x: 0.52, y: 0.47, width: .infinity, height: 0.013) }
    }
    add("box-huge-maxx-moneyline") { _, boxes in
        if boxes.count > 28 { boxes[28] = CGRect(x: 0, y: 0.47, width: 1e17, height: 0.013) }
    }
    add("box-nan-firstline") { _, boxes in
        if !boxes.isEmpty { boxes[0] = CGRect(x: CGFloat.nan, y: .nan, width: .nan, height: .nan) }
    }
    add("box-nan-everywhere") { _, boxes in
        boxes = boxes.map { _ in CGRect(x: CGFloat.nan, y: .nan, width: .nan, height: .nan) }
    }
    add("box-all-identical") { _, boxes in
        boxes = boxes.map { _ in CGRect(x: 0.3, y: 0.5, width: 0.28, height: 0.015) }
    }
    add("box-all-zero") { _, boxes in
        boxes = boxes.map { _ in CGRect.zero }
    }
    add("box-negative") { _, boxes in
        boxes = boxes.map { _ in CGRect(x: -0.5, y: -0.5, width: 0.28, height: 0.015) }
    }
    add("box-short") { _, boxes in
        if boxes.count > 10 { boxes = Array(boxes.prefix(10)) }
    }

    // (e) nhân đôi dòng
    add("dup2") { lines, boxes in
        var l2: [OCRLine] = []; var b2: [CGRect?] = []
        for i in lines.indices { l2.append(lines[i]); l2.append(lines[i]); b2.append(boxes[i]); b2.append(boxes[i]) }
        lines = l2; boxes = b2
    }
    add("dup3") { lines, boxes in
        var l2: [OCRLine] = []; var b2: [CGRect?] = []
        for i in lines.indices { for _ in 0..<3 { l2.append(lines[i]); b2.append(boxes[i]) } }
        lines = l2; boxes = b2
    }

    // (f) token tiền lạ
    add("money-thousands") { lines, _ in
        if lines.count > 28 { lines[28].text = "1,234,567.89" }
    }
    add("money-thousands-total", appendLine("TOTAL 1,234,567.89"))
    add("money-dot99", appendLine("TOTAL .99"))
    add("money-99dot", appendLine("TOTAL 99."))
    add("money-comma-decimal", appendLine("TOTAL $2,79"))
    add("money-baht-tax", appendLine("TAX 1 8.517% ฿9.60"))

    // (g) cấu trúc cực đoan
    add("merge-all") { lines, boxes in
        let joined = lines.map { $0.text }.joined(separator: " ")
        lines = [OCRLine(text: joined, confidence: 0.9)]
        boxes = [CGRect(x: 0.3, y: 0.5, width: 0.3, height: 0.9)]
    }
    add("charbomb-5000") { lines, boxes in
        lines = [OCRLine(text: String(repeating: "9", count: 5000) + " TOTAL 134.86", confidence: 0.9)]
        boxes = [CGRect(x: 0.3, y: 0.5, width: 0.3, height: 0.015)]
    }
    add("token-500-letters") { lines, boxes in
        lines = [OCRLine(text: String(repeating: "A", count: 500) + " 12.34", confidence: 0.9)]
        boxes = [CGRect(x: 0.3, y: 0.5, width: 0.3, height: 0.015)]
    }
    add("empty") { lines, boxes in lines = []; boxes = [] }
    add("single-baremoney") { lines, boxes in
        lines = [OCRLine(text: "125.48", confidence: 0.9)]
        boxes = [CGRect(x: 0.5, y: 0.5, width: 0.05, height: 0.013)]
    }
    return table
}

// MARK: - Điều phối chế độ

// MARK: - ocrprobe: dụng cụ đo đọc thử (Layer-2, 2026-11-20)

/// Phóng ảnh bằng nội suy chất lượng cao (cùng phép của
/// cropForROI trong ReadPipeline, viết lại tại chỗ cho driver).
func probeUpscale(_ image: CGImage, factor: Double) -> CGImage {
    guard factor > 1.05 else { return image }
    let outW = Int((Double(image.width) * factor).rounded())
    let outH = Int((Double(image.height) * factor).rounded())
    guard let ctx = CGContext(
        data: nil, width: outW, height: outH,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return image }
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: outW, height: outH))
    return ctx.makeImage() ?? image
}

/// Tăng tương phản cho một crop (bản driver của biến thể
/// enhancedContrast: bỏ màu + nâng tương phản) — CoreImage.
func probeContrast(_ image: CGImage) -> CGImage {
    let ci = CIImage(cgImage: image)
    guard let filter = CIFilter(name: "CIColorControls") else { return image }
    filter.setValue(ci, forKey: kCIInputImageKey)
    filter.setValue(0.0, forKey: kCIInputSaturationKey)
    filter.setValue(1.3, forKey: kCIInputContrastKey)
    guard let out = filter.outputImage else { return image }
    let ctx = CIContext(options: nil)
    return ctx.createCGImage(out, from: out.extent) ?? image
}

/// Đọc một ảnh bằng một engine, nuốt lỗi thành [] (đo, không cổng).
func probeRecognize(_ engine: ClassicTextEngine, _ image: CGImage) -> [Fragment] {
    (try? engine.recognize(in: image, region: nil)) ?? []
}

/// Chia ảnh thành n dải ngang chồng lấn, đọc từng dải, ghép
/// mảnh về toạ độ chuẩn hoá TOÀN KHUNG (gốc dưới-trái như
/// Vision). overlapFrac tính theo chiều cao một dải; upscale
/// áp lên từng crop trước khi đọc; contrast tăng tương phản
/// từng crop trước khi đọc.
func probeTiles(_ image: CGImage, bands n: Int, overlapFrac: Double,
                upscale: Double, contrast: Bool,
                engine: ClassicTextEngine) -> [Fragment] {
    let W = image.width, H = image.height
    guard n >= 1, W >= 2, H >= 2 else { return [] }
    let tileH = Double(H) / Double(n)
    var out: [Fragment] = []
    var nextID = 0
    for i in 0..<n {
        let grow = tileH * overlapFrac
        let yTop = max(0.0, Double(i) * tileH - (i > 0 ? grow : 0))
        let yBot = min(Double(H), Double(i + 1) * tileH + (i < n - 1 ? grow : 0))
        let rect = CGRect(x: 0, y: yTop, width: Double(W),
                          height: yBot - yTop).integral
        guard rect.height >= 2, var crop = image.cropping(to: rect)
        else { continue }
        if contrast { crop = probeContrast(crop) }
        if upscale > 1.05 { crop = probeUpscale(crop, factor: upscale) }
        let frags = probeRecognize(engine, crop)
        // Hộp Vision của crop: chuẩn hoá gốc dưới-trái CỦA
        // CROP. Đáy crop trong hệ toàn khung (gốc dưới):
        let cropBottomBL = 1.0 - (Double(rect.maxY) / Double(H))
        let cropHFrac = Double(rect.height) / Double(H)
        for f in frags {
            let b = f.box
            let mapped = CGRect(x: b.minX,
                                y: cropBottomBL + b.minY * cropHFrac,
                                width: b.width,
                                height: b.height * cropHFrac)
            out.append(Fragment(id: nextID, text: f.text,
                                alternates: f.alternates,
                                confidence: f.confidence, box: mapped,
                                passID: "ocrprobe", tileIndex: i,
                                regionID: nil))
            nextID += 1
        }
    }
    return out
}

/// In một dòng kết quả đo: số mảnh + vài chữ đầu làm mẫu.
func probeReport(file: String, strat: String, frags: [Fragment]) {
    let sample = frags.prefix(6).map {
        $0.text.replacingOccurrences(of: "\n", with: " ")
    }.joined(separator: " | ")
    print("OCRPROBE file=\(file) strat=\(strat) frags=\(frags.count) sample=[\(sample)]")
}

/// Ráp dòng + parseV4 trên tập mảnh đã ghép, in kết quả khép sổ.
func probeParse(file: String, strat: String, frags: [Fragment]) {
    let assembly = LineAssembly.assemble(frags)
    let lines = assembly.lines.map {
        OCRLine(text: $0.text, confidence: $0.confidence,
                alternates: $0.alternates)
    }
    let boxes: [CGRect?] = assembly.lines.map { $0.box }
    let parsed = ReceiptParser.parseV4(lines: lines, boxes: boxes)
    print("OCRPROBE-PARSE file=\(file) strat=\(strat) lines=\(assembly.lines.count) "
        + "dedupeDropped=\(assembly.dedupeDropped) \(parseSummary(parsed)) "
        + "arb=\(parsed.arbiterStatus ?? "nil")")
}

let mode = args.first ?? "probe"

switch mode {
case "probe":
    let supported = (try? VNRecognizeTextRequest.supportedRecognitionLanguages(
        for: .accurate, revision: VNRecognizeTextRequestRevision3)) ?? []
    print("supported(rev3, accurate) = \(supported)")
    print("vendors dataVersion = \(VendorData.shared.dataVersion)")
    print("lexicon version = \(DomainCorrector.lexiconVersion)")
    print("SURVIVED probe")

case "unittests":
    // G1 (cổng kiểm chứng thật): test LOGIC THUẦN + VÒNG ĐỜI
    // bằng Swift thật — PendingDraftStore (save/load/hỏng/
    // schema lạ/xoá) và ReceiptLogic (canReparse / hasLoadable
    // Original / flags). Bộ test ở UnitTests.swift (cùng thư
    // mục HarnessApp). Không chạm đường đọc nên không cần
    // requireDataLoaded (không phụ thuộc vendors/lexicon).
    // In từng dòng UNITTEST PASS/FAIL + UNITTESTS-DONE; có
    // FAIL -> thoát 1 để bước CI đỏ. Khép bằng SURVIVED như
    // mọi chế độ khác.
    let results = HarnessUnitTests.runAll()
    var failedCount = 0
    for line in results {
        print(line)
        if line.hasPrefix("UNITTEST FAIL") { failedCount += 1 }
    }
    print("UNITTESTS-DONE total=\(results.count) failed=\(failedCount)")
    if failedCount > 0 { exit(1) }
    print("SURVIVED unittests")

case "fixture":
    guard args.count >= 2 else { fail("fixture cần đường dẫn file") }
    print("[fixture] start path=\(args[1])")
    requireDataLoaded()
    print("[fixture] data-loaded")
    let fx = loadFixture(args[1])
    let boxes: [CGRect?]? = hasFlag("--nobox") ? nil : fx.boxes
    print("fixture lines=\(fx.lines.count) boxes=\(boxes != nil ? "yes" : "nil")")
    print("[fixture] parsing")
    let parsed = ReceiptParser.parse(lines: fx.lines, boxes: boxes)
    print("[fixture] parsed")
    print(parseSummary(parsed))
    print("SURVIVED fixture")

case "parseonly":
    // Process CON cho bisect: parse đúng một lựa chọn dòng của
    // fixture rồi thoát. Chết vì signal = lựa chọn đó gây chết.
    //   --keep i,j,k   chỉ giữ các dòng theo chỉ số 0-based
    //   --count k      giữ k dòng đầu
    //   --text "..."   parse đúng một dòng chữ thô này (hộp lấy
    //                  từ dòng 8 của fixture — hộp của ca chết)
    guard args.count >= 2 else { fail("parseonly cần đường dẫn file") }
    requireDataLoaded()
    let fx = loadFixture(args[1])
    if let t = argValue("--text") {
        let box: CGRect? = fx.boxes.indices.contains(8) ? fx.boxes[8] : nil
        print("[parseonly] rawtext=\(t)")
        _ = ReceiptParser.parse(lines: [OCRLine(text: t, confidence: 1.0)],
                                boxes: [box])
        print("SURVIVED parseonly")
        exit(0)
    }
    var idx = Array(fx.lines.indices)
    if let keep = argValue("--keep") {
        idx = keep.split(separator: ",").compactMap { Int($0) }
            .filter { fx.lines.indices.contains($0) }
    } else if let c = argValue("--count"), let k = Int(c) {
        idx = Array(fx.lines.indices.prefix(max(0, k)))
    }
    let lines = idx.map { fx.lines[$0] }
    let boxes = idx.map { fx.boxes[$0] }
    print("[parseonly] lines=\(lines.count) idx=\(idx.map(String.init).joined(separator: ","))")
    _ = ReceiptParser.parse(lines: lines, boxes: boxes)
    print("SURVIVED parseonly")

case "streamone":
    // Process con của "streams": parse đúng một file luồng (mỗi
    // dòng = một OCRLine, confidence = recoveredLineConfidence
    // như đường reparse) rồi in STREAM-RESULT. Chết vì signal =
    // ca đó gây chết — cha ghi STREAM-DIED thay cho kết quả.
    // Thuế in TỪNG DÒNG để bàn chấm Ledger Gate theo SCORECARD.
    guard args.count >= 2 else { fail("streamone cần đường dẫn file") }
    requireDataLoaded()
    guard let raw = try? String(contentsOfFile: args[1], encoding: .utf8) else {
        fail("streamone: không đọc được \(args[1])")
    }
    let streamLines = raw.split(separator: "\n")
        .map { OCRLine(text: String($0), confidence: ReceiptParser.recoveredLineConfidence) }
    // V4-1: --core v4 chạy parseV4 (ứng viên + trọng tài khối
    // tổng, DESIGN-V4 §8: công tắc chỉ ở harness/bench) và in
    // STREAM4-RESULT = STREAM-RESULT + prov= (số trường khối
    // tổng có provenance: subtotal/tax[i]/total) + arb=
    // (trạng thái trọng tài). Không tham số = v3 như cũ.
    let useV4 = argValue("--core") == "v4"
    let parsed = useV4 ? ReceiptParser.parseV4(lines: streamLines)
                       : ReceiptParser.parse(lines: streamLines)
    let taxList = parsed.taxes.map { String($0.amountCents) }.joined(separator: ",")
    let qtySum = parsed.items.reduce(0) { $0 + $1.qty }
    let qtyPos = parsed.items.filter { ($0.amountCents ?? 0) > 0 }.reduce(0) { $0 + $1.qty }
    if useV4 {
        let provCount = parsed.totalsProvenance.keys.filter {
            $0 == "subtotal" || $0 == "total" || $0.hasPrefix("tax[")
        }.count
        print("STREAM4-RESULT file=\((args[1] as NSString).lastPathComponent) \(parseSummary(parsed)) taxes=[\(taxList)] qty=\(qtySum) qtyPos=\(qtyPos) prov=\(provCount) arb=\(parsed.arbiterStatus ?? "nil")")
    } else {
        print("STREAM-RESULT file=\((args[1] as NSString).lastPathComponent) \(parseSummary(parsed)) taxes=[\(taxList)] qty=\(qtySum) qtyPos=\(qtyPos)")
    }
    print("SURVIVED streamone")

case "streams":
    // CỔNG LUỒNG (V4-0, DESIGN-V4 §7): chạy parser HIỆN HÀNH
    // trên mọi luồng .txt trong --dir. Mỗi ca ở process con
    // riêng (mẫu của bisect): một ca chết không kéo cả cổng,
    // và cái chết được ghi đích danh. Cổng hoàn thành khi in
    // STREAMS-DONE — ca chết/tệ là DỮ LIỆU ĐO của đường cơ
    // sở, không phải lỗi vận hành của cổng.
    guard let dir = argValue("--dir") else { fail("streams cần --dir") }
    requireDataLoaded()
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else {
        fail("streams: không đọc được thư mục \(dir)")
    }
    let files = names.filter { $0.hasSuffix(".txt") }.sorted()
    print("[streams] dir=\(dir) files=\(files.count)")
    let selfPath = CommandLine.arguments[0]
    var died = 0
    var died4 = 0
    for name in files {
        let path = (dir as NSString).appendingPathComponent(name)
        // Chạy process con streamone một lượt; extra = tham số
        // lõi (rỗng = v3, ["--core","v4"] = v4). Ngữ nghĩa chết/
        // ghi chú giữ nguyên của cổng V4-0.
        func runChildOnce(_ extra: [String]) -> (ok: Bool, note: String, out: String) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: selfPath)
            p.arguments = ["streamone", path] + extra
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice
            var out = ""
            var spawnOK = true
            do { try p.run() } catch { spawnOK = false }
            if spawnOK {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                out = String(data: data, encoding: .utf8) ?? ""
            }
            let ok = spawnOK && p.terminationReason == .exit && p.terminationStatus == 0
            let note = !spawnOK ? "spawn-failed"
                : (p.terminationReason == .exit ? "exit \(p.terminationStatus)" : "signal \(p.terminationStatus)")
            return (ok, note, out)
        }
        let r3 = runChildOnce([])
        if r3.ok, let line = r3.out.split(separator: "\n").first(where: { $0.hasPrefix("STREAM-RESULT") }) {
            print(line)
        } else {
            died += 1
            print("STREAM-DIED file=\(name) (\(r3.note))")
        }
        // V4-1: lượt v4 trên cùng file — con chết ghi STREAM4-DIED
        // đích danh, cổng chốt bằng STREAMS4-DONE riêng để số
        // V4-0 (STREAMS-DONE) giữ nguyên ý nghĩa đối chứng.
        let r4 = runChildOnce(["--core", "v4"])
        if r4.ok, let line = r4.out.split(separator: "\n").first(where: { $0.hasPrefix("STREAM4-RESULT") }) {
            print(line)
        } else {
            died4 += 1
            print("STREAM4-DIED file=\(name) (\(r4.note))")
        }
    }
    print("STREAMS-DONE total=\(files.count) died=\(died)")
    print("STREAMS4-DONE total=\(files.count) died=\(died4)")

case "bisect":
    // Truy vết cái chết trong parse TRÊN CHÍNH luồng fixture:
    // mỗi lựa chọn dòng chạy trong process con riêng (chết vì
    // signal không kéo theo cha). Pha A: tiền tố tăng dần —
    // tiền tố chết đầu tiên khoanh đoạn cuối. Pha B: tham lam
    // bỏ từng dòng mà vẫn chết -> tập tối thiểu gây chết.
    guard args.count >= 2 else { fail("bisect cần đường dẫn file") }
    requireDataLoaded()
    let fxPath = args[1]
    let fx = loadFixture(fxPath)
    let n = fx.lines.count
    let selfPath = CommandLine.arguments[0]
    func runChild(_ keep: [Int]) -> (ok: Bool, note: String) {
        // ok = con sống (in SURVIVED); note ghi cách con kết thúc
        // (exit code hay signal) để log nói rõ cách chết.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: selfPath)
        p.arguments = ["parseonly", fxPath, "--keep",
                       keep.map(String.init).joined(separator: ",")]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return (false, "spawn-failed") }
        p.waitUntilExit()
        let ok = p.terminationReason == .exit && p.terminationStatus == 0
        let note = p.terminationReason == .exit
            ? "exit \(p.terminationStatus)" : "signal \(p.terminationStatus)"
        return (ok, note)
    }
    print("[bisect] total lines=\(n)")
    var fatalPrefix = -1
    for k in 1...n {
        let r = runChild(Array(0..<k))
        print("[bisect] prefix k=\(k) -> \(r.ok ? "ok" : "DIED (\(r.note))")")
        let ok = r.ok
        if !ok { fatalPrefix = k; break }
    }
    guard fatalPrefix > 0 else {
        print("BISECT-DONE no-death-on-any-prefix")
        exit(0)
    }
    var current = Array(0..<fatalPrefix)
    var improved = true
    var guardRounds = 0
    while improved && guardRounds < 12 {
        improved = false
        guardRounds += 1
        for i in current.reversed() {
            let trial = current.filter { $0 != i }
            if trial.isEmpty { continue }
            if !runChild(trial).ok {
                print("[bisect] drop line \(i) -> still DIED (kept dropped)")
                current = trial
                improved = true
            }
        }
    }
    print("[bisect] minimal idx=\(current.map(String.init).joined(separator: ","))")
    for i in current {
        print("[bisect] line \(i): \(fx.lines[i].text)")
    }
    print("BISECT-DONE fatalPrefix=\(fatalPrefix) minimalCount=\(current.count)")

case "variants":
    // Chẻ nhỏ dòng gây chết (run #16: trap trong
    // extractSamelineItems trên dòng 8 của L-R01) — mỗi biến
    // thể chạy trong process con riêng qua parseonly --text;
    // biến thể nào chết/sống sẽ chỉ ra đặc điểm kích hoạt.
    guard args.count >= 2 else { fail("variants cần đường dẫn fixture") }
    requireDataLoaded()
    let fxPath = args[1]
    let variants: [String] = [
        "3006152 BOUNCE 400 11.49 A",   // V1 nguyên văn dòng 8
        "BOUNCE 400 11.49 A",           // V2 bỏ mã đầu dòng
        "3006152 BOUNCE 11.49 A",       // V3 bỏ "400"
        "3006152 BOUNCE 400 11.49",     // V4 bỏ cờ đuôi "A"
        "3006152 BOUNCE 400 A",         // V5 bỏ tiền
        "BOUNCE 11.49 A",               // V6 tối thiểu tiền + cờ
        "BOUNCE 11.49",                 // V7 tiền, không cờ
        "1234567 XXXXX 999 22.50 B",    // V8 cùng dạng, số khác
        "ABCDEFG BOUNCE 400 11.49 A",   // V9 chữ thay mã số
        "3006152 BOUNCE 400 11.49 AF",  // V10 cờ đuôi 2 chữ
    ]
    let selfPath = CommandLine.arguments[0]
    for (i, v) in variants.enumerated() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: selfPath)
        p.arguments = ["parseonly", fxPath, "--text", v]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        var note = "spawn-failed"
        var ok = false
        if (try? p.run()) != nil {
            p.waitUntilExit()
            ok = p.terminationReason == .exit && p.terminationStatus == 0
            note = p.terminationReason == .exit
                ? "exit \(p.terminationStatus)" : "signal \(p.terminationStatus)"
        }
        print("[variants] V\(i + 1) \(ok ? "ok" : "DIED (\(note))"): \(v)")
    }
    print("VARIANTS-DONE")

case "fuzz":
    guard args.count >= 2 else { fail("fuzz cần đường dẫn fixture") }
    let table = mutationTable()
    if hasFlag("--list") {
        for entry in table { print(entry.id) }
        exit(0)
    }
    guard args.count >= 3 else { fail("fuzz cần id đột biến (xem --list)") }
    requireDataLoaded()
    let id = args[2]
    guard let entry = table.first(where: { $0.id == id }) else {
        fail("không có đột biến \(id)")
    }
    var fx = loadFixture(args[1])
    entry.body(&fx.lines, &fx.boxes)
    print("fuzz \(id): lines=\(fx.lines.count)")
    let parsed = ReceiptParser.parse(lines: fx.lines, boxes: fx.boxes)
    print(parseSummary(parsed))
    print("SURVIVED \(id)")

case "images":
    guard let dirPath = argValue("--dir") else { fail("images cần --dir") }
    requireDataLoaded()
    applyEngineConfig()
    let sets = Int(argValue("--sets") ?? "1") ?? 1
    let dir = URL(fileURLWithPath: dirPath)
    let files = (try? FileManager.default.contentsOfDirectory(
        at: dir, includingPropertiesForKeys: nil)) ?? []
    let jpgs = files.filter { $0.pathExtension.lowercased() == "jpg" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    if jpgs.isEmpty { fail("không có .jpg trong \(dirPath)") }
    var dumpDir: URL? = nil
    if let d = argValue("--dump") {
        dumpDir = URL(fileURLWithPath: d)
        try? FileManager.default.createDirectory(at: dumpDir!,
                                                 withIntermediateDirectories: true)
    }
    let engine = ClassicTextEngine()
    print("manifest: family=\(engine.manifest.family) rev=\(engine.manifest.revision) "
        + "langs=\(engine.manifest.languagesEffective) topk=\(ClassicTextEngine.topCandidates)")
    for set in 1...sets {
        var okCount = 0
        for url in jpgs {
            guard let cg = loadCGImage(url) else {
                print("SET \(set) \(url.lastPathComponent): LOAD-FAILED")
                continue
            }
            // G5: ReceiptReader.read không ném lỗi (fail-closed
            // như app) — "sống" ở đây = tiến trình không chết +
            // outcome trở về; ca đọc rỗng tự lộ qua parseSummary.
            let run = runImage(cg)
            print("SET \(set) \(url.lastPathComponent): frag[\(boxCensus(run.fragBoxes))] "
                + "asm[\(boxCensus(run.asmBoxes))] "
                + "\(parseSummary(run.parsed)) e1=\(run.e1) e2=\(run.e2) score=\(String(format: "%.1f", run.score))"
                + " roi=\(run.outcome.diagnostics.roiRounds.count) arb=\(run.parsed.arbiterStatus ?? "nil")")
            if let dumpDir, set == 1 {
                dumpImageRun(name: url.lastPathComponent, run: run, dir: dumpDir)
            }
            // A5 (vòng 2, CHỈ CÔNG CỤ): truy vết nguồn gốc thuế cho
            // các ca có lỗi ghi sổ — in dòng đã ráp + họ nhãn, dòng
            // thuế cuối + chỉ số dòng nguồn, vết chọn và provenance.
            // Chỉ IN; không đổi phán quyết nào của cổng.
            if set == 1, traceCaseNames.contains(url.lastPathComponent) {
                printCaseTrace(name: url.lastPathComponent, run: run)
                printAxisTrace(name: url.lastPathComponent, run: run)
            }
            // Vòng 3 Phần 1 (CHỈ ĐO): mọi ca, lượt 1 — nguồn nhận của
            // từng dòng thuế cuối (nhãn TAX / TAXSUM / % in / ước tính /
            // CHỈ VỊ TRÍ). Không đổi phán quyết nào.
            if set == 1 {
                printTaxSourceLine(name: url.lastPathComponent, run: run)
            }
            okCount += 1
        }
        print("SET \(set) DONE \(okCount)/\(jpgs.count)")
        if okCount != jpgs.count { fail("set \(set) thiếu ảnh", code: 4) }
    }
    print("SURVIVED images x\(sets)")

case "roigate":
    // CỔNG ẢNH–ROI (G5): hai làn trên cùng một ảnh — làn CŨ
    // (thân images trước G5: một lượt engine -> ráp -> parse
    // v3, không ứng viên phụ, không alternates, không ROI) và
    // làn APP (ReceiptReader.read trọn đường). GT nạp để biết
    // ca nào là ca hạt giống/F2, nhưng THƯỚC CHẤM của cổng này
    // là khép sổ nội tại (E1/E2 + thâm hụt xu) của từng làn —
    // cùng thước evaluate() của chế độ images.
    guard let dirPath = argValue("--dir") else { fail("roigate cần --dir") }
    guard let gtPath = argValue("--gt") else { fail("roigate cần --gt") }
    requireDataLoaded()
    applyEngineConfig()
    guard let gtData = try? Data(contentsOf: URL(fileURLWithPath: gtPath)),
          let gtObj = try? JSONSerialization.jsonObject(with: gtData) as? [String: Any],
          let gtCases = gtObj["cases"] as? [String: Any] else {
        fail("roigate: không đọc được bảng GT \(gtPath)")
    }
    // Tập F2 đóng băng (mất chữ số ở tầng vật lý trên luồng
    // DEVICE — G2/TEAM4): họ 003 (C-003 + SYN-003 suy biến),
    // L-R05 (patty mất chữ số đầu), L-R08 (thuế 13.23 -> 1.23),
    // L-R09 (tạm tính mất chữ số đầu). Đóng băng theo TÊN FILE.
    let roiF2Files: Set<String> = [
        "C-003.jpg", "L-R05.jpg", "L-R08.jpg", "L-R09.jpg",
        "SYN-003-BLUR.jpg", "SYN-003-DOWNSCALE.jpg",
        "SYN-003-LIGHT.jpg", "SYN-003-NOISE.jpg",
        "SYN-003-TILT.jpg", "SYN-003-WRINKLE.jpg",
    ]
    let dir = URL(fileURLWithPath: dirPath)
    let files = (try? FileManager.default.contentsOfDirectory(
        at: dir, includingPropertiesForKeys: nil)) ?? []
    let jpgs = files.filter { $0.pathExtension.lowercased() == "jpg" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    if jpgs.isEmpty { fail("không có .jpg trong \(dirPath)") }
    let legacyEngine = ClassicTextEngine()
    // A9 / FL-314 (sửa THƯỚC, không sửa app): mỗi làn đọc ít nhất
    // 2 lượt (--passes N, tối thiểu 2) và CHẤM LƯỢT TỆ NHẤT của làn
    // đó — một lượt đọc may mắn của làn nào cũng không còn quyết
    // định deltaOK.
    let passes = max(2, Int(argValue("--passes") ?? "") ?? 2)
    print("[roigate] passes=\(passes) (chấm lượt tệ nhất mỗi làn)")
    var deficitCases = 0
    var roiAssertFailures = 0
    var regressions = 0
    var f2Rescued = 0
    // Thước một làn: (số đẳng thức khép 0..2, thâm hụt xu).
    // Thâm hụt = |Σmón - tạm tính| + |tạm tính + thuế - tổng|;
    // thiếu neo nào thì cộng phạt cố định 100_000 cho hạng tử
    // đó (ca tổng-only thiếu cả hai neo ở CẢ hai làn như nhau).
    func laneMetric(_ p: ParseResult, _ assembly: AssemblyResult)
        -> (closed: Int, deficit: Int) {
        let ev = evaluate(parsed: p, assembly: assembly)
        var deficit = 0
        let sumItems = SafeMoney.sumCents(p.items.map { $0.amountCents ?? 0 })
        if let subtotal = p.subtotalCents, let sum = sumItems {
            deficit += abs(sum - subtotal)
        } else { deficit += 100_000 }
        if let subtotal = p.subtotalCents, let total = p.totalCents {
            deficit += abs(subtotal + p.taxTotalCents - total)
        } else { deficit += 100_000 }
        return ((ev.e1 ? 1 : 0) + (ev.e2 ? 1 : 0), deficit)
    }
    // A9 / FL-316: tờ KHÔNG in tạm tính (GT subtotal = null) — thước
    // thâm hụt ở trên cộng phạt phẳng 200_000 cho làn đọc ĐÚNG là
    // "không có tạm tính", trong khi làn bịa ra tạm tính lại được
    // điểm tốt hơn. Ca loại này chấm bằng SO TỪNG TRƯỜNG với GT:
    // tạm tính (phải nil), tổng, danh sách thuế — số trường đúng.
    //
    // SỬA A9 (vòng 2, lượt 2): bản đầu cộng điểm "tạm tính = nil" và
    // "thuế = []" cho CẢ làn không đọc được gì — làn đọc rỗng (thâm hụt
    // 200_000, không thấy cả tổng) thắng làn đọc ĐÚNG tổng (6 ca đỏ giả
    // ở lượt chạy 45133478103: 09-safeway, 24-hy-vee-gas, 25-exxon,
    // 37-cvs-3, WR-shell, WR-walgreens — số của app y hệt nền v3). Điểm
    // "vắng mặt" chỉ có nghĩa khi làn đã đọc ra tờ: tổng phải khớp GT
    // trước, rồi mới chấm tạm tính vắng + danh sách thuế.
    func fieldScore(_ p: ParseResult, gt: [String: Any]) -> Int {
        let totalOK: Bool
        if let t = gt["total"] as? Int { totalOK = p.totalCents == t }
        else { totalOK = gt["total"] is NSNull && p.totalCents == nil }
        guard totalOK else { return 0 }
        var score = 1
        if p.subtotalCents == nil { score += 1 }
        let gtTaxes = ((gt["taxes"] as? [Int]) ?? []).sorted()
        if p.taxes.map({ $0.amountCents }).sorted() == gtTaxes { score += 1 }
        return score
    }
    // Lượt tệ nhất: ít đẳng thức khép nhất, rồi thâm hụt lớn nhất.
    func worst(_ a: (closed: Int, deficit: Int), _ b: (closed: Int, deficit: Int))
        -> Bool {
        a.closed < b.closed || (a.closed == b.closed && a.deficit > b.deficit)
    }
    for url in jpgs {
        let name = url.lastPathComponent
        guard let cg = loadCGImage(url) else {
            print("ROIGATE-CASE file=\(name) LOAD-FAILED")
            regressions += 1
            continue
        }
        // Làn CŨ: đúng thân runImage trước G5 — chạy `passes` lượt,
        // giữ lượt TỆ NHẤT.
        var legacy: (closed: Int, deficit: Int)? = nil
        var legacyField = Int.max
        for _ in 0..<passes {
            var legacyParsed = ParseResult()
            var legacyAssembly = AssemblyResult(lines: [], dedupeDropped: [],
                                                invariantViolations: 0)
            if let frags = try? legacyEngine.recognize(in: cg, region: nil) {
                legacyAssembly = LineAssembly.assemble(frags)
                let lines = legacyAssembly.lines.map {
                    OCRLine(text: $0.text, confidence: $0.confidence)
                }
                let boxes: [CGRect?] = legacyAssembly.lines.map { $0.box }
                legacyParsed = ReceiptParser.parse(lines: lines, boxes: boxes)
            }
            let m = laneMetric(legacyParsed, legacyAssembly)
            if legacy == nil || worst(m, legacy!) { legacy = m }
            if let gt = gtCases[name] as? [String: Any] {
                legacyField = min(legacyField, fieldScore(legacyParsed, gt: gt))
            }
        }
        // Làn APP: trọn đường ReceiptReader — `passes` lượt, giữ lượt
        // TỆ NHẤT (kèm số vòng ROI của chính lượt đó).
        var appMetric: (closed: Int, deficit: Int)? = nil
        var appField = Int.max
        var roiRounds = 0
        for _ in 0..<passes {
            let app = runImage(cg)
            let m = laneMetric(app.parsed, app.assembly)
            if appMetric == nil || worst(m, appMetric!) {
                appMetric = m
                roiRounds = app.outcome.diagnostics.roiRounds.count
            }
            if let gt = gtCases[name] as? [String: Any] {
                appField = min(appField, fieldScore(app.parsed, gt: gt))
            }
        }
        let legacyW = legacy!, appW = appMetric!
        let isF2 = roiF2Files.contains(name)
        let hasGT = gtCases[name] != nil
        let gtNoSubtotal = (gtCases[name] as? [String: Any])?["subtotal"] is NSNull
        var deltaOK = true
        if gtNoSubtotal {
            // FL-316: chấm theo từng trường với GT (lượt tệ nhất).
            if appField < legacyField {
                deltaOK = false
                regressions += 1
            }
        } else if appW.closed < legacyW.closed
            || (appW.closed == legacyW.closed
                && appW.deficit > legacyW.deficit) {
            deltaOK = false
            regressions += 1
        }
        var roiAssert = "na"
        if legacyW.closed < 2 {
            deficitCases += 1
            if appW.closed == 2 {
                roiAssert = "rescued"
                if isF2 { f2Rescued += 1 }
            } else if roiRounds > 0 {
                roiAssert = "roi-ran"
            } else {
                roiAssert = "ROI-MISSING"
                roiAssertFailures += 1
            }
        }
        print("ROIGATE-CASE file=\(name) gt=\(hasGT ? "yes" : "no") f2=\(isF2 ? "yes" : "no") "
            + "legacyClosed=\(legacyW.closed) legacyDeficit=\(legacyW.deficit) "
            + "appClosed=\(appW.closed) appDeficit=\(appW.deficit) "
            + "roiRounds=\(roiRounds) roiAssert=\(roiAssert) deltaOK=\(deltaOK) "
            + "passes=\(passes) scoring=\(gtNoSubtotal ? "fields" : "deficit")"
            + (gtNoSubtotal ? " legacyFields=\(legacyField) appFields=\(appField)" : ""))
    }
    print("ROIGATE-DONE cases=\(jpgs.count) deficitCases=\(deficitCases) "
        + "roiAssertFailures=\(roiAssertFailures) f2Rescued=\(f2Rescued) regressions=\(regressions)")
    if roiAssertFailures > 0 || regressions > 0 || f2Rescued < 1 {
        print("ROIGATE-FAILED roiAssertFailures=\(roiAssertFailures) regressions=\(regressions) f2Rescued=\(f2Rescued)")
        exit(1)
    }
    print("SURVIVED roigate")

case "ocrprobe":
    // PHÉP ĐO LAYER-2 (2026-11-20): ca 02-walmart-2 (và ca
    // anh em 01-walmart-1) — hoá đơn dài trên ảnh nhỏ, đường
    // app chỉ vớt 2 mảnh chữ. Pin này thử các cách đọc cứu
    // trên ĐÚNG engine của app để kết án bằng số mảnh + kết
    // quả khép sổ, trước khi bất kỳ cách nào vào app.
    requireDataLoaded()
    let paths = Array(args.dropFirst())
    if paths.isEmpty { fail("ocrprobe cần ít nhất 1 đường ảnh") }
    let mainEngine = ClassicTextEngine()
    let altEngine = ClassicTextEngine(minimumTextHeight: 0.01)
    for path in paths {
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent
        guard let cg = loadCGImage(url) else {
            print("OCRPROBE file=\(name) LOAD-FAILED")
            continue
        }
        print("OCRPROBE file=\(name) size=\(cg.width)x\(cg.height)")
        probeReport(file: name, strat: "full-main-x1",
                    frags: probeRecognize(mainEngine, cg))
        probeReport(file: name, strat: "full-main-x2",
                    frags: probeRecognize(mainEngine,
                                           probeUpscale(cg, factor: 2)))
        probeReport(file: name, strat: "full-main-x3",
                    frags: probeRecognize(mainEngine,
                                           probeUpscale(cg, factor: 3)))
        probeReport(file: name, strat: "full-alt-x1",
                    frags: probeRecognize(altEngine, cg))
        probeReport(file: name, strat: "full-alt-x2",
                    frags: probeRecognize(altEngine,
                                           probeUpscale(cg, factor: 2)))
        for n in [2, 3, 4, 6] {
            for up in [1.0, 2.0] {
                let frags = probeTiles(cg, bands: n, overlapFrac: 0.12,
                                       upscale: up, contrast: false,
                                       engine: mainEngine)
                let strat = "tiles\(n)-main-x\(Int(up))"
                probeReport(file: name, strat: strat, frags: frags)
                if up == 2.0 || n == 4 {
                    probeParse(file: name, strat: strat, frags: frags)
                }
            }
        }
        let cFrags = probeTiles(cg, bands: 4, overlapFrac: 0.12,
                                upscale: 1.0, contrast: true,
                                engine: mainEngine)
        probeReport(file: name, strat: "tiles4-contrast-x1", frags: cFrags)
        probeParse(file: name, strat: "tiles4-contrast-x1", frags: cFrags)
        let aFrags = probeTiles(cg, bands: 4, overlapFrac: 0.12,
                                upscale: 1.0, contrast: false,
                                engine: altEngine)
        probeReport(file: name, strat: "tiles4-alt-x1", frags: aFrags)
        probeParse(file: name, strat: "tiles4-alt-x1", frags: aFrags)
    }
    print("OCRPROBE-DONE")

default:
    fail("chế độ không rõ: \(mode) — probe|images|roigate|fixture|fuzz|streams|unittests|ocrprobe")
}
