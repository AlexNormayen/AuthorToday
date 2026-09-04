import AVKit
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
    @State private var activeVideo: IdentifiableURL?
    @State private var activeBrowser: IdentifiableURL?

    @State private var comments: [WorkComment] = []
    @State private var commentsLoading = false
    @State private var commentsError: String?
    @State private var commentsPage = 1
    @State private var commentsHasMore = false
    @State private var draftText = ""
    @State private var replyTo: WorkComment?
    @State private var isSendingComment = false
    @State private var openAuthor = false
    @State private var openWorkId: Int?

    var body: some View {
        Group {
            if isLoading {
                LoadingStateView(title: "Загрузка поста…")
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

                        Text(details.attributedBody)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .tint(appearance.accent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .environment(\.openURL, OpenURLAction { url in
                                handleLink(url)
                            })

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

                        if !details.videoEmbedURLs.isEmpty {
                            Text("Видео")
                                .font(AppTheme.headlineFont)
                            ForEach(details.videoEmbedURLs, id: \.absoluteString) { url in
                                VStack(alignment: .leading, spacing: 8) {
                                    VideoEmbedView(url: url)
                                        .frame(height: 220)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    Button {
                                        activeVideo = IdentifiableURL(url: url)
                                    } label: {
                                        Label("На весь экран", systemImage: "arrow.up.left.and.arrow.down.right")
                                            .font(.caption)
                                    }
                                }
                            }
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
                .themedGroupedFill()
            }
        }
        .navigationTitle("Пост")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $openAuthor) {
            authorDestination
        }
        .navigationDestination(item: $openWorkId) { workId in
            BookDetailView(workId: workId)
        }
        .fullScreenCover(item: Binding(
            get: { previewImage.map(IdentifiableURL.init) },
            set: { previewImage = $0?.url }
        )) { item in
            ImagePreviewView(url: item.url)
        }
        .fullScreenCover(item: $activeVideo) { item in
            InAppVideoPlayerView(url: item.url)
        }
        .sheet(item: $activeBrowser) { item in
            InAppBrowserView(url: item.url)
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

    private func handleLink(_ url: URL) -> OpenURLAction.Result {
        if MediaURL.isVideo(url) {
            activeVideo = IdentifiableURL(url: MediaURL.embedURL(for: url))
            return .handled
        }
        if let workId = FeedLinkParser.entityId(in: url.absoluteString, kind: .work) {
            openWorkId = workId
            return .handled
        }
        // Keep author.today deep content inside the app browser (cookies / no App Store jump).
        activeBrowser = IdentifiableURL(url: url)
        return .handled
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

private struct InAppVideoPlayerView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    private var isDirectFile: Bool {
        ["mp4", "m3u8", "webm", "mov"].contains(url.pathExtension.lowercased())
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if isDirectFile {
                    VideoPlayer(player: AVPlayer(url: url))
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    VideoEmbedView(url: url)
                        .ignoresSafeArea(edges: .bottom)
                }
            }
            .navigationTitle("Видео")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Закрыть") { dismiss() }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

private struct InAppBrowserView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ZStack {
                BrowserWebView(url: url, isLoading: $isLoading)
                if isLoading {
                    ProgressView()
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .navigationTitle(url.host ?? "Ссылка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
    }
}

private struct BrowserWebView: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var isLoading: Bool
        init(isLoading: Binding<Bool>) { _isLoading = isLoading }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoading = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            isLoading = false
        }
    }
}

private struct VideoEmbedView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        if #available(iOS 15.0, *) {
            config.allowsPictureInPictureMediaPlayback = true
        }
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.backgroundColor = .black
        webView.isOpaque = false
        context.coordinator.load(url, into: webView)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if context.coordinator.loadedURL != url {
            context.coordinator.load(url, into: uiView)
        }
    }

    final class Coordinator {
        var loadedURL: URL?

        func load(_ url: URL, into webView: WKWebView) {
            loadedURL = url
            let ext = url.pathExtension.lowercased()
            if ["mp4", "m3u8", "webm", "mov"].contains(ext) {
                webView.load(URLRequest(url: url))
                return
            }
            let src = url.absoluteString.replacingOccurrences(of: "\"", with: "%22")
            let html = """
            <!DOCTYPE html><html><head>
            <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
            <style>
              html,body{margin:0;padding:0;background:#000;height:100%;}
              iframe{position:fixed;inset:0;width:100%;height:100%;border:0;}
            </style></head><body>
            <iframe src="\(src)" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; fullscreen" allowfullscreen playsinline></iframe>
            </body></html>
            """
            webView.loadHTMLString(html, baseURL: URL(string: "https://author.today"))
        }
    }
}
