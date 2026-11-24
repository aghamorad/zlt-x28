import SwiftUI

/// One material, one signal colour.
///
/// The scene this is designed for: a warm room at night, the router on a shelf,
/// someone checking the connection before a call. Not a SaaS dashboard — a
/// control sheet for a piece of equipment. Warm charcoal ground, cream ink,
/// hairlines instead of shadows, and a single amber signal reserved for the
/// thing that is live. Numbers are tabular so counters never jitter.
enum Theme {
    // Surfaces
    static let paper   = Color(red: 0.090, green: 0.078, blue: 0.067)  // #171411
    static let panel   = Color(red: 0.122, green: 0.106, blue: 0.090)  // #1F1B17
    static let raised  = Color(red: 0.153, green: 0.133, blue: 0.114)  // #27221D

    // Ink
    static let ink     = Color(red: 0.937, green: 0.902, blue: 0.839)  // #EFE6D6
    static let muted   = Color(red: 0.655, green: 0.604, blue: 0.522)  // #A79A85
    static let faint   = Color(red: 0.427, green: 0.388, blue: 0.325)  // #6D6353

    // Signal
    static let amber   = Color(red: 0.890, green: 0.604, blue: 0.294)  // #E39A4B
    static let green   = Color(red: 0.561, green: 0.765, blue: 0.643)  // #8FC3A4
    static let brick   = Color(red: 0.878, green: 0.514, blue: 0.435)  // #E0836F

    static let hairline = Color(red: 0.937, green: 0.902, blue: 0.839).opacity(0.13)
    static let hairlineStrong = Color(red: 0.937, green: 0.902, blue: 0.839).opacity(0.22)

    // Type
    static let title = Font.system(size: 27, weight: .semibold, design: .default)
    static let sectionTitle = Font.system(size: 13, weight: .semibold)
    static let body = Font.system(size: 13, weight: .regular)
    static let value = Font.system(size: 14, weight: .semibold).monospacedDigit()
    static let caption = Font.system(size: 11.5, weight: .regular)
    static let label = Font.system(size: 11, weight: .semibold)
}
