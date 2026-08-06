import Foundation
import Combine

/// Durable reading position + last UI place.
/// Primary store is a JSON file in Documents (survives force-quit); UserDefaults is a mirror.
@MainActor
final class ReadingSessionStore: ObservableObject {
    static let shared = ReadingSessionStore()

    struct Checkpoint: Codable, Equatable {
        var workId: Int
        var chapterId: Int
        /// Pixel offset (legacy / secondary).
        var offsetY: Double
        /// 0...1 through the chapter — primary restore key.
        var fraction: Double
        /// Approximate character index in chapter plain text.
        var charOffset: Int
        var pageIndex: Int
        var updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case workId, chapterId, offsetY, fraction, charOffset, pageIndex, updatedAt
        }

        init(
            workId: Int,
            chapterId: Int,
            offsetY: Double = 0,
            fraction: Double = 0,
            charOffset: Int = 0,
            pageIndex: Int = 0,
            updatedAt: Date = .now
        ) {
            self.workId = workId
            self.chapterId = chapterId
            self.offsetY = offsetY
            self.fraction = fraction
            self.charOffset = charOffset
            self.pageIndex = pageIndex
            self.updatedAt = updatedAt
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            workId = try c.decode(Int.self, forKey: .workId)
            chapterId = try c.decode(Int.self, forKey: .chapterId)
            offsetY = try c.decodeIfPresent(Double.self, forKey: .offsetY) ?? 0
            fraction = try c.decodeIfPresent(Double.self, forKey: .fraction) ?? 0
            charOffset = try c.decodeIfPresent(Int.self, forKey: .charOffset) ?? 0
            pageIndex = try c.decodeIfPresent(Int.self, forKey: .pageIndex) ?? 0
            updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .now
            // Migrate old pixel-only checkpoints into a rough fraction.
            if fraction < 0.001, offsetY > 8 {
                fraction = min(offsetY / 4000.0, 0.95)
            }
        }

        var hasInChapterProgress: Bool {
            fraction > 0.01 || pageIndex > 0 || offsetY > 8 || charOffset > 40
        }
    }

    struct ResumeReader: Identifiable, Equatable {
        var id: Int { workId }
        let workId: Int
        let chapterId: Int?
    }

    private struct SessionBlob: Codable {
        var selectedTab: Int
        var isReading: Bool
        var workId: Int?
        var chapterId: Int?
    }

    private let defaults = UserDefaults.standard
    private let checkpointsKey = "at.readingCheckpoints.v3"
    private let sessionKey = "at.appSession.v2"

    @Published var selectedTab: Int = 0
    @Published var pendingResume: ResumeReader?

    private var checkpoints: [String: Checkpoint] = [:]
    private(set) var isReading = false
    private var activeWorkId: Int?
    private var activeChapterId: Int?

    private var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("reading_checkpoints.json")
    }

    private init() {
        loadFromDisk()
    }

    func checkpoint(for workId: Int) -> Checkpoint? {
        checkpoints[Self.key(workId)]
    }

    func saveCheckpoint(
        workId: Int,
        chapterId: Int,
        offsetY: Double,
        fraction: Double,
        charOffset: Int,
        pageIndex: Int
    ) {
        let cp = Checkpoint(
            workId: workId,
            chapterId: chapterId,
            offsetY: offsetY,
            fraction: min(max(fraction, 0), 1),
            charOffset: max(charOffset, 0),
            pageIndex: max(pageIndex, 0),
            updatedAt: .now
        )
        checkpoints[Self.key(workId)] = cp
        if isReading, activeWorkId == workId {
            activeChapterId = chapterId
        }
        persistCheckpoints()
        persistSession()
    }

    func beginReading(workId: Int, chapterId: Int?) {
        isReading = true
        activeWorkId = workId
        activeChapterId = chapterId
        persistSession()
    }

    func updateActiveChapter(_ chapterId: Int) {
        guard isReading else { return }
        activeChapterId = chapterId
        persistSession()
    }

    func endReading() {
        isReading = false
        activeWorkId = nil
        activeChapterId = nil
        pendingResume = nil
        persistSession()
    }

    func setSelectedTab(_ tab: Int) {
        selectedTab = tab
        persistSession()
    }

    func prepareColdStartResume() {
        guard isReading, let workId = activeWorkId else {
            pendingResume = nil
            return
        }
        let chapter = activeChapterId ?? checkpoint(for: workId)?.chapterId
        pendingResume = ResumeReader(workId: workId, chapterId: chapter)
    }

    private func loadFromDisk() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: Checkpoint].self, from: data) {
            checkpoints = decoded
        } else if let data = defaults.data(forKey: checkpointsKey),
                  let decoded = try? JSONDecoder().decode([String: Checkpoint].self, from: data) {
            checkpoints = decoded
        } else if let data = defaults.data(forKey: "at.readingCheckpoints.v2"),
                  let decoded = try? JSONDecoder().decode([String: Checkpoint].self, from: data) {
            checkpoints = decoded
        }

        if let data = defaults.data(forKey: sessionKey),
           let blob = try? JSONDecoder().decode(SessionBlob.self, from: data) {
            selectedTab = blob.selectedTab
            isReading = blob.isReading
            activeWorkId = blob.workId
            activeChapterId = blob.chapterId
        }
    }

    private func persistCheckpoints() {
        guard let data = try? JSONEncoder().encode(checkpoints) else { return }
        defaults.set(data, forKey: checkpointsKey)
        try? data.write(to: fileURL, options: [.atomic])
        defaults.synchronize()
    }

    private func persistSession() {
        let blob = SessionBlob(
            selectedTab: selectedTab,
            isReading: isReading,
            workId: activeWorkId,
            chapterId: activeChapterId
        )
        if let data = try? JSONEncoder().encode(blob) {
            defaults.set(data, forKey: sessionKey)
        }
        defaults.synchronize()
    }

    private static func key(_ workId: Int) -> String { String(workId) }
}
