import AppKit

/// Étagère flottante (action « Flotter ») : garde des fichiers à portée, on les glisse ensuite dans une autre app.
final class Shelf: NSObject {
    static var panels: [NSPanel] = []

    static func show(_ urls: [URL], near p: NSPoint) {
        let size: CGFloat = 76, pad: CGFloat = 14
        let shown = Array(urls.prefix(6))
        let w = CGFloat(shown.count) * size + pad * 2, h = size + 56
        let root = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        root.material = .hudWindow; root.blendingMode = .behindWindow; root.state = .active
        root.appearance = NSAppearance(named: .vibrantDark)
        root.wantsLayer = true; root.layer?.cornerRadius = 20; root.layer?.masksToBounds = true

        for (i, u) in shown.enumerated() {
            let v = ShelfItem(url: u, frame: NSRect(x: pad + CGFloat(i) * size, y: 36, width: size, height: size))
            root.addSubview(v)
        }
        let close = NSButton(frame: NSRect(x: w - 30, y: h - 30, width: 20, height: 20))
        close.bezelStyle = .circular; close.isBordered = false
        close.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .regular))
        close.contentTintColor = NSColor(white: 1, alpha: 0.55)
        root.addSubview(close)
        let count = NSTextField(labelWithString: urls.count > shown.count ? "+\(urls.count - shown.count)" : "")
        count.font = .systemFont(ofSize: 11, weight: .semibold); count.textColor = NSColor(white: 1, alpha: 0.6)
        count.frame = NSRect(x: pad, y: h - 28, width: 60, height: 16)
        root.addSubview(count)

        let panel = NSPanel(contentRect: root.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.level = .floating; panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = root
        close.target = panel; close.action = #selector(NSWindow.close)
        panel.isReleasedWhenClosed = false
        let screen = NSScreen.screens.first { $0.frame.contains(p) } ?? NSScreen.main!
        let y = min(max(p.y - h / 2, screen.visibleFrame.minY + 8), screen.visibleFrame.maxY - h - 8)
        panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - w - 16, y: y))
        panel.orderFrontRegardless()
        panels.append(panel)
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: panel, queue: .main) { _ in panels.removeAll { $0 === panel } }
    }
}

private final class ShelfItem: NSView, NSDraggingSource {
    let url: URL
    init(url: URL, frame: NSRect) {
        self.url = url
        super.init(frame: frame)
        let icon = NSImageView(frame: NSRect(x: 12, y: 22, width: 52, height: 52))
        icon.image = NSWorkspace.shared.icon(forFile: url.path)
        addSubview(icon)
        let name = NSTextField(labelWithString: url.lastPathComponent)
        name.font = .systemFont(ofSize: 10.5, weight: .medium); name.textColor = NSColor(white: 1, alpha: 0.85)
        name.lineBreakMode = .byTruncatingMiddle; name.alignment = .center
        name.frame = NSRect(x: 2, y: 2, width: frame.width - 4, height: 16)
        addSubview(name)
    }
    required init?(coder: NSCoder) { fatalError() }
    func draggingSession(_ s: NSDraggingSession, sourceOperationMaskFor c: NSDraggingContext) -> NSDragOperation { [.copy, .move] }
    override func mouseDown(with e: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        item.setDraggingFrame(NSRect(x: 10, y: 20, width: 56, height: 56), contents: NSWorkspace.shared.icon(forFile: url.path))
        beginDraggingSession(with: [item], event: e, source: self)
    }
}
