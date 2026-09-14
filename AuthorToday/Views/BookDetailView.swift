import SwiftUI

struct BookDetailView: View {
    let workId: Int

    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var appearance: AppAppearanceStore
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var pro: ProEntitlementStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var details: WorkDetails?
    @State private var error: String?
    @State private var isLoading = true
    @State private var openReader = false
    @State private var startChapterId: Int?
    @State private var showPurchase = false
    @State private var showTOC = false
    @State private var openAuthorProfile = false
    @State private var openSeries = false
    @State private var showPaywall = false
    @State private var paywallReason: String?

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

    private var resolvedSeriesTitle: String? {
        if let title = details?.displaySeriesTitle { return title }
        let cached = offline.cachedWork(workId: workId)?.displaySeriesFolder ?? ""
        return cached.isEmpty || cached == "Без серии" ? nil : cached
    }

    private var resolvedSeriesId: Int? {
        details?.seriesId ?? offline.cachedWork(workId: workId)?.seriesId
    }

    var body: some View {
        Group {
            if isLoading {
                LoadingStateView(title: "Загрузка…")
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
        .navigationDestination(isPresented: $openSeries) {
            seriesDestination
        }
        .sheet(isPresented: $showPurchase, onDismiss: {
            Task { await load() }
        }) {
            purchaseSheet
        }
        .sheet(isPresented: $showPaywall) {
            ProPaywallView(reason: paywallReason)
                .environmentObject(pro)
                .environmentObject(appearance)
                .environmentObject(offline)
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
            presentCachedPageIfPossible()
            if details != nil {
                Task { await load() }
                await loadComments(reset: true)
            } else {
                await load()
                await loadComments(reset: true)
            }
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
    private var seriesDestination: some View {
        if let seriesTitle = resolvedSeriesTitle {
            SeriesDetailView(
                seriesTitle: seriesTitle,
                seriesId: resolvedSeriesId,
                authorUserName: resolvedAuthorUserName,
                authorDisplayName: details?.displayAuthor
            )
        } else {
            ContentUnavailableView(
                "Нет серии",
                systemImage: "books.vertical",
                description: Text("У этой книги не указана серия.")
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
                            .foregroundStyle(appearance.themePreset.chromePrimaryText(colorScheme: colorScheme))
                            .themedReadableText()
                        Text(HTMLText.plain(from: annotation))
                            .font(.body)
                            .foregroundStyle(appearance.themePreset.chromePrimaryText(colorScheme: colorScheme).opacity(0.92))
                            .themedReadableText()
                    }
                }
                commentsBlock
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .themedGroupedFill()
        .background {
            ThemeAtmosphereView(preset: appearance.themePreset)
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .environment(\.themePreset, appearance.themePreset)
        .environment(\.themeAccent, appearance.accent)
    }

    private func header(_ details: WorkDetails) -> some View {
        HStack(alignment: .top, spacing: 16) {
            CoverImage(urlString: details.coverUrl, corner: 10)
                .frame(width: 120, height: 170)
                .shadow(color: .black.opacity(0.12), radius: 10, y: 6)

            VStack(alignment: .leading, spacing: 8) {
                Text(details.displayTitle)
                    .font(.system(.title2, design: .serif).weight(.semibold))
                    .foregroundStyle(appearance.themePreset.chromePrimaryText(colorScheme: colorScheme))
                    .themedReadableText()

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
                    .font(.caption)
                    .themedSecondaryText()
                }
                .disabled(resolvedAuthorUserName == nil)

                if let seriesTitle = resolvedSeriesTitle {
                    Button {
                        openSeries = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "books.vertical")
                                .font(.caption)
                            Text("Серия: \(seriesTitle)")
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                        }
                        .font(.caption)
                        .themedSecondaryText()
                    }
                    .buttonStyle(.plain)
                }

                if let genre = details.genreName {
                    Text([genre, details.secondGenreName].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .themedSecondaryText()
                }

                if details.isPurchased == true {
                    Label("Куплено", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .themedSecondaryText()
                } else if let price = details.displayPriceText {
                    Text(price)
                        .font(.caption.weight(.semibold))
                        .themedSecondaryText()
                }

                if offline.cachedWork(workId: workId)?.isFullyDownloaded == true {
                    Label("Скачано целиком", systemImage: "arrow.down.circle.fill")
                        .font(.caption)
                        .themedSecondaryText()
                } else if let cov = offline.offlineChapterCoverage(workId: workId), cov.ready > 0 {
                    Label("Офлайн \(cov.ready) из \(cov.total)", systemImage: "arrow.down.circle")
                        .font(.caption)
                        .themedSecondaryText()
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
                    .font(.caption)
                    .themedSecondaryText()
            }

            Button {
                Task {
                    if downloads.online, !offline.isInLibrary(workId) {
                        try? await offline.addToSiteLibrary(workId: workId, state: "Reading")
                    }
                    // Always nil for Continue/Read — DownloadManager picks the furthest
                    // of local checkpoint, ReadingProgress and portal lastReadChapterId.
                    // Passing a concrete id (esp. a stale first chapter) blocked resume.
                    startChapterId = nil
                    openReader = true
                }
            } label: {
                Text(readButtonTitle)
            }
            .buttonStyle(PrimaryButtonStyle())
            .opacity(canOpenReader(details) ? 1 : 0.45)
            .disabled(!canOpenReader(details))

            if let chapters = details.chapters, !chapters.isEmpty {
                Button {
                    showTOC = true
                } label: {
                    Label("Оглавление (\(chapters.count))", systemImage: "list.bullet")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(detailChromeInk)
            }

            if offline.library.contains(where: { $0.workId == workId }) {
                Label("В вашей библиотеке", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .themedSecondaryText()
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
                .tint(detailChromeInk)
            }

            if !details.availableChapters.isEmpty || offline.hasReadableOfflineChapters(workId: workId) {
                downloadBlock(details)
            }

            NavigationLink {
                BookmarksNotesView(workIdFilter: workId)
            } label: {
                Label(
                    pro.isProUnlocked ? "Закладки и заметки" : "Закладки и заметки (Pro)",
                    systemImage: "bookmark"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(detailChromeInk)
        }
    }

    private var detailChromeInk: Color {
        appearance.themePreset.chromePrimaryText(colorScheme: colorScheme)
    }

    private func downloadBlock(_ details: WorkDetails) -> some View {
        let alreadyFull = offline.cachedWork(workId: workId)?.isFullyDownloaded == true
        let fullCount = offline.fullyDownloadedCount
        let allowed = pro.canStartFullDownload(
            workId: workId,
            fullyDownloadedCount: fullCount,
            alreadyFullyDownloaded: alreadyFull
        )

        return VStack(alignment: .leading, spacing: 10) {
            Text("Загрузка")
                .font(AppTheme.headlineFont)
                .foregroundStyle(detailChromeInk)
                .themedReadableText()

            if !pro.isProUnlocked {
                OfflineQuotaStatusView(
                    compact: true,
                    onUpgrade: {
                        paywallReason = "Лимит бесплатного офлайна (\(ProFeatures.freeFullDownloadLimit) книги) исчерпан. Pro снимает ограничение."
                        showPaywall = true
                    }
                )
            }

            Button {
                if !allowed {
                    paywallReason = "Лимит бесплатного офлайна (\(ProFeatures.freeFullDownloadLimit) книги) исчерпан. Pro снимает ограничение."
                    showPaywall = true
                    return
                }
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
                    Label(
                        allowed ? downloadButtonTitle : "Скачать все главы (Pro)",
                        systemImage: allowed ? "arrow.down.circle" : "lock.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .tint(detailChromeInk)
            .disabled(downloads.activeDownloads.contains(workId))

            if let p = offline.downloadProgress[workId], p > 0, p < 1 {
                ProgressView(value: p)
            }
        }
    }

    private func canOpenReader(_ details: WorkDetails) -> Bool {
        if offline.hasReadableOfflineChapters(workId: workId) { return true }
        if !details.availableChapters.isEmpty { return true }
        return false
    }

    private var readButtonTitle: String {
        let canContinue = ReadingSessionStore.shared.checkpoint(for: workId) != nil
            || offline.progress(for: workId) != nil
            || offline.library.contains(where: { $0.workId == workId && $0.lastReadChapterId != nil })
        return canContinue ? "Продолжить чтение" : "Читать"
    }

    private var downloadButtonTitle: String {
        if offline.cachedWork(workId: workId)?.isFullyDownloaded == true {
            return "Скачать заново"
        }
        if let cov = offline.offlineChapterCoverage(workId: workId), cov.ready > 0, cov.ready < cov.total {
            return "Докачать главы (\(cov.ready)/\(cov.total))"
        }
        return "Скачать все главы"
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

    private func presentCachedPageIfPossible() {
        if let cached = offline.workDetailsFromCache(workId: workId) {
            details = cached
            isLoading = false
            error = nil
        }
    }

    private func load() async {
        let hadCache = details != nil
        if !hadCache {
            presentCachedPageIfPossible()
        }
        if details == nil {
            isLoading = true
        }
        defer { isLoading = false }
        do {
            if downloads.online {
                // Portal may be blocked even when the path looks online — keep the saved page.
                let remote = try await APIClient.shared.workDetails(id: workId)
                details = remote
                offline.cacheWorkDetails(remote)
                offline.adoptRemoteResumeIfNeeded(
                    workId: workId,
                    chapterId: remote.resolvedLastReadChapterId,
                    chapterFraction: remote.resolvedChapterProgress,
                    bookProgress: nil
                )
                // meta-info is the most reliable source for series + last-read chapter + %
                if let meta = try? await APIClient.shared.workMeta(id: workId) {
                    details = (details ?? remote).mergingSeries(from: meta)
                    if let merged = details {
                        offline.cacheWorkDetails(merged)
                    }
                    if offline.isInLibrary(workId) {
                        offline.upsertWork(from: meta, markFromSite: true)
                    }
                    offline.adoptRemoteResumeIfNeeded(
                        workId: workId,
                        chapterId: meta.resolvedLastReadChapterId,
                        chapterFraction: meta.resolvedChapterProgress,
                        bookProgress: meta.resolvedProgress
                    )
                    if meta.resolvedProgress > 0 {
                        offline.updateBookProgress(workId: workId, progress: meta.resolvedProgress)
                    }
                }
                error = nil
            } else if details == nil {
                if let vault = await BookVaultSync.shared.fetchWorkDetails(workId: workId) {
                    details = vault
                    offline.cacheWorkDetails(vault)
                    error = nil
                } else {
                    error = offline.hasOfflineBookPage(workId: workId)
                        ? "Нет сети и нет оглавления. Откройте книгу онлайн хотя бы раз или скачайте главы."
                        : "Нет сети и нет локальной копии"
                }
            }
        } catch {
            if details == nil, let cached = offline.workDetailsFromCache(workId: workId) {
                details = cached
            } else if details == nil, let vault = await BookVaultSync.shared.fetchWorkDetails(workId: workId) {
                details = vault
                offline.cacheWorkDetails(vault)
            } else if details == nil {
                self.error = error.localizedDescription
            }
            // Keep the saved page if the portal is unreachable.
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
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var composerFocused: Bool

    private var primaryInk: Color {
        appearance.themePreset.chromePrimaryText(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Комментарии")
                    .font(AppTheme.headlineFont)
                    .foregroundStyle(primaryInk)
                    .themedReadableText()
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
                        .themedReadableText()
                }
            } else {
                Text("Войдите в аккаунт, чтобы писать комментарии.")
                    .font(.caption)
                    .themedSecondaryText()
            }

            if !canWrite, let commentsError {
                Text(commentsError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .themedReadableText()
            }

            if comments.isEmpty, !commentsLoading {
                Text("Пока нет комментариев")
                    .font(.caption)
                    .themedSecondaryText()
            }

            ForEach(comments) { comment in
                commentRow(comment)
            }

            if commentsHasMore {
                Button("Ещё комментарии", action: onLoadMore)
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.bordered)
                    .tint(primaryInk)
            }
        }
        .onChange(of: replyTo) { _, next in
            if next != nil { composerFocused = true }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let replyTo {
                HStack {
                    Text("Ответ для \(replyTo.authorName)")
                        .font(.caption)
                        .themedSecondaryText()
                    Spacer()
                    Button("Отмена") {
                        self.replyTo = nil
                        composerFocused = false
                    }
                    .font(.caption)
                    .tint(primaryInk)
                }
            }
            TextField(
                replyTo == nil ? "Написать комментарий…" : "Ваш ответ…",
                text: $draftText,
                axis: .vertical
            )
            .lineLimit(3...8)
            .padding(10)
            .background(Color.clear)
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(primaryInk.opacity(0.45), lineWidth: 1)
            }
            .foregroundStyle(primaryInk)
            .tint(primaryInk)
            .focused($composerFocused)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Готово") { composerFocused = false }
                }
            }

            HStack(spacing: 10) {
                if composerFocused {
                    Button("Скрыть клавиатуру") {
                        composerFocused = false
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .tint(primaryInk)
                }
                Button(action: {
                    composerFocused = false
                    onSend()
                }) {
                    if isSendingComment {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(replyTo == nil ? "Отправить" : "Ответить")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(appearance.accent)
                .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSendingComment)
            }
        }
    }

    private func commentRow(_ comment: WorkComment) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(comment.authorName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(primaryInk)
                    .themedReadableText()
                if comment.isAuthor {
                    Text("автор")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .themedSecondaryText()
                        .overlay {
                            Capsule().strokeBorder(primaryInk.opacity(0.45), lineWidth: 1)
                        }
                }
                if comment.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .themedSecondaryText()
                }
                Spacer()
                if let rating = comment.rating, rating != 0 {
                    Text(rating > 0 ? "+\(rating)" : "\(rating)")
                        .font(.caption2.monospacedDigit())
                        .themedSecondaryText()
                }
            }
            if !comment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(comment.text)
                    .font(.subheadline)
                    .foregroundStyle(primaryInk)
                    .textSelection(.enabled)
                    .themedReadableText()
            }
            if canWrite {
                Button("Ответить") {
                    replyTo = comment
                    composerFocused = true
                }
                .font(.caption)
                .themedSecondaryText()
            }
        }
        .padding(.vertical, 8)
        .padding(.leading, CGFloat(min(comment.level, 4)) * 14)
    }
}

