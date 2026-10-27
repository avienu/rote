import RoteCore
import SwiftData
import SwiftUI

/// Poems grouped by status with a due count per poem.
struct LibraryView: View {
    @Binding var selection: Poem?
    @Binding var showingNewPoem: Bool
    @Binding var showingReview: Bool
    @Binding var showingSettings: Bool
    @Binding var importing: Bool
    @Environment(\.modelContext) private var context
    @Query(sort: \Poem.title) private var poems: [Poem]

    private let now = Date()

    var body: some View {
        List(selection: $selection) {
            ForEach(PoemStatus.allCases, id: \.self) { status in
                let group = status == .draft ? LearningQueue.ordered(poems.filter { $0.status == .draft }) : poems.filter { $0.status == status }
                if !group.isEmpty {
                    Section {
                        ForEach(group) { poem in
                            NavigationLink(value: poem) {
                                PoemRow(poem: poem, now: now, upNext: status == .draft && poem === group.first)
                            }
                            .contextMenu {
                                if status == .draft, poem !== group.first {
                                    Button { LearningQueue.moveToFront(poem, in: group) } label: { Label("Learn next", systemImage: "arrow.up.to.line") }
                                }
                                Button("Delete", role: .destructive) { delete(poem) }
                            }
                        }
                        .onDelete { offsets in offsets.map { group[$0] }.forEach(delete) }
                        .onMove { offsets, destination in
                            if status == .draft { LearningQueue.move(group, fromOffsets: offsets, toOffset: destination) }
                        }
                        .moveDisabled(status != .draft)
                    } header: {
                        HStack {
                            Text(sectionTitle(status))
                            if status == .draft {
                                Spacer()
                                #if os(iOS)
                                EditButton().font(.caption)
                                #else
                                Text("drag to reorder").font(.caption).foregroundStyle(.tertiary)
                                #endif
                            }
                        }
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
            #if os(iOS)
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button { showingSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                    Button { importing = true } label: { Label("Import poems…", systemImage: "square.and.arrow.down") }
                } label: { Label("More", systemImage: "ellipsis.circle") }
            }
            #endif
            ToolbarItem {
                Button { showingReview = true } label: {
                    Label(dueTotal > 0 ? "Review \(dueTotal)" : "Review", systemImage: "rectangle.stack")
                }
                .disabled(dueTotal == 0)
                .keyboardShortcut("r", modifiers: .command)
            }
        }
        .sheet(isPresented: $showingReview) {
            ReviewSessionView(poems: poems.filter { $0.status == .reviewing })
        }
    }

    private var dueTotal: Int {
        poems.filter { $0.status == .reviewing }.reduce(0) { $0 + $1.dueItems(now: now).count + RunScheduling.dueRuns(poem: $1, now: now).count }
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
    var upNext = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(poem.title).font(.body)
                    if upNext {
                        Text("Up next")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.18), in: Capsule())
                    }
                }
                HStack(spacing: 6) {
                    if let author = poem.author, !author.isEmpty { Text(author) }
                    Text("^[\(poem.askedLines.count) line](inflect: true)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            let due = poem.dueItems(now: now).count + RunScheduling.dueRuns(poem: poem, now: now).count
            if due > 0 {
                Text("\(due)")
                    .font(.caption.monospacedDigit())
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.18), in: Capsule())
            }
        }
    }
}
