import SwiftUI
import SwiftData

/// Tab "Thẻ & Cài Đặt":
/// - Đăng ký đuôi thẻ debit: thêm / sửa / NGƯNG (không xoá đuôi đã có hoá đơn).
///   Đổi loại 1 thẻ -> app hỏi rõ "chỉ từ nay, hay xếp lại hoá đơn cũ của thẻ này?".
/// - Cài Đặt: khoá Face ID, ghi chú lưu trữ.
struct CardsView: View {
    @Query(sort: \CardTail.createdAt) private var cardTails: [CardTail]
    // P2-0/C-8 + B-7: toàn sổ — đếm phạm vi xếp lại theo thẻ
    // và tính file ảnh mồ côi.
    @Query private var allReceipts: [Receipt]
    @Environment(\.modelContext) private var modelContext
    @AppStorage("faceIDLockEnabled") private var lockEnabled = true

    @State private var formTarget: CardFormTarget? = nil
    @State private var pendingKindChange: PendingKindChange? = nil
    /// N2-FIX: lưu thẻ thất bại — hiện alert, không nuốt lặng.
    @State private var saveFailed = false
    /// P2-1: gương thư mục Files — trạng thái thật đọc từ
    /// MirrorSettings (UserDefaults) mỗi lần vẽ; mirrorStateTick
    /// là móc làm mới khi lượt gương nền báo đổi trạng thái.
    @State private var mirrorStateTick = 0
    /// LOGKIT (L-2026-11-19-39): móc làm mới riêng cho mục
    /// Log chẩn đoán (kích thước log đổi sau khi xoá).
    @State private var logStateTick = 0
    /// P2-2: móc làm mới riêng cho mục Google Drive (trạng
    /// thái đổi khi đăng nhập/đăng xuất/lượt đồng bộ báo về).
    @State private var driveStateTick = 0
    /// L-2026-11-20-42: móc làm mới riêng cho dòng kiểm kê
    /// ảnh gốc (trạng thái đổi sau mỗi lượt kiểm kê mở app).
    @State private var integrityStateTick = 0
    /// PHA 2 (L-2026-11-21-47): cài đặt thuế — trạng thái thật
    /// đọc từ TaxSettings (UserDefaults) mỗi lần màn hiện.
    @State private var taxLandingEnabled = TaxSettings.landingEnabled
    @State private var taxDefaultAreaID = TaxSettings.defaultAreaID
    @State private var taxPortions: [TaxAreaPortion] =
        TaxSettings.effectiveTable.portions

    private var activeCards: [CardTail] { cardTails.filter { !$0.archived } }
    private var archivedCards: [CardTail] { cardTails.filter { $0.archived } }

    /// P2-0/B-7: file trong thư mục bằng chứng KHÔNG thuộc
    /// hoá đơn nào và không thuộc bản nháp đang chờ (nháp
    /// thường + nháp bị cổng chất lượng chặn) — chỉ LIỆT KÊ.
    private var orphanFiles: (count: Int, bytes: Int) {
        let directory = ImageStore.directory
        let names = (try? FileManager.default.contentsOfDirectory(
            atPath: directory.path)) ?? []
        var referenced = Set<String>()
        for receipt in allReceipts {
            for name in receipt.allOriginalImageFileNames {
                referenced.insert(name)
                referenced.insert(DiagnosticsStore.fileName(
                    forImageFileName: name))
            }
        }
        if let snapshot = PendingDraftStore.load() {
            referenced.insert(snapshot.imageFileName)
            referenced.formUnion(snapshot.originalFileNames)
            referenced.insert(DiagnosticsStore.fileName(
                forImageFileName: snapshot.imageFileName))
        }
        if let block = PendingBlockStore.load() {
            referenced.insert(block.draft.imageFileName)
            referenced.formUnion(block.draft.originalFileNames)
            referenced.insert(DiagnosticsStore.fileName(
                forImageFileName: block.draft.imageFileName))
        }
        var count = 0
        var bytes = 0
        for name in names where !referenced.contains(name) {
            count += 1
            if let attributes = try? FileManager.default
                .attributesOfItem(atPath: directory
                    .appendingPathComponent(name).path),
               let size = attributes[.size] as? Int {
                bytes += size
            }
        }
        return (count, bytes)
    }

    /// P2-0/C-8: tờ này có phải "bản chụp phân loại theo
    /// thẻ" không — lý do phân loại do CHÍNH cơ chế thẻ ghi
    /// (gợi ý lúc lưu hoặc lần xếp lại trước), không phải
    /// quyết định tay của anh.
    private func isCardClassifiedSnapshot(_ receipt: Receipt,
                                          last4: String) -> Bool {
        receipt.classificationReason.hasPrefix("Thẻ •• \(last4)")
            || receipt.classificationReason
                .hasPrefix("Xếp lại theo thẻ •• \(last4)")
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(activeCards) { card in
                        cardRow(card)
                    }
                } header: {
                    Text("Thẻ đang dùng")
                } footer: {
                    Text("App chỉ nhớ 4 số cuối + hãng thẻ — không bao giờ cần số thẻ đầy đủ. Đuôi thẻ là GỢI Ý phân loại, anh luôn đổi được từng hoá đơn.")
                }

                if !archivedCards.isEmpty {
                    Section("Thẻ đã ngưng dùng") {
                        ForEach(archivedCards) { card in
                            cardRow(card)
                        }
                    }
                }

                Section {
                    Button {
                        formTarget = .new
                    } label: {
                        Label("Thêm đuôi thẻ", systemImage: "plus.circle.fill")
                    }
                }

                Section("Cài Đặt") {
                    Toggle(isOn: $lockEnabled) {
                        Label("Khoá bằng Face ID", systemImage: "faceid")
                    }
                    Text("Bật khoá: mỗi lần mở app phải xác nhận Face ID hoặc mật mã máy. Máy không có Face ID/mật mã thì app mở bình thường, không khoá cứng.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    LabeledContent("Nơi lưu ảnh gốc", value: "Trong app (Files → Sổ Hóa Đơn)")
                    LabeledContent("Đọc hoá đơn", value: "Ngay trên máy, không gửi ra ngoài")
                    // P2-0/B-7: LIỆT KÊ file ảnh chưa thuộc
                    // hoá đơn nào (mồ côi) — chỉ để anh biết,
                    // app KHÔNG tự xoá (file của bản nháp
                    // đang chờ cũng có thể nằm trong số này).
                    LabeledContent("File ảnh chưa gắn hoá đơn",
                                   value: "\(orphanFiles.count) file · \(ByteCountFormatter.string(fromByteCount: Int64(orphanFiles.bytes), countStyle: .file))")
                    Text("Chỉ liệt kê để anh biết — app không tự xoá. Sau gói này, huỷ ở màn Kiểm Lại và lượt đọc rỗng đã tự xoá file của chúng; số còn lại là di sản các bản trước.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // P2-2 (§2.3): Google Drive — đường sao lưu
                // NGOÀI MÁY chính từ Gói 6 (Q1 anh quyết
                // 2026-11-20, sau khi bộ chọn thư mục gương
                // chết trên bản ký lại). App chỉ đụng thư
                // mục GL-Keeper do chính nó tạo (scope
                // drive.file); token nằm ở Keychain của máy.
                Section {
                    LabeledContent("Trạng thái", value: driveStatusText)
                    // L-2026-11-20-42: dòng đếm ảnh gốc lấy
                    // từ KIỂM KÊ ĐỘC LẬP mỗi lần mở app —
                    // KHÔNG mượn bộ đếm của lượt đồng bộ
                    // (sau vá L-41 đường verify của Drive
                    // không đếm lại ảnh mất, dòng đồng bộ
                    // không còn là nguồn sự thật cho việc
                    // đủ/thiếu ảnh gốc).
                    LabeledContent("Ảnh gốc", value: integrityStatusText)
                    if IntegritySettings.lastCheckAt != nil {
                        LabeledContent("Kiểm kê gần nhất",
                                       value: integrityLastCheckText)
                    }
                    if DriveAuth.isSignedIn {
                        LabeledContent("Lần đồng bộ gần nhất",
                                       value: driveLastRunText)
                        if let summary = DriveSettings.lastSummary {
                            Text(summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let error = DriveSettings.lastError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        Button {
                            DriveSync.requestSync(using: modelContext)
                        } label: {
                            Label("Đồng bộ ngay", systemImage: "arrow.triangle.2.circlepath")
                        }
                        Button(role: .destructive) {
                            DriveAuth.signOut()
                        } label: {
                            Label("Đăng xuất Google", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } else {
                        if let error = DriveSettings.lastError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        Button {
                            DriveAuth.signIn { _ in driveStateTick += 1 }
                        } label: {
                            Label("Đăng nhập Google", systemImage: "person.crop.circle.badge.checkmark")
                        }
                    }
                } header: {
                    Text("Google Drive (bản sao ngoài máy)")
                } footer: {
                    Text("Mỗi hoá đơn (ảnh gốc + dữ kiện) được app tự đồng bộ vào thư mục GL-Keeper trong Google Drive của anh — đồng bộ khi mở app và ngay sau mỗi thay đổi. Đăng nhập một lần; app chỉ thấy file do chính nó tạo, không thấy phần Drive còn lại. Xoá hoá đơn trên máy thì bản Drive được CHUYỂN vào thư mục _deleted trên Drive, không biến mất.")
                }

                // A1 (vòng 2): đường kéo về từ Drive (chỉ đọc Drive).
                DriveRestoreSection()

                // P2-1 (§2.2): gương thư mục Files — lớp sao
                // lưu PHỤ. Kho trên máy vẫn là gốc; gương lỗi
                // chỉ hiện ở mục này, không chặn việc lưu.
                Section {
                    Toggle(isOn: mirrorToggleBinding) {
                        Label("Gương thư mục Files", systemImage: "folder.badge.gearshape")
                    }
                    LabeledContent("Thư mục gương",
                                   value: MirrorSettings.folderDisplayName ?? "Chưa chọn")
                    LabeledContent("Trạng thái", value: mirrorStatusText)
                    // Gói 1 (điểm yếu 2.6): dấu vết của lần mở
                    // bộ chọn thư mục gần nhất — chỉ hiện khi
                    // đã từng mở ít nhất một lần.
                    if MirrorSettings.lastPickerOutcome != nil {
                        LabeledContent("Lần mở bộ chọn gần nhất",
                                       value: mirrorLastPickerText)
                    }
                    LabeledContent("Lần gương gần nhất", value: mirrorLastRunText)
                    if let summary = MirrorSettings.lastSummary {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let error = MirrorSettings.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Button {
                        presentMirrorFolderPicker()
                    } label: {
                        Label(MirrorSettings.isConnected ? "Đổi thư mục gương…" : "Chọn thư mục gương…",
                              systemImage: "folder.badge.plus")
                    }
                    if MirrorSettings.isEnabled && MirrorSettings.isConnected {
                        Button {
                            MirrorSync.requestSync(using: modelContext)
                            DriveSync.requestSync(using: modelContext)
                        } label: {
                            Label("Gương ngay", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                } header: {
                    Text("Gương Files (bản sao phụ)")
                } footer: {
                    Text("App sao mỗi hoá đơn (ảnh gốc + dữ kiện) sang thư mục anh chọn trong một thư mục con GL-Keeper — chọn thư mục nằm trong iCloud Drive là có thêm bản sao mây của Apple ở cấp file. Xoá hoá đơn trên máy thì bản gương được CHUYỂN vào thư mục _deleted trong thư mục gương, không biến mất. Gương chạy nền sau mỗi thay đổi và mỗi lần mở app.")
                }

                // PHA 2 (L-2026-11-21-47): cài đặt cơ chế hạ
                // cánh bằng thuế — khu mặc định + bảng thuế.
                Section {
                    Toggle("Tự ước tính số thiếu bằng thuế (tờ khó đọc)",
                           isOn: $taxLandingEnabled)
                        .onChange(of: taxLandingEnabled) { _, newValue in
                            TaxSettings.landingEnabled = newValue
                        }
                    Picker("Khu vực mặc định (khi mất ZIP và chưa học được tiệm)",
                           selection: $taxDefaultAreaID) {
                        ForEach(taxPortions, id: \.id) { portion in
                            Text(portion.displayName).tag(portion.id)
                        }
                    }
                    .onChange(of: taxDefaultAreaID) { _, newValue in
                        TaxSettings.defaultAreaID = newValue
                    }
                    NavigationLink {
                        TaxAreaListView()
                    } label: {
                        Label("Bảng thuế theo khu vực",
                              systemImage: "percent")
                    }
                } header: {
                    Text("Thuế Oklahoma")
                } footer: {
                    Text("Tờ quá mờ không đọc khép được: app lấy khu vực theo ZIP in trên tờ (mất ZIP thì theo tiệm đã học, rồi tới khu mặc định này), áp suất theo loại hàng và suy ra số còn thiếu — số suy ra luôn gắn nhãn ƯỚC TÍNH ở màn Kiểm Lại để anh duyệt. Bảng hạt giống từ Cục Thuế Oklahoma (OTC), hiệu lực 10/2026 – 03/2027.")
                }

                // LOGKIT (L-2026-11-19-39): bộ log chẩn đoán
                // trong app — luật cứng 2026-11-18. Log ghi
                // sự kiện bộ chọn thư mục / gương / mở app
                // ngay trên máy; xuất qua phiếu chia sẻ UIKit
                // thuần (không ShareLink) sau khi đã lọc
                // đường dẫn nhà.
                Section {
                    LabeledContent("Kích thước log hiện tại",
                                   value: logSizeText)
                    NavigationLink {
                        DiagnosticsLogView()
                    } label: {
                        Label("Xem log", systemImage: "doc.text.magnifyingglass")
                    }
                    Button {
                        DiagLogSharePresenter.presentShare()
                    } label: {
                        Label("Xuất log", systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive) {
                        DiagLog.clear()
                        logStateTick += 1
                    } label: {
                        Label("Xoá log", systemImage: "trash")
                    }
                } header: {
                    Text("Log chẩn đoán")
                } footer: {
                    Text("Log chỉ ghi sự kiện kỹ thuật trên máy (mở app, bộ chọn thư mục, lượt gương, lượt đồng bộ Drive) kèm giờ — không ghi nội dung hoá đơn, không ghi token. Khi xuất, đường dẫn thư mục nhà được thay bằng \"~\" trước khi rời máy; token Google nằm ở Keychain của máy và không bao giờ vào log.")
                }
                // A6: hạn lưu giữ 7 năm — CHỈ XEM, không xoá gì.
                Section {
                    NavigationLink {
                        RetentionHorizonView()
                    } label: {
                        Label("Tờ tới hạn lưu giữ 7 năm", systemImage: "archivebox")
                    }
                } header: {
                    Text("Lưu giữ hồ sơ")
                } footer: {
                    Text("Hạn lưu giữ = 31/12 của năm thuế + 7. Danh sách chỉ để anh xem; app không bao giờ tự xoá hoá đơn hay ảnh gốc.")
                }
            }
            .navigationTitle("Thẻ & Cài Đặt")
            .onAppear {
                mirrorStateTick += 1
                taxLandingEnabled = TaxSettings.landingEnabled
                taxDefaultAreaID = TaxSettings.defaultAreaID
                taxPortions = TaxSettings.effectiveTable.portions
            }
            .onReceive(NotificationCenter.default.publisher(
                for: MirrorSync.statusChangedNotification)) { _ in
                mirrorStateTick += 1
            }
            .onReceive(NotificationCenter.default.publisher(
                for: DriveSync.statusChangedNotification)) { _ in
                driveStateTick += 1
            }
            .onReceive(NotificationCenter.default.publisher(
                for: ImageIntegrity.statusChangedNotification)) { _ in
                integrityStateTick += 1
            }
            .sheet(item: $formTarget) { target in
                CardFormView(target: target, existingTails: cardTails) { data in
                    handleFormData(data)
                }
            }
            .alert("Lưu không thành công", isPresented: $saveFailed) {
                Button("Đã hiểu", role: .cancel) {}
            } message: {
                Text("Thay đổi thẻ CHƯA được lưu vào máy. Anh thử lại giúp — nếu vẫn không được, anh kiểm tra dung lượng trống của máy.")
            }
            .confirmationDialog(
                "Đổi loại thẻ •• \(pendingKindChange?.last4 ?? "")?",
                isPresented: Binding(
                    get: { pendingKindChange != nil },
                    set: { if !$0 { pendingKindChange = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Chỉ áp dụng từ nay") {
                    if let pending = pendingKindChange { applyCardChange(pending, reclassifyOld: false) }
                    pendingKindChange = nil
                }
                Button("Xếp lại cả hoá đơn cũ của thẻ này") {
                    if let pending = pendingKindChange { applyCardChange(pending, reclassifyOld: true) }
                    pendingKindChange = nil
                }
                Button("Huỷ", role: .cancel) { pendingKindChange = nil }
            } message: {
                // P2-0/C-8: nói rõ PHẠM VI trước khi anh
                // chọn — xếp lại chỉ chạm các tờ đang chờ
                // duyệt mà phân loại đến từ chính thẻ này;
                // tờ anh đã duyệt / đã tự quyết thì không
                // một lần xếp lại nào được ghi đè.
                if let pending = pendingKindChange {
                    Text("Xếp lại sẽ chạm \(pending.affectedCount) tờ đang chờ duyệt do thẻ này phân loại. \(pending.untouchedCount) tờ khác của thẻ này (đã duyệt hoặc anh đã tự quyết) giữ nguyên.")
                } else {
                    Text("Hoá đơn cũ của thẻ này giữ nguyên phân loại đã lưu, trừ khi anh chọn xếp lại.")
                }
            }
        }
    }

    // MARK: Dòng thẻ — vẽ như thẻ vật lý (học Apple Wallet)

    private func cardRow(_ card: CardTail) -> some View {
        HStack(spacing: 12) {
            ZStack {
                // UI-2026-11-13: thẻ mini có gradient chéo + bóng
                // đổ nhuộm màu loại thẻ (cảm giác thẻ vật lý).
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(
                        colors: [card.kind.color, card.kind.color.opacity(0.6)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 86, height: 56)
                    .shadow(color: card.kind.color.opacity(0.35), radius: 6, y: 3)
                VStack(alignment: .leading, spacing: 3) {
                    Image(systemName: card.kind.iconName)
                    Text("•• \(card.last4)")
                        .font(.caption.bold())
                        .monospacedDigit()
                }
                .foregroundStyle(.white)
                .frame(width: 86, alignment: .leading)
                .padding(.leading, 10)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(card.brand.isEmpty ? "Thẻ" : card.brand)
                    .font(.body.weight(.semibold))
                HStack(spacing: 6) {
                    StatusChip(text: card.kind.label, color: card.kind.color)
                    if card.archived {
                        Text("đã ngưng")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Menu {
                Button("Sửa thẻ") { formTarget = .edit(card) }
                if card.archived {
                    Button("Dùng lại thẻ này") { setArchived(card, false) }
                } else {
                    Button("Ngưng dùng thẻ này") { setArchived(card, true) }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
            }
        }
        .padding(.vertical, 4)
        .opacity(card.archived ? 0.6 : 1.0)
    }

    private func setArchived(_ card: CardTail, _ archived: Bool) {
        // N2-FIX: lưu hỏng thì trả trạng thái cũ + báo thật;
        // bản cũ nuốt lỗi, thẻ trông như đã ngưng mà máy chưa ghi.
        let old = card.archived
        card.archived = archived
        if !saveContextOrFalse(modelContext) {
            card.archived = old
            saveFailed = true
        }
    }

    // MARK: Xử lý form thêm/sửa

    private func handleFormData(_ data: CardFormData) {
        if let card = data.existingCard {
            if card.kind != data.kind {
                // Đổi loại: không tự áp — hỏi anh trước qua confirmationDialog.
                // P2-0/C-8: đếm sẵn phạm vi xếp lại để hộp
                // thoại nói rõ trước khi anh chọn.
                let affected = allReceipts.filter {
                    $0.cardLast4 == card.last4
                        && $0.status == .needsReview
                        && isCardClassifiedSnapshot($0, last4: card.last4)
                }.count
                let untouched = allReceipts.filter {
                    $0.cardLast4 == card.last4
                }.count - affected
                pendingKindChange = PendingKindChange(
                    card: card, brand: data.brand, kind: data.kind,
                    last4: card.last4,
                    affectedCount: affected,
                    untouchedCount: untouched)
            } else {
                // N2-FIX: như setArchived — hỏng thì hoàn tác
                // trong bộ nhớ và báo thật.
                let oldBrand = card.brand
                card.brand = data.brand
                if !saveContextOrFalse(modelContext) {
                    card.brand = oldBrand
                    saveFailed = true
                }
            }
        } else {
            let card = CardTail()
            card.last4 = data.last4
            card.brand = data.brand
            card.kind = data.kind
            modelContext.insert(card)
            if !saveContextOrFalse(modelContext) {
                // Gỡ thẻ chưa lưu khỏi context — không để nó
                // tự hạ cánh ở một lần lưu khác sau này.
                modelContext.delete(card)
                saveFailed = true
            }
        }
    }

    private func applyCardChange(_ pending: PendingKindChange, reclassifyOld: Bool) {
        // N2-FIX: bản cũ `(try? fetch) ?? []` — đọc sổ lỗi thì
        // việc xếp lại hoá đơn cũ lặng lẽ thành không làm gì,
        // trong khi đổi loại thẻ vẫn lưu: trạng thái nửa vời mà
        // không ai biết. Nay: cần xếp lại mà đọc sổ lỗi thì
        // DỪNG TOÀN BỘ thay đổi và báo thật.
        var receipts: [Receipt] = []
        if reclassifyOld {
            do {
                receipts = try modelContext.fetch(FetchDescriptor<Receipt>())
            } catch {
                saveFailed = true
                return
            }
        }
        pending.card.brand = pending.brand
        pending.card.kind = pending.kind
        if reclassifyOld {
            let last4 = pending.last4
            // Lọc trong bộ nhớ thay cho #Predicate (tránh phụ thuộc macro với optional).
            // P2-0/C-8: CHỈ xếp lại các tờ đang chờ duyệt
            // mà phân loại đến từ chính thẻ này (bản chụp
            // gợi ý) — bản cũ quét MỌI tờ cùng đuôi, ghi
            // đè cả quyết định tay và tờ đã duyệt. Sau khi
            // xếp: mục không thuộc loại mới -> mặc định của
            // loại mới, và trạng thái suy lại bằng bộ cờ
            // (cùng luật C-7).
            for receipt in receipts
            where receipt.cardLast4 == last4
                && receipt.status == .needsReview
                && isCardClassifiedSnapshot(receipt, last4: last4) {
                receipt.classification = pending.kind
                receipt.classificationReason = "Xếp lại theo thẻ •• \(last4) — anh chọn đổi cả hoá đơn cũ"
                if !Categories.list(for: pending.kind)
                    .contains(receipt.category) {
                    receipt.category = Categories.defaultValue(
                        for: pending.kind)
                }
                receipt.scheduleCLine = Categories.scheduleCLine(
                    forCategory: receipt.category)
                refreshReceiptStatusFromFlags(receipt)
            }
        }
        if saveContextOrFalse(modelContext) {
            // P2-1: xếp lại có thể đã đổi nhiều tờ — kích một
            // lượt gương bắt kịp (lớp phụ, chạy nền).
            MirrorSync.requestSync(using: modelContext)
            DriveSync.requestSync(using: modelContext)
        } else {
            modelContext.rollback()
            saveFailed = true
        }
    }

    // MARK: P2-1 — trạng thái gương (đọc MirrorSettings)

    /// Trạng thái nói thật theo cài đặt + lỗi lượt gần nhất;
    /// đọc mirrorStateTick để SwiftUI vẽ lại khi lượt gương
    /// nền phát thông báo đổi trạng thái.
    private var mirrorStatusText: String {
        _ = mirrorStateTick
        if !MirrorSettings.isConnected {
            return "Chưa nối — chưa chọn thư mục"
        }
        if MirrorSettings.lastError != nil {
            return "Đã nối · lượt gần nhất có lỗi (xem dưới)"
        }
        return MirrorSettings.isEnabled ? "Đã nối · đang bật" : "Đã nối · đang tắt"
    }

    private var mirrorLastRunText: String {
        _ = mirrorStateTick
        guard let date = MirrorSettings.lastRunAt else {
            return "Chưa gương lần nào"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "HH:mm dd/MM/yyyy"
        return formatter.string(from: date)
    }

    /// Dòng "Lần mở bộ chọn gần nhất" (Gói 1 — điểm yếu
    /// 2.6): kết quả lần mở bộ chọn thư mục vừa rồi kèm giờ,
    /// đọc từ bản ghi bền của MirrorSettings. Ba kết quả
    /// phân biệt rõ: chọn được thư mục (kèm tên) / anh tự
    /// huỷ / bộ chọn không có phản hồi. Chưa từng mở thì
    /// CardsView không hiện dòng này (điều kiện ở chỗ gọi).
    private var mirrorLastPickerText: String {
        _ = mirrorStateTick
        guard let outcome = MirrorSettings.lastPickerOutcome,
              let date = MirrorSettings.lastPickerAt else {
            return "Chưa có"
        }
        let result: String
        switch outcome {
        case .picked:
            if let name = MirrorSettings.lastPickerFolderName {
                result = "Đã chọn thư mục “\(name)”"
            } else {
                result = "Đã chọn thư mục"
            }
        case .cancelled:
            result = "Đã huỷ"
        case .noResponse:
            result = "Không có phản hồi"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "HH:mm dd/MM/yyyy"
        return "\(result) — \(formatter.string(from: date))"
    }

    // MARK: P2-2 — trạng thái Drive (đọc DriveSettings)

    /// Trạng thái Drive nói thật: chưa đăng nhập / đã đăng
    /// nhập (kèm email nếu lấy được) / lượt gần nhất có lỗi.
    /// Đọc driveStateTick để vẽ lại khi có thông báo đổi.
    private var driveStatusText: String {
        _ = driveStateTick
        guard DriveAuth.isSignedIn else {
            return "Chưa đăng nhập"
        }
        if DriveSettings.lastError != nil {
            return "Đã đăng nhập · lượt gần nhất có lỗi (xem dưới)"
        }
        if let email = DriveSettings.accountEmail {
            return "Đã đăng nhập · \(email)"
        }
        return "Đã đăng nhập"
    }

    private var driveLastRunText: String {
        _ = driveStateTick
        guard let date = DriveSettings.lastRunAt else {
            return "Chưa đồng bộ lần nào"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "HH:mm dd/MM/yyyy"
        return formatter.string(from: date)
    }

    // MARK: L-2026-11-20-42 — trạng thái kiểm kê ảnh gốc

    /// Dòng "Ảnh gốc": đủ N/N khi không file tham chiếu nào
    /// mất hẳn; có mất thì nêu số thiếu + số đã tự khôi phục
    /// từ kho an toàn ở lượt kiểm gần nhất. Đọc
    /// integrityStateTick để vẽ lại khi kiểm kê báo đổi.
    private var integrityStatusText: String {
        _ = integrityStateTick
        guard let summary = IntegritySettings.lastSummary else {
            return "Chưa kiểm kê"
        }
        if summary.missingCount == 0 {
            return "đủ \(summary.presentCount)/\(summary.referencedCount)"
        }
        return "thiếu \(summary.missingCount) · đã tự khôi phục \(summary.restoredCount)"
    }

    private var integrityLastCheckText: String {
        _ = integrityStateTick
        guard let date = IntegritySettings.lastCheckAt else {
            return "Chưa kiểm kê"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "HH:mm dd/MM/yyyy"
        return formatter.string(from: date)
    }

    /// Mở bộ chọn thư mục gương bằng đường trình UIKit thuần
    /// (L-2026-11-19-36: KHÔNG qua .sheet SwiftUI — bản 146
    /// thao tác chọn bị nuốt, delegate không chạy). Chọn xong:
    /// nhận thư mục, dậy lại giao diện, gương ngay một lượt.
    private func presentMirrorFolderPicker() {
        MirrorFolderPickerPresenter.present(
            onPick: { url in
                MirrorSettings.adoptFolder(url)
                mirrorStateTick += 1
                MirrorSync.requestSync(using: modelContext)
                DriveSync.requestSync(using: modelContext)
            },
            onCancel: {
                mirrorStateTick += 1
            })
    }

    /// Kích thước file log chẩn đoán hiện tại; đọc
    /// logStateTick để vẽ lại sau khi xoá log.
    private var logSizeText: String {
        _ = logStateTick
        return DiagLog.currentSizeText
    }

    /// Bật gương mà chưa có thư mục thì bật = mở bộ chọn thư
    /// mục trước (chọn xong MirrorSettings tự bật); đã có thư
    /// mục thì bật và gương ngay một lượt.
    private var mirrorToggleBinding: Binding<Bool> {
        Binding(
            get: { MirrorSettings.isEnabled },
            set: { newValue in
                if newValue {
                    if MirrorSettings.isConnected {
                        MirrorSettings.isEnabled = true
                        MirrorSync.requestSync(using: modelContext)
                        DriveSync.requestSync(using: modelContext)
                    } else {
                        presentMirrorFolderPicker()
                    }
                } else {
                    MirrorSettings.isEnabled = false
                }
                mirrorStateTick += 1
            })
    }
}

// MARK: - Dữ liệu trung gian của form thẻ

struct CardFormData {
    var existingCard: CardTail? = nil
    var last4: String
    var brand: String
    var kind: Classification
}

struct PendingKindChange {
    var card: CardTail
    var brand: String
    var kind: Classification
    var last4: String
    /// P2-0/C-8: số tờ xếp lại sẽ chạm / số tờ giữ nguyên —
    /// tính lúc mở hộp thoại để nói rõ phạm vi trước.
    var affectedCount: Int = 0
    var untouchedCount: Int = 0
}

enum CardFormTarget: Identifiable {
    case new
    case edit(CardTail)

    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let card): return "edit-\(card.last4)-\(card.createdAt.timeIntervalSince1970)"
        }
    }
}

// MARK: - Form thêm / sửa thẻ

struct CardFormView: View {
    var target: CardFormTarget
    var existingTails: [CardTail]
    var onComplete: (CardFormData) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var last4Text: String
    @State private var brandText: String
    @State private var selectedKind: Classification
    @State private var errorText: String? = nil

    init(target: CardFormTarget, existingTails: [CardTail], onComplete: @escaping (CardFormData) -> Void) {
        self.target = target
        self.existingTails = existingTails
        self.onComplete = onComplete
        switch target {
        case .new:
            _last4Text = State(initialValue: "")
            _brandText = State(initialValue: "")
            _selectedKind = State(initialValue: .business)
        case .edit(let card):
            _last4Text = State(initialValue: card.last4)
            _brandText = State(initialValue: card.brand)
            // P2-0 mục 17 (§2.2(7)): giữ đúng loại đã lưu —
            // bản cũ ép .unknown thành .personal ngay khi
            // mở form, anh chỉ sửa hãng cũng bị đổi loại oan.
            _selectedKind = State(initialValue: card.kind)
        }
    }

    private var isEditing: Bool {
        if case .edit = target { return true }
        return false
    }

    private var editedCard: CardTail? {
        if case .edit(let card) = target { return card }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("4 số cuối của thẻ") {
                    TextField("VD: 2586", text: $last4Text)
                        .keyboardType(.numberPad)
                        .monospacedDigit()
                        .disabled(isEditing) // đổi đuôi = thêm thẻ mới, không sửa đuôi của thẻ cũ
                    TextField("Hãng / nhãn (VD: Mastercard Debit)", text: $brandText)
                }
                Section("Thẻ này dùng cho") {
                    Picker("Loại", selection: $selectedKind) {
                        Text("CÁ NHÂN").tag(Classification.personal)
                        Text("BUSINESS").tag(Classification.business)
                        // P2-0 mục 17 (§2.2(7)): loại CHƯA RÕ
                        // chọn được ở form thẻ như mọi nơi khác.
                        Text("CHƯA RÕ").tag(Classification.unknown)
                    }
                    .pickerStyle(.segmented)
                    Text("Hoá đơn trả bằng thẻ này sẽ được GỢI Ý xếp vào loại trên — anh luôn đổi được từng tờ.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let errorText {
                    Section {
                        Text(errorText).foregroundStyle(.red).font(.callout)
                    }
                }
                Section {
                    Button("Lưu thẻ") { submit() }
                        .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(isEditing ? "Sửa Thẻ" : "Thêm Thẻ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { dismiss() }
                }
            }
        }
    }

    private func submit() {
        let digits = last4Text.filter { $0.isNumber }
        guard digits.count == 4 else {
            errorText = "Anh nhập đúng 4 số cuối của thẻ giúp em."
            return
        }
        if !isEditing, existingTails.contains(where: { $0.last4 == digits && !$0.archived }) {
            errorText = "Đuôi \(digits) đã có trong danh sách thẻ đang dùng."
            return
        }
        // P2-0 mục 17 (§2.2(7)): đuôi đã có ở mục NGƯNG
        // DÙNG cũng không thêm bản trùng — chỉ đường dùng
        // lại thẻ cũ. Bản cũ cho qua và sinh hai CardTail
        // cùng đuôi.
        if !isEditing, existingTails.contains(where: { $0.last4 == digits && $0.archived }) {
            errorText = "Đuôi \(digits) đã có ở mục thẻ đã ngưng dùng — anh dùng lại thẻ đó (nút Dùng lại) thay vì thêm trùng."
            return
        }
        let data = CardFormData(
            existingCard: editedCard,
            last4: digits,
            brand: brandText.trimmingCharacters(in: .whitespaces),
            kind: selectedKind
        )
        onComplete(data)
        dismiss()
    }
}

// MARK: - Màn xem log chẩn đoán (LOGKIT — L-2026-11-19-39)

/// Đọc toàn văn file log ngay trong app: cuộn dọc, chữ
/// monospace nhỏ, chọn/copy được. Nạp lại mỗi lần mở màn và
/// khi anh bấm "Nạp lại" (log vẫn ghi tiếp trong lúc xem).
private struct DiagnosticsLogView: View {
    @State private var text: String = ""

    var body: some View {
        ScrollView {
            Text(text.isEmpty
                 ? "Log đang trống — chưa có sự kiện nào được ghi."
                 : text)
                .font(.system(.caption2, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .textSelection(.enabled)
        }
        .navigationTitle("Log chẩn đoán")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { text = DiagLog.readAllText() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Nạp lại") { text = DiagLog.readAllText() }
            }
        }
    }
}

// MARK: - Pha 2 (L-2026-11-21-47): bảng thuế theo khu vực

struct TaxAreaListView: View {
    @State private var portions: [TaxAreaPortion] =
        TaxSettings.effectiveTable.portions

    var body: some View {
        List {
            Section {
                ForEach(portions, id: \.id) { portion in
                    NavigationLink {
                        TaxAreaEditorView(portion: portion)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(portion.displayName)
                            Text("Đầy đủ \(TaxLanding.formatPct(portion.fullPct))% · Thực phẩm \(TaxLanding.formatPct(portion.groceryPct))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                Text("Mỗi khu gồm ba phần: bang + quận + thành phố. Thực phẩm được miễn phần bang nên chỉ tính quận + thành phố. Bấm vào một khu để sửa từng phần trăm.")
            }
        }
        .navigationTitle("Bảng thuế theo khu vực")
        .onAppear { portions = TaxSettings.effectiveTable.portions }
    }
}

struct TaxAreaEditorView: View {
    let portion: TaxAreaPortion

    @State private var stateText: String
    @State private var countyText: String
    @State private var cityText: String
    @Environment(\.dismiss) private var dismiss

    init(portion: TaxAreaPortion) {
        self.portion = portion
        _stateText = State(initialValue: TaxLanding.formatPct(portion.statePct))
        _countyText = State(initialValue: TaxLanding.formatPct(portion.countyPct))
        _cityText = State(initialValue: TaxLanding.formatPct(portion.cityPct))
    }

    private func parsePct(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }

    private var fullPct: Double? {
        guard let s = parsePct(stateText),
              let c = parsePct(countyText),
              let t = parsePct(cityText) else { return nil }
        return s + c + t
    }

    private var groceryPct: Double? {
        guard let c = parsePct(countyText),
              let t = parsePct(cityText) else { return nil }
        return c + t
    }

    /// Mỗi phần phải nằm trong 0–15% — chặn lỗi gõ thừa số 0
    /// (4.5 thành 45) làm hỏng mọi ước tính của khu về sau.
    private var partsValid: Bool {
        [stateText, countyText, cityText].allSatisfy { text in
            guard let v = parsePct(text) else { return false }
            return v >= 0 && v <= 15
        }
    }

    var body: some View {
        Form {
            Section("Ba phần thuế (%) — anh nhập từng phần, app cộng") {
                HStack {
                    Text("Bang (State)")
                    Spacer()
                    pctField($stateText)
                }
                HStack {
                    Text("Quận (County)")
                    Spacer()
                    pctField($countyText)
                }
                HStack {
                    Text("Thành phố (City)")
                    Spacer()
                    pctField($cityText)
                }
            }
            Section("Suất gộp app sẽ áp") {
                LabeledContent("Đầy đủ (hàng thường, nhà hàng)",
                               value: fullPct.map {
                                   "\(TaxLanding.formatPct($0))%"
                               } ?? "—")
                LabeledContent("Thực phẩm (chỉ quận + thành phố)",
                               value: groceryPct.map {
                                   "\(TaxLanding.formatPct($0))%"
                               } ?? "—")
            }
            Section {
                if !partsValid {
                    Text("Mỗi phần thuế phải là số từ 0% đến 15% — anh kiểm tra lại giúp (gõ thừa một số 0 là suất nhảy gấp mười lần).")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Button("Lưu phần trăm khu này") {
                    guard let s = parsePct(stateText),
                          let c = parsePct(countyText),
                          let t = parsePct(cityText) else { return }
                    var edited = portion
                    edited.statePct = s
                    edited.countyPct = c
                    edited.cityPct = t
                    TaxSettings.setOverride(edited)
                    dismiss()
                }
                .disabled(!partsValid)
            } footer: {
                Text("Số đã sửa được lưu trên máy và áp cho mọi lần đọc sau, cho tới khi anh sửa lại.")
            }
        }
        .navigationTitle(portion.displayName)
    }

    private func pctField(_ binding: Binding<String>) -> some View {
        TextField("0.0", text: binding)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 90)
    }
}

// MARK: - A6: danh sách tờ tới ngưỡng lưu giữ 7 năm (chỉ xem)

/// Liệt kê tờ có hạn lưu giữ đã qua hoặc rơi trong 12 tháng tới.
/// Tờ cũ chưa được gán retentionUntil thì hạn được TÍNH từ năm
/// thuế để hiển thị (không ghi lại vào sổ). Không có nút xoá.
struct RetentionHorizonView: View {
    @Query(sort: \Receipt.date) private var receipts: [Receipt]

    private var dueRows: [(receipt: Receipt, until: Date)] {
        let now = Date()
        return receipts.compactMap { receipt in
            guard let until = receipt.retentionUntil
                    ?? receipt.computedRetentionUntil,
                  RetentionPolicy.reachesHorizon(retentionUntil: until, now: now)
            else { return nil }
            return (receipt, until)
        }
    }

    var body: some View {
        let rows = dueRows
        List {
            Section {
                if rows.isEmpty {
                    Text("Chưa có tờ nào tới hạn lưu giữ trong 12 tháng tới.")
                        .foregroundStyle(.secondary)
                }
                ForEach(rows, id: \.receipt.id) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.receipt.vendor.isEmpty ? "(Chưa rõ tiệm)" : row.receipt.vendor)
                            .font(.body.weight(.semibold))
                        Text("Năm thuế \(String(row.receipt.taxYear)) · hạn 31/12/\(String(RetentionPolicy.year(of: row.until)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("\(rows.count) tờ. Chỉ xem — app không tự xoá. Hạn = 31/12 năm thuế + \(RetentionPolicy.years).")
            }
        }
        .navigationTitle("Hạn lưu giữ")
    }
}
