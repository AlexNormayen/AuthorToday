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

    private var isOwner: Bool {
        ProFeatures.isOwnerAccount(
            email: auth.user?.email,
            userName: auth.user?.resolvedUserName ?? auth.resolvedUserName
        )
    }

    /// Snapshot value arrays so ForEach cannot pick the Binding overload.
    private var issuedSnapshot: [ProGrantStore.IssuedCode] {
        Array(grantStore.issuedCodes.prefix(20))
    }

    private var grantsSnapshot: [ProGrantStore.Grant] {
        Array(grantStore.grants)
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
                Text("Внутренняя выдача промокодов (не СБП). Для продаж используйте App Store IAP.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(ProGrantStore.Plan.allCases) { plan in
                    Button {
                        let code = grantStore.generateAccessCode(plan: plan)
                        lastGenerated = code
                        UIPasteboard.general.string = code
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

            if !issuedSnapshot.isEmpty {
                Section("Недавно созданные") {
                    ForEach(issuedSnapshot, id: \ProGrantStore.IssuedCode.id) { item in
                        IssuedCodeRow(item: item)
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
                if grantsSnapshot.isEmpty {
                    Text("Пока никого нет").foregroundStyle(.secondary)
                } else {
                    ForEach(grantsSnapshot, id: \ProGrantStore.Grant.id) { item in
                        GrantRow(
                            item: item,
                            onRevoke: {
                                grantStore.revoke(item.email)
                                pro.refreshComplimentaryFromGrants()
                            }
                        )
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
}

private struct IssuedCodeRow: View {
    let item: ProGrantStore.IssuedCode

    var body: some View {
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

private struct GrantRow: View {
    let item: ProGrantStore.Grant
    let onRevoke: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.email)
                .font(.body.weight(.medium))
            Text(item.isActive ? expiryLabel(item.expiresAt) : "Истёк")
                .font(.caption)
                .foregroundStyle(item.isActive ? Color.secondary : Color.red)
        }
        .swipeActions {
            Button(role: .destructive, action: onRevoke) {
                Label("Отозвать", systemImage: "trash")
            }
        }
    }

    private func expiryLabel(_ date: Date?) -> String {
        guard let date else { return "Бессрочно" }
        return "До \(date.formatted(date: .abbreviated, time: .omitted))"
    }
}
