import Foundation

/// Duplicate of app WidgetResumeStore for the widget extension target (no app dependencies).
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
