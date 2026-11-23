# OPTIMIZATION-AUDIT.md — GL-Keeper (Sohoadon-claude-opt), baseline `v3` @ 84dfa00

Round 1 audit. Read-only analysis of the code on `v3`. Every claim below is
tied to `file:line` on that commit. Where the code and `HOW-IT-WORKS.md`
disagree, the code wins and the disagreement is listed in §5.

Tooling note: this audit was produced in a Linux workspace with **no Swift
toolchain and no device**. Nothing here was compiled or run locally. Image
sizes in §3 were measured with Python/PIL on the repo's own `BenchImages/`
(43 files). Runtime numbers must come from the measurement methods given per
item (bench app / GitHub Actions build / DiagLog on the owner's phone).

---

## 1. Map of the app

### 1.1 Targets (project.yml)
| Target | Bundle | Deploy | Sources | Notes |
|---|---|---|---|---|
| `SoHoaDon` (GL-Keeper) | `com.nje.sohoadon` | iOS 17.0, Swift 5.9 | app layer + shared read core | `SWIFT_ACTIVE_COMPILATION_CONDITIONS: GLKEEPER_V4_ONLY GLKEEPER_APP` (project.yml) |
| `SoHoaDonBench` | `com.nje.sohoadon.bench` | iOS 26.0 | `BenchApp/BenchView/BenchSelfCheck` + shared read core + `PendingDraft/ReceiptLogic` + `BenchImages/*` | no app model/UI layer |
| Harness (macOS, `harness/project-harness.yml`) | — | — | shared read core + `PendingDraft/ReceiptLogic/ImageIntegrity` + `harness/HarnessApp` | **does not** compile `Models.swift`, `ReceiptViews.swift`, `ScanView.swift`, `HomeView.swift` |

CI: `.github/workflows/build-ipa.yml` (push to `v3` + manual) builds both
schemes and uploads two unsigned IPAs; it does **not** run the harness.
`.github/workflows/harness-ci.yml` is manual-dispatch only.

### 1.2 Modules (by responsibility)
- **App shell**: `SoHoaDonApp.swift` (ModelContainer for `Receipt, LineItem, CardTail, TaxLine`, :14) → `ContentView.swift` (Face ID overlay, :61-120) → `TabShellView` (5 tabs, :208-229; launch tasks :231-247; foreground tasks :248-264).
- **Model / storage**: `Models.swift` (`@Model` classes :163-389; `ImageStore` :476-547). `ImageIntegrity.swift` (OriginalVault mirror copy + launch audit). `PendingDraft.swift` (draft persistence). `StoreProfiles.swift`, `TaxSettings.swift`.
- **Capture**: `ScanView.swift` (entry for camera / VisionKit scanner / photo library / Files / open-in), `ScanCameraView.swift` (custom camera), `FlatScan.swift` (flattened scan sidecar).
- **Read core (shared with bench + harness)**: `ReadPipeline.swift` (`ReceiptReader.read`, :860), `CaptureIntake.swift` (candidate chain :69-96, quality gate, luminance grid), `OCREngine.swift` (`ClassicTextEngine` :120, `DocumentsEngine` :208), `LineAssembly.swift`, `Parser.swift` (v4 parser; v3 paths compiled out of the app by `#if !GLKEEPER_V4_ONLY`), `Candidates.swift`, `ItemCandidates.swift`, `Arbiter.swift`, `Reconcile.swift`, `RegionReReader.swift`, `TaxLanding.swift` + `TaxSeed.swift`, `VendorData.swift`, `Money.swift`, `ReadDiagnostics.swift`.
- **Review / approval / list UI**: `ReceiptViews.swift` (`ReceiptRowView` :274, `ReceiptListView` :339, `ReceiptDetailView` :502, `ReviewView` :1753), `ReceiptLogic.swift` (pure flags + approval gate :273-279), `HomeView.swift` (Home + `ReportsView` :327), `CardsView.swift` (cards & settings).
- **Sync**: `MirrorSync.swift` (Files-folder mirror; snapshot DTO :147-231 shared with Drive), `DriveSync.swift` (OAuth PKCE, Drive REST, engine :978-2240).
- **Diagnostics**: `Diagnostics.swift` (`DiagLog`, 512 KB rotating file, export).

### 1.3 Data flow: scan → parse → totals → approval → Drive
1. **Capture** — `ScanView.process(scan:)` :513 / `process(cameraImages:)` :546 / `process(image:)` :612. Each page is saved first via `ImageStore.saveJPEG` (Models.swift:486; JPEG q0.8 re-encode + `OriginalVault.backfill` copy, :494-495) **on the main thread**, then `ReceiptReader.uprightCGImage` (ReadPipeline.swift:908) redraws non-`.up` images at full pixel size, also on main.
2. **Flatten** (camera/scanner only) — background queue, `FlatScan.makeFlatImage` (ScanView.swift:584-596).
3. **Read** — `runRead` dispatches `ReceiptReader.read` to `.userInitiated` (ScanView.swift:660-661). `finishImagePath` (ReadPipeline.swift:1086) runs the candidate chain `original → perspective → (dewarp: not implemented) → shadowRemoved → enhancedContrast → enhancedDocument (off in app, :843) → binarized (only if no E1 close)` (:1099-1170), each a full-image `.accurate` Vision pass (`runCandidate` :1364-1373, OCREngine.swift:155-171). Optional tiled rescue (:1189-1203). Winner chosen by `CandidateScorer` (:1205-1221); loser images released (:1227-1241). Then QualityMap, ROI re-reads (`RegionReReader`), arbiter, reconcile, tax landing, diagnostics written to `ImageStore.directory`.
4. **Totals / reconcile** — `ReadPipeline.run` + `runArbiter` (:135, :288) → `Reconcile.swift` produces `ReconcileReport` + flags.
5. **Review** — `ReviewView` (ReceiptViews.swift:1753) shows image + fields; save inserts `Receipt` + `LineItem`s (:1552, :2787), computes flags via `ReceiptLogic.flags` (:2762-2772).
6. **Approval** — `ReceiptDetailView` uses `receiptFlags` (:963) → `ReceiptLogic.approvalGate` (:1066; ReceiptLogic.swift:273): no flags → approve; arithmetic/missing-field flags → approve **with explicit confirmation** (`confirmedWithFlag`); missing original image → blocked.
7. **Totals shown** — Home (HomeView.swift:13-66), Reports (:327-370), list (ReceiptViews.swift:380-397): "official" = `status == .reviewed && !excludedFromTotals`, summed on `amountPaidCents`.
8. **Sync** — every save/delete point calls `MirrorSync.requestSync` + `DriveSync.requestSync` (28 call sites: ReceiptViews 14, CardsView 9, ContentView 4, ImageIntegrity 1). Each fetches **all** receipts and builds snapshots on the caller's (main) thread (MirrorSync.swift:481-490, DriveSync.swift:978-986), then runs a serial pass on its own queue. Drive pass: token → folders → remote state → per receipt `processOne` (DriveSync.swift:1434) → deletions → manifest upload.
9. **Launch / foreground** — `ImageIntegrity.runLaunchAudit` (ImageIntegrity.swift:426) fetches all receipts on main, lists both image directories on `auditQueue`, then fires both sync triggers (ContentView.swift:240-246, 258-263).

---

## 2. Top 10 optimization opportunities (impact order)

Measurement tools that already exist in the repo:
- **Bench app**: `BenchSelfCheck` records per-image `elapsedMs` and reports p50/p95/max (BenchSelfCheck.swift:250, :704-766); `outcome.diagnostics.outcome.elapsedMs` is written by the real pipeline (ReadPipeline.swift:1935).
- **Harness CI** (manual): runs `ReceiptReader.read` over 43 images × 10 sets plus ROI gate, fuzz and unit tests.
- **build-ipa** (push to v3 / manual dispatch): proves both targets compile; prints IPA size (`ls -lh`).
- **DiagLog** on device: millisecond timestamps (Diagnostics.swift:69-74). Drive pass logs start/end lines.
- Xcode Instruments/Memory Graph on the owner's phone: not reachable from CI; listed as unverified where needed.

### #1 List & Home rows decode the full original photo to draw a 46×58 thumbnail
- **Evidence**: `ReceiptRowView.body` calls `ImageStore.load` (ReceiptViews.swift:286-289), which reads the whole file and returns `UIImage(data:)` (Models.swift:523-540). It is drawn at `.frame(width: 46, height: 58)` (:291). PDFs are rendered at 1240 px wide on each call (Models.swift:526-535). Used by every list row (:440-445) and the 5 Home "recent" rows (HomeView.swift:155-164). `ImageStore.directory` also runs `fileExists` (+maybe `createDirectory`) on every access (Models.swift:477-483).
- **Size of the problem (measured on BenchImages)**: median 2.32 MP / 326 KB file → **~8.9 MB RGBA** per decoded row; max 100 MP → ~382 MB. A 240 px thumbnail of the median image is ~0.1 MB.
- **Expected gain**: large memory and scroll-jank reduction in Hoá Đơn / Home; decode work per row drops from full-size to thumbnail size.
- **Risk**: low (read-only, display only). EXIF orientation must be honoured (ImageIO `kCGImageSourceCreateThumbnailWithTransform`).
- **Measure**: code-level: decoded bytes per row (w×h×4) before vs after using BenchImages dimensions. On device: Xcode memory gauge / Instruments while scrolling the list (unverified from CI). Compile proof: build-ipa.
- **What could break**: wrong orientation; a PDF thumbnail path; a stale image if a file is replaced in place under the same name (ImageStore always writes new UUID names, Models.swift:488, :509).

### #2 Detail and Review screens re-read/re-decode the same original on every body evaluation
- **Evidence**: `ReceiptDetailView.body` loads the first original twice (ReceiptViews.swift:619 hero, :683 evidence section), the flat scan (:793), and again through `receiptFlags` → `receiptHasOriginalImage` → `ImageStore.load` (:963 → :240 → :214-216). The body re-runs on every keystroke in its `@State` text fields (`purposeText`, `vendorText`, :520-526). `ReviewView` does the same (`FlatScan.displayImage` in body, :1989; `hasLoadableOriginal` with `ImageStore.load`, :2769-2771).
- **Expected gain**: removes 3–4 file reads (≈0.3–0.9 MB each, median 326 KB) + image object creation per keystroke on those screens.
- **Risk**: low–medium. Any cache must keep the "file still loadable" semantics that gate approval (ReceiptLogic.swift:273-279 blocks on missing image) — i.e. a deleted file must still read as missing.
- **Measure**: count `ImageStore.load` file reads per body pass (can be logged); typing latency on device (unverified). Compile proof: build-ipa.
- **What could break**: the missing-image approval gate if a cache answers "present" after the file is gone.

### #3 `ReceiptListView` recomputes the full filter 9× per render and builds the duplicate set once per row
- **Evidence**: `filtered` is a computed property (ReceiptViews.swift:346-359). In search mode each evaluation lowercases every receipt's `vendor`, `category`, every item name (faulting `items`) and the whole `ocrRawText` (:351-355). `body` evaluates it 9 times (:412, :416, :418, :423, :424, :428, :429, via `monthGroups` :364, :458). `duplicateTargetIDs` (:402-404) builds a `Set` over all receipts and is evaluated **inside the row `ForEach`** (:444) → O(rows × receipts).
- **Expected gain**: ~9× less filter work per render; duplicate check O(N) instead of O(N²). The search field re-renders on each keystroke, so this is the hottest path while searching.
- **Risk**: low if it is a pure "evaluate once, reuse the value" change (same predicates, same order, same sums).
- **Measure**: count of filter evaluations per body (deterministic from code: 9 → 1); Instruments SwiftUI time on device (unverified).
- **What could break**: totals shown in the header/sections if the reused value diverged from the old one (it cannot if it is computed from the same inputs in the same pass).

### #4 Every save point fetches and snapshots the whole book twice on the main thread
- **Evidence**: `MirrorSync.requestSync` (MirrorSync.swift:481-490) and `DriveSync.requestSync` (DriveSync.swift:978-986) each `fetch(FetchDescriptor<Receipt>())` and map every receipt through `MirrorReceiptSnapshot.make` (MirrorSync.swift:147-218), which copies `ocrRawText` (:194) and faults + sorts `items` and `taxLines` (:198-217). Called as a pair at 14 save/delete points plus launch and every foreground.
- **Expected gain**: one fetch + one snapshot array instead of two; work grows linearly with book size, so it matters more each tax year.
- **Risk**: medium — touches the sync trigger path at 14 sites; each sync has its own enable guard (Mirror enabled? Drive signed in?).
- **Measure**: DiagLog timestamps around the trigger on device with a known receipt count (unverified from CI).
- **What could break**: a sync not firing when only one of the two is enabled; snapshot taken at a different moment than before.

### #5 Drive pass makes one serial network call per *unchanged* receipt, every pass
- **Evidence**: for a receipt whose hash matches the manifest, `processOne` still calls `verifyRemoteCopy` (DriveSync.swift:1443-1463) → `DriveAPI.listChildren` per receipt folder (:1487), sequentially via `processReceipts` recursion (:1422-1432). Passes start on launch, foreground and every save (§1.3 step 8).
- **Expected gain**: N HTTP round-trips → ~0 for unchanged receipts (e.g. verify on a cadence, or batch). Battery and data on every app open.
- **Risk**: **high** — this verify is the deliberate self-heal against out-of-app Drive deletions (comment :1444-1451). Any change is a behaviour change of the backup.
- **Measure**: DiagLog Drive pass start/end timestamps and request count with N receipts (device only).
- **What could break**: silent loss of the self-heal guarantee.

### #6 OCR candidate chain: up to 5 full `.accurate` Vision passes per page, all images held until scoring
- **Evidence**: chain loop ReadPipeline.swift:1099-1170 (app: original, perspective if gated, shadowRemoved, enhancedContrast, binarized if no E1 close; enhancedDocument off at :843/:1137-1141), each `runCandidate` → `ClassicTextEngine.recognize` building a new `VNImageRequestHandler` (OCREngine.swift:155-171). Plus tiled rescue (:1189-1203) and ROI/arbiter re-reads (:182, :327). Every candidate keeps its full-res `CGImage` until the winner is picked; losers are released only afterwards (:1227-1241), so peak = (#candidates) × full image.
- **Expected gain**: large CPU/time per scan if the chain could stop early, and lower peak memory if loser images were dropped as soon as each candidate's evaluation is done.
- **Risk**: **high** — candidate set and order decide which read wins; this is money-reading behaviour and the history in HOW-IT-WORKS warns about it. Only allowed with bench + harness proof of identical results.
- **Measure**: bench p50/p95 `elapsedMs` (BenchSelfCheck.swift:704-766) + harness law/roigate gates must be identical field-for-field.
- **What could break**: different winner → different totals/flags.

### #7 Main-thread JPEG encode, vault copy and full-size orientation redraw before the read starts
- **Evidence**: per page `ImageStore.saveJPEG` (JPEG encode q0.8, file write, `OriginalVault.backfill` copy — Models.swift:486-500) runs on main in `process(scan:)` (ScanView.swift:522-531), `process(cameraImages:)` (:552-561), `process(image:)` (:621); `uprightCGImage` (ReadPipeline.swift:908-925) redraws the full bitmap on main (ScanView.swift:533, :564, :626).
- **Expected gain**: removes a visible UI stall after capture (multi-page scans multiply it).
- **Risk**: medium–high — the evidence-save ordering ("save original BEFORE read, all-or-nothing", ScanView.swift:508-512) and image-store writes are flagged high-risk in HOW-IT-WORKS ("14 originals went missing").
- **Measure**: DiagLog timestamps capture→"Đang đọc" on device (unverified from CI).
- **What could break**: evidence ordering, error messages on the wrong thread, orphan files.

### #8 Launch and every foreground: full-book fetch on main + two sync passes
- **Evidence**: `TabShellView.task` and `.onChange(scenePhase == .active)` both call `ImageIntegrity.runLaunchAudit` (ContentView.swift:240-246, :258-263), which fetches all receipts on main (ImageIntegrity.swift:428-445) before queueing; its completion fires #4 (two more full fetches) — so **three full fetches on main per foreground**, plus Drive's #5.
- **Expected gain**: faster return-to-app as the book grows.
- **Risk**: medium (integrity audit is a protection layer; must keep running before sync).
- **Measure**: DiagLog "mở app" line → integrity "kiểm kê xong" line timing.
- **What could break**: ordering "audit before sync" (deliberate, ContentView.swift:233-239).

### #9 Duplicated logic (money totals; capture paths)
- **Evidence**: the "official total" predicate (`status == .reviewed && !excludedFromTotals`, sum `amountPaidCents`) is written out 5 times in HomeView.swift (:27-30, :36-38, :45-47, :344-348, :353-356, :360-363 — six filters incl. pending) and twice in ReceiptViews.swift (:384-389, :393-396). `yearTotalCents` re-filters the year three times (HomeView.swift:64-66). `process(scan:)` and `process(cameraImages:)` are near-copies (ScanView.swift:513-541 vs :546-566). "has duplicates" is computed two different ways (HomeView.swift:160-163 vs ReceiptViews.swift:402-404, :443-444).
- **Expected gain**: clarity and a single place for the money rule (lower drift risk); small CPU.
- **Risk**: medium — money display code; a consolidation must be provably identical.
- **Measure**: not a perf item; diff review + build. (No harness coverage: these files are not in the harness.)
- **What could break**: a total that stops matching between screens.

### #10 Dead / stale code
- **Evidence**:
  - `ReceiptParser.reparse(storedText:)` (Parser.swift:601-606): no callers anywhere in the repo (app, bench, harness); UI moved to `ReceiptReader.read(.storedText)` (ReceiptViews.swift:1488-1494).
  - `DocumentsEngine` (OCREngine.swift:208-246) is compiled into the **app** but always throws `documentsAdapterNotWired` (:245); only `BenchView.swift:523` constructs it.
  - `github/workflows/build-ipa.yml` (no leading dot) is an old main-branch workflow copy, not active. `harness/workflow/harness-ci.yml` differs from the active `.github/workflows/harness-ci.yml`.
  - `README-BUILD.md` describes "IPA Test 0" (empty test app) — stale.
  - v3 parser paths are compiled out of the app (Parser.swift:351-406, :608-1358, …; Reconcile.swift:198-1056) but intentionally kept as the bench/harness control lane — **not** dead.
- **Expected gain**: small binary/clarity gain; no runtime gain except the app no longer linking `DocumentsEngine`.
- **Risk**: low for `reparse`; workflow copies are out of scope (CLAUDE.md rule 5).
- **Measure**: build-ipa IPA size (`ls -lh` in the package step).

---

## 3. Measured facts used above
- BenchImages (43 JPEGs): pixels min 0.79 MP / median 2.32 MP / max 100.2 MP; median file 326 KB; decoded RGBA median 8.9 MB, max 382 MB. (Python/PIL, this session.)
- `ReceiptListView.body` evaluates `filtered` 9 times (line list in #3).
- Sync trigger call sites: 28 (`grep MirrorSync.requestSync|DriveSync.requestSync`).

## 4. Could NOT verify from code alone
- Any runtime number on the owner's iPhone (launch time, scroll FPS, memory peak, scan latency). No device/simulator here.
- Whether SwiftData materialises `ocrRawText` on fetch or faults it lazily — affects #4/#8 magnitude.
- Actual Drive round-trip latency and book size on the owner's device (#5 magnitude).
- Whether Vision internally reuses work across separate `VNImageRequestHandler`s on the same image (#6).
- Real original file sizes on device (HOW-IT-WORKS says ~300–600 KB; BenchImages median 326 KB is consistent but not the same corpus).
- Harness pass/fail status on current v3 (not re-run in this audit).
- The cause of the "14 missing originals" incident.

## 5. Disagreements between HOW-IT-WORKS.md and the code (code wins)
1. **Tax Pack export (PDF + CSV + ZIP) does not exist.** HomeView.swift:442 says it "will come in a later version"; no CSV/PDF/ZIP writer exists in the app.
2. **"A flagged receipt CANNOT be approved until resolved."** Code allows approval *with explicit confirmation* for arithmetic-discrepancy and missing-field flags; only a missing original image blocks (ReceiptLogic.swift:258-279, rule L-2026-11-18-32).
3. **"7-year retention default."** `Receipt.retentionUntil` (Models.swift:260) is never assigned anywhere; it is only mirrored (MirrorSync.swift:193).
4. **"Line-level split is supported."** `LineItem.classificationRaw/category/scheduleCLine` exist (Models.swift:339-341) but no code writes them; no split UI or split-sums-to-total check was found.
5. **"Original image is NEVER modified."** Originals are stored as a re-encoded JPEG q0.8 of a `UIImage` (Models.swift:486-487): photo-library picks decode the original bytes and re-encode (ScanView.swift:291-294 → :621); camera photos likewise (ScanCameraView.swift:918). Only PDFs are kept byte-exact (`saveFile`, Models.swift:508).
6. **Store profiles learn "layout, tax labels".** `StoreProfile` holds only `zip`, `category`, `approvedCount`, `lastSeenISO` (StoreProfiles.swift:15-21).
7. **"A green main build with a red harness is NOT a pass."** `build-ipa.yml` does not run the harness; `harness-ci.yml` is manual only — the rule is procedural, not enforced by CI.
8. Minor: DriveSync comment says "13 save points" (DriveSync.swift:972); there are 14 paired call sites.
