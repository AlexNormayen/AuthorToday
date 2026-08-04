import SwiftUI

struct BookDetailView: View {
    let workId: Int

    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var downloads: DownloadManager
    @State private var details: WorkDetails?
    @State private var error: String?
    @State private var isLoading = true
    @State private var openReader = false
    @State private var startChapterId: Int?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Загрузка…")
            } else if let error, details == nil {
                ContentUnavailableView("Не удалось открыть", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if let details {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(alignment: .top, spacing: 16) {
                            CoverImage(urlString: details.coverUrl, corner: 10)
                                .frame(width: 120, height: 170)
                                .shadow(color: .black.opacity(0.12), radius: 10, y: 6)

                            VStack(alignment: .leading, spacing: 8) {
                                Text(details.displayTitle)
                                    .font(.system(.title2, design: .serif).weight(.semibold))
                                    .foregroundStyle(AppTheme.ink)
                                Text(details.displayAuthor)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                if let genre = details.genreName {
                                    Text([genre, details.secondGenreName].compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.moss)
                                }
                                if offline.library.contains(where: { $0.workId == workId && $0.isFullyDownloaded }) {
                                    Label("Скачано", systemImage: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.moss)
                                }
                            }
                        }

                        Button {
                            startChapterId = offline.progress(for: workId)?.chapterId
                                ?? details.availableChapters.first?.id
                            openReader = true
                        } label: {
                            Text(offline.progress(for: workId) != nil ? "Продолжить чтение" : "Читать")
                        }
                        .buttonStyle(PrimaryButtonStyle())

                        if let annotation = details.annotation, !annotation.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("О книге")
                                    .font(AppTheme.headlineFont)
                                Text(HTMLText.plain(from: annotation))
                                    .font(.body)
                                    .foregroundStyle(.primary.opacity(0.85))
                            }
                        }

                        if let chapters = details.chapters, !chapters.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Оглавление")
                                    .font(AppTheme.headlineFont)
                                ForEach(chapters.filter(\.isAvailableEffective)) { chapter in
                                    Button {
                                        startChapterId = chapter.id
                                        openReader = true
                                    } label: {
                                        HStack {
                                            Text(chapter.displayTitle)
                                                .font(.subheadline)
                                                .foregroundStyle(AppTheme.ink)
                                                .multilineTextAlignment(.leading)
                                            Spacer()
                                            if offline.isChapterCached(workId: workId, chapterId: chapter.id) {
                                                Image(systemName: "arrow.down.circle.fill")
                                                    .foregroundStyle(AppTheme.moss)
                                                    .font(.caption)
                                            }
                                        }
                                        .padding(.vertical, 6)
                                    }
                                    Divider()
                                }
                            }
                        }
                    }
                    .padding(20)
                }
                .background(AppTheme.mist.ignoresSafeArea())
            }
        }
        .navigationTitle("Книга")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $openReader) {
            ReaderView(workId: workId, initialChapterId: startChapterId)
        }
        .task {
            await load()
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            if downloads.online {
                details = try await APIClient.shared.workDetails(id: workId)
                if let details {
                    offline.upsertWork(from: details)
                }
            } else if let cached = offline.library.first(where: { $0.workId == workId }) {
                let chapters = (cached.chaptersJSON).flatMap {
                    try? JSONDecoder().decode([ChapterMeta].self, from: $0)
                } ?? []
                details = WorkDetails(
                    id: workId,
                    title: cached.title,
                    authorFIO: cached.author,
                    authorUserName: nil,
                    coverUrl: cached.coverURL,
                    annotation: cached.annotation,
                    chapters: chapters,
                    status: nil,
                    genreName: nil,
                    secondGenreName: nil,
                    likeCount: nil,
                    viewsCount: nil,
                    chapterCount: chapters.count,
                    downloadAllowed: nil,
                    isFinished: nil
                )
            } else {
                error = "Нет сети и нет локальной копии"
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
