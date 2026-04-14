import SwiftUI

struct HistoryView: View {
    @ObservedObject var store: TranscriptionStore
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                TabButton(title: "History", icon: "clock", isSelected: selectedTab == 0) {
                    selectedTab = 0
                }
                TabButton(title: "Statistics", icon: "chart.bar", isSelected: selectedTab == 1) {
                    selectedTab = 1
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .background(.bar)

            Divider()

            // Content
            if selectedTab == 0 {
                HistoryListView(store: store)
            } else {
                StatisticsView(store: store)
            }
        }
        .frame(minWidth: 500, minHeight: 350)
    }
}

struct TabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.subheadline)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.15) : .clear)
            .foregroundColor(isSelected ? .accentColor : .secondary)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

struct HistoryListView: View {
    @ObservedObject var store: TranscriptionStore
    @State private var searchText = ""
    @State private var selectedID: UUID?

    private var filteredEntries: [TranscriptionEntry] {
        store.filtered(by: searchText)
    }

    private var selectedEntry: TranscriptionEntry? {
        guard let id = selectedID else { return nil }
        return store.entries.first { $0.id == id }
    }

    var body: some View {
        HSplitView {
            masterPanel
                .frame(minWidth: 200, idealWidth: 280, maxWidth: 350)
            detailPanel
                .frame(minWidth: 280)
        }
    }

    private var masterPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search transcriptions...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(.bar)

            Divider()

            List(selection: $selectedID) {
                let entries = filteredEntries
                let favorites = entries.filter(\.isFavorite)
                let regular = entries.filter { !$0.isFavorite }

                if !favorites.isEmpty {
                    Section("Favorites") {
                        ForEach(favorites) { entry in
                            EntryRow(entry: entry)
                                .tag(entry.id)
                        }
                    }
                }

                Section(favorites.isEmpty ? "All" : "Recent") {
                    ForEach(regular) { entry in
                        EntryRow(entry: entry)
                            .tag(entry.id)
                    }
                }
            }
            .listStyle(.sidebar)

            HStack {
                Text("\(store.entries.count) transcriptions")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.bar)
        }
    }

    private var detailPanel: some View {
        Group {
            if let entry = selectedEntry {
                DetailView(entry: entry, store: store)
            } else {
                VStack {
                    Spacer()
                    Image(systemName: "text.bubble")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Select a transcription to view details")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
    }
}

struct EntryRow: View {
    let entry: TranscriptionEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.date, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(entry.language.uppercased())
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(3)
                if entry.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundColor(.yellow)
                }
            }
            Text(entry.text)
                .font(.body)
                .lineLimit(2)
                .foregroundColor(.primary)
        }
        .padding(.vertical, 2)
    }
}

struct DetailView: View {
    let entry: TranscriptionEntry
    @ObservedObject var store: TranscriptionStore
    @State private var editedText: String = ""
    @State private var isEditing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(entry.date, format: .dateTime.month().day().year().hour().minute())
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("·").foregroundColor(.secondary)
                Text(entry.language.uppercased())
                    .font(.subheadline.bold())
                    .foregroundColor(.secondary)
                Text("·").foregroundColor(.secondary)
                Text(String(format: "%.1fs", entry.duration))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding()

            Divider()

            if isEditing {
                TextEditor(text: $editedText)
                    .font(.body)
                    .padding(8)
                HStack {
                    Spacer()
                    Button("Cancel") { isEditing = false }
                    Button("Save") {
                        var updated = entry
                        updated.text = editedText
                        store.update(updated)
                        isEditing = false
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            } else {
                ScrollView {
                    Text(entry.text)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            }

            Divider()

            HStack(spacing: 12) {
                Button { ClipboardManager.copy(entry.text) } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                Button { TextInjector.inject(entry.text) } label: {
                    Label("Re-inject", systemImage: "text.insert")
                }
                Button {
                    editedText = entry.text
                    isEditing = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                Button { store.toggleFavorite(entry) } label: {
                    Label(
                        entry.isFavorite ? "Unfavorite" : "Favorite",
                        systemImage: entry.isFavorite ? "star.fill" : "star"
                    )
                }
                .foregroundColor(entry.isFavorite ? .yellow : nil)
                Spacer()
                Button(role: .destructive) { store.delete(entry) } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .padding()
            .background(.bar)
        }
        .onChange(of: entry.id) { _, _ in
            isEditing = false
        }
    }
}
