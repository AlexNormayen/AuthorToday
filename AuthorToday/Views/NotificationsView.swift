import SwiftUI
import WebKit

enum FeedRoute: Hashable {
    case work(Int)
    case post(Int)
}

struct NotificationsView: View {
    @EnvironmentObject private var notifications: NotificationPoller
    @EnvironmentObject private var appearance: AppAppearanceStore
    @State private var path = NavigationPath()
    @State private var expandedIds: Set<String> = []
    @State private var quickFilter: FeedQuickFilter = .all
    @State private var showKindSettings = false

    private var filteredItems: [NotificationItem] {
        notifications.items.filter { item in
            notifications.enabledKinds.contains(item.feedKind)
                && quickFilter.matches(item, isUnread: notifications.isUnread(item))
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if notifications.items.isEmpty && notifications.isLoading {
                    LoadingStateView(
                        title: "Загрузка ленты…",
                        subtitle: "Получаем обновления с Author.Today"
                    )
                } else if notifications.items.isEmpty {
                    ContentUnavailableView(
                        notifications.lastError == nil ? "Лента пуста" : "Не удалось загрузить",
                        systemImage: notifications.lastError == nil ? "bell.slash" : "wifi.exclamationmark",
                        description: Text(notifications.lastError
                            ?? "Обновления книг и посты авторов появятся здесь")
                    )
                } else {
                    List {
                        Section {
                            filterBar
                                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 4, trailing: 12))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }

                        if filteredItems.isEmpty {
                            ContentUnavailableView(
                                "Нет записей",
                                systemImage: "line.3.horizontal.decrease.circle",
                                description: Text("Попробуйте другой фильтр или включите типы в настройках ленты")
                            )
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        } else {
                            ForEach(filteredItems, id: \.stableId) { item in
                                feedRow(item)
                                    .listRowBackground(
                                        Rectangle().fill(.ultraThinMaterial.opacity(0.82))
                                    )
                                    .onAppear {
                                        if item.stableId == filteredItems.last?.stableId {
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
                                .listRowBackground(Color.clear)
                            } else if notifications.hasMore {
                                Color.clear
                                    .frame(height: 1)
                                    .listRowBackground(Color.clear)
                                    .onAppear {
                                        Task { await notifications.loadMore() }
                                    }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background {
                ThemeAtmosphereView(preset: appearance.themePreset)
            }
            .navigationTitle("Лента")
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button {
                            showKindSettings = true
                        } label: {
                            Label("Что показывать…", systemImage: "slider.horizontal.3")
                        }
                        if notifications.unreadCount > 0 {
                            Button {
                                Task { await notifications.markAllRead() }
                            } label: {
                                Label("Прочитать всё", systemImage: "checkmark.circle")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Обновить") {
                        Task { await notifications.refresh(announceNew: false) }
                    }
                }
            }
            .refreshable {
                await notifications.refresh(announceNew: false)
            }
            .sheet(isPresented: $showKindSettings) {
                FeedKindSettingsSheet()
                    .environmentObject(notifications)
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
                // Do not mark all as read on open — keep badge and unread styling (AT-style).
                await notifications.refresh(announceNew: false)
            }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FeedQuickFilter.allCases) { filter in
                    let selected = quickFilter == filter
                    Button {
                        quickFilter = filter
                    } label: {
                        Text(filter.title)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background {
                                Capsule()
                                    .fill(selected ? appearance.accent.opacity(0.92) : Color.primary.opacity(0.08))
                            }
                            .foregroundStyle(selected ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func feedRow(_ item: NotificationItem) -> some View {
        let expanded = expandedIds.contains(item.stableId)
        let unread = notifications.isUnread(item)
        return Button {
            openOrExpand(item)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(unread ? appearance.accent : Color.clear)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)

                if let cover = item.coverURL {
                    CoverImage(urlString: cover, corner: 8)
                        .frame(width: 52, height: 52)
                        .opacity(unread ? 1 : 0.72)
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(item.feedKind.title)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
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
                            .foregroundStyle(.primary.opacity(unread ? 0.85 : 0.55))
                    }
                    if let title = item.displayTitle {
                        Text(title)
                            .font(.body.weight(unread ? .bold : .semibold))
                            .foregroundStyle(.primary.opacity(unread ? 1 : 0.78))
                            .multilineTextAlignment(.leading)
                            .lineLimit(expanded ? nil : 3)
                    }
                    Text(item.displayText)
                        .font(.body.weight(unread ? .medium : .regular))
                        .foregroundStyle(.primary.opacity(unread ? 1 : 0.72))
                        .multilineTextAlignment(.leading)
                        .lineLimit(expanded ? nil : 6)

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
        .accessibilityLabel(unread ? "Новое: \(item.displayText)" : item.displayText)
    }

    private func openOrExpand(_ item: NotificationItem) {
        notifications.markItemRead(item)
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

private struct FeedKindSettingsSheet: View {
    @EnvironmentObject private var notifications: NotificationPoller
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Выберите, какие типы событий показывать в ленте — по аналогии с настройками уведомлений на Author.Today.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
                Section("Типы") {
                    ForEach(FeedKind.allCases) { kind in
                        Toggle(isOn: Binding(
                            get: { notifications.enabledKinds.contains(kind) },
                            set: { notifications.setKind(kind, enabled: $0) }
                        )) {
                            Text(kind.title)
                        }
                    }
                }
            }
            .navigationTitle("Фильтр ленты")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
