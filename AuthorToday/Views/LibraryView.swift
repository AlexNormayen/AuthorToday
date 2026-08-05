import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var downloads: DownloadManager
    @State private var path = NavigationPath()
    @State private var query = ""

    private var filtered: [CachedWork] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return offline.library }
        return offline.library.filter {
            $0.title.lowercased().contains(q) || $0.author.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if offline.library.isEmpty && offline.isSyncing {
                    ProgressView("Синхронизация библиотеки…")
                } else if offline.library.isEmpty {
                    ContentUnavailableView(
                        "Библиотека пуста",
                        systemImage: "books.vertical",
                        description: Text(emptyLibraryMessage)
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filtered, id: \.workId) { work in
                                Button {
                                    path.append(LibraryRoute.reader(workId: work.workId, chapterId: work.lastReadChapterId))
                                } label: {
                                    LibraryRow(work: work)
                                }
                                .buttonStyle(.plain)

                                Divider().padding(.leading, 88)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Библиотека")
            .searchable(text: $query, prompt: "Название или автор")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await offline.syncLibrary(force: true) }
                    } label: {
                        if offline.isSyncing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .refreshable {
                await offline.syncLibrary()
            }
            .navigationDestination(for: LibraryRoute.self) { route in
                switch route {
                case .reader(let workId, let chapterId):
                    ReaderView(workId: workId, initialChapterId: chapterId)
                case .details(let workId):
                    BookDetailView(workId: workId)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let msg = downloads.statusMessage {
                    Text(msg)
                        .font(.caption)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .task {
                await offline.syncLibrary(force: true)
            }
        }
    }

    private var emptyLibraryMessage: String {
        if let err = offline.lastSyncError {
            return "Ошибка синхронизации: \(err)\nПотяните вниз или нажмите обновить."
        }
        if downloads.online {
            return "Добавьте книги на author.today или найдите их во вкладке Поиск, затем нажмите обновить."
        }
        return "Нет сети. Когда появится интернет — обновите библиотеку."
    }
}

enum LibraryRoute: Hashable {
    case reader(workId: Int, chapterId: Int?)
    case details(workId: Int)
}

struct LibraryRow: View {
    let work: CachedWork
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var appearance: AppAppearanceStore

    var body: some View {
        HStack(spacing: 14) {
            CoverImage(urlString: work.coverURL)
                .frame(width: 56, height: 80)

            VStack(alignment: .leading, spacing: 6) {
                Text(work.title)
                    .font(.system(.body, design: .serif).weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(work.author)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if work.isFullyDownloaded {
                        Label("Офлайн", systemImage: "arrow.down.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(appearance.accent)
                    } else if let p = offline.downloadProgress[work.workId], p > 0, p < 1 {
                        ProgressView(value: p)
                            .frame(width: 60)
                    } else if downloads.activeDownloads.contains(work.workId) {
                        ProgressView()
                            .scaleEffect(0.7)
                    }

                    if work.progress > 0 {
                        Text("\(Int(work.progress * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                // open details via notification — parent handles path; use openURL style workaround
            } label: {
                Label("О книге", systemImage: "info.circle")
            }
            .disabled(true)
        }
    }
}

extension OfflineStore {
    func syncLibrary(force: Bool) async {
        await syncLibraryIfNeeded(force: force)
    }
}
