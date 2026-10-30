import RoteCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// App-wide settings (§10.7): default input mode, desired retention, Mac audio
/// input device, export and import.
struct SettingsView: View {
    @AppStorage("defaultInputMode") private var defaultModeRaw = InputMode.selfGrade.rawValue
    @AppStorage("desiredRetention") private var desiredRetention = FSRSScheduler.defaultRetention
    @AppStorage("audioInputDeviceUID") private var audioInputDeviceUID = ""
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Poem.title) private var poems: [Poem]

    @State private var exportDocument: DataDocument?
    @State private var importing = false
    @State private var message: String?

    var body: some View {
        Form {
            Section("Review") {
                Picker("Default input", selection: $defaultModeRaw) {
                    Text("Speak").tag(InputMode.speech.rawValue)
                    Text("Type").tag(InputMode.firstLetterTyping.rawValue)
                    Text("Self-grade").tag(InputMode.selfGrade.rawValue)
                }
                LabeledContent("Desired retention") {
                    HStack {
                        Slider(value: $desiredRetention, in: FSRSScheduler.retentionRange, step: 0.01)
                        Text(String(format: "%.0f%%", desiredRetention * 100)).monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
                Text("Higher retention means more frequent reviews. 90% is the FSRS default; poems can override this.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            #if os(macOS)
            Section("Microphone") {
                Picker("Input device", selection: $audioInputDeviceUID) {
                    Text("System default").tag("")
                    ForEach(AudioInputDevices.list()) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
            }
            #endif
            Section("Help") {
                Button("How Rote works…") {
                    AppCommands.shared.guideRequested = true
                    #if os(iOS)
                    dismiss()
                    #endif
                }
            }
            Section("Backup") {
                Button("Export all poems…") { exportAll() }
                    .disabled(poems.isEmpty)
                Button("Import from export…") { importing = true }
                Text("JSON exports include every schedule and review log, so an import restores where you left off.")
                    .font(.caption).foregroundStyle(.secondary)
                if let message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .fileExporter(isPresented: Binding(get: { exportDocument != nil }, set: { if !$0 { exportDocument = nil } }),
                      document: exportDocument, contentType: .json, defaultFilename: "Rote export") { result in
            if case .failure(let error) = result { message = error.localizedDescription }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): message = PoemImport.run(url: url, context: context)
            case .failure(let error): message = error.localizedDescription
            }
        }
        #if os(macOS)
        .frame(width: 480)
        #else
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        #endif
    }

    private func exportAll() {
        do {
            exportDocument = DataDocument(data: try PoemArchive.jsonData(PoemArchive.export(poems)), type: .json)
        } catch {
            message = error.localizedDescription
        }
    }
}

enum PoemImport {
    /// Reads a text file as a poem with an optional title/author header.
    static func readText(url: URL) -> PoemFile? {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return PoemFile.parse(contents)
    }

    /// Imports an export file; poems with a known id are replaced.
    @MainActor
    static func run(url: URL, context: ModelContext) -> String {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let export = try PoemArchive.decode(try Data(contentsOf: url))
            var replaced = 0
            for e in export.poems {
                let id = e.id
                if let existing = try context.fetch(FetchDescriptor<Poem>(predicate: #Predicate { $0.id == id })).first {
                    context.delete(existing)
                    replaced += 1
                }
                context.insert(PoemArchive.makePoem(from: e))
            }
            try context.save()
            return "Imported \(export.poems.count) poems (\(replaced) replaced)."
        } catch {
            return "Import failed: \(error.localizedDescription)"
        }
    }
}
