import SwiftUI
import AppKit

// MARK: SVG-pad naar SwiftUI-pad (voor Material Design Icons)

enum SVGPath {
    private struct Reader {
        let c: [Character]
        var i = 0

        init(_ s: String) { c = Array(s) }

        var atEnd: Bool { i >= c.count }

        mutating func skipSeparators() {
            while i < c.count, c[i] == " " || c[i] == "," || c[i] == "\n" || c[i] == "\t" || c[i] == "\r" { i += 1 }
        }

        mutating func peekLetter() -> Character? {
            skipSeparators()
            guard i < c.count, c[i].isLetter else { return nil }
            return c[i]
        }

        mutating func number() -> Double? {
            skipSeparators()
            var j = i
            if j < c.count, c[j] == "-" || c[j] == "+" { j += 1 }
            var digits = false
            var dot = false
            while j < c.count {
                let ch = c[j]
                if ch.isASCII, ch.isNumber { digits = true; j += 1 }
                else if ch == ".", !dot { dot = true; j += 1 }
                else { break }
            }
            guard digits else { return nil }
            if j < c.count, c[j] == "e" || c[j] == "E" {
                var k = j + 1
                if k < c.count, c[k] == "-" || c[k] == "+" { k += 1 }
                var expDigits = false
                while k < c.count, c[k].isASCII, c[k].isNumber { expDigits = true; k += 1 }
                if expDigits { j = k }
            }
            guard let v = Double(String(c[i..<j])) else { return nil }
            i = j
            return v
        }

        /// Vlaggen in een boog-commando zijn één teken en kunnen aan elkaar geplakt staan ("011").
        mutating func flag() -> Bool? {
            skipSeparators()
            guard i < c.count, c[i] == "0" || c[i] == "1" else { return nil }
            defer { i += 1 }
            return c[i] == "1"
        }
    }

    static func parse(_ d: String) -> Path {
        var r = Reader(d)
        var path = Path()
        var cur = CGPoint.zero
        var start = CGPoint.zero
        var lastC: CGPoint?     // laatste kubische controlepunt (voor S)
        var lastQ: CGPoint?     // laatste kwadratische controlepunt (voor T)
        var cmd: Character = " "

        func pt(_ x: Double, _ y: Double, _ rel: Bool) -> CGPoint {
            rel ? CGPoint(x: cur.x + CGFloat(x), y: cur.y + CGFloat(y)) : CGPoint(x: CGFloat(x), y: CGFloat(y))
        }

        while true {
            r.skipSeparators()
            if r.atEnd { break }
            if let letter = r.peekLetter() {
                cmd = letter
                r.i += 1
                if letter == "z" || letter == "Z" {
                    path.closeSubpath()
                    cur = start
                    lastC = nil
                    lastQ = nil
                    continue
                }
            } else if cmd == " " {
                break
            }

            let rel = cmd.isLowercase
            switch cmd.uppercased() {
            case "M":
                guard let x = r.number(), let y = r.number() else { return path }
                let p = pt(x, y, rel)
                path.move(to: p)
                cur = p
                start = p
                cmd = rel ? "l" : "L"      // volgende paren zijn lijnen
                lastC = nil; lastQ = nil
            case "L":
                guard let x = r.number(), let y = r.number() else { return path }
                let p = pt(x, y, rel)
                path.addLine(to: p)
                cur = p
                lastC = nil; lastQ = nil
            case "H":
                guard let x = r.number() else { return path }
                let p = CGPoint(x: rel ? cur.x + CGFloat(x) : CGFloat(x), y: cur.y)
                path.addLine(to: p)
                cur = p
                lastC = nil; lastQ = nil
            case "V":
                guard let y = r.number() else { return path }
                let p = CGPoint(x: cur.x, y: rel ? cur.y + CGFloat(y) : CGFloat(y))
                path.addLine(to: p)
                cur = p
                lastC = nil; lastQ = nil
            case "C":
                guard let x1 = r.number(), let y1 = r.number(), let x2 = r.number(), let y2 = r.number(),
                      let x = r.number(), let y = r.number() else { return path }
                let c1 = pt(x1, y1, rel), c2 = pt(x2, y2, rel), p = pt(x, y, rel)
                path.addCurve(to: p, control1: c1, control2: c2)
                cur = p
                lastC = c2; lastQ = nil
            case "S":
                guard let x2 = r.number(), let y2 = r.number(), let x = r.number(), let y = r.number() else { return path }
                let c1 = lastC.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
                let c2 = pt(x2, y2, rel), p = pt(x, y, rel)
                path.addCurve(to: p, control1: c1, control2: c2)
                cur = p
                lastC = c2; lastQ = nil
            case "Q":
                guard let x1 = r.number(), let y1 = r.number(), let x = r.number(), let y = r.number() else { return path }
                let c = pt(x1, y1, rel), p = pt(x, y, rel)
                path.addQuadCurve(to: p, control: c)
                cur = p
                lastQ = c; lastC = nil
            case "T":
                guard let x = r.number(), let y = r.number() else { return path }
                let c = lastQ.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
                let p = pt(x, y, rel)
                path.addQuadCurve(to: p, control: c)
                cur = p
                lastQ = c; lastC = nil
            case "A":
                guard let rx = r.number(), let ry = r.number(), let rot = r.number(),
                      let large = r.flag(), let sweep = r.flag(),
                      let x = r.number(), let y = r.number() else { return path }
                let p = pt(x, y, rel)
                addArc(&path, from: cur, to: p, rx: rx, ry: ry, rotation: rot, large: large, sweep: sweep)
                cur = p
                lastC = nil; lastQ = nil
            default:
                return path
            }
        }
        return path
    }

    /// Zet een SVG-boog (eindpunt-notatie) om in kubische bézierstukken.
    private static func addArc(_ path: inout Path, from p0: CGPoint, to p1: CGPoint,
                               rx rx0: Double, ry ry0: Double, rotation: Double, large: Bool, sweep: Bool) {
        var rx = abs(rx0), ry = abs(ry0)
        if rx == 0 || ry == 0 || p0 == p1 {
            path.addLine(to: p1)
            return
        }
        let phi = rotation * .pi / 180
        let cosP = cos(phi), sinP = sin(phi)
        let dx = Double(p0.x - p1.x) / 2, dy = Double(p0.y - p1.y) / 2
        let x1 = cosP * dx + sinP * dy
        let y1 = -sinP * dx + cosP * dy

        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 {
            let s = sqrt(lambda)
            rx *= s
            ry *= s
        }
        let sign: Double = (large == sweep) ? -1 : 1
        let num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let den = rx * rx * y1 * y1 + ry * ry * x1 * x1
        let coef = den == 0 ? 0 : sign * sqrt(max(0, num / den))
        let cxp = coef * rx * y1 / ry
        let cyp = coef * -(ry * x1 / rx)
        let cx = cosP * cxp - sinP * cyp + Double(p0.x + p1.x) / 2
        let cy = sinP * cxp + cosP * cyp + Double(p0.y + p1.y) / 2

        let th1 = atan2((y1 - cyp) / ry, (x1 - cxp) / rx)
        var dth = atan2((-y1 - cyp) / ry, (-x1 - cxp) / rx) - th1
        if sweep, dth < 0 { dth += 2 * .pi }
        else if !sweep, dth > 0 { dth -= 2 * .pi }

        let segments = max(1, Int(ceil(abs(dth) / (.pi / 2) - 1e-9)))
        let delta = dth / Double(segments)
        let k = 4.0 / 3.0 * tan(delta / 4)

        func map(_ ux: Double, _ uy: Double) -> CGPoint {
            let x = rx * ux, y = ry * uy
            return CGPoint(x: cosP * x - sinP * y + cx, y: sinP * x + cosP * y + cy)
        }
        var a = th1
        for _ in 0..<segments {
            let cosA = cos(a), sinA = sin(a)
            let cosB = cos(a + delta), sinB = sin(a + delta)
            path.addCurve(to: map(cosB, sinB),
                          control1: map(cosA - k * sinA, sinA + k * cosA),
                          control2: map(cosB + k * sinB, sinB - k * cosB))
            a += delta
        }
    }
}

/// Een MDI-icoon (24x24-raster) schaalbaar in elk kader.
struct MDIShape: Shape {
    let glyph: Path
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        return glyph
            .applying(CGAffineTransform(scaleX: s, y: s))
            .applying(CGAffineTransform(translationX: rect.midX - 12 * s, y: rect.midY - 12 * s))
    }
}

// MARK: Material Design Icons (zoals Home Assistant: "mdi:printer-3d")

/// Haalt de icoonlijst en losse iconen op bij het eerste gebruik en bewaart ze op schijf.
final class MDIStore: ObservableObject {
    static let shared = MDIStore()

    @Published private(set) var names: [String] = []
    @Published private(set) var paths: [String: Path] = [:]
    @Published private(set) var loadingIndex = false

    private var haystack: [String: String] = [:]
    private var requested: Set<String> = []
    private let bases = ["https://cdn.jsdelivr.net/npm/@mdi/svg@7.4.47",
                         "https://raw.githubusercontent.com/Templarian/MaterialDesign-SVG/master"]
    private let dir: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        dir = support.appendingPathComponent("Dokko/mdi", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func fetch(_ relative: String) async -> Data? {
        for base in bases {
            guard let url = URL(string: base + "/" + relative) else { continue }
            var req = URLRequest(url: url, timeoutInterval: 20)
            req.setValue("Dokko", forHTTPHeaderField: "User-Agent")
            if let (data, resp) = try? await URLSession.shared.data(for: req),
               ((resp as? HTTPURLResponse)?.statusCode ?? 0) == 200 {
                return data
            }
        }
        return nil
    }

    func loadIndex() {
        guard names.isEmpty, !loadingIndex else { return }
        loadingIndex = true
        let file = dir.appendingPathComponent("meta.json")
        Task {
            var data = try? Data(contentsOf: file)
            if data == nil, let fresh = await fetch("meta.json") {
                try? fresh.write(to: file)
                data = fresh
            }
            var list: [String] = []
            var hay: [String: String] = [:]
            if let data, let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
                for item in arr {
                    guard let name = item["name"] as? String else { continue }
                    list.append(name)
                    let aliases = (item["aliases"] as? [String]) ?? []
                    let tags = (item["tags"] as? [String]) ?? []
                    hay[name] = ([name.replacingOccurrences(of: "-", with: " ")] + aliases + tags)
                        .joined(separator: " ").lowercased()
                }
            }
            let finalList = list.sorted()
            await MainActor.run {
                self.names = finalList
                self.haystack = hay
                self.loadingIndex = false
            }
        }
    }

    /// Zoekt op naam, alias en label. Kortere namen eerst.
    func search(_ query: String, limit: Int = 60) -> [String] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        let hits = names.filter { n in
            let h = haystack[n] ?? n
            return words.allSatisfy { h.contains($0) }
        }
        return Array(hits.sorted { ($0.count, $0) < ($1.count, $1) }.prefix(limit))
    }

    /// Zorgt dat het pad van dit icoon beschikbaar komt (uit de cache of van het net).
    func ensure(_ name: String) {
        guard paths[name] == nil, !requested.contains(name), !name.isEmpty,
              name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { return }
        requested.insert(name)
        let file = dir.appendingPathComponent(name + ".svg")
        Task {
            var data = try? Data(contentsOf: file)
            if data == nil, let fresh = await fetch("svg/\(name).svg") {
                try? fresh.write(to: file)
                data = fresh
            }
            guard let data, let svg = String(data: data, encoding: .utf8),
                  let re = try? NSRegularExpression(pattern: "\\sd=\"([^\"]+)\""),
                  let m = re.firstMatch(in: svg, range: NSRange(svg.startIndex..., in: svg)),
                  let r = Range(m.range(at: 1), in: svg) else { return }
            let parsed = SVGPath.parse(String(svg[r]))
            await MainActor.run { self.paths[name] = parsed }
        }
    }
}

struct MDIGlyph: View {
    let name: String
    let size: CGFloat
    let color: Color?
    @ObservedObject var store = MDIStore.shared

    var body: some View {
        Group {
            if let p = store.paths[name] {
                MDIShape(glyph: p).fill(color ?? Color.primary)
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .onAppear { store.ensure(name) }
    }
}

/// Eén weergave voor SF Symbols ("lightbulb.fill") en Material Design Icons ("mdi:printer-3d").
struct TileGlyph: View {
    let name: String
    let size: CGFloat
    var color: Color? = nil

    var body: some View {
        if name.hasPrefix("mdi:") {
            MDIGlyph(name: String(name.dropFirst(4)), size: size * 1.1, color: color)
        } else if let color {
            Image(systemName: name).font(.system(size: size)).foregroundColor(color)
        } else {
            Image(systemName: name).font(.system(size: size))
        }
    }
}

// MARK: SF Symbols-catalogus

enum SFSymbolCatalog {
    /// Alle namen die macOS kent, uit het systeembestand. Zonder dat bestand blijft een kleinere lijst over.
    static let all: [String] = {
        let candidates = [
            "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/name_availability.plist",
            "/System/Library/PrivateFrameworks/SFSymbols.framework/Versions/A/Resources/CoreGlyphs.bundle/Contents/Resources/name_availability.plist"
        ]
        for path in candidates {
            if let dict = NSDictionary(contentsOfFile: path),
               let symbols = dict["symbols"] as? [String: Any], !symbols.isEmpty {
                return symbols.keys.sorted()
            }
        }
        return fallback
    }()

    static let fallback: [String] = [
        "printer.fill", "lightbulb.fill", "lamp.floor.fill", "lamp.desk.fill", "power", "fan.fill",
        "lock.fill", "lock.shield.fill", "sparkles", "moon.fill", "sun.max.fill", "tv.fill",
        "speaker.wave.2.fill", "thermometer.medium", "door.garage.closed", "blinds.horizontal.closed",
        "bed.double.fill", "sofa.fill", "house.fill", "bolt.fill", "cpu", "memorychip", "externaldrive.fill",
        "network", "wifi", "antenna.radiowaves.left.and.right", "battery.100", "gauge.medium", "chart.bar.fill",
        "cloud.fill", "cloud.sun.fill", "cloud.rain.fill", "snowflake", "flame.fill", "drop.fill", "leaf.fill",
        "folder.fill", "doc.fill", "terminal.fill", "gearshape.fill", "bell.fill", "calendar", "clock",
        "music.note", "play.fill", "pause.fill", "camera.fill", "video.fill", "mic.fill", "headphones",
        "car.fill", "bicycle", "airplane", "cart.fill", "creditcard.fill", "envelope.fill", "message.fill",
        "phone.fill", "person.fill", "heart.fill", "star.fill", "flag.fill", "bookmark.fill", "tag.fill",
        "key.fill", "shield.fill", "eye.fill", "magnifyingglass", "link", "paperplane.fill", "tray.fill"
    ]

    static func search(_ query: String, limit: Int = 60) -> [String] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return Array(fallback.prefix(limit)) }
        let hits = all.filter { n in
            let h = n.replacingOccurrences(of: ".", with: " ")
            return words.allSatisfy { h.contains($0) }
        }
        return Array(hits.sorted { ($0.count, $0) < ($1.count, $1) }.prefix(limit))
    }
}

// MARK: Icoonkiezer

struct IconPickerView: View {
    let current: String
    let onPick: (String) -> Void

    @State private var source = 0
    @State private var query = ""
    @ObservedObject var mdi = MDIStore.shared

    init(current: String, onPick: @escaping (String) -> Void) {
        self.current = current
        self.onPick = onPick
        _source = State(initialValue: current.hasPrefix("mdi:") ? 1 : 0)
    }

    private var results: [String] {
        source == 0 ? SFSymbolCatalog.search(query) : mdi.search(query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $source) {
                Text("SF Symbols").tag(0)
                Text("Material (MDI)").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            TextField(source == 0 ? "Zoek, bijv. printer of battery" : "Zoek, bijv. printer-3d of vpn",
                      text: $query)
                .textFieldStyle(.roundedBorder)

            if source == 1 && mdi.names.isEmpty {
                Text(mdi.loadingIndex ? "Iconenlijst laden…"
                                      : "Kon de lijst niet ophalen. Controleer de internetverbinding.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if source == 1 && query.isEmpty {
                Text("Typ om te zoeken in \(mdi.names.count) iconen. Dezelfde namen als in Home Assistant.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if results.isEmpty {
                Text("Geen resultaten.").font(.caption).foregroundStyle(.secondary)
            }

            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(46), spacing: 6), count: 6), spacing: 6) {
                    ForEach(results, id: \.self) { name in
                        let full = source == 0 ? name : "mdi:" + name
                        Button { onPick(full) } label: {
                            TileGlyph(name: full, size: 20, color: .primary)
                                .frame(width: 42, height: 36)
                                .background(RoundedRectangle(cornerRadius: 6)
                                    .fill(full == current ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.06)))
                        }
                        .buttonStyle(.plain)
                        .help(full)
                    }
                }
            }
            .frame(height: 250)
        }
        .padding(12)
        .frame(width: 320)
        .onAppear { mdi.loadIndex() }
    }
}
