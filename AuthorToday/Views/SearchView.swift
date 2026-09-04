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

    private enum Route: Hashable {
        case work(Int)
        case author(String, String)
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
                    ContentUnavailableView("Ошибка", systemImage: "wifi.exclamationmark", description: Text(error))
                } else if results.isEmpty && authors.isEmpty {
                    ContentUnavailableView(
                        emptyTitle,
                        systemImage: "magnifyingglass",
                        description: Text(emptyDescription)
                    )
                } else {
                    List {
                        if !authors.isEmpty {
                            Section("Авторы") {
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
                                                    .foregroundStyle(.primary)
                                                Text("@\(author.userName)")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    .listRowBackground(Color.clear)
                                }
                            }
                        }

                        if !results.isEmpty {
                            Section(showingRecent ? "Свежее" : "Произведения") {
                                ForEach(results) { work in
                                    Button {
                                        path.append(Route.work(work.id))
                                    } label: {
                                        HStack(spacing: 12) {
                                            CoverImage(urlString: work.absoluteCoverURL)
                                                .frame(width: 48, height: 68)
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(work.displayTitle)
                                                    .font(.system(.body, design: .serif).weight(.medium))
                                                    .foregroundStyle(.primary)
                                                    .multilineTextAlignment(.leading)
                                                Text(work.displayAuthor)
                                                    .font(.subheadline)
                                                    .foregroundStyle(.secondary)
                                                HStack(spacing: 8) {
                                                    if let price = work.displayPriceText {
                                                        Text(price)
                                                            .font(.caption.weight(.semibold))
                                                            .foregroundStyle(Color.accentColor)
                                                    }
                                                    if work.isInLibrary {
                                                        Text("В библиотеке")
                                                            .font(.caption2)
                                                            .foregroundStyle(.secondary)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    .listRowBackground(Color.clear)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .themedScreenChrome()
            .background {
                ThemeAtmosphereView(preset: appearance.themePreset)
            }
            .navigationTitle("Поиск")
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                Picker("Режим", selection: $mode) {
                    ForEach(CatalogSearchMode.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
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
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Свежее") {
                        Task { await loadRecent() }
                    }
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
            if authors.isEmpty && results.isEmpty {
                error = "Ничего не найдено"
            }
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
