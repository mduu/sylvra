// swift-tools-version: 6.2
import PackageDescription

/// Shared kernel + one target per feature slice (see specs/architecture.md §3).
/// Feature slices depend only on the shared kernel — never on each other.
let sharedKernel: [Target.Dependency] = ["SylvraCore", "Platform", "DesignSystem"]

let featureSlices = [
    "FeatureInbox",
    "FeaturePullRequest",
    "FeatureDiff",
    "FeatureReview",
    "FeatureAIReview",
    "FeatureOpenInIDE",
    "FeatureTerminal",
    "FeatureCustomTools",
    "FeatureActivity",
    "FeatureSettings",
    "FeatureUpdates",
]

/// Composition shared by the app and the `sylvra` command line tool: bridges the diff and AI review slices and
/// runs AI reviews of local changes (see specs/architecture.md §8.8).
let compositionModules = ["LocalReview"]

let allModules = ["SylvraCore", "Platform", "DesignSystem"] + featureSlices + compositionModules

/// Third-party dependencies per slice (keep minimal, see AGENTS.md).
/// SwiftTerm (MIT): terminal emulator + PTY for the terminal panel.
let sliceDependencies: [String: [Target.Dependency]] = [
    "FeatureTerminal": [.product(name: "SwiftTerm", package: "SwiftTerm")]
]

let package = Package(
    name: "SylvraKit",
    defaultLocalization: "en",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "SylvraKit", targets: allModules),
        .executable(name: "sylvra", targets: ["SylvraCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", exact: "1.10.0")
    ],
    targets: [
        .target(name: "SylvraCore"),
        .target(name: "Platform", dependencies: ["SylvraCore"]),
        .target(name: "DesignSystem", dependencies: ["SylvraCore"]),
    ]
        + featureSlices.map { .target(name: $0, dependencies: sharedKernel + (sliceDependencies[$0] ?? [])) }
        + [
            .target(name: "LocalReview", dependencies: ["SylvraCore", "Platform", "FeatureDiff", "FeatureAIReview"]),
            .executableTarget(name: "SylvraCLI", dependencies: ["LocalReview"]),
        ]
        + allModules.map { .testTarget(name: "\($0)Tests", dependencies: [.target(name: $0)]) }
)
