import AppKit
import Carbon.HIToolbox

// Captures d'écran vers le presse-papiers (aucun fichier créé), via /usr/sbin/screencapture.
// Raccourcis globaux (Carbon, aucune permission d'accessibilité requise) : ⌃⇧4 zone, ⌃⇧3 écran entier.
enum Capture {
    static func pasteboardHasImage() -> Bool {
        NSPasteboard.general.canReadItem(withDataConformingToTypes: [NSPasteboard.PasteboardType.png.rawValue, NSPasteboard.PasteboardType.tiff.rawValue])
    }

    /// Lance la capture. `region` = l'utilisateur sélectionne une zone (Échap annule). Retourne true si une image est arrivée dans le presse-papiers.
    static func run(region: Bool) -> Bool {
        let pb = NSPasteboard.general
        let before = pb.changeCount
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = region ? ["-i", "-c", "-x"] : ["-c", "-x"]   // -c presse-papiers, -x sans son d'obturateur
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0 && pb.changeCount != before && pasteboardHasImage()
    }
}

final class HotKeys {
    static var handlers: [UInt32: () -> Void] = [:]
    private static var installed = false
    private static var refs: [EventHotKeyRef?] = []

    /// Enregistre un raccourci global. Retourne false si le système refuse (déjà pris).
    @discardableResult
    static func register(id: UInt32, keyCode: Int, modifiers: Int, _ action: @escaping () -> Void) -> Bool {
        if !installed {
            installed = true
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, ev, _ in
                var hk = EventHotKeyID()
                GetEventParameter(ev, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &hk)
                if let h = HotKeys.handlers[hk.id] { DispatchQueue.main.async { h() } }
                return noErr
            }, 1, &spec, nil, nil)
        }
        var ref: EventHotKeyRef?
        let hkid = EventHotKeyID(signature: OSType(0x4D414E44), id: id)   // 'MAND'
        let st = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hkid, GetApplicationEventTarget(), 0, &ref)
        guard st == noErr else { return false }
        refs.append(ref); handlers[id] = action
        return true
    }
}
