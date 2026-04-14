import SwiftUI
import Charts

struct StatisticsView: View {
    @ObservedObject var store: TranscriptionStore

    private var totalCount: Int { store.entries.count }

    private var totalDuration: Double {
        store.entries.reduce(0) { $0 + $1.duration }
    }

    private var totalWords: Int {
        store.entries.reduce(0) { $0 + $1.text.split(separator: " ").count }
    }

    private var estimatedTimeSaved: Double {
        totalDuration * 3 // Typing is ~3x slower than speaking
    }

    private var languageBreakdown: [(language: String, count: Int)] {
        let grouped = Dictionary(grouping: store.entries, by: { $0.language.uppercased() })
        return grouped.map { (language: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }

    private var dailyActivity: [(date: Date, count: Int)] {
        let calendar = Calendar.current
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: Date())!
        let recent = store.entries.filter { $0.date >= thirtyDaysAgo }
        let grouped = Dictionary(grouping: recent) { calendar.startOfDay(for: $0.date) }
        return grouped.map { (date: $0.key, count: $0.value.count) }
            .sorted { $0.date < $1.date }
    }

    private var streak: Int {
        let calendar = Calendar.current
        let days = Set(store.entries.map { calendar.startOfDay(for: $0.date) }).sorted(by: >)
        guard !days.isEmpty else { return 0 }

        var count = 1
        for i in 0..<(days.count - 1) {
            let diff = calendar.dateComponents([.day], from: days[i + 1], to: days[i]).day ?? 0
            if diff == 1 { count += 1 } else { break }
        }
        return count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Summary cards
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                ], spacing: 12) {
                    StatCard(title: "Transcriptions", value: "\(totalCount)", icon: "text.bubble.fill", color: .blue)
                    StatCard(title: "Words", value: formatNumber(totalWords), icon: "textformat.abc", color: .purple)
                    StatCard(title: "Duration", value: formatDuration(totalDuration), icon: "clock.fill", color: .green)
                    StatCard(title: "Time Saved", value: formatDuration(estimatedTimeSaved), icon: "bolt.fill", color: .orange)
                    StatCard(title: "Streak", value: "\(streak) day\(streak == 1 ? "" : "s")", icon: "flame.fill", color: .red)
                    StatCard(title: "Languages", value: "\(languageBreakdown.count)", icon: "globe", color: .teal)
                }

                // Daily activity chart
                if !dailyActivity.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Daily Activity (Last 30 Days)")
                            .font(.headline)

                        Chart(dailyActivity, id: \.date) { item in
                            BarMark(
                                x: .value("Date", item.date, unit: .day),
                                y: .value("Count", item.count)
                            )
                            .foregroundStyle(.blue.gradient)
                            .cornerRadius(3)
                        }
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .day, count: 7)) {
                                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            }
                        }
                        .frame(height: 150)
                    }
                    .padding()
                    .background(.bar)
                    .cornerRadius(8)
                }

                // Language breakdown chart
                if languageBreakdown.count > 1 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Language Breakdown")
                            .font(.headline)

                        Chart(languageBreakdown, id: \.language) { item in
                            SectorMark(
                                angle: .value("Count", item.count),
                                innerRadius: .ratio(0.5),
                                angularInset: 2
                            )
                            .foregroundStyle(by: .value("Language", item.language))
                            .annotation(position: .overlay) {
                                Text(item.language)
                                    .font(.caption2.bold())
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(height: 200)
                    }
                    .padding()
                    .background(.bar)
                    .cornerRadius(8)
                } else if let lang = languageBreakdown.first {
                    HStack {
                        Text("Primary Language:")
                            .foregroundColor(.secondary)
                        Text(lang.language)
                            .font(.headline)
                    }
                    .padding()
                    .background(.bar)
                    .cornerRadius(8)
                }

                if store.entries.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "chart.bar")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("No transcriptions yet")
                            .foregroundColor(.secondary)
                        Text("Statistics will appear after your first transcription")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            }
            .padding()
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        if seconds < 60 { return String(format: "%.0fs", seconds) }
        if seconds < 3600 { return String(format: "%.0fm", seconds / 60) }
        return String(format: "%.1fh", seconds / 3600)
    }

    private func formatNumber(_ n: Int) -> String {
        if n < 1000 { return "\(n)" }
        return String(format: "%.1fk", Double(n) / 1000)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            Text(value)
                .font(.title3.bold())
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.bar)
        .cornerRadius(8)
    }
}
