import SwiftUI

struct SearchView: View {
    var initialQuery: String = ""
    /// Shown when opened from Library as a sheet (iPhone).
    var showsDismissButton: Bool = false

    @State private var query = ""
    @State private var mode: CatalogSearchMode = .both
    @State private var authors: [AuthorSearchHit] = []
    @State private var results: [WorkMeta] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var path = NavigationPath()
    @State private var showingRecent = false
    @State private var didApplyInitialQuery = false
    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var appearance: AppAppearanceStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private enum Route: Hashable {
        case work(Int)
        case author(String, String)
    }

    private var primaryInk: Color {
        appearance.themePreset.chromePrimaryText(colorScheme: colorScheme)
    }

    private var secondaryInk: Color {
        appearance.themePreset.chromeSecondaryText(accent: appearance.accent, colorScheme: colorScheme)
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if isLoading && results.isEmpty && authors.isEmpty {
                    LoadingStateView(
                        title: "Поиск…",
                        subtitle: downloads.online ? mode.title : "Нет сети"
                    )
                } else if let error, results.isEmpty && authors.isEmpty {
                    ThemedEmptyStateView(
                        title: "Ошибка",
                        systemImage: "wifi.exclamationmark",
                        description: error
                    )
                } else if results.isEmpty && authors.isEmpty {
                    ThemedEmptyStateView(
                        title: emptyTitle,
                        systemImage: "magnifyingglass",
                        description: emptyDescription
                    )
                } else {
                    List {
                        if !authors.isEmpty {
                            Section {
                                ForEach(authors) { author in
                                    Button {
                                        path.append(Route.author(author.userName, author.displayName))
                                    } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: "person.crop.circle.fill")
                                                .font(.system(size: 36))
                                                .foregroundStyle(appearance.accent)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(author.displayName)
                                                    .font(.body.weight(.semibold))
                                                    .foregroundStyle(primaryInk)
                                                    .themedReadableText()
                                                Text("@\(author.userName)")
                                                    .font(.caption.weight(.medium))
                                                    .foregroundStyle(secondaryInk)
                                                    .themedReadableText()
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(secondaryInk.opacity(0.7))
                                        }
                                    }
                                    .themedPanelRow()
                                }
                            } header: {
                                Text("Авторы").themedSectionChrome()
                            }
                        }

                        if !results.isEmpty {
                            Section {
                                ForEach(results) { work in
                                    Button {
                                        path.append(Route.work(work.id))
                                    } label: {
                                        HStack(spacing: 12) {
                                            CoverImage(urlString: work.absoluteCoverURL)
                                                .frame(width: 48, height: 68)
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(work.displayTitle)
                                                    .font(.system(.body, design: .serif).weight(.semibold))
                                                    .foregroundStyle(primaryInk)
                                                    .multilineTextAlignment(.leading)
                                                    .themedReadableText()
                                                Text(work.displayAuthor)
                                                    .font(.subheadline.weight(.medium))
                                                    .foregroundStyle(secondaryInk)
                                                    .themedReadableText()
                                                HStack(spacing: 8) {
                                                    if let price = work.displayPriceText {
                                                        Text(price)
                                                            .font(.caption.weight(.semibold))
                                                            .foregroundStyle(secondaryInk)
                                                            .themedReadableText()
                                                    }
                                                    if work.isInLibrary {
                                                        Text("В библиотеке")
                                                            .font(.caption2.weight(.semibold))
                                                            .foregroundStyle(appearance.accent)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    .themedPanelRow()
                                }
                            } header: {
                                Text(showingRecent ? "Свежее" : "Произведения").themedSectionChrome()
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .environment(\.themePreset, appearance.themePreset)
            .environment(\.themeAccent, appearance.accent)
            .themedScreenChrome()
            .background {
                ThemeAtmosphereView(preset: appearance.themePreset)
            }
            .navigationTitle("Поиск")
            .toolbarBackground(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                Picker("Режим", selection: $mode) {
                    ForEach(CatalogSearchMode.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.clear)
            }
            .searchable(text: $query, prompt: mode.prompt)
            .onSubmit(of: .search) {
                Task { await runSearch() }
            }
            .onChange(of: mode) { _, _ in
                let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !q.isEmpty else { return }
                Task { await runSearch() }
            }
            .toolbar {
                if showsDismissButton {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Закрыть") { dismiss() }
                            .foregroundStyle(primaryInk)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Свежее") {
                        Task { await loadRecent() }
                    }
                    .foregroundStyle(primaryInk)
                    .disabled(!downloads.online || isLoading)
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .work(let workId):
                    BookDetailView(workId: workId)
                case .author(let userName, let displayName):
                    AuthorProfileView(userName: userName, displayNameHint: displayName)
                }
            }
            .task {
                if !didApplyInitialQuery {
                    didApplyInitialQuery = true
                    let seed = initialQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !seed.isEmpty {
                        query = seed
                        await runSearch()
                        return
                    }
                }
                if results.isEmpty && authors.isEmpty && downloads.online {
                    await loadRecent()
                }
            }
        }
        // Sheets often ignore the app-level scheme — force chrome to match theme mode.
        .preferredColorScheme(appearance.preferredColorScheme)
        .tint(appearance.accent)
    }

    private var emptyTitle: String {
        switch mode {
        case .title: return "Найдите книгу"
        case .author: return "Найдите автора"
        case .both: return "Найдите книгу или автора"
        }
    }

    private var emptyDescription: String {
        if !downloads.online {
            return "Поиск недоступен офлайн"
        }
        switch mode {
        case .title:
            return "Режим «Название» — только произведения, по популярности.\nИли откройте «Свежее»."
        case .author:
            return "Режим «Автор» — только авторы, по рейтингу на сайте.\nИли откройте «Свежее»."
        case .both:
            return "Режим «Всё» — авторы и книги, по популярности.\nИли откройте «Свежее»."
        }
    }

    private func runSearch() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        guard downloads.online else {
            error = "Поиск недоступен офлайн"
            authors = []
            results = []
            showingRecent = false
            return
        }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let bundle = try await APIClient.shared.search(query: q, mode: mode)
            authors = bundle.authors
            results = bundle.works
            showingRecent = false
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadRecent() async {
        guard downloads.online else {
            error = "Каталог недоступен офлайн"
            return
        }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            authors = []
            results = try await APIClient.shared.catalogRecent()
            showingRecent = true
            if results.isEmpty {
                error = "Каталог пуст или недоступен"
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
