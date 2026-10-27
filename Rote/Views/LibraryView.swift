import RoteCore
import SwiftData
import SwiftUI

/// Poems grouped by status with a due count per poem.
struct LibraryView: View {
    @Binding var selection: Poem?
    @Binding var showingNewPoem: Bool
    @Environment(\.modelContext) private var context
    @Query(sort: \Poem.title) private var poems: [Poem]

    private let now = Date()

    var body: some View {
        List(selection: $selection) {
            ForEach(PoemStatus.allCases, id: \.self) { status in
                let group = poems.filter { $0.status == status }
                if !group.isEmpty {
                    Section(sectionTitle(status)) {
                        ForEach(group) { poem in
                            NavigationLink(value: poem) {
                                PoemRow(poem: poem, now: now)
                            }
                            .contextMenu {
                                Button("Delete", role: .destructive) { delete(poem) }
                            }
                        }
                        .onDelete { offsets in offsets.map { group[$0] }.forEach(delete) }
                    }
                }
            }
        }
        .navigationTitle("Rote")
        .overlay {
            if poems.isEmpty {
                ContentUnavailableView("No poems yet", systemImage: "text.quote",
                                       description: Text("Add a poem to start learning it by heart."))
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingNewPoem = true } label: { Label("Add poem", systemImage: "plus") }
                    .keyboardShortcut("n", modifiers: .command)
            }
        }
    }

    private func sectionTitle(_ status: PoemStatus) -> String {
        switch status {
        case .draft: "Drafts"
        case .acquiring: "Learning"
        case .reviewing: "Reviewing"
        case .retired: "Retired"
        }
    }

    private func delete(_ poem: Poem) {
        if selection == poem { selection = nil }
        context.delete(poem)
    }
}

struct PoemRow: View {
    let poem: Poem
    let now: Date

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(poem.title).font(.body)
                HStack(spacing: 6) {
                    if let author = poem.author, !author.isEmpty { Text(author) }
                    Text("\(poem.askedLines.count) lines")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            let due = poem.dueItems(now: now).count
            if due > 0 {
                Text("\(due)")
                    .font(.caption.monospacedDigit())
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.18), in: Capsule())
            }
        }
    }
}
