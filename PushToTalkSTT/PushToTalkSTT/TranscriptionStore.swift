import Foundation
import SwiftUI

struct TranscriptionEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    let date: Date
    let language: String
    let duration: Double
    var isFavorite: Bool

    init(text: String, language: String, duration: Double) {
        self.id = UUID()
        self.text = text
        self.date = Date()
        self.language = language
        self.duration = duration
        self.isFavorite = false
    }
}

@MainActor
class TranscriptionStore: ObservableObject {
    @Published private(set) var entries: [TranscriptionEntry] = []

    private static var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("PushToTalkSTT", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }

    init() {
        load()
    }

    func add(_ entry: TranscriptionEntry) {
        entries.insert(entry, at: 0)
        save()
    }

    func update(_ entry: TranscriptionEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = entry
        save()
    }

    func delete(_ entry: TranscriptionEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func toggleFavorite(_ entry: TranscriptionEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].isFavorite.toggle()
        save()
    }

    func filtered(by query: String) -> [TranscriptionEntry] {
        let all = query.isEmpty ? entries : entries.filter {
            $0.text.localizedCaseInsensitiveContains(query)
        }
        return all.sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }
            return lhs.date > rhs.date
        }
    }

    var lastTranscription: TranscriptionEntry? {
        entries.first
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(entries)
            try data.write(to: Self.fileURL, options: .atomic)
        } catch {
            print("TranscriptionStore: save failed – \(error)")
        }
    }

    private func load() {
        let url = Self.fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            entries = try decoder.decode([TranscriptionEntry].self, from: data)
        } catch {
            print("TranscriptionStore: load failed – \(error)")
        }
    }
}