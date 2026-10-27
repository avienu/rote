import RoteCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Add or edit a poem. The text is stored exactly as typed; Rote never fixes it.
struct PoemEditorView: View {
    let poem: Poem?
    /// Title, author and text to start a new poem from (an opened or dropped file).
    var prefill: PoemFile? = nil
    var onSave: ((Poem) -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var author = ""
    @State private var sourceNote = ""
    @State private var locale = "en-US"
    @State private var text = ""
    @State private var monospaced = false

    static let locales = ["en-US", "en-GB", "fr-FR", "de-DE", "es-ES", "it-IT", "pt-BR"]

    private var parsed: ParsedPoem { PoemParser.parse(text) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title, prompt: Text(parsed.suggestedTitle ?? "Title"))
                    TextField("Author", text: $author)
                    TextField("Source note", text: $sourceNote, prompt: Text("Where the text came from"))
                    Picker("Language", selection: $locale) {
                        ForEach(Self.locales, id: \.self) { Text(Locale.current.localizedString(forIdentifier: $0) ?? $0).tag($0) }
                    }
                }
                Section {
                    TextEditor(text: $text)
                        .font(monospaced ? .system(.body, design: .monospaced) : .system(.body, design: .serif))
                        .frame(minHeight: 280)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .dropDestination(for: URL.self) { urls, _ in loadDroppedFile(urls) }
                } header: {
                    HStack {
                        Text("Text")
                        Spacer()
                        Toggle("Monospaced", isOn: $monospaced).toggleStyle(.switch).controlSize(.mini).labelsHidden()
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(parsed.stanzas.count) stanzas · \(parsed.askedLines.count) lines · \(parsed.lines.count - parsed.askedLines.count) context")
                            .monospacedDigit()
                        Text("Blank line = stanza break. Start a line with @ for a context line (a speaker name, a chorus mark): it is shown but never asked. Indentation is kept.")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(poem == nil ? "New poem" : "Edit poem")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(parsed.askedLines.isEmpty)
                }
            }
        }
        .onAppear(perform: load)
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 620)
        #endif
    }

    private func load() {
        guard let poem else {
            if let prefill { apply(prefill) }
            return
        }
        title = poem.title
        author = poem.author ?? ""
        sourceNote = poem.sourceNote ?? ""
        locale = poem.locale
        text = poem.rawText
    }

    private func save() {
        let finalTitle = title.trimmingCharacters(in: .whitespaces).isEmpty ? (parsed.suggestedTitle ?? "Untitled") : title
        if let poem {
            poem.title = finalTitle
            poem.author = author.isEmpty ? nil : author
            poem.sourceNote = sourceNote.isEmpty ? nil : sourceNote
            poem.locale = locale
            if poem.rawText != text { poem.rebuildStructure(from: text) }
            poem.updatedAt = Date()
            onSave?(poem)
        } else {
            let created = Poem.make(title: finalTitle, author: author.isEmpty ? nil : author, rawText: text, locale: locale)
            created.sourceNote = sourceNote.isEmpty ? nil : sourceNote
            context.insert(created)
            onSave?(created)
        }
        dismiss()
    }

    private func loadDroppedFile(_ urls: [URL]) -> Bool {
        guard let url = urls.first else { return false }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return false }
        apply(PoemFile.parse(contents))
        if sourceNote.isEmpty { sourceNote = url.lastPathComponent }
        return true
    }

    /// Fills empty fields from a file; the user confirms before saving.
    private func apply(_ file: PoemFile) {
        text = file.body
        if title.isEmpty, let t = file.title { title = t }
        if author.isEmpty, let a = file.author { author = a }
    }
}
