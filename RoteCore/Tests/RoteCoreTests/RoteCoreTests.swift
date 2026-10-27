import Testing
@testable import RoteCore

@Suite struct RoteCoreSmokeTests {
    @Test func versionIsSet() {
        #expect(!RoteCore.version.isEmpty)
    }
}
