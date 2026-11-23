import SwiftUI
import SwiftData

/// Trang Chủ: thẻ Chờ Duyệt lên đầu (khi có việc), 2 ô tổng năm nay
/// Cá nhân / Business tách bạch, vài hoá đơn gần nhất. (DESIGN-V2 / Copilot Money)
struct HomeView: View {
    /// PASS 2: hàng hành động nhanh chuyển tab thật (tab do
    /// TabShellView giữ) — không phải nút trang trí.
    @Binding var selectedTab: Int

    @Query(sort: \Receipt.date, order: .reverse) private var receipts: [Receipt]

    private var currentYearReceipts: [Receipt] {
        let year = Calendar.current.component(.year, from: Date())
        return receipts.filter { Calendar.current.component(.year, from: $0.date) == year }
    }

    private var needsReviewCount: Int {
        receipts.filter { $0.status == .needsReview }.count
    }

    /// P2-0/C-2: tổng năm CHÍNH THỨC = chỉ tờ đã duyệt,
    /// không bị loại khỏi tổng (bản trùng), tính theo số ĐÃ
    /// TRẢ (tổng in + tip). Trước gói này hero cộng cả tờ
    /// đang chờ duyệt và dùng totalCents trơn.
    private func yearSum(_ kind: Classification) -> Int {
        // A7: luật chính thức một nguồn (OfficialReceiptRule).
        currentYearReceipts.officialTotalCents(kind: kind)
    }

    /// P2-0/C-2: tiền chờ duyệt của năm nay — hiện một dòng
    /// riêng dưới thẻ hero, không trộn vào tổng chính thức.
    private var yearPendingTotal: Int {
        currentYearReceipts.pendingTotalCents()
    }

    private var topCategories: [(name: String, kind: Classification, total: Int)] {
        var totals: [String: (Classification, Int)] = [:]
        // P2-0/C-2: chỉ tờ chính thức (đã duyệt, không loại
        // khỏi tổng), số đã trả.
        for receipt in currentYearReceipts
        where receipt.isOfficialRecord {
            let key = receipt.category.isEmpty ? "Khác" : receipt.category
            let old = totals[key] ?? (receipt.classification, 0)
            totals[key] = (receipt.classification, old.1 + receipt.countedAmountCents)
        }
        return totals
            .map { (name: $0.key, kind: $0.value.0, total: $0.value.1) }
            .sorted { $0.total > $1.total }
            .prefix(6)
            .map { $0 }
    }

    // UI-2026-11-13: Trang Chủ dựng lại theo DesignSystem —
    // thẻ hero tổng năm + thanh chia tỉ lệ Cá nhân/Business,
    // banner chờ duyệt dạng thẻ cảnh báo, các khối là DSCard
    // trên ScrollView (chuẩn app tài chính top: số liệu lớn
    // lên đầu, một điểm nhấn màu, khoảng trắng đều thang 4).
    // MỌI phép tính dữ liệu giữ nguyên như bản List cũ.
    private var yearTotalCents: Int {
        yearSum(.personal) + yearSum(.business) + yearSum(.unknown)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.spaceL) {
                    if needsReviewCount > 0 {
                        NavigationLink {
                            ReceiptListView(onlyNeedsReview: true)
                        } label: {
                            HStack(spacing: DS.spaceM) {
                                Image(systemName: "tray.full.fill")
                                    .font(.title3)
                                    .foregroundStyle(DS.warning)
                                    .frame(width: 40, height: 40)
                                    .background(DS.warning.opacity(0.14))
                                    .clipShape(Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(needsReviewCount) hoá đơn chờ phân loại / duyệt")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text("Chưa duyệt = chưa phải chứng từ chính thức")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(DS.spaceL)
                            .dsCard()
                        }
                        .buttonStyle(.plain)
                    }

                    heroCard

                    HStack(spacing: DS.spaceM) {
                        actionTile(icon: "camera.viewfinder", title: "Quét hoá đơn") { selectedTab = 2 }
                        actionTile(icon: "square.and.arrow.down", title: "Nạp file") { selectedTab = 2 }
                        actionTile(icon: "doc.text.magnifyingglass", title: "Hồ sơ thuế") { selectedTab = 3 }
                    }

                    if !topCategories.isEmpty {
                        VStack(alignment: .leading, spacing: DS.spaceS) {
                            sectionTitle("Theo mục")
                            VStack(spacing: 0) {
                                // P2-0 mục 17 (§2.2(7)): id theo
                                // vị trí — hai mục trùng tên ở
                                // hai loại khác nhau không còn
                                // đè nhau trong danh sách.
                                ForEach(Array(topCategories.enumerated()), id: \.offset) { index, entry in
                                    HStack(spacing: DS.spaceM) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 13)
                                                .fill(LinearGradient(colors: DS.categoryTileColors(entry.name),
                                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                                            Image(systemName: DS.categoryIconName(entry.name))
                                                .font(.system(size: 17, weight: .semibold))
                                                .foregroundStyle(.white)
                                        }
                                        .frame(width: 42, height: 42)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(entry.name)
                                                .lineLimit(1)
                                            Text(entry.kind.label)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        MoneyAmount(cents: entry.total, font: .callout.weight(.semibold))
                                    }
                                    .padding(.vertical, DS.spaceS)
                                    if index < topCategories.count - 1 {
                                        Divider()
                                    }
                                }
                            }
                            .padding(.horizontal, DS.spaceL)
                            .padding(.vertical, DS.spaceS)
                            .dsCard()
                        }
                    }

                    if !receipts.isEmpty {
                        VStack(alignment: .leading, spacing: DS.spaceS) {
                            sectionTitle("Gần đây")
                            VStack(spacing: 0) {
                                ForEach(Array(receipts.prefix(5).enumerated()), id: \.element.id) { index, receipt in
                                    NavigationLink {
                                        ReceiptDetailView(receipt: receipt)
                                    } label: {
                                        ReceiptRowView(
                                            receipt: receipt,
                                            hasDuplicates: !receipt.stableID.isEmpty
                                                && receipts.contains {
                                                    $0.duplicateOfStableID == receipt.stableID
                                                })
                                    }
                                    .buttonStyle(.plain)
                                    if index < min(5, receipts.count) - 1 {
                                        Divider()
                                    }
                                }
                            }
                            .padding(.horizontal, DS.spaceL)
                            .padding(.vertical, DS.spaceS)
                            .dsCard()
                        }
                    } else {
                        VStack(spacing: DS.spaceS) {
                            Image(systemName: "doc.viewfinder")
                                .font(.system(size: 40))
                                .foregroundStyle(DS.brand)
                            Text("Chưa có hoá đơn nào")
                                .font(.headline)
                            Text("Bấm nút CHỤP ở dưới để quét tờ đầu tiên.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(DS.spaceXL)
                        .dsCard()
                    }

                    Text("Đọc ngay trên máy — ảnh hoá đơn không rời khỏi iPhone. Ảnh gốc lưu trong thư mục của app (Files → Trên iPhone → GL-Keeper).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(DS.spaceL)
            }
            .dsScreenBackground()
            .navigationTitle("GL-Keeper")
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// PASS 2: dòng phụ của thẻ hero — suy thẳng từ 3 tổng
    /// năm nay (không thêm phép tính mới): toàn Business /
    /// toàn Cá nhân / tỉ lệ phần trăm khi có cả hai.
    private var heroSubtitle: String {
        let personal = yearSum(.personal), business = yearSum(.business)
        if personal == 0 && business > 0 { return "Toàn bộ là Business" }
        if business == 0 && personal > 0 { return "Toàn bộ là Cá nhân" }
        let total = max(yearTotalCents, 1)
        let bPct = Int((Double(business) / Double(total) * 100).rounded())
        return "Business \(bPct)% · Cá nhân \(100 - bPct)%"
    }

    private func actionTile(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(DS.brand)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.spaceM)
            .dsCard(radius: 18)
        }
        .buttonStyle(.plain)
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: DS.spaceM) {
            Text("TỔNG CHI NĂM NAY — \(String(Calendar.current.component(.year, from: Date())))")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.75))
                .tracking(0.6)
            Text(formatMoney(cents: yearTotalCents))
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(heroSubtitle)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.82))
            splitBar
            HStack(spacing: DS.spaceL) {
                splitLegend(kind: .personal)
                splitLegend(kind: .business)
                if yearSum(.unknown) != 0 {
                    splitLegend(kind: .unknown)
                }
            }
            // P2-0/C-2: tiền chờ duyệt hiện RIÊNG — tổng lớn
            // ở trên là tổng chính thức (đã duyệt) mà thôi.
            if yearPendingTotal != 0 {
                Text("Đang chờ duyệt: \(formatMoney(cents: yearPendingTotal)) — chưa tính vào tổng chính thức")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.82))
            }
        }
        .padding(DS.spaceL)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.heroGradient)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .shadow(color: Color(red: 0.016, green: 0.235, blue: 0.157).opacity(0.45), radius: 17, x: 0, y: 9)
    }

    private var splitBar: some View {
        GeometryReader { geo in
            let total = max(yearTotalCents, 1)
            HStack(spacing: 2) {
                Rectangle()
                    .fill(Theme.personalColor)
                    .frame(width: geo.size.width * CGFloat(yearSum(.personal)) / CGFloat(total))
                Rectangle()
                    .fill(Theme.businessColor)
                    .frame(width: geo.size.width * CGFloat(yearSum(.business)) / CGFloat(total))
                if yearSum(.unknown) != 0 {
                    Rectangle()
                        .fill(Color.gray)
                        .frame(width: geo.size.width * CGFloat(yearSum(.unknown)) / CGFloat(total))
                }
            }
        }
        .frame(height: 8)
        .background(Capsule().fill(Color.white.opacity(0.22)))
        .clipShape(Capsule())
    }

    private func splitLegend(kind: Classification) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Circle()
                    .fill(kind.color)
                    .frame(width: 8, height: 8)
                Text(kind.label)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.75))
            }
            Text(formatMoney(cents: yearSum(kind)))
                .font(.callout.weight(.bold))
                .foregroundStyle(.white)
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
    }
}

// MARK: - Báo Cáo Thuế (Build 1: bảng tổng theo năm — xuất Tax Pack để bản sau)

struct ReportsView: View {
    @Query(sort: \Receipt.date, order: .reverse) private var receipts: [Receipt]
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())

    private var availableYears: [Int] {
        var years = Set(receipts.map { Calendar.current.component(.year, from: $0.date) })
        years.insert(Calendar.current.component(.year, from: Date()))
        return years.sorted(by: >)
    }

    private var yearReceipts: [Receipt] {
        receipts.filter { Calendar.current.component(.year, from: $0.date) == selectedYear }
    }

    // A3 (vòng 2): phép tính của màn này nay nằm ở TaxReportMath
    // (ExportKit.swift) — MỘT nguồn cho cả màn Báo Cáo lẫn Tax Pack
    // xuất ra (cùng thuật toán cũ: luật tờ chính thức A7, mục gom
    // theo "<loại>|<mục|Khác>", business trước rồi tổng giảm dần).

    var body: some View {
        let yearInputs = yearReceipts.map(ExportInputBuilder.light)
        let totals = TaxReportMath.totals(yearInputs)
        let categoryRows = TaxReportMath.categoryRows(yearInputs)
        NavigationStack {
            List {
                Section {
                    Picker("Năm thuế", selection: $selectedYear) {
                        ForEach(availableYears, id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // A12(iii) (vòng 2, WP9 §4.13): cảnh báo sẵn sàng của
                // năm thuế — CHỈ CẢNH BÁO, mở Hộp Chờ có sẵn.
                let readinessGap = TaxReportMath.readinessGapCount(yearInputs)
                if readinessGap > 0 {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Năm \(String(selectedYear)) chưa sẵn sàng",
                                  systemImage: "exclamationmark.triangle.fill")
                                .font(.headline)
                                .foregroundStyle(DS.warning)
                            Text("Còn \(readinessGap) tờ chưa phân loại / chờ duyệt — xuất hồ sơ bây giờ sẽ thiếu các tờ này.")
                                .font(.callout)
                            NavigationLink {
                                ReceiptListView(onlyNeedsReview: true)
                            } label: {
                                Text("Mở Hộp Chờ")
                                    .font(.callout.weight(.semibold))
                                    .frame(minHeight: 44)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Tổng năm \(String(selectedYear))") {
                    HStack {
                        Label("CÁ NHÂN", systemImage: "person.fill")
                            .foregroundStyle(Theme.personalColor)
                        Spacer()
                        Text(formatMoney(cents: totals.personal))
                            .font(.body.weight(.semibold))
                            .monospacedDigit()
                    }
                    HStack {
                        Label("BUSINESS", systemImage: "briefcase.fill")
                            .foregroundStyle(Theme.businessColor)
                        Spacer()
                        Text(formatMoney(cents: totals.business))
                            .font(.body.weight(.semibold))
                            .monospacedDigit()
                    }
                    if totals.unknown != 0 {
                        HStack {
                            Label("CHƯA RÕ", systemImage: "questionmark.circle.fill")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(formatMoney(cents: totals.unknown))
                                .monospacedDigit()
                        }
                    }
                    Text("\(totals.count) hoá đơn · \(totals.needsReviewCount) tờ đang chờ duyệt (\(formatMoney(cents: totals.pending))) — tổng ở trên chỉ tính tờ ĐÃ duyệt, tiền chờ chưa tính vào")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !categoryRows.isEmpty {
                    Section("Theo mục (Schedule C worksheet — bản xem trước)") {
                        ForEach(categoryRows, id: \.key) { row in
                            HStack {
                                let kind = Classification(rawValue: row.kindNormalized) ?? .unknown
                                Image(systemName: kind.iconName)
                                    .foregroundStyle(kind.color)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(row.name)
                                    Text("\(row.count) hoá đơn")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(formatMoney(cents: row.total))
                                    .monospacedDigit()
                            }
                        }
                    }
                }

                // A3 (vòng 2): xuất Tax Pack + gói file gốc cho kế toán
                // (thay dòng "sẽ có ở bản sau").
                TaxPackExportSection(year: selectedYear, receipts: Array(receipts))
            }
            .dsListBackground()
            .navigationTitle("Báo Cáo Thuế")
        }
    }
}
