import SwiftUI
import UniformTypeIdentifiers

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
                .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
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
                        }
                        .listRowBackground(Color.clear)
                    }
                    ForEach(localLibrary.books, id: \.id) { book in
                        Button {
                            readerBookId = book.id
                        } label: {
                            bookRow(book)
                        }
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
            Image(systemName: book.format == .epub ? "book.closed" : "doc.plaintext")
                .font(.title2)
                .foregroundStyle(appearance.accent)
                .frame(width: 40)
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
                        .background(appearance.accent.opacity(0.15), in: Capsule())
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

private struct LocalReaderItem: Identifiable {
    let id: UUID
}
