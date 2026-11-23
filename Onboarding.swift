// Onboarding.swift — A12(i) (vòng 2, WP9; DESIGN-AUDIT §4.10).
//
// Ba bước "làm thật" kiểu Things 3, không slideshow, hiện MỘT lần
// (cờ didOnboard), bước nào cũng có "Để sau". Chỉ mở cho SỔ TRỐNG
// (chưa có hoá đơn nào) — sổ đang dùng của anh không bao giờ thấy màn
// này. Không ghi dữ liệu gì ngoài:
//   - cờ didOnboard (UserDefaults);
//   - thẻ MỚI khi anh tự bấm "Thêm thẻ khác" (đúng CardFormView +
//     đúng luật lưu của màn Thẻ: lưu hỏng thì gỡ thẻ, không im lặng).
// Thẻ mồi •• 2586 vẫn do seedStarterCardIfNeeded tạo như cũ; bước 2
// chỉ hỏi anh xác nhận nó. Chỉ target app.

import SwiftUI
import SwiftData

enum OnboardingState {
    static let didOnboardKey = "didOnboard"

    static var didOnboard: Bool {
        get { UserDefaults.standard.bool(forKey: didOnboardKey) }
        set { UserDefaults.standard.set(newValue, forKey: didOnboardKey) }
    }
}

struct OnboardingView: View {
    /// Anh bấm "Chụp thử" ở bước 3 -> tầng vỏ chuyển sang tab CHỤP.
    var onScanNow: () -> Void
    var onFinish: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CardTail.createdAt) private var cards: [CardTail]
    @State private var step = 1
    @State private var showCardForm = false
    @State private var saveFailed = false

    private var activeCards: [CardTail] { cards.filter { !$0.archived } }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                switch step {
                case 1: stepIntro
                case 2: stepCard
                default: stepScan
                }
                Spacer()
                Button("Để sau") { finish() }
                    .font(.callout)
                    .frame(minHeight: 44)
                    .frame(maxWidth: .infinity)
            }
            .padding(24)
            .background(DSBackground())
            .navigationTitle("Bước \(step)/3")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showCardForm) {
            CardFormView(target: .new, existingTails: cards) { data in
                addCard(data)
            }
        }
        .alert("Lưu không thành công", isPresented: $saveFailed) {
            Button("Đã hiểu", role: .cancel) {}
        } message: {
            Text("Thẻ CHƯA được lưu vào máy. Anh thử lại ở tab Thẻ & Cài Đặt giúp.")
        }
    }

    // MARK: Bước 1 — một câu

    private var stepIntro: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sổ Hóa Đơn").font(.largeTitle.bold())
            Text("Chụp hoá đơn — app tự đọc và chia Cá nhân / Business theo đuôi thẻ debit của anh.")
                .font(.body)
            HStack(spacing: 8) {
                ClassificationBadge(kind: .personal)
                ClassificationBadge(kind: .business)
            }
            Button("Bắt đầu") { step = 2 }
                .buttonStyle(PrimaryButtonStyle())
        }
    }

    // MARK: Bước 2 — thẻ debit hay dùng nhất

    private var stepCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Thẻ debit anh hay dùng nhất").font(.title2.bold())
            if activeCards.isEmpty {
                Text("Chưa có thẻ nào. Anh thêm 4 số cuối của thẻ — app sẽ tự gợi ý Cá nhân / Business cho mỗi hoá đơn trả bằng thẻ đó.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("Thẻ này đúng chưa?").font(.callout).foregroundStyle(.secondary)
                ForEach(activeCards) { card in
                    HStack {
                        Text(card.brand.isEmpty ? "Thẻ" : card.brand)
                        Spacer()
                        ClassificationBadge(kind: card.kind, cardLast4: card.last4)
                    }
                }
            }
            if !activeCards.isEmpty {
                Button("Đúng, giữ thẻ này") { step = 3 }
                    .buttonStyle(PrimaryButtonStyle())
            }
            Button("Thêm thẻ khác") { showCardForm = true }
                .font(.callout.weight(.semibold))
                .frame(minHeight: 44)
            if activeCards.isEmpty {
                Button("Tiếp") { step = 3 }
                    .font(.callout)
                    .frame(minHeight: 44)
            }
            Text("Sửa / ngưng thẻ bất cứ lúc nào ở tab Thẻ & Cài Đặt.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Bước 3 — chụp thử một tờ

    private var stepScan: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Thử chụp 1 tờ").font(.title2.bold())
            Text("Chọn một hoá đơn bất kỳ — đọc ngay trên máy, ảnh không rời khỏi iPhone.")
                .font(.body)
            Button("Chụp thử") {
                OnboardingState.didOnboard = true
                onScanNow()
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    // MARK: Ghi

    private func finish() {
        OnboardingState.didOnboard = true
        onFinish()
    }

    /// Cùng luật lưu thẻ MỚI của CardsView.handleFormData.
    private func addCard(_ data: CardFormData) {
        guard data.existingCard == nil else { return }
        let card = CardTail()
        card.last4 = data.last4
        card.brand = data.brand
        card.kind = data.kind
        modelContext.insert(card)
        if !saveContextOrFalse(modelContext) {
            modelContext.delete(card)
            saveFailed = true
        }
    }
}
