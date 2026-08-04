import SwiftUI
import UIKit

struct ReaderView: View {
    let workId: Int
    let initialChapterId: Int?

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
    @State private var showChrome = true
    @State private var showSettings = false
    @State private var showTOC = false
    @State private var pageIndex = 0
    @State private var scrollOffset: Double = 0

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
                VStack(spacing: 12) {
                    Text(error)
                        .foregroundStyle(settings.textColor)
                        .multilineTextAlignment(.center)
                    Button("Повторить") { Task { await bootstrap() } }
                }
                .padding()
            } else {
                readerContent
                    .opacity(showChrome ? 1 : 1)
            }

            if showChrome {
                VStack {
                    topBar
                    Spacer()
                    bottomBar
                }
                .transition(.opacity)
            }
        }
        .navigationBarHidden(true)
        .statusBarHidden(!showChrome)
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
                    // near end — optional auto next chapter could go here
                }
                persistProgress()
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
            if let progress = offline.progress(for: workId) {
                pageIndex = progress.pageIndex
                scrollOffset = progress.offsetY
            }
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
            if downloads.online {
                try? await APIClient.shared.readerStart(workId: workId, chapterId: chapter.id)
            }
        } catch {
            self.error = error.localizedDescription
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
