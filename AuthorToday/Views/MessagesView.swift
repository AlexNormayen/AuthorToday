import SwiftUI

struct MessagesView: View {
    @EnvironmentObject private var appearance: AppAppearanceStore
    @State private var chats: [PMChat] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var onlyUnread = false

    var body: some View {
        Group {
            if isLoading && chats.isEmpty {
                LoadingStateView(title: "Загружаем сообщения…")
            } else if let error, chats.isEmpty {
                ContentUnavailableView(
                    "Не удалось загрузить",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text(error)
                )
            } else if chats.isEmpty {
                ContentUnavailableView(
                    "Нет переписок",
                    systemImage: "tray",
                    description: Text(onlyUnread
                        ? "Нет непрочитанных сообщений."
                        : "Напишите автору из профиля — диалог появится здесь.")
                )
            } else {
                List(chats) { chat in
                    NavigationLink {
                        ChatThreadView(
                            chatId: chat.id > 0 ? chat.id : nil,
                            title: chat.title,
                            peerUserId: chat.peerUserId,
                            peerUserName: chat.peerUserName
                        )
                    } label: {
                        chatRow(chat)
                    }
                    .themedListRow()
                }
                .listStyle(.plain)
                .themedScreenChrome()
            }
        }
        .navigationTitle("Сообщения")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .background {
            ThemeAtmosphereView(preset: appearance.themePreset)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(onlyUnread ? "Все сообщения" : "Только непрочитанные") {
                        onlyUnread.toggle()
                        Task { await load() }
                    }
                    Button("Обновить") {
                        Task { await load() }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func chatRow(_ chat: PMChat) -> some View {
        HStack(spacing: 12) {
            avatar(chat.avatarURL)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(chat.title)
                        .font(.subheadline.weight(chat.unreadCount > 0 ? .semibold : .regular))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if chat.unreadCount > 0 {
                        Text("\(chat.unreadCount)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(appearance.accent)
                            .clipShape(Capsule())
                    }
                }
                if let preview = chat.preview, !preview.isEmpty {
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func avatar(_ urlString: String?) -> some View {
        if let urlString, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    Circle().fill(.secondary.opacity(0.25))
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())
        } else {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
        }
    }

    private func load() async {
        if chats.isEmpty { isLoading = true }
        defer { isLoading = false }
        do {
            chats = try await APIClient.shared.pmRecentChats(page: 1, onlyUnread: onlyUnread)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
