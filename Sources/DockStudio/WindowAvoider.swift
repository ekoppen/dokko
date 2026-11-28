import AppKit
import ApplicationServices

enum WindowMode: String, Codable, CaseIterable, Identifiable {
    case none, reserve, smartHide

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "Geen (vensters mogen eroverheen)"
        case .reserve: return "Ruimte vrijhouden"
        case .smartHide: return "Slim verbergen"
        }
    }
}

/// Houdt vensters van andere apps in de gaten via de Toegankelijkheids-API.
/// - reserve: vensters worden kleiner/omhoog geschoven zodat ze niet onder de dock vallen.
/// - smartHide: meldt of een venster over de dock heen ligt.
final class WindowAvoider {
    static let shared = WindowAvoider()

    private var timer: Timer?
    private let queue = DispatchQueue(label: "dockstudio.windowavoider", qos: .utility)
    private var busy = false
    private static var didPrompt = false

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func start() {
        guard timer == nil else { return }
        // Bij een Space-wissel (bv. naar een app op volledig scherm) meteen controleren.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.tick() }
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    // MARK: Tick (hoofdthread)

    private func tick() {
        let store = ThemeStore.shared
        let controller = DockWindowController.shared
        let mode = store.windowMode

        guard store.dockEnabled else {
            controller.setWantsHidden(false)
            controller.setFullScreenHidden(false)
            return
        }
        // Volledig-scherm-detectie zonder Toegankelijkheid: een venster dat het hele scherm bedekt.
        let coverFull = NSScreen.screens.first.map { Self.fullScreenWindowCovers($0) } ?? false
        if !AXIsProcessTrusted() {
            controller.setFullScreenHidden(coverFull)
            if !Self.didPrompt {
                Self.didPrompt = true
                Self.requestTrust()
            }
            return
        }
        // Niet ingrijpen terwijl de gebruiker een venster sleept of vergroot.
        guard !busy, NSEvent.pressedMouseButtons & 1 == 0,
              let screen = NSScreen.screens.first else {
            controller.setFullScreenHidden(coverFull)
            return
        }

        let t = store.theme
        let count = DockModel.shared.items.count
        let barH = DockLayout.barHeight(t)
        let barW = DockLayout.barWidth(t, count: count)
        let H = screen.frame.height
        let W = screen.frame.width

        let dockTopAppKit = screen.frame.minY + CGFloat(t.bottomMargin) + barH
        let limitY = H - (dockTopAppKit + 6)                 // AX-coördinaten (y omlaag)
        let menuTop = H - screen.visibleFrame.maxY
        // Tegel-docks naast de hoofd-dock horen erbij.
        let sideL = TileStore.shared.sideWidth(.left, main: t)
        let sideR = TileStore.shared.sideWidth(.right, main: t)
        let extL = sideL > 0 ? sideL + TileStore.shared.gap(.left) : 0
        let extR = sideR > 0 ? sideR + TileStore.shared.gap(.right) : 0
        let barRect = CGRect(x: screen.frame.midX - barW / 2 + CGFloat(t.offsetX) - extL,
                             y: H - dockTopAppKit,
                             width: barW + extL + extR, height: barH)
        let screenRect = CGRect(x: 0, y: 0, width: W, height: H)

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let pids = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != ownPID }
            .map { $0.processIdentifier }

        busy = true
        queue.async { [weak self] in
            guard let self else { return }
            var overlap = false
            if mode != .none {
                for pid in pids {
                    if self.process(pid: pid, mode: mode, limitY: limitY, menuTop: menuTop,
                                    barRect: barRect, screenRect: screenRect) {
                        overlap = true
                    }
                }
            }
            var fullscreen = false
            if let frontPID, frontPID != ownPID {
                fullscreen = self.focusedWindowIsFullScreen(pid: frontPID)
            }
            DispatchQueue.main.async {
                self.busy = false
                controller.setWantsHidden(mode == .smartHide && overlap)
                controller.setFullScreenHidden(fullscreen || coverFull)
            }
        }
    }

    // MARK: Per app (achtergrondthread)

    /// Geeft true terug als een venster van deze app over de dock heen ligt.
    private func process(pid: pid_t, mode: WindowMode, limitY: CGFloat, menuTop: CGFloat,
                         barRect: CGRect, screenRect: CGRect) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        guard let winsRef = copy(app, kAXWindowsAttribute),
              let windows = winsRef as? [AXUIElement] else { return false }

        var overlapping = false

        for w in windows {
            AXUIElementSetMessagingTimeout(w, 0.15)
            guard (copy(w, kAXSubroleAttribute) as? String) == (kAXStandardWindowSubrole as String),
                  !(bool(w, kAXMinimizedAttribute)),
                  !(bool(w, "AXFullScreen")),
                  let pos = cgPoint(copy(w, kAXPositionAttribute)),
                  let size = cgSize(copy(w, kAXSizeAttribute)) else { continue }

            let frame = CGRect(origin: pos, size: size)
            guard screenRect.contains(CGPoint(x: frame.midX, y: frame.midY)) else { continue }

            if frame.intersects(barRect) { overlapping = true }

            guard mode == .reserve, frame.maxY > limitY + 1 else { continue }

            let avail = limitY - menuTop
            var settable: DarwinBoolean = false
            AXUIElementIsAttributeSettable(w, kAXSizeAttribute as CFString, &settable)

            if size.height > avail, settable.boolValue {
                var newSize = CGSize(width: size.width, height: avail)
                if let v = AXValueCreate(.cgSize, &newSize) {
                    AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, v)
                }
                var newPos = CGPoint(x: pos.x, y: menuTop)
                if let v = AXValueCreate(.cgPoint, &newPos) {
                    AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, v)
                }
            } else {
                var newPos = CGPoint(x: pos.x, y: max(menuTop, limitY - size.height))
                if let v = AXValueCreate(.cgPoint, &newPos) {
                    AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, v)
                }
            }
        }
        return overlapping
    }

    /// True als een zichtbaar venster van een andere app het hele scherm bedekt (inclusief menubalk):
    /// apps op volledig scherm, games en videospelers. Werkt zonder Toegankelijkheid.
    private static func fullScreenWindowCovers(_ screen: NSScreen) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return false }
        let own = ProcessInfo.processInfo.processIdentifier
        let W = screen.frame.width, H = screen.frame.height
        for w in list {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  (w[kCGWindowOwnerPID as String] as? Int32) != own,
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0.5,
                  let dict = w[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: dict) else { continue }
            if r.minX <= 1, r.minY <= 1, r.width >= W - 1, r.height >= H - 40 { return true }
        }
        return false
    }

    /// Is het actieve venster van deze app in volledig scherm?
    private func focusedWindowIsFullScreen(pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        guard let f = copy(app, kAXFocusedWindowAttribute),
              CFGetTypeID(f) == AXUIElementGetTypeID() else { return false }
        return bool(f as! AXUIElement, "AXFullScreen")
    }

    // MARK: AX-hulpjes

    private func copy(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var r: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, name as CFString, &r) == .success ? r : nil
    }

    private func bool(_ el: AXUIElement, _ name: String) -> Bool {
        (copy(el, name) as? Bool) ?? false
    }

    private func cgPoint(_ v: CFTypeRef?) -> CGPoint? {
        guard let v, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        return AXValueGetValue(v as! AXValue, .cgPoint, &p) ? p : nil
    }

    private func cgSize(_ v: CFTypeRef?) -> CGSize? {
        guard let v, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var s = CGSize.zero
        return AXValueGetValue(v as! AXValue, .cgSize, &s) ? s : nil
    }
}
