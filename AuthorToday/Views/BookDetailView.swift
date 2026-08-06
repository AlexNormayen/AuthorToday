import SwiftUI

struct BookDetailView: View {
    let workId: Int

    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var appearance: AppAppearanceStore
    @EnvironmentObject private var auth: AuthService

    @State private var details: WorkDetails?
    @State private var error: String?
    @State private var isLoading = true
    @State private var openReader = false
    @State private var startChapterId: Int?
    @State private var showPurchase = false
    @State private var showTOC = false
    @State private var openAuthorProfile = false

    @State private var comments: [WorkComment] = []
    @State private var commentsLoading = false
    @State private var commentsError: String?
    @State private var commentsPage = 1
    @State private var commentsHasMore = false
    @State private var draftText = ""
    @State private var replyTo: WorkComment?
    @State private var isSendingComment = false

    private var resolvedAuthorUserName: String? {
        if let name = details?.authorUserName, !name.isEmpty { return name }
        if let name = offline.cachedWork(workId: workId)?.authorUserName, !name.isEmpty { return name }
        return nil
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Загрузка…")
            } else if let error, details == nil {
                ContentUnavailableView(
                    "Не удалось открыть",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else if let details {
                detailScroll(details)
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
        .navigationDestination(isPresented: $openAuthorProfile) {
            authorDestination
        }
        .sheet(isPresented: $showPurchase, onDismiss: {
            Task { await load() }
        }) {
            purchaseSheet
        }
        .sheet(isPresented: $showTOC) {
            BookTOCSheet(
                workId: workId,
                chapters: details?.chapters ?? [],
                needsPurchase: details?.needsPurchase == true,
                onOpen: { id in
                    showTOC = false
                    startChapterId = id
                    openReader = true
                },
                onPurchase: {
                    showTOC = false
                    showPurchase = true
                },
                onClose: { showTOC = false }
            )
            .environmentObject(offline)
            .environmentObject(appearance)
        }
        .task {
            await load()
            await loadComments(reset: true)
        }
    }

    @ViewBuilder
    private var authorDestination: some View {
        if let userName = resolvedAuthorUserName {
            AuthorProfileView(userName: userName, displayNameHint: details?.displayAuthor)
        } else {
            ContentUnavailableView(
                "Нет профиля",
                systemImage: "person.crop.circle.badge.questionmark",
                description: Text("У этой книги нет ссылки на автора.")
            )
        }
    }

    @ViewBuilder
    private var purchaseSheet: some View {
        if let details {
            PurchaseWebView(url: details.purchaseURL, title: "Покупка")
        } else {
            ProgressView()
        }
    }

    private func detailScroll(_ details: WorkDetails) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(details)
                actions(details)
                if let annotation = details.annotation, !annotation.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("О книге")
                            .font(AppTheme.headlineFont)
                        Text(HTMLText.plain(from: annotation))
                            .font(.body)
                            .foregroundStyle(.primary.opacity(0.85))
                    }
                }
                commentsBlock
            }
            .padding(20)
        }
        .themedGroupedFill()
    }

    private func header(_ details: WorkDetails) -> some View {
        HStack(alignment: .top, spacing: 16) {
            CoverImage(urlString: details.coverUrl, corner: 10)
                .frame(width: 120, height: 170)
                .shadow(color: .black.opacity(0.12), radius: 10, y: 6)

            VStack(alignment: .leading, spacing: 8) {
                Text(details.displayTitle)
                    .font(.system(.title2, design: .serif).weight(.semibold))

                Button {
                    openAuthorProfile = true
                } label: {
                    HStack(spacing: 4) {
                        Text(details.displayAuthor)
                        if resolvedAuthorUserName != nil {
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(resolvedAuthorUserName != nil ? appearance.accent : Color.secondary)
                }
                .disabled(resolvedAuthorUserName == nil)

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
    }

    private func actions(_ details: WorkDetails) -> some View {
        VStack(alignment: .leading, spacing: 12) {
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
                    ?? offline.library.first(where: { $0.workId == workId })?.lastReadChapterId
                    ?? details.availableChapters.first?.id
                openReader = true
            } label: {
                Text(readButtonTitle)
            }
            .buttonStyle(PrimaryButtonStyle())
            .opacity(details.availableChapters.isEmpty && details.needsPurchase ? 0.45 : 1)
            .disabled(details.availableChapters.isEmpty && details.needsPurchase)

            if let chapters = details.chapters, !chapters.isEmpty {
                Button {
                    showTOC = true
                } label: {
                    Label("Оглавление (\(chapters.count))", systemImage: "list.bullet")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            if offline.library.contains(where: { $0.workId == workId }) {
                Text("В вашей библиотеке")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    Task {
                        do {
                            try await offline.addToSiteLibrary(workId: workId, state: "Reading")
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                } label: {
                    Label("В библиотеку", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            if downloads.online, !details.availableChapters.isEmpty {
                downloadBlock(details)
            }
        }
    }

    private func downloadBlock(_ details: WorkDetails) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Загрузка")
                .font(AppTheme.headlineFont)
            Button {
                Task {
                    await downloads.downloadEntireBook(details: details, store: offline)
                }
            } label: {
                if downloads.activeDownloads.contains(workId) {
                    HStack {
                        ProgressView()
                        Text("Скачивание…")
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Label(downloadButtonTitle, systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .disabled(downloads.activeDownloads.contains(workId))

            if let p = offline.downloadProgress[workId], p > 0, p < 1 {
                ProgressView(value: p)
            }
        }
    }

    private var readButtonTitle: String {
        let canContinue = offline.progress(for: workId) != nil
            || offline.library.contains(where: { $0.workId == workId && $0.lastReadChapterId != nil })
        return canContinue ? "Продолжить чтение" : "Читать"
    }

    private var downloadButtonTitle: String {
        let downloaded = offline.library.contains(where: { $0.workId == workId && $0.isFullyDownloaded })
        return downloaded ? "Скачать заново" : "Скачать все главы"
    }

    private var commentsBlock: some View {
        BookCommentsSection(
            comments: comments,
            commentsLoading: commentsLoading,
            commentsError: commentsError,
            commentsHasMore: commentsHasMore,
            draftText: $draftText,
            replyTo: $replyTo,
            isSendingComment: isSendingComment,
            canWrite: auth.isAuthenticated,
            onSend: { Task { await sendComment() } },
            onLoadMore: { Task { await loadComments(reset: false) } }
        )
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            if downloads.online {
                details = try await APIClient.shared.workDetails(id: workId)
                if let details {
                    offline.cacheWorkDetails(details)
                }
            } else if let cached = offline.cachedWork(workId: workId) {
                details = Self.detailsFromCache(cached)
                if (details?.chapters ?? []).isEmpty, offline.cachedChapters(workId: workId).isEmpty {
                    error = "Нет сети и нет оглавления. Откройте книгу онлайн хотя бы раз или скачайте главы."
                }
            } else {
                error = "Нет сети и нет локальной копии"
            }
        } catch {
            if details == nil, let cached = offline.cachedWork(workId: workId) {
                details = Self.detailsFromCache(cached)
            } else {
                self.error = error.localizedDescription
            }
        }
    }

    private func loadComments(reset: Bool) async {
        guard downloads.online else {
            commentsError = "Комментарии доступны только онлайн"
            return
        }
        guard !commentsLoading else { return }
        commentsLoading = true
        defer { commentsLoading = false }
        do {
            let page = reset ? 1 : max(commentsPage, 1)
            let result = try await APIClient.shared.loadWorkComments(workId: workId, page: page)
            if reset {
                comments = result.comments
                commentsPage = 1
            } else {
                var seen = Set(comments.map(\.id))
                for item in result.comments where seen.insert(item.id).inserted {
                    comments.append(item)
                }
            }
            commentsHasMore = result.hasMore
            if result.hasMore {
                commentsPage = result.nextPage ?? (page + 1)
            }
            commentsError = nil
        } catch {
            commentsError = error.localizedDescription
        }
    }

    private func sendComment() async {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSendingComment = true
        commentsError = nil
        defer { isSendingComment = false }
        do {
            try await APIClient.shared.submitWorkComment(
                workId: workId,
                text: text,
                parentId: replyTo?.id,
                threadId: replyTo?.threadId ?? replyTo?.id,
                level: (replyTo?.level ?? -1) + 1
            )
            draftText = ""
            replyTo = nil
            commentsError = nil
            await loadComments(reset: true)
        } catch {
            commentsError = error.localizedDescription
        }
    }

    private static func detailsFromCache(_ cached: CachedWork) -> WorkDetails {
        let chapters = (cached.chaptersJSON).flatMap {
            try? JSONDecoder().decode([ChapterMeta].self, from: $0)
        } ?? []
        return WorkDetails(
            id: cached.workId,
            title: cached.title,
            authorFIO: cached.author,
            authorUserName: cached.authorUserName,
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
    }
}

private struct BookTOCSheet: View {
    let workId: Int
    let chapters: [ChapterMeta]
    let needsPurchase: Bool
    let onOpen: (Int) -> Void
    let onPurchase: () -> Void
    let onClose: () -> Void

    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var appearance: AppAppearanceStore

    var body: some View {
        NavigationStack {
            List(chapters) { chapter in
                Button {
                    if chapter.isAvailableEffective {
                        onOpen(chapter.id)
                    } else if needsPurchase {
                        onPurchase()
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(chapter.displayTitle)
                                .foregroundStyle(chapter.isAvailableEffective ? Color.primary : .secondary)
                            if !chapter.isAvailableEffective {
                                Text("Недоступна")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
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
                }
            }
            .navigationTitle("Оглавление")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Закрыть", action: onClose)
                }
            }
        }
    }
}

struct BookCommentsSection: View {
    let comments: [WorkComment]
    let commentsLoading: Bool
    let commentsError: String?
    let commentsHasMore: Bool
    @Binding var draftText: String
    @Binding var replyTo: WorkComment?
    let isSendingComment: Bool
    let canWrite: Bool
    let onSend: () -> Void
    let onLoadMore: () -> Void

    @EnvironmentObject private var appearance: AppAppearanceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Комментарии")
                    .font(AppTheme.headlineFont)
                Spacer()
                if commentsLoading {
                    ProgressView()
                }
            }

            if canWrite {
                composer
                if let commentsError {
                    Text(commentsError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } else {
                Text("Войдите в аккаунт, чтобы писать комментарии.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if !canWrite, let commentsError {
                Text(commentsError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if comments.isEmpty, !commentsLoading {
                Text("Пока нет комментариев")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(comments) { comment in
                commentRow(comment)
                Divider()
            }

            if commentsHasMore {
                Button("Ещё комментарии", action: onLoadMore)
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.bordered)
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let replyTo {
                HStack {
                    Text("Ответ для \(replyTo.authorName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Отмена") { self.replyTo = nil }
                        .font(.caption)
                }
            }
            TextField(
                replyTo == nil ? "Написать комментарий…" : "Ваш ответ…",
                text: $draftText,
                axis: .vertical
            )
            .lineLimit(3...8)
            .textFieldStyle(.roundedBorder)

            Button(action: onSend) {
                if isSendingComment {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text(replyTo == nil ? "Отправить" : "Ответить")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSendingComment)
        }
    }

    private func commentRow(_ comment: WorkComment) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(comment.authorName)
                    .font(.subheadline.weight(.semibold))
                if comment.isAuthor {
                    Text("автор")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(appearance.accent.opacity(0.15))
                        .clipShape(Capsule())
                }
                if comment.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let rating = comment.rating, rating != 0 {
                    Text(rating > 0 ? "+\(rating)" : "\(rating)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Text(comment.text)
                .font(.subheadline)
                .foregroundStyle(.primary.opacity(0.9))
            if canWrite {
                Button("Ответить") { replyTo = comment }
                    .font(.caption)
            }
        }
        .padding(.leading, CGFloat(min(comment.level, 4)) * 14)
    }
}
