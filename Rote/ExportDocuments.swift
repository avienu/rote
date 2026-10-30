import SwiftUI
import UniformTypeIdentifiers

/// Export payloads for `fileExporter`.
struct DataDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json, .plainText]
    var data: Data
    var type: UTType

    init(data: Data, type: UTType) {
        self.data = data
        self.type = type
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
        type = configuration.contentType
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Cross-view requests raised by menu commands.
@MainActor @Observable
final class AppCommands {
    static let shared = AppCommands()
    var newPoem = false
    var importRequested = false
    var exportAllRequested = false
    var reviewRequested = false
    var settingsRequested = false
    var guideRequested = false
}
