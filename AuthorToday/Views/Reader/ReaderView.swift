import SwiftUI
import UIKit

struct ReaderView: View {
    let workId: Int
    let initialChapterId: Int?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var settings: ReaderSettingsStore

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
    @State private var pageIndex = 0
    @State private var scrollOffset: Double = 0
    @State private var didAddToLibrary = false
    @State private var pageCountForChapter = 1

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
                VStack {
                    topBar
                    Spacer()
                    if error == nil {
                        bottomBar
                    }
                }
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
        .sheet(isPresented: $showTOC) {
            NavigationStack {
                List(Array(chapters.enumerated()), id: \.element.id) { idx, chapter in
                    Button {
                        showTOC = false
                        Task { await openChapter(at: idx) }
                    } label: {
                        HStack {
                            Text(chapter.displayTitle)
                            Spacer()
                            if idx == chapterIndex {
                                Image(systemName: "book.fill")
                                    .foregroundStyle(AppTheme.moss)
                            }
                        }
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
        .onChange(of: settings.keepScreenOn) { _, on in
            UIApplication.shared.isIdleTimerDisabled = on
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            persistProgress()
            syncProgressRemote()
        }
    }

    // MARK: - Layers

    private var readerBackground: some View {
        ZStack {
            settings.solidBackground.ignoresSafeArea()
            if let image = settings.backgroundImage {
                image
                    .resizable()
                    .scaledToFill()
                    .opacity(settings.backgroundImageOpacity)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
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
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ScrollOffsetKey.self,
                            value: -geo.frame(in: .named("readerScroll")).minY
                        )
                    }
                )
        }
        .coordinateSpace(name: "readerScroll")
        .onPreferenceChange(ScrollOffsetKey.self) { value in
            scrollOffset = value
            // Approximate half-chapter by scroll depth vs content heuristic
            let approx = min(max(value / 1200.0, 0), 1)
            considerLibraryAdd(chapterProgress: approx)
        }
        .simultaneousGesture(
            TapGesture().onEnded { toggleChrome() }
        )
    }

    private var pagedReader: some View {
        GeometryReader { geo in
            let pages = paginate(text: plainText, size: geo.size)
            let mode = settings.pageTurnMode

            ZStack {
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
                pageIndex = 0
            }
            .onChange(of: pageIndex) { _, newValue in
                if newValue >= pages.count - 1 {
                    // near end
                }
                pageCountForChapter = max(pages.count, 1)
                persistProgress()
                considerLibraryAdd(chapterProgress: chapterReadProgress(page: newValue, pages: pages.count))
            }
            .onAppear {
                pageCountForChapter = max(pages.count, 1)
            }
        }
    }

    private var topBar: some View {
        HStack {
            DismissReaderButton()
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
                Task { await openChapter(at: chapterIndex - 1) }
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
            }
            .disabled(chapterIndex <= 0)

            Spacer()

            Text("\(chapterIndex + 1) / \(max(chapters.count, 1))")
                .font(.caption.monospacedDigit())

            Spacer()

            Button {
                Task { await openChapter(at: chapterIndex + 1) }
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
            }
            .disabled(chapterIndex >= chapters.count - 1)
        }
        .foregroundStyle(settings.textColor)
        .padding(.horizontal, 12)
        .background(.ultraThinMaterial.opacity(0.92))
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
            chapters = result.details.availableChapters
            if let idx = chapters.firstIndex(where: { $0.id == result.chapterId }) {
                chapterIndex = idx
            }
            html = result.html
            chapterTitle = result.title
            plainText = HTMLText.plain(from: result.html)
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
                plainText = HTMLText.plain(from: reloaded.html)
            }
            if let progress = offline.progress(for: workId) {
                pageIndex = progress.pageIndex
                scrollOffset = progress.offsetY
            }
            didAddToLibrary = offline.isInLibrary(workId)
            persistProgress()
            prefetchNeighborChapters()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func openChapter(at index: Int) async {
        guard chapters.indices.contains(index) else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let chapter = chapters[index]
            let loaded = try await downloads.loadChapter(
                workId: workId,
                chapter: chapter,
                sortIndex: index,
                store: offline
            )
            chapterIndex = index
            chapterTitle = loaded.title
            html = loaded.html
            plainText = HTMLText.plain(from: loaded.html)
            pageIndex = 0
            persistProgress()
            syncProgressRemote()
            prefetchNeighborChapters()
            if downloads.online {
                try? await APIClient.shared.readerStart(workId: workId, chapterId: chapter.id)
                try? await APIClient.shared.updateProgress(
                    workId: workId,
                    chapterId: chapter.id,
                    progress: chapters.isEmpty ? nil : Double(index + 1) / Double(chapters.count),
                    location: "page:0"
                )
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Keep current (+ next) chapter on disk so offline reopen works.
    private func prefetchNeighborChapters() {
        guard downloads.online else { return }
        let indices = [chapterIndex, chapterIndex + 1].filter { chapters.indices.contains($0) }
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

    private func turnPage(by delta: Int, pageCount: Int) {
        let next = pageIndex + delta
        if next < 0 {
            Task { await openChapter(at: chapterIndex - 1) }
            return
        }
        if next >= pageCount {
            Task { await openChapter(at: chapterIndex + 1) }
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

    private func persistProgress() {
        guard let chapter = currentChapter else { return }
        offline.saveProgress(
            workId: workId,
            chapterId: chapter.id,
            offsetY: scrollOffset,
            pageIndex: pageIndex
        )
    }

    private func syncProgressRemote() {
        guard downloads.online, let chapter = currentChapter else { return }
        let progress = chapters.isEmpty ? 0.0 : Double(chapterIndex + 1) / Double(chapters.count)
        Task {
            try? await APIClient.shared.updateProgress(
                workId: workId,
                chapterId: chapter.id,
                progress: progress,
                location: "page:\(pageIndex)"
            )
        }
    }

    private func chapterReadProgress(page: Int, pages: Int) -> Double {
        guard pages > 0 else { return 0 }
        if pages == 1 {
            // Single-page chapter: count as fully readable once opened and chrome toggled / short delay
            return plainText.count < 800 ? 1.0 : 0.55
        }
        return Double(page + 1) / Double(pages)
    }

    private func considerLibraryAdd(chapterProgress: Double) {
        guard !didAddToLibrary, chapterProgress >= 0.5, downloads.online else { return }
        didAddToLibrary = true
        Task {
            try? await offline.addToSiteLibrary(workId: workId, state: "Reading")
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

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: Double = 0
    static func reduce(value: inout Double, nextValue: () -> Double) {
        value = nextValue()
    }
}

private struct DismissReaderButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(.body.weight(.semibold))
                .frame(width: 36, height: 36)
        }
    }
}
