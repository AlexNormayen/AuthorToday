import SwiftUI
import UIKit

/// Temporary owner-only screen to grant Pro (sideload / friends). Hide before App Store if needed.
struct ProGrantsAdminView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var pro: ProEntitlementStore
    @EnvironmentObject private var appearance: AppAppearanceStore
    @ObservedObject private var grantStore = ProGrantStore.shared

    @State private var rawIdentity = ""
    @State private var daysText = "30"
    @State private var note = ""
    @State private var formError: String?
    @State private var lastGenerated: String?
    @State private var copiedCode: String?

    private var isOwner: Bool {
        ProFeatures.isOwnerAccount(
            email: auth.user?.email,
            userName: auth.user?.resolvedUserName ?? auth.resolvedUserName
        )
    }

    var body: some View {
        Group {
            if isOwner {
                adminContent
            } else {
                ContentUnavailableView(
                    "Нет доступа",
                    systemImage: "lock.fill",
                    description: Text("Раздел только для владельца приложения.")
                )
            }
        }
        .navigationTitle("Pro-доступы")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var adminContent: some View {
        List {
            Section {
                Text("Оплата: СБП \(ProFeatures.ManualPayment.phoneDisplay), \(ProFeatures.ManualPayment.bank). После перевода сгенерируйте код и отправьте в Max/Telegram.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(ProGrantStore.Plan.allCases) { plan in
                    Button {
                        let code = grantStore.generateAccessCode(plan: plan)
                        lastGenerated = code
                        UIPasteboard.general.string = code
                        copiedCode = code
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(plan.title).font(.body.weight(.semibold))
                                Text(plan.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(plan.priceLabel)
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                            Text("Код")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(appearance.accent)
                        }
                    }
                }
                if let lastGenerated {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Последний код (скопирован):")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(lastGenerated)
                            .font(.body.monospaced().weight(.semibold))
                            .textSelection(.enabled)
                        Button("Скопировать снова") {
                            UIPasteboard.general.string = lastGenerated
                            copiedCode = lastGenerated
                        }
                        .font(.caption)
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Сгенерировать код после оплаты")
            } footer: {
                Text("Код одноразовый на устройстве друга. Срок Pro считается с момента активации.")
            }

            if !grantStore.issuedCodes.isEmpty {
                Section("Недавно созданные") {
                    ForEach(Array(grantStore.issuedCodes.prefix(20)), id: \.id) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.code)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                            Text("\(item.days) дн. · \(item.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button {
                                UIPasteboard.general.string = item.code
                            } label: {
                                Label("Копия", systemImage: "doc.on.doc")
                            }
                        }
                    }
                }
            }

            Section {
                TextField("Email или username", text: $rawIdentity)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                TextField("Срок (дней), пусто = бессрочно", text: $daysText)
                    .keyboardType(.numberPad)
                TextField("Заметка", text: $note)
                if let formError {
                    Text(formError).font(.caption).foregroundStyle(.red)
                }
                Button("Выдать Pro на этом устройстве") { addGrant() }
                    .disabled(rawIdentity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: {
                Text("Выдать по email (только этот iPhone)")
            }

            Section {
                if grantStore.grants.isEmpty {
                    Text("Пока никого нет").foregroundStyle(.secondary)
                } else {
                    ForEach(grantStore.grants, id: \.id) { grant in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(grant.email).font(.body.weight(.medium))
                            Text(grant.isActive ? expiryLabel(grant.expiresAt) : "Истёк")
                                .font(.caption)
                                .foregroundStyle(grant.isActive ? .secondary : .red)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                grantStore.revoke(grant.email)
                                pro.refreshComplimentaryFromGrants()
                            } label: {
                                Label("Отозвать", systemImage: "trash")
                            }
                        }
                    }
                }
            } header: {
                Text("Гранты на этом устройстве")
            }
        }
        .themedScreenChrome()
        .background {
            ThemeAtmosphereView(preset: appearance.themePreset)
        }
    }

    private func addGrant() {
        let days = Int(daysText.trimmingCharacters(in: .whitespacesAndNewlines))
        if let err = grantStore.grant(raw: rawIdentity, days: days, note: note) {
            formError = err
            return
        }
        formError = nil
        rawIdentity = ""
        note = ""
        pro.refreshComplimentaryFromGrants()
    }

    private func expiryLabel(_ date: Date?) -> String {
        guard let date else { return "Бессрочно" }
        return "До \(date.formatted(date: .abbreviated, time: .omitted))"
    }
}
