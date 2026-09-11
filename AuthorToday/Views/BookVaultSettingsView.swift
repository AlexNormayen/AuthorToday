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
                    .themedPanelRow()
                TextField("URL сервера", text: $settings.baseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.footnote.monospaced())
                    .themedPanelRow()
                SecureField("Токен", text: $settings.apiToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.footnote.monospaced())
                    .themedPanelRow()
            } header: {
                Text("Подключение").themedSectionChrome()
            } footer: {
                Text(
                    ChitalnyaDistribution.isAppStore
                        ? "По умолчанию выключено. Включая полку, вы соглашаетесь отправлять скачанные книги, прогресс и закладки на сервер разработчика Читальни (HTTPS). Токен выдаёт разработчик — в App Store-сборке он не зашит в приложение."
                        : "Скачанные книги Author.Today и TXT/EPUB из «Мои книги» хранятся на VPS отдельно для каждого аккаунта. После переустановки приложения — «Восстановить с VPS»."
                )
                .themedSectionChrome()
            }

            Section {
                if sync.isSyncing {
                    HStack {
                        ProgressView()
                        Text(sync.statusText.isEmpty ? "Синхронизация…" : sync.statusText)
                            .font(.subheadline)
                    }
                    .themedPanelRow()
                }
                Button("Проверить связь") {
                    Task {
                        pingResult = await sync.ping()
                    }
                }
                .disabled(!settings.isEnabled || sync.isSyncing)
                .themedPanelRow()

                Button("Выгрузить всё локальное") {
                    Task {
                        _ = localLibrary.importNewFilesFromDocuments()
                        await sync.pushAllDownloaded(store: offline, localStore: localLibrary)
                    }
                }
                .disabled(!settings.isEnabled || sync.isSyncing)
                .themedPanelRow()

                Button("Восстановить с VPS") {
                    Task { await sync.pullAndRestore(store: offline, localStore: localLibrary) }
                }
                .disabled(!settings.isEnabled || sync.isSyncing)
                .themedPanelRow()

                if !pingResult.isEmpty {
                    Text(pingResult)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .themedPanelRow()
                }
                if !settings.lastStatus.isEmpty {
                    LabeledContent("Статус", value: settings.lastStatus)
                        .font(.caption)
                        .themedPanelRow()
                }
                if let at = settings.lastSyncAt {
                    LabeledContent("Последний синк", value: at.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .themedPanelRow()
                }
                LabeledContent("Скачано AT", value: "\(offline.downloadedWorks.count)")
                    .themedPanelRow()
                LabeledContent("Мои книги", value: "\(localLibrary.books.count)")
                    .themedPanelRow()
            } header: {
                Text("Синхронизация").themedSectionChrome()
            }

            Section {
                Text("Удаление в «Мои книги» снимает файл с устройства и с VPS. Удаление в «Скачанные» убирает только офлайн-копию, не библиотеку Author.Today.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .themedPanelRow()
            }
        }
        .listStyle(.plain)
        .environment(\.themePreset, appearance.themePreset)
        .environment(\.themeAccent, appearance.accent)
        .navigationTitle("Облачная полка")
        .navigationBarTitleDisplayMode(.inline)
        .themedScreenChrome()
        .background {
            ThemeAtmosphereView(preset: appearance.themePreset)
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            guard settings.isEnabled else { return }
            await sync.autoBackfillIfNeeded(store: offline, localStore: localLibrary)
        }
    }
}
