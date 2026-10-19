import AppKit

/// Roue radiale qui sert aussi de zone de dépôt.
final class WheelView: NSView {
    var items: [Item] = [] { didSet { hovered = nil; needsDisplay = true } }
    var title = "" { didSet { needsDisplay = true } }
    var subtitle = "" { didSet { needsDisplay = true } }
    var hovered: Int? { didSet { if oldValue != hovered { needsDisplay = true } } }
    var onDrop: ((Item) -> Void)?

    let inner: CGFloat = 50
    let outer: CGFloat = 142
    static let accent = NSColor(srgbRed: 1.0, green: 0.55, blue: 0.1, alpha: 1)

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { false }

    // MARK: géométrie
    private var center: NSPoint { NSPoint(x: bounds.midX, y: bounds.midY) }

    func index(at p: NSPoint) -> Int? {
        guard !items.isEmpty else { return nil }
        let dx = p.x - center.x, dy = p.y - center.y
        let r = hypot(dx, dy)
        guard r >= inner, r <= outer + 24 else { return nil }
        var a = Double.pi / 2 - atan2(Double(dy), Double(dx))   // sens horaire depuis le haut
        let full = 2 * Double.pi
        a = a.truncatingRemainder(dividingBy: full)
        if a < 0 { a += full }
        let seg = full / Double(items.count)
        return min(Int(a / seg), items.count - 1)
    }

    private func slice(_ i: Int) -> NSBezierPath {
        let n = Double(items.count)
        let gap = items.count > 1 ? 1.6 : 0.0
        let s = 90 - (Double(i) * 360 / n) - gap
        let e = 90 - (Double(i + 1) * 360 / n) + gap
        let path = NSBezierPath()
        path.appendArc(withCenter: center, radius: outer, startAngle: CGFloat(s), endAngle: CGFloat(e), clockwise: true)
        path.appendArc(withCenter: center, radius: inner, startAngle: CGFloat(e), endAngle: CGFloat(s), clockwise: false)
        path.close()
        return path
    }

    // MARK: dessin
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.cgContext.clear(bounds)

        // halo
        let halo = NSBezierPath(ovalIn: NSRect(x: center.x - outer - 10, y: center.y - outer - 10, width: (outer + 10) * 2, height: (outer + 10) * 2))
        NSColor(white: 0, alpha: 0.28).setFill()
        halo.fill()

        for i in items.indices {
            let p = slice(i)
            (hovered == i ? WheelView.accent : NSColor(white: 0.10, alpha: 0.90)).setFill()
            p.fill()
            NSColor(white: 1, alpha: hovered == i ? 0.0 : 0.10).setStroke()
            p.lineWidth = 1
            p.stroke()

            // libellé au milieu de la tranche
            let n = Double(items.count)
            let mid = (90 - (Double(i) + 0.5) * 360 / n) * .pi / 180
            let r = (inner + outer) / 2
            let c = NSPoint(x: center.x + CGFloat(cos(mid)) * r, y: center.y + CGFloat(sin(mid)) * r)
            let para = NSMutableParagraphStyle()
            para.alignment = .center
            para.lineBreakMode = .byWordWrapping
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: items.count > 6 ? 12 : 13, weight: .semibold),
                .foregroundColor: hovered == i ? NSColor.black : NSColor.white,
                .paragraphStyle: para
            ]
            let w: CGFloat = 84
            let str = items[i].title as NSString
            let h = str.boundingRect(with: NSSize(width: w, height: 60), options: .usesLineFragmentOrigin, attributes: attrs).height
            str.draw(in: NSRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h), withAttributes: attrs)
        }

        // centre
        let disc = NSBezierPath(ovalIn: NSRect(x: center.x - inner + 6, y: center.y - inner + 6, width: (inner - 6) * 2, height: (inner - 6) * 2))
        NSColor(white: 0.06, alpha: 0.95).setFill()
        disc.fill()
        WheelView.accent.setStroke()
        disc.lineWidth = 2
        disc.stroke()

        let para = NSMutableParagraphStyle()
        para.alignment = .center
        let t1: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 20, weight: .bold), .foregroundColor: WheelView.accent, .paragraphStyle: para]
        let t2: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 9, weight: .regular), .foregroundColor: NSColor(white: 0.8, alpha: 1), .paragraphStyle: para]
        (title as NSString).draw(in: NSRect(x: center.x - 38, y: center.y - 2, width: 76, height: 26), withAttributes: t1)
        (subtitle as NSString).draw(in: NSRect(x: center.x - 38, y: center.y - 15, width: 76, height: 13), withAttributes: t2)
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
