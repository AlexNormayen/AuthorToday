import SwiftUI

struct BookVaultSettingsView: View {
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var localLibrary: LocalLibraryStore
    @EnvironmentObject private var appearance: AppAppearanceStore
    @StateObject private var settings = BookVaultSettings.shared
    @StateObject private var sync = BookVaultSync.shared
    @State private var pingResult = ""

    private var syncBlockedReason: String? {
        if !settings.isEnabled { return "Сначала включите облачную полку." }
        if !settings.hasToken { return "Укажите токен — без него сервер не отдаст сохранённые книги." }
        return nil
    }

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
                if settings.isEnabled, !settings.hasToken {
                    Button("Подставить токен Читальни") {
                        settings.applySharedShelfToken()
                    }
                    .themedPanelRow()
                    Text("Без токена восстановление с VPS не работает. Токен нужен один раз; данные уходят на сервер разработчика Читальни.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .themedPanelRow()
                }
            } header: {
                Text("Подключение").themedSectionChrome()
            } footer: {
                Text(
                    ChitalnyaDistribution.isAppStore
                        ? "По умолчанию выключено. Включая полку, вы соглашаетесь отправлять скачанные книги, прогресс и закладки на сервер разработчика Читальни (HTTPS). В App Store-сборке токен не подставляется сам — нажмите «Подставить токен Читальни» или вставьте свой."
                        : "Скачанные книги Author.Today и TXT/EPUB из «Мои книги» хранятся на VPS отдельно для каждого аккаунта. После переустановки приложения — «Восстановить с VPS»."
                )
                .themedFooterNote()
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
                if let reason = syncBlockedReason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .themedPanelRow()
                }
                Button("Проверить связь") {
                    Task {
                        pingResult = await sync.ping()
                    }
                }
                .disabled(!settings.canSync || sync.isSyncing)
                .themedPanelRow()

                Button("Выгрузить всё локальное") {
                    Task {
                        _ = localLibrary.importNewFilesFromDocuments()
                        await sync.pushAllDownloaded(store: offline, localStore: localLibrary)
                    }
                }
                .disabled(!settings.canSync || sync.isSyncing)
                .themedPanelRow()

                Button("Восстановить с VPS") {
                    Task { await sync.pullAndRestore(store: offline, localStore: localLibrary) }
                }
                .disabled(!settings.canSync || sync.isSyncing)
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
            } footer: {
                Text("«Скачано AT» — офлайн-копии книг Author.Today. «Мои книги» — свои TXT/EPUB. Восстановление поднимает оба типа с VPS.")
                    .themedFooterNote()
            }

            Section {
                Text("Удаление в «Мои книги» снимает файл с устройства и с VPS. Удаление в «Скачанные» убирает только офлайн-копию, не библиотеку Author.Today.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .themedPanelRow()
            }
        }
        .themedAtmosphereList()
        .environment(\.themePreset, appearance.themePreset)
        .environment(\.themeAccent, appearance.accent)
        .preferredColorScheme(appearance.preferredColorScheme)
        .navigationTitle("Облачная полка")
        .navigationBarTitleDisplayMode(.inline)
        .themedScreenChrome()
        .background {
            ThemeAtmosphereView(preset: appearance.themePreset)
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            guard settings.canSync else { return }
            await sync.autoBackfillIfNeeded(store: offline, localStore: localLibrary)
        }
    }
}
