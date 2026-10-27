import RoteCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Per-poem settings (§10.6): context lines, retention override, sleep gate,
/// stats reset, export.
struct PoemSettingsView: View {
    @Bindable var poem: Poem
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("desiredRetention") private var appRetention = FSRSScheduler.defaultRetention

    @State private var settings: PoemSettings
    @State private var overridesRetention: Bool
    @State private var confirmClear = false
    @State private var exportDocument: DataDocument?
    @State private var exportType: UTType = .plainText

    init(poem: Poem) {
        self.poem = poem
        _settings = State(initialValue: poem.settings)
        _overridesRetention = State(initialValue: poem.settings.desiredRetention != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Cards") {
                    Stepper("Context lines: \(settings.contextLines)", value: $settings.contextLines, in: 1...4)
                    Toggle("Override desired retention", isOn: $overridesRetention)
                    if overridesRetention {
                        LabeledContent("Retention") {
                            HStack {
                                Slider(value: Binding(get: { settings.desiredRetention ?? appRetention },
                                                      set: { settings.desiredRetention = $0 }),
                                       in: FSRSScheduler.retentionRange, step: 0.01)
                                Text(String(format: "%.0f%%", (settings.desiredRetention ?? appRetention) * 100)).monospacedDigit()
                            }
                        }
                    }
                }
                Section("Learning") {
                    Toggle("Sleep gate", isOn: $settings.sleepGateEnabled)
                    Text("Off is for testing only. Sleep is part of the method.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Data") {
                    Button("Export as text…") { export(.plainText) }
                    Button("Export as JSON (with schedules)…") { export(.json) }
                    Button("Clear word stats", role: .destructive) { confirmClear = true }
                        .disabled((poem.wordStats ?? []).isEmpty)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Poem settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.keyboardShortcut(.defaultAction) }
            }
            .confirmationDialog("Clear all word stats for this poem?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear stats", role: .destructive) {
                    poem.wordStats = []
                    try? context.save()
                }
            }
            .fileExporter(isPresented: Binding(get: { exportDocument != nil }, set: { if !$0 { exportDocument = nil } }),
                          document: exportDocument, contentType: exportType, defaultFilename: poem.title) { _ in }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 420)
        #endif
    }

    private func export(_ type: UTType) {
        exportType = type
        if type == .json {
            exportDocument = (try? PoemArchive.jsonData(PoemArchive.export([poem]))).map { DataDocument(data: $0, type: .json) }
        } else {
            exportDocument = DataDocument(data: Data(poem.exportText.utf8), type: .plainText)
        }
    }

    private func save() {
        var s = settings
        if !overridesRetention { s.desiredRetention = nil }
        poem.settings = s
        poem.updatedAt = Date()
        try? context.save()
        dismiss()
    }
}
