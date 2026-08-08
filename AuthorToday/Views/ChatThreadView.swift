import SwiftUI

struct ChatThreadView: View {
    @EnvironmentObject private var appearance: AppAppearanceStore
    @EnvironmentObject private var auth: AuthService

    let initialChatId: Int?
    let title: String
    let peerUserId: Int?
    let peerUserName: String?

    @State private var chatId: Int?
    @State private var resolvedPeerUserId: Int?
    @State private var messages: [PMMessage] = []
    @State private var draft = ""
    @State private var isLoading = true
    @State private var isSending = false
    @State private var error: String?
    @FocusState private var inputFocused: Bool

    init(
        chatId: Int?,
        title: String,
        peerUserId: Int? = nil,
        peerUserName: String? = nil
    ) {
        self.initialChatId = chatId
        self.title = title
        self.peerUserId = peerUserId
        self.peerUserName = peerUserName
        _chatId = State(initialValue: chatId)
        _resolvedPeerUserId = State(initialValue: peerUserId)
    }

    var body: some View {
        VStack(spacing: 0) {
            messageList
            if let error, !error.isEmpty {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
            }
            Divider()
            composer
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .background {
            ThemeAtmosphereView(preset: appearance.themePreset)
        }
        .task { await bootstrap() }
    }

    @ViewBuilder
    private var messageList: some View {
        Group {
            if isLoading && messages.isEmpty {
                ProgressView("Загрузка…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error, messages.isEmpty, chatId == nil || chatId == 0 {
                ContentUnavailableView(
                    "Новый диалог",
                    systemImage: "bubble.left",
                    description: Text(error.isEmpty
                        ? "Напишите первое сообщение ниже."
                        : error)
                )
            } else if messages.isEmpty {
                ContentUnavailableView(
                    "Пока пусто",
                    systemImage: "text.bubble",
                    description: Text("Отправьте первое сообщение.")
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(messages) { message in
                                bubble(message)
                                    .id(message.id)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let last = messages.last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                    .onAppear {
                        if let last = messages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func bubble(_ message: PMMessage) -> some View {
        HStack {
            if message.isMine { Spacer(minLength: 48) }
            VStack(alignment: message.isMine ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .font(.body)
                    .foregroundStyle(message.isMine ? .white : .primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        message.isMine
                            ? appearance.accent
                            : Color.primary.opacity(0.08)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                if let created = message.createdAt, !created.isEmpty {
                    Text(created)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if !message.isMine { Spacer(minLength: 48) }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Сообщение", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .padding(10)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .focused($inputFocused)

            Button {
                Task { await send() }
            } label: {
                if isSending {
                    ProgressView()
                        .frame(width: 36, height: 36)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(appearance.accent)
                }
            }
            .buttonStyle(.borderless)
            .disabled(isSending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private func bootstrap() async {
        isLoading = true
        defer { isLoading = false }
        do {
            if resolvedPeerUserId == nil, let peerUserName, !peerUserName.isEmpty {
                if let profile = try? await APIClient.shared.authorProfile(userName: peerUserName) {
                    resolvedPeerUserId = profile.userId
                }
            }
            if let initialChatId, initialChatId > 0 {
                chatId = initialChatId
            } else if resolvedPeerUserId != nil || peerUserName != nil {
                let ensured = try await APIClient.shared.pmEnsureChat(
                    userId: resolvedPeerUserId,
                    userName: peerUserName,
                    displayName: title
                )
                if ensured.id > 0 {
                    chatId = ensured.id
                }
                if resolvedPeerUserId == nil {
                    resolvedPeerUserId = ensured.peerUserId
                }
            }
            if let chatId, chatId > 0 {
                messages = try await APIClient.shared.pmMessages(chatId: chatId)
                try? await APIClient.shared.pmMarkAsRead(chatId: chatId)
            }
            error = nil
        } catch {
            // New chat without history is fine — composer still works.
            if chatId == nil || chatId == 0 {
                self.error = ""
            } else {
                self.error = error.localizedDescription
            }
        }
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSending = true
        defer { isSending = false }
        do {
            if resolvedPeerUserId == nil, let peerUserName, !peerUserName.isEmpty,
               let profile = try? await APIClient.shared.authorProfile(userName: peerUserName) {
                resolvedPeerUserId = profile.userId
            }
            let resolved = try await APIClient.shared.pmSendMessage(
                chatId: (chatId ?? 0) > 0 ? chatId : nil,
                userId: resolvedPeerUserId,
                text: text
            )
            if let resolved, resolved > 0 {
                chatId = resolved
            }
            draft = ""
            inputFocused = false
            if let chatId, chatId > 0 {
                messages = try await APIClient.shared.pmMessages(chatId: chatId)
            } else {
                // Optimistic local bubble until chat id appears.
                let mine = PMMessage(
                    id: (messages.map(\.id).max() ?? 0) + 1,
                    text: text,
                    isMine: true,
                    senderName: auth.user?.resolvedUserName,
                    createdAt: nil
                )
                messages.append(mine)
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
