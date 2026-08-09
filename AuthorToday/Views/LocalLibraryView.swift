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

    private var canUseLocalLibrary: Bool {
        !ProFeatures.localLibraryRequiresPro || pro.isProUnlocked
    }

    var body: some View {
        Group {
            if !canUseLocalLibrary {
                freeGate
            } else if localLibrary.books.isEmpty {
                ContentUnavailableView {
                    Label("Мои книги", systemImage: "tray.and.arrow.down")
                } description: {
                    Text("Добавьте TXT или EPUB с устройства. Книги хранятся только локально и не синхронизируются с Author.Today.")
                } actions: {
                    Button("Добавить файл") { showImporter = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(localLibrary.books, id: \.id) { book in
                        Button {
                            readerBookId = book.id
                        } label: {
                            bookRow(book)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                localLibrary.delete(book)
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
            if canUseLocalLibrary {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showImporter = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(localLibrary.isImporting)
                }
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
            ProPaywallView()
        }
        .fullScreenCover(item: Binding(
            get: { readerBookId.map { LocalReaderItem(id: $0) } },
            set: { readerBookId = $0?.id }
        )) { item in
            NavigationStack {
                LocalReaderView(bookId: item.id)
            }
        }
        .onAppear { localLibrary.reload() }
    }

    private var freeGate: some View {
        ContentUnavailableView {
            Label("Мои книги — Pro", systemImage: "lock.fill")
        } description: {
            Text("Импорт своих TXT и EPUB и чтение в Читальне доступны в «Читальня Pro». Файлы остаются только на устройстве.")
        } actions: {
            Button("Открыть Pro") { showPaywall = true }
                .buttonStyle(.borderedProminent)
        }
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
        guard canUseLocalLibrary else {
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
