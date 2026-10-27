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
            container = try RoteSchema.makePersistentContainer(cloudKit: Self.cloudKitAvailable)
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

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
        #if os(macOS)
        .defaultSize(width: 1000, height: 700)
        #endif
    }
}
