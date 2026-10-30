import RoteCore
import SwiftData
import SwiftUI
#if os(macOS)
import Security
#endif

@main
struct RoteApp: App {
    let container: ModelContainer

    init() {
        do {
            // ROTE_STORE_PATH points development runs at a throwaway store.
            let storeURL = ProcessInfo.processInfo.environment["ROTE_STORE_PATH"].map { URL(fileURLWithPath: $0) }
            container = try RoteSchema.makePersistentContainer(cloudKit: Self.cloudKitAvailable, url: storeURL)
            #if DEBUG
            SampleData.seedIfRequested(into: container.mainContext)
            #endif
        } catch {
            fatalError("Could not open the Rote store: \(error)")
        }
    }

    /// CloudKit needs the iCloud entitlement. Xcode signs iOS builds with it;
    /// on the Mac an unsigned build would trap, so check the running process.
    /// `ROTE_LOCAL_STORE=1` forces local-only storage for development runs.
    static var cloudKitAvailable: Bool {
        if ProcessInfo.processInfo.environment["ROTE_LOCAL_STORE"] != nil { return false }
        #if os(macOS)
        let task = SecTaskCreateFromSelf(nil)
        let value = task.flatMap { SecTaskCopyValueForEntitlement($0, "com.apple.developer.icloud-services" as CFString, nil) }
        return value != nil
        #else
        return true
        #endif
    }

    private var commands: AppCommands { AppCommands.shared }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
        #if os(macOS)
        .defaultSize(width: 1000, height: 700)
        #endif
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Poem") { commands.newPoem = true }.keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .newItem) {
                Divider()
                Button("Import Poems…") { commands.importRequested = true }.keyboardShortcut("i", modifiers: .command)
                Button("Export All Poems…") { commands.exportAllRequested = true }.keyboardShortcut("e", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .help) {
                Button("How Rote Works") { commands.guideRequested = true }
            }
            CommandMenu("Review") {
                Button("Review Due Cards") { commands.reviewRequested = true }.keyboardShortcut("r", modifiers: .command)
                Divider()
                Text("On a card: space reveals, H hints, R records, 1–4 grade.")
            }
        }
        #if os(macOS)
        Settings {
            SettingsView()
                .modelContainer(container)
        }
        #endif
    }
}
