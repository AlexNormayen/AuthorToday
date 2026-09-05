import SwiftUI

struct BookVaultSettingsView: View {
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var localLibrary: LocalLibraryStore
    @EnvironmentObject private var appearance: AppAppearanceStore
    @StateObject private var settings = BookVaultSettings.shared
    @StateObject private var sync = BookVaultSync.shared
    @State private var pingResult = ""

    var body: some View {
        List {
            Section {
                Toggle("Включить облачную полку", isOn: $settings.isEnabled)
                    .onChange(of: settings.isEnabled) { _, on in
                        guard on else { return }
                        Task {
                            await sync.autoBackfillIfNeeded(store: offline, localStore: localLibrary)
                        }
                    }
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
                Text("Скачанные книги Author.Today и TXT/EPUB из «Мои книги» хранятся на VPS отдельно для каждого аккаунта. После переустановки приложения — «Восстановить с VPS».")
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

                Button("Выгрузить всё локальное") {
                    Task {
                        _ = localLibrary.importNewFilesFromDocuments()
                        await sync.pushAllDownloaded(store: offline, localStore: localLibrary)
                    }
                }
                .disabled(!settings.isEnabled || sync.isSyncing)

                Button("Восстановить с VPS") {
                    Task { await sync.pullAndRestore(store: offline, localStore: localLibrary) }
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
                LabeledContent("Скачано AT", value: "\(offline.downloadedWorks.count)")
                LabeledContent("Мои книги", value: "\(localLibrary.books.count)")
            }

            Section {
                Text("Удаление в «Мои книги» снимает файл с устройства и с VPS. Удаление в «Скачанные» убирает только офлайн-копию, не библиотеку Author.Today.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Облачная полка")
        .navigationBarTitleDisplayMode(.inline)
        .themedGroupedFill()
        .task {
            guard settings.isEnabled else { return }
            await sync.autoBackfillIfNeeded(store: offline, localStore: localLibrary)
        }
    }
}
