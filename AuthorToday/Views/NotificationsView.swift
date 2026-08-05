import SwiftUI

struct NotificationsView: View {
    @EnvironmentObject private var notifications: NotificationPoller
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if notifications.items.isEmpty {
                    ContentUnavailableView(
                        notifications.lastError == nil ? "Лента пуста" : "Не удалось загрузить",
                        systemImage: "bell.slash",
                        description: Text(notifications.lastError
                            ?? "Новости с author.today/feed появятся здесь")
                    )
                } else {
                    List(notifications.items, id: \.stableId) { item in
                        Button {
                            if let workId = item.workId {
                                path.append(workId)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.displayText)
                                    .font(.body)
                                    .foregroundStyle((item.isRead ?? false) ? .secondary : AppTheme.ink)
                                    .multilineTextAlignment(.leading)
                                if let time = item.creationTime {
                                    Text(time)
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.vertical, 4)
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
            }
        }
    }
}
