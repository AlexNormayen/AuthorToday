import SwiftUI

struct BookDetailView: View {
    let workId: Int

    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var appearance: AppAppearanceStore
    @State private var details: WorkDetails?
    @State private var error: String?
    @State private var isLoading = true
    @State private var openReader = false
    @State private var startChapterId: Int?
    @State private var showPurchase = false

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
                                Text(details.displayAuthor)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                if let genre = details.genreName {
                                    Text([genre, details.secondGenreName].compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(appearance.accent)
                                }
                                if details.isPurchased == true {
                                    Label("Куплено", systemImage: "checkmark.seal.fill")
                                        .font(.caption)
                                        .foregroundStyle(appearance.accent)
                                } else if let price = details.displayPriceText {
                                    Text(price)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(appearance.accent)
                                }
                                if offline.library.contains(where: { $0.workId == workId && $0.isFullyDownloaded }) {
                                    Label("Скачано", systemImage: "arrow.down.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(appearance.accent)
                                }
                            }
                        }

                        if details.needsPurchase {
                            Button {
                                Task {
                                    try? await APIClient.shared.establishWebSession()
                                    showPurchase = true
                                }
                            } label: {
                                Text(details.displayPriceText.map { "Купить за \($0)" } ?? "Купить на author.today")
                            }
                            .buttonStyle(PrimaryButtonStyle())

                            Text("Оплата проходит на сайте author.today в защищённом окне. После покупки нажмите «Обновить» и откройте книгу снова.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        Button {
                            startChapterId = offline.progress(for: workId)?.chapterId
                                ?? details.availableChapters.first?.id
                            openReader = true
                        } label: {
                            Text(offline.progress(for: workId) != nil ? "Продолжить чтение" : "Читать")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .opacity(details.availableChapters.isEmpty && details.needsPurchase ? 0.45 : 1)
                        .disabled(details.availableChapters.isEmpty && details.needsPurchase)

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
                                ForEach(chapters) { chapter in
                                    Button {
                                        if chapter.isAvailableEffective {
                                            startChapterId = chapter.id
                                            openReader = true
                                        } else if details.needsPurchase {
                                            showPurchase = true
                                        }
                                    } label: {
                                        HStack {
                                            Text(chapter.displayTitle)
                                                .font(.subheadline)
                                                .foregroundStyle(chapter.isAvailableEffective ? Color.primary : .secondary)
                                                .multilineTextAlignment(.leading)
                                            Spacer()
                                            if !chapter.isAvailableEffective {
                                                Image(systemName: "lock.fill")
                                                    .foregroundStyle(.secondary)
                                                    .font(.caption)
                                            } else if offline.isChapterCached(workId: workId, chapterId: chapter.id) {
                                                Image(systemName: "arrow.down.circle.fill")
                                                    .foregroundStyle(appearance.accent)
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
                .background(Color(.systemGroupedBackground).ignoresSafeArea())
            }
        }
        .navigationTitle("Книга")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .navigationDestination(isPresented: $openReader) {
            ReaderView(workId: workId, initialChapterId: startChapterId)
        }
        .sheet(isPresented: $showPurchase, onDismiss: {
            Task { await load() }
        }) {
            if let details {
                PurchaseWebView(url: details.purchaseURL, title: "Покупка")
            }
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
                    isFinished: nil,
                    price: nil,
                    discount: nil,
                    isPurchased: nil,
                    orderStatus: nil,
                    orderStatusMessage: nil,
                    freeChapterCount: nil
                )
            } else {
                error = "Нет сети и нет локальной копии"
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
