import RoteCore
import SwiftData
import SwiftUI

/// Sidebar + detail on Mac and iPad; collapses to a stack on iPhone.
struct RootView: View {
    @State private var selection: Poem?
    @State private var showingNewPoem = false
    @Environment(\.modelContext) private var context

    var body: some View {
        NavigationSplitView {
            LibraryView(selection: $selection, showingNewPoem: $showingNewPoem)
        } detail: {
            if let poem = selection {
                PoemDetailView(poem: poem)
            } else {
                ContentUnavailableView("No poem selected", systemImage: "text.book.closed",
                                       description: Text("Pick a poem or add one."))
            }
        }
        .sheet(isPresented: $showingNewPoem) {
            PoemEditorView(poem: nil) { created in selection = created }
        }
        #if DEBUG && os(macOS)
        .task {
            guard DebugSnapshot.requested else { return }
            try? await Task.sleep(for: .seconds(1))
            selection = try? context.fetch(FetchDescriptor<Poem>(sortBy: [SortDescriptor(\.title)])).first
            await DebugSnapshot.runIfRequested()
        }
        #endif
    }
}
