import SwiftUI
import UIKit
import SwiftData

struct ReaderView: View {
    let workId: Int
    let initialChapterId: Int?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var settings: ReaderSettingsStore
    @EnvironmentObject private var pro: ProEntitlementStore
    @EnvironmentObject private var appearance: AppAppearanceStore
    @ObservedObject private var session = ReadingSessionStore.shared

    @State private var details: WorkDetails?
    @State private var chapters: [ChapterMeta] = []
    @State private var chapterIndex = 0
    @State private var html = ""
    @State private var chapterTitle = ""
    @State private var plainText = ""
    @State private var isLoading = true
    @State private var error: String?
    @State private var showChrome = false
    @State private var showSettings = false
    @State private var showTOC = false
    @State private var showPurchase = false
    @State private var showPaywall = false
    @State private var paywallReason: String?
    @State private var showNoteComposer = false
    @State private var noteDraft = ""
    @State private var bookmarkFlash: String?
    @State private var pageIndex = 0
    @State private var scrollOffset: Double = 0
    @State private var scrollFraction: Double = 0
    @State private var charOffset: Int = 0
    @State private var didAddToLibrary = false
    @State private var pageCountForChapter = 1
    @State private var pendingRestore = false
    @State private var restorePageIndex = 0
    @State private var restoreOffsetY: Double = 0
    @State private var restoreFraction: Double = 0
    @State private var restoreGeneration = 0
    @State private var persistScrollTask: Task<Void, Never>?
    @State private var remoteSyncTask: Task<Void, Never>?
    @State private var didStartSession = false
    @State private var chapterContentFits = false

    private var currentChapter: ChapterMeta? {
        chapters.indices.contains(chapterIndex) ? chapters[chapterIndex] : nil
    }

    var body: some View {
        ZStack {
            readerBackground

            if isLoading {
                VStack(spacing: 20) {
                    LoadingStateView(
                        title: "Открываем книгу…",
                        subtitle: downloads.online
                            ? nil
                            : "Нет сети. Нужна заранее скачанная глава."
                    )
                    Button("Закрыть") {
                        session.endReading()
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .tint(settings.textColor)
                }
            } else if let error {
                VStack(spacing: 16) {
                    Image(systemName: "wifi.slash")
                        .font(.largeTitle)
                        .foregroundStyle(settings.textColor.opacity(0.7))
                    Text(error)
                        .foregroundStyle(settings.textColor)
                        .multilineTextAlignment(.center)
                    Button("Повторить") { Task { await bootstrap() } }
                        .buttonStyle(.borderedProminent)
                    Button("Назад") {
                        session.endReading()
                        dismiss()
                    }
                    .foregroundStyle(settings.textColor)
                }
                .padding(24)
            } else {
                readerContent
            }

            // End-of-chapter CTA — visible without tapping chrome.
            if error == nil, !isLoading, !showChrome, showEndOfChapterCTA {
                VStack {
                    Spacer(minLength: 0)
                    endOfChapterBar
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.2), value: showEndOfChapterCTA)
            }

            if showChrome || error != nil || isLoading {
                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: 0)
                    if error == nil && !isLoading {
                        bottomBar
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .transition(.opacity)
            }
        }
        .navigationBarHidden(true)
        // Show status bar with chrome; force scheme so time/battery stay readable.
        .statusBarHidden(!showChrome && error == nil && !isLoading)
        .preferredColorScheme(
            (showChrome || error != nil || isLoading)
                ? (chromePrefersDark ? .dark : .light)
                : nil
        )
        .toolbar(.hidden, for: .tabBar)
        .toolbar(.hidden, for: .navigationBar)
        .ignoresSafeArea(edges: (showChrome || error != nil || isLoading) ? [] : .all)
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                ReaderSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Готово") { showSettings = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showPurchase) {
            if let details {
                PurchaseWebView(url: details.purchaseURL, title: "Покупка")
            }
        }
        .sheet(isPresented: $showTOC) {
            NavigationStack {
                List {
                    ForEach(Array(chapters.enumerated()), id: \.element.id) { idx, chapter in
                        tocRow(idx: idx, chapter: chapter)
                    }
                }
                .navigationTitle("Оглавление")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Закрыть") { showTOC = false }
                    }
                }
            }
        }
        .sheet(isPresented: $showPaywall) {
            ProPaywallView(reason: paywallReason)
        }
        .sheet(isPresented: $showNoteComposer) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Заметка к «\(chapterTitle)»")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $noteDraft)
                        .frame(minHeight: 160)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                    Spacer()
                }
                .padding()
                .navigationTitle("Новая заметка")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Отмена") { showNoteComposer = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Сохранить") { saveNote() }
                            .disabled(noteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .task {
            await bootstrap()
            UIApplication.shared.isIdleTimerDisabled = settings.keepScreenOn
            ProNudgeStore.shared.recordActiveReadingDay()
        }
        .onChange(of: settings.keepScreenOn) { _, on in
            UIApplication.shared.isIdleTimerDisabled = on
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .inactive || phase == .background {
                persistScrollTask?.cancel()
                remoteSyncTask?.cancel()
                persistProgress()
                syncProgressRemote()
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            persistScrollTask?.cancel()
            remoteSyncTask?.cancel()
            persistProgress()
            syncProgressRemote()
            // Only clear "was reading" when user navigates away while app is active.
            if scenePhase == .active {
                session.endReading()
            }
        }
    }

    // MARK: - Layers

    private var readerBackground: some View {
        GeometryReader { geo in
            ZStack {
                settings.solidBackground
                if let image = settings.backgroundImage {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .opacity(settings.backgroundImageOpacity)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var readerContent: some View {
        switch settings.pageTurnMode {
        case .verticalScroll:
            scrollReader
        case .horizontalSwipe, .curlStyle, .tapAndSwipe, .tapZones:
            pagedReader
        }
    }

    private var scrollReader: some View {
        ReaderTextScrollView(
            text: plainText,
            chapterHeading: chapterTitle,
            font: settings.fontFamily.uiFont(size: settings.fontSize),
            textColor: settings.textColor.uiColor(),
            lineSpacing: settings.lineSpacing,
            contentInset: UIEdgeInsets(
                top: settings.marginVertical + (showChrome ? 56 : 12),
                left: settings.marginHorizontal,
                bottom: settings.marginVertical + (showChrome ? 56 : 12),
                right: settings.marginHorizontal
            ),
            restoreFraction: restoreFraction,
            restoreCharOffset: charOffset,
            restoreGeneration: restoreGeneration,
            onScroll: { offsetY, fraction, char in
                handleScroll(offsetY: offsetY, fraction: fraction, charOffset: char)
            },
            onContentFits: { fits in
                chapterContentFits = fits
            },
            onTap: { toggleChrome() }
        )
        .ignoresSafeArea(edges: showChrome ? [] : .bottom)
    }

    private func handleScroll(offsetY: Double, fraction: Double, charOffset: Int) {
        // While restoring, ignore intermediate layout fractions (e.g. 30% before
        // content height settles) — otherwise they overwrite a good 45% checkpoint.
        if pendingRestore {
            let target = restoreFraction
            let closeEnough = target <= 0.01
                || fraction + 0.03 >= target
                || (charOffset > 40 && self.charOffset > 40
                    && charOffset + max(plainText.count / 40, 80) >= self.charOffset)
            if fraction <= 0.01 || !closeEnough {
                return
            }
            pendingRestore = false
        }

        scrollOffset = offsetY
        scrollFraction = fraction
        // Keep restoreFraction in sync with live reading so a later text reflow
        // does not snap back to the position from when the chapter was opened.
        if fraction > 0.005 {
            restoreFraction = fraction
            restoreOffsetY = offsetY
        }
        if charOffset > 0 {
            self.charOffset = charOffset
        }
        considerLibraryAdd(chapterProgress: fraction)
        if let chapter = currentChapter {
            session.saveCheckpoint(
                workId: workId,
                chapterId: chapter.id,
                offsetY: offsetY,
                fraction: fraction,
                charOffset: charOffset > 0 ? charOffset : self.charOffset,
                pageIndex: pageIndex
            )
        }
        schedulePersistScroll()
    }

    private var pagedReader: some View {
        GeometryReader { geo in
            pagedReaderContent(size: geo.size)
        }
    }

    private func pagedReaderContent(size: CGSize) -> some View {
        let pages = paginate(text: plainText, size: size)
        let mode = settings.pageTurnMode

        return ZStack {
            TabView(selection: $pageIndex) {
                ForEach(Array(pages.enumerated()), id: \.offset) { idx, page in
                    Text(HTMLText.attributedReaderPage(
                        page,
                        chapterHeading: chapterTitle,
                        isFirstPage: idx == 0,
                        size: settings.fontSize,
                        family: settings.fontFamily
                    ))
                        .font(settings.fontFamily.font(size: settings.fontSize))
                        .foregroundStyle(settings.textColor)
                        .lineSpacing(settings.lineSpacing)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.horizontal, settings.marginHorizontal)
                        .padding(.vertical, settings.marginVertical + (showChrome ? 48 : 8))
                        .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(mode == .curlStyle ? .easeInOut(duration: 0.28) : .default, value: pageIndex)

            if mode == .tapZones || mode == .tapAndSwipe {
                HStack(spacing: 0) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { turnPage(by: -1, pageCount: pages.count) }
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { toggleChrome() }
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { turnPage(by: 1, pageCount: pages.count) }
                }
            } else {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { toggleChrome() }
            }
        }
        .onChange(of: plainText) { _, _ in
            if pendingRestore {
                // Keep restored page until layout applies it.
            } else {
                pageIndex = 0
            }
        }
        .onChange(of: pageIndex) { _, newValue in
            pageCountForChapter = max(pages.count, 1)
            if pendingRestore { return }
            let fraction = pages.count <= 1 ? 0.0 : Double(newValue) / Double(pages.count - 1)
            scrollFraction = fraction
            charOffset = Int(Double(plainText.count) * fraction)
            if let chapter = currentChapter {
                session.saveCheckpoint(
                    workId: workId,
                    chapterId: chapter.id,
                    offsetY: scrollOffset,
                    fraction: fraction,
                    charOffset: charOffset,
                    pageIndex: newValue
                )
            }
            persistProgress()
            considerLibraryAdd(chapterProgress: chapterReadProgress(page: newValue, pages: pages.count))
        }
        .onAppear {
            pageCountForChapter = max(pages.count, 1)
            applyPendingPageRestoreIfNeeded(pageCount: pages.count)
            considerLibraryAdd(chapterProgress: chapterReadProgress(page: pageIndex, pages: pages.count))
        }
        .onChange(of: pages.count) { _, newCount in
            applyPendingPageRestoreIfNeeded(pageCount: newCount)
        }
    }

    /// Dark chrome → light status-bar icons; light chrome → dark icons.
    private var chromePrefersDark: Bool {
        if let scheme = settings.appColorScheme { return scheme == .dark }
        // Custom / image themes: light reader text usually means a dark page.
        let ui = UIColor(settings.textColor)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return luminance > 0.55
    }

    private var chromeForeground: Color {
        chromePrefersDark ? .white : .primary
    }

    private var chromeSecondary: Color {
        chromePrefersDark ? .white.opacity(0.7) : .secondary
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                persistProgress()
                session.endReading()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)

            VStack(alignment: .leading, spacing: 2) {
                Text(details?.displayTitle ?? "Чтение")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(chapterTitle)
                    .font(.caption)
                    .foregroundStyle(chromeSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button { showTOC = true } label: {
                Image(systemName: "list.bullet")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)

            Button { addBookmarkTapped() } label: {
                Image(systemName: "bookmark")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)

            Button { noteTapped() } label: {
                Image(systemName: "note.text")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)

            Button { showSettings = true } label: {
                Image(systemName: "textformat.size")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
        }
        .foregroundStyle(chromeForeground)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                (chromePrefersDark ? Color.black : Color.white)
                    .opacity(0.94)
                Rectangle().fill(.ultraThinMaterial)
            }
            .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .bottom) {
            if let bookmarkFlash {
                Text(bookmarkFlash)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 4)
                    .transition(.opacity)
            }
        }
    }

    /// Near the end of the current chapter (scroll or last page).
    private var isAtChapterEnd: Bool {
        guard !pendingRestore, !plainText.isEmpty else { return false }
        if settings.pageTurnMode == .verticalScroll {
            // Scrolled near bottom, or chapter fits on one screen.
            return scrollFraction >= 0.90 || chapterContentFits
        }
        return pageCountForChapter > 0 && pageIndex + 1 >= pageCountForChapter
    }

    private var showEndOfChapterCTA: Bool {
        isAtChapterEnd && nearestReadableIndex(from: chapterIndex, direction: 1) != nil
    }

    private var endOfChapterBar: some View {
        Button {
            if let next = nearestReadableIndex(from: chapterIndex, direction: 1) {
                Task { await openChapter(at: next) }
            }
        } label: {
            Label("Следующая глава", systemImage: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .contentShape(Rectangle())
                .foregroundStyle(settings.textColor)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(settings.textColor.opacity(0.12))
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(settings.solidBackground.opacity(0.92))
                        )
                )
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.bottom, 16)
        .padding(.top, 8)
        .background(
            LinearGradient(
                colors: [settings.solidBackground.opacity(0), settings.solidBackground.opacity(0.95)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 88)
            .allowsHitTesting(false),
            alignment: .bottom
        )
    }

    private var bottomBar: some View {
        let paged = settings.pageTurnMode != .verticalScroll
        let canPrevChapter = nearestReadableIndex(from: chapterIndex, direction: -1) != nil
        let canNextChapter = nearestReadableIndex(from: chapterIndex, direction: 1) != nil
        let canPrevPage = paged && pageIndex > 0
        let canNextPage = paged && pageIndex + 1 < pageCountForChapter
        let canGoBack = paged ? (canPrevPage || canPrevChapter) : canPrevChapter
        let canGoForward = paged ? (canNextPage || canNextChapter) : canNextChapter

        return VStack(spacing: 10) {
            Text(bottomProgressLabel(paged: paged))
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(chromeSecondary)

            HStack(spacing: 12) {
                Button {
                    navigateReader(direction: -1, paged: paged)
                } label: {
                    Label(
                        paged ? "Назад" : "Пред. глава",
                        systemImage: "chevron.left"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(chromeForeground.opacity(chromePrefersDark ? 0.14 : 0.08))
                    )
                }
                .buttonStyle(.borderless)
                .disabled(!canGoBack)
                .opacity(canGoBack ? 1 : 0.35)

                Button {
                    navigateReader(direction: 1, paged: paged)
                } label: {
                    Label(
                        paged ? "Вперёд" : "След. глава",
                        systemImage: "chevron.right"
                    )
                    .font(.subheadline.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(chromeForeground.opacity(chromePrefersDark ? 0.14 : 0.08))
                    )
                }
                .buttonStyle(.borderless)
                .disabled(!canGoForward)
                .opacity(canGoForward ? 1 : 0.35)
            }
        }
        .foregroundStyle(chromeForeground)
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                (chromePrefersDark ? Color.black : Color.white)
                    .opacity(0.94)
                Rectangle().fill(.ultraThinMaterial)
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private func bottomProgressLabel(paged: Bool) -> String {
        let chapterPart = "Глава \(chapterIndex + 1)/\(max(chapters.count, 1))"
        if paged {
            return "\(chapterPart)  ·  стр. \(pageIndex + 1)/\(max(pageCountForChapter, 1))"
        }
        // Percent inside the current chapter (not whole-book library %).
        let pct = Int((scrollFraction * 100).rounded())
        return "\(chapterPart)  ·  \(pct)% главы"
    }

    private func navigateReader(direction: Int, paged: Bool) {
        if paged {
            turnPage(by: direction, pageCount: pageCountForChapter)
            return
        }
        if let idx = nearestReadableIndex(from: chapterIndex, direction: direction) {
            Task { await openChapter(at: idx) }
        }
    }

    private func tocRow(idx: Int, chapter: ChapterMeta) -> some View {
        let locked = !chapter.isAvailableEffective
        return Button {
            guard !locked else {
                if details?.needsPurchase == true {
                    showTOC = false
                    showPurchase = true
                }
                return
            }
            showTOC = false
            Task { await openChapter(at: idx) }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(chapter.displayTitle)
                        .foregroundStyle(locked ? Color.secondary : Color.primary)
                        .multilineTextAlignment(.leading)
                    if locked {
                        Text("Недоступна · нужна покупка")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if idx == chapterIndex {
                    Image(systemName: "book.fill")
                        .foregroundStyle(AppTheme.moss)
                }
            }
        }
        .disabled(locked && details?.needsPurchase != true)
    }

    // MARK: - Logic

    private func bootstrap() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let result = try await withThrowingTaskGroup(
                of: (details: WorkDetails, chapterId: Int, html: String, title: String).self
            ) { group in
                group.addTask { @MainActor in
                    try await downloads.openAndCache(
                        workId: workId,
                        preferredChapterId: initialChapterId,
                        store: offline
                    )
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 45_000_000_000)
                    throw APIError.message(
                        "Превышено время ожидания. Проверьте сеть или скачайте книгу заранее."
                    )
                }
                let first = try await group.next()!
                group.cancelAll()
                return first
            }
            details = result.details
            // Full TOC including paid/locked chapters (drafts still hidden)
            chapters = (result.details.chapters ?? []).filter { !($0.isDraft ?? false) }
            if chapters.isEmpty {
                chapters = result.details.availableChapters
            }
            if let idx = chapters.firstIndex(where: { $0.id == result.chapterId }) {
                chapterIndex = idx
            } else if let firstReadable = chapters.firstIndex(where: \.isAvailableEffective) {
                chapterIndex = firstReadable
            }
            html = result.html
            chapterTitle = result.title
            plainText = HTMLText.readerPlain(title: result.title, html: result.html)
            if Self.looksGarbled(plainText) {
                // Drop bad cache from older builds and refetch once
                offline.removeCachedChapter(workId: workId, chapterId: result.chapterId)
                let chapter = chapters.first(where: { $0.id == result.chapterId }) ?? chapters[0]
                let idx = chapters.firstIndex(where: { $0.id == chapter.id }) ?? 0
                let reloaded = try await downloads.loadChapter(
                    workId: workId,
                    chapter: chapter,
                    sortIndex: idx,
                    store: offline
                )
                html = reloaded.html
                chapterTitle = reloaded.title
                plainText = HTMLText.readerPlain(title: reloaded.title, html: reloaded.html)
            }
            if let progress = bestCheckpoint(for: result.chapterId) {
                var frac = progress.fraction
                var chars = progress.charOffset
                if frac < 0.005, chars > 40, plainText.count > 0 {
                    frac = min(Double(chars) / Double(plainText.count), 0.95)
                }
                if frac < 0.005, progress.offsetY > 8 {
                    frac = min(progress.offsetY / 4000.0, 0.95)
                }
                if chars <= 40, frac > 0.01, plainText.count > 0 {
                    chars = Int((Double(plainText.count) * frac).rounded())
                }
                restorePageIndex = progress.pageIndex
                restoreOffsetY = progress.offsetY
                restoreFraction = frac
                scrollOffset = progress.offsetY
                scrollFraction = frac
                charOffset = chars
                pageIndex = progress.pageIndex
                pendingRestore = frac > 0.01 || progress.pageIndex > 0
                    || progress.offsetY > 8 || chars > 40
                if settings.pageTurnMode == .verticalScroll, frac > 0.005 || chars > 40 {
                    restoreGeneration += 1
                }
            } else {
                pendingRestore = false
                restorePageIndex = 0
                restoreOffsetY = 0
                restoreFraction = 0
            }
            chapterContentFits = false
            didAddToLibrary = offline.isInLibrary(workId)
            // Opening a book to read → ensure it appears in the library.
            if !didAddToLibrary, downloads.online {
                considerLibraryAdd(chapterProgress: 1)
            }
            // Only mark "was reading" after a successful open — otherwise cold start
            // keeps reopening a book that can't load offline.
            session.beginReading(workId: workId, chapterId: result.chapterId)
            didStartSession = true
            // Do not persistProgress() here: a wrong start chapter at offset 0 would
            // overwrite a further last-read position before the user scrolls.
            prefetchNeighborChapters()
        } catch {
            self.error = error.localizedDescription
            session.endReading()
            didStartSession = false
        }
    }

    private func openChapter(at index: Int) async {
        guard chapters.indices.contains(index) else { return }
        let chapter = chapters[index]
        guard chapter.isAvailableEffective else {
            if details?.needsPurchase == true {
                showPurchase = true
            } else {
                error = "Эта глава недоступна"
            }
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await downloads.loadChapter(
                workId: workId,
                chapter: chapter,
                sortIndex: index,
                store: offline
            )
            chapterIndex = index
            chapterTitle = loaded.title
            html = loaded.html
            plainText = HTMLText.readerPlain(title: loaded.title, html: loaded.html)
            pageIndex = 0
            scrollOffset = 0
            scrollFraction = 0
            charOffset = 0
            chapterContentFits = false
            pendingRestore = false
            restoreOffsetY = 0
            restoreFraction = 0
            restorePageIndex = 0
            // New chapter starts at 0 — allow overwriting previous chapter's checkpoint.
            session.saveCheckpoint(
                workId: workId,
                chapterId: chapter.id,
                offsetY: 0,
                fraction: 0,
                charOffset: 0,
                pageIndex: 0,
                allowZeroOverwrite: true
            )
            persistProgress(forceChapter: true)
            syncProgressRemote()
            session.updateActiveChapter(chapter.id)
            considerLibraryAdd(chapterProgress: 0.55)
            prefetchNeighborChapters()
            if downloads.online {
                try? await APIClient.shared.readerStart(workId: workId, chapterId: chapter.id)
                let readableCount = max(chapters.filter(\.isAvailableEffective).count, 1)
                let readableIdx = chapters.prefix(index + 1).filter(\.isAvailableEffective).count
                try? await APIClient.shared.updateProgress(
                    workId: workId,
                    chapterId: chapter.id,
                    progress: Double(readableIdx) / Double(readableCount),
                    location: "page:0"
                )
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Keep current (+ next available) chapter on disk so offline reopen works.
    private func prefetchNeighborChapters() {
        guard downloads.online else { return }
        var indices: [Int] = []
        if chapters.indices.contains(chapterIndex), chapters[chapterIndex].isAvailableEffective {
            indices.append(chapterIndex)
        }
        if let next = chapters[(chapterIndex + 1)...].firstIndex(where: \.isAvailableEffective) {
            indices.append(next)
        }
        Task {
            for idx in indices {
                let chapter = chapters[idx]
                if offline.isChapterCached(workId: workId, chapterId: chapter.id) { continue }
                _ = try? await downloads.loadChapter(
                    workId: workId,
                    chapter: chapter,
                    sortIndex: idx,
                    store: offline
                )
            }
        }
    }

    private func nearestReadableIndex(from index: Int, direction: Int) -> Int? {
        guard direction != 0 else { return nil }
        var i = index + direction
        while chapters.indices.contains(i) {
            if chapters[i].isAvailableEffective { return i }
            i += direction
        }
        return nil
    }

    private func turnPage(by delta: Int, pageCount: Int) {
        let next = pageIndex + delta
        if next < 0 {
            if let prev = nearestReadableIndex(from: chapterIndex, direction: -1) {
                Task { await openChapter(at: prev) }
            }
            return
        }
        if next >= pageCount {
            if let nxt = nearestReadableIndex(from: chapterIndex, direction: 1) {
                Task { await openChapter(at: nxt) }
            }
            return
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            pageIndex = next
        }
        // brief chrome hide on turn feels nicer
        if showChrome {
            withAnimation { showChrome = false }
        }
    }

    private func toggleChrome() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showChrome.toggle()
        }
    }

    private func schedulePersistScroll() {
        persistScrollTask?.cancel()
        persistScrollTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            persistProgress()
            scheduleRemoteSync()
        }
    }

    /// Debounced push of chapter/progress to author.today so portal «Недавние» stays in sync.
    private func scheduleRemoteSync() {
        remoteSyncTask?.cancel()
        remoteSyncTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            syncProgressRemote()
        }
    }

    private func applyPendingPageRestoreIfNeeded(pageCount: Int) {
        guard pendingRestore, settings.pageTurnMode != .verticalScroll else { return }
        guard pageCount > 0 else { return }
        if restorePageIndex > 0 {
            pageIndex = min(restorePageIndex, max(pageCount - 1, 0))
        } else if restoreFraction > 0.01 {
            pageIndex = min(Int((restoreFraction * Double(max(pageCount - 1, 1))).rounded()), max(pageCount - 1, 0))
        }
        pendingRestore = false
        persistProgress()
    }

    private func persistProgress(forceChapter: Bool = false) {
        guard let chapter = currentChapter else { return }
        let fraction: Double
        let offset: Double
        let char: Int
        let page: Int
        if pendingRestore, restoreFraction > 0.005 || restoreOffsetY > 8 || restorePageIndex > 0 {
            fraction = max(restoreFraction, scrollFraction)
            offset = max(restoreOffsetY, scrollOffset)
            char = max(charOffset, 0)
            page = max(restorePageIndex, pageIndex)
        } else {
            fraction = scrollFraction
            offset = scrollOffset
            char = charOffset
            page = pageIndex
        }
        if forceChapter || fraction > 0.01 || page > 0 || offset > 8 || char > 40 {
            session.saveCheckpoint(
                workId: workId,
                chapterId: chapter.id,
                offsetY: offset,
                fraction: fraction,
                charOffset: char,
                pageIndex: page,
                allowZeroOverwrite: forceChapter
            )
        }
        let bookProgress: Double? = {
            guard !chapters.isEmpty else { return nil }
            // Whole-book %: finished chapters + position inside current one.
            let value = (Double(chapterIndex) + min(max(fraction, 0), 1)) / Double(chapters.count)
            return min(max(value, 0), 1)
        }()
        offline.saveProgress(
            workId: workId,
            chapterId: chapter.id,
            offsetY: offset,
            pageIndex: page,
            fraction: fraction,
            bookProgress: bookProgress,
            forceChapter: forceChapter
        )
        session.updateActiveChapter(chapter.id)
        publishWidgetResume()
    }

    private func publishWidgetResume() {
        WidgetResumeStore.save(
            workId: workId,
            chapterId: currentChapter?.id,
            title: details?.displayTitle ?? "Книга",
            chapterTitle: chapterTitle.isEmpty ? nil : chapterTitle,
            coverURL: details?.coverUrl
        )
    }

    private func requireProOrPaywall(_ reason: String) -> Bool {
        guard pro.isProUnlocked else {
            paywallReason = reason
            showPaywall = true
            return false
        }
        return true
    }

    private func addBookmarkTapped() {
        guard requireProOrPaywall("Закладки доступны в Читальне Pro.") else { return }
        guard let chapter = currentChapter else { return }
        let bm = ReadingBookmark(
            workId: workId,
            chapterId: chapter.id,
            workTitle: details?.displayTitle ?? "Книга",
            chapterTitle: chapterTitle.isEmpty ? chapter.displayTitle : chapterTitle,
            charOffset: charOffset,
            fraction: scrollFraction
        )
        modelContext.insert(bm)
        try? modelContext.save()
        withAnimation {
            bookmarkFlash = "Закладка сохранена"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation { bookmarkFlash = nil }
        }
    }

    private func noteTapped() {
        guard requireProOrPaywall("Заметки доступны в Читальне Pro.") else { return }
        noteDraft = ""
        showNoteComposer = true
    }

    private func saveNote() {
        guard let chapter = currentChapter else { return }
        let text = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let note = ReadingNote(
            workId: workId,
            chapterId: chapter.id,
            workTitle: details?.displayTitle ?? "Книга",
            chapterTitle: chapterTitle.isEmpty ? chapter.displayTitle : chapterTitle,
            body: text,
            charOffset: charOffset,
            fraction: scrollFraction
        )
        modelContext.insert(note)
        try? modelContext.save()
        showNoteComposer = false
        withAnimation { bookmarkFlash = "Заметка сохранена" }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation { bookmarkFlash = nil }
        }
    }

    private struct ChapterPosition {
        let chapterId: Int
        let offsetY: Double
        let fraction: Double
        let charOffset: Int
        let pageIndex: Int
        var hasInChapterProgress: Bool {
            fraction > 0.01 || pageIndex > 0 || offsetY > 8 || charOffset > 40
        }
    }

    private func bestCheckpoint(for chapterId: Int) -> ChapterPosition? {
        if let cp = session.checkpoint(for: workId), cp.chapterId == chapterId {
            return ChapterPosition(
                chapterId: cp.chapterId,
                offsetY: cp.offsetY,
                fraction: cp.fraction,
                charOffset: cp.charOffset,
                pageIndex: cp.pageIndex
            )
        }
        if let p = offline.progress(for: workId), p.chapterId == chapterId {
            var fraction = p.fraction
            if fraction < 0.005, p.offsetY > 8 {
                fraction = min(p.offsetY / 4000.0, 0.95)
            }
            return ChapterPosition(
                chapterId: p.chapterId,
                offsetY: p.offsetY,
                fraction: fraction,
                charOffset: 0,
                pageIndex: p.pageIndex
            )
        }
        return nil
    }

    private func syncProgressRemote() {
        guard downloads.online, let chapter = currentChapter else { return }
        // Book-level progress for the portal (0…1), not "chapter finished" alone.
        let fraction = max(scrollFraction, restoreFraction)
        let progress: Double = {
            guard !chapters.isEmpty else { return 0 }
            return min(max((Double(chapterIndex) + fraction) / Double(chapters.count), 0), 1)
        }()
        let offset = Int(max(scrollOffset, restoreOffsetY))
        let page = max(pageIndex, restorePageIndex)
        Task {
            try? await APIClient.shared.updateProgress(
                workId: workId,
                chapterId: chapter.id,
                progress: progress,
                location: "fraction:\(String(format: "%.4f", fraction));offset:\(offset);page:\(page)"
            )
        }
    }

    private func chapterReadProgress(page: Int, pages: Int) -> Double {
        guard pages > 0 else { return 0 }
        if pages == 1 {
            return plainText.count < 800 ? 1.0 : 0.55
        }
        return Double(page + 1) / Double(pages)
    }

    private func considerLibraryAdd(chapterProgress: Double) {
        guard !didAddToLibrary, chapterProgress >= 0.45 else { return }
        didAddToLibrary = true
        Task {
            do {
                if downloads.online {
                    try await offline.addToSiteLibrary(workId: workId, state: "Reading")
                } else if let details {
                    let meta = WorkMeta.stub(
                        id: details.id,
                        title: details.title,
                        author: details.displayAuthor,
                        coverUrl: details.coverUrl,
                        libraryState: "Reading"
                    )
                    offline.upsertWork(from: meta, markFromSite: true)
                    if let chapter = currentChapter {
                        offline.saveProgress(
                            workId: workId,
                            chapterId: chapter.id,
                            offsetY: scrollOffset,
                            pageIndex: pageIndex,
                            fraction: scrollFraction
                        )
                    }
                }
            } catch {
                didAddToLibrary = offline.isInLibrary(workId)
            }
        }
    }

    static func looksGarbled(_ text: String) -> Bool {
        guard text.count > 60 else { return false }
        let start = text.index(text.startIndex, offsetBy: min(40, text.count - 1))
        let sample = String(text[start...].prefix(500))
        let weird = sample.unicodeScalars.filter { scalar in
            let v = scalar.value
            return (v >= 0x0080 && v <= 0x024F) || (v >= 0x0370 && v <= 0x03FF)
        }.count
        return Double(weird) / Double(max(sample.count, 1)) > 0.08
    }

    /// Rough pagination by character budget based on viewport size.
    private func paginate(text: String, size: CGSize) -> [String] {
        let usableH = max(size.height - settings.marginVertical * 2 - 80, 120)
        let usableW = max(size.width - settings.marginHorizontal * 2, 120)
        let lineHeight = settings.fontSize + settings.lineSpacing
        let lines = max(Int(usableH / lineHeight), 8)
        let charsPerLine = max(Int(usableW / (settings.fontSize * 0.55)), 20)
        let budget = max(lines * charsPerLine, 200)

        if text.count <= budget { return [text] }

        var pages: [String] = []
        var rest = text[...]
        while !rest.isEmpty {
            if rest.count <= budget {
                pages.append(String(rest))
                break
            }
            let end = rest.index(rest.startIndex, offsetBy: budget)
            var split = end
            // prefer paragraph / space break
            if let para = rest[..<end].lastIndex(of: "\n") {
                split = para
            } else if let space = rest[..<end].lastIndex(of: " ") {
                split = space
            }
            let page = String(rest[..<split]).trimmingCharacters(in: .whitespacesAndNewlines)
            pages.append(page.isEmpty ? String(rest[..<end]) : page)
            rest = rest[split...].drop(while: { $0 == "\n" || $0 == " " })
        }
        return pages.isEmpty ? [text] : pages
    }
}
