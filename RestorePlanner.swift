// RestorePlanner.swift — A1 (vòng 2): bộ lập kế hoạch KHÔI PHỤC từ
// Drive, THUẦN Foundation (harness biên dịch để kiểm bằng Swift thật).
//
// Luật cứng của đường kéo về (lệnh Leader vòng 2, mục A1):
// - KHÔNG BAO GIỜ ghi đè dữ liệu trên máy một cách im lặng: tờ đã có
//   trên máy (cùng danh tính thư mục gương) mà nội dung khác bản Drive
//   -> XUNG ĐỘT, chỉ BÁO CÁO, không trộn, không thay.
// - Idempotent: tờ đã có trên máy với cùng nội dung -> bỏ qua; chạy
//   hai lần không sinh bản trùng.
// - Tôn trọng _deleted: mục manifest "deleted", hoặc thư mục tờ nằm
//   trong _deleted/ -> KHÔNG khôi phục (chỉ đếm).
// - File gốc phải khớp từng byte: tên đích đã có trên máy mà khác
//   byte -> xung đột file, bỏ cả tờ (không ghi đè ảnh trên máy).
//
// Planner chỉ làm việc trên giá trị thuần (id, trạng thái, hash) —
// phần mạng + SwiftData nằm ở DriveRestore.swift (chỉ target app).

import Foundation

/// Một mục manifest đã đối chiếu với chỉ mục thư mục trên Drive.
struct RestoreRemoteEntry: Equatable {
    var id: String
    var status: String            // "active" | "deleted"
    var contentHash: String
    var hasReceiptFolder: Bool    // có thư mục tên = id trong receipts/
    var inDeletedFolder: Bool     // có thư mục tên = id trong _deleted/
}

enum RestoreDecision: Equatable {
    /// Chưa có trên máy -> tải và tạo mới.
    case restore
    /// Đã có trên máy, cùng hash nội dung -> bỏ qua (idempotent).
    case alreadyPresent
    /// Đã có trên máy, KHÁC hash -> báo cáo, không đụng.
    case conflict(localHash: String, remoteHash: String)
    /// Mục đã xoá (manifest deleted hoặc thư mục ở _deleted/).
    case skipDeleted
    /// Mục active nhưng không còn thư mục tờ trên Drive.
    case skipNoFolder
}

/// Quyết định cho một file gốc đích trên máy.
enum RestoreFileDecision: Equatable {
    /// Tên đích chưa có -> ghi file tải về.
    case write
    /// Tên đích đã có và trùng từng byte (SHA-256) -> dùng lại.
    case reuseIdentical
    /// Tên đích đã có và KHÁC byte -> xung đột, bỏ cả tờ.
    case conflict
}

enum RestorePlanner {

    /// - Parameters:
    ///   - entries: mục manifest (đã gắn cờ thư mục).
    ///   - localHashes: danh tính thư mục gương của MỌI tờ trên máy
    ///     -> contentHash của snapshot tờ đó.
    static func decide(_ entry: RestoreRemoteEntry,
                       localHashes: [String: String]) -> RestoreDecision {
        if entry.status != "active" || entry.inDeletedFolder {
            return .skipDeleted
        }
        if let local = localHashes[entry.id] {
            return local == entry.contentHash
                ? .alreadyPresent
                : .conflict(localHash: local, remoteHash: entry.contentHash)
        }
        return entry.hasReceiptFolder ? .restore : .skipNoFolder
    }

    /// Mục trùng id trong manifest: giữ mục CUỐI (cùng luật last-wins
    /// của engine đồng bộ khi dựng chỉ mục manifest).
    static func dedupeLastWins(_ entries: [RestoreRemoteEntry])
        -> [RestoreRemoteEntry] {
        var order: [String] = []
        var byID: [String: RestoreRemoteEntry] = [:]
        for e in entries {
            if byID[e.id] == nil { order.append(e.id) }
            byID[e.id] = e
        }
        return order.compactMap { byID[$0] }
    }

    static func fileDecision(localSHA256: String?,
                             downloadedSHA256: String) -> RestoreFileDecision {
        guard let localSHA256 else { return .write }
        return localSHA256 == downloadedSHA256 ? .reuseIdentical : .conflict
    }

    /// Tên file nguồn từ receipt.json chỉ được là MỘT tên file trơn
    /// (không thư mục, không "..") — file Drive nằm ngoài tầm kiểm
    /// soát của app nên không tin đường dẫn trong đó.
    static func isSafeFileName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".."
            && !name.contains("/") && !name.contains("\\")
            && !name.contains("\0") && !name.hasPrefix(".")
    }

    /// Kiểm tải về: số byte phải khớp byteCount đã ghi lúc gương
    /// (khi có), và MD5 phải khớp md5Checksum của Drive (khi có).
    /// Không có cả hai -> KHÔNG nhận (không chứng minh được byte).
    static func downloadVerified(byteCount: Int?, expectedMD5: String?,
                                 actualCount: Int, actualMD5: String) -> Bool {
        if byteCount == nil && expectedMD5 == nil { return false }
        if let byteCount, byteCount != actualCount { return false }
        if let expectedMD5, expectedMD5.lowercased() != actualMD5.lowercased() {
            return false
        }
        return true
    }
}

// MARK: - Báo cáo đối chiếu sau khôi phục

struct RestoreYearLine: Equatable {
    var year: Int
    var count: Int
    var totalCents: Int
}

struct RestoreReport: Equatable {
    var startedAt: Date
    var finishedAt: Date? = nil
    var abortedReason: String? = nil
    var manifestEntries = 0
    var restored = 0
    var alreadyPresent = 0
    var conflicts: [String] = []          // "id · tiệm · lý do"
    var skippedDeleted = 0
    var skippedNoFolder = 0
    var failed: [String] = []             // "id · lý do"
    var originalsWritten = 0
    var originalsReused = 0
    var originalsMissingInBackup: [String] = []   // "id · tên file"
    var warnings: [String] = []
    /// Danh tính các mục manifest active (không ở _deleted) — dùng để
    /// đối chiếu cột "máy" đúng cùng tập với cột "Drive".
    var activeManifestIDs: [String] = []
    /// Theo năm (năm của ngày mua trong manifest): mục active trong
    /// manifest — số tờ + Σ totalCents in trên manifest.
    var manifestByYear: [RestoreYearLine] = []
    /// Theo năm thuế: sổ TRÊN MÁY sau khôi phục, chỉ các tờ có danh
    /// tính nằm trong manifest active — số tờ + Σ totalCents.
    var localByYear: [RestoreYearLine] = []
    /// Theo năm thuế: tổng CHÍNH THỨC (luật A7) của toàn sổ sau khôi
    /// phục — cá nhân / business.
    var officialByYear: [(year: Int, personal: Int, business: Int)] = []

    static func == (a: RestoreReport, b: RestoreReport) -> Bool {
        a.text() == b.text()
    }

    func text() -> String {
        func money(_ c: Int) -> String { formatMoney(cents: c) }
        var lines: [String] = []
        lines.append("KHÔI PHỤC TỪ DRIVE — báo cáo đối chiếu")
        if let abortedReason {
            lines.append("DỪNG: \(abortedReason)")
        }
        lines.append("Mục trong manifest: \(manifestEntries)")
        lines.append("Đã khôi phục: \(restored)")
        lines.append("Đã có trên máy (bỏ qua, cùng nội dung): \(alreadyPresent)")
        lines.append("Xung đột (KHÔNG đụng dữ liệu máy): \(conflicts.count)")
        for c in conflicts { lines.append("  • \(c)") }
        lines.append("Đã xoá trên Drive (_deleted, không khôi phục): \(skippedDeleted)")
        if skippedNoFolder > 0 {
            lines.append("Mục active nhưng mất thư mục tờ: \(skippedNoFolder)")
        }
        lines.append("Lỗi: \(failed.count)")
        for f in failed { lines.append("  • \(f)") }
        lines.append("File gốc đã ghi: \(originalsWritten) · dùng lại (trùng byte): \(originalsReused)")
        if !originalsMissingInBackup.isEmpty {
            lines.append("File gốc KHÔNG có trong bản Drive: \(originalsMissingInBackup.count)")
            for m in originalsMissingInBackup { lines.append("  • \(m)") }
        }
        for w in warnings { lines.append("Lưu ý: \(w)") }
        if !manifestByYear.isEmpty || !localByYear.isEmpty {
            lines.append("— Đối chiếu theo năm (số tờ · Σ tổng in) —")
            let years = Set(manifestByYear.map(\.year) + localByYear.map(\.year)).sorted()
            for y in years {
                let m = manifestByYear.first { $0.year == y }
                let l = localByYear.first { $0.year == y }
                lines.append("\(y): Drive \(m?.count ?? 0) tờ · \(money(m?.totalCents ?? 0))"
                    + "  |  máy \(l?.count ?? 0) tờ · \(money(l?.totalCents ?? 0))")
            }
            lines.append("(Drive tính theo năm ngày mua; máy tính theo năm thuế — tờ có năm thuế sửa tay có thể lệch năm.)")
        }
        if !officialByYear.isEmpty {
            lines.append("— Tổng CHÍNH THỨC toàn sổ sau khôi phục (cá nhân · business) —")
            for row in officialByYear {
                lines.append("\(row.year): \(money(row.personal)) · \(money(row.business))")
            }
        }
        return lines.joined(separator: "\n")
    }
}

enum RestoreTally {
    /// Gom (năm, cent?) thành dòng theo năm — cent nil tính 0.
    static func byYear(_ rows: [(year: Int, cents: Int?)]) -> [RestoreYearLine] {
        var acc: [Int: RestoreYearLine] = [:]
        for r in rows {
            var line = acc[r.year] ?? RestoreYearLine(year: r.year, count: 0, totalCents: 0)
            line.count += 1
            line.totalCents += r.cents ?? 0
            acc[r.year] = line
        }
        return acc.values.sorted { $0.year < $1.year }
    }
}
