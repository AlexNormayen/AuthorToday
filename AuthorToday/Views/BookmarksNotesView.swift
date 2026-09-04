import SwiftUI
import SwiftData

/// Pro-only bookmarks & notes list (device-local).
struct BookmarksNotesView: View {
    @EnvironmentObject private var pro: ProEntitlementStore
    @EnvironmentObject private var appearance: AppAppearanceStore
    @Environment(\.modelContext) private var modelContext

    var workIdFilter: Int?

    @Query(sort: \ReadingBookmark.createdAt, order: .reverse) private var allBookmarks: [ReadingBookmark]
    @Query(sort: \ReadingNote.updatedAt, order: .reverse) private var allNotes: [ReadingNote]

    @State private var showPaywall = false
    @State private var resume: ReadingSessionStore.ResumeReader?

    private var bookmarks: [ReadingBookmark] {
        guard let workIdFilter else { return allBookmarks }
        return allBookmarks.filter { $0.workId == workIdFilter }
    }

    private var notes: [ReadingNote] {
        guard let workIdFilter else { return allNotes }
        return allNotes.filter { $0.workId == workIdFilter }
    }

    var body: some View {
        Group {
            if !pro.isProUnlocked {
                ContentUnavailableView {
                    Label("Закладки — Pro", systemImage: "bookmark.fill")
                } description: {
                    Text("Создание и просмотр закладок и заметок доступны в Читальне Pro. Только на этом устройстве.")
                } actions: {
                    Button("Открыть Pro") { showPaywall = true }
                        .buttonStyle(.borderedProminent)
                        .tint(appearance.accent)
                }
            } else if bookmarks.isEmpty && notes.isEmpty {
                ContentUnavailableView(
                    "Пока пусто",
                    systemImage: "bookmark",
                    description: Text("Добавляйте закладки и заметки из читалки.")
                )
            } else {
                List {
                    if !bookmarks.isEmpty {
                        Section("Закладки") {
                            ForEach(bookmarks, id: \.id) { bm in
                                Button {
                                    resume = .init(workId: bm.workId, chapterId: bm.chapterId)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(bm.workTitle)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Text(bm.chapterTitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(bm.createdAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            .onDelete(perform: deleteBookmarks)
                        }
                    }
                    if !notes.isEmpty {
                        Section("Заметки") {
                            ForEach(notes, id: \.id) { note in
                                Button {
                                    resume = .init(workId: note.workId, chapterId: note.chapterId)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(note.workTitle)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Text(note.body)
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                            .lineLimit(3)
                                        Text("\(note.chapterTitle) · \(note.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .onDelete(perform: deleteNotes)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle(workIdFilter == nil ? "Закладки и заметки" : "Закладки")
        .navigationBarTitleDisplayMode(.inline)
        .background { ThemeAtmosphereView(preset: appearance.themePreset) }
        .sheet(isPresented: $showPaywall) {
            ProPaywallView(reason: "Закладки и заметки — удобство Читальни Pro.")
        }
        .fullScreenCover(item: $resume) { item in
            NavigationStack {
                ReaderView(workId: item.workId, initialChapterId: item.chapterId)
            }
        }
    }

    private func deleteBookmarks(at offsets: IndexSet) {
        for i in offsets {
            modelContext.delete(bookmarks[i])
        }
        try? modelContext.save()
        BookVaultSync.shared.enqueueBookmarksUpload(modelContext: modelContext)
    }

    private func deleteNotes(at offsets: IndexSet) {
        for i in offsets {
            modelContext.delete(notes[i])
        }
        try? modelContext.save()
    }
}
