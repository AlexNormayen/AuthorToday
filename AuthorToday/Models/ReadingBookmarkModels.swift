import Foundation
import SwiftData

@Model
final class ReadingBookmark {
    @Attribute(.unique) var id: UUID
    var workId: Int
    var chapterId: Int
    var workTitle: String
    var chapterTitle: String
    var charOffset: Int
    var fraction: Double
    var createdAt: Date

    init(
        id: UUID = UUID(),
        workId: Int,
        chapterId: Int,
        workTitle: String,
        chapterTitle: String,
        charOffset: Int = 0,
        fraction: Double = 0,
        createdAt: Date = .now
    ) {
        self.id = id
        self.workId = workId
        self.chapterId = chapterId
        self.workTitle = workTitle
        self.chapterTitle = chapterTitle
        self.charOffset = charOffset
        self.fraction = fraction
        self.createdAt = createdAt
    }
}

@Model
final class ReadingNote {
    @Attribute(.unique) var id: UUID
    var workId: Int
    var chapterId: Int
    var workTitle: String
    var chapterTitle: String
    var body: String
    var charOffset: Int
    var fraction: Double
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        workId: Int,
        chapterId: Int,
        workTitle: String,
        chapterTitle: String,
        body: String,
        charOffset: Int = 0,
        fraction: Double = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.workId = workId
        self.chapterId = chapterId
        self.workTitle = workTitle
        self.chapterTitle = chapterTitle
        self.body = body
        self.charOffset = charOffset
        self.fraction = fraction
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
