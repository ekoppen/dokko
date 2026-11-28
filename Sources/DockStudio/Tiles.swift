import SwiftUI
import AppKit

// MARK: Modellen

enum TileSide: String, Codable, CaseIterable { case left, right }

enum TileKind: String, Codable, CaseIterable, Identifiable {
    case ha, shell, http, vpn, system, claude, clock, weather, button
    var id: String { rawValue }
    var label: String {
        switch self {
        case .ha: return "Home Assistant"
        case .shell: return "Shell-commando"
        case .http: return "URL (JSON)"
        case .vpn: return "VPN-status"
        case .system: return "Systeem"
        case .claude: return "Claude-verbruik"
        case .clock: return "Klok"
        case .weather: return "Weer"
        case .button: return "Knop (alleen actie)"
        }
    }
    /// Bronnen met een eenheid en een instelbare ring.
    var hasNumericValue: Bool { self == .ha || self == .shell || self == .http }
    /// Bronnen waarbij de gebruiker de weergave (waarde/ring/status) kiest.
    var choosesDisplay: Bool { !(self == .clock || self == .weather || self == .button) }
    /// Bronnen die periodiek worden opgehaald.
    var hasInterval: Bool { !(self == .clock || self == .button) }
}

enum TileAction: String, Codable, CaseIterable, Identifiable {
    case none, folder, server, url, shell, ha
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "Niets"
        case .folder: return "Map of bestand openen"
        case .server: return "Serveradres openen (smb://…)"
        case .url: return "Webadres openen"
        case .shell: return "Shell-commando uitvoeren"
        case .ha: return "Home Assistant-actie"
        }
    }
    var placeholder: String {
        switch self {
        case .none: return ""
        case .folder: return "~/Downloads of /Volumes/DATA/dev"
        case .server: return "smb://nas.local/share"
        case .url: return "https://home.example.nl"
        case .shell: return "open -a Terminal"
        case .ha: return "script.film_avond of light.woonkamer"
        }
    }
}

enum TileDisplay: String, Codable, CaseIterable { case value, ring, status }
enum SystemMetric: String, Codable, CaseIterable, Identifiable {
    case cpu, memory, battery, disk
    var id: String { rawValue }
    var label: String {
        switch self {
        case .cpu: return "Processor"
        case .memory: return "Geheugen in gebruik"
        case .battery: return "Accu"
        case .disk: return "Schijf in gebruik"
        }
    }
}
enum ClaudePeriod: String, Codable, CaseIterable { case day, week }

private extension KeyedDecodingContainer {
    func get<T: Decodable>(_ key: Key, _ def: T) -> T { (try? decode(T.self, forKey: key)) ?? def }
}

struct TileConfig: Codable, Identifiable, Equatable {
    var id = UUID()
    var title = "Tegel"
    var kind: TileKind = .ha
    var side: TileSide = .right
    var symbol = "gauge.medium"
    var display: TileDisplay = .value
    var entity = ""                 // Home Assistant
    var command = ""                // shell
    var url = ""                    // http
    var jsonPath = ""
    var metric: SystemMetric = .cpu
    var period: ClaudePeriod = .day
    var unit = ""
    var lo = 0.0                    // ondergrens voor de ring
    var hi = 100.0                  // bovengrens (bij Claude: budget in tokens, 0 = geen ring)
    var interval = 30.0
    var color: RGBA? = nil
    var action: TileAction = .none  // wat een klik doet
    var actionTarget = ""
    var timezone = ""               // klok: leeg = lokale tijd
    var place = ""                  // weer: plaatsnaam
    var edge = false                // tegen de schermrand i.p.v. naast de dock

    enum CodingKeys: String, CodingKey {
        case id, title, kind, side, symbol, display, entity, command, url, jsonPath
        case metric, period, unit, lo, hi, interval, color, action, actionTarget, timezone, place, edge
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.get(.id, UUID())
        title = c.get(.title, "Tegel")
        kind = c.get(.kind, TileKind.ha)
        side = c.get(.side, TileSide.right)
        symbol = c.get(.symbol, "gauge.medium")
        display = c.get(.display, TileDisplay.value)
        entity = c.get(.entity, "")
        command = c.get(.command, "")
        url = c.get(.url, "")
        jsonPath = c.get(.jsonPath, "")
        metric = c.get(.metric, SystemMetric.cpu)
        period = c.get(.period, ClaudePeriod.day)
        unit = c.get(.unit, "")
        lo = c.get(.lo, 0.0)
        hi = c.get(.hi, 100.0)
        interval = c.get(.interval, 30.0)
        color = try? c.decode(RGBA.self, forKey: .color)
        action = c.get(.action, TileAction.none)
        actionTarget = c.get(.actionTarget, "")
        timezone = c.get(.timezone, "")
        place = c.get(.place, "")
        edge = c.get(.edge, false)
    }
}

struct TileValue: Equatable {
    var text: String
    var fraction: Double? = nil
    var ok: Bool? = nil
    var symbol: String? = nil       // bron mag het symbool bepalen (weer)

    static func number(_ v: Double, unit: String, lo: Double, hi: Double) -> TileValue {
        let s = v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
        let frac: Double? = hi > lo ? Swift.min(Swift.max((v - lo) / (hi - lo), 0), 1) : nil
        return TileValue(text: s + unit, fraction: frac, ok: nil)
    }

    static func fromString(_ raw: String, unit: String, lo: Double, hi: Double) -> TileValue {
        if let v = Double(raw.replacingOccurrences(of: ",", with: ".")) {
            return number(v, unit: unit, lo: lo, hi: hi)
        }
        let on = ["on", "open", "unlocked", "playing", "home", "printing", "heat", "cool", "true"]
        let names = ["on": "Aan", "off": "Uit", "unavailable": "n.b.", "unknown": "?", "home": "Thuis",
                     "not_home": "Weg", "open": "Open", "closed": "Dicht", "true": "Ja", "false": "Nee"]
        return TileValue(text: names[raw.lowercased()] ?? raw.prefix(1).uppercased() + raw.dropFirst(),
                         fraction: nil, ok: on.contains(raw.lowercased()))
    }

    static func fromAny(_ v: Any?, unit: String, lo: Double, hi: Double) -> TileValue {
        if let n = v as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                let b = n.boolValue
                return TileValue(text: b ? "Aan" : "Uit", fraction: nil, ok: b)
            }
            return number(n.doubleValue, unit: unit, lo: lo, hi: hi)
        }
        if let s = v as? String { return fromString(s, unit: unit, lo: lo, hi: hi) }
        return TileValue(text: "–")
    }
}

/// Live waarden van de tegels (apart, zodat een nieuwe meting het dock-venster niet opnieuw indeelt).
final class TileData: ObservableObject {
    static let shared = TileData()
    @Published var values: [UUID: TileValue] = [:]
}

// MARK: Store

final class TileStore: ObservableObject {
    static let shared = TileStore()
    static let defaultGap = 12.0

    @Published var tiles: [TileConfig] { didSet { save() } }
    /// Afstand tussen dock en tegels, per kant.
    @Published var gapLeft: Double { didSet { save() } }
    @Published var gapRight: Double { didSet { save() } }
    /// Afstand van randtegels tot de schermrand, per kant (nil = zelfde als de afstand tot de onderrand).
    @Published var edgeLeft: Double? { didSet { save() } }
    @Published var edgeRight: Double? { didSet { save() } }
    @Published var enabled: Bool { didSet { save() } }
    @Published var leftTheme: UUID? { didSet { save() } }
    @Published var rightTheme: UUID? { didSet { save() } }

    private let key = "dockstudio.tiles"
    private struct Blob: Codable {
        var tiles: [TileConfig]
        var enabled: Bool
        var leftTheme: UUID?
        var rightTheme: UUID?
        var gapLeft: Double?
        var gapRight: Double?
        var edgeLeft: Double?
        var edgeRight: Double?
    }

    private var lastRun: [UUID: Date] = [:]
    private var running: Set<UUID> = []
    private var timer: Timer?

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let b = try? JSONDecoder().decode(Blob.self, from: data) {
            tiles = b.tiles
            enabled = b.enabled
            leftTheme = b.leftTheme
            rightTheme = b.rightTheme
            gapLeft = b.gapLeft ?? Self.defaultGap
            gapRight = b.gapRight ?? Self.defaultGap
            edgeLeft = b.edgeLeft
            edgeRight = b.edgeRight
        } else {
            tiles = []
            enabled = true
            leftTheme = nil
            rightTheme = nil
            gapLeft = Self.defaultGap
            gapRight = Self.defaultGap
            edgeLeft = nil
            edgeRight = nil
        }
    }

    private func save() {
        let b = Blob(tiles: tiles, enabled: enabled, leftTheme: leftTheme, rightTheme: rightTheme,
                     gapLeft: gapLeft, gapRight: gapRight, edgeLeft: edgeLeft, edgeRight: edgeRight)
        if let data = try? JSONEncoder().encode(b) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    // Geometrie

    func tiles(on side: TileSide, edge: Bool = false) -> [TileConfig] {
        tiles.filter { $0.side == side && $0.edge == edge }
    }

    func sideTheme(_ side: TileSide, main: DockTheme) -> DockTheme {
        let id = side == .left ? leftTheme : rightTheme
        if let id, let th = ThemeStore.shared.themes.first(where: { $0.id == id }) { return th }
        return main
    }

    func sideWidth(_ side: TileSide, main t: DockTheme, edge: Bool = false) -> CGFloat {
        guard enabled else { return 0 }
        let n = tiles(on: side, edge: edge).count
        guard n > 0 else { return 0 }
        let th = sideTheme(side, main: t)
        return CGFloat(n) * CGFloat(t.iconSize) + CGFloat(n - 1) * CGFloat(th.spacing)
            + CGFloat(th.paddingLeft + th.paddingRight)
    }

    func gap(_ side: TileSide) -> CGFloat { CGFloat(max(side == .left ? gapLeft : gapRight, 0)) }

    /// Afstand van de randtegels tot de schermrand.
    func edgeMargin(_ side: TileSide, main t: DockTheme) -> CGFloat {
        CGFloat(max((side == .left ? edgeLeft : edgeRight) ?? t.bottomMargin, 0))
    }

    /// Extra breedte aan weerszijden van de hoofd-dock (het venster blijft symmetrisch).
    func sideExtent(main t: DockTheme) -> CGFloat {
        TileSide.allCases.map { s -> CGFloat in
            let w = sideWidth(s, main: t)
            return w > 0 ? w + gap(s) : 0
        }.max() ?? 0
    }

    // Waarden

    func value(for t: TileConfig) -> TileValue {
        if t.kind == .clock || t.kind == .button { return TileValue(text: "") }
        if t.kind == .ha {
            guard let s = HAStore.shared.states[t.entity] else { return TileValue(text: "…") }
            return TileValue.fromString(s, unit: t.unit, lo: t.lo, hi: t.hi)
        }
        return TileData.shared.values[t.id] ?? TileValue(text: "…")
    }

    func token(for id: UUID) -> String? { Keychain.get(account: "tile-\(id.uuidString)") }
    func setToken(_ token: String, for id: UUID) { Keychain.set(token, account: "tile-\(id.uuidString)") }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.tick() }
        tick()
    }

    func refreshAll() {
        lastRun = [:]
        tick()
    }

    private func tick() {
        guard enabled else { return }
        let now = Date()
        for t in tiles where t.kind != .ha && t.kind != .clock && t.kind != .button && !running.contains(t.id) {
            let due = (lastRun[t.id].map { now.timeIntervalSince($0) } ?? .infinity) >= max(t.interval, 5)
            guard due else { continue }
            running.insert(t.id)
            lastRun[t.id] = now
            let token = t.kind == .http ? self.token(for: t.id) : nil
            Task.detached(priority: .utility) { [weak self] in
                let v = await TileProviders.compute(t, token: token)
                DispatchQueue.main.async {
                    self?.running.remove(t.id)
                    if let v { TileData.shared.values[t.id] = v }
                }
            }
        }
    }

    // Acties

    func perform(_ t: TileConfig) {
        var target = t.actionTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.action != .none, !target.isEmpty else { return }
        switch t.action {
        case .none:
            break
        case .folder:
            NSWorkspace.shared.open(URL(fileURLWithPath: (target as NSString).expandingTildeInPath))
        case .server:
            if !target.contains("://") { target = "smb://" + target }
            if let u = URL(string: target) { NSWorkspace.shared.open(u) }
        case .url:
            if !target.contains("://") { target = "https://" + target }
            if let u = URL(string: target) { NSWorkspace.shared.open(u) }
        case .shell:
            DispatchQueue.global(qos: .userInitiated).async { _ = TileProviders.shell(target, timeout: 60) }
        case .ha:
            HAStore.shared.activate(target)
        }
    }

    /// Heeft deze kant minstens één tegel die op een klik reageert?
    func hasActions(on side: TileSide, edge: Bool = false) -> Bool {
        enabled && tiles(on: side, edge: edge).contains { $0.action != .none }
    }

    // Voorbeeldtegels

    enum Preset { case printer, vpn, claude, cpu, battery, command, url, clock, weather, folder, server }

    func add(_ p: Preset) {
        var t = TileConfig()
        switch p {
        case .printer:
            t.title = "Print"; t.kind = .ha; t.symbol = "printer.fill"; t.display = .ring; t.unit = "%"
        case .vpn:
            t.title = "VPN"; t.kind = .vpn; t.symbol = "lock.shield.fill"; t.display = .status; t.interval = 15
        case .claude:
            t.title = "Claude"; t.kind = .claude; t.symbol = "sparkles"; t.display = .value; t.hi = 0; t.interval = 60
        case .cpu:
            t.title = "CPU"; t.kind = .system; t.metric = .cpu; t.symbol = "cpu"; t.display = .ring; t.interval = 10
        case .battery:
            t.title = "Accu"; t.kind = .system; t.metric = .battery; t.symbol = "battery.75percent"
            t.display = .ring; t.interval = 60
        case .command:
            t.title = "Commando"; t.kind = .shell; t.symbol = "terminal.fill"
        case .url:
            t.title = "URL"; t.kind = .http; t.symbol = "network"
        case .clock:
            t.title = "Klok"; t.kind = .clock; t.symbol = "clock"
        case .weather:
            t.title = "Weer"; t.kind = .weather; t.symbol = "cloud.sun.fill"; t.display = .value; t.interval = 600
        case .folder:
            t.title = "Downloads"; t.kind = .button; t.symbol = "folder.fill"
            t.action = .folder; t.actionTarget = "~/Downloads"
        case .server:
            t.title = "Server"; t.kind = .button; t.symbol = "externaldrive.connected.to.line.below.fill"
            t.action = .server; t.actionTarget = "smb://"
        }
        tiles.append(t)
        refreshAll()
    }

    func move(_ id: UUID, by offset: Int) {
        guard let i = tiles.firstIndex(where: { $0.id == id }) else { return }
        // Verplaats binnen dezelfde kant
        let side = tiles[i].side
        let edge = tiles[i].edge
        let same = tiles.indices.filter { tiles[$0].side == side && tiles[$0].edge == edge }
        guard let pos = same.firstIndex(of: i), same.indices.contains(pos + offset) else { return }
        tiles.swapAt(i, same[pos + offset])
    }
}

// MARK: Bronnen

enum TileProviders {
    static func compute(_ t: TileConfig, token: String?) async -> TileValue? {
        switch t.kind {
        case .ha: return nil
        case .shell: return shellValue(t)
        case .http: return await httpValue(t, token: token)
        case .vpn: return vpn()
        case .system: return system(t)
        case .claude: return claude(t)
        case .weather: return await weather(t)
        case .clock, .button: return nil
        }
    }

    // Weer via Open-Meteo (gratis, geen sleutel)

    private static let geoLock = NSLock()
    private static var geoCache: [String: [Double]] = [:]
    private static func cachedCoord(_ key: String) -> [Double]? {
        geoLock.lock(); defer { geoLock.unlock() }
        return geoCache[key]
    }
    private static func storeCoord(_ key: String, _ v: [Double]) {
        geoLock.lock(); defer { geoLock.unlock() }
        geoCache[key] = v
    }

    private static func json(_ url: URL) async -> [String: Any]? {
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("Dokko", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              ((resp as? HTTPURLResponse)?.statusCode ?? 0) < 300 else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func weatherSymbol(code: Int, day: Bool) -> String {
        switch code {
        case 0: return day ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return day ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 80...82: return "cloud.heavyrain.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    static func weather(_ t: TileConfig) async -> TileValue? {
        let place = t.place.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !place.isEmpty else { return TileValue(text: "plaats?") }
        let key = place.lowercased()
        var coord = cachedCoord(key)
        if coord == nil {
            var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
            c.queryItems = [URLQueryItem(name: "name", value: place), URLQueryItem(name: "count", value: "1"),
                            URLQueryItem(name: "language", value: "nl"), URLQueryItem(name: "format", value: "json")]
            guard let url = c.url, let obj = await json(url),
                  let r = (obj["results"] as? [[String: Any]])?.first,
                  let lat = (r["latitude"] as? NSNumber)?.doubleValue,
                  let lon = (r["longitude"] as? NSNumber)?.doubleValue else { return TileValue(text: "onbekend") }
            coord = [lat, lon]
            storeCoord(key, [lat, lon])
        }
        guard let ll = coord else { return nil }
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [URLQueryItem(name: "latitude", value: String(ll[0])),
                        URLQueryItem(name: "longitude", value: String(ll[1])),
                        URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day")]
        guard let url = c.url, let obj = await json(url),
              let cur = obj["current"] as? [String: Any],
              let temp = (cur["temperature_2m"] as? NSNumber)?.doubleValue else { return TileValue(text: "fout") }
        let code = (cur["weather_code"] as? NSNumber)?.intValue ?? 3
        let day = ((cur["is_day"] as? NSNumber)?.intValue ?? 1) == 1
        return TileValue(text: "\(Int(temp.rounded()))°", fraction: nil, ok: nil,
                         symbol: weatherSymbol(code: code, day: day))
    }

    static func shell(_ command: String, timeout: TimeInterval = 15) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", command]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            if p.isRunning { p.terminate() }
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    /// Eerste regel is de tekst. "tekst|42" voegt een voortgang van 0-100 toe voor de ring.
    static func shellValue(_ t: TileConfig) -> TileValue {
        guard !t.command.isEmpty else { return TileValue(text: "cmd?") }
        guard let out = shell(t.command) else { return TileValue(text: "fout") }
        let line = out.split(separator: "\n").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        if line.isEmpty { return TileValue(text: "–") }
        if let bar = line.lastIndex(of: "|"), let pct = Double(line[line.index(after: bar)...]
            .trimmingCharacters(in: .whitespaces)) {
            let text = String(line[..<bar]).trimmingCharacters(in: .whitespaces)
            return TileValue(text: text, fraction: Swift.min(Swift.max(pct / 100, 0), 1), ok: nil)
        }
        return TileValue.fromString(line, unit: t.unit, lo: t.lo, hi: t.hi)
    }

    static func httpValue(_ t: TileConfig, token: String?) async -> TileValue {
        guard let url = URL(string: t.url), !t.url.isEmpty else { return TileValue(text: "URL?") }
        var req = URLRequest(url: url, timeoutInterval: 10)
        if let token, !token.isEmpty { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              ((resp as? HTTPURLResponse)?.statusCode ?? 0) < 300 else { return TileValue(text: "fout") }
        let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        var cur: Any? = obj
        for part in t.jsonPath.split(separator: ".").map(String.init) {
            if let d = cur as? [String: Any] { cur = d[part] }
            else if let a = cur as? [Any], let i = Int(part), a.indices.contains(i) { cur = a[i] }
            else { cur = nil; break }
        }
        return TileValue.fromAny(cur, unit: t.unit, lo: t.lo, hi: t.hi)
    }

    static func vpn() -> TileValue {
        let out = shell("scutil --nc list 2>/dev/null; ifconfig -a 2>/dev/null") ?? ""
        var connected = out.contains("(Connected)")
        if !connected {
            var name = ""
            var hasV4 = false
            for line in out.split(separator: "\n", omittingEmptySubsequences: false) {
                if let f = line.first, f != " ", f != "\t" {
                    if name.hasPrefix("utun"), hasV4 { connected = true }
                    name = String(line.split(separator: ":").first ?? "")
                    hasV4 = false
                } else {
                    let parts = line.split(separator: " ")
                    if let i = parts.firstIndex(of: "inet"), i + 1 < parts.count,
                       !parts[i + 1].hasPrefix("169.254") { hasV4 = true }
                }
            }
            if name.hasPrefix("utun"), hasV4 { connected = true }
        }
        return TileValue(text: connected ? "Aan" : "Uit", fraction: nil, ok: connected)
    }

    private static func match(_ pattern: String, in text: String) -> Double? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: text) else { return nil }
        return Double(text[r].replacingOccurrences(of: ",", with: "."))
    }

    private static func percent(_ v: Double) -> TileValue {
        TileValue(text: "\(Int(v.rounded()))%", fraction: Swift.min(Swift.max(v / 100, 0), 1), ok: nil)
    }

    static func system(_ t: TileConfig) -> TileValue {
        switch t.metric {
        case .cpu:
            let out = shell("top -l 1 -n 0 | grep 'CPU usage'") ?? ""
            guard let idle = match("([0-9]+[.,]?[0-9]*)% idle", in: out) else { return TileValue(text: "?") }
            return percent(100 - idle)
        case .memory:
            let out = shell("memory_pressure | grep 'free percentage'") ?? ""
            guard let free = match("free percentage:\\s*([0-9]+)", in: out) else { return TileValue(text: "?") }
            return percent(100 - free)
        case .battery:
            let out = shell("pmset -g batt") ?? ""
            guard let v = match("([0-9]+)%", in: out) else { return TileValue(text: "–") }
            var r = percent(v)
            r.ok = out.contains("charging") && !out.contains("discharging")
            return r
        case .disk:
            let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
            guard let r = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
                  let total = r.volumeTotalCapacity, total > 0,
                  let avail = r.volumeAvailableCapacityForImportantUsage else { return TileValue(text: "?") }
            return percent((1 - Double(avail) / Double(total)) * 100)
        }
    }

    private static func tokens(_ v: Double) -> String {
        if v >= 1_000_000 { return String(format: "%.1fM", v / 1_000_000) }
        if v >= 1_000 { return String(format: "%.0fk", v / 1_000) }
        return String(Int(v))
    }

    /// Telt tokens (invoer + uitvoer + cache-aanmaak) uit de lokale Claude Code-logs.
    static func claude(_ t: TileConfig) -> TileValue {
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        guard let en = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return TileValue(text: "geen logs")
        }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let start = t.period == .day ? today : (cal.date(byAdding: .day, value: -6, to: today) ?? today)
        let iso1 = ISO8601DateFormatter()
        iso1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso2 = ISO8601DateFormatter()

        var seen = Set<String>()
        var total = 0.0
        for case let url as URL in en where url.pathExtension == "jsonl" {
            guard let m = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                  m >= start,
                  let data = try? Data(contentsOf: url, options: .mappedIfSafe),
                  let text = String(data: data, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n") where line.contains("\"usage\"") {
                guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      let msg = obj["message"] as? [String: Any],
                      let usage = msg["usage"] as? [String: Any],
                      let ts = obj["timestamp"] as? String,
                      let date = iso1.date(from: ts) ?? iso2.date(from: ts), date >= start else { continue }
                if let id = msg["id"] as? String, !id.isEmpty {
                    let key = id + ":" + ((obj["requestId"] as? String) ?? "")
                    if !seen.insert(key).inserted { continue }
                }
                for k in ["input_tokens", "output_tokens", "cache_creation_input_tokens"] {
                    total += (usage[k] as? NSNumber)?.doubleValue ?? 0
                }
            }
        }
        let frac: Double? = t.hi > 0 ? Swift.min(total / t.hi, 1) : nil
        return TileValue(text: tokens(total), fraction: frac, ok: nil)
    }
}

// MARK: Weergave

struct TilesBar: View {
    let side: TileSide
    var edge = false
    let mainTheme: DockTheme
    let width: CGFloat
    @ObservedObject var store = TileStore.shared

    var body: some View {
        let theme = store.sideTheme(side, main: mainTheme)
        let items = store.tiles(on: side, edge: edge)
        ZStack(alignment: .bottom) {
            if theme.showBackground {
                DockBackground(theme: theme)
                    .frame(width: width, height: DockLayout.barHeight(mainTheme))
            }
            HStack(alignment: .bottom, spacing: CGFloat(theme.spacing)) {
                ForEach(items) { tile in
                    TileView(tile: tile, theme: theme, size: CGFloat(mainTheme.iconSize))
                }
            }
            .padding(.bottom, CGFloat(mainTheme.paddingBottom) + DockLayout.dotArea)
        }
        .frame(width: width, height: DockLayout.barHeight(mainTheme), alignment: .bottom)
    }
}

struct TileView: View {
    let tile: TileConfig
    let theme: DockTheme
    let size: CGFloat
    @ObservedObject var ha = HAStore.shared
    @ObservedObject var data = TileData.shared
    @State private var flash = false

    var body: some View {
        let v = TileStore.shared.value(for: tile)
        let p = theme.effectivePalette
        let fg = p.fg.color
        let accent = (tile.color ?? p.ac).color
        let shape = theme.iconShape.makeShape(size: size)
        ZStack {
            shape.fill(theme.iconBackgroundEnabled ? theme.iconBackgroundColor.color : fg.opacity(0.10))
            content(v, fg, accent)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.25), radius: CGFloat(theme.iconShadow), y: CGFloat(theme.iconShadow) / 3)
        .scaleEffect(flash ? 0.9 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            guard tile.action != .none else { return }
            withAnimation(.easeOut(duration: 0.1)) { flash = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.easeOut(duration: 0.15)) { flash = false }
            }
            TileStore.shared.perform(tile)
        }
        .help(tile.action == .none ? "" : tile.title)
    }

    @ViewBuilder
    private func content(_ v: TileValue, _ fg: Color, _ accent: Color) -> some View {
        switch tile.kind {
        case .clock:
            ClockTileContent(tile: tile, size: size, fg: fg)
        case .button:
            VStack(spacing: 3) {
                TileGlyph(name: tile.symbol, size: size * 0.4, color: accent)
                Text(tile.title)
                    .font(.system(size: size * 0.16, weight: .medium))
                    .foregroundColor(fg.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 3)
        default:
            valueContent(v, fg, accent)
        }
    }

    @ViewBuilder
    private func valueContent(_ v: TileValue, _ fg: Color, _ accent: Color) -> some View {
        let sym = v.symbol ?? tile.symbol
        switch tile.display {
        case .ring:
            ZStack {
                Circle().stroke(fg.opacity(0.15), lineWidth: size * 0.09)
                Circle()
                    .trim(from: 0, to: CGFloat(v.fraction ?? 0))
                    .stroke(accent, style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.4), value: v.fraction)
                VStack(spacing: 0) {
                    TileGlyph(name: sym, size: size * 0.2, color: accent)
                    Text(v.text)
                        .font(.system(size: size * 0.22, weight: .bold, design: .rounded))
                        .foregroundColor(fg)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
                .padding(size * 0.16)
            }
            .padding(size * 0.08)
        case .status:
            VStack(spacing: 2) {
                TileGlyph(name: sym, size: size * 0.36, color: (v.ok ?? false) ? accent : fg.opacity(0.4))
                Text(v.text)
                    .font(.system(size: size * 0.2, weight: .bold, design: .rounded))
                    .foregroundColor(fg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        case .value:
            VStack(spacing: 1) {
                TileGlyph(name: sym, size: size * 0.2, color: accent)
                Text(v.text)
                    .font(.system(size: size * 0.3, weight: .bold, design: .rounded))
                    .foregroundColor(fg)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(tile.title)
                    .font(.system(size: size * 0.15))
                    .foregroundColor(fg.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 4)
        }
    }
}


/// Klok met tijd en datum (of plaatsnaam bij een andere tijdzone).
struct ClockTileContent: View {
    let tile: TileConfig
    let size: CGFloat
    let fg: Color

    private func text(_ date: Date, _ format: String, _ tz: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "nl_NL")
        f.timeZone = tz
        f.dateFormat = format
        return f.string(from: date)
    }

    var body: some View {
        TimelineView(.everyMinute) { ctx in
            let tz = TimeZone(identifier: tile.timezone) ?? .current
            VStack(spacing: 1) {
                Text(text(ctx.date, "HH:mm", tz))
                    .font(.system(size: size * 0.32, weight: .bold, design: .rounded))
                    .foregroundColor(fg)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(tile.timezone.isEmpty ? text(ctx.date, "EEE d MMM", tz) : tile.title)
                    .font(.system(size: size * 0.15))
                    .foregroundColor(fg.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 3)
        }
    }
}


// MARK: Tegels tegen de schermrand

enum EdgeLayout {
    /// Afstand tot de onderrand (zelfde waarde als bij de dock).
    static func margin(_ t: DockTheme) -> CGFloat { max(CGFloat(t.bottomMargin), 0) }
    /// Afstand tot de zijkant van het scherm (instelbaar per kant).
    static func sideMargin(_ side: TileSide, _ t: DockTheme) -> CGFloat {
        TileStore.shared.edgeMargin(side, main: t)
    }

    static func panelSize(_ side: TileSide, _ t: DockTheme, barWidth w: CGFloat) -> CGSize {
        CGSize(width: w + sideMargin(side, t) + 40,
               height: DockLayout.barHeight(t) + margin(t) + CGFloat(t.shadowRadius) + 12)
    }

    /// De zichtbare balk in schermcoördinaten (AppKit, y omhoog).
    static func barRect(_ side: TileSide, theme t: DockTheme, barWidth w: CGFloat, screen: NSScreen) -> NSRect {
        let m = sideMargin(side, t)
        let x = side == .left ? screen.frame.minX + m : screen.frame.maxX - m - w
        return NSRect(x: x, y: screen.frame.minY + CGFloat(t.bottomMargin),
                      width: w, height: DockLayout.barHeight(t))
    }
}

struct EdgeTilesView: View {
    let side: TileSide
    @ObservedObject var store = ThemeStore.shared
    @ObservedObject var tileStore = TileStore.shared

    var body: some View {
        let t = store.theme
        let w = tileStore.sideWidth(side, main: t, edge: true)
        let size = EdgeLayout.panelSize(side, t, barWidth: w)
        TilesBar(side: side, edge: true, mainTheme: t, width: w)
            .padding(side == .left ? .leading : .trailing, EdgeLayout.sideMargin(side, t))
            .padding(.bottom, EdgeLayout.margin(t))
            .frame(width: size.width, height: size.height,
                   alignment: side == .left ? .bottomLeading : .bottomTrailing)
    }
}
