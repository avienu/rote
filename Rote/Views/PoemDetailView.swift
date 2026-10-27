import RoteCore
import SwiftData
import SwiftUI

/// Poem text with status and editing. Heat map and stats arrive in later milestones.
struct PoemDetailView: View {
    @Bindable var poem: Poem
    @Environment(\.modelContext) private var context
    @State private var editing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                PoemTextView(poem: poem)
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .navigationTitle(poem.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editing = true } label: { Label("Edit", systemImage: "pencil") }
                    .keyboardShortcut("e", modifiers: .command)
            }
            ToolbarItem {
                Menu {
                    if poem.status == .retired {
                        Button("Unretire") { poem.status = .draft }
                    } else {
                        Button("Retire", role: .destructive) { poem.status = .retired }
                    }
                } label: { Label("More", systemImage: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $editing) { PoemEditorView(poem: poem) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let author = poem.author, !author.isEmpty {
                Text(author).font(.title3).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Text(poem.status.rawValue.capitalized)
                Text("\(poem.askedLines.count) lines, \(poem.orderedStanzas.count) stanzas")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

/// Renders the stored lines exactly, with stanza spacing. Context lines dimmed.
struct PoemTextView: View {
    let poem: Poem

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(poem.orderedStanzas) { stanza in
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(stanza.orderedLines) { line in
                        Text(line.text)
                            .font(.system(.body, design: .serif))
                            .foregroundStyle(line.isContext ? .secondary : .primary)
                            .italic(line.isContext)
                    }
                }
            }
        }
        .textSelection(.enabled)
    }
}
