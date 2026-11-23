import Foundation
import CoreGraphics

// MARK: - G1: bộ test logic + vòng đời chạy bằng Swift thật
//
// Chế độ `unittests` của harness (cổng C trong TEAM1-
// VERIFICATION §3, bản macOS theo luật tối ưu chi phí của anh
// 2026-11-15: logic chạy kèm job harness có sẵn; phần giết-app
// thật nằm ở BenchShell tự kiểm trên máy anh — đặc tả ở
// core-expert/G1-BENCH-SELFCHECK-SPEC.md).
//
// Trước G1 toàn project có 0 test target: file test vòng đời
// của P-DRAFT (p-draft/tests/PendingDraftRoundTripTest.swift)
// chưa từng thuộc target nào nên chưa từng chạy. Bộ này là hậu
// duệ của file đó: giữ nguyên các ca vòng đời (đối chiếu lại
// với PendingDraft.swift hiện hành — bản tích hợp KHÔNG còn
// đường ScanDraft/makeDraft ở tầng này nên các ca mã-lạ kiểm ở
// mức DTO toOriginal, là đúng lớp mà PendingDraftStore bảo
// vệ), cộng test cho logic điều kiện thuần vừa tách sang
// ReceiptLogic.swift (khoá L-2026-11-13-17 và L-2026-11-13-20).
//
// KHÔNG dùng XCTest: harness là CLI tool; runAll() trả các
// dòng "UNITTEST PASS/FAIL <tên>" máy-đọc-được, main.swift in
// ra và thoát mã 1 nếu có FAIL — CI grep dòng SURVIVED.

enum HarnessUnitTests {

    static func runAll() -> [String] {
        var lines: [String] = []
        func check(_ name: String, _ ok: Bool) {
            lines.append("UNITTEST \(ok ? "PASS" : "FAIL") \(name)")
        }

        runPendingDraftTests(check)
        runPendingBlockTests(check)
        runReviewEditsTests(check)
        runCanReparseTests(check)
        runHasLoadableOriginalTests(check)
        runFlagsTests(check)
        runApprovalGateTests(check)
        runVariantRescueTests(check)
        runQualityGateTests(check)
        runIntegrityPlannerTests(check)
        runTaxLandingTests(check)
        runOfficialRuleTests(check)
        runRetentionPolicyTests(check)
        runRestorePlannerTests(check)
        runExportKitTests(check)
        runCostcoPDFVendorTests(check)
        runStoreTraitsTests(check)
        runAuditTrailTests(check)
        runReadinessTests(check)
        runReviewConfidenceTests(check)
        return lines
    }

    // MARK: - G2: tầng cứu bằng hồ alternate (DESIGN-V4 §2.6)
    //
    // Các ca tổng hợp chạy qua ĐÚNG đường đọc của app
    // (ReceiptParser.parseV4 trên OCRLine có alternates) —
    // kiểm luật cứu: biến thể chỉ thắng khi làm đẳng thức
    // khép mà giá trị chính không khép được; không alternate
    // thì kết quả y hệt đường cũ; hai bản đọc của cùng một
    // token in không bao giờ cộng vào nhau.

    private static func vline(_ text: String,
                              alts: [String] = []) -> OCRLine {
        OCRLine(text: text, confidence: 0.9,
                alternates: alts.map { AltText(text: $0, confidence: 0.8) })
    }

    private static func runVariantRescueTests(
        _ check: (String, Bool) -> Void) {

        // VT01 — ví dụ §3.9 (ca L-R08): thuế in 1.23, bản đọc
        // thay thế 13.23 → tập thuế {133, 1323} khép duy nhất,
        // dòng thuế thứ hai mang provenance closureVariant.
        let vt01 = ReceiptParser.parseV4(lines: [
            vline("STORE A"),
            vline("SUBTOTAL 155.64"),
            vline("TAX 1.33"),
            vline("TAX 1.23", alts: ["TAX 13.23"]),
            vline("TOTAL 170.20"),
        ])
        check("VT01-status-closed", vt01.arbiterStatus == "closed")
        check("VT01-taxes", vt01.taxes.map { $0.amountCents } == [133, 1323])
        check("VT01-prov", vt01.totalsProvenance["tax[1]"]?.detail == "closureVariant")
        check("VT01-total", vt01.totalCents == 17020)

        // VT02 — cùng tờ, KHÔNG alternate: hồ chính không
        // khép → unclosed, thuế đọc tốt nhất giữ nguyên in.
        let vt02 = ReceiptParser.parseV4(lines: [
            vline("STORE A"),
            vline("SUBTOTAL 155.64"),
            vline("TAX 1.33"),
            vline("TAX 1.23"),
            vline("TOTAL 170.20"),
        ])
        check("VT02-status-unclosed", vt02.arbiterStatus == "unclosed")
        check("VT02-taxes-primary", vt02.taxes.map { $0.amountCents } == [133, 123])

        // VT03 — hồ chính ĐÃ khép: biến thể lạ không được
        // lật kết quả (cứu chỉ chạy khi 0 nghiệm).
        let vt03 = ReceiptParser.parseV4(lines: [
            vline("STORE A"),
            vline("SUBTOTAL 56.75", alts: ["SUBTOTAL 99.99"]),
            vline("TAX 2.28"),
            vline("TOTAL 59.03"),
        ])
        check("VT03-closed-primary", vt03.arbiterStatus == "closed"
              && vt03.subtotalCents == 5675 && vt03.totalCents == 5903)

        // VT04 — hồ biến thể cho HAI nghiệm khác giá trị:
        // mơ hồ ở tầng cứu → từ chối, kết cục chính đứng
        // nguyên (unclosed, thuế tốt nhất = mọi dòng thuế in).
        let vt04 = ReceiptParser.parseV4(lines: [
            vline("STORE A"),
            vline("SUBTOTAL 100.00"),
            vline("TAX 5.00", alts: ["TAX 20.00"]),
            vline("TAX 8.00"),
            vline("TAX 9.00", alts: ["TAX 12.00"]),
            vline("TOTAL 120.00"),
        ])
        check("VT04-ambiguous-rescue-refused",
              vt04.arbiterStatus == "unclosed"
              && vt04.taxes.map { $0.amountCents } == [500, 800, 900])

        // VT05 — mẫu D-18: món gãy "19.9Z", alternate chứa
        // token dính "1280219.97" → biến thể hậu tố 1997 khép
        // E1, provenance closureVariant.
        let vt05 = ReceiptParser.parseV4(lines: [
            vline("ITEM ONE 6.98"),
            vline("HARDWD FLOOR CLEANER 19.9Z",
                  alts: ["HARDWD FLOOR CLEANER 1280219.97"]),
            vline("ITEM THREE 69.96"),
            vline("SUBTOTAL 96.91"),
            vline("SALES TAX 8.25"),
            vline("TOTAL 105.16"),
        ])
        check("VT05-items-closed", vt05.items.count == 3
              && vt05.items[1].amountCents == 1997
              && vt05.arbiterDeficitE1 == 0)
        check("VT05-prov", vt05.itemsProvenance["item[1]"]?.detail == "closureVariant")

        // VT06 — mẫu L-R05: biến thể khá hơn nhưng KHÔNG khép
        // E1 → bị từ chối, số in đứng nguyên.
        let vt06 = ReceiptParser.parseV4(lines: [
            vline("ITEM A 2.19"),
            vline("PATTY 0.29", alts: ["PATTY 6.29"]),
            vline("ITEM B 9.19"),
            vline("SUBTOTAL 20.00"),
            vline("TAX 0.50"),
            vline("TOTAL 20.50"),
        ])
        check("VT06-variant-refused", vt06.items.count == 3
              && vt06.items[1].amountCents == 29
              && vt06.arbiterDeficitE1 == 1167 - 2000)

        // VT07 — mẫu D-17: dòng TOTAL in gãy không token,
        // alternate của chính dòng đó mang 105.16 → tổng chốt
        // bằng closureVariant, sổ khép.
        let vt07 = ReceiptParser.parseV4(lines: [
            vline("SUBTOTAL 96.91"),
            vline("SALES TAX 8.25"),
            vline("TOTAL $105.1G", alts: ["TOTAL 105.16"]),
        ])
        check("VT07-total-rescued", vt07.arbiterStatus == "closed"
              && vt07.totalCents == 10516
              && vt07.totalsProvenance["total"]?.detail == "closureVariant")

        // VT08 — nhóm xung đột: 1.23 và bản thay thế 13.23
        // của nó KHÔNG được cộng nhau (123 + 1323 = 1446
        // đúng bằng thiếu hụt giả) — hai bản đọc của cùng
        // một token in không phải hai dòng thuế.
        let vt08 = ReceiptParser.parseV4(lines: [
            vline("STORE A"),
            vline("SUBTOTAL 100.00"),
            vline("TAX 1.23", alts: ["TAX 13.23"]),
            vline("TOTAL 114.46"),
        ])
        check("VT08-same-token-not-summed", vt08.arbiterStatus == "unclosed")
    }

    // MARK: - Dựng dữ liệu kiểm (bản nháp đầy đủ trường)

    private static func makeSnapshot() -> PendingDraftSnapshot {
        var result = ParseResult()
        result.vendor = "Sam's Club"
        result.vendorKey = "sams"
        result.date = Date(timeIntervalSince1970: 1_791_000_000)
        result.items = [
            ParsedLineItem(name: "COKE 12PK", qty: 2, unitPriceCents: 1948,
                           amountCents: 3896, taxFlag: "A", itemCode: "980012379",
                           weightLb: nil, weightUnitCents: nil, lineIndex: 4),
            ParsedLineItem(name: "BANANA", qty: 1, unitPriceCents: nil,
                           amountCents: 318, taxFlag: nil, itemCode: nil,
                           weightLb: 2.5, weightUnitCents: 127, lineIndex: 9),
        ]
        result.subtotalCents = 4214
        result.taxes = [
            ParsedTaxLine(label: "TAX 1", rateText: "8.5170", amountCents: 359, lineIndex: 20),
            ParsedTaxLine(label: "TAX 2", rateText: "4.0170", amountCents: 25, lineIndex: 21),
        ]
        result.totalCents = 4598
        result.cardLast4 = "2586"
        result.cardBrand = "US DEBIT"
        result.cardConfidence = 0.9
        result.cardLineContaminated = true
        result.dedupeKey = "SAMS-TC-9087"
        result.itemsSold = 3
        result.warnings = ["Sổ chưa khớp"]
        result.vendorConfidence = 0.95
        result.dateConfidence = 0.8
        result.totalConfidence = 0.85
        result.vendorAddress = "123 W Example St"
        result.vendorPhone = "918-555-0100"
        result.storeNumber = "2427"
        result.vendorSource = "tier2-anchor"
        result.vendorSuggestion = nil
        result.vendorAnchorDisputed = true
        result.rawText = "SAM'S CLUB\nCOKE 12PK 38.96"
        result.selectionTrace = ["anchor:subtotal@18"]
        result.totalCandidates = [
            TotalCandidate(lineIndex: 18, cents: 4214, role: "subtotal", chosen: true),
            TotalCandidate(lineIndex: 22, cents: 4598, role: "total", chosen: true),
        ]
        result.totalsProvenance = [
            "total": FieldProvenance(kind: "read", detail: "closureUnique"),
        ]
        result.itemsProvenance = [
            "item[0]": FieldProvenance(kind: "read", detail: "sameLine"),
        ]
        result.arbiterStatus = "closed"
        result.arbiterDisputed = []
        result.arbiterDeficitE1 = 0
        result.arbiterDeficitE2 = 0
        result.geometricCandidates = [result.items[1]]
        result.itemsSoldLabelSeen = true
        result.soldContribution = "byQuantity"
        result.vendorDataVersion = "2026-11-01"

        var fix = ReconcileFix(itemIndex: 1, field: .insert, oldValue: nil,
                               newValue: 318, delta: 318, channel: .orphan, tier: 2)
        fix.insertName = "BANANA"
        fix.insertQty = 1
        fix.insertUnitCents = 318
        fix.insertCode = "123456"
        fix.evidence = "line 9: BANANA 3.18"
        var report = ReconcileReport()
        report.status = .repaired
        report.moneyDeltaCents = 0
        report.qtyDelta = 1
        report.fixes = [fix]
        report.suggestions = [[ReconcileFix(itemIndex: 0, field: .amount, oldValue: 3896,
                                            newValue: 3986, delta: 90, channel: .digit, tier: 3)]]
        report.solutionCount = 1
        var hint = ReconcileRegionHint(block: .items, reason: .qtyMismatch)
        hint.priority = 1
        hint.deltaCents = 318
        hint.lineRange = 4...9
        hint.band = CGRect(x: 0.1, y: 0.2, width: 0.8, height: 0.3)
        report.regionHints = [hint]
        report.notes = ["đã áp 1 sửa ORPHAN"]
        report.nodesVisited = 42
        report.taxMissing = false
        report.impliedTaxCents = 384
        report.anchorsPresent = ["subtotal", "total"]
        report.anchorsMissing = []
        report.requiresReview = true

        return PendingDraftSnapshot(
            result: result,
            imageFileName: "TEST-IMG.jpg",
            sourceTypeRaw: "camera",
            sourceFileName: nil,
            originalFileNames: ["TEST-IMG.jpg", "TEST-IMG-2.jpg"],
            rawTextIsPDFTextLayer: false,
            provenance: ["total": FieldProvenance(kind: "read", detail: "closureUnique")],
            reconcileReport: report,
            diagnosticsID: "diag-test-001",
            diagnosticsWriteFailed: true,
            createdAt: Date(timeIntervalSince1970: 1_791_000_100))
    }

    // MARK: - A. PendingDraftStore: vòng đời bản chụp nháp

    private static func runPendingDraftTests(_ check: (String, Bool) -> Void) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HarnessUnitTests-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            check("PD00-dung-thu-muc-kiem", false)
            return
        }
        defer { try? FileManager.default.removeItem(at: dir) }

        let snapshot = makeSnapshot()
        let fileURL = PendingDraftStore.fileURL(in: dir)

        // Thư mục trống: load == nil (ca thường, không phải lỗi).
        check("PD01-load-khi-chua-co-file-nil", PendingDraftStore.load(in: dir) == nil)

        // Vòng Codable thuần: encode -> decode -> bằng nhau.
        if let data = try? JSONEncoder().encode(snapshot),
           let back = try? JSONDecoder().decode(PendingDraftSnapshot.self, from: data) {
            check("PD02-codable-roundtrip-bang-nhau", back == snapshot)
        } else {
            check("PD02-codable-roundtrip-bang-nhau", false)
        }

        // Vòng qua đĩa: save -> load khớp (Equatable của snapshot
        // + DTO là so TỪNG TRƯỜNG đệ quy; thêm chốt điểm danh
        // các trường chính để khi đỏ biết ngay trường nào lệch).
        check("PD03-save-tra-true", PendingDraftStore.save(snapshot, in: dir))
        let tmpLeft = FileManager.default.fileExists(
            atPath: dir.appendingPathComponent(PendingDraftStore.fileName + ".tmp").path)
        check("PD04-save-khong-de-file-tmp", !tmpLeft)
        let loaded = PendingDraftStore.load(in: dir)
        check("PD05-load-bang-snapshot-tung-truong", loaded == snapshot)
        check("PD06-truong-imageFileName", loaded?.imageFileName == "TEST-IMG.jpg")
        check("PD07-truong-vendor", loaded?.result.vendor == "Sam's Club")
        check("PD08-truong-totalCents", loaded?.result.totalCents == 4598)
        check("PD09-truong-items",
              loaded?.result.items.count == 2 && loaded?.result.items[0].amountCents == 3896)
        check("PD10-truong-taxes",
              loaded?.result.taxes.count == 2 && loaded?.result.taxes[0].amountCents == 359)
        check("PD11-truong-report-statusRaw", loaded?.reconcileReport?.statusRaw == "REPAIRED")
        check("PD12-truong-diagnosticsID", loaded?.diagnosticsID == "diag-test-001")

        // Dựng lại kiểu gốc từ DTO đã nạp: toàn-hay-không.
        if let restored = loaded?.result.toOriginal() {
            check("PD13-dto-restore-parseresult",
                  restored.vendor == "Sam's Club" && restored.totalCents == 4598
                    && restored.itemsSold == 3 && restored.items.count == 2)
        } else {
            check("PD13-dto-restore-parseresult", false)
        }
        if let restoredReport = loaded?.reconcileReport?.toOriginal() {
            check("PD14-dto-restore-report",
                  restoredReport.status == .repaired && restoredReport.fixes.count == 1
                    && restoredReport.regionHints.count == 1)
        } else {
            check("PD14-dto-restore-report", false)
        }

        // Ghi đè: bản mới thắng.
        var newer = snapshot
        newer.imageFileName = "TEST-IMG-MOI.jpg"
        check("PD15-save-lan-2-tra-true", PendingDraftStore.save(newer, in: dir))
        check("PD16-ghi-de-ban-moi-thang", PendingDraftStore.load(in: dir) == newer)

        // Xoá: load -> nil; xoá lần nữa không crash.
        PendingDraftStore.clear(in: dir)
        check("PD17-load-sau-clear-nil", PendingDraftStore.load(in: dir) == nil)
        PendingDraftStore.clear(in: dir)
        check("PD18-clear-lan-2-khong-crash", true)

        // File hỏng: load nil + file bị xoá + có dòng log chẩn đoán.
        _ = PendingDraftStore.save(snapshot, in: dir)
        try? Data("đây không phải JSON {{{".utf8).write(to: fileURL)
        check("PD19-load-file-hong-nil", PendingDraftStore.load(in: dir) == nil)
        check("PD20-file-hong-bi-xoa", !FileManager.default.fileExists(atPath: fileURL.path))
        let logText = (try? String(contentsOf: dir.appendingPathComponent(PendingDraftStore.logFileName),
                                   encoding: .utf8)) ?? ""
        check("PD21-log-ghi-ban-hong", logText.contains("Snapshot nháp hỏng"))

        // Schema lạ: load nil + file bị xoá.
        _ = PendingDraftStore.save(snapshot, in: dir)
        if let data = try? Data(contentsOf: fileURL),
           var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json["schemaVersion"] = 99
            if let edited = try? JSONSerialization.data(withJSONObject: json) {
                try? edited.write(to: fileURL)
            }
        }
        check("PD22-load-schema-la-nil", PendingDraftStore.load(in: dir) == nil)
        check("PD23-file-schema-la-bi-xoa", !FileManager.default.fileExists(atPath: fileURL.path))

        // Mã enum lạ ở tầng DTO: dựng lại phải trả nil TOÀN PHẦN
        // (kỷ luật toàn-hay-không của PendingDraft.swift — bản
        // chụp của phiên bản khác không được dựng nửa vời). Đây
        // là lớp tương đương hai ca makeDraft của bộ test cũ:
        // makeDraft sống ở ScanView (tầng UI) nên ngoài harness;
        // hợp đồng nó dựa vào chính là toOriginal ở đây.
        if var alienReport = snapshot.reconcileReport {
            alienReport.fixes[0].channelRaw = "KENH_KHONG_TON_TAI"
            check("PD24-ma-kenh-la-report-nil", alienReport.toOriginal() == nil)
        } else {
            check("PD24-ma-kenh-la-report-nil", false)
        }
        if var alienStatus = snapshot.reconcileReport {
            alienStatus.statusRaw = "TRANG_THAI_LA"
            check("PD25-ma-trang-thai-la-report-nil", alienStatus.toOriginal() == nil)
        } else {
            check("PD25-ma-trang-thai-la-report-nil", false)
        }
    }

    // MARK: - A2. PendingBlockStore: vòng đời bản chụp bị chặn (G3)
    //
    // Vá sự cố thật 2026-11-15: tờ bị cổng phán .block thoát
    // app là mất. Bộ này khoá hợp đồng của kho mới ở mức THUẦN
    // tách được: round-trip từng trường (bản nháp lồng + kết
    // quả cổng), hỏng -> nil + tự xoá + log, schema lạ -> nil,
    // mã quyết định lạ -> qualityOutcome() nil (dựng lại
    // toàn-hay-không). Phần giết-app thật + khung chặn hiện
    // lại thuộc Gate D trên máy anh (đặc tả G1 §ma trận vòng
    // đời, ca trạng thái bị chặn) — CI không bao phủ.

    private static func makeBlockSnapshot() -> PendingBlockSnapshot {
        let outcome = QualityOutcome(detected: ["blur", "glare"],
                                     decision: .block,
                                     failSafe: false,
                                     consecutiveRejects: 1)
        return PendingBlockSnapshot(
            draftSnapshot: makeSnapshot(),
            quality: outcome,
            createdAt: Date(timeIntervalSince1970: 1_791_000_200))
    }

    private static func runPendingBlockTests(_ check: (String, Bool) -> Void) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HarnessUnitTests-Block-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            check("PB00-dung-thu-muc-kiem", false)
            return
        }
        defer { try? FileManager.default.removeItem(at: dir) }

        let snapshot = makeBlockSnapshot()
        let fileURL = PendingBlockStore.fileURL(in: dir)

        check("PB01-load-khi-chua-co-file-nil", PendingBlockStore.load(in: dir) == nil)

        if let data = try? JSONEncoder().encode(snapshot),
           let back = try? JSONDecoder().decode(PendingBlockSnapshot.self, from: data) {
            check("PB02-codable-roundtrip-bang-nhau", back == snapshot)
        } else {
            check("PB02-codable-roundtrip-bang-nhau", false)
        }

        check("PB03-save-tra-true", PendingBlockStore.save(snapshot, in: dir))
        let tmpLeft = FileManager.default.fileExists(
            atPath: dir.appendingPathComponent(PendingBlockStore.fileName + ".tmp").path)
        check("PB04-save-khong-de-file-tmp", !tmpLeft)
        let loaded = PendingBlockStore.load(in: dir)
        check("PB05-load-bang-snapshot-tung-truong", loaded == snapshot)
        check("PB06-truong-quality-detected", loaded?.quality.detected == ["blur", "glare"])
        check("PB07-truong-quality-decisionRaw", loaded?.quality.decisionRaw == "block")
        check("PB08-truong-nhap-long",
              loaded?.draft.imageFileName == "TEST-IMG.jpg"
                && loaded?.draft.result.totalCents == 4598)

        // Dựng lại kết quả cổng ở mức thuần: quyết định + các
        // trường nguyên thuỷ khớp nguyên văn.
        if let outcome = loaded?.qualityOutcome() {
            check("PB09-restore-quality-outcome",
                  outcome.decision == .block && outcome.detected == ["blur", "glare"]
                    && outcome.failSafe == false && outcome.consecutiveRejects == 1)
        } else {
            check("PB09-restore-quality-outcome", false)
        }

        // Ghi đè: bản mới thắng.
        var newer = snapshot
        newer.quality = QualityOutcomeDTO(QualityOutcome(
            detected: ["lowContrast"], decision: .block,
            failSafe: false, consecutiveRejects: 2))
        check("PB10-save-lan-2-tra-true", PendingBlockStore.save(newer, in: dir))
        check("PB11-ghi-de-ban-moi-thang", PendingBlockStore.load(in: dir) == newer)

        // Xoá: load -> nil; xoá lần nữa không crash.
        PendingBlockStore.clear(in: dir)
        check("PB12-load-sau-clear-nil", PendingBlockStore.load(in: dir) == nil)
        PendingBlockStore.clear(in: dir)
        check("PB13-clear-lan-2-khong-crash", true)

        // File hỏng: load nil + file bị xoá + có dòng log.
        _ = PendingBlockStore.save(snapshot, in: dir)
        try? Data("không phải JSON {{{".utf8).write(to: fileURL)
        check("PB14-load-file-hong-nil", PendingBlockStore.load(in: dir) == nil)
        check("PB15-file-hong-bi-xoa", !FileManager.default.fileExists(atPath: fileURL.path))
        let logText = (try? String(contentsOf: dir.appendingPathComponent(PendingBlockStore.logFileName),
                                   encoding: .utf8)) ?? ""
        check("PB16-log-ghi-ban-hong", logText.contains("Snapshot bị chặn hỏng"))

        // Schema lạ: load nil + file bị xoá.
        _ = PendingBlockStore.save(snapshot, in: dir)
        if let data = try? Data(contentsOf: fileURL),
           var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json["schemaVersion"] = 99
            if let edited = try? JSONSerialization.data(withJSONObject: json) {
                try? edited.write(to: fileURL)
            }
        }
        check("PB17-load-schema-la-nil", PendingBlockStore.load(in: dir) == nil)
        check("PB18-file-schema-la-bi-xoa", !FileManager.default.fileExists(atPath: fileURL.path))

        // Mã quyết định lạ: DTO vẫn giải mã được (nó chỉ là
        // chuỗi) nhưng dựng lại kết quả cổng phải trả nil —
        // quyết định chặn sai nghĩa còn tệ hơn mất bản chụp.
        var alien = snapshot
        alien.quality.decisionRaw = "CHAN_KHONG_TON_TAI"
        check("PB19-ma-quyet-dinh-la-outcome-nil", alien.qualityOutcome() == nil)
    }

    // MARK: - A3. Lớp sửa dở Kiểm Lại trong bản chụp nháp (G3)
    //
    // Khoá ba hợp đồng: (1) bản chụp KHÔNG lớp sửa (mặc định)
    // round-trip với reviewEdits == nil; (2) bản chụp CÓ lớp
    // sửa round-trip khớp từng trường của lớp phủ; (3) TƯƠNG
    // THÍCH NGƯỢC v1: file schema 1 không có khoá reviewEdits
    // (đúng định dạng bản 106 đang chạy trên máy anh) vẫn nạp
    // được; schema trên trần hiện hành (3) bị từ chối + xoá.

    private static func runReviewEditsTests(_ check: (String, Bool) -> Void) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HarnessUnitTests-Edits-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            check("RE00-dung-thu-muc-kiem", false)
            return
        }
        defer { try? FileManager.default.removeItem(at: dir) }

        let base = makeSnapshot()
        let fileURL = PendingDraftStore.fileURL(in: dir)

        // (1) Mặc định: không lớp sửa.
        check("RE01-mac-dinh-khong-lop-sua", base.reviewEdits == nil)
        check("RE02-save-ban-thuong", PendingDraftStore.save(base, in: dir))
        check("RE03-load-ban-thuong-reviewEdits-nil",
              PendingDraftStore.load(in: dir)?.reviewEdits == nil)

        // (2) Có lớp sửa: khớp toàn bộ + chốt các trường chính.
        var edited = base
        edited.reviewEdits = ReviewEditsDTO(
            vendorText: "Sam's Club Tulsa",
            dateValue: Date(timeIntervalSince1970: 1_791_050_000),
            subtotalText: "42.14", taxText: "3.84", totalText: "45.98",
            kindRaw: "business", category: "Vật Tư",
            purposeText: "Mua cho khách trong tiệm",
            reasonText: "Theo thẻ •• 2586", suggestionApplied: true)
        check("RE04-save-ban-co-lop-sua", PendingDraftStore.save(edited, in: dir))
        let loadedEdited = PendingDraftStore.load(in: dir)
        check("RE05-load-bang-tung-truong", loadedEdited == edited)
        check("RE06-truong-vendorText", loadedEdited?.reviewEdits?.vendorText == "Sam's Club Tulsa")
        check("RE07-truong-kindRaw", loadedEdited?.reviewEdits?.kindRaw == "business")
        check("RE08-truong-purposeText",
              loadedEdited?.reviewEdits?.purposeText == "Mua cho khách trong tiệm")
        check("RE09-truong-suggestionApplied",
              loadedEdited?.reviewEdits?.suggestionApplied == true)

        // (3) Tương thích ngược v1: gỡ khoá reviewEdits + hạ
        // schemaVersion về 1 -> vẫn nạp, lớp sửa nil, phần còn
        // lại nguyên vẹn.
        if let data = try? Data(contentsOf: fileURL),
           var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json["schemaVersion"] = 1
            json.removeValue(forKey: "reviewEdits")
            if let v1Data = try? JSONSerialization.data(withJSONObject: json) {
                try? v1Data.write(to: fileURL)
            }
        }
        let loadedV1 = PendingDraftStore.load(in: dir)
        check("RE10-file-v1-van-nap-duoc",
              loadedV1 != nil && loadedV1?.reviewEdits == nil
                && loadedV1?.result.totalCents == 4598)

        // Schema trên trần (3): từ chối + xoá như mã lạ.
        if let data = try? Data(contentsOf: fileURL),
           var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json["schemaVersion"] = 3
            if let v3Data = try? JSONSerialization.data(withJSONObject: json) {
                try? v3Data.write(to: fileURL)
            }
        }
        check("RE11-schema-3-bi-tu-choi", PendingDraftStore.load(in: dir) == nil)
        check("RE12-file-schema-3-bi-xoa", !FileManager.default.fileExists(atPath: fileURL.path))
    }

    // MARK: - B. canReparse (khoá L-2026-11-13-17)

    private static func runCanReparseTests(_ check: (String, Bool) -> Void) {
        // Còn văn bản đã lưu -> bấm được. Điều kiện thuần chỉ
        // còn phụ thuộc văn bản (không tem, không trạng thái) —
        // ba ca này khoá đúng hợp đồng đó.
        check("CR01-co-van-ban-true",
              ReceiptLogic.canReparse(ocrRawText: "SAM'S CLUB\nCOKE 19.48"))
        check("CR02-rong-false",
              !ReceiptLogic.canReparse(ocrRawText: ""))
        // Nguyên văn !isEmpty: chuỗi chỉ xuống dòng VẪN là còn
        // văn bản (không cắt trắng — giữ hành vi trước tách).
        check("CR03-chi-xuong-dong-true",
              ReceiptLogic.canReparse(ocrRawText: "\n"))
    }

    // MARK: - C. hasLoadableOriginal (IMGFIX)

    private static func runHasLoadableOriginalTests(_ check: (String, Bool) -> Void) {
        check("IM01-danh-sach-rong-false",
              !ReceiptLogic.hasLoadableOriginal(fileNames: [], isLoadable: { _ in true }))
        check("IM02-khong-file-nao-tai-duoc-false",
              !ReceiptLogic.hasLoadableOriginal(fileNames: ["a.jpg", "b.jpg"],
                                                isLoadable: { _ in false }))
        check("IM03-file-thu-hai-tai-duoc-true",
              ReceiptLogic.hasLoadableOriginal(fileNames: ["a.jpg", "b.jpg"],
                                               isLoadable: { $0 == "b.jpg" }))
        check("IM04-file-dau-tai-duoc-true",
              ReceiptLogic.hasLoadableOriginal(fileNames: ["a.jpg"],
                                               isLoadable: { _ in true }))
    }

    // MARK: - D. ReceiptLogic.flags (khoá L-2026-11-13-20 + IMGFIX)

    private static func flagInput(
        subtotal: Int? = 4214,
        items: [Int?] = [3896, 318],
        total: Int? = 4598,
        tax: Int? = 384,
        kind: ReceiptKindTag = .business,
        purpose: String = "Mua cho khách trong tiệm",
        hasImage: Bool = true,
        vendor: String? = nil
    ) -> ReceiptFlagInput {
        ReceiptFlagInput(subtotalCents: subtotal, itemAmountCents: items,
                         totalCents: total, taxCents: tax, kind: kind,
                         businessPurpose: purpose, hasOriginalImage: hasImage,
                         vendor: vendor)
    }

    private static func runFlagsTests(_ check: (String, Bool) -> Void) {
        // Tờ sạch hoàn toàn -> không cờ nào.
        check("FL01-to-sach-khong-co",
              ReceiptLogic.flags(for: flagInput()) == [])
        // Business + mục đích rỗng -> đúng một cờ mục đích.
        check("FL02-business-thieu-muc-dich",
              ReceiptLogic.flags(for: flagInput(purpose: ""))
                == [missingPurposeFlagText])
        // Mục đích chỉ toàn khoảng trắng vẫn tính là thiếu
        // (bản gốc cắt .whitespaces trước khi so rỗng).
        check("FL03-muc-dich-toan-khoang-trang",
              ReceiptLogic.flags(for: flagInput(purpose: "   "))
                .contains(missingPurposeFlagText))
        // Đã có mục đích -> cờ mục đích tắt kể cả khi cờ khác còn.
        check("FL04-co-muc-dich-chi-con-co-anh",
              ReceiptLogic.flags(for: flagInput(hasImage: false))
                == [missingOriginalImageFlagText])
        // Cá nhân + mục đích rỗng -> KHÔNG cờ mục đích.
        check("FL05-ca-nhan-khong-co-muc-dich",
              ReceiptLogic.flags(for: flagInput(kind: .personal, purpose: "")) == [])
        // Chưa rõ -> cờ chưa phân loại, không cờ mục đích.
        check("FL06-chua-ro-chi-co-phan-loai",
              ReceiptLogic.flags(for: flagInput(kind: .unknown, purpose: ""))
                == ["Chưa phân loại Cá nhân / Business"])
        // Thiếu tổng tiền.
        check("FL07-thieu-tong-tien",
              ReceiptLogic.flags(for: flagInput(total: nil))
                .contains("Thiếu tổng tiền"))
        // Subtotal + thuế lệch tổng 3 xu -> cờ; lệch đúng 2 xu
        // (trong dung sai) -> không cờ.
        check("FL08-lech-tong-3-xu-co",
              ReceiptLogic.flags(for: flagInput(total: 4601))
                .contains("Subtotal + thuế khác tổng tiền"))
        check("FL09-lech-tong-2-xu-khong-co",
              !ReceiptLogic.flags(for: flagInput(total: 4600))
                .contains("Subtotal + thuế khác tổng tiền"))
        // taxCents nil được tính là 0 (nguyên văn bản gốc).
        check("FL10-thue-nil-tinh-0",
              ReceiptLogic.flags(for: flagInput(total: 4214, tax: nil)) == [])
        // Σ món lệch subtotal: 3 xu -> cờ kèm đúng số đã định
        // dạng; đúng 2 xu -> không cờ.
        check("FL11-lech-mon-3-xu-co-dung-chu",
              ReceiptLogic.flags(for: flagInput(items: [3896, 315]))
                .contains("Tổng các món ($42.11) khác subtotal ($42.14)"))
        check("FL12-lech-mon-2-xu-khong-co",
              ReceiptLogic.flags(for: flagInput(items: [3896, 316])) == [])
        // Không có dòng món -> không cờ món dù có subtotal.
        check("FL13-khong-mon-khong-co-mon",
              ReceiptLogic.flags(for: flagInput(items: [])) == [])
        // Dòng món không có tiền tính 0 vào Σ.
        check("FL14-mon-nil-tinh-0",
              ReceiptLogic.flags(for: flagInput(items: [3896, nil]))
                .contains("Tổng các món ($38.96) khác subtotal ($42.14)"))
        // Thứ tự cờ khoá cứng: món -> mục đích -> ảnh gốc.
        check("FL15-thu-tu-co",
              ReceiptLogic.flags(for: flagInput(subtotal: 500, items: [100],
                                                total: 500, tax: 0,
                                                purpose: "", hasImage: false))
                == ["Tổng các món ($1.00) khác subtotal ($5.00)",
                    missingPurposeFlagText,
                    missingOriginalImageFlagText])
        // P2-0 mục 19: nơi gọi CÓ cung cấp tiệm mà rỗng ->
        // cờ "Chưa rõ tiệm"; toàn khoảng trắng cũng tính rỗng.
        check("FL16-tiem-rong-co",
              ReceiptLogic.flags(for: flagInput(vendor: ""))
                == [missingVendorFlagText])
        check("FL17-tiem-khoang-trang-co",
              ReceiptLogic.flags(for: flagInput(vendor: "   "))
                .contains(missingVendorFlagText))
        // Có tên tiệm -> không cờ tiệm; không cung cấp
        // (vendor nil, mặc định) -> bộ cờ không phán về tiệm.
        check("FL18-co-tiem-khong-co",
              ReceiptLogic.flags(for: flagInput(vendor: "Hobby Lobby")) == [])
        check("FL19-khong-cung-cap-tiem-khong-phan",
              ReceiptLogic.flags(for: flagInput()) == [])
    }

    // MARK: - E. Cổng duyệt theo lớp cờ (khoá L-2026-11-18-32)
    //
    // Cổng cũ (P2-0/C-1): mọi cờ ngoài V1/V2 đều CHẶN nút
    // duyệt — tờ Hobby Lobby của anh chỉ có đúng một cờ
    // "Chưa rõ tiệm" mà Chi Tiết lại không có ô sửa tiệm, nên
    // bị khoá vĩnh viễn. Luật mới: chỉ cờ thiếu ảnh gốc (bằng
    // chứng bắt buộc) còn giữ khoá; lệch số học + thiếu trường
    // đi đường duyệt-kèm-cờ có xác nhận. Các ca dưới đây nạp
    // cờ SINH THẬT từ ReceiptLogic.flags để khoá cả chuỗi cờ
    // lẫn phán quyết cổng.

    private static func runApprovalGateTests(_ check: (String, Bool) -> Void) {
        // Phân lớp từng loại cờ.
        check("GT01-phan-lop-lech-mon",
              ReceiptLogic.flagClass("Tổng các món ($1.00) khác subtotal ($5.00)")
                == .arithmeticDiscrepancy)
        check("GT02-phan-lop-lech-tong",
              ReceiptLogic.flagClass("Subtotal + thuế khác tổng tiền")
                == .arithmeticDiscrepancy)
        check("GT03-phan-lop-thieu-tong",
              ReceiptLogic.flagClass("Thiếu tổng tiền") == .missingField)
        check("GT04-phan-lop-tiem",
              ReceiptLogic.flagClass(missingVendorFlagText) == .missingField)
        check("GT05-phan-lop-muc-dich",
              ReceiptLogic.flagClass(missingPurposeFlagText) == .missingField)
        check("GT06-phan-lop-phan-loai",
              ReceiptLogic.flagClass("Chưa phân loại Cá nhân / Business")
                == .missingField)
        check("GT07-phan-lop-anh-goc",
              ReceiptLogic.flagClass(missingOriginalImageFlagText)
                == .missingOriginalImage)
        // Không cờ -> duyệt thẳng.
        check("GT08-khong-co-duyet-thang",
              ReceiptLogic.approvalGate(flags: ReceiptLogic.flags(for: flagInput()))
                == .approveDirectly)
        // Ca của anh: CHỈ một cờ "Chưa rõ tiệm" -> duyệt kèm
        // cờ được (cổng cũ: khoá cứng).
        check("GT09-chi-co-tiem-duyet-kem-co",
              ReceiptLogic.approvalGate(flags: ReceiptLogic.flags(
                    for: flagInput(vendor: "")))
                == .approveWithFlagConfirmation(flags: [missingVendorFlagText]))
        // Điền tên tiệm -> cờ tự tắt -> duyệt thẳng (nguyên
        // tắc (a): cờ thiếu trường tắt khi điền đúng trường).
        check("GT10-dien-tiem-co-tat",
              ReceiptLogic.approvalGate(flags: ReceiptLogic.flags(
                    for: flagInput(vendor: "Hobby Lobby")))
                == .approveDirectly)
        // Lệch số học V1 / V2 -> duyệt kèm cờ (hành vi cũ giữ
        // nguyên).
        check("GT11-lech-mon-duyet-kem-co",
              ReceiptLogic.approvalGate(flags: ReceiptLogic.flags(
                    for: flagInput(items: [3896, 315])))
                == .approveWithFlagConfirmation(
                    flags: ["Tổng các món ($42.11) khác subtotal ($42.14)"]))
        check("GT12-lech-tong-duyet-kem-co",
              ReceiptLogic.approvalGate(flags: ReceiptLogic.flags(
                    for: flagInput(total: 4601)))
                == .approveWithFlagConfirmation(
                    flags: ["Subtotal + thuế khác tổng tiền"]))
        // Thiếu tổng / thiếu mục đích / chưa phân loại: trước
        // đây khoá cứng, nay duyệt kèm cờ.
        check("GT13-thieu-tong-duyet-kem-co",
              ReceiptLogic.approvalGate(flags: ReceiptLogic.flags(
                    for: flagInput(total: nil)))
                == .approveWithFlagConfirmation(flags: ["Thiếu tổng tiền"]))
        check("GT14-thieu-muc-dich-duyet-kem-co",
              ReceiptLogic.approvalGate(flags: ReceiptLogic.flags(
                    for: flagInput(purpose: "")))
                == .approveWithFlagConfirmation(flags: [missingPurposeFlagText]))
        check("GT15-chua-phan-loai-duyet-kem-co",
              ReceiptLogic.approvalGate(flags: ReceiptLogic.flags(
                    for: flagInput(kind: .unknown, purpose: "")))
                == .approveWithFlagConfirmation(
                    flags: ["Chưa phân loại Cá nhân / Business"]))
        // Thiếu ảnh gốc: lớp DUY NHẤT còn khoá.
        check("GT16-thieu-anh-khoa",
              ReceiptLogic.approvalGate(flags: ReceiptLogic.flags(
                    for: flagInput(hasImage: false)))
                == .blockedByMissingImage(flags: [missingOriginalImageFlagText]))
        // Trộn: lệch + thiếu trường (không ảnh) -> kèm cờ cả
        // bộ; có thêm cờ ảnh -> khoá vì ảnh.
        check("GT17-tron-khong-anh-kem-co",
              ReceiptLogic.approvalGate(flags: ReceiptLogic.flags(
                    for: flagInput(items: [3896, 315], vendor: "")))
                == .approveWithFlagConfirmation(
                    flags: ["Tổng các món ($42.11) khác subtotal ($42.14)",
                            missingVendorFlagText]))
        check("GT18-tron-co-anh-khoa",
              ReceiptLogic.approvalGate(flags: ReceiptLogic.flags(
                    for: flagInput(hasImage: false, vendor: "")))
                == .blockedByMissingImage(
                    flags: [missingVendorFlagText, missingOriginalImageFlagText]))
    }

    // MARK: - G4: cổng chất lượng — ngưỡng dữ liệu, phân loại,
    // bộ đếm bền + leo thang, vùng tờ, chuẩn hoá hạ mẫu
    //
    // Khoá các hợp đồng của gói G4 ở mức THUẦN tách được:
    // (1) bộ ngưỡng hiệu chuẩn 2026-11-15 là DỮ LIỆU có phiên
    // bản, mặc định blockEnabled = false (luật hạ .block ->
    // .warn cho tới khi anh duyệt bật lại); giải mã JSON thiếu
    // khoá rơi về đúng mặc định. (2) Phân loại biên đúng dấu
    // bất đẳng thức chặt của evaluate: blur < min, glare >
    // max, contrast < min — BẰNG ngưỡng thì không gắn cờ.
    // (3) Máy .block còn nguyên cho tương lai (blockEnabled
    // tiêm vào + 2 vấn đề -> .block) nhưng bộ mặc định chỉ
    // .warn. (4) Bộ đếm từ chối liên tiếp BỀN qua các instance
    // cổng khi dùng chung một kho đếm; chạm max thì LEO THANG
    // (escalated, xét TRƯỚC quyết định chặn như fail-safe cũ)
    // rồi đặt lại; lượt sạch đặt lại. (5) Vùng tờ trên lưới
    // tổng hợp: hộp giấy thắng nền tối; nền trắng chói ngoài
    // tờ không rò vào glare; lưới đều màu -> fallback khai
    // rõ. (6) Chuẩn hoá blur theo factor^k đúng tỉ lệ.
    // Phần đo trên ảnh thật + phân phối hiệu chuẩn nằm ở
    // g4/calibration/ (gương Python cùng thuật toán); ca tờ
    // mới bị chặn oan 2026-11-15 kiểm ở Gate D trên máy anh.

    private static func qSignals(blur: Double = 1.0,
                                 glare: Double = 0.0,
                                 contrast: Double = 0.30) -> QualitySignals {
        QualitySignals(blurVariance: blur, glareFraction: glare,
                       localContrast: contrast)
    }

    private static func runQualityGateTests(
        _ check: (String, Bool) -> Void) {

        // (1) Bộ ngưỡng mặc định = bộ hiệu chuẩn đã chốt.
        let d = QualityThresholds()
        check("QG01-nguong-mac-dinh-la-bo-hieu-chuan",
              d.dataVersion == "quality-gate-v4-calibrated-2026-11-15"
                && d.warnEnabled && !d.blockEnabled
                && d.blurMin == 0.008 && d.glareMax == 0.88
                && d.contrastMin == 0.12 && d.maxConsecutiveRejects == 3
                && d.blurScaleExponent == 0.10)
        let cur = QualityThresholds.current()
        check("QG02-current-khong-bat-block",
              !cur.blockEnabled && cur.blurMin == 0.008
                && cur.dataVersion == QualityThresholds.compiledDataVersion)
        let fullJSON = """
        {"dataVersion":"quality-gate-v4-calibrated-2026-11-15",
         "warnEnabled":true,"blockEnabled":false,"blurMin":0.008,
         "glareMax":0.88,"contrastMin":0.12,
         "maxConsecutiveRejects":3,"blurScaleExponent":0.10}
        """
        if let decoded = try? JSONDecoder().decode(
            QualityThresholds.self, from: Data(fullJSON.utf8)) {
            check("QG03-giai-ma-json-day-du",
                  decoded.blurMin == 0.008 && decoded.glareMax == 0.88
                    && decoded.contrastMin == 0.12
                    && !decoded.blockEnabled)
        } else {
            check("QG03-giai-ma-json-day-du", false)
        }
        if let partial = try? JSONDecoder().decode(
            QualityThresholds.self, from: Data("{}".utf8)) {
            check("QG04-giai-ma-json-thieu-khoa-ve-mac-dinh",
                  partial.blurMin == 0.008 && partial.glareMax == 0.88
                    && !partial.blockEnabled)
        } else {
            check("QG04-giai-ma-json-thieu-khoa-ve-mac-dinh", false)
        }

        // (2) Phân loại cơ bản.
        let gate1 = QualityGate(counterStore: InMemoryQualityRejectCounter())
        let clean = gate1.evaluate(qSignals())
        check("QG05-sach-pass", clean.decision == .pass
              && clean.detected.isEmpty && !clean.escalated
              && clean.consecutiveRejects == 0)
        let oneBad = gate1.evaluate(qSignals(blur: 0.004))
        check("QG06-mot-van-de-warn", oneBad.decision == .warn
              && oneBad.detected == ["blur"] && !oneBad.escalated)

        // (3) Hai vấn đề: mặc định .warn; tiêm blockEnabled thì .block.
        let gate2 = QualityGate(counterStore: InMemoryQualityRejectCounter())
        let twoBad = gate2.evaluate(qSignals(blur: 0.004, glare: 0.95))
        check("QG07-hai-van-de-mac-dinh-warn-khong-block",
              twoBad.decision == .warn
                && twoBad.detected == ["blur", "glare"])
        var blockTh = QualityThresholds()
        blockTh.blockEnabled = true
        let gate3 = QualityGate(thresholds: blockTh,
                                counterStore: InMemoryQualityRejectCounter())
        let blocked = gate3.evaluate(qSignals(blur: 0.004, glare: 0.95))
        check("QG08-bat-blockEnabled-thi-block",
              blocked.decision == .block
                && blocked.detected == ["blur", "glare"])

        // Biên: bằng ngưỡng = không cờ; qua ngưỡng một li = cả ba cờ.
        let gate4 = QualityGate(counterStore: InMemoryQualityRejectCounter())
        let atEdge = gate4.evaluate(qSignals(blur: 0.008, glare: 0.88,
                                             contrast: 0.12))
        check("QG09-dung-nguong-khong-co", atEdge.decision == .pass
              && atEdge.detected.isEmpty)
        let pastEdge = gate4.evaluate(qSignals(blur: 0.0079, glare: 0.8801,
                                               contrast: 0.1199))
        check("QG10-qua-nguong-co-ca-ba",
              pastEdge.detected == ["blur", "glare", "lowContrast"]
                && pastEdge.decision == .warn)

        // (4) Bộ đếm bền + leo thang.
        let shared = InMemoryQualityRejectCounter()
        let r1 = QualityGate(counterStore: shared)
            .evaluate(qSignals(blur: 0.004))
        let r2 = QualityGate(counterStore: shared)
            .evaluate(qSignals(blur: 0.004))
        check("QG11-dem-ben-qua-instance", r1.consecutiveRejects == 1
              && r2.consecutiveRejects == 2 && !r2.escalated
              && shared.loadCount() == 2)
        let r3 = QualityGate(counterStore: shared)
            .evaluate(qSignals(blur: 0.004))
        check("QG12-luot-3-leo-thang-va-dat-lai",
              r3.escalated && r3.decision == .warn && !r3.failSafe
                && r3.consecutiveRejects == 3 && shared.loadCount() == 0)
        let r4 = QualityGate(counterStore: shared)
            .evaluate(qSignals(blur: 0.004))
        check("QG13-sau-leo-thang-dem-lai-tu-1",
              r4.consecutiveRejects == 1 && !r4.escalated)
        let store2 = InMemoryQualityRejectCounter(2)
        _ = QualityGate(counterStore: store2).evaluate(qSignals())
        check("QG14-luot-sach-dat-lai-dem", store2.loadCount() == 0)
        var blockTh2 = QualityThresholds()
        blockTh2.blockEnabled = true
        let esc = QualityGate(thresholds: blockTh2,
                              counterStore: InMemoryQualityRejectCounter(2))
            .evaluate(qSignals(blur: 0.004, glare: 0.95))
        check("QG15-leo-thang-truoc-block", esc.escalated
              && esc.decision == .warn)

        // (5) Vùng tờ trên lưới tổng hợp 100x100: nền tối 0.15,
        // giấy x 20..<80, y 10..<90 sáng 0.95, mực 0.05 trong giấy.
        var samples = [Double](repeating: 0.15, count: 100 * 100)
        for y in 10..<90 {
            for x in 20..<80 {
                samples[y * 100 + x] = 0.95
            }
        }
        for y in stride(from: 15, to: 90, by: 5) {
            for x in stride(from: 25, to: 80, by: 5) {
                samples[y * 100 + x] = 0.05
            }
        }
        let grid = LuminanceGrid(width: 100, height: 100, samples: samples)
        let region = grid.documentRegion()
        check("QG16-vung-to-la-hop-giay", !region.fallback
              && region.x0 <= 20 && region.x1 >= 80
              && region.y0 <= 10 && region.y1 >= 90
              && region.x0 > 0 && region.x1 < 100)
        // Cùng tờ, nền ngoài đổi thành trắng chói 1.0: glare
        // trong vùng phải vẫn 0 (nền không rò vào phép đo).
        var samplesB = samples
        for y in 0..<100 {
            for x in 0..<100 where !(x >= 20 && x < 80 && y >= 10 && y < 90) {
                samplesB[y * 100 + x] = 1.0
            }
        }
        let gridB = LuminanceGrid(width: 100, height: 100, samples: samplesB)
        let sigA = grid.signals()
        let sigB = gridB.signals()
        // A: vùng = hộp giấy, glare đúng 0. B: giấy ~cả khung
        // nên vùng lấy theo hộp MỰC trong tờ; lề nới 8% kéo
        // theo vài hàng nền trắng sát mép tờ (~0.04) — vẫn
        // thấp hơn hẳn mức 0.52 nếu đo toàn khung như bản cũ.
        check("QG17-nen-ngoai-khong-ro-vao-glare",
              !sigA.regionFallback && sigA.glareFraction == 0
                && !sigB.regionFallback && sigB.glareFraction < 0.05)
        // Lưới đều màu: không ngưỡng Otsu, không vùng — fallback.
        let flat = LuminanceGrid(width: 20, height: 20,
                                 samples: [Double](repeating: 0.5,
                                                   count: 20 * 20))
        check("QG18-luoi-deu-mau-fallback",
              flat.documentRegion().fallback && flat.signals().regionFallback)

        // (6) Chuẩn hoá hạ mẫu: cùng lưới, factor 2 -> blur x2 khi k=1.
        var checker = [Double]()
        for y in 0..<40 {
            for x in 0..<40 {
                checker.append((x + y) % 2 == 0 ? 0.0 : 1.0)
            }
        }
        var normTh = QualityThresholds()
        normTh.blurScaleExponent = 1.0
        let plain = LuminanceGrid(width: 40, height: 40, samples: checker)
        let scaled = LuminanceGrid(width: 40, height: 40, samples: checker,
                                   sourcePixelWidth: 80,
                                   sourcePixelHeight: 80)
        let blurPlain = plain.signals(thresholds: normTh).blurVariance
        let blurScaled = scaled.signals(thresholds: normTh).blurVariance
        check("QG19-chuan-hoa-factor-k",
              blurPlain > 0 && abs(blurScaled - 2 * blurPlain) < 0.000001)
        check("QG20-factor-suy-tu-kich-thuoc-goc",
              plain.downsampleFactor == 1 && scaled.downsampleFactor == 2)

        // (7) DTO: escalated đi vòng tròn; JSON cũ không có
        // khoá escalated giải mã ra false (tương thích G3).
        let escOutcome = QualityOutcome(detected: ["blur"], decision: .warn,
                                        failSafe: false, consecutiveRejects: 3,
                                        escalated: true)
        let dto = QualityOutcomeDTO(escOutcome)
        check("QG21-dto-escalated-vong-tron",
              dto.escalated == true
                && dto.toOriginal()?.escalated == true)
        let legacyJSON = """
        {"detected":["blur"],"decisionRaw":"warn","failSafe":false,
         "consecutiveRejects":2}
        """
        if let legacy = try? JSONDecoder().decode(
            QualityOutcomeDTO.self, from: Data(legacyJSON.utf8)) {
            check("QG22-dto-json-cu-escalated-false",
                  legacy.escalated == nil
                    && legacy.toOriginal()?.escalated == false
                    && legacy.toOriginal()?.decision == .warn)
        } else {
            check("QG22-dto-json-cu-escalated-false", false)
        }
    }

    // MARK: - L-2026-11-20-42: planner kiểm kê ảnh gốc (thuần)
    //
    // IntegrityPlanner (ImageIntegrity.swift) quyết định ở
    // mức TÊN FILE: bản đồ tham chiếu (tên file -> tập id
    // hoá đơn còn tham chiếu) + tập file ở kho chính + tập
    // file ở kho an toàn + tập "đã biết còn" ở kho chính từ
    // lần kiểm trước. Bốn loại hành động phải phủ đủ: khôi
    // phục từ kho an toàn / chép bổ sung vào kho / mất hẳn /
    // mất mới. Ca file CHUNG hai hoá đơn kiểm ở mức file:
    // một hoá đơn biến mất khỏi bản đồ KHÔNG biến file còn
    // nguyên thành "mất" cho hoá đơn còn lại.

    private static func runIntegrityPlannerTests(
        _ check: (String, Bool) -> Void) {

        // IG01 — file đủ ở cả hai kho -> không hành động.
        let ig01 = IntegrityPlanner.plan(
            references: ["a.jpg": ["R1"], "b.pdf": ["R2"]],
            mainFiles: ["a.jpg", "b.pdf"],
            vaultFiles: ["a.jpg", "b.pdf"],
            knownPresent: ["a.jpg", "b.pdf"])
        check("IG01-du-hai-kho-khong-hanh-dong", ig01.isEmpty)

        // IG02 — kho chính có, kho an toàn thiếu -> chép
        // bổ sung đúng một hành động.
        let ig02 = IntegrityPlanner.plan(
            references: ["a.jpg": ["R1"]],
            mainFiles: ["a.jpg"],
            vaultFiles: [],
            knownPresent: ["a.jpg"])
        check("IG02-thieu-vault-chep-bo-sung",
              ig02 == [.backfillVault(fileName: "a.jpg")])

        // IG03 — kho chính mất, kho an toàn còn -> khôi
        // phục; file chưa từng "biết còn" nên không kèm
        // nhãn mất mới.
        let ig03 = IntegrityPlanner.plan(
            references: ["a.jpg": ["R1"]],
            mainFiles: [],
            vaultFiles: ["a.jpg"],
            knownPresent: [])
        check("IG03-mat-chinh-con-vault-khoi-phuc",
              ig03 == [.restoreFromVault(fileName: "a.jpg")])

        // IG04 — mất cả hai kho, chưa từng biết còn ->
        // mất hẳn, KHÔNG nhãn mất mới (không có căn cứ
        // nói nó vừa mất).
        let ig04 = IntegrityPlanner.plan(
            references: ["a.jpg": ["R1"]],
            mainFiles: [],
            vaultFiles: [],
            knownPresent: [])
        check("IG04-mat-ca-hai-chua-biet",
              ig04 == [.missingUnrecoverable(fileName: "a.jpg")])

        // IG05 — mất cả hai kho, lần kiểm trước còn ở kho
        // chính -> mất hẳn + MẤT MỚI (ca bắt vụ mất ở lần
        // mở app kế tiếp).
        let ig05 = IntegrityPlanner.plan(
            references: ["a.jpg": ["R1"]],
            mainFiles: [],
            vaultFiles: [],
            knownPresent: ["a.jpg"])
        check("IG05-mat-ca-hai-la-mat-moi",
              ig05 == [.missingUnrecoverable(fileName: "a.jpg"),
                       .newlyLost(fileName: "a.jpg")])

        // IG06 — mất kho chính nhưng cứu được từ kho an
        // toàn, lần trước còn -> khôi phục + MẤT MỚI (sự
        // kiện mất vẫn phải để lại dấu vết dù đã cứu).
        let ig06 = IntegrityPlanner.plan(
            references: ["a.jpg": ["R1"]],
            mainFiles: [],
            vaultFiles: ["a.jpg"],
            knownPresent: ["a.jpg"])
        check("IG06-cuu-duoc-van-la-mat-moi",
              ig06 == [.restoreFromVault(fileName: "a.jpg"),
                       .newlyLost(fileName: "a.jpg")])

        // IG07 — file được HAI hoá đơn cùng tham chiếu,
        // kiểm ở mức file:
        // (a) cả hai còn tham chiếu, file đủ -> im lặng.
        let ig07a = IntegrityPlanner.plan(
            references: ["s.jpg": ["R1", "R2"]],
            mainFiles: ["s.jpg"],
            vaultFiles: ["s.jpg"],
            knownPresent: ["s.jpg"])
        check("IG07a-file-chung-con-du", ig07a.isEmpty)
        // (b) một hoá đơn đã bị xoá khỏi bản đồ (tờ còn
        // lại vẫn tham chiếu), file còn ở kho chính ->
        // KHÔNG tính mất; chỉ chép bổ sung vào kho an
        // toàn đang thiếu.
        let ig07b = IntegrityPlanner.plan(
            references: ["s.jpg": ["R2"]],
            mainFiles: ["s.jpg"],
            vaultFiles: [],
            knownPresent: ["s.jpg"])
        check("IG07b-xoa-mot-to-file-chung-khong-mat",
              ig07b == [.backfillVault(fileName: "s.jpg")])
        // (c) file chung mất cả hai kho -> đúng MỘT hành
        // động mất hẳn cho file, không nhân đôi theo số
        // hoá đơn tham chiếu.
        let ig07c = IntegrityPlanner.plan(
            references: ["s.jpg": ["R1", "R2"]],
            mainFiles: [],
            vaultFiles: [],
            knownPresent: [])
        check("IG07c-file-chung-mat-mot-hanh-dong",
              ig07c == [.missingUnrecoverable(fileName: "s.jpg")])

        // IG08 — file mồ côi (không hoá đơn nào tham
        // chiếu) dù có mặt ở kho -> planner không xét,
        // không sinh hành động.
        let ig08 = IntegrityPlanner.plan(
            references: ["a.jpg": ["R1"]],
            mainFiles: ["a.jpg", "orphan.jpg"],
            vaultFiles: ["a.jpg", "orphan.jpg"],
            knownPresent: ["a.jpg", "orphan.jpg"])
        check("IG08-file-mo-coi-khong-xet", ig08.isEmpty)

        // IG09 — không có tham chiếu nào -> không hành
        // động (kho trống tham chiếu là trạng thái hợp lệ).
        check("IG09-khong-tham-chieu",
              IntegrityPlanner.plan(
                references: [:],
                mainFiles: ["x.jpg"],
                vaultFiles: [],
                knownPresent: ["x.jpg"]).isEmpty)

        // IG10 — hành động sắp theo tên file tăng dần
        // (ổn định cho log + test).
        let ig10 = IntegrityPlanner.plan(
            references: ["b.jpg": ["R1"], "a.jpg": ["R2"]],
            mainFiles: [],
            vaultFiles: [],
            knownPresent: [])
        check("IG10-thu-tu-ten-file",
              ig10.map { $0.fileName } == ["a.jpg", "b.jpg"])

        // TR01 — hình học dải cứu FL-317 (bản sao probeTiles):
        // 4 dải phủ kín khung; dải mép cao 0.28 (0.25 + nở
        // 0.03 một phía), dải giữa cao 0.31 (nở cả hai phía);
        // hai dải kề nhau chồng lấn.
        let bands = ReceiptReader.tiledRescueBands()
        check("TR01-bon-dai-phu-kin-chong-lan",
              bands.count == 4
                  && abs(bands[0].minY) < 1e-9
                  && abs(bands[3].maxY - 1.0) < 1e-9
                  && abs(bands[0].height - 0.28) < 1e-9
                  && abs(bands[1].height - 0.31) < 1e-9
                  && bands[1].minY < bands[0].maxY
                  && bands[2].minY < bands[1].maxY
                  && bands[3].minY < bands[2].maxY)
        // TR02 — remap hộp đầy dải trả đúng dải.
        let band1 = bands[1]
        let full = ReceiptReader.remapTiledBox(
            CGRect(x: 0, y: 0, width: 1, height: 1), band: band1)
        check("TR02-remap-day-dai",
              abs(full.minX - band1.minX) < 1e-9
                  && abs(full.minY - band1.minY) < 1e-9
                  && abs(full.width - band1.width) < 1e-9
                  && abs(full.height - band1.height) < 1e-9)
        // TR03 — remap hộp giữa dải theo đúng tỉ lệ: dải 2
        // (đếm từ đáy) = [0.47, 0.78], cao 0.31; hộp
        // (0.5, 0.5, 0.25, 0.1) -> (0.5, 0.625, 0.25, 0.031).
        let mid = ReceiptReader.remapTiledBox(
            CGRect(x: 0.5, y: 0.5, width: 0.25, height: 0.1),
            band: bands[2])
        check("TR03-remap-giua-dai",
              abs(mid.minX - 0.5) < 1e-9
                  && abs(mid.minY - 0.625) < 1e-9
                  && abs(mid.width - 0.25) < 1e-9
                  && abs(mid.height - 0.031) < 1e-9)

        // ES01–ES04 — PHA 1: hoán đổi bằng chứng (PHASE1-DIFF.md).
        func esEv(hasTotal: Bool, hasSubtotal: Bool, e2: Bool,
                  integrity: Double, isOriginal: Bool = false)
            -> CandidateEvaluation {
            CandidateEvaluation(
                e1Closed: false, e2Within2c: e2, e3Closed: false,
                integrity: integrity, hasSubtotal: hasSubtotal,
                hasTotal: hasTotal, hasTaxLine: false, hasDate: false,
                vendorResolved: true, itemsMissingAmount: 0,
                alnumChars: 0, isOriginal: isOriginal)
        }
        let esEmpty = ParseResult()
        var esTotalOnly = ParseResult(); esTotalOnly.totalCents = 8907
        var esFull = ParseResult()
        esFull.subtotalCents = 8772; esFull.totalCents = 8907
        // ES01 — winner rỗng + có ứng viên mang số: nhường ứng
        // viên giàu nhất (total+subtotal+e2, integrity cao,
        // nhiều mảnh nhất) — đúng hình ca 02-walmart-2 run #70.
        check("ES01-hoan-doi-sang-ung-vien-giau-nhat",
              CandidateScorer.evidenceSwapWinner(
                  evals: [esEv(hasTotal: false, hasSubtotal: false,
                               e2: false, integrity: 0,
                               isOriginal: true),
                          esEv(hasTotal: true, hasSubtotal: false,
                               e2: false, integrity: 0.25),
                          esEv(hasTotal: true, hasSubtotal: true,
                               e2: true, integrity: 0.889)],
                  parses: [esEmpty, esTotalOnly, esFull],
                  fragmentCounts: [2, 119, 163],
                  currentWinner: 0) == 2)
        // ES02 — winner đã mang total: không hoán đổi dù có
        // ứng viên giàu hơn.
        check("ES02-winner-co-total-giu-nguyen",
              CandidateScorer.evidenceSwapWinner(
                  evals: [esEv(hasTotal: true, hasSubtotal: false,
                               e2: false, integrity: 0.1,
                               isOriginal: true),
                          esEv(hasTotal: true, hasSubtotal: true,
                               e2: true, integrity: 0.9)],
                  parses: [esTotalOnly, esFull],
                  fragmentCounts: [10, 200],
                  currentWinner: 0) == 0)
        // ES03 — winner rỗng nhưng KHÔNG ứng viên nào mang số:
        // giữ nguyên (hình ca 22-taco-bell-1).
        check("ES03-khong-ung-vien-mang-so-giu-nguyen",
              CandidateScorer.evidenceSwapWinner(
                  evals: [esEv(hasTotal: false, hasSubtotal: false,
                               e2: false, integrity: 0,
                               isOriginal: true),
                          esEv(hasTotal: false, hasSubtotal: false,
                               e2: false, integrity: 1)],
                  parses: [esEmpty, esEmpty],
                  fragmentCounts: [2, 60],
                  currentWinner: 0) == 0)
        // ES04 — phá hòa trong nhóm mang số: integrity trước,
        // số mảnh sau.
        check("ES04a-hoa-thi-integrity-thang",
              CandidateScorer.evidenceSwapWinner(
                  evals: [esEv(hasTotal: false, hasSubtotal: false,
                               e2: false, integrity: 0,
                               isOriginal: true),
                          esEv(hasTotal: true, hasSubtotal: true,
                               e2: true, integrity: 0.5),
                          esEv(hasTotal: true, hasSubtotal: true,
                               e2: true, integrity: 0.9)],
                  parses: [esEmpty, esFull, esFull],
                  fragmentCounts: [2, 200, 50],
                  currentWinner: 0) == 2)
        check("ES04b-hoa-integrity-thi-nhieu-manh-thang",
              CandidateScorer.evidenceSwapWinner(
                  evals: [esEv(hasTotal: false, hasSubtotal: false,
                               e2: false, integrity: 0,
                               isOriginal: true),
                          esEv(hasTotal: true, hasSubtotal: true,
                               e2: true, integrity: 0.5),
                          esEv(hasTotal: true, hasSubtotal: true,
                               e2: true, integrity: 0.5)],
                  parses: [esEmpty, esFull, esFull],
                  fragmentCounts: [2, 50, 200],
                  currentWinner: 0) == 2)
    }

    // MARK: - Pha 2 (L-2026-11-21-47): hạ cánh bằng thuế
    //
    // TaxLanding.evaluate là hàm THUẦN — các ca dưới đây dựng
    // ParseResult tay và kiểm đúng số học tam giác + luật chọn
    // khu/loại + luật không-ghi-đè của PHASE2-DIFF.md §3.

    private static func tlResult(
        subtotal: Int? = nil, taxAmounts: [Int] = [], total: Int? = nil,
        address: String? = nil, vendor: String? = nil,
        vendorKey: String = "generic",
        items: [ParsedLineItem] = []
    ) -> ParseResult {
        var r = ParseResult()
        r.subtotalCents = subtotal
        r.taxes = taxAmounts.map {
            ParsedTaxLine(label: "TAX", amountCents: $0)
        }
        r.totalCents = total
        r.vendorAddress = address
        r.vendor = vendor
        r.vendorKey = vendorKey
        r.items = items
        return r
    }

    private static func tlContext(
        hints: [String: TaxProfileHint] = [:]
    ) -> TaxLandingContext {
        TaxLandingContext(table: .seed,
                          defaultAreaID: TaxTable.defaultSeedAreaID,
                          profileHints: hints)
    }

    private static func runTaxLandingTests(
        _ check: (String, Bool) -> Void
    ) {
        let tulsaAddr = "1100 S Lewis Ave, Tulsa, OK 74133"

        // TL01: subtotal + suất đầy đủ Tulsa → thuế + total.
        let tl01 = TaxLanding.evaluate(
            tlResult(subtotal: 10000, address: tulsaAddr),
            context: tlContext())
        check("TL01-subtotal-ra-thue-va-total",
              tl01?.result.taxes.first?.amountCents == 852
              && tl01?.result.totalCents == 10852
              && tl01?.report.filledFields.contains("tax[0]") == true
              && tl01?.report.filledFields.contains("total") == true
              && tl01?.report.areaSource == "zip")

        // TL02: total + suất → subtotal + thuế (tam giác ngược).
        let tl02 = TaxLanding.evaluate(
            tlResult(total: 10852, address: tulsaAddr),
            context: tlContext())
        check("TL02-total-ra-subtotal-va-thue",
              tl02?.result.subtotalCents == 10000
              && tl02?.result.taxes.first?.amountCents == 852
              && tl02?.report.areaSource == "zip")

        // TL03: ba phép không cần suất (chỉ số đã đọc).
        let tl03a = TaxLanding.evaluate(
            tlResult(subtotal: 5000, taxAmounts: [400]),
            context: tlContext())
        let tl03b = TaxLanding.evaluate(
            tlResult(taxAmounts: [400], total: 5400),
            context: tlContext())
        let tl03c = TaxLanding.evaluate(
            tlResult(subtotal: 5000, total: 5400),
            context: tlContext())
        check("TL03-tam-giac-khong-can-suat",
              tl03a?.result.totalCents == 5400
              && tl03a?.report.ratePct == nil
              && tl03b?.result.subtotalCents == 5000
              && tl03c?.result.taxes.first?.amountCents == 400
              && tl03c?.result.taxes.first?.rateText == nil)

        // TL04: đủ cả ba đỉnh → không kích hoạt, result nguyên vẹn.
        let tl04 = TaxLanding.evaluate(
            tlResult(subtotal: 5000, taxAmounts: [400], total: 5400,
                     address: tulsaAddr),
            context: tlContext())
        check("TL04-du-ba-dinh-khong-dung",
              tl04?.report.attempted == false
              && tl04?.report.filledFields.isEmpty == true
              && tl04?.result.totalCents == 5400)

        // TL05: không neo nào → không kích hoạt.
        let tl05 = TaxLanding.evaluate(
            tlResult(address: tulsaAddr), context: tlContext())
        check("TL05-khong-neo-khong-dung",
              tl05?.report.attempted == false
              && tl05?.result.totalCents == nil)

        // TL06: trích ZIP từ địa chỉ.
        check("TL06-trich-zip",
              TaxLanding.extractZIP(from: tulsaAddr) == "74133"
              && TaxLanding.extractZIP(from: "không có mã vùng") == nil
              && TaxLanding.extractZIP(from: nil) == nil
              && TaxLanding.extractZIP(
                  from: "ĐT 9185551234, Tulsa, OK 74133") == "74133")

        // TL07: ZIP trong bảng → đúng khu; ZIP ngoài bảng → chặn
        // phép cần suất.
        let tl07a = TaxLanding.evaluate(
            tlResult(subtotal: 10000, address: tulsaAddr),
            context: tlContext())
        let tl07b = TaxLanding.evaluate(
            tlResult(subtotal: 10000,
                     address: "100 Rodeo Dr, Beverly Hills, CA 90210"),
            context: tlContext())
        // TL07c: cùng ZIP ngoài bảng nhưng có subtotal + thuế —
        // phép KHÔNG cần % (Pha A) vẫn chạy và điền total, không
        // bị chặn bởi ZIP (Pha A đứng trước khâu chọn khu).
        let tl07c = TaxLanding.evaluate(
            tlResult(subtotal: 5000, taxAmounts: [400],
                     address: "100 Rodeo Dr, Beverly Hills, CA 90210"),
            context: tlContext())
        check("TL07-zip-trong-bang-va-ngoai-bang",
              tl07a?.report.areaID == "tulsa-tulsa"
              && tl07b?.report.attempted == true
              && tl07b?.report.blockedReason == "zip-ngoai-bang"
              && tl07b?.report.filledFields.isEmpty == true
              && tl07b?.result.totalCents == nil
              && tl07c?.result.totalCents == 5400
              && tl07c?.report.filledFields == ["total"]
              && tl07c?.report.blockedReason == nil)

        // TL08: món thực phẩm → suất thực phẩm (4.017%).
        let tl08 = TaxLanding.evaluate(
            tlResult(subtotal: 10000, address: tulsaAddr,
                     items: [ParsedLineItem(name: "Whole Milk 1gal"),
                             ParsedLineItem(name: "Eggs 12ct")]),
            context: tlContext())
        check("TL08-thuc-pham-suat-thuc-pham",
              tl08?.result.taxes.first?.amountCents == 402
              && tl08?.report.category == .grocery
              && tl08?.report.categorySource == "items")

        // TL09: thuế đọc sẵn không bị ghi đè — chỉ điền subtotal.
        let tl09 = TaxLanding.evaluate(
            tlResult(taxAmounts: [400], total: 5400, address: tulsaAddr),
            context: tlContext())
        check("TL09-khong-ghi-de-thue-doc",
              tl09?.result.subtotalCents == 5000
              && tl09?.result.taxes.count == 1
              && tl09?.result.taxes.first?.amountCents == 400
              && tl09?.report.filledFields == ["subtotal"])

        // TL10: ZIP từ hồ sơ tiệm (cờ profile).
        let tl10 = TaxLanding.evaluate(
            tlResult(subtotal: 10000, vendor: "Sam's Club",
                     vendorKey: "sams"),
            context: tlContext(hints: [
                "sams": TaxProfileHint(zip: "74133", category: nil),
            ]))
        check("TL10-zip-tu-ho-so-tiem",
              tl10?.result.taxes.first?.amountCents == 852
              && tl10?.report.areaSource == "profile"
              && tl10?.report.detail.contains("theo tiệm") == true)

        // TL11: làm tròn nửa lên — 9999 × 8.417% (Broken Arrow
        // 74012) = 841.62… → 842.
        let tl11 = TaxLanding.evaluate(
            tlResult(subtotal: 9999,
                     address: "701 W Kenosha St, Broken Arrow, OK 74012"),
            context: tlContext())
        check("TL11-lam-tron",
              tl11?.result.taxes.first?.amountCents == 842
              && tl11?.report.areaID == "broken-arrow-tulsa")

        // TL12: mất ZIP khắp nơi → khu mặc định Tulsa.
        let tl12 = TaxLanding.evaluate(
            tlResult(subtotal: 10000), context: tlContext())
        check("TL12-khu-mac-dinh-tulsa",
              tl12?.result.taxes.first?.amountCents == 852
              && tl12?.report.areaSource == "default"
              && tl12?.report.areaID == "tulsa-tulsa"
              && tl12?.report.detail.contains("mặc định") == true)

        // TL13: arbiter báo unclosed nhưng tam giác đủ → không điền.
        var tl13in = tlResult(subtotal: 5000, taxAmounts: [400],
                              total: 5400, address: tulsaAddr)
        tl13in.arbiterStatus = "unclosed"
        let tl13 = TaxLanding.evaluate(tl13in, context: tlContext())
        check("TL13-unclosed-nhung-du-dinh-khong-dien",
              tl13?.report.attempted == false
              && tl13?.report.filledFields.isEmpty == true)

        // TL14: tờ trọng tài đã KHÉP + taxes rỗng (tờ miễn thuế,
        // subtotal == total) → KHÔNG kích hoạt, không bịa thuế.
        var tl14in = tlResult(subtotal: 5000, total: 5000,
                              address: tulsaAddr)
        tl14in.arbiterStatus = "closed"
        let tl14 = TaxLanding.evaluate(tl14in, context: tlContext())
        check("TL14-closed-khong-dung",
              tl14?.report.attempted == false
              && tl14?.report.filledFields.isEmpty == true
              && tl14?.result.taxes.isEmpty == true)

        // TL15: subtotal + total đều có, thuế thiếu, total ≤
        // subtotal (số đọc mâu thuẫn) → Pha B KHÔNG bịa thuế theo
        // suất. Hai biến thể: total < sub và total == sub.
        let tl15a = TaxLanding.evaluate(
            tlResult(subtotal: 5000, total: 4800, address: tulsaAddr),
            context: tlContext())
        let tl15b = TaxLanding.evaluate(
            tlResult(subtotal: 5000, total: 5000, address: tulsaAddr),
            context: tlContext())
        check("TL15-sub-total-mau-thuan-khong-bia-thue",
              tl15a?.report.filledFields.isEmpty == true
              && tl15a?.result.taxes.isEmpty == true
              && tl15a?.result.totalCents == 4800
              && tl15b?.report.filledFields.isEmpty == true
              && tl15b?.result.taxes.isEmpty == true)

        // TL16: thuế đọc (500) lớn hơn total (400) → rule 2 không
        // sinh subtotal âm; đỉnh để trống cho Kiểm Lại.
        let tl16 = TaxLanding.evaluate(
            tlResult(taxAmounts: [500], total: 400),
            context: tlContext())
        check("TL16-khong-subtotal-am",
              tl16?.result.subtotalCents == nil
              && tl16?.report.filledFields.isEmpty == true)

        // TL17: detail mang NGUỒN chọn (khu theo ZIP tờ, loại
        // theo món đọc được) — provenance/log giữ được phân biệt.
        let tl17 = TaxLanding.evaluate(
            tlResult(subtotal: 10000, address: tulsaAddr,
                     items: [ParsedLineItem(name: "Whole Milk 1gal")]),
            context: tlContext())
        check("TL17-detail-ghi-nguon",
              tl17?.report.detail.contains("theo ZIP trên tờ") == true
              && tl17?.report.detail.contains("theo món đọc được")
                  == true)

        // TL18: neo duy nhất là dòng thuế → kích hoạt nhưng không
        // đỉnh nào suy được; blockedReason nói rõ, không im lặng.
        let tl18 = TaxLanding.evaluate(
            tlResult(taxAmounts: [400]), context: tlContext())
        check("TL18-neo-thue-don-doc",
              tl18?.report.attempted == true
              && tl18?.report.filledFields.isEmpty == true
              && tl18?.report.blockedReason
                  == "khong-dien-duoc-dinh-nao")
    }

    // MARK: - A7: luật tờ chính thức một nguồn (OfficialReceiptRule)
    //
    // Chứng minh hàm một-nguồn trả ĐÚNG biểu thức chép tay cũ
    // (status == .reviewed && !excludedFromTotals; needsReview &&
    // !excluded; amountPaidCents ?? 0) trên TOÀN BỘ không gian vào,
    // rồi so tổng trước/sau trên cùng một sổ tổng hợp 500 tờ.
    private static func runOfficialRuleTests(_ check: (String, Bool) -> Void) {
        let amounts: [Int?] = [nil, 0, 1, -250, 12345, 999_999_99]
        var truthOK = true
        for reviewed in [true, false] {
            let needsReview = !reviewed
            for excluded in [true, false] {
                if OfficialReceiptRule.isOfficial(isReviewed: reviewed,
                        excludedFromTotals: excluded) != (reviewed && !excluded) {
                    truthOK = false
                }
                if OfficialReceiptRule.isPending(isNeedsReview: needsReview,
                        excludedFromTotals: excluded) != (needsReview && !excluded) {
                    truthOK = false
                }
            }
        }
        check("OR01-bang-chan-tri-khop-bieu-thuc-cu", truthOK)
        check("OR02-countedCents-khop-amountPaid-or-0",
              amounts.allSatisfy { OfficialReceiptRule.countedCents($0) == ($0 ?? 0) })

        // Sổ tổng hợp tất định (LCG) — 3 loại × 2 trạng thái ×
        // loại/không loại × số tiền có/không.
        struct Row { var kind: Int; var reviewed: Bool; var excluded: Bool; var paid: Int? }
        var seed: UInt64 = 0x5EED_A7
        func next() -> UInt64 {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return seed >> 33
        }
        var rows: [Row] = []
        for _ in 0..<500 {
            let paid: Int? = next() % 7 == 0 ? nil : Int(next() % 50_000) - 1_000
            rows.append(Row(kind: Int(next() % 3), reviewed: next() % 2 == 0,
                            excluded: next() % 5 == 0, paid: paid))
        }
        var sameTotals = true
        for kind in 0..<3 {
            let old = rows.filter { $0.kind == kind && $0.reviewed && !$0.excluded }
                .reduce(0) { $0 + ($1.paid ?? 0) }
            let new = rows.filter {
                $0.kind == kind && OfficialReceiptRule.isOfficial(
                    isReviewed: $0.reviewed, excludedFromTotals: $0.excluded)
            }.reduce(0) { $0 + OfficialReceiptRule.countedCents($1.paid) }
            if old != new { sameTotals = false }
        }
        let oldPending = rows.filter { !$0.reviewed && !$0.excluded }
            .reduce(0) { $0 + ($1.paid ?? 0) }
        let newPending = rows.filter {
            OfficialReceiptRule.isPending(isNeedsReview: !$0.reviewed,
                                          excludedFromTotals: $0.excluded)
        }.reduce(0) { $0 + OfficialReceiptRule.countedCents($1.paid) }
        check("OR03-tong-truoc-sau-cung-so-500-to",
              sameTotals && oldPending == newPending)
    }

    // MARK: - A6: hạn lưu giữ 7 năm tất định
    private static func runRetentionPolicyTests(_ check: (String, Bool) -> Void) {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let d2026 = RetentionPolicy.retentionUntil(taxYear: 2026)
        check("RP01-2026-ra-2033-12-31Z",
              d2026.map { iso.string(from: $0) } == "2033-12-31T00:00:00Z")
        check("RP02-tat-dinh-hai-lan-goi",
              RetentionPolicy.retentionUntil(taxYear: 2019)
                == RetentionPolicy.retentionUntil(taxYear: 2019))
        check("RP03-nam-cua-han", d2026.map { RetentionPolicy.year(of: $0) } == 2033)
        let now = iso.date(from: "2026-11-22T12:00:00Z")!
        let past = iso.date(from: "2025-12-31T00:00:00Z")!
        let soon = iso.date(from: "2027-06-30T00:00:00Z")!
        let far = iso.date(from: "2030-12-31T00:00:00Z")!
        check("RP04-nguong-12-thang",
              RetentionPolicy.reachesHorizon(retentionUntil: past, now: now)
              && RetentionPolicy.reachesHorizon(retentionUntil: soon, now: now)
              && !RetentionPolicy.reachesHorizon(retentionUntil: far, now: now))
    }

    // MARK: - A1: planner khôi phục Drive
    private static func runRestorePlannerTests(_ check: (String, Bool) -> Void) {
        func e(_ id: String, _ status: String = "active", hash: String = "h1",
               folder: Bool = true, deleted: Bool = false) -> RestoreRemoteEntry {
            RestoreRemoteEntry(id: id, status: status, contentHash: hash,
                               hasReceiptFolder: folder, inDeletedFolder: deleted)
        }
        check("RS01-chua-co-tren-may-thi-khoi-phuc",
              RestorePlanner.decide(e("a"), localHashes: [:]) == .restore)
        check("RS02-cung-hash-bo-qua-idempotent",
              RestorePlanner.decide(e("a"), localHashes: ["a": "h1"]) == .alreadyPresent)
        check("RS03-khac-hash-la-xung-dot-khong-ghi-de",
              RestorePlanner.decide(e("a"), localHashes: ["a": "h9"])
                == .conflict(localHash: "h9", remoteHash: "h1"))
        check("RS04-manifest-deleted-khong-ve",
              RestorePlanner.decide(e("a", "deleted"), localHashes: [:]) == .skipDeleted)
        check("RS05-thu-muc-o-_deleted-khong-ve",
              RestorePlanner.decide(e("a", deleted: true), localHashes: [:]) == .skipDeleted)
        check("RS06-mat-thu-muc-to",
              RestorePlanner.decide(e("a", folder: false), localHashes: [:]) == .skipNoFolder)
        // Idempotent hai lượt: lượt 1 khôi phục -> máy có hash -> lượt 2 bỏ qua hết.
        let entries = [e("a"), e("b", hash: "h2"), e("c", "deleted")]
        let pass1 = entries.map { RestorePlanner.decide($0, localHashes: [:]) }
        var local: [String: String] = [:]
        for (en, d) in zip(entries, pass1) where d == .restore { local[en.id] = en.contentHash }
        let pass2 = entries.map { RestorePlanner.decide($0, localHashes: local) }
        check("RS07-chay-hai-lan-khong-sinh-ban-trung",
              pass1.filter { $0 == .restore }.count == 2
              && pass2.filter { $0 == .restore }.isEmpty)
        check("RS08-manifest-trung-id-giu-muc-cuoi",
              RestorePlanner.dedupeLastWins([e("a", hash: "old"), e("b"), e("a", hash: "new")])
                .map { $0.contentHash } == ["new", "h1"])
        check("RS09-file-dich-khac-byte-la-xung-dot",
              RestorePlanner.fileDecision(localSHA256: "x", downloadedSHA256: "y") == .conflict
              && RestorePlanner.fileDecision(localSHA256: "y", downloadedSHA256: "y") == .reuseIdentical
              && RestorePlanner.fileDecision(localSHA256: nil, downloadedSHA256: "y") == .write)
        check("RS10-ten-file-khong-an-toan-bi-tu-choi",
              RestorePlanner.isSafeFileName("A1B2.jpg")
              && !RestorePlanner.isSafeFileName("../x.jpg")
              && !RestorePlanner.isSafeFileName("a/b.jpg")
              && !RestorePlanner.isSafeFileName("")
              && !RestorePlanner.isSafeFileName(".hidden"))
        check("RS11-kiem-byte-tai-ve",
              RestorePlanner.downloadVerified(byteCount: 10, expectedMD5: "AB",
                                              actualCount: 10, actualMD5: "ab")
              && !RestorePlanner.downloadVerified(byteCount: 10, expectedMD5: nil,
                                                  actualCount: 9, actualMD5: "ab")
              && !RestorePlanner.downloadVerified(byteCount: nil, expectedMD5: "ab",
                                                  actualCount: 9, actualMD5: "cd")
              && !RestorePlanner.downloadVerified(byteCount: nil, expectedMD5: nil,
                                                  actualCount: 9, actualMD5: "cd"))
        let tally = RestoreTally.byYear([(2025, 100), (2026, 250), (2025, nil), (2026, 1)])
        check("RS12-tong-theo-nam",
              tally == [RestoreYearLine(year: 2025, count: 2, totalCents: 100),
                        RestoreYearLine(year: 2026, count: 2, totalCents: 251)])
    }

    // MARK: - A2 + A3: lõi xuất (ZIP / CSV / mục lục / phép tính Báo Cáo)
    private static func runExportKitTests(_ check: (String, Bool) -> Void) {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("glk-ex-\(UUID().uuidString)")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        check("EX01-crc32-chuan", CRC32.checksum(Data("123456789".utf8)) == 0xCBF4_3926)
        check("EX02-dollars-phep-nguyen",
              ExportCSV.dollars(23411) == "234.11" && ExportCSV.dollars(5) == "0.05"
              && ExportCSV.dollars(-50) == "-0.50" && ExportCSV.dollars(0) == "0.00"
              && ExportCSV.dollars(nil) == ""
              && [0, 5, 100, 23411, -50, 999_999_99].allSatisfy {
                  ExportCSV.cents(fromDollars: ExportCSV.dollars($0)) == $0 })
        let tricky = ["a,b", "say \"hi\"", "line1\nline2", "Cà phê đ"]
        let doc = ExportCSV.document(header: ["x", "y"], rows: [tricky, ["1", ""]])
        check("EX03-csv-khu-hoi", ExportCSV.parse(doc) == [["x", "y"], tricky, ["1", ""]])

        // ZIP khứ hồi: nhị phân ngẫu nhiên, file rỗng, tên UTF-8, file ~3 MB.
        var seed: UInt64 = 42
        func rnd(_ n: Int) -> Data {
            Data((0..<n).map { _ -> UInt8 in
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return UInt8(truncatingIfNeeded: seed >> 56) })
        }
        let blobs: [(String, Data)] = [("goc/a.jpg", rnd(4321)), ("goc/rong.pdf", Data()),
                                       ("goc/Cà-phê_đá.jpg", rnd(17)), ("goc/lon.jpg", rnd(3_000_000))]
        let zurl = dir.appendingPathComponent("t.zip")
        var zipOK = false
        do {
            let w = try ZipWriter(url: zurl, date: Date(timeIntervalSince1970: 1_700_000_000))
            for (n, d) in blobs { try w.add(name: n, data: d) }
            try w.finish()
            zipOK = true
        } catch {
            zipOK = false
        }
        let back = (try? Data(contentsOf: zurl)).flatMap { try? ZipReader.entries(of: $0) }
        check("EX04-zip-khu-hoi-dung-byte",
              zipOK && back == blobs.map { ZipReader.Entry(name: $0.0, data: $0.1) })
        // Đối chứng ĐỘC LẬP bằng /usr/bin/unzip của macOS.
        func unzip(_ args: [String]) -> (Int32, Data) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            p.arguments = args
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = Pipe()
            do { try p.run() } catch { return (-1, Data()) }
            let out = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return (p.terminationStatus, out)
        }
        let (tStatus, _) = unzip(["-tq", zurl.path])
        let (pStatus, pData) = unzip(["-p", zurl.path, "goc/lon.jpg"])
        check("EX05-usr-bin-unzip-test-va-giai-nen-dung-byte",
              tStatus == 0 && pStatus == 0 && pData == blobs[3].1)
        if let w = try? ZipWriter(url: dir.appendingPathComponent("d.zip")) {
            try? w.add(name: "x", data: Data([1]))
            var dupRefused = false
            do { try w.add(name: "x", data: Data([2])) } catch { dupRefused = true }
            var badRefused = false
            do { try w.add(name: "../x", data: Data([2])) } catch { badRefused = true }
            check("EX06-tu-choi-ten-trung-va-ten-thoat-thu-muc", dupRefused && badRefused)
        }

        // Mục lục kế toán: tờ thiếu file được ĐẾM + ĐỌC TÊN.
        func input(_ id: String, kind: String = "business", official: Bool = true,
                   paid: Int = 1000, line: String? = nil, files: [ExportFileRef],
                   year: Int = 2026, est: Set<String> = [], known: Bool = true) -> ExportReceiptInput {
            ExportReceiptInput(id: id, date: Date(timeIntervalSince1970: 1_767_225_600 + Double(id.count) * 86_400),
                               reportYear: year, vendor: "Tiệm \(id)", kindRaw: kind, kindNormalized: kind,
                               isOfficial: official, isPending: !official, isNeedsReview: !official,
                               category: "Mục", scheduleCLine: line, subtotalCents: nil, taxCents: nil,
                               totalCents: paid, countedCents: paid, tipCents: nil, cardLast4: "2586",
                               businessPurpose: "", estimatedFields: est, provenanceKnown: known,
                               originals: files)
        }
        let a = input("AAAA1111", files: [ExportFileRef(localName: "x.jpg", data: Data([1, 2, 3]))])
        let b = input("BBBB2222", files: [ExportFileRef(localName: "y.jpg", data: nil)])
        let c = input("CCCC3333", files: [])
        let murl = dir.appendingPathComponent("m.zip")
        var summary: AccountantExport.Summary? = nil
        if let w = try? ZipWriter(url: murl) {
            summary = try? AccountantExport.write([a, b, c], into: w)
            try? w.finish()
        }
        let mEntries = (try? Data(contentsOf: murl)).flatMap { try? ZipReader.entries(of: $0) } ?? []
        let index = mEntries.first { $0.name == AccountantExport.indexName }
            .map { ExportCSV.parse($0.data) } ?? []
        let missingRows = index.filter { $0.last?.hasPrefix("THIEU") == true }
        check("EX07-muc-luc-dem-va-goi-ten-file-thieu",
              summary?.filesIncluded == 1 && summary?.filesMissing == 2
              && summary?.receiptsWithMissing == ["BBBB2222", "CCCC3333"]
              && missingRows.count == 2
              && missingRows.contains { $0[1] == "BBBB2222" && $0[11] == "y.jpg" }
              && missingRows.contains { $0[1] == "CCCC3333" }
              && index.last?.first == "TONG"
              && mEntries.contains { $0.data == Data([1, 2, 3]) })

        // TaxReportMath == thuật toán cũ của ReportsView (tham chiếu chép lại).
        var rows: [ExportReceiptInput] = []
        var s2: UInt64 = 7
        func r2() -> Int { s2 = s2 &* 6364136223846793005 &+ 1442695040888963407; return Int(s2 >> 40) }
        let kinds = ["personal", "business", "unknown"]
        let cats = ["", "Ăn uống", "Vật Tư (Supplies)", "Xăng"]
        for i in 0..<300 {
            let reviewed = r2() % 2 == 0, excluded = r2() % 6 == 0
            var x = input("R\(i)", kind: kinds[r2() % 3], official: reviewed && !excluded,
                          paid: r2() % 40_000 - 500, files: [])
            x.isPending = !reviewed && !excluded
            x.isNeedsReview = !reviewed
            x.category = cats[r2() % 4]
            rows.append(x)
        }
        let t = TaxReportMath.totals(rows)
        let refP = rows.filter { $0.kindNormalized == "personal" && $0.isOfficial }.reduce(0) { $0 + $1.countedCents }
        let refB = rows.filter { $0.kindNormalized == "business" && $0.isOfficial }.reduce(0) { $0 + $1.countedCents }
        let refU = rows.filter { $0.kindNormalized == "unknown" && $0.isOfficial }.reduce(0) { $0 + $1.countedCents }
        let refPend = rows.filter { $0.isPending }.reduce(0) { $0 + $1.countedCents }
        var refGroups: [String: (String, Int, Int)] = [:]
        for r in rows where r.kindNormalized != "unknown" && r.isOfficial {
            let key = "\(r.kindRaw)|\(r.category.isEmpty ? "Khác" : r.category)"
            let o = refGroups[key] ?? (r.kindNormalized, 0, 0)
            refGroups[key] = (r.kindNormalized, o.1 + r.countedCents, o.2 + 1)
        }
        let cr = TaxReportMath.categoryRows(rows)
        check("EX08-taxreportmath-bang-thuat-toan-cu",
              t.personal == refP && t.business == refB && t.unknown == refU && t.pending == refPend
              && t.count == 300 && t.needsReviewCount == rows.filter { $0.isNeedsReview }.count
              && cr.count == refGroups.count
              && cr.allSatisfy { row in
                  guard let g = refGroups[row.key] else { return false }
                  return g.1 == row.total && g.2 == row.count }
              && zip(cr, cr.dropFirst()).allSatisfy { x, y in
                  x.kindNormalized == y.kindNormalized ? x.total >= y.total
                      : (x.kindNormalized == "business") })

        // Tax Pack CSV: chỉ tờ chính thức, cộng lại khớp tổng; Schedule C
        // không bịa; nhãn ƯỚC TÍNH giữ nguyên.
        let (csv, official) = TaxPackCSV.document(rows)
        check("EX09-taxpack-csv-khop-tong-den-cent",
              TaxPackCSV.verify(csv, against: t)
              && official.allSatisfy { $0.isOfficial }
              && official.count == rows.filter { $0.isOfficial }.count)
        var off = t; off.business += 1
        check("EX10-lech-1-cent-thi-tu-choi", !TaxPackCSV.verify(csv, against: off))
        let withLine = input("L1", line: "Line 22 — Supplies", files: [])
        let noLine = input("L2", files: [], est: ["tax"])
        let unknownSrc = input("L3", files: [], known: false)
        let (csv2, _) = TaxPackCSV.document([withLine, noLine, unknownSrc])
        let parsed = ExportCSV.parse(csv2)
        let sc = parsed.first!.firstIndex(of: "schedule_c")!
        let srcTax = parsed.first!.firstIndex(of: "nguon_thue")!
        let byID = Dictionary(uniqueKeysWithValues: parsed.dropFirst().map { ($0[1], $0) })
        let summ = TaxPackCSV.scheduleCSummary([withLine, noLine])
        check("EX11-khong-bia-dong-schedule-c",
              byID["L1"]?[sc] == "Line 22 — Supplies" && byID["L2"]?[sc] == ""
              && summ.lines.count == 1 && summ.unassignedCount == 1)
        check("EX12-nhan-uoc-tinh-va-khong-ro-nguon",
              byID["L2"]?[srcTax] == EstimateRule.label
              && byID["L1"]?[srcTax] == "doc/nhap"
              && byID["L3"]?[srcTax] == "khong_ro_nguon")
        check("EX13-luat-uoc-tinh-than-trong",
              EstimateRule.estimatedFields(landingFlag: true, rawSubtotalMissing: true,
                                           rawTaxMissing: true, rawTotalMissing: false,
                                           userEntered: ["subtotal"]) == ["tax"]
              && EstimateRule.estimatedFields(landingFlag: false, rawSubtotalMissing: true,
                                              rawTaxMissing: true, rawTotalMissing: true,
                                              userEntered: []).isEmpty)
    }

    // MARK: - A4: tờ PDF Costco đọc RỖNG tên tiệm (ca thật 2026-11-22)
    //
    // LƯU Ý TRUNG THỰC: chữ trích của tờ PDF thật KHÔNG có trong repo.
    // Đây là bản DỰNG LẠI TỔNG HỢP từ các dữ kiện Leader ghi về tờ đó
    // (subtotal 221.14 · thuế 12.97 · total 234.11 · thẻ •• 2586 · địa
    // chỉ 10220 S MEMORIAL DR · không có dòng tên COSTCO) theo khuôn
    // tờ Costco Tulsa #1207 có thật trong corpus (L-R01). Chạy ĐÚNG
    // đường app: ReceiptReader.read nguồn pdfTextLayer, confidence 1.0
    // như ScanView.textLayerLines.
    private static func runCostcoPDFVendorTests(_ check: (String, Bool) -> Void) {
        guard VendorData.shared.dataVersion != "unloaded" else {
            check("A4-00-vendors-json-phai-nap-duoc", false)
            return
        }
        func read(_ text: String) -> ParseResult {
            let lines = text.split(separator: "\n").map {
                OCRLine(text: String($0), confidence: 1.0)
            }
            return ReceiptReader.read(ReadRequest(
                source: .pdfTextLayer, imageFileName: "A4-SYNTH.pdf",
                textLines: lines)).result
        }
        let body = """
        Member 111987102109
        1811598 H&S SHAMPOO 89.99 A
        2008132 ALWAYS FLEX 45.49 A
        2218587 SWIFFER DUST 33.97 A
        5161251 UNSTPBL FRSH 24.99 A
        1840548 DOWNY FABRIC 16.71 A
        112266 PANETTONE 9.99 F
        SUBTOTAL 221.14
        TAX 12.97
        **** TOTAL 234.11
        XXXXXXXXXXXX2586
        APPROVED - Purchase
        AMOUNT: $234.11
        TOTAL NUMBER OF ITEMS SOLD = 6
        11/20/2026 14:17
        """
        let synth = "10220 S MEMORIAL DR\nTULSA, OK 74133\n" + body
        let r = read(synth)
        let tag = "vendor=\(r.vendor ?? "nil")·src=\(r.vendorSource ?? "nil")"
            + "·sub=\(r.subtotalCents.map(String.init) ?? "nil")"
            + "·tax=\(r.taxTotalCents)·total=\(r.totalCents.map(String.init) ?? "nil")"
            + "·card=\(r.cardLast4 ?? "nil")"
        check("A4-01-costco-pdf-ten-tiem-tu-neo-dia-chi[\(tag)]",
              r.vendor?.uppercased() == "COSTCO" && r.vendorSource == "tier2-anchor")
        check("A4-02-so-tien-giu-nguyen-221.14-12.97-234.11[\(tag)]",
              r.subtotalCents == 22114 && r.taxTotalCents == 1297
              && r.totalCents == 23411 && r.cardLast4 == "2586")
        // Không neo nào -> KHÔNG đoán tên tiệm (để trống cho anh duyệt).
        let none = read("TULSA, OK 74133\n" + body)
        check("A4-03-khong-neo-thi-khong-doan[vendor=\(none.vendor ?? "nil")]",
              none.vendor == nil)
        // Số nhà lệch một chữ số -> không phải kho này -> không đoán.
        let near = read("10221 S MEMORIAL DR\nTULSA, OK 74133\n" + body)
        check("A4-04-dia-chi-gan-giong-khong-du[vendor=\(near.vendor ?? "nil")]",
              near.vendor == nil)
        // Neo cũ vẫn đúng: tờ có dòng tên COSTCO giữ nấc 1.
        let named = read("COSTCO\nWHOLESALE\nTulsa #1207\n10220 S. Memorial Drive\n" + body)
        check("A4-05-co-ten-in-van-la-nac-1[src=\(named.vendorSource ?? "nil")]",
              named.vendor == "Costco" && named.vendorSource == "tier1-exact")
    }

    // MARK: - A10 (vòng 2): nét tiệm vượt v1 — CHỈ GỢI Ý

    static func runStoreTraitsTests(_ check: (String, Bool) -> Void) {
        let text = "COSTCO\nWHOLESALE\n1234567 MILK\n7654321 EGGS\nSUBTOTAL 100.00\nTAX 8.52\nTOTAL 108.52\nVISA"
        let o = StoreTraits.observe(rawText: text, subtotalCents: 10000, taxCents: 852,
                                    taxLabels: ["TAX "], category: "Groceries",
                                    taxCategoryRaw: "food")
        // 8 dòng; 2 dòng mở bằng >= 6 chữ số; TOTAL cuối ở dòng 6 -> 6*100/7.
        check("ST01-quan-sat-tat-dinh[lines=\(o.lineCount) code=\(o.itemCodeLinePct) tot=\(o.totalLinePct.map(String.init) ?? "nil") rate=\(o.taxRatePer100k.map(String.init) ?? "nil")]",
              o.lineCount == 8 && o.itemCodeLinePct == 25 && o.totalLinePct == 85
              && o.taxRatePer100k == 8520 && o.taxLabels == ["TAX"])
        // Một tờ chưa đủ làm "thói quen" -> không gợi ý.
        let one = StoreTraits.merge(nil, o)
        check("ST02-mot-to-chua-goi-y", StoreTraits.suggestions(one).isEmpty)
        // Hai tờ -> có gợi ý, MỌI dòng mang nhãn "theo tiệm".
        let two = StoreTraits.merge(one, o)
        let sug = StoreTraits.suggestions(two)
        check("ST03-moi-goi-y-mang-nhan-theo-tiem[n=\(sug.count)]",
              !sug.isEmpty && sug.allSatisfy { $0.contains(StoreTraits.flag) })
        check("ST04-suat-thue-hien-dung-8.520%",
              sug.contains { $0.contains("8.520%") })
        // Cửa sổ trượt giữ tối đa `window` quan sát số.
        var many: StoreTraitsSummary? = nil
        for _ in 0..<(StoreTraits.window + 5) { many = StoreTraits.merge(many, o) }
        check("ST05-cua-so-truot[\(many?.ratesPer100k.count ?? -1)]",
              many?.ratesPer100k.count == StoreTraits.window
              && many?.observations == StoreTraits.window + 5)
        // Thiếu tạm tính -> không bịa suất thuế.
        let noSub = StoreTraits.observe(rawText: text, subtotalCents: nil, taxCents: 852,
                                        taxLabels: [], category: nil, taxCategoryRaw: nil)
        check("ST06-thieu-tam-tinh-khong-bia-suat", noSub.taxRatePer100k == nil)
        // Bản tóm tắt nét tiệm giải mã được từ JSON đã lưu. (StoreProfile
        // v1 nằm ở StoreProfiles.swift — chỉ target app — trường traits
        // là Optional nên file v1 cũ không có khoá này vẫn giải mã; điều
        // đó dựa trên giải mã tổng hợp của Swift, harness không kiểm.)
        let decoded = try? JSONDecoder().decode(StoreTraitsSummary.self,
                                                from: Data(#"{"observations":3,"lineCounts":[],"itemCodeLinePcts":[],"totalLinePcts":[],"ratesPer100k":[],"taxLabelCounts":{},"categoryCounts":{},"taxCategoryCounts":{}}"#.utf8))
        check("ST07-tom-tat-giai-ma-duoc", decoded?.observations == 3)
    }

    // MARK: - A12(iv) (vòng 2): nhật ký hồ sơ — chỉ đọc

    static func runAuditTrailTests(_ check: (String, Bool) -> Void) {
        let d0 = Date(timeIntervalSince1970: 0)
        let d1 = Date(timeIntervalSince1970: 86_400)
        func fmt(_ d: Date) -> String { d == d0 ? "D0" : "D1" }
        let r = AuditTrail.rows(createdAt: d0, sourceLabel: AuditTrail.sourceLabel("pdfImport"),
                                sourceFileName: "a.pdf", parserVersion: "core-v4-4",
                                isReviewed: true, reviewedAt: d1,
                                userEnteredFieldNames: ["vendor", "total", "vendor", "zzz"],
                                duplicateOfStableID: nil, formatDate: fmt)
        check("AT01-hang-co-dinh-thu-tu",
              r.map(\.label) == ["Tạo lúc", "Nguồn nạp", "Bộ đọc", "Duyệt lúc", "Anh nhập / sửa tay"])
        check("AT02-gia-tri-dung", r[0].value == "D0" && r[1].value == "File PDF · a.pdf"
              && r[3].value == "D1")
        check("AT03-bo-lap-giu-thu-tu-ten-la-nguyen-van",
              r[4].value == "Tên tiệm, Tổng, zzz")
        let old = AuditTrail.rows(createdAt: d0, sourceLabel: "x", sourceFileName: nil,
                                  parserVersion: "", isReviewed: true, reviewedAt: nil,
                                  userEnteredFieldNames: [], duplicateOfStableID: "S1",
                                  formatDate: fmt)
        check("AT04-to-doi-cu-khong-bia-thoi-diem",
              old[3].value.contains("không có dấu thời điểm")
              && old[4].value == "không trường nào"
              && old.last?.value == "S1")
    }

    // MARK: - A12(iii) (vòng 2): cảnh báo sẵn sàng năm thuế

    static func runReadinessTests(_ check: (String, Bool) -> Void) {
        func r(_ id: String, kind: String, official: Bool, pending: Bool) -> ExportReceiptInput {
            ExportReceiptInput(id: id, date: Date(timeIntervalSince1970: 0), reportYear: 2026,
                               vendor: id, kindRaw: kind, kindNormalized: kind,
                               isOfficial: official, isPending: pending, isNeedsReview: pending,
                               category: "", scheduleCLine: nil, subtotalCents: nil, taxCents: nil,
                               totalCents: 100, countedCents: 100, tipCents: nil, cardLast4: nil,
                               businessPurpose: "", estimatedFields: [], provenanceKnown: true,
                               originals: [])
        }
        let rows = [
            r("ok-b", kind: "business", official: true, pending: false),
            r("ok-p", kind: "personal", official: true, pending: false),
            r("unk", kind: "unknown", official: true, pending: false),     // thiếu: chưa phân loại
            r("pend", kind: "business", official: false, pending: true),   // thiếu: chờ duyệt
            r("excl", kind: "unknown", official: false, pending: false),   // đã loại khỏi tổng: không tính
        ]
        check("RD01-dem-cho-duyet-cong-chua-phan-loai[\(TaxReportMath.readinessGapCount(rows))]",
              TaxReportMath.readinessGapCount(rows) == 2)
        check("RD02-du-sach-thi-0",
              TaxReportMath.readinessGapCount(Array(rows.prefix(2))) == 0)
    }

    // MARK: - A11(iii) (vòng 2): trường tin cậy thấp + cờ kế tiếp

    static func runReviewConfidenceTests(_ check: (String, Bool) -> Void) {
        check("RC01-chi-tin-hieu-thap-moi-to",
              ReviewConfidence.lowFields(vendor: 0.5, date: 0.9, total: 0.84) == ["vendor", "total"])
        check("RC02-khong-tin-hieu-0-khong-to-va-0.85-khong-to",
              ReviewConfidence.lowFields(vendor: 0, date: 0.85, total: 1).isEmpty)
        let t = ["flags", "vendor", "total"]
        check("RC03-cờ-ke-tiep-xoay-vong",
              ReviewConfidence.nextTarget(targets: t, after: nil) == "flags"
              && ReviewConfidence.nextTarget(targets: t, after: "flags") == "vendor"
              && ReviewConfidence.nextTarget(targets: t, after: "total") == "flags"
              && ReviewConfidence.nextTarget(targets: t, after: "gone") == "flags"
              && ReviewConfidence.nextTarget(targets: [], after: nil) == nil)
    }
}
