import SwiftUI
import UIKit

/// Background behind grouped lists/forms (cards, settings rows). The stock light-mode
/// `systemGroupedBackground` (#F2F2F7) is barely distinguishable from the white row surface, so light mode
/// uses a deeper grey; dark mode keeps the system colour.
extension Color {
    static let groupedSurfaceBackground = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? .systemGroupedBackground
            : UIColor(red: 0.875, green: 0.875, blue: 0.90, alpha: 1)
    })
}

extension Color {
    /// Sheet backdrop: sheet rows render as a translucent grey, so a white backdrop (light mode) gives them
    /// clearly more separation than the stock #F2F2F7. Dark mode keeps the system colour.
    static let sheetSurfaceBackground = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? .systemGroupedBackground : .white
    })
}

extension View {
    /// For Forms/Lists shown in sheets (settings, editor, detail).
    func sheetSurfaceBackground() -> some View {
        scrollContentBackground(.hidden).background(Color.sheetSurfaceBackground)
    }

    /// Replaces a List/Form's default background with `groupedSurfaceBackground`.
    func groupedSurfaceBackground() -> some View {
        scrollContentBackground(.hidden).background(Color.groupedSurfaceBackground)
    }
}
