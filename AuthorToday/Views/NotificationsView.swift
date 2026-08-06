import SwiftUI

struct NotificationsView: View {
    @EnvironmentObject private var notifications: NotificationPoller
    @State private var path = NavigationPath()

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
                            Button {
                                if let workId = item.resolvedWorkId {
                                    path.append(workId)
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    if let category = item.category, !category.isEmpty {
                                        Text(category)
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(item.displayText)
                                        .font(.body)
                                        .foregroundStyle((item.isRead ?? false) ? .secondary : Color.primary)
                                        .multilineTextAlignment(.leading)
                                        .lineLimit(8)
                                    if let time = item.creationTime {
                                        Text(Self.formatTime(time))
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
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
            .navigationDestination(for: Int.self) { workId in
                BookDetailView(workId: workId)
            }
            .task {
                await notifications.refresh(announceNew: false)
                await notifications.markFeedSeen()
            }
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
