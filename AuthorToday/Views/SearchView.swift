import SwiftUI

struct SearchView: View {
    @State private var query = ""
    @State private var authors: [AuthorSearchHit] = []
    @State private var results: [WorkMeta] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var path = NavigationPath()
    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var appearance: AppAppearanceStore

    private enum Route: Hashable {
        case work(Int)
        case author(String, String)
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if isLoading && results.isEmpty && authors.isEmpty {
                    ProgressView("Поиск…")
                } else if let error, results.isEmpty && authors.isEmpty {
                    ContentUnavailableView("Ошибка", systemImage: "wifi.exclamationmark", description: Text(error))
                } else if results.isEmpty && authors.isEmpty {
                    ContentUnavailableView(
                        "Найдите книгу или автора",
                        systemImage: "magnifyingglass",
                        description: Text(downloads.online
                            ? "Введите название или автора и нажмите поиск на клавиатуре.\nИли откройте «Свежее»."
                            : "Поиск недоступен офлайн")
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
                            Section("Произведения") {
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
            .themedGroupedFill()
            .navigationTitle("Поиск")
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .searchable(text: $query, prompt: "Название или автор")
            .onSubmit(of: .search) {
                Task { await runSearch() }
            }
            .toolbar {
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
                if results.isEmpty && authors.isEmpty && downloads.online {
                    await loadRecent()
                }
            }
        }
    }

    private func runSearch() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let bundle = try await APIClient.shared.search(query: q)
            authors = bundle.authors
            results = bundle.works
            if authors.isEmpty && results.isEmpty {
                error = "Ничего не найдено"
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadRecent() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            authors = []
            results = try await APIClient.shared.catalogRecent()
            if results.isEmpty {
                error = "Каталог пуст или недоступен"
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
