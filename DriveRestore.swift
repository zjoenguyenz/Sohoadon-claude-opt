// DriveRestore.swift — A1 (vòng 2): đường KÉO VỀ từ Google Drive.
//
// Trước gói này app chỉ đồng bộ LÊN (manifest + thư mục mỗi tờ +
// receipt.json + file gốc). Đây là đường ngược lại: đăng nhập ->
// đọc manifest -> dựng lại tờ + món + dòng thuế + file gốc vào
// SwiftData bằng ĐÚNG các DTO đang có (MirrorReceiptFile /
// MirrorReceiptSnapshot / MirrorManifest, giải mã bằng MirrorJSON).
//
// Luật (lệnh Leader vòng 2, A1) — quyết định nằm ở RestorePlanner
// (thuần, harness kiểm):
// - KHÔNG đổi schema SwiftData; chỉ tạo bản ghi mới bằng các trường
//   có sẵn.
// - Idempotent: tờ đã có (cùng danh tính thư mục gương + cùng hash)
//   -> bỏ qua. Chạy hai lần không sinh bản trùng.
// - KHÔNG BAO GIỜ ghi đè im lặng: cùng danh tính mà khác nội dung ->
//   XUNG ĐỘT, chỉ báo cáo; tên file gốc đã có trên máy mà khác byte
//   -> xung đột, bỏ cả tờ.
// - File gốc khớp từng byte: số byte = byteCount lúc gương VÀ MD5 =
//   md5Checksum của Drive; ghi nguyên byte tải về.
// - Tôn trọng _deleted: mục deleted / thư mục ở _deleted/ không về.
// - Cuối lượt: báo cáo đối chiếu (số tờ, tổng theo năm) hiện ở UI +
//   ghi DiagLog cho Leader.
// - CHỈ ĐỌC Drive: đường này không tạo/sửa/xoá gì trên Drive.

import Foundation
import SwiftData
import CryptoKit
import SwiftUI

/// File con của một thư mục tờ, có md5Checksum (Drive v3 trả trường
/// này cho file nhị phân) — liệt kê riêng ở đây để không đổi
/// DriveFileResource/fieldsParam của engine đồng bộ.
private struct RestoreDriveFile: Codable {
    var id: String
    var name: String
    var mimeType: String?
    var size: String?
    var md5Checksum: String?
}

private struct RestoreDriveList: Codable {
    var files: [RestoreDriveFile]
    var nextPageToken: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        files = (try? c.decodeIfPresent([RestoreDriveFile].self, forKey: .files)) ?? []
        nextPageToken = try? c.decodeIfPresent(String.self, forKey: .nextPageToken)
    }
}

/// Một tờ đã tải xong vào thư mục tạm, chờ áp vào sổ trên main.
private struct StagedReceipt {
    var snapshot: MirrorReceiptSnapshot
    /// (tên file đích trong kho ảnh, URL file tạm, SHA-256 hex)
    var files: [(name: String, staged: URL, sha256: String)]
    var missingInBackup: [String]
}

enum DriveRestoreSettings {
    private static let lastReportKey = "glkeeper.driveRestore.lastReport"
    static var lastReportText: String? {
        get { UserDefaults.standard.string(forKey: lastReportKey) }
        set { UserDefaults.standard.set(newValue, forKey: lastReportKey) }
    }
}

enum DriveRestore {
    private static let queue = DispatchQueue(label: "glkeeper.drive.restore",
                                             qos: .userInitiated)
    /// Chỉ chạm trên main.
    private(set) static var isRunning = false

    // MARK: Điểm vào (gọi trên main)

    static func run(using context: ModelContext,
                    completion: @escaping (RestoreReport) -> Void) {
        var report = RestoreReport(startedAt: Date())
        guard !isRunning else {
            report.abortedReason = "đang có một lượt khôi phục chạy"
            completion(report)
            return
        }
        guard DriveAuth.isSignedIn else {
            report.abortedReason = "chưa đăng nhập Google"
            completion(report)
            return
        }
        let localHashes: [String: String]
        do {
            localHashes = try localIndex(context)
        } catch {
            report.abortedReason = "đọc sổ trên máy thất bại — không khôi phục"
            completion(report)
            return
        }
        isRunning = true
        DiagLog.log(.drive, "KHÔI PHỤC: bắt đầu (máy có \(localHashes.count) tờ)")
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("glkeeper-restore-\(UUID().uuidString)",
                                    isDirectory: true)
        try? FileManager.default.createDirectory(at: staging,
                                                 withIntermediateDirectories: true)
        queue.async {
            fetchAndStage(localHashes: localHashes, staging: staging,
                          report: report) { staged, report in
                DispatchQueue.main.async {
                    var report = report
                    if report.abortedReason == nil {
                        apply(staged, context: context, report: &report)
                        tally(context: context, report: &report)
                    }
                    try? FileManager.default.removeItem(at: staging)
                    report.finishedAt = Date()
                    let text = report.text()
                    DriveRestoreSettings.lastReportText = text
                    for line in text.split(separator: "\n") {
                        DiagLog.log(.drive, "KHÔI PHỤC: \(line)")
                    }
                    isRunning = false
                    completion(report)
                }
            }
        }
    }

    /// Danh tính thư mục gương -> contentHash của MỌI tờ trên máy.
    private static func localIndex(_ context: ModelContext) throws -> [String: String] {
        let receipts = try context.fetch(FetchDescriptor<Receipt>())
        var out: [String: String] = [:]
        for r in receipts {
            let snap = MirrorReceiptSnapshot.make(from: r)
            out[snap.folderID] = snap.contentHash()
        }
        return out
    }

    // MARK: Pha mạng (hàng đợi riêng) — chỉ ĐỌC Drive

    private static func fetchAndStage(
        localHashes: [String: String], staging: URL, report: RestoreReport,
        completion: @escaping ([StagedReceipt], RestoreReport) -> Void
    ) {
        var report = report
        func abort(_ why: String) {
            report.abortedReason = why
            completion([], report)
        }
        DriveAuth.validAccessToken { token, expired in
            queue.async {
                guard let token else {
                    abort(expired ? "phiên Google hết hạn — đăng nhập lại"
                                  : "chưa lấy được token Google (mạng?)")
                    return
                }
                listAll(token: token, parentID: "root") { rootList in
                    guard let rootList else { abort("không liệt kê được My Drive"); return }
                    let roots = rootList.filter {
                        $0.name == DriveConfig.rootFolderName
                            && $0.mimeType == DriveConfig.folderMIME
                    }
                    let root: RestoreDriveFile?
                    if roots.count == 1 {
                        root = roots[0]
                    } else if let cached = DriveSettings.rootFolderID {
                        root = roots.first { $0.id == cached }
                    } else {
                        root = nil
                    }
                    guard let root else {
                        abort(roots.isEmpty
                              ? "không có thư mục \(DriveConfig.rootFolderName) trên Drive"
                              : "có \(roots.count) thư mục \(DriveConfig.rootFolderName) — không đoán")
                        return
                    }
                    listAll(token: token, parentID: root.id) { children in
                        guard let children else { abort("không liệt kê được thư mục gốc"); return }
                        guard let manifestFile = children.first(where: { $0.name == "manifest.json" }) else {
                            abort("không có manifest.json trên Drive")
                            return
                        }
                        let receiptsFolder = children.first {
                            $0.name == DriveConfig.receiptsFolderName
                                && $0.mimeType == DriveConfig.folderMIME
                        }
                        let deletedFolder = children.first {
                            $0.name == DriveConfig.deletedFolderName
                                && $0.mimeType == DriveConfig.folderMIME
                        }
                        DriveAPI.download(token: token, fileID: manifestFile.id) { result in
                            queue.async {
                                guard case .success(let data) = result,
                                      let manifest = try? MirrorJSON.decoder()
                                        .decode(MirrorManifest.self, from: data) else {
                                    abort("không tải/giải mã được manifest.json")
                                    return
                                }
                                loadFolderIndex(token: token, folder: receiptsFolder) { receiptFolders in
                                    guard let receiptFolders else { abort("không liệt kê được receipts/"); return }
                                    loadFolderIndex(token: token, folder: deletedFolder) { deletedFolders in
                                        guard let deletedFolders else { abort("không liệt kê được _deleted/"); return }
                                        plan(manifest: manifest, localHashes: localHashes,
                                             receiptFolders: receiptFolders,
                                             deletedNames: Set(deletedFolders.keys),
                                             token: token, staging: staging,
                                             report: report, completion: completion)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Thư mục -> [tên thư mục con: file]. Thư mục không có -> [:].
    private static func loadFolderIndex(
        token: String, folder: RestoreDriveFile?,
        completion: @escaping ([String: RestoreDriveFile]?) -> Void
    ) {
        guard let folder else { completion([:]); return }
        listAll(token: token, parentID: folder.id) { list in
            guard let list else { completion(nil); return }
            var out: [String: RestoreDriveFile] = [:]
            for f in list where f.mimeType == DriveConfig.folderMIME {
                out[f.name] = f
            }
            completion(out)
        }
    }

    private static func plan(
        manifest: MirrorManifest, localHashes: [String: String],
        receiptFolders: [String: RestoreDriveFile], deletedNames: Set<String>,
        token: String, staging: URL, report: RestoreReport,
        completion: @escaping ([StagedReceipt], RestoreReport) -> Void
    ) {
        var report = report
        let entries = RestorePlanner.dedupeLastWins(manifest.entries.map {
            RestoreRemoteEntry(id: $0.id, status: $0.status,
                               contentHash: $0.contentHash,
                               hasReceiptFolder: receiptFolders[$0.id] != nil,
                               inDeletedFolder: deletedNames.contains($0.id))
        })
        report.manifestEntries = entries.count
        report.activeManifestIDs = entries
            .filter { $0.status == "active" && !$0.inDeletedFolder }
            .map(\.id)
        let byID = Dictionary(manifest.entries.map { ($0.id, $0) },
                              uniquingKeysWith: { _, last in last })
        report.manifestByYear = RestoreTally.byYear(entries
            .filter { $0.status == "active" && !$0.inDeletedFolder }
            .compactMap { e in byID[e.id].map {
                (year: Calendar.current.component(.year, from: $0.date),
                 cents: $0.totalCents) } })
        var toFetch: [(entry: RestoreRemoteEntry, folder: RestoreDriveFile)] = []
        for e in entries {
            switch RestorePlanner.decide(e, localHashes: localHashes) {
            case .restore:
                if let f = receiptFolders[e.id] { toFetch.append((e, f)) }
            case .alreadyPresent:
                report.alreadyPresent += 1
            case .conflict:
                report.conflicts.append("\(e.id) · \(byID[e.id]?.vendor ?? "?") · "
                    + "trên máy đã có tờ này với nội dung KHÁC bản Drive — giữ bản máy")
            case .skipDeleted:
                report.skippedDeleted += 1
            case .skipNoFolder:
                report.skippedNoFolder += 1
            }
        }
        stageNext(toFetch, index: 0, token: token, staging: staging,
                  staged: [], report: report, completion: completion)
    }

    /// Tải lần lượt từng tờ (tuần tự — không dồn mạng).
    private static func stageNext(
        _ list: [(entry: RestoreRemoteEntry, folder: RestoreDriveFile)], index: Int,
        token: String, staging: URL, staged: [StagedReceipt], report: RestoreReport,
        completion: @escaping ([StagedReceipt], RestoreReport) -> Void
    ) {
        guard index < list.count else { completion(staged, report); return }
        let item = list[index]
        stageOne(entry: item.entry, folder: item.folder, token: token,
                 staging: staging) { result in
            queue.async {
                var staged = staged
                var report = report
                switch result {
                case .success(let s): staged.append(s)
                case .failure(let why): report.failed.append("\(item.entry.id) · \(why.text)")
                }
                stageNext(list, index: index + 1, token: token, staging: staging,
                          staged: staged, report: report, completion: completion)
            }
        }
    }

    private struct StageError: Error { var text: String }

    private static func stageOne(
        entry: RestoreRemoteEntry, folder: RestoreDriveFile, token: String,
        staging: URL, completion: @escaping (Result<StagedReceipt, StageError>) -> Void
    ) {
        listAll(token: token, parentID: folder.id) { children in
            queue.async {
                guard let children else {
                    completion(.failure(StageError(text: "không liệt kê được thư mục tờ")))
                    return
                }
                var byName: [String: RestoreDriveFile] = [:]
                for c in children { byName[c.name] = c }
                guard let json = byName["receipt.json"] else {
                    completion(.failure(StageError(text: "thiếu receipt.json")))
                    return
                }
                DriveAPI.download(token: token, fileID: json.id) { result in
                    queue.async {
                        guard case .success(let data) = result,
                              let file = try? MirrorJSON.decoder()
                                .decode(MirrorReceiptFile.self, from: data) else {
                            completion(.failure(StageError(text: "không tải/giải mã được receipt.json")))
                            return
                        }
                        guard file.receipt.folderID == entry.id else {
                            completion(.failure(StageError(
                                text: "receipt.json mang danh tính \(file.receipt.folderID) khác thư mục")))
                            return
                        }
                        var refs = file.originals
                        if let enhanced = file.enhanced { refs.append(enhanced) }
                        var missing: [String] = []
                        var wanted: [MirrorOriginalRef] = []
                        for ref in refs {
                            if ref.missing || byName[ref.mirrorFileName] == nil {
                                missing.append(ref.sourceFileName)
                            } else {
                                wanted.append(ref)
                            }
                        }
                        downloadFiles(wanted, index: 0, byName: byName, token: token,
                                      staging: staging, acc: []) { filesResult in
                            switch filesResult {
                            case .failure(let e): completion(.failure(e))
                            case .success(let files):
                                completion(.success(StagedReceipt(
                                    snapshot: file.receipt, files: files,
                                    missingInBackup: missing)))
                            }
                        }
                    }
                }
            }
        }
    }

    private static func downloadFiles(
        _ refs: [MirrorOriginalRef], index: Int,
        byName: [String: RestoreDriveFile], token: String, staging: URL,
        acc: [(name: String, staged: URL, sha256: String)],
        completion: @escaping (Result<[(name: String, staged: URL, sha256: String)], StageError>) -> Void
    ) {
        guard index < refs.count else { completion(.success(acc)); return }
        let ref = refs[index]
        guard RestorePlanner.isSafeFileName(ref.sourceFileName),
              let remote = byName[ref.mirrorFileName] else {
            completion(.failure(StageError(text: "tên file gốc không hợp lệ: \(ref.sourceFileName)")))
            return
        }
        DriveAPI.download(token: token, fileID: remote.id) { result in
            queue.async {
                guard case .success(let data) = result else {
                    completion(.failure(StageError(text: "tải \(ref.mirrorFileName) thất bại")))
                    return
                }
                let md5 = Insecure.MD5.hash(data: data)
                    .map { String(format: "%02x", $0) }.joined()
                guard RestorePlanner.downloadVerified(
                        byteCount: ref.byteCount, expectedMD5: remote.md5Checksum,
                        actualCount: data.count, actualMD5: md5) else {
                    completion(.failure(StageError(
                        text: "\(ref.mirrorFileName) không khớp byte (số byte/MD5)")))
                    return
                }
                let staged = staging.appendingPathComponent(UUID().uuidString)
                do {
                    try data.write(to: staged, options: [.atomic])
                } catch {
                    completion(.failure(StageError(text: "ghi file tạm thất bại")))
                    return
                }
                let sha = sha256Hex(data)
                downloadFiles(refs, index: index + 1, byName: byName, token: token,
                              staging: staging,
                              acc: acc + [(ref.sourceFileName, staged, sha)],
                              completion: completion)
            }
        }
    }

    /// Liệt kê toàn bộ con trực tiếp (đi hết trang), có md5Checksum.
    private static func listAll(token: String, parentID: String,
                                pageToken: String? = nil,
                                acc: [RestoreDriveFile] = [],
                                completion: @escaping ([RestoreDriveFile]?) -> Void) {
        var comps = URLComponents(string: "\(DriveConfig.apiBase)/files")
        var items = [
            URLQueryItem(name: "q", value: "'\(parentID)' in parents and trashed = false"),
            URLQueryItem(name: "fields",
                         value: "files(id,name,mimeType,size,md5Checksum),nextPageToken"),
            URLQueryItem(name: "pageSize", value: "1000"),
            URLQueryItem(name: "spaces", value: "drive"),
        ]
        if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
        comps?.queryItems = items
        guard let url = comps?.url else { completion(nil); return }
        DriveHTTP.perform(token: token, method: "GET", url: url) { result in
            queue.async {
                guard case .success(let data) = result,
                      let page = try? JSONDecoder().decode(RestoreDriveList.self, from: data)
                else { completion(nil); return }
                let all = acc + page.files
                if let next = page.nextPageToken {
                    listAll(token: token, parentID: parentID, pageToken: next,
                            acc: all, completion: completion)
                } else {
                    completion(all)
                }
            }
        }
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Pha áp vào sổ (main)

    private static func apply(_ staged: [StagedReceipt], context: ModelContext,
                              report: inout RestoreReport) {
        // Đọc lại danh tính trên máy NGAY LÚC ÁP (anh có thể đã lưu
        // tờ mới trong lúc tải) — trùng thì là xung đột, không ghi.
        guard let present = try? localIndex(context) else {
            report.abortedReason = "đọc sổ trên máy thất bại lúc áp — không ghi gì"
            return
        }
        let fm = FileManager.default
        let imageDir = ImageStore.directory
        for item in staged {
            let snap = item.snapshot
            if present[snap.folderID] != nil {
                report.conflicts.append("\(snap.folderID) · \(snap.vendor) · tờ vừa xuất hiện trên máy trong lúc tải — giữ bản máy")
                continue
            }
            // Quyết định từng file TRƯỚC khi ghi bất kỳ file nào.
            var plan: [(name: String, staged: URL, decision: RestoreFileDecision)] = []
            for f in item.files {
                let dest = imageDir.appendingPathComponent(f.name)
                // File đích đã có mà không đọc được -> coi như KHÁC byte
                // (xung đột, không ghi đè).
                let localSHA: String? = fm.fileExists(atPath: dest.path)
                    ? ((try? Data(contentsOf: dest)).map(sha256Hex) ?? "unreadable")
                    : nil
                plan.append((f.name, f.staged,
                             RestorePlanner.fileDecision(localSHA256: localSHA,
                                                         downloadedSHA256: f.sha256)))
            }
            if let clash = plan.first(where: { $0.decision == .conflict }) {
                report.conflicts.append("\(snap.folderID) · \(snap.vendor) · file \(clash.name) trên máy khác byte bản Drive — giữ bản máy, không khôi phục tờ")
                continue
            }
            var written: [String] = []
            var writeFailed = false
            for p in plan where p.decision == .write {
                do {
                    try fm.moveItem(at: p.staged,
                                    to: imageDir.appendingPathComponent(p.name))
                    written.append(p.name)
                } catch {
                    writeFailed = true
                    break
                }
            }
            if writeFailed {
                for n in written { ImageStore.delete(fileName: n) }
                report.failed.append("\(snap.folderID) · ghi file gốc vào máy thất bại")
                continue
            }
            let receipt = makeReceipt(from: snap)
            context.insert(receipt)
            for i in snap.items {
                let item = LineItem()
                item.name = i.name
                item.qty = i.qty
                item.unitPriceCents = i.unitPriceCents
                item.amountCents = i.amountCents
                item.taxFlag = i.taxFlag
                item.itemCode = i.itemCode
                item.sortIndex = i.sortIndex
                item.classificationRaw = i.classificationRaw
                item.category = i.category
                item.scheduleCLine = i.scheduleCLine
                item.receipt = receipt
                context.insert(item)
            }
            for t in snap.taxLines {
                let line = TaxLine()
                line.label = t.label
                line.rateText = t.rateText
                line.amountCents = t.amountCents
                line.sortIndex = t.sortIndex
                line.receipt = receipt
                context.insert(line)
            }
            if saveContextOrFalse(context) {
                report.restored += 1
                report.originalsWritten += written.count
                report.originalsReused += plan.filter { $0.decision == .reuseIdentical }.count
                for n in written {
                    OriginalVault.backfill(fileName: n, mainDirectory: imageDir)
                }
                for m in item.missingInBackup {
                    report.originalsMissingInBackup.append("\(snap.folderID) · \(m)")
                }
            } else {
                context.rollback()
                for n in written { ImageStore.delete(fileName: n) }
                report.failed.append("\(snap.folderID) · lưu sổ thất bại — đã gỡ file vừa ghi")
            }
        }
    }

    /// Dựng Receipt từ snapshot bằng ĐÚNG các trường có sẵn. Tờ đời
    /// cũ (stableID rỗng, danh tính "pre2-…") nhận stableID = danh tính
    /// thư mục để MirrorReceiptSnapshot.folderID trỏ đúng thư mục cũ
    /// (lần khôi phục sau nhận ra là đã có — idempotent).
    private static func makeReceipt(from s: MirrorReceiptSnapshot) -> Receipt {
        let r = Receipt()
        r.stableID = s.stableID.isEmpty ? s.folderID : s.stableID
        r.vendor = s.vendor
        r.date = s.date
        r.createdAt = s.createdAt
        r.subtotalCents = s.subtotalCents
        r.taxCents = s.taxCents
        r.totalCents = s.totalCents
        r.totalPrintedCents = s.totalPrintedCents
        r.tipAmountCents = s.tipAmountCents
        r.cardLast4 = s.cardLast4
        r.cardBrand = s.cardBrand
        r.paymentMethodRaw = s.paymentMethodRaw
        r.classificationRaw = s.classificationRaw
        r.classificationReason = s.classificationReason
        r.category = s.category
        r.scheduleCLine = s.scheduleCLine
        r.businessPurpose = s.businessPurpose
        r.mealsAttendees = s.mealsAttendees
        r.capitalizationFlagRaw = s.capitalizationFlagRaw
        r.taxYearOverride = s.taxYearOverride
        r.vendorAddress = s.vendorAddress
        r.vendorPhone = s.vendorPhone
        r.storeNumber = s.storeNumber
        r.transactionRef = s.transactionRef
        r.authCode = s.authCode
        r.dedupeKey = s.dedupeKey
        r.duplicateOfStableID = s.duplicateOfStableID
        r.excludedFromTotals = s.excludedFromTotals
        r.confirmedWithFlag = s.confirmedWithFlag
        r.isReturn = s.isReturn
        r.statusRaw = s.statusRaw
        r.reviewedAt = s.reviewedAt
        r.userEnteredFieldNames = s.userEnteredFieldNames
        r.parserVersion = s.parserVersion
        r.vendorConfidence = s.vendorConfidence
        r.dateConfidence = s.dateConfidence
        r.totalConfidence = s.totalConfidence
        r.sourceTypeRaw = s.sourceTypeRaw
        r.sourceFileName = s.sourceFileName
        r.rawTextFromPDFTextLayer = s.rawTextFromPDFTextLayer
        r.retentionUntil = s.retentionUntil
        r.ocrRawText = s.ocrRawText
        r.imageFileName = s.imageFileName
        r.originalImageFileNames = s.sourceOriginalFileNames
        r.enhancedImageFileName = s.enhancedImageFileName
        return r
    }

    // MARK: Báo cáo đối chiếu

    private static func tally(context: ModelContext, report: inout RestoreReport) {
        guard let all = try? context.fetch(FetchDescriptor<Receipt>()) else {
            report.warnings.append("không đọc lại được sổ để đối chiếu")
            return
        }
        // Chỉ các tờ có danh tính nằm trong manifest active — để
        // đặt cạnh cột Drive cùng tập.
        let active = Set(report.activeManifestIDs)
        report.localByYear = RestoreTally.byYear(all
            .filter { active.contains(MirrorReceiptSnapshot.folderID(for: $0)) }
            .map { (year: $0.taxYear, cents: $0.totalCents) })
        let years = Set(all.map(\.taxYear)).sorted()
        report.officialByYear = years.map { y in
            let inYear = all.filter { $0.taxYear == y }
            return (y, inYear.officialTotalCents(kind: .personal),
                    inYear.officialTotalCents(kind: .business))
        }
    }
}

// MARK: - Mục khôi phục ở Thẻ & Cài Đặt

struct DriveRestoreSection: View {
    @Environment(\.modelContext) private var modelContext
    @State private var running = false
    @State private var confirm = false
    @State private var reportText: String? = DriveRestoreSettings.lastReportText

    var body: some View {
        Section {
            Button {
                confirm = true
            } label: {
                Label(running ? "Đang khôi phục…" : "Khôi phục từ Drive",
                      systemImage: "arrow.down.doc")
            }
            .disabled(running || !DriveAuth.isSignedIn)
            if let reportText {
                NavigationLink {
                    ScrollView {
                        Text(reportText)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .navigationTitle("Báo cáo khôi phục")
                } label: {
                    Label("Báo cáo khôi phục gần nhất", systemImage: "doc.plaintext")
                }
            }
        } header: {
            Text("Khôi phục từ Drive")
        } footer: {
            Text("Kéo hoá đơn từ thư mục GL-Keeper trên Drive về máy. Tờ đã có trên máy KHÔNG bị ghi đè — tờ khác nội dung được báo là xung đột. Tờ trong _deleted không được khôi phục. App chỉ đọc Drive ở bước này.")
        }
        .confirmationDialog("Khôi phục hoá đơn từ Google Drive?",
                            isPresented: $confirm, titleVisibility: .visible) {
            Button("Khôi phục") {
                running = true
                DriveRestore.run(using: modelContext) { report in
                    running = false
                    reportText = report.text()
                }
            }
            Button("Huỷ", role: .cancel) {}
        } message: {
            Text("Chỉ thêm tờ còn thiếu trên máy; không sửa, không xoá tờ nào đang có.")
        }
    }
}
