import RoteCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Sidebar + detail on Mac and iPad; collapses to a stack on iPhone.
struct RootView: View {
    @State private var selection: Poem?
    @State private var showingNewPoem = false
    @State private var showingReview = false
    @State private var showingSettings = false
    @State private var importing = false
    @State private var exportDocument: DataDocument?
    @State private var notice: String?
    @State private var openedFile: PoemFile?
    @State private var showingGuide = false
    @AppStorage("hasSeenGuide") private var hasSeenGuide = false
    @Environment(\.modelContext) private var context
    private var commands: AppCommands { AppCommands.shared }

    var body: some View {
        NavigationSplitView {
            LibraryView(selection: $selection, showingNewPoem: $showingNewPoem, showingReview: $showingReview,
                        showingSettings: $showingSettings, importing: $importing)
        } detail: {
            if let poem = selection {
                PoemDetailView(poem: poem)
            } else {
                ContentUnavailableView {
                    Label("No poem selected", systemImage: "text.book.closed")
                } description: {
                    Text("Pick a poem or add one.")
                } actions: {
                    Button("How Rote works") { showingGuide = true }
                }
            }
        }
        .sheet(isPresented: $showingNewPoem) {
            PoemEditorView(poem: nil) { created in selection = created }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack { SettingsView() }
        }
        .sheet(isPresented: $showingGuide) { GuideView() }
        .onAppear {
            // First launch: explain the flow once. Available later from Help / More / Settings.
            if !hasSeenGuide { showingGuide = true }
        }
        .onChange(of: commands.guideRequested) { _, v in if v { showingGuide = true; commands.guideRequested = false } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result { notice = PoemImport.run(url: url, context: context) }
        }
        // Files opened from Finder, the share sheet or `open -a Rote <file>`:
        // a JSON archive is imported; a text file opens the editor pre-filled.
        // They go to the open window instead of spawning a new one.
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        .onOpenURL { url in
            guard url.isFileURL else { return }
            if url.pathExtension.lowercased() == "json" {
                notice = PoemImport.run(url: url, context: context)
            } else if let file = PoemImport.readText(url: url) {
                openedFile = file
            } else {
                notice = "Could not read \(url.lastPathComponent) as UTF-8 text."
            }
        }
        .sheet(isPresented: Binding(get: { openedFile != nil }, set: { if !$0 { openedFile = nil } })) {
            if let file = openedFile {
                PoemEditorView(poem: nil, prefill: file) { created in selection = created }
            }
        }
        .fileExporter(isPresented: Binding(get: { exportDocument != nil }, set: { if !$0 { exportDocument = nil } }),
                      document: exportDocument, contentType: .json, defaultFilename: "Rote export") { _ in }
        .alert(notice ?? "", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK") { notice = nil }
        }
        .onChange(of: commands.newPoem) { _, v in if v { showingNewPoem = true; commands.newPoem = false } }
        .onChange(of: commands.reviewRequested) { _, v in if v { showingReview = true; commands.reviewRequested = false } }
        .onChange(of: commands.importRequested) { _, v in if v { importing = true; commands.importRequested = false } }
        .onChange(of: commands.exportAllRequested) { _, v in
            if v {
                let poems = (try? context.fetch(FetchDescriptor<Poem>(sortBy: [SortDescriptor(\.title)]))) ?? []
                exportDocument = (try? PoemArchive.jsonData(PoemArchive.export(poems))).map { DataDocument(data: $0, type: .json) }
                commands.exportAllRequested = false
            }
        }
        #if DEBUG
        .task {
            // Screenshot helpers: ROTE_AUTO_REVIEW opens the review session;
            // ROTE_SNAPSHOT (Mac) writes the key window to a PNG and quits.
            let env = ProcessInfo.processInfo.environment
            try? await Task.sleep(for: .seconds(1))
            if env["ROTE_AUTO_GUIDE"] != nil {
                showingGuide = true
            } else if env["ROTE_AUTO_REVIEW"] != nil {
                showingReview = true
            } else if env["ROTE_AUTO_SETTINGS"] != nil {
                showingSettings = true      // the same view the Mac Settings scene shows
            } else if env["ROTE_AUTO_LEARN"] != nil {
                let acquiring = PoemStatus.acquiring.rawValue
                selection = try? context.fetch(FetchDescriptor<Poem>(predicate: #Predicate { $0.statusRaw == acquiring })).first
            } else if env["ROTE_AUTO_LIBRARY"] == nil {   // ROTE_AUTO_LIBRARY stays on the list
                selection = try? context.fetch(FetchDescriptor<Poem>(sortBy: [SortDescriptor(\.title)])).first
            }
            #if os(macOS)
            await DebugSnapshot.runIfRequested()
            #endif
        }
        #endif
    }
}
