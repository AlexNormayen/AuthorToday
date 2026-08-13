import SwiftUI
import UIKit

/// Chapter-based reader for locally imported books (no Author.Today API).
struct LocalReaderView: View {
    let bookId: UUID

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var localLibrary: LocalLibraryStore
    @EnvironmentObject private var settings: ReaderSettingsStore

    @State private var bookTitle = "Чтение"
    @State private var chapters: [LocalChapter] = []
    @State private var chapterIndex = 0
    @State private var chapterTitle = ""
    @State private var plainText = ""
    @State private var isLoading = true
    @State private var error: String?
    @State private var showChrome = false
    @State private var showSettings = false
    @State private var showTOC = false
    @State private var pageIndex = 0
    @State private var scrollOffset: Double = 0
    @State private var scrollFraction: Double = 0
    @State private var charOffset: Int = 0
    @State private var pageCountForChapter = 1
    @State private var pendingRestore = false
    @State private var restorePageIndex = 0
    @State private var restoreOffsetY: Double = 0
    @State private var restoreFraction: Double = 0
    @State private var restoreGeneration = 0
    @State private var persistScrollTask: Task<Void, Never>?
    @State private var chapterContentFits = false

    var body: some View {
        ZStack {
            readerBackground

            if isLoading {
                VStack(spacing: 20) {
                    LoadingStateView(title: "Открываем книгу…")
                    Button("Закрыть") { dismiss() }
                        .buttonStyle(.bordered)
                        .tint(settings.textColor)
                }
            } else if let error {
                VStack(spacing: 16) {
                    Text(error)
                        .foregroundStyle(settings.textColor)
                        .multilineTextAlignment(.center)
                    Button("Назад") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }
                .padding(24)
            } else {
                readerContent
            }

            if error == nil, !isLoading, !showChrome, showEndOfChapterCTA {
                VStack {
                    Spacer(minLength: 0)
                    endOfChapterBar
                }
            }

            if showChrome || error != nil {
                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: 0)
                    if error == nil {
                        bottomBar
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .statusBarHidden(!showChrome && error == nil)
        .preferredColorScheme(
            (showChrome || error != nil)
                ? (chromePrefersDark ? .dark : .light)
                : nil
        )
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
                List {
                    ForEach(Array(chapters.enumerated()), id: \.element.id) { idx, chapter in
                        Button {
                            showTOC = false
                            openChapter(at: idx, restore: false)
                        } label: {
                            HStack {
                                Text(chapter.title)
                                Spacer()
                                if idx == chapterIndex {
                                    Image(systemName: "checkmark")
                                }
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
        .task { bootstrap() }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = settings.keepScreenOn
        }
        .onChange(of: settings.keepScreenOn) { _, on in
            UIApplication.shared.isIdleTimerDisabled = on
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .inactive || phase == .background {
                persistScrollTask?.cancel()
                persistProgress()
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            persistScrollTask?.cancel()
            persistProgress()
        }
    }

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
        case .horizontalSwipe, .curlStyle, .tapAndSwipe, .tapZones:
            GeometryReader { geo in
                pagedReaderContent(size: geo.size)
            }
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
        .onChange(of: pageIndex) { _, newValue in
            pageCountForChapter = max(pages.count, 1)
            if pendingRestore { return }
            let fraction = pages.count <= 1 ? 0.0 : Double(newValue) / Double(pages.count - 1)
            scrollFraction = fraction
            charOffset = Int(Double(plainText.count) * fraction)
            persistProgress()
        }
        .onAppear {
            pageCountForChapter = max(pages.count, 1)
            applyPendingPageRestoreIfNeeded(pageCount: pages.count)
        }
        .onChange(of: pages.count) { _, newCount in
            applyPendingPageRestoreIfNeeded(pageCount: newCount)
        }
    }

    private var chromePrefersDark: Bool {
        if let scheme = settings.appColorScheme { return scheme == .dark }
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
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)

            VStack(alignment: .leading, spacing: 2) {
                Text(bookTitle)
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
                (chromePrefersDark ? Color.black : Color.white).opacity(0.94)
                Rectangle().fill(.ultraThinMaterial)
            }
            .ignoresSafeArea(edges: .top)
        }
    }

    private var isAtChapterEnd: Bool {
        guard !pendingRestore, !plainText.isEmpty else { return false }
        if settings.pageTurnMode == .verticalScroll {
            return scrollFraction >= 0.90 || chapterContentFits
        }
        return pageCountForChapter > 0 && pageIndex + 1 >= pageCountForChapter
    }

    private var showEndOfChapterCTA: Bool {
        isAtChapterEnd && chapterIndex + 1 < chapters.count
    }

    private var endOfChapterBar: some View {
        Button {
            openChapter(at: chapterIndex + 1, restore: false)
        } label: {
            Label("Следующая глава", systemImage: "chevron.right")
                .font(.subheadline.weight(.semibold))
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
    }

    private var bottomBar: some View {
        let paged = settings.pageTurnMode != .verticalScroll
        let canPrevChapter = chapterIndex > 0
        let canNextChapter = chapterIndex + 1 < chapters.count
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
                    navigate(direction: -1, paged: paged)
                } label: {
                    Label(paged ? "Назад" : "Пред. глава", systemImage: "chevron.left")
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
                    navigate(direction: 1, paged: paged)
                } label: {
                    Label(paged ? "Вперёд" : "След. глава", systemImage: "chevron.right")
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
                .disabled(!canGoForward)
                .opacity(canGoForward ? 1 : 0.35)
            }
        }
        .foregroundStyle(chromeForeground)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            ZStack {
                (chromePrefersDark ? Color.black : Color.white).opacity(0.94)
                Rectangle().fill(.ultraThinMaterial)
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private func bottomProgressLabel(paged: Bool) -> String {
        let chapterPart = "Глава \(chapterIndex + 1)/\(max(chapters.count, 1))"
        if paged {
            return "\(chapterPart) · стр. \(pageIndex + 1)/\(max(pageCountForChapter, 1))"
        }
        let pct = Int((scrollFraction * 100).rounded())
        return "\(chapterPart) · \(pct)%"
    }

    private func toggleChrome() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showChrome.toggle()
        }
    }

    private func navigate(direction: Int, paged: Bool) {
        if paged {
            let next = pageIndex + direction
            if next >= 0, next < pageCountForChapter {
                pageIndex = next
                return
            }
        }
        let target = chapterIndex + direction
        guard chapters.indices.contains(target) else { return }
        openChapter(at: target, restore: false)
    }

    private func turnPage(by delta: Int, pageCount: Int) {
        let next = pageIndex + delta
        guard next >= 0, next < pageCount else {
            let target = chapterIndex + (delta > 0 ? 1 : -1)
            if chapters.indices.contains(target) {
                openChapter(at: target, restore: false)
            }
            return
        }
        pageIndex = next
    }

    private func bootstrap() {
        isLoading = true
        error = nil
        guard let book = localLibrary.book(id: bookId) else {
            error = "Книга не найдена"
            isLoading = false
            return
        }
        bookTitle = book.title
        chapters = localLibrary.sortedChapters(for: book)
        guard !chapters.isEmpty else {
            error = "В файле нет текста"
            isLoading = false
            return
        }
        let start = min(max(book.lastChapterIndex, 0), chapters.count - 1)
        openChapter(at: start, restore: true, book: book)
        isLoading = false
    }

    private func openChapter(at index: Int, restore: Bool, book: LocalBook? = nil) {
        guard chapters.indices.contains(index) else { return }
        let chapter = chapters[index]
        chapterIndex = index
        chapterTitle = chapter.title
        plainText = HTMLText.withChapterHeading(chapter.title, body: chapter.readerPlain)
        pageIndex = 0
        scrollOffset = 0
        scrollFraction = 0
        charOffset = 0
        chapterContentFits = false

        if restore, let book = book ?? localLibrary.book(id: bookId), book.lastChapterIndex == index {
            restorePageIndex = book.chapterPageIndex
            restoreOffsetY = book.chapterOffsetY
            restoreFraction = book.chapterFraction
            scrollOffset = book.chapterOffsetY
            scrollFraction = book.chapterFraction
            pageIndex = book.chapterPageIndex
            pendingRestore = book.chapterFraction > 0.01 || book.chapterPageIndex > 0 || book.chapterOffsetY > 8
            if settings.pageTurnMode == .verticalScroll, book.chapterFraction > 0.005 {
                restoreGeneration += 1
            }
        } else {
            pendingRestore = false
            restorePageIndex = 0
            restoreOffsetY = 0
            restoreFraction = 0
        }
        persistProgress()
    }

    private func handleScroll(offsetY: Double, fraction: Double, charOffset: Int) {
        if pendingRestore {
            let target = restoreFraction
            let closeEnough = target <= 0.01 || fraction + 0.03 >= target
            if fraction <= 0.01 || !closeEnough { return }
            pendingRestore = false
        }
        scrollOffset = offsetY
        scrollFraction = fraction
        if fraction > 0.005 {
            restoreFraction = fraction
            restoreOffsetY = offsetY
        }
        if charOffset > 0 {
            self.charOffset = charOffset
        }
        schedulePersistScroll()
    }

    private func schedulePersistScroll() {
        persistScrollTask?.cancel()
        persistScrollTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            persistProgress()
        }
    }

    private func applyPendingPageRestoreIfNeeded(pageCount: Int) {
        guard pendingRestore, settings.pageTurnMode != .verticalScroll else { return }
        guard pageCount > 0 else { return }
        if restorePageIndex > 0 {
            pageIndex = min(restorePageIndex, max(pageCount - 1, 0))
        } else if restoreFraction > 0.01 {
            pageIndex = min(
                Int((restoreFraction * Double(max(pageCount - 1, 1))).rounded()),
                max(pageCount - 1, 0)
            )
        }
        pendingRestore = false
        persistProgress()
    }

    private func persistProgress() {
        guard !chapters.isEmpty else { return }
        let fraction: Double
        let offset: Double
        let page: Int
        if pendingRestore, restoreFraction > 0.005 || restoreOffsetY > 8 || restorePageIndex > 0 {
            fraction = max(restoreFraction, scrollFraction)
            offset = max(restoreOffsetY, scrollOffset)
            page = max(restorePageIndex, pageIndex)
        } else {
            fraction = scrollFraction
            offset = scrollOffset
            page = pageIndex
        }
        localLibrary.saveProgress(
            bookId: bookId,
            chapterIndex: chapterIndex,
            offsetY: offset,
            fraction: fraction,
            pageIndex: page
        )
    }

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
            var cut = end
            if let space = rest[..<end].lastIndex(of: " ") {
                cut = space
            } else if let nl = rest[..<end].lastIndex(of: "\n") {
                cut = nl
            }
            pages.append(String(rest[..<cut]))
            rest = rest[cut...].drop(while: { $0 == " " || $0 == "\n" })
        }
        return pages.isEmpty ? [""] : pages
    }
}
