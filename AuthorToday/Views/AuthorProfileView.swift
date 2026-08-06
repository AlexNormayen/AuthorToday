import SwiftUI

struct AuthorProfileView: View {
    let userName: String
    let displayNameHint: String?

    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var appearance: AppAppearanceStore
    @State private var profile: AuthorProfile?
    @State private var error: String?
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Загрузка автора…")
            } else if let error, profile == nil {
                ContentUnavailableView(
                    "Не удалось открыть автора",
                    systemImage: "person.crop.circle.badge.exclamationmark",
                    description: Text(error)
                )
            } else if let profile {
                List {
                    Section {
                        HStack(spacing: 14) {
                            authorAvatar(profile.avatarURL)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(profile.displayName)
                                    .font(.title3.weight(.semibold))
                                Text("@\(profile.userName)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(worksAndCyclesText(profile))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)

                        if let about = profile.about, !about.isEmpty {
                            Text(about)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    ForEach(profile.series) { group in
                        Section(group.title) {
                            ForEach(group.works, id: \.id) { work in
                                NavigationLink {
                                    BookDetailView(workId: work.id)
                                } label: {
                                    HStack(spacing: 12) {
                                        CoverImage(urlString: work.absoluteCoverURL, corner: 6)
                                            .frame(width: 40, height: 56)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(work.displayTitle)
                                                .font(.subheadline.weight(.medium))
                                                .lineLimit(2)
                                            if let order = work.seriesOrder, group.title != "Без серии" {
                                                Text("Том \(order)")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                            if offline.library.contains(where: { $0.workId == work.id }) {
                                                Text("В библиотеке")
                                                    .font(.caption2)
                                                    .foregroundStyle(appearance.accent)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(displayNameHint ?? userName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .task { await load() }
    }

    private func worksAndCyclesText(_ profile: AuthorProfile) -> String {
        let cycleCount = profile.series.filter { $0.title != "Без серии" }.count
        return "\(profile.works.count) произведений · \(cycleCount) циклов"
    }

    private func authorAvatar(_ url: String?) -> some View {
        Group {
            if let url, let u = URL(string: url) {
                AsyncImage(url: u) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(Circle())
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            profile = try await APIClient.shared.authorProfile(
                userName: userName,
                displayNameHint: displayNameHint
            )
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
