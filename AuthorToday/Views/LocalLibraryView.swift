import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// Standalone entry (kept for previews / deep links). Main UX embeds `LocalLibraryPane` in `LibraryView`.
struct LocalLibraryView: View {
    @EnvironmentObject private var appearance: AppAppearanceStore

    var body: some View {
        NavigationStack {
            LocalLibraryPane()
                .background {
                    ThemeAtmosphereView(preset: appearance.themePreset)
                }
                .navigationTitle("Мои книги")
                .navigationBarTitleDisplayMode(.large)
                .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}

struct LocalLibraryPane: View {
    @EnvironmentObject private var localLibrary: LocalLibraryStore
    @EnvironmentObject private var pro: ProEntitlementStore
    @EnvironmentObject private var appearance: AppAppearanceStore
    @State private var showImporter = false
    @State private var showPaywall = false
    @State private var importError: String?
    @State private var readerBookId: UUID?

    private var canImportMore: Bool {
        localLibrary.canImportLocalBook(isProUnlocked: pro.isProUnlocked)
    }

    private var isInFreeCooldown: Bool {
        guard !pro.isProUnlocked,
              let next = localLibrary.nextFreeImportAvailableAt else { return false }
        return Date() < next
    }

    var body: some View {
        Group {
            if localLibrary.books.isEmpty {
                ContentUnavailableView {
                    Label("Мои книги", systemImage: "tray.and.arrow.down")
                } description: {
                    Text(emptyDescription)
                } actions: {
                    Button(emptyPrimaryTitle) {
                        if canImportMore {
                            showImporter = true
                        } else {
                            showPaywall = true
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .themedEmptyStateCard()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if !pro.isProUnlocked {
                        Section {
                            Text(quotaHint)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .themedReadableText()
                                .themedPanelRow()
                        }
                        .listRowSeparator(.hidden)
                    }
                    ForEach(localLibrary.books, id: \.id) { book in
                        Button {
                            readerBookId = book.id
                        } label: {
                            bookRow(book)
                        }
                        .themedPanelRow()
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task {
                                    await BookVaultSync.shared.deleteLocalBookEverywhere(
                                        book,
                                        localStore: localLibrary
                                    )
                                }
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.themePreset, appearance.themePreset)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if canImportMore {
                        showImporter = true
                    } else {
                        showPaywall = true
                    }
                } label: {
                    Image(systemName: canImportMore ? "plus" : "lock.fill")
                }
                .disabled(localLibrary.isImporting)
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.plainText, .epub],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .alert("Импорт", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .sheet(isPresented: $showPaywall) {
            ProPaywallView(reason: paywallReason)
                .environmentObject(OfflineStore.shared)
        }
        .fullScreenCover(item: Binding(
            get: { readerBookId.map { LocalReaderItem(id: $0) } },
            set: { readerBookId = $0?.id }
        )) { item in
            NavigationStack {
                LocalReaderView(bookId: item.id)
            }
        }
        .onAppear {
            localLibrary.reload()
            let n = localLibrary.importNewFilesFromDocuments()
            if n > 0 {
                importError = "Добавлено из Файлов: \(n)"
            }
        }
    }

    private var emptyPrimaryTitle: String {
        if canImportMore { return "Добавить файл" }
        if isInFreeCooldown { return "Открыть Pro" }
        return "Открыть Pro"
    }

    private var paywallReason: String {
        if isInFreeCooldown, let next = localLibrary.nextFreeImportAvailableAt {
            let formatted = next.formatted(date: .abbreviated, time: .omitted)
            return "После удаления бесплатной книги следующий файл — с \(formatted). Pro снимает лимит сразу."
        }
        return "Бесплатно — \(ProFeatures.freeLocalLibraryLimit) своя книга. После удаления повтор через \(ProFeatures.freeLocalLibraryCooldownDays) дней. Pro — без лимита."
    }

    private var emptyDescription: String {
        if pro.isProUnlocked {
            return "Добавьте TXT или EPUB. Книги можно выгрузить на облачную полку VPS и восстановить после переустановки. Также подхватываются файлы из папки «Читальня» в Файлах."
        }
        if isInFreeCooldown, let next = localLibrary.nextFreeImportAvailableAt {
            let formatted = next.formatted(date: .abbreviated, time: .omitted)
            return "Бесплатный слот на перезарядке до \(formatted). Досрочно — в Читальня Pro."
        }
        return "Бесплатно — \(ProFeatures.freeLocalLibraryLimit) файл (TXT/EPUB). Удалите — следующий бесплатный через \(ProFeatures.freeLocalLibraryCooldownDays) дней. Без лимита — в Pro."
    }

    private var quotaHint: String {
        let used = localLibrary.books.count
        let limit = ProFeatures.freeLocalLibraryLimit
        if used >= limit {
            return "Бесплатный слот занят (\(used)/\(limit)). Удаление запускает паузу \(ProFeatures.freeLocalLibraryCooldownDays) дней до следующей бесплатной загрузки. Pro — без лимита."
        }
        return "Бесплатно: \(used)/\(limit). Pro снимает лимит."
    }

    private func bookRow(_ book: LocalBook) -> some View {
        HStack(spacing: 12) {
            LocalBookCoverView(book: book, width: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Text(book.format.rawValue.uppercased())
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(appearance.accent.opacity(0.22), in: Capsule())
                    if !book.author.isEmpty {
                        Text(book.author)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text("\(book.displayProgressPercent)%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .themedReadableText()
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard canImportMore else {
            showPaywall = true
            return
        }
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let book = try localLibrary.importFile(from: url)
                readerBookId = book.id
            } catch {
                importError = error.localizedDescription
            }
        }
    }
}

/// Cover art or a stable gradient + initials placeholder for local TXT/EPUB.
struct LocalBookCoverView: View {
    let book: LocalBook
    var width: CGFloat = 44

    private var height: CGFloat { width * 1.4 }

    var body: some View {
        Group {
            if let data = book.coverData, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    LinearGradient(
                        colors: Self.palette(for: book),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    VStack(spacing: 4) {
                        Text(Self.initials(from: book.title))
                            .font(.system(size: width * 0.34, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                        Image(systemName: book.format == .epub ? "book.closed.fill" : "doc.plaintext.fill")
                            .font(.system(size: width * 0.22, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .padding(6)
                }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
        .accessibilityHidden(true)
    }

    private static func initials(from title: String) -> String {
        let words = title
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .prefix(2)
        let letters = words.compactMap { $0.first.map { String($0).uppercased() } }
        if letters.isEmpty { return "К" }
        return letters.joined()
    }

    private static func palette(for book: LocalBook) -> [Color] {
        let seed = book.id.uuidString.hashValue & 0x7FFFFFFF
        let palettes: [[Color]] = [
            [Color(red: 0.45, green: 0.28, blue: 0.18), Color(red: 0.72, green: 0.42, blue: 0.22)],
            [Color(red: 0.18, green: 0.32, blue: 0.42), Color(red: 0.28, green: 0.52, blue: 0.62)],
            [Color(red: 0.28, green: 0.22, blue: 0.38), Color(red: 0.48, green: 0.32, blue: 0.55)],
            [Color(red: 0.22, green: 0.36, blue: 0.28), Color(red: 0.35, green: 0.55, blue: 0.40)],
            [Color(red: 0.42, green: 0.22, blue: 0.24), Color(red: 0.62, green: 0.32, blue: 0.35)],
            [Color(red: 0.20, green: 0.24, blue: 0.34), Color(red: 0.35, green: 0.40, blue: 0.55)]
        ]
        return palettes[seed % palettes.count]
    }
}

private struct LocalReaderItem: Identifiable {
    let id: UUID
}
