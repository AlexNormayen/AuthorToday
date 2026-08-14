import SwiftUI
import StoreKit

struct ProPaywallView: View {
    @EnvironmentObject private var pro: ProEntitlementStore
    @EnvironmentObject private var appearance: AppAppearanceStore
    @EnvironmentObject private var offline: OfflineStore
    @Environment(\.dismiss) private var dismiss

    var reason: String?

    @State private var showRedeem = false
    @State private var redeemCode = ""
    @State private var redeemMessage: String?

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
                    if !pro.isProUnlocked {
                        OfflineQuotaStatusView(compact: true)
                    }
                    bullets
                    if !pro.isProUnlocked {
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
            Text("Pro улучшает Читальню (темы, офлайн, закладки, «Мои книги»). Книги Author.Today — только на author.today.")
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

    private var storeProducts: some View {
        VStack(spacing: 12) {
            Text("Оплата через App Store")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("Часто доступны пробный период или скидка на первый срок — если Apple покажет их ниже, это настройки App Store Connect.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if pro.isLoadingProducts, pro.products.isEmpty {
                ProgressView("Загрузка тарифов…")
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if pro.products.isEmpty {
                Text("Тарифы появятся после публикации продуктов в App Store Connect. Пока можно восстановить покупки или ввести промокод.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Year first (best value), then month, then lifetime.
            if let yearly = pro.yearlyProduct {
                productButton(
                    yearly,
                    badge: "Выгодно",
                    subtitleHint: yearlySavingsHint(yearly: yearly, monthly: pro.monthlyProduct)
                )
            }
            if let monthly = pro.monthlyProduct {
                productButton(monthly, badge: nil, subtitleHint: introHint(for: monthly))
            }
            if let lifetime = pro.lifetimeProduct {
                productButton(lifetime, badge: "Навсегда", subtitleHint: "Как примерно 2 года подписки — без продления")
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

    private func yearlySavingsHint(yearly: Product, monthly: Product?) -> String? {
        if let intro = introHint(for: yearly) { return intro }
        guard let monthly,
              let yearPrice = priceValue(yearly),
              let monthPrice = priceValue(monthly),
              monthPrice > 0 else { return "Один платёж в год" }
        let fullYear = monthPrice * 12
        let saved = fullYear - yearPrice
        guard saved > 0 else { return "Один платёж в год" }
        let pct = Int((saved / fullYear * 100).rounded())
        return "Экономия ~\(pct)% против 12 месяцев"
    }

    private func introHint(for product: Product) -> String? {
        guard let sub = product.subscription,
              let offer = sub.introductoryOffer else { return nil }
        let price = offer.displayPrice
        switch offer.paymentMode {
        case .freeTrial:
            return "Пробный период: \(offer.periodDebugLabel)"
        case .payAsYouGo, .payUpFront:
            return "Intro: \(price) · \(offer.periodDebugLabel)"
        default:
            return "Спецпредложение: \(price)"
        }
    }

    private func priceValue(_ product: Product) -> Decimal? {
        product.price
    }

    private var redeemBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                showRedeem.toggle()
            } label: {
                Text(showRedeem ? "Скрыть промокод" : "У меня есть промокод")
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)

            if showRedeem {
                TextField("Промокод", text: $redeemCode)
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

    private func productButton(_ product: Product, badge: String?, subtitleHint: String?) -> some View {
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
                    if let subtitleHint, !subtitleHint.isEmpty {
                        Text(subtitleHint)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(appearance.accent)
                    }
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
            Text("Оплата через Apple (In-App Purchase). Это удобства клиента Читальня, не покупка книг Author.Today. Подписку можно отменить в настройках Apple ID. Семейный доступ — если включён для подписки в App Store Connect.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let url = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/") {
                Link("Условия использования Apple (EULA)", destination: url)
                    .font(.caption)
            }
        }
        .padding(.top, 8)
    }
}

private extension Product.SubscriptionOffer {
    var periodDebugLabel: String {
        let n = period.value
        switch period.unit {
        case .day: return n == 1 ? "1 день" : "\(n) дн."
        case .week: return n == 1 ? "1 неделя" : "\(n) нед."
        case .month: return n == 1 ? "1 месяц" : "\(n) мес."
        case .year: return n == 1 ? "1 год" : "\(n) г."
        @unknown default: return "спецпериод"
        }
    }
}
