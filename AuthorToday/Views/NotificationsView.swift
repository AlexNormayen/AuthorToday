import SwiftUI
import WebKit

enum FeedRoute: Hashable {
    case work(Int)
    case post(Int)
}

struct NotificationsView: View {
    @EnvironmentObject private var notifications: NotificationPoller
    @State private var path = NavigationPath()
    @State private var expandedIds: Set<String> = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if notifications.items.isEmpty && notifications.isLoading {
                    ProgressView("Загрузка ленты…")
                } else if notifications.items.isEmpty {
                    ContentUnavailableView(
                        notifications.lastError == nil ? "Лента пуста" : "Не удалось загрузить",
                        systemImage: "bell.slash",
                        description: Text(notifications.lastError
                            ?? "Обновления книг и посты авторов появятся здесь")
                    )
                } else {
                    List {
                        ForEach(notifications.items, id: \.stableId) { item in
                            feedRow(item)
                                .onAppear {
                                    if item.stableId == notifications.items.last?.stableId {
                                        Task { await notifications.loadMore() }
                                    }
                                }
                        }

                        if notifications.isLoadingMore {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                            .listRowSeparator(.hidden)
                        } else if notifications.hasMore {
                            Color.clear
                                .frame(height: 1)
                                .onAppear {
                                    Task { await notifications.loadMore() }
                                }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Лента")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Обновить") {
                        Task { await notifications.refresh(announceNew: false) }
                    }
                }
            }
            .refreshable {
                await notifications.refresh(announceNew: false)
            }
            .navigationDestination(for: FeedRoute.self) { route in
                switch route {
                case .work(let workId):
                    BookDetailView(workId: workId)
                case .post(let postId):
                    FeedPostDetailView(postId: postId)
                }
            }
            .task {
                await notifications.refresh(announceNew: false)
                await notifications.markFeedSeen()
            }
        }
    }

    private func feedRow(_ item: NotificationItem) -> some View {
        let expanded = expandedIds.contains(item.stableId)
        return Button {
            openOrExpand(item)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                if let cover = item.coverURL {
                    CoverImage(urlString: cover, corner: 8)
                        .frame(width: 52, height: 52)
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        if let category = item.category, !category.isEmpty {
                            Text(category)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        if item.isBlogPost {
                            Text("Пост")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(AppTheme.moss)
                        }
                        Spacer(minLength: 0)
                        if let time = item.creationTime {
                            Text(Self.formatTime(time))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let author = item.authorName, !author.isEmpty {
                        Text(author)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary.opacity(0.75))
                    }
                    if let title = item.displayTitle {
                        Text(title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(expanded ? nil : 3)
                    }
                    Text(item.displayText)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(expanded ? nil : 6)
                        .opacity((item.isRead ?? false) ? 0.88 : 1)

                    if !expanded && item.displayText.count > 220 {
                        Text("Показать полностью")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.moss)
                    } else if item.isBlogPost || item.resolvedWorkId != nil {
                        Text(item.isBlogPost ? "Открыть пост" : "Открыть книгу")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.moss)
                    }
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func openOrExpand(_ item: NotificationItem) {
        if let postId = item.postId {
            path.append(FeedRoute.post(postId))
            return
        }
        if item.isBlogPost, let id = item.id {
            path.append(FeedRoute.post(id))
            return
        }
        if let workId = item.resolvedWorkId {
            path.append(FeedRoute.work(workId))
            return
        }
        if expandedIds.contains(item.stableId) {
            expandedIds.remove(item.stableId)
        } else {
            expandedIds.insert(item.stableId)
        }
    }

    private static func formatTime(_ raw: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = iso.date(from: raw) ?? {
            iso.formatOptions = [.withInternetDateTime]
            return iso.date(from: raw)
        }()
        guard let date else { return raw }
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}
