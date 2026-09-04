import SwiftUI

struct BookVaultSettingsView: View {
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var appearance: AppAppearanceStore
    @StateObject private var settings = BookVaultSettings.shared
    @StateObject private var sync = BookVaultSync.shared
    @State private var pingResult = ""

    var body: some View {
        List {
            Section {
                Toggle("Включить облачную полку", isOn: $settings.isEnabled)
                TextField("URL сервера", text: $settings.baseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.footnote.monospaced())
                SecureField("Токен", text: $settings.apiToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.footnote.monospaced())
            } header: {
                Text("Подключение")
            } footer: {
                Text("Книги хранятся на вашем VPS отдельно для каждого аккаунта Author.Today. После скачивания главы уходят в облако; другой телефон может восстановить их и прогресс.")
            }

            Section("Синхронизация") {
                if sync.isSyncing {
                    HStack {
                        ProgressView()
                        Text(sync.statusText.isEmpty ? "Синхронизация…" : sync.statusText)
                            .font(.subheadline)
                    }
                }
                Button("Проверить связь") {
                    Task {
                        pingResult = await sync.ping()
                    }
                }
                .disabled(!settings.isEnabled || sync.isSyncing)

                Button("Выгрузить скачанное") {
                    Task { await sync.pushAllDownloaded(store: offline) }
                }
                .disabled(!settings.isEnabled || sync.isSyncing || offline.downloadedWorks.isEmpty)

                Button("Восстановить с VPS") {
                    Task { await sync.pullAndRestore(store: offline) }
                }
                .disabled(!settings.isEnabled || sync.isSyncing)

                if !pingResult.isEmpty {
                    Text(pingResult)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !settings.lastStatus.isEmpty {
                    LabeledContent("Статус", value: settings.lastStatus)
                        .font(.caption)
                }
                if let at = settings.lastSyncAt {
                    LabeledContent("Последний синк", value: at.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                }
                LabeledContent("Скачано локально", value: "\(offline.downloadedWorks.count)")
            }

            Section {
                Text("Личная полка, не зеркало Author.Today. TXT/EPUB из «Мои книги» не синкаются.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Облачная полка")
        .navigationBarTitleDisplayMode(.inline)
        .themedGroupedFill()
    }
}
