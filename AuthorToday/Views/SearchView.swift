import SwiftUI

struct SearchView: View {
    @State private var query = ""
    @State private var results: [WorkMeta] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var path = NavigationPath()
    @EnvironmentObject private var downloads: DownloadManager

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if isLoading && results.isEmpty {
                    ProgressView("Поиск…")
                } else if let error, results.isEmpty {
                    ContentUnavailableView("Ошибка", systemImage: "wifi.exclamationmark", description: Text(error))
                } else if results.isEmpty {
                    ContentUnavailableView(
                        "Найдите книгу",
                        systemImage: "magnifyingglass",
                        description: Text(downloads.online
                            ? "Введите название или откройте свежие обновления"
                            : "Поиск недоступен офлайн")
                    )
                } else {
                    List(results) { work in
                        Button {
                            path.append(work.id)
                        } label: {
                            HStack(spacing: 12) {
                                CoverImage(urlString: work.coverUrl)
                                    .frame(width: 48, height: 68)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(work.displayTitle)
                                        .font(.system(.body, design: .serif).weight(.medium))
                                        .foregroundStyle(AppTheme.ink)
                                        .multilineTextAlignment(.leading)
                                    Text(work.displayAuthor)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .background(AppTheme.mist.ignoresSafeArea())
            .navigationTitle("Поиск")
            .searchable(text: $query, prompt: "Название книги")
            .onSubmit(of: .search) {
                Task { await runSearch() }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Свежее") {
                        Task { await loadRecent() }
                    }
                    .disabled(!downloads.online)
                }
            }
            .navigationDestination(for: Int.self) { workId in
                BookDetailView(workId: workId)
            }
            .task {
                if results.isEmpty && downloads.online {
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
            let page = try await APIClient.shared.search(query: q)
            results = page.items
            if results.isEmpty {
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
            let page = try await APIClient.shared.catalogRecent()
            results = page.items
        } catch {
            self.error = error.localizedDescription
        }
    }
}
