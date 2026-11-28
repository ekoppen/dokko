import SwiftUI
import AppKit

/// Kleur die we kunnen opslaan (SwiftUI Color is niet Codable).
struct RGBA: Codable, Equatable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    init(color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.black
        self.init(Double(ns.redComponent), Double(ns.greenComponent),
                  Double(ns.blueComponent), Double(ns.alphaComponent))
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
}

enum DockShape: String, Codable, CaseIterable, Identifiable {
    case rounded, capsule, rectangle, cutCorner

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rounded: return "Afgerond"
        case .capsule: return "Capsule"
        case .rectangle: return "Rechthoek"
        case .cutCorner: return "Afgeschuind"
        }
    }
}

enum IconShape: String, Codable, CaseIterable, Identifiable {
    case original, rounded, circle

    var id: String { rawValue }

    var label: String {
        switch self {
        case .original: return "Origineel"
        case .rounded: return "Afgerond vierkant"
        case .circle: return "Cirkel"
        }
    }

    func makeShape(size: CGFloat) -> AnyShape {
        switch self {
        case .original: return AnyShape(Rectangle())
        case .rounded: return AnyShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
        case .circle: return AnyShape(Circle())
        }
    }
}

/// Rechthoek met afgeschuinde hoeken.
struct CutCornerShape: Shape {
    var cut: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = min(cut, min(rect.width, rect.height) / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + c, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - c, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + c))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - c))
        p.addLine(to: CGPoint(x: rect.maxX - c, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + c, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - c))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + c))
        p.closeSubpath()
        return p
    }
}

struct DockTheme: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String

    var shape: DockShape = .rounded
    var cornerRadius: Double = 22
    var colorA: RGBA = RGBA(1, 1, 1, 0.2)
    var useGradient: Bool = false
    var colorB: RGBA = RGBA(0, 0, 0, 0.3)
    var useBlur: Bool = true
    var borderColor: RGBA = RGBA(1, 1, 1, 0.3)
    var borderWidth: Double = 1
    var shadowRadius: Double = 12
    var iconSize: Double = 54
    var spacing: Double = 10
    var paddingTop: Double = 10
    var paddingBottom: Double = 10
    var paddingLeft: Double = 10
    var paddingRight: Double = 10
    var magnification: Double = 1.6
    var magnificationRange: Double = 1.6
    var bottomMargin: Double = 8
    var indicatorColor: RGBA = RGBA(1, 1, 1, 0.9)
    var iconShape: IconShape = .original
    var iconBackgroundEnabled: Bool = false
    var iconBackgroundColor: RGBA = RGBA(1, 1, 1, 0.25)
    var iconInset: Double = 0
    var showLabels: Bool = true
    var animResponse: Double = 0.22
    var animDamping: Double = 0.72
    var launchBounce: Bool = true
    var fadeDuration: Double = 0.2

    // Achtergrond en hover-effecten
    var showBackground: Bool = true
    var iconShadow: Double = 0
    var glowEnabled: Bool = false
    var glowColor: RGBA = RGBA(1, 1, 1, 0.9)
    var glowSize: Double = 1.3
    var glowIntensity: Double = 0.8
    var dimOthers: Bool = false
    var dimAmount: Double = 0.55
    var dimDesaturate: Bool = false

    /// Palet waaruit dit thema is afgeleid (voor hooks)
    var palette: Palette? = nil

    // Positie
    var offsetX: Double = 0
    var fixedWidth: Double = 0      // 0 = breedte volgt de inhoud; anders vaste breedte met scrollen

    enum CodingKeys: String, CodingKey {
        case id, name, shape, cornerRadius, colorA, useGradient, colorB, useBlur, borderColor, borderWidth, shadowRadius, iconSize, spacing, paddingTop, paddingBottom, paddingLeft, paddingRight, magnification, magnificationRange, bottomMargin, indicatorColor, iconShape, iconBackgroundEnabled, iconBackgroundColor, iconInset, showLabels, animResponse, animDamping, launchBounce, fadeDuration, showBackground, iconShadow, glowEnabled, glowColor, glowSize, glowIntensity, dimOthers, dimAmount, dimDesaturate, palette, offsetX, fixedWidth
    }

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }

    /// Tolerant: ontbrekende velden (uit oudere versies/bestanden) krijgen een standaardwaarde.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decode(String.self, forKey: .name)) ?? "Thema"
        if let v = try? c.decode(DockShape.self, forKey: .shape) { shape = v }
        if let v = try? c.decode(Double.self, forKey: .cornerRadius) { cornerRadius = v }
        if let v = try? c.decode(RGBA.self, forKey: .colorA) { colorA = v }
        if let v = try? c.decode(Bool.self, forKey: .useGradient) { useGradient = v }
        if let v = try? c.decode(RGBA.self, forKey: .colorB) { colorB = v }
        if let v = try? c.decode(Bool.self, forKey: .useBlur) { useBlur = v }
        if let v = try? c.decode(RGBA.self, forKey: .borderColor) { borderColor = v }
        if let v = try? c.decode(Double.self, forKey: .borderWidth) { borderWidth = v }
        if let v = try? c.decode(Double.self, forKey: .shadowRadius) { shadowRadius = v }
        if let v = try? c.decode(Double.self, forKey: .iconSize) { iconSize = v }
        if let v = try? c.decode(Double.self, forKey: .spacing) { spacing = v }
        if let v = try? c.decode(Double.self, forKey: .paddingTop) { paddingTop = v }
        if let v = try? c.decode(Double.self, forKey: .paddingBottom) { paddingBottom = v }
        if let v = try? c.decode(Double.self, forKey: .paddingLeft) { paddingLeft = v }
        if let v = try? c.decode(Double.self, forKey: .paddingRight) { paddingRight = v }
        if let v = try? c.decode(Double.self, forKey: .magnification) { magnification = v }
        if let v = try? c.decode(Double.self, forKey: .magnificationRange) { magnificationRange = v }
        if let v = try? c.decode(Double.self, forKey: .bottomMargin) { bottomMargin = v }
        if let v = try? c.decode(RGBA.self, forKey: .indicatorColor) { indicatorColor = v }
        if let v = try? c.decode(IconShape.self, forKey: .iconShape) { iconShape = v }
        if let v = try? c.decode(Bool.self, forKey: .iconBackgroundEnabled) { iconBackgroundEnabled = v }
        if let v = try? c.decode(RGBA.self, forKey: .iconBackgroundColor) { iconBackgroundColor = v }
        if let v = try? c.decode(Double.self, forKey: .iconInset) { iconInset = v }
        if let v = try? c.decode(Bool.self, forKey: .showLabels) { showLabels = v }
        if let v = try? c.decode(Double.self, forKey: .animResponse) { animResponse = v }
        if let v = try? c.decode(Double.self, forKey: .animDamping) { animDamping = v }
        if let v = try? c.decode(Bool.self, forKey: .launchBounce) { launchBounce = v }
        if let v = try? c.decode(Double.self, forKey: .fadeDuration) { fadeDuration = v }
        if let v = try? c.decode(Bool.self, forKey: .showBackground) { showBackground = v }
        if let v = try? c.decode(Double.self, forKey: .iconShadow) { iconShadow = v }
        if let v = try? c.decode(Bool.self, forKey: .glowEnabled) { glowEnabled = v }
        if let v = try? c.decode(RGBA.self, forKey: .glowColor) { glowColor = v }
        if let v = try? c.decode(Double.self, forKey: .glowSize) { glowSize = v }
        if let v = try? c.decode(Double.self, forKey: .glowIntensity) { glowIntensity = v }
        if let v = try? c.decode(Bool.self, forKey: .dimOthers) { dimOthers = v }
        if let v = try? c.decode(Double.self, forKey: .dimAmount) { dimAmount = v }
        if let v = try? c.decode(Bool.self, forKey: .dimDesaturate) { dimDesaturate = v }
        if let v = try? c.decode(Palette.self, forKey: .palette) { palette = v }
        if let v = try? c.decode(Double.self, forKey: .offsetX) { offsetX = v }
        if let v = try? c.decode(Double.self, forKey: .fixedWidth) { fixedWidth = v }
    }

    func makeShape() -> AnyShape {
        switch shape {
        case .rounded: return AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        case .capsule: return AnyShape(Capsule())
        case .rectangle: return AnyShape(Rectangle())
        case .cutCorner: return AnyShape(CutCornerShape(cut: cornerRadius))
        }
    }
}

enum Presets {
    private static func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
    }

    static var all: [DockTheme] {
        [
            DockTheme(id: id(1), name: "Glas"),

            {
                var t = DockTheme(id: id(2), name: "Middernacht")
                t.shape = .rounded
                t.cornerRadius = 28
                t.colorA = RGBA(0.05, 0.08, 0.25, 0.9)
                t.useGradient = true
                t.colorB = RGBA(0.25, 0.05, 0.35, 0.9)
                t.useBlur = false
                t.borderColor = RGBA(0.5, 0.6, 1, 0.6)
                t.dimOthers = true
                t.dimAmount = 0.5
                return t
            }(),

            {
                var t = DockTheme(id: id(3), name: "Neon")
                t.shape = .capsule
                t.colorA = RGBA(0.02, 0.02, 0.05, 0.92)
                t.useBlur = false
                t.borderColor = RGBA(1, 0.1, 0.7, 1)
                t.borderWidth = 2.5
                t.shadowRadius = 22
                t.indicatorColor = RGBA(0.1, 1, 0.9, 1)
                t.iconShape = .circle
                t.iconBackgroundEnabled = true
                t.iconBackgroundColor = RGBA(0.1, 0.1, 0.18, 1)
                t.iconInset = 6
                t.paddingLeft = 16
                t.paddingRight = 16
                t.glowEnabled = true
                t.glowColor = RGBA(1, 0.1, 0.7, 0.95)
                return t
            }(),

            {
                var t = DockTheme(id: id(4), name: "Retro")
                t.shape = .cutCorner
                t.cornerRadius = 16
                t.colorA = RGBA(0.95, 0.6, 0.2, 1)
                t.useGradient = true
                t.colorB = RGBA(0.6, 0.25, 0.1, 1)
                t.useBlur = false
                t.borderColor = RGBA(0.2, 0.1, 0.05, 1)
                t.borderWidth = 3
                t.indicatorColor = RGBA(0.2, 0.1, 0.05, 1)
                t.iconShape = .rounded
                t.launchBounce = true
                return t
            }(),

            {
                var t = DockTheme(id: id(5), name: "Zacht roze")
                t.shape = .capsule
                t.colorA = RGBA(1, 0.8, 0.88, 0.85)
                t.useBlur = true
                t.borderColor = RGBA(1, 1, 1, 0.8)
                t.borderWidth = 2
                t.indicatorColor = RGBA(0.8, 0.2, 0.45, 1)
                t.iconShape = .circle
                t.iconBackgroundEnabled = true
                t.iconBackgroundColor = RGBA(1, 1, 1, 0.6)
                t.iconInset = 5
                t.animDamping = 0.55
                return t
            }(),

            {
                var t = DockTheme(id: id(6), name: "Strak donker")
                t.shape = .rectangle
                t.colorA = RGBA(0.08, 0.08, 0.09, 0.95)
                t.useBlur = false
                t.borderColor = RGBA(1, 1, 1, 0.12)
                t.borderWidth = 1
                t.shadowRadius = 4
                t.magnification = 1.2
                t.bottomMargin = 0
                t.paddingTop = 6
                t.paddingBottom = 6
                t.animDamping = 0.95
                t.launchBounce = false
                return t
            }(),

            {
                var t = DockTheme(id: id(7), name: "Alleen iconen")
                t.showBackground = false
                t.iconShadow = 8
                t.glowEnabled = true
                t.glowColor = RGBA(1, 1, 1, 0.8)
                t.dimOthers = true
                t.dimAmount = 0.6
                t.dimDesaturate = true
                t.paddingTop = 0
                t.paddingBottom = 0
                return t
            }()
        ]
    }
}
