import RoteCore
import SwiftData
import SwiftUI

/// Sidebar + detail on Mac and iPad; collapses to a stack on iPhone.
struct RootView: View {
    @State private var selection: Poem?
    @State private var showingNewPoem = false
    @State private var showingReview = false
    @Environment(\.modelContext) private var context

    var body: some View {
        NavigationSplitView {
            LibraryView(selection: $selection, showingNewPoem: $showingNewPoem, showingReview: $showingReview)
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
        #if DEBUG
        .task {
            // Screenshot helpers: ROTE_AUTO_REVIEW opens the review session;
            // ROTE_SNAPSHOT (Mac) writes the key window to a PNG and quits.
            let env = ProcessInfo.processInfo.environment
            try? await Task.sleep(for: .seconds(1))
            if env["ROTE_AUTO_REVIEW"] != nil {
                showingReview = true
            } else if env["ROTE_AUTO_LEARN"] != nil {
                let acquiring = PoemStatus.acquiring.rawValue
                selection = try? context.fetch(FetchDescriptor<Poem>(predicate: #Predicate { $0.statusRaw == acquiring })).first
            } else {
                selection = try? context.fetch(FetchDescriptor<Poem>(sortBy: [SortDescriptor(\.title)])).first
            }
            #if os(macOS)
            await DebugSnapshot.runIfRequested()
            #endif
        }
        #endif
    }
}
