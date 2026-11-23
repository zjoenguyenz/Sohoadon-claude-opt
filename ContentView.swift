import SwiftUI
import SwiftData
import LocalAuthentication

/// Gốc của app: cổng khoá Face ID (nếu bật) + khung 5 tab.
/// Khoá Face ID PHẢI fail-open: máy không có sinh trắc/mật mã, hoặc lỗi lạ
/// -> mở app bình thường kèm thông báo, KHÔNG bao giờ khoá cứng anh ở ngoài
/// và KHÔNG crash (bài học Test 0: đụng vào framework lạ lúc khởi động là chết app).
///
/// G3 (luật bền hoá trạng thái): màn khoá là LỚP PHỦ lên cây giao
/// diện, KHÔNG còn là nút thay cây. Bản cũ dùng if/else THÁO toàn
/// bộ TabShellView khỏi cây mỗi lần app vào nền -> mọi @State của
/// cả 5 tab chết tại chỗ, tab về 0 — đúng triệu chứng "nó quay về
/// home đầu tiên" của anh, chỉ cần chuyển app là mất, không cần
/// giết app. Nay: cây chính dựng MỘT lần (sau lần mở khoá đầu
/// tiên) rồi SỐNG MÃI; các chu kỳ khoá sau chỉ phủ màn khoá lên
/// trên, mở khoá thì gỡ phủ — trạng thái các tab nguyên vẹn.
/// Trước lần mở khoá đầu tiên cây CHƯA dựng: không nội dung nào
/// (kể cả sheet khôi phục của ScanView) được hiện trước cổng
/// khoá, giữ nguyên hợp đồng bảo mật của bản cũ.
struct ContentView: View {
    @AppStorage("faceIDLockEnabled") private var lockEnabled = true
    @State private var unlocked = false
    /// Đã dựng cây giao diện lần đầu hay chưa (sau mở khoá đầu
    /// tiên, hoặc ngay từ đầu khi khoá tắt). Một khi đã true thì
    /// KHÔNG bao giờ quay lại false trong phiên — đó là điều
    /// kiện để khoá thành lớp phủ thay vì nút reset trạng thái.
    @State private var treeMounted = false
    @State private var lockNote: String? = nil
    @Environment(\.scenePhase) private var scenePhase
    /// WP3 bước 2: file anh mở bằng "Mở bằng Sổ Hóa Đơn" / Share Sheet
    /// (khai báo CFBundleDocumentTypes ở project.yml). URL chỉ được GIỮ
    /// ở đây — việc đọc file diễn ra đồng bộ trong ScanView như đường
    /// Files; app đang khoá Face ID thì URL chờ ở đây, mở khoá xong mới
    /// truyền xuống (không đọc file khi chưa qua cổng khoá).
    @State private var pendingImportURLs: [URL] = []
    /// L-2026-11-20-44 (đính chính): bộ đếm lần mở khoá THÀNH CÔNG
    /// trong phiên — tín hiệu TƯỜNG MINH cho đường nạp file. Khi
    /// mở khoá, giá trị của binding gatedImportURLs lật [] -> [url]
    /// chỉ qua hàm get tự-tính; .onChange ở TabShellView/ScanView
    /// không cháy tin cậy cho thay đổi kiểu đó, và cây giao diện
    /// nay giữ nguyên khi khoá (G3) nên không onAppear nào cứu —
    /// URL chờ thành vô hình. Mỗi lần unlocked lật lên true thì
    /// tick tăng 1 (xem .onChange(of: unlocked) ở body), cây dưới
    /// nghe tick để nhảy tab + hút file chờ đã qua cổng.
    @State private var unlockTick = 0

    /// Binding truyền xuống cây giao diện, CỔNG theo trạng thái
    /// khoá: đang khoá thì cây chỉ thấy danh sách rỗng (URL chờ
    /// nguyên ở ContentView, không file nào bị đọc trước cổng
    /// khoá — giữ hợp đồng WP3 bước 2); mở khoá thì danh sách
    /// thật hiện ra và onChange ở TabShellView/ScanView tự hút
    /// vào hàng chờ như cũ. Ghi (ScanView xoá sau khi hút) luôn
    /// chuyển thẳng vào kho thật.
    private var gatedImportURLs: Binding<[URL]> {
        Binding(
            get: { (lockEnabled && !unlocked) ? [] : pendingImportURLs },
            set: { pendingImportURLs = $0 })
    }

    var body: some View {
        ZStack {
            if !lockEnabled || treeMounted {
                TabShellView(lockNote: lockNote, pendingImportURLs: gatedImportURLs, unlockTick: unlockTick)
            }
            if lockEnabled && !unlocked {
                // Lớp phủ khoá: nền ĐẶC toàn màn (không nhìn
                // xuyên được nội dung bên dưới) + nằm trên cùng
                // của ZStack nên chạm không lọt xuống cây chính.
                lockScreen
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
                    .ignoresSafeArea()
                    .zIndex(1)
            }
        }
        .onOpenURL { url in
            // L-2026-11-20-44: để lại dấu vết cho đường chia sẻ/
            // open-in — lượt nhận URL nào cũng có một dòng log,
            // không còn ca "app mở mà không biết file có tới".
            DiagLog.log(.app, "NẠP FILE: nhận URL mở-từ-ngoài: \(url.lastPathComponent)")
            pendingImportURLs.append(url)
        }
        .onAppear {
            // LOGKIT (L-2026-11-19-39): một dòng mở app kèm
            // dấu bản bộ đọc + phiên bản app — điểm neo thời
            // gian cho mọi dòng log sau trong phiên.
            let info = Bundle.main.infoDictionary
            let appVersion = info?["CFBundleShortVersionString"] as? String ?? "?"
            let appBuild = info?["CFBundleVersion"] as? String ?? "?"
            DiagLog.log(.app, "mở app — bộ đọc \(ReadCoreVersion.parserVersion) · app \(appVersion) (\(appBuild))")
            // Khoá đang tắt thì cây hiện ngay từ đầu — ghi nhận
            // đã dựng để lần bật khoá sau đó (giữa phiên) cũng
            // chỉ phủ lên, không tháo cây.
            if !lockEnabled { treeMounted = true }
            authenticateIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background && lockEnabled {
                unlocked = false
            }
            if newPhase == .active && lockEnabled && !unlocked {
                authenticateIfNeeded()
            }
        }
        .onChange(of: lockEnabled) { _, newValue in
            // Anh bật khoá giữa phiên (ở Thẻ & Cài Đặt): đòi xác
            // thực ngay cho khớp trạng thái, thay vì chờ chu kỳ
            // nền lần tới.
            if newValue { authenticateIfNeeded() }
        }
        .onChange(of: unlocked) { _, newValue in
            // L-2026-11-20-44 (đính chính): mỗi lần mở khoá thành
            // công thì tăng tick — TabShellView/ScanView nghe tick
            // này để hút file mở-từ-ngoài đang chờ qua cổng khoá,
            // thay vì trông vào .onChange của binding tự-tính
            // gatedImportURLs (không cháy tin cậy, xem unlockTick).
            if newValue { unlockTick += 1 }
        }
    }

    private var lockScreen: some View {
        VStack(spacing: 20) {
            // UI-2026-11-13: dấu hiệu thương hiệu ở màn khoá —
            // vòng tròn xanh ngọc + biểu tượng quét hoá đơn.
            ZStack {
                Circle()
                    .fill(DS.brand.opacity(0.15))
                    .frame(width: 92, height: 92)
                Image(systemName: "doc.viewfinder")
                    .font(.system(size: 40))
                    .foregroundStyle(DS.brand)
                Image(systemName: "lock.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(Circle().fill(DS.brand))
                    .offset(x: 32, y: 32)
            }
            Text("GL-Keeper đang khoá")
                .font(.title3.bold())
            if let lockNote {
                Text(lockNote)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            Button("Mở khoá bằng Face ID / mật mã") { authenticateIfNeeded() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding()
    }

    private func authenticateIfNeeded() {
        guard lockEnabled, !unlocked else { return }
        let context = LAContext()
        var error: NSError?
        // .deviceOwnerAuthentication = Face ID, hỏng thì rơi về mật mã máy.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // Không có sinh trắc lẫn mật mã -> fail-open, không khoá người dùng ở ngoài.
            lockNote = "Máy chưa đặt Face ID/mật mã nên app mở không khoá. Anh có thể tắt khoá hẳn trong Thẻ & Cài Đặt."
            unlocked = true
            treeMounted = true
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication,
                               localizedReason: "Mở khoá GL-Keeper") { success, _ in
            DispatchQueue.main.async {
                if success {
                    unlocked = true
                    // G3: từ khoảnh khắc này cây giao diện được
                    // dựng và SỐNG MÃI trong phiên — các lần
                    // khoá sau chỉ là lớp phủ (xem body).
                    treeMounted = true
                    lockNote = nil
                } else {
                    lockNote = "Chưa mở được — anh bấm nút dưới để thử lại (hoặc dùng mật mã máy)."
                }
            }
        }
    }
}

// MARK: - Khung 5 tab (BLUEPRINT mục 5)

struct TabShellView: View {
    var lockNote: String? = nil
    /// WP3 bước 2: hàng chờ file mở-từ-ngoài, truyền thẳng xuống ScanView.
    @Binding var pendingImportURLs: [URL]
    /// L-2026-11-20-44 (đính chính): bộ đếm lần mở khoá thành công
    /// từ ContentView — tín hiệu tường minh để nhảy tab Chụp khi
    /// có file chờ vừa qua cổng khoá (xem .onChange(of: unlockTick)).
    var unlockTick: Int
    @Environment(\.modelContext) private var modelContext
    /// G3: vị trí tab theo @SceneStorage — sống qua việc hệ
    /// thống thu hồi cảnh và qua khởi động lại, thay vì @State
    /// chết theo chu kỳ khoá như bản cũ (một nửa triệu chứng
    /// "về home đầu tiên"; nửa còn lại là cổng khoá tháo cây,
    /// đã sửa ở ContentView).
    @SceneStorage("glkeeper.selectedTab") private var selectedTab = 0
    @State private var seeded = false
    /// A12(i) (vòng 2): onboarding 3 bước — chỉ sổ trống, một lần.
    @State private var showOnboarding = false
    /// P2-1: theo dõi foreground để kích lượt gương bắt kịp
    /// khi anh quay lại app (thư mục/mạng khả dụng trở lại).
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(selectedTab: $selectedTab)
                .tabItem { Label("Trang Chủ", systemImage: "house.fill") }
                .tag(0)

            ReceiptListView()
                .tabItem { Label("Hoá Đơn", systemImage: "doc.text.fill") }
                .tag(1)

            ScanView(externalImportURLs: $pendingImportURLs, unlockTick: unlockTick)
                .tabItem { Label("CHỤP", systemImage: "camera.fill") }
                .tag(2)

            ReportsView()
                .tabItem { Label("Báo Cáo Thuế", systemImage: "chart.pie.fill") }
                .tag(3)

            CardsView()
                .tabItem { Label("Thẻ & Cài Đặt", systemImage: "creditcard.fill") }
                .tag(4)
        }
        .tint(DS.brand)
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView(onScanNow: {
                showOnboarding = false
                selectedTab = 2
            }, onFinish: {
                showOnboarding = false
            })
        }
        .task {
            seedStarterCardIfNeeded()
            // A12(i): sổ TRỐNG + chưa onboarding + không có file chờ
            // nạp -> mở onboarding. Đọc sổ lỗi thì không mở (không
            // đoán là sổ trống).
            if !OnboardingState.didOnboard, pendingImportURLs.isEmpty,
               let count = try? modelContext.fetchCount(FetchDescriptor<Receipt>()),
               count == 0 {
                showOnboarding = true
            }
            // L-2026-11-20-42: kiểm kê ảnh gốc chạy TRƯỚC
            // các trigger đồng bộ lúc mở app — kho chính mất
            // file mà kho an toàn còn thì khôi phục/bổ sung
            // xong mới tới lượt gương/Drive, để đồng bộ luôn
            // nhìn thấy bộ bằng chứng đã lành. Completion của
            // kiểm kê bắn hai trigger như cũ (kiểm kê lỗi thì
            // vẫn bắn — lớp bảo vệ không chặn đồng bộ).
            ImageIntegrity.runLaunchAudit(using: modelContext) {
                // P2-1: lượt gương bắt kịp mỗi lần mở app
                // (lớp phụ — chưa bật/chưa chọn thư mục thì
                // thoát ngay, không ghi lỗi).
                MirrorSync.requestSync(using: modelContext)
                DriveSync.requestSync(using: modelContext)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // P2-1: app quay lại foreground -> bắt kịp gương
            // (các thay đổi lúc app nền hoặc thư mục iCloud
            // vừa khả dụng trở lại đều được quét bù ở đây).
            // L-2026-11-20-42 (rà soát R1 ghế A-3 + C-2):
            // đường này cũng qua CÙNG cổng kiểm kê như .task
            // ở trên — file mất trong lúc app ở nền được khôi
            // phục/bổ sung TRƯỚC, completion mới bắn hai
            // trigger đồng bộ; các lượt kiểm tự xếp hàng trên
            // auditQueue serial nên không chạy chồng nhau.
            if newPhase == .active {
                ImageIntegrity.runLaunchAudit(using: modelContext) {
                    MirrorSync.requestSync(using: modelContext)
                    DriveSync.requestSync(using: modelContext)
                }
            }
        }
        // WP3 bước 2: có file mở-từ-ngoài đang chờ -> nhảy thẳng sang
        // tab CHỤP để ScanView hút vào hàng chờ và mở màn Kiểm Lại.
        .onChange(of: pendingImportURLs) { _, urls in
            if !urls.isEmpty {
                DiagLog.log(.app, "NẠP FILE: nhảy tab Chụp vì có file chờ (onChange)")
                selectedTab = 2
            }
        }
        // L-2026-11-20-44 (đính chính): tín hiệu mở khoá TƯỜNG MINH —
        // file chia sẻ vào lúc app đang khoá thì binding cổng chỉ
        // thấy []; lúc mở khoá xong, giá trị lật qua hàm get tự-tính
        // nên .onChange(of: pendingImportURLs) ở trên không cháy
        // tin cậy. Tick tăng là sự kiện có thật: có file chờ thì
        // nhảy tab Chụp ngay (ScanView nghe cùng tick để hút file).
        .onChange(of: unlockTick) { _, _ in
            if !pendingImportURLs.isEmpty {
                selectedTab = 2
                DiagLog.log(.app, "NẠP FILE: mở khoá xong — nhảy tab Chụp vì có file chờ")
            }
        }
        // L-2026-11-20-44: ca MỞ LẠNH từ share sheet — app chưa chạy,
        // URL tới qua .onOpenURL TRƯỚC khi TabShellView hiện lần đầu.
        // .onChange không cháy cho giá trị đã có sẵn lúc view hiện,
        // nên cú nhảy của WP3 không bao giờ tới: ScanView không được
        // dựng, file nằm chờ vô hạn, app mở lên như không có gì.
        // .onAppear lấp đúng lỗ này: view vừa hiện mà danh sách chờ
        // (đã qua cổng khoá ở binding gatedImportURLs) không rỗng
        // thì nhảy ngay sang tab Chụp cho ScanView hút file.
        .onAppear {
            if !pendingImportURLs.isEmpty {
                DiagLog.log(.app, "NẠP FILE: nhảy tab Chụp vì có file chờ (onAppear)")
                selectedTab = 2
            }
        }
    }

    /// Nạp sẵn thẻ đã chốt với anh: Mastercard Debit •• 2586 = Business.
    /// Chỉ nạp khi danh sách thẻ đang TRỐNG và chưa từng nạp (cờ UserDefaults),
    /// để anh xoá/ngưng về sau không bị app tự nạp lại.
    private func seedStarterCardIfNeeded() {
        guard !seeded else { return }
        seeded = true
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "didSeedStarterCard2586") else { return }
        let descriptor = FetchDescriptor<CardTail>()
        // N2-FIX: bản cũ `(try? fetch) ?? []` — đọc sổ lỗi bị
        // hiểu là "chưa có thẻ" -> nạp TRÙNG thẻ 2586; và cờ
        // UserDefaults được đặt vô điều kiện nên lưu hỏng một
        // lần là thẻ mồi không bao giờ được nạp lại. Nay: đọc
        // lỗi thì bỏ lượt này (lần mở app sau thử lại, không
        // đặt cờ); chỉ đặt cờ sau khi đã chắc chắn trạng thái.
        let existing: [CardTail]
        do {
            existing = try modelContext.fetch(descriptor)
        } catch {
            seeded = false
            return
        }
        if existing.isEmpty {
            let card = CardTail()
            card.last4 = "2586"
            card.brand = "Mastercard Debit"
            card.kind = .business
            modelContext.insert(card)
            if !saveContextOrFalse(modelContext) {
                modelContext.delete(card)
                seeded = false
                return
            }
        }
        defaults.set(true, forKey: "didSeedStarterCard2586")
    }
}
