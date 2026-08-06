import Foundation
import Combine

/// Durable reading position + last UI place. UserDefaults survives force-quit better than in-memory SwiftData quirks.
@MainActor
final class ReadingSessionStore: ObservableObject {
    static let shared = ReadingSessionStore()

    struct Checkpoint: Codable, Equatable {
        var workId: Int
        var chapterId: Int
        var offsetY: Double
        var pageIndex: Int
        var updatedAt: Date
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
    private let checkpointsKey = "at.readingCheckpoints.v2"
    private let sessionKey = "at.appSession.v2"

    @Published var selectedTab: Int = 0
    /// Set once on cold start when the user left while reading.
    @Published var pendingResume: ResumeReader?

    private var checkpoints: [String: Checkpoint] = [:]
    private(set) var isReading = false
    private var activeWorkId: Int?
    private var activeChapterId: Int?

    private init() {
        loadFromDisk()
    }

    func checkpoint(for workId: Int) -> Checkpoint? {
        checkpoints[Self.key(workId)]
    }

    func saveCheckpoint(workId: Int, chapterId: Int, offsetY: Double, pageIndex: Int) {
        let cp = Checkpoint(
            workId: workId,
            chapterId: chapterId,
            offsetY: offsetY,
            pageIndex: pageIndex,
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

    /// User left the reader intentionally (back button / dismiss cover).
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

    /// Call once after login UI appears.
    func prepareColdStartResume() {
        guard isReading, let workId = activeWorkId else {
            pendingResume = nil
            return
        }
        let chapter = activeChapterId ?? checkpoint(for: workId)?.chapterId
        pendingResume = ResumeReader(workId: workId, chapterId: chapter)
    }

    private func loadFromDisk() {
        if let data = defaults.data(forKey: checkpointsKey),
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
        if let data = try? JSONEncoder().encode(checkpoints) {
            defaults.set(data, forKey: checkpointsKey)
        }
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
