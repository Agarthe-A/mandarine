import Foundation
import AppKit
import PDFKit
import ImageIO
import Vision

/// Infos lues par ffmpeg (durée, pistes, taille de la vidéo).
struct MediaInfo { let duration: Double; let hasAudio: Bool; let width: Int; let height: Int }

enum Media {
    static func probe(_ u: URL) throws -> MediaInfo {
        let log = try Engine.run(Engine.ffmpeg, ["-hide_banner", "-i", u.path, "-t", "0.1", "-f", "null", "-"])
        var dur = 0.0
        if let r = log.range(of: "Duration: [0-9:.]+", options: .regularExpression) {
            let t = log[r].dropFirst(10).split(separator: ":").compactMap { Double($0) }
            if t.count == 3 { dur = t[0] * 3600 + t[1] * 60 + t[2] }
        }
        var w = 0, h = 0
        if let re = try? NSRegularExpression(pattern: "Video:[^\\n]*?, (\\d{2,5})x(\\d{2,5})[ ,\\[]"),
           let m = re.firstMatch(in: log, range: NSRange(log.startIndex..., in: log)),
           let a = Range(m.range(at: 1), in: log), let b = Range(m.range(at: 2), in: log) {
            w = Int(log[a]) ?? 0; h = Int(log[b]) ?? 0
        }
        return MediaInfo(duration: dur, hasAudio: log.contains("Audio:"), width: w, height: h)
    }

    /// Image orientée comme à l'écran (EXIF appliqué), 4096 px max.
    static func loadImage(_ u: URL) throws -> CGImage {
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: 4096]
        guard let s = CGImageSourceCreateWithURL(u as CFURL, nil),
              let img = CGImageSourceCreateThumbnailAtIndex(s, 0, opts as CFDictionary)
        else { throw EngineError("image illisible: \(u.lastPathComponent)") }
        return img
    }

    static func png(width: Int, height: Int, _ draw: (CGContext) -> Void) throws -> Data {
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              true else { throw EngineError("dessin impossible") }
        draw(ctx)
        guard let img = ctx.makeImage(), let d = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])
        else { throw EngineError("écriture de l'image impossible") }
        return d
    }

    static let h264 = ["-c:v", "libx264", "-crf", "20", "-preset", "medium", "-pix_fmt", "yuv420p", "-movflags", "+faststart"]
}

extension Tools {
    // MARK: recadrer (image ou vidéo) en carré centré
    static func cropSquare(_ src: URL, _ k: Kind) throws -> URL {
        let crop = "crop='min(iw,ih)':'min(iw,ih)'"
        if k == .video {
            let out = Engine.outURL(src, ext: "mp4", suffix: "-carré")
            try Engine.ff(["-i", src.path, "-vf", crop] + Media.h264 + ["-c:a", "aac", "-b:a", "160k", out.path])
            return out
        }
        let out = Engine.outURL(src, ext: src.pathExtension, suffix: "-carré")
        try Engine.ff(["-i", src.path, "-vf", crop, "-frames:v", "1", "-q:v", "2", out.path])
        return out
    }

    // MARK: photo posée sur un fond dégradé, coins arrondis, ombre
    static func background(_ src: URL, _ k: Kind) throws -> URL {
        let img = try Media.loadImage(src)
        let w = img.width, h = img.height
        let pad = Int(Double(max(w, h)) * 0.12)
        let W = w + 2 * pad, H = h + 2 * pad
        let rect = CGRect(x: pad, y: pad, width: w, height: h)
        let radius = CGFloat(min(w, h)) * 0.035
        let data = try Media.png(width: W, height: H) { c in
            let cs = CGColorSpace(name: CGColorSpace.sRGB)!
            let g = CGGradient(colorsSpace: cs, colors: [CGColor(srgbRed: 1, green: 0.74, blue: 0.25, alpha: 1),
                                                         CGColor(srgbRed: 1, green: 0.38, blue: 0.0, alpha: 1)] as CFArray, locations: [0, 1])!
            c.drawLinearGradient(g, start: CGPoint(x: 0, y: CGFloat(H)), end: CGPoint(x: CGFloat(W), y: 0), options: [])
            let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
            c.saveGState()
            c.setShadow(offset: CGSize(width: 0, height: -CGFloat(pad) * 0.14), blur: CGFloat(pad) * 0.4, color: CGColor(gray: 0, alpha: 0.38))
            c.addPath(path); c.setFillColor(CGColor(gray: 1, alpha: 1)); c.fillPath()
            c.restoreGState()
            c.saveGState(); c.addPath(path); c.clip(); c.draw(img, in: rect); c.restoreGState()
        }
        let out = Engine.outURL(src, ext: "png", suffix: "-fond")
        try data.write(to: out)
        return out
    }

    // MARK: collage en grille
    static func collage(_ urls: [URL]) throws -> [URL] {
        let imgs = try urls.map(Media.loadImage)
        let cols = Int(ceil(sqrt(Double(imgs.count)))), rows = (imgs.count + cols - 1) / cols
        let cell = 640, gap = 24
        let W = cols * cell + (cols + 1) * gap, H = rows * cell + (rows + 1) * gap
        let data = try Media.png(width: W, height: H) { c in
            c.setFillColor(CGColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: W, height: H))
            for (i, img) in imgs.enumerated() {
                let r = i / cols, col = i % cols
                let x = gap + col * (cell + gap), y = H - gap - (r + 1) * cell - r * gap
                let box = CGRect(x: x, y: y, width: cell, height: cell)
                let s = max(CGFloat(cell) / CGFloat(img.width), CGFloat(cell) / CGFloat(img.height))
                let dw = CGFloat(img.width) * s, dh = CGFloat(img.height) * s
                c.saveGState()
                c.addPath(CGPath(roundedRect: box, cornerWidth: 22, cornerHeight: 22, transform: nil)); c.clip()
                c.draw(img, in: CGRect(x: box.midX - dw / 2, y: box.midY - dh / 2, width: dw, height: dh))
                c.restoreGState()
            }
        }
        let out = Engine.outURL(urls[0], ext: "png", suffix: "-collage")
        try data.write(to: out)
        return [out]
    }

    // MARK: vidéo
    static func slow(_ src: URL, _ k: Kind) throws -> URL {
        let info = try Media.probe(src)
        let out = Engine.outURL(src, ext: "mp4", suffix: "-lent")
        var a = ["-i", src.path, "-filter_complex", info.hasAudio ? "[0:v]setpts=2*PTS[v];[0:a]atempo=0.5[a]" : "[0:v]setpts=2*PTS[v]", "-map", "[v]"]
        if info.hasAudio { a += ["-map", "[a]", "-c:a", "aac", "-b:a", "160k"] }
        try Engine.ff(a + Media.h264 + [out.path])
        return out
    }

    static func joinVideos(_ urls: [URL]) throws -> [URL] {
        let infos = try urls.map(Media.probe)
        let w = max(2, (infos[0].width == 0 ? 1280 : infos[0].width) / 2 * 2), h = max(2, (infos[0].height == 0 ? 720 : infos[0].height) / 2 * 2)
        let audio = infos.allSatisfy { $0.hasAudio }
        var args: [String] = [], f = "", pairs = ""
        for (i, u) in urls.enumerated() {
            args += ["-i", u.path]
            f += "[\(i):v]scale=\(w):\(h):force_original_aspect_ratio=decrease,pad=\(w):\(h):(ow-iw)/2:(oh-ih)/2,setsar=1,fps=30,format=yuv420p[v\(i)];"
            if audio { f += "[\(i):a]aresample=48000,aformat=channel_layouts=stereo[a\(i)];" }
            pairs += audio ? "[v\(i)][a\(i)]" : "[v\(i)]"
        }
        f += pairs + "concat=n=\(urls.count):v=1:a=\(audio ? 1 : 0)[v]" + (audio ? "[a]" : "")
        let out = Engine.outURL(urls[0], ext: "mp4", suffix: "-assemblé")
        args += ["-filter_complex", f, "-map", "[v]"] + (audio ? ["-map", "[a]", "-c:a", "aac", "-b:a", "160k"] : []) + Media.h264 + [out.path]
        try Engine.ff(args)
        return [out]
    }

    static func videoFrame(_ src: URL, _ k: Kind) throws -> URL {
        let info = try Media.probe(src)
        let out = Engine.outURL(src, ext: "png", suffix: "-image")
        try Engine.ff(["-ss", String(format: "%.2f", info.duration / 2), "-i", src.path, "-frames:v", "1", out.path])
        return out
    }

    static func splitVideo(_ src: URL, _ k: Kind) throws -> URL {
        let info = try Media.probe(src)
        guard info.duration >= 1 else { throw EngineError("vidéo trop courte pour être coupée") }
        let dir = Engine.uniqueURL(dir: src.deletingLastPathComponent(), base: src.deletingPathExtension().lastPathComponent + "-parties", ext: "")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let half = String(format: "%.3f", info.duration / 2)
        let enc = Media.h264 + (info.hasAudio ? ["-c:a", "aac", "-b:a", "160k"] : [])
        try Engine.ff(["-i", src.path, "-t", half] + enc + [dir.appendingPathComponent("partie-1.mp4").path])
        try Engine.ff(["-ss", half, "-i", src.path] + enc + [dir.appendingPathComponent("partie-2.mp4").path])
        return dir
    }

    // MARK: audio
    static func mono(_ src: URL, _ k: Kind) throws -> URL {
        let e = Engine.normExt(src.pathExtension)
        guard let codec = audioCodecs[e] else { throw EngineError("format audio non supporté pour cet outil: .\(e)") }
        let out = Engine.outURL(src, ext: src.pathExtension, suffix: "-mono")
        try Engine.ff(["-i", src.path, "-vn", "-ac", "1"] + codec + [out.path])
        return out
    }

    /// Onde animée sur fond noir, 1280×720.
    static func visualizer(_ src: URL, _ k: Kind) throws -> URL {
        let out = Engine.outURL(src, ext: "mp4", suffix: "-vidéo")
        try Engine.ff(["-i", src.path, "-filter_complex",
                       "[0:a]showwaves=s=1280x720:mode=cline:colors=0xff9f0a:rate=30,format=yuv420p[v]",
                       "-map", "[v]", "-map", "0:a", "-c:v", "libx264", "-crf", "22", "-preset", "medium", "-c:a", "aac", "-b:a", "192k",
                       "-shortest", "-movflags", "+faststart", out.path])
        return out
    }

    // MARK: PDF
    static func splitPDF(_ src: URL, _ k: Kind) throws -> URL {
        guard let d = PDFDocument(url: src), d.pageCount > 1 else { throw EngineError("ce PDF n'a qu'une page") }
        let dir = Engine.uniqueURL(dir: src.deletingLastPathComponent(), base: src.deletingPathExtension().lastPathComponent + "-pages", ext: "")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for i in 0..<d.pageCount {
            guard let p = d.page(at: i) else { continue }
            let one = PDFDocument(); one.insert(p, at: 0)
            guard one.write(to: dir.appendingPathComponent(String(format: "page-%02d.pdf", i + 1))) else { throw EngineError("écriture du PDF impossible") }
        }
        return dir
    }

    static func rotatePDF(_ src: URL, _ k: Kind) throws -> URL {
        guard let d = PDFDocument(url: src) else { throw EngineError("PDF illisible: \(src.lastPathComponent)") }
        for i in 0..<d.pageCount { if let p = d.page(at: i) { p.rotation = (p.rotation + 90) % 360 } }
        let out = Engine.outURL(src, ext: "pdf", suffix: "-pivoté")
        guard d.write(to: out) else { throw EngineError("écriture du PDF impossible") }
        return out
    }

    // MARK: flouter visages et texte (Vision, tout reste sur le Mac)
    /// Détecte les visages et les textes puis les pixellise. Refuse de produire un fichier identique à l'original.
    static func redact(_ src: URL, _ k: Kind) throws -> URL {
        let img = try Media.loadImage(src)
        let faces = VNDetectFaceRectanglesRequest()
        let text = VNRecognizeTextRequest(); text.recognitionLevel = .accurate; text.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: img, options: [:]).perform([faces, text])
        let boxes = (faces.results ?? []).map { $0.boundingBox } + (text.results ?? []).map { $0.boundingBox }
        guard !boxes.isEmpty else { throw EngineError("aucun visage ni texte détecté") }
        let W = img.width, H = img.height
        let data = try Media.png(width: W, height: H) { c in
            c.draw(img, in: CGRect(x: 0, y: 0, width: W, height: H))
            for b in boxes {
                let pad = max(CGFloat(W) * b.width, CGFloat(H) * b.height) * 0.06
                var r = CGRect(x: b.minX * CGFloat(W), y: b.minY * CGFloat(H), width: b.width * CGFloat(W), height: b.height * CGFloat(H)).insetBy(dx: -pad, dy: -pad)
                r = r.intersection(CGRect(x: 0, y: 0, width: W, height: H)).integral
                guard r.width > 2, r.height > 2,
                      let crop = img.cropping(to: CGRect(x: r.minX, y: CGFloat(H) - r.maxY, width: r.width, height: r.height)) else { continue }
                // pixellisation : réduction forte puis agrandissement sans lissage
                let block = max(6, Int(min(r.width, r.height) / 5))
                let sw = max(1, Int(r.width) / block), sh = max(1, Int(r.height) / block)
                guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
                      let small = CGContext(data: nil, width: sw, height: sh, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
                small.interpolationQuality = .medium
                small.draw(crop, in: CGRect(x: 0, y: 0, width: sw, height: sh))
                guard let tiny = small.makeImage() else { continue }
                c.saveGState(); c.interpolationQuality = .none; c.draw(tiny, in: r); c.restoreGState()
            }
        }
        let out = Engine.outURL(src, ext: "png", suffix: "-flouté")
        try data.write(to: out)
        return out
    }
}
