import AppKit
import UserNotifications

// MARK: mode ligne de commande (tests / scripts)
//   Mandarine --list convert|tools|actions <fichiers…>
//   Mandarine --run convert:png <fichiers…>
let args = CommandLine.arguments
if args.count >= 3, args[1] == "--list" {
    let urls = args.dropFirst(3).map { URL(fileURLWithPath: $0) }
    Engine.items(mode: args[2], urls: urls).forEach { print($0.id, "·", $0.title) }
    exit(0)
}
if args.count >= 4, args[1] == "--run" {
    let urls = args.dropFirst(3).map { URL(fileURLWithPath: $0) }
    do {
        try Engine.perform(args[2], urls: urls).forEach { print($0.path) }
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("ERREUR: \(error)\n".utf8))
        exit(1)
    }
}

if args.count >= 5, args[1] == "--render" {   // --render convert out.png <fichiers…> : dessine la roue hors écran + test des tranches
    _ = NSApplication.shared
    let urls = args.dropFirst(4).map { URL(fileURLWithPath: $0) }
    let w = WheelView(frame: NSRect(x: 0, y: 0, width: 340, height: 340))
    w.items = Engine.items(mode: args[2], urls: urls)
    w.title = "⇧"; w.subtitle = urls.first?.pathExtension.uppercased() ?? ""
    w.hovered = 1
    guard let rep = w.bitmapImageRepForCachingDisplay(in: w.bounds) else { exit(1) }
    w.cacheDisplay(in: w.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[3]))
    // hit-test : le centre de chaque tranche doit retrouver son index
    var bad = 0
    for i in w.items.indices {
        let a = (90 - (Double(i) + 0.5) * 360 / Double(w.items.count)) * .pi / 180
        let pt = NSPoint(x: 170 + cos(a) * 96, y: 170 + sin(a) * 96)
        if w.index(at: pt) != i { bad += 1; print("hit-test KO tranche", i, "->", w.index(at: pt) as Any) }
    }
    print("tranches:", w.items.count, "hit-test KO:", bad)
    exit(bad == 0 ? 0 : 1)
}

// MARK: panneaux
final class WheelPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let size: CGFloat = 340
    var panel: WheelPanel!
    var wheel: WheelView!
    var toast: NSPanel?
    var statusItem: NSStatusItem!

    var timer: Timer?
    var lastPBCount = NSPasteboard(name: .drag).changeCount
    var dragging = false
    var cancelled = false
    var dragURLs: [URL] = []
    var prevMods: NSEvent.ModifierFlags = []
    var mode: String?

    func applicationDidFinishLaunching(_ n: Notification) {
        panel = WheelPanel(contentRect: NSRect(x: 0, y: 0, width: size, height: size),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        wheel = WheelView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        wheel.onDrop = { [weak self] item in self?.handleDrop(item) }
        panel.contentView = wheel

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🍊"
        let menu = NSMenu()
        menu.addItem(withTitle: "Mandarine", action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(withTitle: "Glisse un fichier, puis tape :", action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(withTitle: "   ⇧ Maj  → convertir", action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(withTitle: "   ⌘ Cmd → outils", action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(withTitle: "   ⌃ Ctrl → actions", action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quitter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu

        timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)

        // mode démo pour captures d'écran : Mandarine --demo convert <fichier>
        if args.count >= 4, args[1] == "--demo" {
            dragURLs = args.dropFirst(3).map { URL(fileURLWithPath: $0) }
            showWheel(mode: args[2], at: NSPoint(x: NSScreen.main!.frame.midX, y: NSScreen.main!.frame.midY))
            wheel.hovered = 1
        }
    }

    // MARK: détection du glisser + modificateurs (aucune permission requise)
    func tick() {
        guard args.count < 2 || args[1] != "--demo" else { return }
        let pb = NSPasteboard(name: .drag)
        let down = NSEvent.pressedMouseButtons & 1 != 0

        if !down {
            if dragging {
                dragging = false
                // laisser le temps à performDragOperation de s'exécuter
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                    guard let self, !self.dragging else { return }
                    self.hideWheel()
                }
            }
            lastPBCount = pb.changeCount
            prevMods = []
            return
        }

        if !dragging, !cancelled, pb.changeCount != lastPBCount {
            let urls = (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
            lastPBCount = pb.changeCount
            if !urls.isEmpty { dragging = true; dragURLs = urls; prevMods = NSEvent.modifierFlags.intersection([.shift, .command, .control]) }
        }
        guard dragging else { return }

        let mods = NSEvent.modifierFlags.intersection([.shift, .command, .control])
        let pressed = mods.subtracting(prevMods)
        prevMods = mods

        if pressed.contains(.shift) { showWheel(mode: "convert", at: NSEvent.mouseLocation) }
        else if pressed.contains(.command) { showWheel(mode: "tools", at: NSEvent.mouseLocation) }
        else if pressed.contains(.control) { showWheel(mode: "actions", at: NSEvent.mouseLocation) }

        // Échap annule
        if panel.isVisible, CGEventSource.keyState(.combinedSessionState, key: 53) {
            hideWheel()
            dragging = false
            cancelled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.cancelled = false }
        }
    }

    func showWheel(mode m: String, at p: NSPoint) {
        let items = Engine.items(mode: m, urls: dragURLs)
        guard !items.isEmpty else {
            flash("Rien à proposer pour ce type de fichier", at: p, ok: false)
            return
        }
        mode = m
        wheel.items = items
        switch m {
        case "convert": wheel.title = "⇧"
        case "tools": wheel.title = "⌘"
        default: wheel.title = "⌃"
        }
        wheel.subtitle = dragURLs.count == 1 ? dragURLs[0].pathExtension.uppercased() : "\(dragURLs.count) fichiers"

        // garder la roue dans l'écran
        let screen = NSScreen.screens.first { $0.frame.contains(p) } ?? NSScreen.main!
        var o = NSPoint(x: p.x - size / 2, y: p.y - size / 2)
        o.x = min(max(o.x, screen.frame.minX), screen.frame.maxX - size)
        o.y = min(max(o.y, screen.frame.minY), screen.frame.maxY - size)
        panel.setFrameOrigin(o)
        panel.orderFrontRegardless()
    }

    func hideWheel() {
        panel.orderOut(nil)
        wheel.hovered = nil
        mode = nil
    }

    // MARK: exécution
    func handleDrop(_ item: Item) {
        let urls = dragURLs
        let at = NSEvent.mouseLocation
        hideWheel()
        if item.id.hasPrefix("act:") { runAction(item.id, urls: urls); return }
        flash("Conversion…", at: at, ok: true, sticky: true)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let out = try Engine.perform(item.id, urls: urls)
                DispatchQueue.main.async {
                    let name = out.count == 1 ? out[0].lastPathComponent : "\(out.count) fichiers"
                    self.flash("✓ \(name)", at: at, ok: true)
                    NSWorkspace.shared.activateFileViewerSelecting(out)
                }
            } catch {
                DispatchQueue.main.async { self.flash("✗ \(error)", at: at, ok: false) }
            }
        }
    }

    func runAction(_ id: String, urls: [URL]) {
        let at = NSEvent.mouseLocation
        switch id {
        case "act:copypath":
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(urls.map { $0.path }.joined(separator: "\n"), forType: .string)
            flash("✓ Chemin copié", at: at, ok: true)
        case "act:copy":
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects(urls as [NSURL])
            flash("✓ Copié", at: at, ok: true)
        case "act:airdrop":
            NSSharingService(named: .sendViaAirDrop)?.perform(withItems: urls)
        case "act:move":
            NSApp.activate(ignoringOtherApps: true)
            let op = NSOpenPanel()
            op.canChooseDirectories = true
            op.canChooseFiles = false
            op.canCreateDirectories = true
            op.prompt = "Déplacer ici"
            guard op.runModal() == .OK, let dest = op.url else { return }
            var failed = 0
            for u in urls {
                let target = Engine.uniqueURL(dir: dest, base: u.deletingPathExtension().lastPathComponent, ext: u.pathExtension)
                do { try FileManager.default.moveItem(at: u, to: target) } catch { failed += 1 }
            }
            flash(failed == 0 ? "✓ Déplacé" : "✗ \(failed) échec(s)", at: at, ok: failed == 0)
        case "act:terminal":
            var isDir: ObjCBool = false
            let first = urls[0]
            FileManager.default.fileExists(atPath: first.path, isDirectory: &isDir)
            let folder = isDir.boolValue ? first : first.deletingLastPathComponent()
            let iterm = FileManager.default.fileExists(atPath: "/Applications/iTerm.app")
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            p.arguments = ["-a", iterm ? "iTerm" : "Terminal", folder.path]
            try? p.run()
        default: break
        }
    }

    // MARK: toast
    func flash(_ text: String, at p: NSPoint, ok: Bool, sticky: Bool = false) {
        toast?.orderOut(nil)
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white
        label.lineBreakMode = .byTruncatingMiddle
        label.sizeToFit()
        let w = min(label.frame.width + 28, 460), h: CGFloat = 34
        let v = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        v.wantsLayer = true
        v.layer?.cornerRadius = h / 2
        v.layer?.backgroundColor = (ok ? NSColor(white: 0.1, alpha: 0.92) : NSColor(srgbRed: 0.7, green: 0.1, blue: 0.1, alpha: 0.95)).cgColor
        label.frame = NSRect(x: 14, y: (h - label.frame.height) / 2, width: w - 28, height: label.frame.height)
        v.addSubview(label)
        let t = WheelPanel(contentRect: v.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        t.isOpaque = false
        t.backgroundColor = .clear
        t.level = .statusBar
        t.ignoresMouseEvents = true
        t.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        t.contentView = v
        t.setFrameOrigin(NSPoint(x: p.x - w / 2, y: p.y + 20))
        t.orderFrontRegardless()
        toast = t
        if !sticky {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { [weak self, weak t] in
                if self?.toast === t { t?.orderOut(nil) }
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
