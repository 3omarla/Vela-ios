import SwiftUI

/// Material 3 tones in the Google Maps app's arrangement: one blue for primary actions, a light
/// blue tonal fill for secondary ones, flat surfaces with soft elevation.
enum GM {
    static let blue = Color(light: 0x0B57D0, dark: 0xA8C7FA)
    static let onBlue = Color(light: 0xFFFFFF, dark: 0x062E6F)
    static let tonal = Color(light: 0xD3E3FD, dark: 0x004A77)
    static let onTonal = Color(light: 0x041E49, dark: 0xD3E3FD)
    static let surface = Color(light: 0xFFFFFF, dark: 0x1F1F1F)
    static let surfaceHigh = Color(light: 0xF0F4F9, dark: 0x2D2F31)
    static let onSurface = Color(light: 0x1F1F1F, dark: 0xE3E3E3)
    static let muted = Color(light: 0x444746, dark: 0xC4C7C5)
    static let outline = Color(light: 0xC4C7C5, dark: 0x444746)
    static let open = Color(light: 0x146C2E, dark: 0x6DD58C)
    static let closed = Color(light: 0xB3261E, dark: 0xF2B8B5)
    static let star = Color(light: 0xE8A300, dark: 0xFBBC04)
    static let navGreen = Color(light: 0x0F6B3A, dark: 0x0F5530)

    static func elevation(_ level: CGFloat = 1) -> some ViewModifier { Elevation(level: level) }
}

private struct Elevation: ViewModifier {
    let level: CGFloat
    func body(content: Content) -> some View {
        content.shadow(color: .black.opacity(0.12 + 0.04 * level), radius: 2 + 2 * level, y: level)
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { t in
            let v = t.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
                           blue: CGFloat(v & 0xff) / 255, alpha: 1)
        })
    }
}

/// Filled blue pill: the one primary action on a sheet (Directions, Start).
struct FilledPill: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 18).frame(height: 40)
            .foregroundStyle(GM.onBlue)
            .background(GM.blue.opacity(configuration.isPressed ? 0.8 : 1), in: Capsule())
    }
}

/// Light blue tonal pill: secondary actions (Save, Call, Share, Steps).
struct TonalPill: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 16).frame(height: 40)
            .foregroundStyle(GM.onTonal)
            .background(GM.tonal.opacity(configuration.isPressed ? 0.7 : 1), in: Capsule())
    }
}

/// Round icon button on a light surface (sheet close, share).
struct CircleIcon: View {
    let symbol: String
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(GM.muted)
            .frame(width: 32, height: 32)
            .background(GM.surfaceHigh, in: Circle())
    }
}

/// Vela's mark (the two-tone arrow from the app icon), for the search bar.
struct VelaMark: View {
    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 512
            func tri(_ pts: [CGPoint], _ c: Color) {
                var p = Path()
                p.move(to: CGPoint(x: pts[0].x * s, y: pts[0].y * s))
                pts.dropFirst().forEach { p.addLine(to: CGPoint(x: $0.x * s, y: $0.y * s)) }
                p.closeSubpath()
                ctx.fill(p, with: .color(c))
            }
            tri([CGPoint(x: 256, y: 40), CGPoint(x: 116, y: 472), CGPoint(x: 256, y: 390)], Color(light: 0x0D3D43, dark: 0xFFFFFF))
            tri([CGPoint(x: 256, y: 40), CGPoint(x: 396, y: 472), CGPoint(x: 256, y: 390)], Color(light: 0x149387, dark: 0x39E0C8))
        }
        .frame(width: 22, height: 22)
    }
}

/// Mixed Arabic and Latin text in an English layout: each part isolated and the line held
/// left-to-right, so "ملحمة · 17 km" does not flip into "km 17 · ملحمة".
enum Bidi {
    static func isolate(_ s: String) -> String { "\u{2068}\(s)\u{2069}" }
    static func ltr(_ s: String) -> String { "\u{200E}" + isolate(s) }
    static func join(_ parts: [String], _ sep: String = " · ") -> String { "\u{200E}" + parts.map(isolate).joined(separator: sep) }
}
