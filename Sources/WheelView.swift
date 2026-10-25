import AppKit

/// Roue radiale qui sert aussi de zone de dépôt.
/// Fond : matériau HUD flou découpé en anneau ; survol : dégradé orange ; centre : touche active + type du fichier.
final class WheelView: NSView {
    var items: [Item] = [] { didSet { hovered = nil; needsDisplay = true } }
    /// Nom du pictogramme de la touche active (« shift », « command », « control »).
    var keySymbol = "shift" { didSet { needsDisplay = true } }
    var subtitle = "" { didSet { needsDisplay = true } }
    var hovered: Int? { didSet { if oldValue != hovered { needsDisplay = true } } }
    var onDrop: ((Item) -> Void)?
    /// Vrai pour le rendu hors écran (le flou derrière la fenêtre n'existe pas dans un bitmap).
    var flatBackdrop = false { didSet { blur?.isHidden = flatBackdrop } }

    let inner: CGFloat = 56
    let outer: CGFloat = 158
    static let accent = Style.accent

    private var blur: NSVisualEffectView?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        let v = NSVisualEffectView(frame: bounds)
        v.material = .hudWindow; v.blendingMode = .behindWindow; v.state = .active
        v.appearance = NSAppearance(named: .vibrantDark)
        v.maskImage = ringMask()
        v.autoresizingMask = [.width, .height]
        addSubview(v)
        blur = v
        let f = Face(frame: bounds); f.owner = self; f.autoresizingMask = [.width, .height]
        addSubview(f); face = f
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { false }

    // MARK: géométrie
    private var center: NSPoint { NSPoint(x: bounds.midX, y: bounds.midY) }

    func index(at p: NSPoint) -> Int? {
        guard !items.isEmpty else { return nil }
        let dx = p.x - center.x, dy = p.y - center.y
        let r = hypot(dx, dy)
        guard r >= inner, r <= outer + 14 else { return nil }
        var a = Double.pi / 2 - atan2(Double(dy), Double(dx))   // sens horaire depuis le haut
        let full = 2 * Double.pi
        a = a.truncatingRemainder(dividingBy: full)
        if a < 0 { a += full }
        let seg = full / Double(items.count)
        return min(Int(a / seg), items.count - 1)
    }

    private func slice(_ i: Int, inset: CGFloat = 0) -> NSBezierPath {
        let n = Double(items.count)
        let gap = items.count > 1 ? 1.1 : 0.0
        let s = 90 - (Double(i) * 360 / n) - gap
        let e = 90 - (Double(i + 1) * 360 / n) + gap
        let path = NSBezierPath()
        path.appendArc(withCenter: center, radius: outer - inset, startAngle: CGFloat(s), endAngle: CGFloat(e), clockwise: true)
        path.appendArc(withCenter: center, radius: inner + inset, startAngle: CGFloat(e), endAngle: CGFloat(s), clockwise: false)
        path.close()
        path.lineJoinStyle = .round
        return path
    }

    private func ringPath() -> NSBezierPath {
        let ring = NSBezierPath(ovalIn: NSRect(x: center.x - outer, y: center.y - outer, width: outer * 2, height: outer * 2))
        ring.append(NSBezierPath(ovalIn: NSRect(x: center.x - inner, y: center.y - inner, width: inner * 2, height: inner * 2)))
        ring.windingRule = .evenOdd
        return ring
    }

    private func ringMask() -> NSImage {
        NSImage(size: bounds.size, flipped: false) { _ in
            NSColor.black.setFill(); self.ringPath().fill()
            return true
        }
    }

    // MARK: dessin
    // Une sous-vue se dessine après la vue parente : le flou (sous-vue) cacherait les tranches.
    // Le dessin vit donc dans `Face`, ajoutée au-dessus du flou.
    private final class Face: NSView {
        weak var owner: WheelView?
        override var isFlipped: Bool { false }
        override func hitTest(_ p: NSPoint) -> NSView? { nil }
        override func draw(_ r: NSRect) { owner?.drawFace() }
    }
    private var face: Face?
    override func draw(_ dirtyRect: NSRect) { NSGraphicsContext.current?.cgContext.clear(bounds) }
    override var needsDisplay: Bool { didSet { face?.needsDisplay = true } }

    func drawFace() {
        NSGraphicsContext.current?.cgContext.clear(bounds)
        let n = items.count

        if flatBackdrop {
            NSColor(srgbRed: 0.13, green: 0.13, blue: 0.15, alpha: 0.90).setFill(); ringPath().fill()
        }
        // voile sombre et filet de lumière : donne du corps au verre
        NSColor(white: 0, alpha: 0.22).setFill(); ringPath().fill()
        let edge = ringPath(); NSColor(white: 1, alpha: 0.16).setStroke(); edge.lineWidth = 1; edge.stroke()

        for i in items.indices {
            let on = hovered == i
            if on {
                let p = slice(i, inset: 5)
                NSGraphicsContext.saveGraphicsState()
                let sh = NSShadow(); sh.shadowColor = Style.accent.withAlphaComponent(0.55); sh.shadowBlurRadius = 14; sh.shadowOffset = .zero
                sh.set()
                NSGradient(colors: [Style.accentTop, Style.accent, NSColor(srgbRed: 1, green: 0.46, blue: 0.02, alpha: 1)])?
                    .draw(in: p, relativeCenterPosition: .zero)
                NSGraphicsContext.restoreGraphicsState()
                NSColor(white: 1, alpha: 0.35).setStroke(); p.lineWidth = 0.75; p.stroke()
            } else if n > 1 {
                // séparateur fin entre deux tranches
                let a = (90 - Double(i) * 360 / Double(n)) * .pi / 180
                let l = NSBezierPath()
                l.move(to: NSPoint(x: center.x + CGFloat(cos(a)) * (inner + 2), y: center.y + CGFloat(sin(a)) * (inner + 2)))
                l.line(to: NSPoint(x: center.x + CGFloat(cos(a)) * (outer - 2), y: center.y + CGFloat(sin(a)) * (outer - 2)))
                NSColor(white: 1, alpha: 0.10).setStroke(); l.lineWidth = 1; l.stroke()
            }

            // contenu : pictogramme (outils, actions) au-dessus du libellé
            let mid = (90 - (Double(i) + 0.5) * 360 / Double(n)) * .pi / 180
            let r = (inner + outer) / 2 + 2
            let c = NSPoint(x: center.x + CGFloat(cos(mid)) * r, y: center.y + CGFloat(sin(mid)) * r)
            let fg = on ? NSColor(white: 0.10, alpha: 1) : NSColor(white: 1, alpha: 0.94)
            let arc = 2 * CGFloat.pi * r / CGFloat(max(n, 1))
            let w = min(86, max(54, arc - 6))
            let fs: CGFloat = n > 8 ? 10.5 : (n > 6 ? 11.5 : 12.5)
            let para = NSMutableParagraphStyle(); para.alignment = .center; para.lineBreakMode = .byWordWrapping; para.lineSpacing = -1
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fs, weight: .semibold), .foregroundColor: fg, .paragraphStyle: para, .kern: -0.1,
            ]
            let str = items[i].title as NSString
            let th = str.boundingRect(with: NSSize(width: w, height: 60), options: .usesLineFragmentOrigin, attributes: attrs).height
            if let icon = Style.symbol(items[i].id, size: n > 8 ? 15 : 17, color: fg) {
                let gap: CGFloat = 4
                let total = icon.size.height + gap + th
                let top = c.y + total / 2
                icon.draw(in: NSRect(x: c.x - icon.size.width / 2, y: top - icon.size.height, width: icon.size.width, height: icon.size.height))
                str.draw(in: NSRect(x: c.x - w / 2, y: top - total, width: w, height: th), withAttributes: attrs)
            } else {
                str.draw(in: NSRect(x: c.x - w / 2, y: c.y - th / 2, width: w, height: th), withAttributes: attrs)
            }
        }

        // centre : touche active, type du fichier
        let d = (inner - 8) * 2
        let disc = NSBezierPath(ovalIn: NSRect(x: center.x - d / 2, y: center.y - d / 2, width: d, height: d))
        NSColor(white: 0.04, alpha: 0.80).setFill(); disc.fill()
        NSColor(white: 1, alpha: 0.12).setStroke(); disc.lineWidth = 1; disc.stroke()
        if let key = NSImage(systemSymbolName: keySymbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 19, weight: .semibold)) {
            let tinted = NSImage(size: key.size, flipped: false) { r in key.draw(in: r); WheelView.accent.set(); r.fill(using: .sourceAtop); return true }
            tinted.draw(in: NSRect(x: center.x - tinted.size.width / 2, y: center.y - 1, width: tinted.size.width, height: tinted.size.height))
        }
        let para = NSMutableParagraphStyle(); para.alignment = .center
        let t2: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 9.5, weight: .semibold), .foregroundColor: NSColor(white: 1, alpha: 0.62),
                                                  .paragraphStyle: para, .kern: 0.4]
        (subtitle as NSString).draw(in: NSRect(x: center.x - 36, y: center.y - 17, width: 72, height: 13), withAttributes: t2)
    }

    // MARK: dépôt
    private func update(_ s: NSDraggingInfo) {
        hovered = index(at: convert(s.draggingLocation, from: nil))
    }
    override func draggingEntered(_ s: NSDraggingInfo) -> NSDragOperation {
        update(s)
        return hovered == nil ? [] : .copy
    }
    override func draggingUpdated(_ s: NSDraggingInfo) -> NSDragOperation {
        update(s)
        return hovered == nil ? [] : .copy
    }
    override func draggingExited(_ s: NSDraggingInfo?) { hovered = nil }
    override func prepareForDragOperation(_ s: NSDraggingInfo) -> Bool { hovered != nil }
    override func performDragOperation(_ s: NSDraggingInfo) -> Bool {
        update(s)
        guard let i = hovered else { return false }
        onDrop?(items[i])
        return true
    }
}
