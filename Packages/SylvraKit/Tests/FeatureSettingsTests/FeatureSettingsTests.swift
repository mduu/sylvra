import Testing

@testable import FeatureSettings

struct FeatureSettingsTests {
    @Test func moduleBuilds() {
        // Placeholder until the first real tests for FeatureSettings exist.
        #expect(Bool(true))
    }
}

struct AppVersionTests {
    @Test func showsVersionAndBuild() {
        #expect(
            AppVersion.display(info: ["CFBundleShortVersionString": "0.5.16", "CFBundleVersion": "21"]) == "0.5.16 (21)"
        )
        #expect(AppVersion.display(info: ["CFBundleShortVersionString": "0.5.16"]) == "0.5.16")
        #expect(AppVersion.display(info: nil) == "–")
    }
}
