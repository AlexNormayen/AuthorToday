import WidgetKit
import SwiftUI

struct ContinueReadingProvider: TimelineProvider {
    func placeholder(in context: Context) -> ContinueReadingEntry {
        ContinueReadingEntry(date: .now, snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (ContinueReadingEntry) -> Void) {
        completion(ContinueReadingEntry(date: .now, snapshot: WidgetResumeStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ContinueReadingEntry>) -> Void) {
        let entry = ContinueReadingEntry(date: .now, snapshot: WidgetResumeStore.load())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(60 * 30))))
    }
}

struct ContinueReadingEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetResumeStore.Snapshot?
}

struct ContinueReadingWidgetView: View {
    var entry: ContinueReadingEntry

    var body: some View {
        Group {
            if let snap = entry.snapshot {
                Link(destination: WidgetResumeStore.openURL(for: snap.workId, chapterId: snap.chapterId)) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Продолжить")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(snap.title)
                            .font(.headline)
                            .lineLimit(2)
                        if let chapter = snap.chapterTitle, !chapter.isEmpty {
                            Text(chapter)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .padding(12)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Читальня")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Откройте книгу — здесь появится продолжение")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(12)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct ContinueReadingWidget: Widget {
    let kind = "ContinueReadingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ContinueReadingProvider()) { entry in
            ContinueReadingWidgetView(entry: entry)
        }
        .configurationDisplayName("Продолжить чтение")
        .description("Быстрый возврат к последней книге.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct ContinueReadingWidgetBundle: WidgetBundle {
    var body: some Widget {
        ContinueReadingWidget()
    }
}
