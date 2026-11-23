import SwiftUI
import VisionKit
import Vision
import CoreImage
import PhotosUI
import UIKit
import PDFKit
import UniformTypeIdentifiers

/// Bản nháp sau khi đọc xong 1 hoá đơn — đưa sang màn Review để anh kiểm/sửa rồi mới lưu.
struct ScanDraft: Identifiable {
    let id = UUID()
    var result: ParseResult
    var imageFileName: String
    /// WP2 bước 2: nguồn nạp (ACCOUNTING-SPEC F3) — ScanView ghi theo đúng
    /// đường vào (.camera cho quét tài liệu, .photoLibrary cho chọn ảnh);
    /// ReviewView.save() chép vào Receipt.sourceType lúc lưu. Mặc định
    /// .unknown để mọi điểm dựng draft khác (nếu có) vẫn biên dịch được.
    var sourceType: SourceType = .unknown
    /// WP3: tên file gốc như anh chọn trong Files (vd "sams-club.pdf") —
    /// ReviewView.save() chép vào Receipt.sourceFileName. Chỉ đường nạp
    /// file mới có; camera/Photos để nil.
    var sourceFileName: String? = nil
    /// WP3: file bằng chứng gốc đi kèm ngoài imageFileName — với PDF là
    /// chính file PDF đã lưu nguyên byte vào ReceiptImages (khi lớp chữ
    /// đọc thẳng thì imageFileName CŨNG là file PDF đó; khi render->OCR
    /// thì imageFileName là JPEG render còn PDF nằm ở đây).
    /// ReviewView.save() chép vào Receipt.originalImageFileNames.
    var originalFileNames: [String] = []
    /// WP3 bước 2: true CHỈ khi rawText trích thẳng từ lớp chữ của PDF
    /// (đường textLayerLines). PDF không lớp chữ -> render -> OCR thì
    /// false dù sourceType vẫn là .pdfImport. Nhãn F3 ở Kiểm Lại/Chi Tiết
    /// quyết theo cờ này (CODE-AUDIT F3 mục 3: nhãn phải nói đúng đường
    /// nào sinh ra chữ). ReviewView.save() chép vào Receipt.
    var rawTextIsPDFTextLayer: Bool = false
    /// V3 (Pha 4): provenance từng trường của lần đọc (đọc thẳng /
    /// suy luận F5 / đọc-lại-ROI / sửa chữ theo từ điển) — ReviewView
    /// hiển thị ở mức dữ liệu cạnh trường tương ứng (M12, §7 Pha 4).
    var provenance: [String: FieldProvenance] = [:]
    /// V3 (Pha 4): báo cáo trọng tài của lần đọc — ReviewView dùng
    /// requiresReview cho công thức trạng thái và suggestions để
    /// trình gợi ý đối chiếu (chỉ trình, không tự áp).
    var reconcileReport: ReconcileReport? = nil
    /// V3 (Pha 4): mã hồ sơ chẩn đoán v2 của lần đọc (nil khi ghi
    /// chẩn đoán thất bại hoặc không có thư mục ghi).
    var diagnosticsID: String? = nil
    /// V3 (Pha 4): ghi chẩn đoán THẤT BẠI -> tờ bị ép vào Kiểm Lại
    /// khi lưu (hợp đồng fail-closed §1.5: không có lần đọc nào
    /// "sạch" mà không có bản ghi kiểm chứng được).
    var diagnosticsWriteFailed: Bool = false
}

/// Màn Chụp: camera quét tài liệu của Apple (VisionKit) -> lưu ảnh gốc vào
/// thư mục của app -> đọc bằng ĐƯỜNG ĐỌC V3 (ReceiptReader trong
/// ReadPipeline.swift: F1->F2->F3->F4->F5+ROI, chẩn đoán v2 bắt buộc) ->
/// màn Review. Không có bước nào gửi ảnh ra ngoài iPhone.
/// WP3 thêm đường nạp file từ Files: PDF có lớp chữ -> trích thẳng vào cùng
/// đường đọc (không qua OCR); PDF không lớp chữ -> render trang -> đọc;
/// file ảnh -> đọc như đường chọn ảnh.
/// V3 (Pha 4): file này chỉ còn là VỎ UI + hàng chờ nạp — toàn bộ cơ chế
/// đọc cũ (recognizeLines/yieldScore/cắt lát/ứng viên phái sinh kiểu
/// OCRFIX) đã GỠ sang module dùng chung; không còn bộ đọc thứ hai nào
/// trong app (luật 1.6).
struct ScanView: View {
    /// WP3 bước 2: file anh mở bằng "Mở bằng Sổ Hóa Đơn" / Share Sheet —
    /// ContentView nhận qua onOpenURL rồi truyền xuống đây; ScanView hút
    /// vào CÙNG importQueue của đường Files (không có đường nạp thứ hai).
    @Binding var externalImportURLs: [URL]
    /// L-2026-11-20-44 (đính chính): tín hiệu mở khoá TƯỜNG MINH từ
    /// ContentView (tăng 1 mỗi lần mở khoá thành công) — ScanView
    /// nghe tick này để hút file chờ đã qua cổng khoá, vì thay đổi
    /// của binding cổng tự-tính không phát hiện tin cậy được bằng
    /// .onChange(of: externalImportURLs).
    var unlockTick: Int
    @State private var showCamera = false
    // S1: cover chụp mặc định là camera tự dựng (ScanCameraView);
    // khi máy không dùng được camera tự dựng (không có camera /
    // bị từ chối quyền) anh chọn đường lùi này thì đổi sang máy
    // quét hệ thống trong cùng một cover.
    @State private var useSystemScanner = false
    @State private var showPhotoPicker = false
    @State private var pickerItem: PhotosPickerItem? = nil
    @State private var isProcessing = false
    @State private var statusText: String? = nil
    @State private var errorText: String? = nil
    @State private var draft: ScanDraft? = nil
    /// WP3: hàng chờ nạp NHIỀU file một lúc (Master Plan WP3) — xử lý lần
    /// lượt từng file, mỗi file một màn Review; đóng Review thì nạp tiếp.
    @State private var importQueue: [URL] = []
    /// A11(i) (vòng 2, WP8): số file đã lấy ra khỏi hàng chờ trong lô
    /// đang chạy — để hiện "Đang đọc 3/12 tờ…". Chỉ HIỂN THỊ: thứ tự
    /// đọc, luồng Kiểm Lại từng tờ và hợp đồng bản nháp không đổi.
    @State private var importBatchTaken = 0
    /// Dòng tiến độ cho lần đọc KẾ TIẾP của đường nạp file — runRead
    /// dùng một lần rồi xoá; presentDraft cũng xoá (không rò sang
    /// lượt chụp camera).
    @State private var importProgressText: String? = nil
    /// GÓI V4-4 (D-V4-2, sửa A2-05): cổng chất lượng theo TỪNG TỜ —
    /// mỗi lần đọc tạo một QualityGate MỚI (xem các điểm gọi
    /// runRead), không còn instance sống cho cả phiên.
    /// G4: từ bản này cổng KHÔNG còn chặn tờ mới đọc — quyết
    /// định .block (nếu bộ ngưỡng tương lai bật lại) chỉ ghi
    /// nhận nội bộ, tờ vẫn vào Kiểm Lại kèm cảnh báo mạnh (xem
    /// runRead). Hai trạng thái chặn dưới đây CHỈ còn phục vụ
    /// bản chụp bị chặn do bản TRƯỚC G4 ghi xuống đĩa
    /// (PendingBlockStore — khôi phục ở restorePendingBlockIfNeeded
    /// để tờ của sự cố 2026-11-15 không mất đường quyết định).
    @State private var blockedDraft: ScanDraft? = nil
    @State private var blockedQuality: QualityOutcome? = nil
    /// G3: lớp sửa dở ở Kiểm Lại khôi phục từ bản chụp nháp
    /// (PendingDraftSnapshot.reviewEdits) — chỉ đặt khi khôi
    /// phục, truyền vào ReviewView để dựng lại các ô anh đã
    /// sửa; bản nháp mới ra đời thì presentDraft xoá về nil.
    @State private var restoredReviewEdits: ReviewEditsDTO? = nil

    /// Máy quét của hệ thống (VisionKit) — giữ nguyên làm
    /// ĐƯỜNG LÙI khi camera tự dựng không dùng được trên máy
    /// (không có camera / bị từ chối quyền), và vẫn là đường
    /// quét lại ảnh gốc ở màn chi tiết.
    private var systemScannerCover: some View {
        DocumentCameraView(
            onScan: { scan in
                showCamera = false
                guard scan.pageCount > 0 else {
                    errorText = "Chưa chụp được trang nào — anh thử lại giúp."
                    return
                }
                // V3 (Pha 4): đọc MỌI trang của lượt quét
                // (hoá đơn dài nhiều trang — nối chữ ở tầng
                // ráp dòng của pipeline), thay giới hạn
                // trang đầu của Build 1.
                process(scan: scan)
            },
            onCancel: { showCamera = false },
            onError: { error in
                showCamera = false
                errorText = "Quét thất bại: \(error.localizedDescription)"
            }
        )
        .ignoresSafeArea()
    }

    private var cameraSupported: Bool {
        VNDocumentCameraViewController.isSupported
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                // UI-2026-11-13: biểu tượng thương hiệu + tiêu đề
                // lớn ở tab Chụp (điểm vào chính của app).
                ZStack {
                    Circle()
                        .fill(DS.heroGradient)
                        .frame(width: 104, height: 104)
                        .shadow(color: Color(red: 0.016, green: 0.235, blue: 0.157).opacity(0.45), radius: 14, x: 0, y: 7)
                    Image(systemName: "doc.viewfinder")
                        .font(.system(size: 46))
                        .foregroundStyle(.white)
                }
                Text("Chụp hoá đơn giấy, app tự đọc: tiệm, ngày, từng món, tổng tiền và đuôi thẻ — rồi gợi ý Cá nhân / Business theo thẻ đã đăng ký.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if isProcessing {
                    ProgressView()
                    Text(statusText ?? "Đang đọc hoá đơn…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        errorText = nil
                        showCamera = true
                    } label: {
                        Label("Quét hoá đơn", systemImage: "camera.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!cameraSupported)
                    .padding(.horizontal)

                    Button {
                        errorText = nil
                        showPhotoPicker = true
                    } label: {
                        Label("Chọn ảnh có sẵn", systemImage: "photo.on.rectangle.angled")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(DS.brand)
                    .padding(.horizontal)

                    Button {
                        errorText = nil
                        // Gói 3 (L-2026-11-20-43, Q10a): trình
                        // picker bằng UIKit thuần ở chế độ SAO
                        // CHÉP qua ReceiptFilePickerPresenter —
                        // .fileImporter của SwiftUI (mở tại chỗ)
                        // chết ở nút Open trên bản ký lại
                        // KravaSigner y hệt bộ chọn thư mục L-36.
                        ReceiptFilePickerPresenter.present(
                            onPick: { urls in
                                // G3 (luật bền hoá): sao NGAY
                                // các URL được chọn vào thư mục
                                // chờ của app (PendingImports)
                                // rồi mới xếp hàng — hàng đợi từ
                                // đây là danh sách file CỦA APP
                                // trên đĩa, sống qua giết app.
                                // Nối vào hàng chờ sẵn có thay vì
                                // thay thế — thay thế sẽ làm rơi
                                // lặng các file đang chờ trên đĩa.
                                importQueue.append(
                                    contentsOf: stageExternalURLs(urls))
                                processNextImportedFile()
                            },
                            onCancel: {
                                // Huỷ chọn: giữ nguyên hành vi cũ
                                // của .fileImporter — không báo
                                // lỗi, không đổi trạng thái (lượt
                                // chọn đã có dòng log [app] tiền tố
                                // "NẠP FILE:" ở presenter).
                            },
                            onFailure: { error in
                                errorText = "Không nạp được file: \(error.localizedDescription)"
                            })
                    } label: {
                        Label("Nạp file (PDF / ảnh tải về)", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(DS.brand)
                    .padding(.horizontal)

                    if !cameraSupported {
                        Text("Máy này không hỗ trợ quét tài liệu (thường là máy ảo) — anh dùng nút Chọn ảnh có sẵn.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }

                if let errorText {
                    Text(errorText)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                if let statusText, !isProcessing {
                    Text(statusText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                // GÓI V4-4 (D-V4-2): trạng thái giao diện RIÊNG của
                // tờ bị cổng chất lượng chặn — tách thành view con
                // riêng (blockedBanner) để thân body không phình quá
                // ngân sách kiểm tra kiểu của trình biên dịch (lỗi
                // type-check timeout ở bản dựng run #99).
                blockedBanner
                Spacer()
                Text("Đọc ngay trên máy — ảnh hoá đơn không rời khỏi iPhone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }
            .dsScreenBackground()
            .navigationTitle("Chụp Hoá Đơn")
            .fullScreenCover(isPresented: $showCamera, onDismiss: {
                useSystemScanner = false
            }) {
                if useSystemScanner {
                    systemScannerCover
                } else {
                    // S1: đường chụp chính là camera tự dựng.
                    ScanCameraView(
                        onFinish: { images in
                            showCamera = false
                            guard !images.isEmpty else {
                                errorText = "Chưa chụp được trang nào — anh thử lại giúp."
                                return
                            }
                            process(cameraImages: images)
                        },
                        onCancel: { showCamera = false },
                        onFallbackToSystemScanner: { useSystemScanner = true }
                    )
                }
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $pickerItem, matching: .images)
            .onChange(of: pickerItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        process(image: image, source: .photoLibrary)
                    } else {
                        errorText = "Không mở được ảnh đã chọn."
                    }
                    pickerItem = nil
                }
            }
            // WP3 + Gói 3 (L-2026-11-20-43): nạp từ Files KHÔNG
            // còn qua .fileImporter ở đây — nút "Nạp file (PDF /
            // ảnh tải về)" ở trên gọi thẳng
            // ReceiptFilePickerPresenter (UIKit thuần, chế độ
            // sao chép, chọn nhiều file một lúc) vì .fileImporter
            // chết ở nút Open trên bản ký lại. Đường sau nạp
            // (stageExternalURLs -> importQueue ->
            // processNextImportedFile) giữ nguyên từng chữ.
            .sheet(item: $draft, onDismiss: { processNextImportedFile() }) { d in
                // P-DRAFT (L-2026-11-13-14): onDone của ReviewView
                // CHỈ cháy ở đúng hai điểm — lưu thành công (cuối
                // save()) và nút "Huỷ, không lưu" tường minh — nên
                // xoá bản chụp nháp tại đây là khớp cả hai trường
                // hợp kết thúc. Vuốt đóng sheet KHÔNG qua onDone:
                // bản chụp còn nguyên trên đĩa để lần mở app/tab
                // sau khôi phục lại đúng bản nháp này.
                ReviewView(draft: d, restoredEdits: restoredReviewEdits) {
                    PendingDraftStore.clear()
                    restoredReviewEdits = nil
                    draft = nil
                }
            }
            // WP3 bước 2: file tới qua onOpenURL trong lúc màn Chụp đã
            // hiện -> hút ngay vào hàng chờ chung.
            .onChange(of: externalImportURLs) { _, _ in consumeExternalImports() }
            // L-2026-11-20-44 (đính chính): tín hiệu mở khoá tường
            // minh — file chờ lúc app khoá chỉ hiện ra sau khi mở
            // khoá (binding cổng tự-tính, .onChange ở trên không
            // cháy tin cậy) -> tick tăng thì hút lại file chờ.
            .onChange(of: unlockTick) { _, _ in consumeExternalImports() }
            // Lần đầu màn Chụp hiện: hút file đã chờ sẵn (anh mở file khi
            // app đang khoá Face ID / đang ở tab khác) + quét thư mục
            // Inbox phòng trường hợp hệ thống chép file vào trước khi
            // onOpenURL kịp chạy (khởi động lạnh).
            .onAppear {
                // G3: khôi phục tờ BỊ CHẶN trước tiên — quyết
                // định chặn chưa thi hành đứng trên mọi việc dở
                // khác, và mọi đường đọc/hàng chờ đều đang bị nó
                // canh sẵn nên không gì chen qua được.
                restorePendingBlockIfNeeded()
                // P-DRAFT (L-2026-11-13-14): khôi phục bản nháp chờ
                // TRƯỚC — khi có draft, processNextImportedFile tự
                // giữ hàng chờ nạp đứng chờ theo luật cũ, không có
                // đường nạp nào chen vào bản nháp vừa khôi phục.
                restorePendingDraftIfNeeded()
                consumeExternalImports()
                sweepInbox()
                sweepPendingImports()
            }
        }
    }

    /// G3: dựng lại ĐÚNG khung chặn của tờ bị cổng chất lượng
    /// chặn ở lượt mở trước (sự cố 2026-11-15: thoát app là mất
    /// tờ bị chặn). Bản chụp xuống đĩa ngay khi cổng phán .block
    /// (xem runRead) nên khôi phục ở đây là đường chính thức,
    /// không phải cứu hộ. Chỉ dựng khi đang rảnh tay; bản chụp
    /// không ánh xạ lại được (mã lạ) -> xoá + log như snapshot
    /// nháp, app mở bình thường.
    private func restorePendingBlockIfNeeded() {
        guard blockedDraft == nil, draft == nil, !isProcessing else { return }
        guard let snapshot = PendingBlockStore.load() else { return }
        guard let restored = snapshot.makeBlocked() else {
            PendingBlockStore.discardCorrupt(
                reason: "snapshot bị chặn không ánh xạ lại được thành trạng thái chặn")
            return
        }
        blockedDraft = restored.draft
        blockedQuality = restored.quality
        statusText = "Đã khôi phục tờ bị cổng chất lượng chặn từ lần mở trước — anh quyết định ở khung cảnh báo bên dưới giúp."
    }

    /// P-DRAFT (L-2026-11-13-14): mở lại màn Kiểm Lại với bản nháp
    /// đã chụp xuống đĩa ở lượt trước (app bị hệ thống giết trong
    /// lúc anh đang kiểm dở). Chỉ khôi phục khi đang rảnh tay:
    /// đang có draft khác hoặc đang đọc dở thì bỏ qua — lượt tạo
    /// draft mới sẽ tự chụp snapshot mới đè lên. Snapshot hỏng:
    /// PendingDraftStore.load/discardCorrupt tự xoá + ghi log,
    /// hàm này trả về lặng, app mở bình thường.
    /// G3: lớp sửa dở trong bản chụp (reviewEdits) đi kèm sang
    /// ReviewView; tờ đang bị chặn thì nháp đứng chờ sau nó.
    private func restorePendingDraftIfNeeded() {
        guard draft == nil, blockedDraft == nil, !isProcessing else { return }
        guard let snapshot = PendingDraftStore.load() else { return }
        guard let restored = snapshot.makeDraft() else {
            PendingDraftStore.discardCorrupt(
                reason: "snapshot không ánh xạ lại được thành ScanDraft")
            return
        }
        restoredReviewEdits = snapshot.reviewEdits
        draft = restored
        statusText = "Đã khôi phục bản nháp chưa lưu từ lần mở trước — anh kiểm lại rồi bấm Lưu giúp."
    }

    /// Đổ URL từ onOpenURL vào hàng chờ nạp chung rồi xoá danh sách chờ —
    /// điểm nạp DUY NHẤT vẫn là processNextImportedFile/processImportedFile.
    /// G3: URL mở-tại-chỗ cũng qua sao-chép bền như đường Files
    /// (stageExternalURLs) — URL nằm sẵn trong Documents (hệ
    /// thống chép vào Inbox) được giữ nguyên vì đã bền sẵn.
    private func consumeExternalImports() {
        guard !externalImportURLs.isEmpty else { return }
        importQueue.append(contentsOf: stageExternalURLs(externalImportURLs))
        externalImportURLs = []
        processNextImportedFile()
    }

    /// Thư mục Documents/Inbox là nơi iOS chép file khi app được mở bằng
    /// một file mà không mở-tại-chỗ. File còn sót ở đó (onOpenURL chưa
    /// chạy hoặc app bị giết giữa chừng) được nạp nốt ở đây; bản sao
    /// Inbox bị xoá ngay trong processImportedFile sau khi đọc xong
    /// dữ liệu, nên quét lại không nạp trùng.
    /// G3: chỉ nối các file CHƯA có trong hàng chờ — onAppear
    /// cháy mỗi lần tab Chụp hiện, quét lại mà nối trùng thì một
    /// file chờ xử lý bị đọc hai lần.
    private func sweepInbox() {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let inbox = docs.appendingPathComponent("Inbox", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil) else { return }
        let stray = files.filter { !$0.hasDirectoryPath && !importQueue.contains($0) }
        guard !stray.isEmpty else { return }
        importQueue.append(contentsOf: stray)
        processNextImportedFile()
    }

    // MARK: G3 — hàng chờ nạp bền (Documents/PendingImports)
    //
    // Thư mục này CHÍNH LÀ hàng đợi trên đĩa: file anh chọn từ
    // Files / mở-tại-chỗ được sao vào đây NGAY khi tới (khi
    // quyền truy cập bảo mật còn sống), xử lý xong từng file
    // thì bản sao bị xoá trong processImportedFile. App chết
    // giữa lô -> lần mở sau sweepPendingImports xếp lại đúng
    // các file còn nằm đây, theo thứ tự thời gian sao vào.

    /// Tên thư mục chờ — dùng chung cho điểm sao vào, điểm
    /// quét lại và điểm xoá bản sao sau khi xử lý.
    static let pendingImportsDirectoryName = "PendingImports"

    private func pendingImportsDirectory() -> URL? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let dir = docs.appendingPathComponent(Self.pendingImportsDirectoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Sao các URL NGOÀI app vào thư mục chờ và trả URL của app;
    /// URL đã nằm trong Documents của app (Inbox...) trả nguyên
    /// — chúng bền sẵn, sao nữa chỉ sinh bản trùng. Sao hỏng
    /// một file (hết dung lượng...) thì giữ URL gốc cho file đó:
    /// lượt này vẫn xử lý được trong phiên như hành vi cũ, chỉ
    /// là không bền qua giết app — không chặn cả lô vì một file.
    private func stageExternalURLs(_ urls: [URL]) -> [URL] {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return urls }
        let docsPath = docs.standardizedFileURL.path + "/"
        return urls.map { url in
            if url.standardizedFileURL.path.hasPrefix(docsPath) { return url }
            guard let dir = pendingImportsDirectory() else { return url }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            // Tiền tố mốc giây + mã ngẫu nhiên ngắn: tên duy
            // nhất kể cả khi anh chọn trùng tên file hai lần,
            // và thứ tự tên xấp xỉ thứ tự tới.
            let stamp = Int(Date().timeIntervalSince1970)
            let name = "\(stamp)-\(UUID().uuidString.prefix(8))-\(url.lastPathComponent)"
            let dest = dir.appendingPathComponent(name)
            do {
                try FileManager.default.copyItem(at: url, to: dest)
                return dest
            } catch {
                return url
            }
        }
    }

    /// Xếp lại các file còn trong thư mục chờ (lô nạp bị ngắt
    /// bởi giết app / chu kỳ khoá ở lượt trước) vào hàng chờ
    /// trong bộ nhớ, theo thời gian sao vào — chỉ nối file
    /// chưa có trong hàng chờ, như sweepInbox.
    private func sweepPendingImports() {
        guard let dir = pendingImportsDirectory(),
              let files = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let stray = files.filter { !$0.hasDirectoryPath && !importQueue.contains($0) }
        guard !stray.isEmpty else { return }
        let ordered = stray.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return da != db ? da < db : a.lastPathComponent < b.lastPathComponent
        }
        importQueue.append(contentsOf: ordered)
        processNextImportedFile()
    }


    // MARK: Pipeline V3: lưu ảnh gốc -> ReceiptReader (đường đọc duy
    // nhất) -> bản nháp. Mọi đường nạp đều qua runRead ở dưới.

    /// Ánh xạ nguồn nạp của app (SourceType) sang nguồn nạp của
    /// pipeline (IntakeSource — ghi vào hồ sơ chẩn đoán).
    private func intakeSource(for source: SourceType) -> IntakeSource {
        switch source {
        case .camera: return .documentScanner
        case .photoLibrary: return .photoLibrary
        case .fileImport, .pdfImport: return .fileImport
        case .screenshot, .unknown: return .photoLibrary
        }
    }

    /// Đường quét tài liệu: lưu MỌI trang làm bằng chứng TRƯỚC
    /// (trang 1 = ảnh chính, mọi trang vào originalFileNames —
    /// cùng luật toàn-hay-không của applyRescannedOriginal: lưu
    /// dở dang thì xoá phần đã lưu và báo lỗi, không đọc nửa vời),
    /// rồi đọc đa trang qua pipeline (nối chữ ở tầng ráp dòng).
    private func process(scan: VNDocumentCameraScan) {
        // Tờ bị chặn chưa được quyết định thì không đọc tờ mới
        // chen qua (trạng thái bị chặn là của riêng tờ đó).
        guard blockedDraft == nil else {
            statusText = "Anh quyết định tờ đang bị chặn trước, rồi mới đọc tờ tiếp theo giúp."
            return
        }
        var names: [String] = []
        var images: [UIImage] = []
        for index in 0..<scan.pageCount {
            let image = scan.imageOfPage(at: index)
            guard let name = ImageStore.saveJPEG(image) else {
                for saved in names { ImageStore.delete(fileName: saved) }
                errorText = "Không lưu được ảnh gốc vào máy — anh kiểm tra dung lượng trống giúp."
                return
            }
            names.append(name)
            images.append(image)
        }
        guard !names.isEmpty else { return }
        let pageCG = images.compactMap { ReceiptReader.uprightCGImage(from: $0) }
        guard pageCG.count == images.count, !pageCG.isEmpty else {
            errorText = "Không dựng được ảnh đã quét để đọc."
            return
        }
        // S2: làm phẳng từng trang trước khi đọc (bản phẳng là
        // đầu vào chính; trang nào không có góc tin cậy thì lùi
        // về ảnh gốc như trước).
        flattenThenRead(names: names, pageCG: pageCG)
    }

    /// S1: điểm vào của camera tự dựng — cùng giao kèo với
    /// process(scan:): lưu MỌI trang nguyên gốc TRƯỚC (gốc là
    /// bằng chứng), tất cả-hoặc-không; rồi làm phẳng + đọc.
    private func process(cameraImages: [UIImage]) {
        guard blockedDraft == nil else {
            statusText = "Anh quyết định tờ đang bị chặn trước, rồi mới đọc tờ tiếp theo giúp."
            return
        }
        var names: [String] = []
        var images: [UIImage] = []
        for image in cameraImages {
            guard let name = ImageStore.saveJPEG(image) else {
                for saved in names { ImageStore.delete(fileName: saved) }
                errorText = "Không lưu được ảnh gốc vào máy — anh kiểm tra dung lượng trống giúp."
                return
            }
            names.append(name)
            images.append(image)
        }
        guard !names.isEmpty else { return }
        let pageCG = images.compactMap { ReceiptReader.uprightCGImage(from: $0) }
        guard pageCG.count == images.count, !pageCG.isEmpty else {
            errorText = "Không dựng được ảnh đã chụp để đọc."
            return
        }
        flattenThenRead(names: names, pageCG: pageCG)
    }

    /// S2: bước chung của HAI đường chụp (camera tự dựng + máy
    /// quét hệ thống): mỗi trang thử tạo BẢN SCAN PHẲNG toàn
    /// phân giải từ tứ giác phát hiện được và lưu kèm ảnh gốc
    /// (quy ước tên ở FlatScan — KHÔNG đổi model). Trang nào có
    /// bản phẳng thì bản phẳng là ảnh đọc của trang đó; không
    /// có góc tin cậy -> giữ ảnh gốc (đường cũ). Đường nhập thư
    /// viện ảnh / Files KHÔNG qua bước này: chúng giữ nguyên
    /// pipeline cũ (ứng viên phối cảnh nội bộ vẫn phục vụ ở đó
    /// như trước). Chạy nền; runRead tự lo phần còn lại.
    private func flattenThenRead(names: [String], pageCG: [CGImage]) {
        isProcessing = true
        statusText = "Đang làm phẳng bản scan…"
        DispatchQueue.global(qos: .userInitiated).async {
            var readPages: [CGImage] = []
            for (index, cg) in pageCG.enumerated() {
                var readCG = cg
                if let flat = FlatScan.makeFlatImage(from: cg),
                   FlatScan.saveFlatImage(flat,
                                          forOriginal: names[index]) != nil {
                    readCG = flat
                }
                readPages.append(readCG)
            }
            DispatchQueue.main.async {
                runRead(request: ReadRequest(
                            source: .documentScanner,
                            imageFileName: names[0],
                            image: readPages[0],
                            pageImages: readPages,
                            diagnosticsDirectory: ImageStore.directory,
                            taxLandingContext: TaxLandingContextBuilder.make(),
                            qualityGate: QualityGate()),
                        sourceType: .camera,
                        originalFileNames: names)
            }
        }
    }

    /// Đường ảnh đơn (chọn ảnh / file ảnh / trang PDF đã render):
    /// lưu JPEG gốc trước, dựng thẳng ở pixel gốc, rồi đọc.
    private func process(image: UIImage, source: SourceType,
                         sourceFileName: String? = nil,
                         originalFileNames: [String] = [],
                         pdfRenderScale: Double? = nil) {
        guard blockedDraft == nil else {
            statusText = "Anh quyết định tờ đang bị chặn trước, rồi mới đọc tờ tiếp theo giúp."
            processNextImportedFile()
            return
        }
        guard let fileName = ImageStore.saveJPEG(image) else {
            errorText = "Không lưu được ảnh gốc vào máy — anh kiểm tra dung lượng trống giúp."
            processNextImportedFile()
            return
        }
        guard let cg = ReceiptReader.uprightCGImage(from: image) else {
            errorText = "Không dựng được ảnh để đọc."
            processNextImportedFile()
            return
        }
        runRead(request: ReadRequest(
                    source: intakeSource(for: source),
                    imageFileName: fileName,
                    image: cg,
                    pdfRenderScale: pdfRenderScale,
                    diagnosticsDirectory: ImageStore.directory,
                    taxLandingContext: TaxLandingContextBuilder.make(),
                    qualityGate: QualityGate()),
                sourceType: source,
                sourceFileName: sourceFileName,
                originalFileNames: originalFileNames)
    }

    /// Chạy MỘT lần đọc trên hàng đợi nền (pipeline gồm nhiều ứng
    /// viên + tối đa 2 vòng ROI — không chạy trên main) rồi hạ
    /// cánh thành bản nháp trên main, đúng kỷ luật bất đồng bộ
    /// của đường đọc cũ.
    private func runRead(request: ReadRequest,
                         sourceType: SourceType,
                         sourceFileName: String? = nil,
                         originalFileNames: [String] = [],
                         rawTextIsPDFTextLayer: Bool = false) {
        isProcessing = true
        statusText = importProgressText ?? "Đang đọc hoá đơn…"
        importProgressText = nil
        errorText = nil
        var request = request
        // GÓI V4-4 (D-V4-2): cổng MỚI cho riêng lần đọc này khi
        // tầng gọi chưa cấp — không bao giờ dùng cổng của tờ khác.
        if request.qualityGate == nil { request.qualityGate = QualityGate() }
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = ReceiptReader.read(request)
            DispatchQueue.main.async {
                isProcessing = false
                // Không dòng chữ nào đọc được -> cùng thông báo lỗi
                // như đường cũ, không mở Review với tờ rỗng.
                if outcome.result.rawText
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty {
                    // P2-0/B-7: lượt đọc RỖNG thì xoá file đã
                    // lưu của chính lượt này (ảnh chính + file
                    // gốc kèm + hồ sơ chẩn đoán) — bản cũ để
                    // chúng thành file mồ côi vĩnh viễn.
                    ImageStore.delete(fileName: request.imageFileName)
                    ImageStore.delete(fileName: DiagnosticsStore.fileName(
                        forImageFileName: request.imageFileName))
                    for name in originalFileNames
                    where name != request.imageFileName {
                        ImageStore.delete(fileName: name)
                    }
                    // S2: bản scan phẳng đi kèm cũng là file của
                    // lượt đọc rỗng này — dọn cùng, không để mồ côi.
                    FlatScan.deleteFlat(forOriginal: request.imageFileName)
                    for name in originalFileNames {
                        FlatScan.deleteFlat(forOriginal: name)
                    }
                    statusText = nil
                    errorText = "Không đọc được chữ nào trong ảnh — anh chụp lại rõ hơn, đủ sáng giúp."
                    processNextImportedFile()
                    return
                }
                let newDraft = ScanDraft(
                    result: outcome.result,
                    imageFileName: request.imageFileName,
                    sourceType: sourceType,
                    sourceFileName: sourceFileName,
                    originalFileNames: originalFileNames,
                    rawTextIsPDFTextLayer: rawTextIsPDFTextLayer,
                    provenance: outcome.provenance,
                    reconcileReport: outcome.report,
                    diagnosticsID: outcome.diagnosticsID,
                    diagnosticsWriteFailed: outcome.diagnosticsWriteFailed)
                // G4 (hạ .block -> .warn ở TẦNG HÀNH VI): cổng
                // KHÔNG còn giữ tờ nào lại. Bộ ngưỡng hiệu
                // chuẩn 2026-11-15 đặt blockEnabled = false nên
                // quyết định .block vốn không sinh ra; nhưng kể
                // cả khi một bộ ngưỡng tương lai bật lại, tầng
                // này cũng KHÔNG dựng trạng thái chặn cho tờ mới
                // đọc: quyết định .block chỉ còn là ghi nhận nội
                // bộ (cờ quality-block trong hồ sơ chẩn đoán do
                // ReadPipeline ghi), tờ đi thẳng vào Kiểm Lại
                // qua presentDraft với dòng cảnh báo mạnh nhất
                // của qualityNote, và hợp đồng P-DRAFT chụp bản
                // nháp như mọi tờ khác — không còn đường nào để
                // một quyết định của cổng làm tờ biến mất khỏi
                // luồng của anh (sự cố 2026-11-15). Khung chặn +
                // PendingBlockStore giữ nguyên CHỈ để khôi phục
                // bản chụp do bản trước G4 đã ghi (xem
                // restorePendingBlockIfNeeded).
                presentDraft(newDraft,
                             note: qualityNote(outcome.qualityOutcome))
            }
        }
    }

    /// Trình MỘT bản nháp lên màn Kiểm Lại + chụp snapshot
    /// P-DRAFT — điểm hạ cánh DUY NHẤT của cả đường đọc thường
    /// lẫn đường "Vẫn đọc tờ này" từ trạng thái bị chặn, để hợp
    /// đồng chống mất bản nháp (L-2026-11-13-14) chỉ có một nơi
    /// thi hành.
    private func presentDraft(_ newDraft: ScanDraft, note: String?) {
        importProgressText = nil
        statusText = note
        // G3: bản nháp MỚI ra đời thì không có lớp sửa dở khôi
        // phục nào đi kèm — xoá dấu vết của bản nháp trước kẻo
        // ReviewView dựng nhầm các ô sửa của tờ khác.
        restoredReviewEdits = nil
        draft = newDraft
        // P-DRAFT (L-2026-11-13-14): chụp bản nháp xuống đĩa NGAY
        // khi nó được trình, TRƯỚC khi sheet Kiểm Lại hiện — từ
        // khoảnh khắc này, việc dở của anh sống trên đĩa chứ
        // không chỉ trong @State. Ghi hỏng (hết dung lượng...)
        // thì nói thật bằng dòng trạng thái để anh biết mà lưu
        // sớm, không lặng im quay về chế độ dễ mất như trước.
        if !PendingDraftStore.save(PendingDraftSnapshot(draft: newDraft)) {
            let warning = "Chưa ghi được bản nháp phòng hờ xuống máy — anh lưu sớm giúp, đừng rời app lâu kẻo mất bản đang kiểm."
            statusText = statusText.map { $0 + " " + warning } ?? warning
        }
    }

    /// Chữ mô tả các vấn đề chất lượng đã phát hiện — dùng chung
    /// cho dòng nhắc .warn, khung .block và dòng ghi đè.
    private func qualityIssueText(_ outcome: QualityOutcome) -> String {
        var issues: [String] = []
        for detected in outcome.detected {
            switch detected {
            case "blur": issues.append("hơi mờ")
            case "glare": issues.append("bị chói sáng")
            case "lowContrast": issues.append("tương phản thấp (chữ nhạt)")
            default: issues.append(detected)
            }
        }
        return issues.isEmpty ? "chất lượng chưa đạt"
            : issues.joined(separator: ", ")
    }

    /// GÓI V4-4 (D-V4-2): khung trạng thái của tờ bị cổng chất
    /// lượng chặn. Tờ nằm yên ở đây cho tới khi anh chọn một
    /// trong hai hành động — hàng chờ nạp cũng đứng chờ
    /// (processNextImportedFile canh blockedDraft), không tờ
    /// nào chen qua mặt. Tách khỏi body vì ngân sách kiểm tra
    /// kiểu của trình biên dịch (run #99).
    /// G4: khung này CHỈ còn hiện cho bản chụp bị chặn khôi
    /// phục từ đĩa (bản trước G4 ghi) — tờ mới đọc không bao
    /// giờ vào đây nữa (xem runRead).
    @ViewBuilder
    private var blockedBanner: some View {
        if blockedDraft != nil, let quality = blockedQuality {
            VStack(spacing: 12) {
                Label("Tờ này bị cổng chất lượng chặn",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text("Ảnh \(qualityIssueText(quality)) — app chưa mở tờ này để kiểm hay lưu. Ảnh gốc của tờ vẫn đã lưu trong máy. Anh chụp / chọn lại rõ hơn, hoặc vẫn đọc tờ này nếu không chụp lại được.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                HStack(spacing: 12) {
                    Button {
                        // G3: quyết định ĐÃ thi hành (bỏ tờ này)
                        // -> bản chụp bị chặn hết việc, xoá ngay.
                        PendingBlockStore.clear()
                        blockedDraft = nil
                        blockedQuality = nil
                        statusText = nil
                        errorText = nil
                        processNextImportedFile()
                    } label: {
                        Label("Chụp / chọn lại", systemImage: "camera.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button {
                        guard let d = blockedDraft,
                              let q = blockedQuality else { return }
                        // G3: quyết định ĐÃ thi hành (đọc tiếp) ->
                        // xoá bản chụp bị chặn; tờ từ đây sống
                        // tiếp dưới hợp đồng P-DRAFT do
                        // presentDraft chụp ngay sau đây.
                        PendingBlockStore.clear()
                        blockedDraft = nil
                        blockedQuality = nil
                        presentDraft(d, note: blockedNote(q))
                    } label: {
                        Label("Vẫn đọc tờ này", systemImage: "doc.text.magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(DS.brand)
                }
            }
            .padding()
            .background(Color.orange.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
        }
    }

    /// Dòng nhắc chất lượng lúc chụp. G4: MỌI quyết định khác
    /// .pass đều đi qua đây — kể cả .block (từ bản này chỉ là
    /// ghi nhận nội bộ, tờ vẫn vào Kiểm Lại, xem runRead) và
    /// cảnh báo LEO THANG khi nhiều tờ liên tiếp cùng kém
    /// (QualityGate.escalated): chữ mạnh dần theo mức, nhưng
    /// tờ luôn đi tiếp, không gì bị giữ lại.
    private func qualityNote(_ outcome: QualityOutcome?) -> String? {
        guard let outcome, outcome.decision != .pass else { return nil }
        if outcome.decision == .block {
            return "Ảnh \(qualityIssueText(outcome)) — cổng chất lượng đánh giá tờ này rất kém, nhưng bản này chỉ cảnh báo chứ không chặn: anh kiểm tra kỹ từng số ở màn sau giúp."
        }
        if outcome.escalated {
            return "Ảnh \(qualityIssueText(outcome)) — đây là tờ thứ \(outcome.consecutiveRejects) liên tiếp ảnh chưa đạt: anh kiểm tra kỹ các số ở màn sau giúp, và nếu chụp lại được thì đủ sáng, tránh chói, giữ máy yên."
        }
        return "Ảnh \(qualityIssueText(outcome)) — anh kiểm tra kỹ các số ở màn sau giúp."
    }

    /// Dòng trạng thái khi anh bấm "Vẫn đọc tờ này" ở khung bị
    /// chặn: nói rõ đây là đọc theo quyết định của anh.
    private func blockedNote(_ outcome: QualityOutcome) -> String {
        "Đã đọc tờ bị chặn theo yêu cầu của anh (ảnh \(qualityIssueText(outcome))) — anh kiểm tra kỹ các số ở màn sau giúp."
    }

    // MARK: - WP3: nạp file từ Files (CODE-AUDIT F1)

    /// Lấy file tiếp theo trong hàng chờ — chỉ chạy khi không có bản nháp
    /// nào đang mở và không có OCR nào đang chạy. Được gọi từ: kết quả của
    /// ReceiptFilePickerPresenter qua onPick, đường hút file mở-từ-ngoài
    /// (consumeExternalImports) và các lượt quét bù Inbox/PendingImports,
    /// lúc đóng màn Review (onDismiss), và các nhánh lỗi/thoát sớm của
    /// đường nạp file (để một file hỏng không chặn cả lô).
    private func processNextImportedFile() {
        // A11(i): lô cạn và không còn tờ nào đang dở -> đếm lại từ 0.
        if importQueue.isEmpty, draft == nil, blockedDraft == nil, !isProcessing {
            importBatchTaken = 0
            importProgressText = nil
        }
        guard draft == nil, blockedDraft == nil, !isProcessing, !importQueue.isEmpty else { return }
        let url = importQueue.removeFirst()
        importBatchTaken += 1
        let total = importBatchTaken + importQueue.count
        importProgressText = total > 1 ? "Đang đọc \(importBatchTaken)/\(total) tờ…" : nil
        processImportedFile(url: url)
    }

    private func processImportedFile(url: URL) {
        // File nằm ngoài sandbox: mở quyền truy cập bảo mật và LUÔN đóng
        // trong cùng lượt gọi này. Mọi lần đọc file đều ĐỒNG BỘ tại đây —
        // đường OCR bất đồng bộ phía sau chỉ dùng UIImage + JPEG đã lưu
        // trong app, không chạm lại URL này nữa.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            errorText = "Không đọc được file \(url.lastPathComponent)."
            processNextImportedFile()
            return
        }
        // File do hệ thống chép vào Documents/Inbox của app: dữ liệu đã
        // nằm trong bộ nhớ (và PDF sẽ được lưu nguyên byte vào
        // ReceiptImages ở bước sau) nên xoá bản sao Inbox ngay — để sót
        // là lần mở sau quét Inbox sẽ nạp trùng tờ này. File mở-tại-chỗ
        // từ Files KHÔNG nằm trong Inbox -> tuyệt đối không đụng vào
        // file gốc của anh.
        // G3: cùng luật cho bản sao ở thư mục chờ PendingImports
        // (do stageExternalURLs sao vào) — dữ liệu đã vào bộ nhớ
        // thì bản sao chờ hết việc; để sót là lần mở sau quét
        // thư mục chờ sẽ nạp trùng tờ này.
        removeAppStagedCopyIfNeeded(url)
        if url.pathExtension.lowercased() == "pdf" {
            processImportedPDF(data: data, sourceFileName: url.lastPathComponent)
        } else if let image = UIImage(data: data) {
            process(image: image, source: .fileImport, sourceFileName: url.lastPathComponent)
        } else {
            errorText = "File \(url.lastPathComponent) không phải PDF hay ảnh đọc được."
            processNextImportedFile()
        }
    }

    /// Xoá `url` CHỈ khi nó là bản sao CỦA APP: nằm trong
    /// Documents/Inbox (hệ thống chép vào) hoặc Documents/
    /// PendingImports (G3 sao vào lúc nhận file). File gốc của
    /// anh ở Files/iCloud không bao giờ nằm ở hai thư mục này.
    private func removeAppStagedCopyIfNeeded(_ url: URL) {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let path = url.standardizedFileURL.path
        for sub in ["Inbox", Self.pendingImportsDirectoryName] {
            let dirPath = docs.appendingPathComponent(sub, isDirectory: true).standardizedFileURL.path
            if path.hasPrefix(dirPath + "/") {
                try? FileManager.default.removeItem(at: url)
                return
            }
        }
    }

    private func processImportedPDF(data: Data, sourceFileName: String) {
        // Bằng chứng gốc lưu TRƯỚC, nguyên byte (CODE-AUDIT F1 mục 5) —
        // lưu hỏng thì báo lỗi thật, không đi tiếp như đã có bằng chứng.
        guard let storedPDFName = ImageStore.saveFile(data: data, fileExtension: "pdf") else {
            errorText = "Không lưu được file PDF gốc vào máy — anh kiểm tra dung lượng trống giúp."
            processNextImportedFile()
            return
        }
        if let lines = textLayerLines(pdfData: data) {
            // Lớp chữ là chữ thật do hệ thống của tiệm tạo ra — không phải
            // chữ đoán — nên độ tin cậy 1.0 (CODE-AUDIT F1 mục 4). Đường
            // chữ đi vào CÙNG ReceiptReader như mọi đường khác (không
            // parser thứ hai): F4+F5 chạy trên đúng các dòng này, hồ sơ
            // chẩn đoán ghi nguồn pdfTextLayer. File PDF chính là bằng
            // chứng: imageFileName trỏ thẳng tới nó, các màn hiển thị
            // render trang 1 qua ImageStore.load.
            runRead(request: ReadRequest(
                        source: .pdfTextLayer,
                        imageFileName: storedPDFName,
                        byteSize: data.count,
                        textLines: lines,
                        diagnosticsDirectory: ImageStore.directory,
                        taxLandingContext: TaxLandingContextBuilder.make(),
                        qualityGate: QualityGate()),
                    sourceType: .pdfImport,
                    sourceFileName: sourceFileName,
                    originalFileNames: [storedPDFName],
                    rawTextIsPDFTextLayer: true)
            return
        }
        // Không có lớp chữ (PDF là ảnh scan): render trang 1 -> đường ảnh.
        // PDF gốc vẫn là bằng chứng chính (originalFileNames); JPEG render
        // là nguồn đọc. Hoá đơn PDF nhiều trang -> xử lý nhiều trang ở WP8;
        // bước này giữ đúng giới hạn 1 trang như Build 1 và ghi rõ ở cổng.
        guard let doc = PDFDocument(data: data), doc.pageCount > 0,
              let image = renderPageImage(doc.page(at: 0)) else {
            errorText = "PDF không có lớp chữ và không render được trang nào để đọc."
            processNextImportedFile()
            return
        }
        process(image: image, source: .pdfImport, sourceFileName: sourceFileName,
                originalFileNames: [storedPDFName],
                pdfRenderScale: 200.0 / 72.0)
    }

    /// Trích lớp chữ nhúng trong PDF (PDFKit — có từ iOS 11, không phải
    /// framework lạ lúc khởi động; chỉ chạm khi anh bấm nạp file, đúng
    /// luật TEAM.md #1). Trả nil khi PDF không chứa dòng chữ nào — đó là
    /// tín hiệu rẽ sang đường render->OCR, KHÔNG phải lỗi.
    /// Thứ tự dòng = thứ tự nội dung từng trang (page.string); với hoá đơn
    /// do máy tạo thì đó là thứ tự đọc (CODE-AUDIT F1 mục 3).
    private func textLayerLines(pdfData: Data) -> [OCRLine]? {
        guard let doc = PDFDocument(data: pdfData) else { return nil }
        var lines: [OCRLine] = []
        for index in 0..<doc.pageCount {
            guard let page = doc.page(at: index), let text = page.string else { continue }
            for rawLine in text.components(separatedBy: .newlines) {
                let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    lines.append(OCRLine(text: trimmed, confidence: 1.0))
                }
            }
        }
        return lines.isEmpty ? nil : lines
    }

    /// Render 1 trang PDF thành ảnh ~200 dpi cho đường OCR. Phép biến đổi
    /// lật trục Y theo mẫu chuẩn của Quartz (PDF gốc toạ độ dưới-trái,
    /// ảnh bitmap trên-trái) — hướng ảnh render phải được kiểm trên máy ở
    /// mốc M1 (ghi ở WP3-GATE.md, mục chưa kiểm chứng).
    private func renderPageImage(_ page: PDFPage?) -> UIImage? {
        guard let page = page else { return nil }
        let bounds = page.bounds(for: .cropBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let scaleFactor = 200.0 / 72.0
        var size = CGSize(width: bounds.width * scaleFactor, height: bounds.height * scaleFactor)
        // A2-06 (rà soát vòng 2, 2026-11-13): trần cạnh dài
        // 4096px — PDF khổ lớn ở 200dpi có thể dựng bitmap
        // hàng chục MP và bị hệ thống giết vì bộ nhớ ngay
        // trong thao tác nạp. Hạ kích thước tương ứng, giữ
        // tỉ lệ (phép vẽ ở dưới tỉ lệ theo size/bounds nên
        // tự đúng); trang PDF thường (Letter/A4 ~1700x2200)
        // không chạm trần này.
        let maxSide: CGFloat = 4096
        let longest = max(size.width, size.height)
        if longest > maxSide {
            let shrink = maxSide / longest
            size = CGSize(width: size.width * shrink, height: size.height * shrink)
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let cg = context.cgContext
            cg.translateBy(x: 0, y: size.height)
            cg.scaleBy(x: size.width / bounds.width, y: -size.height / bounds.height)
            page.draw(with: .cropBox, to: cg)
        }
    }
}


// MARK: - Gói 3: trình chọn file nạp (UIKit thuần, chế độ SAO CHÉP)
//
// L-2026-11-20-43 + Q10a (kế hoạch đã duyệt — Gói 3 trong
// study/APP-ASSESSMENT-AND-PLAN.md): đường nạp file cũ dùng
// .fileImporter của SwiftUI, tức mở file TẠI CHỖ — hệ thống
// phải cấp quyền tại chỗ cho danh tính app, và trên bản cài
// ký lại KravaSigner bước cấp quyền đó chết ở nút Open y hệt
// bộ chọn thư mục của gương (L-2026-11-19-36, hồ sơ
// PICKER-RERESEARCH.md): picker hiện, duyệt được, bấm Open
// không tác dụng, callback không bao giờ chạy. Anh xác nhận
// đúng triệu chứng này trên bản #159 (2026-11-20).
// Trình ở đây theo đúng mẫu MirrorFolderPickerPresenter
// (trình từ view controller trên cùng, coordinator giữ tĩnh
// tới callback, khoá tái nhập, nhịp tự nhả 0,6 s) nhưng ở chế
// độ SAO CHÉP (asCopy: true): hệ thống chép file anh chọn vào
// vùng của app rồi mới trao URL — một hình cấp quyền khác hẳn
// grant tại chỗ, và là hình chưa từng đo trên máy anh (mục
// "chưa kiểm được" trong IMPORT-DIFF.md).
// Kỷ luật log của gói: MỌI kết cục của một lượt chọn đều ghi
// DiagLog [app] tiền tố "NẠP FILE:" — đã trình / đã chọn (kèm
// tên file) / bị huỷ / lỗi / không có view controller để
// trình. Một lượt chết không được phép câm lặng nữa (bài học
// L-36: picker chết mà app không để lại một dòng log nào).

enum ReceiptFilePickerPresenter {
    /// Coordinator của lượt chọn đang mở. Delegate của picker
    /// là weak nên phải có tham chiếu mạnh giữ nó sống tới khi
    /// picker báo xong; nhả ngay trong callback.
    private static var activeCoordinator: Coordinator?

    /// allowsMultiple: điểm gọi ở tab CHỤP giữ mặc định true
    /// (nạp nhiều file một lượt); màn Chi Tiết gắn lại ảnh gốc
    /// (ReceiptViews, L-2026-11-20-45) truyền false — chỉ lấy
    /// đúng một file cho một tờ. Tham số đặt CUỐI với mặc định
    /// để điểm gọi cũ không đổi một chữ.
    static func present(onPick: @escaping ([URL]) -> Void,
                        onCancel: @escaping () -> Void,
                        onFailure: @escaping (Error) -> Void,
                        allowsMultiple: Bool = true) {
        DiagLog.log(.app, "NẠP FILE: present() được gọi")
        // Lùi một nhịp runloop như mẫu gương: nút bấm nằm
        // trong ngữ cảnh SwiftUI — trình ngay trong cùng nhịp
        // sự kiện là cơ chế nuốt thao tác đã dính ở L-36.
        DispatchQueue.main.async {
            // Khoá tái nhập (cùng kỷ luật bản gương): hai lần
            // bấm rất nhanh không được sinh hai picker — lần mở
            // sau ghi đè biến tĩnh sẽ làm coordinator của
            // picker trước mất tham chiếu mạnh, delegate chết
            // theo. Mọi lối ra của một lượt (chọn / huỷ / lỗi /
            // present bị nuốt) đều nhả biến tĩnh nên chốt này
            // không thể gây kẹt.
            guard activeCoordinator == nil else {
                DiagLog.log(.app,
                            "NẠP FILE: present bị chặn bởi khoá tái nhập (đang có picker mở)")
                return
            }
            guard let presenter = topPresenter() else {
                // Không có cửa sổ nào để trình: picker không hề
                // hiện và sẽ không có phản hồi nào tới — đây là
                // LỖI của lượt (không phải anh huỷ): báo lên UI
                // qua onFailure đúng câu chữ của nhánh .failure
                // ở .fileImporter cũ.
                let error = NSError(
                    domain: "GLKeeper.FileImport", code: 1,
                    userInfo: [NSLocalizedDescriptionKey:
                        "Không tìm được cửa sổ để mở bộ chọn file"])
                DiagLog.log(.app,
                            "NẠP FILE: lỗi — không tìm được view controller để trình: \(error.localizedDescription)")
                onFailure(error)
                return
            }
            DiagLog.log(.app,
                        "NẠP FILE: topPresenter có: \(type(of: presenter))")
            let coordinator = Coordinator(onPick: onPick,
                                          onCancel: onCancel)
            activeCoordinator = coordinator
            let picker = UIDocumentPickerViewController(
                forOpeningContentTypes: [.pdf, .jpeg, .png, .heic],
                asCopy: true)
            picker.delegate = coordinator
            picker.allowsMultipleSelection = allowsMultiple
            presenter.present(picker, animated: true)
            DiagLog.log(.app, "NẠP FILE: đã gọi present(picker)")
            // Lối thoát phụ (cùng mẫu gương): nếu UIKit NUỐT
            // lệnh present (VC đích đang giữa một chuyển cảnh
            // đóng/mở modal khác) thì cả hai callback delegate
            // không bao giờ chạy — biến tĩnh kẹt sẽ chặn mọi
            // lần mở sau. Sau nhịp trình diễn chuẩn, tự kiểm:
            // picker không có presentingViewController mà biến
            // tĩnh vẫn là coordinator của lượt này thì tự nhả
            // chốt và đi đường huỷ.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                if picker.presentingViewController == nil,
                   ReceiptFilePickerPresenter.activeCoordinator === coordinator {
                    ReceiptFilePickerPresenter.activeCoordinator = nil
                    DiagLog.log(.app,
                                "NẠP FILE: nhịp kiểm 0,6s — picker KHÔNG có presentingViewController, present bị nuốt, tự nhả chốt (đi đường huỷ)")
                    onCancel()
                } else if picker.presentingViewController != nil {
                    DiagLog.log(.app,
                                "NẠP FILE: nhịp kiểm 0,6s — picker đang hiện (có presentingViewController)")
                } else {
                    DiagLog.log(.app,
                                "NẠP FILE: nhịp kiểm 0,6s — picker đã kết thúc qua delegate trước nhịp kiểm")
                }
            }
        }
    }

    /// View controller trên cùng của cửa sổ khoá thuộc scene
    /// đang foreground — cùng thuật toán với
    /// MirrorFolderPickerPresenter.topPresenter.
    private static func topPresenter() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive }
            ?? scenes.first
        guard let root = scene?.windows
            .first(where: { $0.isKeyWindow })?.rootViewController
            ?? scene?.windows.first?.rootViewController else {
            return nil
        }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var onPick: ([URL]) -> Void
        var onCancel: () -> Void

        init(onPick: @escaping ([URL]) -> Void,
             onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            defer { ReceiptFilePickerPresenter.activeCoordinator = nil }
            guard !urls.isEmpty else {
                // Picker trả về rỗng: không file nào được
                // chọn — đi đường huỷ như mẫu gương.
                DiagLog.log(.app,
                            "NẠP FILE: didPick NHƯNG urls rỗng — đi đường huỷ")
                onCancel()
                return
            }
            // Chế độ asCopy: các URL ở đây trỏ vào bản sao hệ
            // thống đã chép vào vùng của app. Đường sau nạp
            // (stageExternalURLs) sao tiếp vào PendingImports
            // như cũ — thêm một lần sao là vô hại, đổi lại
            // hàng chờ bền không phụ thuộc tuổi thọ của bản
            // sao tạm này.
            let names = urls.map { $0.lastPathComponent }
                .joined(separator: ", ")
            DiagLog.log(.app,
                        "NẠP FILE: đã chọn \(urls.count) file: \(names)")
            onPick(urls)
        }

        func documentPickerWasCancelled(
            _ controller: UIDocumentPickerViewController
        ) {
            defer { ReceiptFilePickerPresenter.activeCoordinator = nil }
            DiagLog.log(.app,
                        "NẠP FILE: bị huỷ (documentPickerWasCancelled)")
            onCancel()
        }
    }
}


// MARK: - P-DRAFT: ánh xạ ScanDraft <-> PendingDraftSnapshot
//
// Ánh xạ sống ở file này vì ScanDraft khai ở đây; các DTO + kho
// lưu (PendingDraft.swift) không phụ thuộc tầng UI. Trường `id`
// của ScanDraft là định danh phiên hiển thị (Identifiable) —
// KHÔNG chụp: bản nháp khôi phục nhận id mới, đúng nghĩa của nó.

extension PendingDraftSnapshot {
    /// Chụp từ bản nháp đang sống trong bộ nhớ (gọi ngay khi
    /// draft ra đời ở runRead).
    init(draft: ScanDraft) {
        self.init(result: draft.result,
                  imageFileName: draft.imageFileName,
                  sourceTypeRaw: draft.sourceType.rawValue,
                  sourceFileName: draft.sourceFileName,
                  originalFileNames: draft.originalFileNames,
                  rawTextIsPDFTextLayer: draft.rawTextIsPDFTextLayer,
                  provenance: draft.provenance,
                  reconcileReport: draft.reconcileReport,
                  diagnosticsID: draft.diagnosticsID,
                  diagnosticsWriteFailed: draft.diagnosticsWriteFailed)
    }

    /// Dựng lại bản nháp để mở Kiểm Lại. Trả nil khi báo cáo đối
    /// chiếu chứa mã enum lạ (bản chụp của phiên bản khác) — nơi
    /// gọi xử như snapshot hỏng (xoá + log). Riêng sourceType lạ
    /// thì hạ về .unknown: đó là nhãn nguồn nạp (F3), không đáng
    /// đánh đổi cả bản nháp vì một nhãn.
    func makeDraft() -> ScanDraft? {
        var restoredReport: ReconcileReport? = nil
        if let reportDTO = reconcileReport {
            guard let report = reportDTO.toOriginal() else { return nil }
            restoredReport = report
        }
        return ScanDraft(result: result.toOriginal(),
                         imageFileName: imageFileName,
                         sourceType: SourceType(rawValue: sourceTypeRaw) ?? .unknown,
                         sourceFileName: sourceFileName,
                         originalFileNames: originalFileNames,
                         rawTextIsPDFTextLayer: rawTextIsPDFTextLayer,
                         provenance: provenance,
                         reconcileReport: restoredReport,
                         diagnosticsID: diagnosticsID,
                         diagnosticsWriteFailed: diagnosticsWriteFailed)
    }
}


// MARK: - G3: ánh xạ trạng thái chặn <-> PendingBlockSnapshot
//
// Ánh xạ sống ở file này vì ScanDraft khai ở đây, cùng tiền lệ
// của PendingDraftSnapshot ở trên; các DTO + kho lưu
// (PendingDraft.swift) không phụ thuộc tầng UI.

extension PendingBlockSnapshot {
    /// Chụp từ trạng thái chặn đang sống trong bộ nhớ (gọi
    /// ngay khi cổng phán .block ở runRead).
    init(draft: ScanDraft, quality: QualityOutcome) {
        self.init(draftSnapshot: PendingDraftSnapshot(draft: draft),
                  quality: quality)
    }

    /// Dựng lại cặp (bản nháp, kết quả cổng) để hiện lại khung
    /// chặn. Trả nil khi BẤT KỲ lớp nào chứa mã lạ (báo cáo đối
    /// chiếu của bản nháp hoặc mã quyết định của cổng) — nơi
    /// gọi xử như bản chụp hỏng (xoá + log), không dựng nửa vời
    /// một quyết định chặn sai nghĩa.
    func makeBlocked() -> (draft: ScanDraft, quality: QualityOutcome)? {
        guard let restoredDraft = draft.makeDraft(),
              let restoredQuality = qualityOutcome() else { return nil }
        return (restoredDraft, restoredQuality)
    }
}


// MARK: - Bọc VNDocumentCameraViewController cho SwiftUI

struct DocumentCameraView: UIViewControllerRepresentable {
    var onScan: (VNDocumentCameraScan) -> Void
    var onCancel: () -> Void
    var onError: (Error) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let parent: DocumentCameraView
        init(parent: DocumentCameraView) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            parent.onScan(scan)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            parent.onError(error)
        }
    }
}
