import SwiftUI
import UIKit

struct ReaderView: View {
    let workId: Int
    let initialChapterId: Int?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var settings: ReaderSettingsStore
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
    @State private var pageIndex = 0
    @State private var scrollOffset: Double = 0
    @State private var didAddToLibrary = false
    @State private var pageCountForChapter = 1
    @State private var pendingRestore = false
    @State private var restorePageIndex = 0
    @State private var restoreOffsetY: Double = 0
    @State private var persistScrollTask: Task<Void, Never>?
    @State private var restoreRetryTask: Task<Void, Never>?
    @State private var scrollViewRef: UIScrollView?
    /// After programmatic restore, ignore offset noise that reports 0.
    @State private var ignoreScrollTrackingUntil: Date = .distantPast
    @State private var didStartSession = false

    private var currentChapter: ChapterMeta? {
        chapters.indices.contains(chapterIndex) ? chapters[chapterIndex] : nil
    }

    var body: some View {
        ZStack {
            readerBackground

            if isLoading {
                ProgressView("Открываем книгу…")
                    .tint(settings.textColor)
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
                    Button("Назад в библиотеку") { dismiss() }
                        .foregroundStyle(settings.textColor)
                }
                .padding(24)
            } else {
                readerContent
            }

            if showChrome || error != nil {
                VStack(spacing: 0) {
                    topBar
                        .padding(.top, 4)
                    Spacer()
                    if error == nil {
                        bottomBar
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .transition(.opacity)
            }
        }
        .navigationBarHidden(true)
        .statusBarHidden(!showChrome && error == nil)
        .toolbar(.hidden, for: .tabBar)
        .toolbar(.hidden, for: .navigationBar)
        .ignoresSafeArea(edges: (showChrome || error != nil) ? [] : .all)
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
        .task {
            await bootstrap()
            UIApplication.shared.isIdleTimerDisabled = settings.keepScreenOn
        }
        .onAppear {
            if !didStartSession {
                didStartSession = true
                session.beginReading(workId: workId, chapterId: initialChapterId)
            }
        }
        .onChange(of: settings.keepScreenOn) { _, on in
            UIApplication.shared.isIdleTimerDisabled = on
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .inactive || phase == .background {
                persistScrollTask?.cancel()
                persistProgress()
                syncProgressRemote()
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            persistScrollTask?.cancel()
            restoreRetryTask?.cancel()
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
        ScrollView {
            Text(plainText)
                .font(settings.fontFamily.font(size: settings.fontSize))
                .foregroundStyle(settings.textColor)
                .lineSpacing(settings.lineSpacing)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, settings.marginHorizontal)
                .padding(.vertical, settings.marginVertical + (showChrome ? 56 : 12))
        }
        .background(
            ScrollViewTracker(scrollView: $scrollViewRef) { y in
                handleScrollOffset(y)
            }
        )
        .onChange(of: scrollViewRef) { _, _ in
            applyPendingScrollRestoreIfNeeded()
        }
        .onAppear {
            applyPendingScrollRestoreIfNeeded()
        }
        .simultaneousGesture(
            TapGesture().onEnded { toggleChrome() }
        )
    }

    private func handleScrollOffset(_ value: Double) {
        if pendingRestore { return }
        if Date() < ignoreScrollTrackingUntil { return }
        // Ignore tiny layout jitter near zero right after appear.
        if abs(value - scrollOffset) < 0.5 { return }
        scrollOffset = value
        let approx = min(max(value / 1200.0, 0), 1)
        considerLibraryAdd(chapterProgress: approx)
        // Immediate UserDefaults checkpoint — survives kill before debounce fires.
        if let chapter = currentChapter {
            session.saveCheckpoint(
                workId: workId,
                chapterId: chapter.id,
                offsetY: value,
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
                    Text(page)
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
            if let chapter = currentChapter {
                session.saveCheckpoint(
                    workId: workId,
                    chapterId: chapter.id,
                    offsetY: scrollOffset,
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

    private var topBar: some View {
        HStack {
            Button {
                persistProgress()
                session.endReading()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(details?.displayTitle ?? "Чтение")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(chapterTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button { showTOC = true } label: {
                Image(systemName: "list.bullet")
            }
            Button { showSettings = true } label: {
                Image(systemName: "textformat.size")
            }
        }
        .foregroundStyle(settings.textColor)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial.opacity(0.92))
    }

    private var bottomBar: some View {
        HStack {
            Button {
                if let prev = nearestReadableIndex(from: chapterIndex, direction: -1) {
                    Task { await openChapter(at: prev) }
                }
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
            }
            .disabled(nearestReadableIndex(from: chapterIndex, direction: -1) == nil)

            Spacer()

            Text("\(chapterIndex + 1) / \(max(chapters.count, 1))")
                .font(.caption.monospacedDigit())

            Spacer()

            Button {
                if let next = nearestReadableIndex(from: chapterIndex, direction: 1) {
                    Task { await openChapter(at: next) }
                }
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
            }
            .disabled(nearestReadableIndex(from: chapterIndex, direction: 1) == nil)
        }
        .foregroundStyle(settings.textColor)
        .padding(.horizontal, 12)
        .background(.ultraThinMaterial.opacity(0.92))
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
            let result = try await downloads.openAndCache(
                workId: workId,
                preferredChapterId: initialChapterId,
                store: offline
            )
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
            plainText = HTMLText.readerPlain(from: result.html)
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
                plainText = HTMLText.readerPlain(from: reloaded.html)
            }
            if let progress = bestCheckpoint(for: result.chapterId) {
                restorePageIndex = progress.pageIndex
                restoreOffsetY = progress.offsetY
                scrollOffset = progress.offsetY
                pageIndex = progress.pageIndex
                pendingRestore = progress.pageIndex > 0 || progress.offsetY > 8
            } else {
                pendingRestore = false
                restorePageIndex = 0
                restoreOffsetY = 0
            }
            didAddToLibrary = offline.isInLibrary(workId)
            // Opening a book to read → ensure it appears in the library.
            if !didAddToLibrary, downloads.online {
                considerLibraryAdd(chapterProgress: 1)
            }
            session.beginReading(workId: workId, chapterId: result.chapterId)
            // Persist chapter/page immediately; keep offsetY from saved progress (do not zero it).
            persistProgress()
            prefetchNeighborChapters()
            scheduleRestoreRetries()
        } catch {
            self.error = error.localizedDescription
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
            plainText = HTMLText.readerPlain(from: loaded.html)
            pageIndex = 0
            scrollOffset = 0
            pendingRestore = false
            restoreOffsetY = 0
            restorePageIndex = 0
            restoreRetryTask?.cancel()
            persistProgress()
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
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            guard !pendingRestore else { return }
            persistProgress()
        }
    }

    /// Retries restore until ScrollView has laid out enough content (or gives up).
    private func scheduleRestoreRetries() {
        restoreRetryTask?.cancel()
        guard pendingRestore else { return }
        restoreRetryTask = Task { @MainActor in
            let delaysNs: [UInt64] = [
                50_000_000, 150_000_000, 300_000_000, 500_000_000,
                800_000_000, 1_200_000_000, 2_000_000_000
            ]
            for delay in delaysNs {
                guard !Task.isCancelled, pendingRestore else { return }
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled, pendingRestore else { return }
                applyPendingScrollRestoreIfNeeded()
            }
            // Give up quietly — keep saved offset for next open rather than wiping it.
            if pendingRestore {
                pendingRestore = false
            }
        }
    }

    private func applyPendingScrollRestoreIfNeeded() {
        guard pendingRestore else { return }

        if settings.pageTurnMode != .verticalScroll {
            // Paged modes restore via pageIndex.
            return
        }

        guard restoreOffsetY > 8 else {
            pendingRestore = false
            return
        }
        guard let scroll = scrollViewRef else { return }

        // Wait until text has a real height — early restore clamps to 0 and loses place.
        let maxY = max(scroll.contentSize.height - scroll.bounds.height, 0)
        if maxY < restoreOffsetY * 0.5, maxY < 80 {
            return
        }

        let y = min(max(restoreOffsetY, 0), Double(maxY))
        scroll.setContentOffset(CGPoint(x: 0, y: y), animated: false)
        scrollOffset = y
        ignoreScrollTrackingUntil = Date().addingTimeInterval(0.5)
        pendingRestore = false
        // Re-save after successful restore so a zeroed intermediate write cannot stick.
        persistProgress()
    }

    private func applyPendingPageRestoreIfNeeded(pageCount: Int) {
        guard pendingRestore, settings.pageTurnMode != .verticalScroll else { return }
        guard pageCount > 0 else { return }
        pageIndex = min(max(restorePageIndex, 0), max(pageCount - 1, 0))
        pendingRestore = false
        persistProgress()
    }

    private func liveScrollOffset() -> Double {
        if settings.pageTurnMode == .verticalScroll,
           let scroll = scrollViewRef {
            return Double(scroll.contentOffset.y)
        }
        return scrollOffset
    }

    private func persistProgress() {
        guard let chapter = currentChapter else { return }
        // Never persist a zeroed scroll while we still owe a restore from disk.
        let offset: Double
        if pendingRestore, restoreOffsetY > 8 {
            offset = restoreOffsetY
        } else {
            offset = liveScrollOffset()
            scrollOffset = offset
        }
        let page = pendingRestore && settings.pageTurnMode != .verticalScroll
            ? max(restorePageIndex, pageIndex)
            : pageIndex
        offline.saveProgress(
            workId: workId,
            chapterId: chapter.id,
            offsetY: offset,
            pageIndex: page
        )
        session.updateActiveChapter(chapter.id)
    }

    private struct ChapterPosition {
        let chapterId: Int
        let offsetY: Double
        let pageIndex: Int
    }

    private func bestCheckpoint(for chapterId: Int) -> ChapterPosition? {
        let sessionCP = session.checkpoint(for: workId)
        let offlineCP = offline.progress(for: workId)

        let candidates: [ChapterPosition] = [
            sessionCP.map { ChapterPosition(chapterId: $0.chapterId, offsetY: $0.offsetY, pageIndex: $0.pageIndex) },
            offlineCP.map { ChapterPosition(chapterId: $0.chapterId, offsetY: $0.offsetY, pageIndex: $0.pageIndex) }
        ].compactMap { $0 }

        // Prefer checkpoint for the chapter we actually opened.
        if let match = candidates.first(where: { $0.chapterId == chapterId && ($0.offsetY > 8 || $0.pageIndex > 0) })
            ?? candidates.first(where: { $0.chapterId == chapterId }) {
            return match
        }
        return nil
    }

    private func syncProgressRemote() {
        guard downloads.online, let chapter = currentChapter else { return }
        let progress = chapters.isEmpty ? 0.0 : Double(chapterIndex + 1) / Double(chapters.count)
        let offset = Int(liveScrollOffset())
        let page = pageIndex
        Task {
            try? await APIClient.shared.updateProgress(
                workId: workId,
                chapterId: chapter.id,
                progress: progress,
                location: "offset:\(offset);page:\(page)"
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
                            pageIndex: pageIndex
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

/// Finds the enclosing UIScrollView and observes contentOffset via KVO (more reliable than PreferenceKey).
private struct ScrollViewTracker: UIViewRepresentable {
    @Binding var scrollView: UIScrollView?
    var onOffsetChange: (Double) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onOffsetChange: onOffsetChange)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onOffsetChange = onOffsetChange
        DispatchQueue.main.async {
            guard let found = Self.findScrollView(from: uiView) else { return }
            if scrollView !== found {
                scrollView = found
            }
            context.coordinator.attach(found)
        }
    }

    final class Coordinator {
        var onOffsetChange: (Double) -> Void
        private var observation: NSKeyValueObservation?
        private weak var observed: UIScrollView?

        init(onOffsetChange: @escaping (Double) -> Void) {
            self.onOffsetChange = onOffsetChange
        }

        func attach(_ scroll: UIScrollView) {
            guard observed !== scroll else { return }
            observation?.invalidate()
            observed = scroll
            observation = scroll.observe(\.contentOffset, options: [.new]) { [weak self] sv, _ in
                let y = Double(sv.contentOffset.y)
                DispatchQueue.main.async {
                    self?.onOffsetChange(y)
                }
            }
        }

        deinit {
            observation?.invalidate()
        }
    }

    private static func findScrollView(from view: UIView) -> UIScrollView? {
        var current: UIView? = view
        while let c = current {
            if let scroll = c as? UIScrollView { return scroll }
            current = c.superview
        }
        return nil
    }
}
