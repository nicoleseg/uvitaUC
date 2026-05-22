import SwiftUI

// System background color shims — work on iOS, macOS, and any SDK target
extension Color {
    static let secondaryBackground = Color(
        red: 0.949, green: 0.949, blue: 0.969, opacity: 1) // iOS secondarySystemBackground light
    static let tertiaryBackground  = Color(
        red: 1.0,   green: 1.0,   blue: 1.0,   opacity: 1) // iOS tertiarySystemBackground light
}
