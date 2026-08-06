import SwiftUI
import WebKit

struct FeedPostDetailView: View {
    let postId: Int

    @EnvironmentObject private var appearance: AppAppearanceStore
    @EnvironmentObject private var auth: AuthService

    @State private var details: PostDetails?
    @State private var error: String?
    @State private var isLoading = true
    @State private var previewImage: URL?

    @State private var comments: [WorkComment] = []
    @State private var commentsLoading = false
    @State private var commentsError: String?
    @State private var commentsPage = 1
    @State private var commentsHasMore = false
    @State private var draftText = ""
    @State private var replyTo: WorkComment?
    @State private var isSendingComment = false
    @State private var openAuthor = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Загрузка поста…")
            } else if let error, details == nil {
                ContentUnavailableView(
                    "Не удалось открыть пост",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else if let details {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(details.title)
                            .font(.system(.title2, design: .serif).weight(.semibold))

                        if let author = details.authorName ?? details.authorUserName {
                            Button {
                                openAuthor = true
                            } label: {
                                HStack(spacing: 4) {
                                    Text(author)
                                    if details.authorUserName != nil {
                                        Image(systemName: "chevron.right")
                                            .font(.caption2.weight(.semibold))
                                    }
                                }
                                .font(.subheadline)
                                .foregroundStyle(details.authorUserName != nil ? appearance.accent : Color.secondary)
                            }
                            .disabled(details.authorUserName == nil)
                        }

                        Text(details.plainText)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        ForEach(details.imageURLs, id: \.absoluteString) { url in
                            Button {
                                previewImage = url
                            } label: {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFit()
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    case .failure:
                                        Label("Не удалось загрузить изображение", systemImage: "photo")
                                            .foregroundStyle(.secondary)
                                    default:
                                        ProgressView()
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 160)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }

                        ForEach(details.videoEmbedURLs, id: \.absoluteString) { url in
                            VideoEmbedView(url: url)
                                .frame(height: 220)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        Divider()

                        BookCommentsSection(
                            comments: comments,
                            commentsLoading: commentsLoading,
                            commentsError: commentsError,
                            commentsHasMore: commentsHasMore,
                            draftText: $draftText,
                            replyTo: $replyTo,
                            isSendingComment: isSendingComment,
                            canWrite: auth.isAuthenticated,
                            onSend: { Task { await sendComment() } },
                            onLoadMore: { Task { await loadComments(reset: false) } }
                        )
                    }
                    .padding(20)
                }
                .background(Color(.systemGroupedBackground).ignoresSafeArea())
            }
        }
        .navigationTitle("Пост")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $openAuthor) {
            authorDestination
        }
        .fullScreenCover(item: Binding(
            get: { previewImage.map(IdentifiableURL.init) },
            set: { previewImage = $0?.url }
        )) { item in
            ImagePreviewView(url: item.url)
        }
        .task {
            await load()
            await loadComments(reset: true)
        }
    }

    @ViewBuilder
    private var authorDestination: some View {
        if let user = details?.authorUserName {
            AuthorProfileView(userName: user, displayNameHint: details?.authorName)
        } else {
            ContentUnavailableView("Нет профиля", systemImage: "person.crop.circle.badge.questionmark")
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            details = try await APIClient.shared.postDetails(id: postId)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadComments(reset: Bool) async {
        guard !commentsLoading else { return }
        commentsLoading = true
        defer { commentsLoading = false }
        do {
            let page = reset ? 1 : max(commentsPage, 1)
            let result = try await APIClient.shared.loadPostComments(postId: postId, page: page)
            if reset {
                comments = result.comments
                commentsPage = 1
            } else {
                var seen = Set(comments.map(\.id))
                for item in result.comments where seen.insert(item.id).inserted {
                    comments.append(item)
                }
            }
            commentsHasMore = result.hasMore
            if result.hasMore {
                commentsPage = result.nextPage ?? (page + 1)
            }
            commentsError = nil
        } catch {
            commentsError = error.localizedDescription
        }
    }

    private func sendComment() async {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSendingComment = true
        commentsError = nil
        defer { isSendingComment = false }
        do {
            try await APIClient.shared.submitPostComment(
                postId: postId,
                text: text,
                parentId: replyTo?.id,
                threadId: replyTo?.threadId ?? replyTo?.id,
                level: (replyTo?.level ?? -1) + 1
            )
            draftText = ""
            replyTo = nil
            await loadComments(reset: true)
        } catch {
            commentsError = error.localizedDescription
        }
    }
}

private struct IdentifiableURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct ImagePreviewView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .padding()
                    default:
                        ProgressView().tint(.white)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Закрыть") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
        }
    }
}

private struct VideoEmbedView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.backgroundColor = .black
        webView.isOpaque = false
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
