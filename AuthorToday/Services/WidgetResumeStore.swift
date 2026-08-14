import Foundation
import WidgetKit

/// Shared App Group payload for the Continue Reading home-screen widget (free for all users).
enum WidgetResumeStore {
    static let appGroupID = "group.ru.chitalnya.reader"
    static let snapshotKey = "widget.resume.v1"
    static let suite: UserDefaults? = UserDefaults(suiteName: appGroupID)

    struct Snapshot: Codable, Equatable {
        var workId: Int
        var chapterId: Int?
        var title: String
        var chapterTitle: String?
        var coverURL: String?
        var updatedAt: Date
    }

    static func load() -> Snapshot? {
        guard let data = suite?.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    static func save(
        workId: Int,
        chapterId: Int?,
        title: String,
        chapterTitle: String?,
        coverURL: String?
    ) {
        let previous = load()
        let sameBook =
            previous?.workId == workId
            && previous?.chapterId == chapterId
            && previous?.title == title
            && previous?.chapterTitle == chapterTitle
        // Avoid hammering WidgetKit while scrolling; refresh at least every 2 minutes.
        if sameBook, let previous, Date().timeIntervalSince(previous.updatedAt) < 120 {
            return
        }
        let snap = Snapshot(
            workId: workId,
            chapterId: chapterId,
            title: title,
            chapterTitle: chapterTitle,
            coverURL: coverURL,
            updatedAt: .now
        )
        if let data = try? JSONEncoder().encode(snap) {
            suite?.set(data, forKey: snapshotKey)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func openURL(for workId: Int, chapterId: Int?) -> URL {
        var c = URLComponents()
        c.scheme = "chitalnya"
        c.host = "resume"
        c.path = "/\(workId)"
        if let chapterId {
            c.queryItems = [URLQueryItem(name: "chapter", value: "\(chapterId)")]
        }
        return c.url ?? URL(string: "chitalnya://resume/\(workId)")!
    }
}
