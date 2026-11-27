import Foundation
import Testing

@testable import FeatureTerminal

@MainActor
private final class NoProcesses: TerminalProcessHosting {
    func terminate(_ id: UUID) {}
}

/// The bell of a tab (Claude Code waiting): a dot unless the user looks at it, the app told either way.
@MainActor
struct TerminalAttentionTests {
    /// Two tabs, the second in view.
    @MainActor
    private struct Fixture {
        let model: TerminalModel
        let first: UUID
        let second: UUID

        init() {
            model = TerminalModel(host: NoProcesses(), defaults: UserDefaults(suiteName: UUID().uuidString)!)
            first = model.openTab(title: "Claude · #812")
            second = model.openTab(title: "zsh")
        }
    }

    private func model() -> (TerminalModel, Fixture) {
        let fixture = Fixture()
        return (fixture.model, fixture)
    }

    @Test func aTabOutOfViewGetsADotAndTheAppIsTold() {
        let (model, tabs) = model()
        let first = tabs.first
        var told: [(String, Bool)] = []
        model.onAttention = { told.append(($0.title, $1)) }
        model.ringBell(first, appIsActive: true)
        #expect(model.sessions.first { $0.id == first }?.needsAttention == true)
        #expect(told.map(\.0) == ["Claude · #812"])
        // Looking at it clears the dot.
        model.selectedID = first
        #expect(model.sessions.first { $0.id == first }?.needsAttention == false)
    }

    @Test func theTabInViewStaysQuiet() {
        let (model, tabs) = model()
        let second = tabs.second
        var told = 0
        model.onAttention = { _, _ in told += 1 }
        model.ringBell(second, appIsActive: true)
        #expect(model.sessions.first { $0.id == second }?.needsAttention == false)
        #expect(told == 0)
    }

    @Test func inTheBackgroundEvenTheTabInViewCounts() {
        let (model, tabs) = model()
        let second = tabs.second
        var background: [Bool] = []
        model.onAttention = { background.append($1) }
        model.ringBell(second, appIsActive: false)
        #expect(background == [false])
    }

    @Test func aHiddenPanelCountsAsOutOfView() {
        let (model, tabs) = model()
        let second = tabs.second
        model.isPresented = false
        model.ringBell(second, appIsActive: true)
        #expect(model.sessions.first { $0.id == second }?.needsAttention == true)
        model.isPresented = true
        #expect(model.sessions.first { $0.id == second }?.needsAttention == false)
    }
}
