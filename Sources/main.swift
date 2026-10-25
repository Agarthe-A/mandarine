import AppKit
import Carbon.HIToolbox
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

if args.count >= 5, args[1] == "--render" {   // --render convert|tools|actions out.png <fichiers…> : dessine la roue hors écran + test des tranches
    // HOVER=<n> choisit la tranche survolée (-1 = aucune), SCALE=<n> la définition (1 par défaut)
    _ = NSApplication.shared
    let urls = args.dropFirst(4).map { URL(fileURLWithPath: $0) }
    let w = WheelView(frame: NSRect(x: 0, y: 0, width: 372, height: 372))
    w.flatBackdrop = true
    w.items = Engine.items(mode: args[2], urls: urls)
    w.keySymbol = args[2] == "convert" ? "shift" : (args[2] == "tools" ? "command" : "control")
    w.subtitle = urls.count > 1 ? "\(urls.count) fichiers" : (urls.first?.pathExtension.uppercased() ?? "")
    let env = ProcessInfo.processInfo.environment
    let hv = Int(env["HOVER"] ?? "") ?? 1
    w.hovered = hv >= 0 && hv < w.items.count ? hv : nil
    let scale = max(1, Int(env["SCALE"] ?? "") ?? 1)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 372 * scale, pixelsHigh: 372 * scale, bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
    rep.size = w.bounds.size
    w.cacheDisplay(in: w.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[3]))
    // hit-test : le centre de chaque tranche doit retrouver son index
    var bad = 0
    for i in w.items.indices {
        let a = (90 - (Double(i) + 0.5) * 360 / Double(w.items.count)) * .pi / 180
        let pt = NSPoint(x: 186 + cos(a) * 107, y: 186 + sin(a) * 107)
        if w.index(at: pt) != i { bad += 1; print("hit-test KO tranche", i, "->", w.index(at: pt) as Any) }
    }
    print("tranches:", w.items.count, "hit-test KO:", bad)
    exit(bad == 0 ? 0 : 1)
}

//   Mandarine --catalog : catalogue réel (conversions, outils, actions) en JSON, source des chiffres et de la liste du site
//   Mandarine --symbols dossier : exporte en PNG blanc les pictogrammes utilisés par la roue
if args.count >= 2, args[1] == "--catalog" {
    let groups: [(String, Kind, [String])] = [
        ("image", .image, Array(Engine.imageExts)), ("video", .video, Array(Engine.videoExts)), ("audio", .audio, Array(Engine.audioExts)),
        ("pdf", .pdf, ["pdf"]), ("doc", .doc, Array(Engine.docExts)), ("archive", .archive, Array(Engine.archiveExts)),
        ("subtitle", .subtitle, Array(Engine.subtitleExts)), ("table", .table, Array(Engine.tableExts)),
    ]
    var convert: [String: Any] = [:]; var pairs = 0
    for (name, kind, exts) in groups {
        guard let c = Converters.converter(for: kind) else { continue }
        var union = Set<String>(); var n = 0
        for e in exts.sorted() { let t = c.targets(for: URL(fileURLWithPath: "/tmp/x.\(e)")); union.formUnion(t); n += t.count }
        pairs += n
        convert[name] = ["targets": union.sorted(), "inputs": exts.sorted(), "pairs": n] as [String: Any]
    }
    if let f = Converters.converter(for: .folder) { let t = f.targets(for: URL(fileURLWithPath: "/tmp")); pairs += t.count; convert["folder"] = ["targets": t, "inputs": ["dossier"], "pairs": t.count] }
    let kindName: (Kind) -> String = { "\($0)" }
    let tools = Tools.all.map { ["id": $0.id, "title": $0.title, "kinds": $0.kinds.map(kindName).sorted(), "minCount": $0.minCount, "symbol": Style.symbols["tool:" + $0.id] ?? ""] as [String: Any] }
    let actions = Engine.items(mode: "actions", urls: [URL(fileURLWithPath: "/tmp/x.png")]).map { ["id": $0.id, "title": $0.title, "symbol": Style.symbols[$0.id] ?? ""] }
    // exemples de fichiers : ce que propose réellement la roue pour chacun (le site les rejoue tels quels)
    var samples: [String: Any] = [:]
    for e in ["png", "mp4", "wav", "pdf", "md", "csv", "srt"] {
        let u = [URL(fileURLWithPath: "/tmp/x.\(e)")]
        samples[e] = ["convert": Engine.items(mode: "convert", urls: u).map { $0.title },
                      "tools": Engine.items(mode: "tools", urls: u).map { $0.id.replacingOccurrences(of: "tool:", with: "") }]
    }
    let out: [String: Any] = ["version": Updater.current, "conversionPairs": pairs, "convert": convert, "tools": tools, "actions": actions, "samples": samples]
    let data = try! JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: data, as: UTF8.self)); exit(0)
}
if args.count >= 3, args[1] == "--symbols" {
    _ = NSApplication.shared
    let dir = URL(fileURLWithPath: args[2]); try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    var n = 0
    for (id, _) in Style.symbols {
        guard let img = Style.symbol(id, size: 64, color: .white) else { continue }
        let px = Int(img.size.width.rounded(.up)), py = Int(img.size.height.rounded(.up))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: py, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { continue }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        img.draw(in: NSRect(x: 0, y: 0, width: px, height: py)); NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(id.replacingOccurrences(of: ":", with: "-") + ".png")); n += 1
    }
    print("symboles exportés:", n); exit(0)
}

//   Mandarine --icon out.png [taille] [tile] : dessine l'icône (tile = carré d'app)
if args.count >= 3, args[1] == "--icon" {
    _ = NSApplication.shared
    let px = args.count >= 4 ? Int(args[3]) ?? 1024 : 1024
    let img = Style.iconImage(size: CGFloat(px), tile: args.contains("tile"))
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[2]))
    exit(0)
}

// MARK: panneaux
final class WheelPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

//   Mandarine --check-update [url-api]            : affiche « à jour » ou « nouvelle version X »
//   Mandarine --self-update <url-api> <chemin.app> : installe la version annoncée à la place de <chemin.app> (test)
if args.count >= 2, args[1] == "--check-update" {
    do {
        let r = try Updater.latest(api: args.count >= 3 ? args[2] : Updater.defaultAPI)
        print(Updater.isNewer(r.version, than: Updater.current) ? "nouvelle version \(r.version)" : "à jour (\(Updater.current))")
        exit(0)
    } catch { FileHandle.standardError.write(Data("ERREUR: \(error)\n".utf8)); exit(1) }
}
if args.count >= 4, args[1] == "--self-update" {
    do {
        let r = try Updater.latest(api: args[2])
        try Updater.install(r, target: URL(fileURLWithPath: args[3]), strict: false)
        print("installée \(r.version)")
        exit(0)
    } catch { FileHandle.standardError.write(Data("ERREUR: \(error)\n".utf8)); exit(1) }
}

//   Mandarine --capture screen   : capture l'écran entier vers le presse-papiers (test), affiche « ok » si une image y est arrivée
if args.count >= 3, args[1] == "--capture", args[2] == "screen" {
    let ok = Capture.run(region: false)
    print(ok ? "ok" : "échec"); exit(ok ? 0 : 1)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let size: CGFloat = 372
    var panel: WheelPanel!
    var wheel: WheelView!
    var toast: NSPanel?
    var statusItem: NSStatusItem!
    var updateItem: NSMenuItem!
    var autoItem: NSMenuItem!
    var updating = false
    var capturing = false

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
        statusItem.button?.image = Style.menuBarImage()
        let menu = NSMenu()
        let capZone = NSMenuItem(title: "Capturer une zone", action: #selector(captureZone), keyEquivalent: "4")
        capZone.keyEquivalentModifierMask = [.control, .shift]; capZone.target = self; menu.addItem(capZone)
        let capScreen = NSMenuItem(title: "Capturer l'écran", action: #selector(captureScreen), keyEquivalent: "3")
        capScreen.keyEquivalentModifierMask = [.control, .shift]; capScreen.target = self; menu.addItem(capScreen)
        let okZone = HotKeys.register(id: 1, keyCode: kVK_ANSI_4, modifiers: controlKey | shiftKey) { [weak self] in self?.captureZone() }
        let okScreen = HotKeys.register(id: 2, keyCode: kVK_ANSI_3, modifiers: controlKey | shiftKey) { [weak self] in self?.captureScreen() }
        if !okZone { capZone.title = "Capturer une zone ⚠️" }
        if !okScreen { capScreen.title = "Capturer l'écran ⚠️" }
        menu.addItem(.separator())
        menu.addItem(withTitle: "\(Updater.current)", action: nil, keyEquivalent: "").isEnabled = false
        updateItem = NSMenuItem(title: "Mises à jour…", action: #selector(checkUpdatesManually), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)
        autoItem = NSMenuItem(title: "Automatique", action: #selector(toggleAutoCheck), keyEquivalent: "")
        autoItem.target = self; autoItem.state = Updater.autoCheck ? .on : .off
        menu.addItem(autoItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quitter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        // vérification discrète au lancement (après 8 s) puis toutes les 24 h
        if Updater.autoCheck {
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.checkUpdates(manual: false) }
            Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { [weak self] _ in
                if Updater.autoCheck { self?.checkUpdates(manual: false) }
            }
        }

        timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)

        // mode démo pour captures d'écran : Mandarine --demo convert <fichier>
        if args.count >= 4, args[1] == "--demo" {
            dragURLs = args.dropFirst(3).map { URL(fileURLWithPath: $0) }
            showWheel(mode: args[2], at: NSPoint(x: NSScreen.main!.frame.midX, y: NSScreen.main!.frame.midY))
            wheel.hovered = 1
        }
    }

    // MARK: captures
    @objc func captureZone() { capture(region: true) }
    @objc func captureScreen() { capture(region: false) }
    func capture(region: Bool) {
        if capturing { return }
        capturing = true
        DispatchQueue.global().async {
            // petite pause pour laisser le menu se fermer avant de photographier l'écran
            if !region { Thread.sleep(forTimeInterval: 0.3) }
            let ok = Capture.run(region: region)
            DispatchQueue.main.async {
                self.capturing = false
                if ok { self.flash("📋 Capture copiée", at: NSEvent.mouseLocation, ok: true, sticky: false) }
            }
        }
    }

    // MARK: mises à jour
    @objc func toggleAutoCheck() {
        Updater.autoCheck.toggle(); autoItem.state = Updater.autoCheck ? .on : .off
    }
    @objc func checkUpdatesManually() { checkUpdates(manual: true) }

    func alert(_ title: String, _ text: String, buttons: [String] = ["OK"]) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert(); a.messageText = title; a.informativeText = text
        buttons.forEach { a.addButton(withTitle: $0) }
        return a.runModal() == .alertFirstButtonReturn
    }

    func checkUpdates(manual: Bool) {
        if updating { return }
        updating = true; updateItem.title = "Recherche en cours…"
        DispatchQueue.global().async {
            let res = Result { try Updater.latest() }
            DispatchQueue.main.async {
                self.updating = false; self.updateItem.title = "Mises à jour…"
                switch res {
                case .failure(let e):
                    if manual { _ = self.alert("Impossible de vérifier", "\(e)\n\nVérifie ta connexion internet.") }
                case .success(let r):
                    if !Updater.isNewer(r.version, than: Updater.current) {
                        if manual { _ = self.alert("Mandarine est à jour", "Tu as la version \(Updater.current), la plus récente.") }
                        return
                    }
                    let skipped = UserDefaults.standard.string(forKey: "skippedVersion")
                    if !manual && skipped == r.version { return }
                    let notes = Updater.shortNotes(r.notes)
                    let go = self.alert("Mandarine \(r.version) est disponible",
                                        "Tu as la version \(Updater.current).\n\n\(notes)",
                                        buttons: ["Mettre à jour maintenant", "Plus tard"])
                    if go { self.installUpdate(r) }
                    else { UserDefaults.standard.set(r.version, forKey: "skippedVersion") }
                }
            }
        }
    }

    func installUpdate(_ r: ReleaseInfo) {
        updating = true; updateItem.title = "Mise à jour en cours…"
        flash("Téléchargement de Mandarine \(r.version)…", at: NSEvent.mouseLocation, ok: true, sticky: false)
        let target = Bundle.main.bundleURL
        DispatchQueue.global().async {
            let res = Result { try Updater.install(r, target: target, strict: true) }
            DispatchQueue.main.async {
                self.updating = false; self.updateItem.title = "Mises à jour…"
                switch res {
                case .success:
                    UserDefaults.standard.removeObject(forKey: "skippedVersion")
                    Updater.relaunch(target)
                    NSApp.terminate(nil)
                case .failure(let e):
                    let open = self.alert("La mise à jour a échoué", "\(e)\n\nTon ancienne version est intacte.",
                                          buttons: ["Ouvrir la page de téléchargement", "Fermer"])
                    if open { NSWorkspace.shared.open(Updater.releasesPage) }
                }
            }
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
        case "convert": wheel.keySymbol = "shift"
        case "tools": wheel.keySymbol = "command"
        default: wheel.keySymbol = "control"
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
        case "act:float":
            Shelf.show(urls, near: at)
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
