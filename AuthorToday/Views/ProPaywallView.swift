import SwiftUI
import StoreKit
import UIKit

struct ProPaywallView: View {
    @EnvironmentObject private var pro: ProEntitlementStore
    @EnvironmentObject private var appearance: AppAppearanceStore
    @Environment(\.dismiss) private var dismiss

    var reason: String?

    @State private var showRedeem = false
    @State private var redeemCode = ""
    @State private var redeemMessage: String?
    @State private var selectedPlan: ProGrantStore.Plan = .month
    @State private var didCopyPhone = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if let reason, !reason.isEmpty {
                        Text(reason)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                    }
                    bullets
                    if !pro.isProUnlocked {
                        manualPayment
                    }
                    if !pro.products.isEmpty {
                        storeProducts
                    }
#if DEBUG
                    Toggle(
                        "DEBUG: Pro без StoreKit",
                        isOn: Binding(
                            get: { UserDefaults.standard.bool(forKey: "pro.debugUnlocked") },
                            set: { pro.setDebugUnlocked($0) }
                        )
                    )
                    .font(.footnote)
#endif
                    redeemBlock
                    legal
                }
                .padding(20)
            }
            .background {
                ThemeAtmosphereView(preset: appearance.themePreset)
            }
            .navigationTitle("Читальня Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Закрыть") { dismiss() }
                }
            }
            .task {
                await pro.refresh()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(pro.isProUnlocked ? "Pro активен" : "Удобства клиента")
                .font(.title2.weight(.semibold))
            if pro.isComplimentaryPro {
                Label("Pro по аккаунту (без App Store)", systemImage: "person.crop.circle.badge.checkmark")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(appearance.accent)
            } else if pro.isProUnlocked {
                Label("Спасибо за поддержку", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(appearance.accent)
            }
            Text("Pro улучшает Читальню (темы, офлайн, «Мои книги»). Книги Author.Today — только на author.today.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var bullets: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(ProFeatures.paywallBullets, id: \.self) { line in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(appearance.accent)
                    Text(line)
                        .font(.subheadline)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var manualPayment: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Оплата (временно)")
                .font(.headline)

            Picker("Срок", selection: $selectedPlan) {
                ForEach(ProGrantStore.Plan.allCases) { plan in
                    Text(plan.title).tag(plan)
                }
            }
            .pickerStyle(.segmented)

            HStack(alignment: .firstTextBaseline) {
                Text(selectedPlan.priceLabel)
                    .font(.title.weight(.semibold))
                if let hint = selectedPlan.perMonthHint {
                    Text(hint)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Text(selectedPlan.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Label("СБП → \(ProFeatures.ManualPayment.bank)", systemImage: "building.columns")
                HStack {
                    Text(ProFeatures.ManualPayment.phoneDisplay)
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .textSelection(.enabled)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = ProFeatures.ManualPayment.phoneE164
                        didCopyPhone = true
                    } label: {
                        Label(didCopyPhone ? "Скопировано" : "Копировать", systemImage: "doc.on.doc")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                }
                Text("Переведите \(selectedPlan.priceLabel). В комментарии укажите:")
                    .font(.subheadline.weight(.medium))
                    .padding(.top, 4)
                VStack(alignment: .leading, spacing: 4) {
                    Text("• «\(ProFeatures.ManualPayment.transferNote)»")
                    Text("• срок: \(selectedPlan.title.lowercased())")
                    Text("• куда выслать код: Max или Telegram (@ник)")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Text("После оплаты пришлём код активации. Затем введите его ниже.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
            )

            VStack(alignment: .leading, spacing: 6) {
                Text("Все тарифы")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(ProGrantStore.Plan.allCases) { plan in
                    HStack {
                        Text(plan.title)
                        Spacer()
                        Text(plan.priceLabel)
                            .font(.body.monospacedDigit().weight(.medium))
                        if let hint = plan.perMonthHint {
                            Text(hint)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(plan == selectedPlan ? .primary : .secondary)
                }
            }
            .padding(.top, 4)
        }
    }

    private var storeProducts: some View {
        VStack(spacing: 12) {
            Text("App Store (когда подключим)")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            if pro.isLoadingProducts, pro.products.isEmpty {
                ProgressView("Загрузка тарифов…")
                    .frame(maxWidth: .infinity)
                    .padding()
            }

            if let yearly = pro.yearlyProduct {
                productButton(yearly, badge: "Выгодно")
            }
            if let monthly = pro.monthlyProduct {
                productButton(monthly, badge: nil)
            }
            if let lifetime = pro.lifetimeProduct {
                productButton(lifetime, badge: "Навсегда")
            }

            Button {
                Task { await pro.restore() }
            } label: {
                Text("Восстановить покупки")
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(pro.isPurchasing)

            if let err = pro.lastError, !err.isEmpty {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var redeemBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                showRedeem.toggle()
            } label: {
                Text(showRedeem ? "Скрыть ввод кода" : (pro.isProUnlocked ? "Другой код" : "У меня есть код"))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)

            if showRedeem {
                TextField("Код (например CN30-…)", text: $redeemCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                Button {
                    redeem()
                } label: {
                    Text("Активировать Pro")
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(appearance.accent)
                if let redeemMessage {
                    Text(redeemMessage)
                        .font(.footnote)
                        .foregroundStyle(
                            redeemMessage.localizedCaseInsensitiveContains("актив")
                                ? appearance.accent
                                : .red
                        )
                }
            }
        }
    }

    private func redeem() {
        let auth = AuthService.shared
        let loginEmail = UserDefaults.standard.string(forKey: "at.auth.loginEmail")
        if let err = ProGrantStore.shared.redeemInvite(
            code: redeemCode,
            email: auth.user?.email ?? loginEmail,
            userName: auth.user?.resolvedUserName ?? auth.resolvedUserName
        ) {
            redeemMessage = err
            return
        }
        pro.applyAccount(
            email: auth.user?.email ?? loginEmail,
            userName: auth.user?.resolvedUserName ?? auth.resolvedUserName
        )
        pro.refreshComplimentaryFromGrants()
        if pro.isProUnlocked {
            let grant = ProGrantStore.shared.grants.first {
                ProFeatures.normalize($0.email) == ProFeatures.normalize(auth.user?.email ?? loginEmail)
                    || ProFeatures.normalize($0.email) == ProFeatures.normalize(auth.user?.resolvedUserName ?? auth.resolvedUserName)
            }
            if let exp = grant?.expiresAt {
                redeemMessage = "Pro до \(exp.formatted(date: .abbreviated, time: .omitted))"
            } else {
                redeemMessage = "Pro активирован"
            }
            redeemCode = ""
        } else {
            redeemMessage = "Код принят. Если Pro не включился — перезайдите в аккаунт."
        }
    }

    private func productButton(_ product: Product, badge: String?) -> some View {
        Button {
            Task {
                let ok = await pro.purchase(product)
                if ok { dismiss() }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(product.displayName)
                            .font(.headline)
                        if let badge {
                            Text(badge)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(appearance.accent.opacity(0.2))
                                .clipShape(Capsule())
                        }
                    }
                    Text(product.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                if pro.isPurchasing {
                    ProgressView()
                } else {
                    Text(product.displayPrice)
                        .font(.headline.monospacedDigit())
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
        }
        .buttonStyle(.plain)
        .disabled(pro.isPurchasing || pro.isProUnlocked)
        .opacity(pro.isProUnlocked ? 0.55 : 1)
    }

    private var legal: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Сейчас оплата идёт переводом на указанный номер (СБП). Это не покупка через Apple и не оплата книг Author.Today. Когда подключим App Store, оплата будет через IAP.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if !pro.products.isEmpty, let url = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/") {
                Link("Условия использования Apple (EULA)", destination: url)
                    .font(.caption)
            }
        }
        .padding(.top, 8)
    }
}
