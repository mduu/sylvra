import SwiftUI
import Testing

@testable import DesignSystem

@MainActor
struct SectionTabBarTests {
    @Test func narrowBarsKeepTheSelectedTabsName() {
        #expect(SectionTabBar<Int>.showsTitle(.selectedTitle, isSelected: true))
        #expect(!SectionTabBar<Int>.showsTitle(.selectedTitle, isSelected: false))
        #expect(!SectionTabBar<Int>.showsTitle(.symbols, isSelected: true))
        #expect(SectionTabBar<Int>.showsTitle(.compact, isSelected: false))
    }

    @Test func tooltipsNameTheShortcutOnlyWhenThereIsOne() {
        #expect(
            SectionTabBar<Int>.help(SectionTabItem(tab: 1, title: "Files", symbol: "doc", shortcut: "2"))
                == "Files (⌘2)")
        #expect(SectionTabBar<Int>.help(SectionTabItem(tab: 1, title: "Chat", symbol: "bubble")) == "Chat")
    }
}
