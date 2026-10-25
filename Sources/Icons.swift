import AppKit

/// Identité visuelle partagée par la roue, le menu et les notifications.
enum Style {
    /// Orange système d'Apple (mode sombre) : le seul accent de l'interface.
    static let accent = NSColor(srgbRed: 1.0, green: 0.62, blue: 0.04, alpha: 1)
    static let accentTop = NSColor(srgbRed: 1.0, green: 0.72, blue: 0.22, alpha: 1)

    /// Pictogramme SF Symbols de chaque outil et action (les conversions n'ont que du texte).
    static let symbols: [String: String] = [
        "tool:imagesToPDF": "doc.richtext", "tool:mergePDF": "square.on.square", "tool:compress": "arrow.down.right.and.arrow.up.left",
        "tool:resize50": "arrow.down.right.and.arrow.up.left.circle", "tool:mute": "speaker.slash", "tool:strip": "eye.slash",
        "tool:rotate90": "rotate.right", "tool:gray": "circle.lefthalf.filled", "tool:video720": "tv", "tool:speed2": "forward",
        "tool:normalize": "waveform", "tool:trimSilence": "scissors", "tool:firstPage": "doc", "tool:compressPDF": "arrow.down.doc",
        "tool:cropSquare": "crop", "tool:background": "photo.on.rectangle", "tool:collage": "square.grid.2x2", "tool:redact": "face.dashed", "tool:slow": "tortoise",
        "tool:joinVideos": "rectangle.stack", "tool:videoFrame": "camera.viewfinder", "tool:splitVideo": "rectangle.split.2x1",
        "tool:mono": "speaker.wave.1", "tool:visualizer": "waveform.circle", "tool:splitPDF": "rectangle.split.3x1", "tool:rotatePDF": "rotate.right",
        "act:float": "rectangle.on.rectangle", "act:copypath": "link", "act:copy": "doc.on.doc", "act:airdrop": "dot.radiowaves.left.and.right", "act:move": "folder",
        "act:terminal": "terminal",
    ]

    static func symbol(_ id: String, size: CGFloat, color: NSColor) -> NSImage? {
        guard let name = symbols[id],
              let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: .medium)) else { return nil }
        let out = NSImage(size: base.size, flipped: false) { r in
            base.draw(in: r)
            color.set(); r.fill(using: .sourceAtop)
            return true
        }
        return out
    }

    /// Mandarine : sphère orange à reflet, feuille verte. `tile` = icône d'app (carré arrondi sombre).
    static func iconImage(size: CGFloat, tile: Bool) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
            let u = r.width / 100
            func P(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: r.minX + x * u, y: r.minY + y * u) }
            if tile {
                let t = NSBezierPath(roundedRect: r.insetBy(dx: 4 * u, dy: 4 * u), xRadius: 22 * u, yRadius: 22 * u)
                NSGradient(colors: [NSColor(white: 0.20, alpha: 1), NSColor(white: 0.04, alpha: 1)])?.draw(in: t, angle: -90)
                NSColor(white: 1, alpha: 0.14).setStroke(); t.lineWidth = 0.8 * u; t.stroke()
            }
            let k: CGFloat = tile ? 0.62 : 0.92
            let d = 100 * k, ox = (100 - d) / 2, oy = (100 - d) / 2 - (tile ? 3 : 4)
            let body = NSBezierPath(ovalIn: NSRect(x: r.minX + ox * u, y: r.minY + oy * u, width: d * u, height: d * 0.94 * u))
            NSGraphicsContext.saveGraphicsState()
            let sh = NSShadow(); sh.shadowColor = NSColor(srgbRed: 1, green: 0.35, blue: 0, alpha: tile ? 0.55 : 0); sh.shadowBlurRadius = 9 * u; sh.shadowOffset = .zero; sh.set()
            NSGradient(colors: [NSColor(srgbRed: 1, green: 0.83, blue: 0.40, alpha: 1), NSColor(srgbRed: 1, green: 0.58, blue: 0.04, alpha: 1),
                                NSColor(srgbRed: 0.90, green: 0.30, blue: 0.0, alpha: 1)], atLocations: [0, 0.5, 1], colorSpace: .sRGB)?
                .draw(in: body, relativeCenterPosition: NSPoint(x: -0.35, y: 0.45))
            NSGraphicsContext.restoreGraphicsState()
            let cx = r.minX + 50 * u, top = r.minY + (oy + d * 0.94) * u
            for dir: CGFloat in [-1, 1] {
                let leaf = NSBezierPath()
                leaf.move(to: NSPoint(x: cx, y: top - 1.5 * u))
                leaf.curve(to: NSPoint(x: cx + dir * 17 * u, y: top + 7 * u), controlPoint1: NSPoint(x: cx + dir * 3 * u, y: top + 9 * u), controlPoint2: NSPoint(x: cx + dir * 11 * u, y: top + 11 * u))
                leaf.curve(to: NSPoint(x: cx, y: top - 1.5 * u), controlPoint1: NSPoint(x: cx + dir * 15 * u, y: top + 1 * u), controlPoint2: NSPoint(x: cx + dir * 7 * u, y: top - 3 * u))
                NSGradient(colors: [NSColor(srgbRed: 0.55, green: 0.88, blue: 0.40, alpha: 1), NSColor(srgbRed: 0.18, green: 0.62, blue: 0.28, alpha: 1)])?.draw(in: leaf, angle: dir > 0 ? -30 : 210)
            }
            return true
        }
    }

    /// Mandarine de la barre des menus.
    static func menuBarImage() -> NSImage { iconImage(size: 18, tile: false) }
}
