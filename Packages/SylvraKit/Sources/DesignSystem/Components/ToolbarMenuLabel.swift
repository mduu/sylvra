import SwiftUI

extension View {
    /// Inset for the icon of a toolbar menu with a primary action (icon + chevron): macOS puts the icon
    /// right at the capsule's left edge.
    public func toolbarMenuLabelInset() -> some View {
        padding(.leading, 5)
    }
}
