import SwiftUI
import StoreKit

struct ProPaywallView: View {
    @EnvironmentObject private var pro: ProEntitlementStore
    @EnvironmentObject private var appearance: AppAppearanceStore
    @EnvironmentObject private var offline: OfflineStore
    @Environment(\.dismiss) private var dismiss

    var reason: String?

#if DEBUG
    @State private var showRedeem = false
    @State private var redeemCode = ""
    @State private var redeemMessage: String?
#endif

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if ChitalnyaDistribution.hidesProMarketing {
                        appStoreDocsSheet
                    } else {
                        commerceSheet
                    }
                }
                .padding(20)
            }
            .background {
                ThemeAtmosphereView(preset: appearance.themePreset)
            }
            .navigationTitle(ChitalnyaDistribution.hidesProMarketing ? "Возможности" : "Читальня Pro")
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

    /// App Store: no Pro branding, no checkout — documentation on author.today only.
    private var appStoreDocsSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(pro.isProUnlocked ? "Расширенные возможности активны" : "Дополнительные возможности")
                .font(.title2.weight(.semibold))
            Text("У Читальни есть расширенная конфигурация клиента (темы, офлайн, закладки, свои файлы). Описание возможностей и как ими пользоваться — в документации на author.today.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let reason, !reason.isEmpty, !pro.isProUnlocked {
                Text(sanitizedAppStoreReason(reason))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Link(destination: ChitalnyaDistribution.authorTodayDocumentationURL) {
                Label("Документация на author.today", systemImage: "doc.text")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(.white)
                    .background(appearance.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            if ChitalnyaDistribution.allowsWebPurchasedPro, !pro.isProUnlocked {
                Button {
                    Task { await pro.refreshWebEntitlement() }
                } label: {
                    Label("Обновить статус", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.medium))
                }
            }
            Text("Книги и оплата контента Author.Today — только на author.today.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func sanitizedAppStoreReason(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "Читальня Pro", with: "расширенной конфигурации")
            .replacingOccurrences(of: "Читальни Pro", with: "расширенной конфигурации")
            .replacingOccurrences(of: "Pro снимает ограничение.", with: "В расширенной конфигурации лимит снимается.")
            .replacingOccurrences(of: "в Читальня Pro.", with: "в расширенной конфигурации.")
            .replacingOccurrences(of: "в Читальне Pro.", with: "в расширенной конфигурации.")
            .replacingOccurrences(of: "— удобство Читальни Pro.", with: "доступны в расширенной конфигурации.")
            .replacingOccurrences(of: "нужен Читальня Pro", with: "нужна расширенная конфигурация")
            .replacingOccurrences(of: "Досрочно — в Читальня Pro.", with: "Досрочно — в расширенной конфигурации.")
    }

    private var commerceSheet: some View {
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
                if ChitalnyaDistribution.offersInAppPurchases {
                    storeProducts
                } else if ChitalnyaDistribution.showsProCommerce {
                    webCheckoutNotice
                }
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
            redeemBlock
#endif
            legal
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
            } else if pro.isWebPurchasedPro {
                Label("Pro активен для аккаунта", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(appearance.accent)
            } else if pro.isProUnlocked {
                Label("Спасибо за поддержку", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(appearance.accent)
            }
            Text("Главное — скачивать книги и читать офлайн. Pro снимает лимит офлайна и открывает темы, закладки и «Мои книги». Книги Author.Today — только на author.today.")
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

    private var webCheckoutNotice: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Покупка Pro на сайте")
                .font(.headline)
            Text("Оплата удобств клиента — на сайте Читальни (не покупка книг Author.Today). После оплаты войдите тем же аккаунтом — Pro подтянется автоматически.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Link(destination: ProWebEntitlementClient.purchasePageURL) {
                Text("Оформить на сайте")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(.white)
                    .background(appearance.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            Button {
                Task { await pro.refreshWebEntitlement() }
            } label: {
                Label("Проверить оплату", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.medium))
            }
            .disabled(pro.isPurchasing)
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
                Text("Тарифы появятся после публикации продуктов в App Store Connect. Можно восстановить уже купленные.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

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
            if let weekly = pro.weeklyProduct {
                productButton(weekly, badge: nil, subtitleHint: introHint(for: weekly))
            }

            Button {
                Task { await pro.restore() }
            } label: {
                Text("Восстановить покупки")
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
        }
    }

#if DEBUG
    private var redeemBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button("Промокод / DEBUG redeem") { showRedeem.toggle() }
                .font(.footnote)
            if showRedeem {
                TextField("Промокод", text: $redeemCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button("Активировать") { redeem() }
                if let redeemMessage {
                    Text(redeemMessage)
                        .font(.caption)
                        .foregroundStyle(
                            redeemMessage.localizedCaseInsensitiveContains("актив")
                                ? AnyShapeStyle(appearance.accent)
                                : AnyShapeStyle(.secondary)
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
        if let g = ProGrantStore.shared.grants.first(where: {
            ProFeatures.normalize($0.email) == ProFeatures.normalize(auth.user?.email ?? loginEmail)
                || ProFeatures.normalize($0.email) == ProFeatures.normalize(auth.user?.resolvedUserName ?? auth.resolvedUserName)
        }) {
            if let exp = g.expiresAt {
                redeemMessage = "Pro до \(exp.formatted(date: .abbreviated, time: .omitted))"
            } else {
                redeemMessage = "Pro активирован"
            }
            redeemCode = ""
        } else {
            redeemMessage = "Код принят. Если Pro не включился — перезайдите в аккаунт."
        }
    }
#endif

    private func introHint(for product: Product) -> String? {
        guard let sub = product.subscription,
              let offer = sub.introductoryOffer else { return nil }
        return "Intro: \(offer.periodDebugLabel)"
    }

    private func yearlySavingsHint(yearly: Product, monthly: Product?) -> String? {
        guard let monthly else { return introHint(for: yearly) }
        let y = NSDecimalNumber(decimal: yearly.price).doubleValue
        let m = NSDecimalNumber(decimal: monthly.price).doubleValue
        guard m > 0 else { return introHint(for: yearly) }
        let save = Int((((m * 12) - y) / (m * 12) * 100).rounded())
        if save > 0 { return "≈ −\(save)% к 12×месяц" }
        return introHint(for: yearly)
    }

    private func productButton(_ product: Product, badge: String?, subtitleHint: String?) -> some View {
        Button {
            Task { _ = await pro.purchase(product) }
        } label: {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
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
            if ChitalnyaDistribution.offersInAppPurchases {
                Text("Оплата через Apple (In-App Purchase). Это удобства клиента Читальня, не покупка книг Author.Today. Подписку можно отменить в настройках Apple ID. Семейный доступ — если включён для подписки в App Store Connect.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Pro — удобства клиента Читальня (темы, офлайн-лимит, TXT/EPUB). Оплата Pro — на сайте Читальни. Книги Author.Today — только на author.today.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if ChitalnyaDistribution.offersInAppPurchases,
               let url = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/") {
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
