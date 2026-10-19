import Foundation
import AppKit
import PDFKit

enum Kind { case image, video, audio, pdf, doc, archive, folder, other }

struct Item: Equatable {
    let id: String      // "convert:png", "tool:compress", "act:copypath"
    let title: String
}

struct EngineError: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) { description = d }
}

enum Engine {
    static let imageExts: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "webp", "avif", "gif", "bmp"]
    static let videoExts: Set<String> = ["mp4", "mov", "mkv", "webm", "avi", "wmv", "m4v", "flv"]
    static let audioExts: Set<String> = ["mp3", "m4a", "wav", "flac", "ogg", "opus", "aiff", "aif", "wma", "aac", "caf"]
    static let docExts: Set<String> = ["docx", "doc", "rtf", "txt", "html", "htm", "md", "markdown", "epub", "odt"]
    static let archiveExts: Set<String> = ["zip", "tar", "gz", "tgz"]

    // MARK: binaries
    static let ffmpeg: String = {
        let fm = FileManager.default
        var c: [String] = []
        if let r = Bundle.main.resourcePath { c.append(r + "/ffmpeg") }
        c += [NSHomeDirectory() + "/.hermes/tools/ffmpeg-9.0.1-darwin-arm64/ffmpeg", "/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
        return c.first { fm.isExecutableFile(atPath: $0) } ?? "ffmpeg"
    }()
    static let pandoc: String = {
        ["/opt/homebrew/bin/pandoc", "/usr/local/bin/pandoc"].first { FileManager.default.isExecutableFile(atPath: $0) } ?? "pandoc"
    }()

    // MARK: classification
    static func normExt(_ e: String) -> String {
        switch e.lowercased() {
        case "jpeg": return "jpg"
        case "tif": return "tiff"
        case "heif": return "heic"
        case "aif": return "aiff"
        case "htm": return "html"
        case "markdown": return "md"
        default: return e.lowercased()
        }
    }

    static func kind(of url: URL) -> Kind {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        if isDir.boolValue { return .folder }
        let e = url.pathExtension.lowercased()
        if imageExts.contains(e) { return .image }
        if videoExts.contains(e) { return .video }
        if audioExts.contains(e) { return .audio }
        if e == "pdf" { return .pdf }
        if docExts.contains(e) { return .doc }
        if archiveExts.contains(e) { return .archive }
        return .other
    }

    static func convertTargets(for url: URL) -> [String] {
        let e = normExt(url.pathExtension)
        let all: [String]
        switch kind(of: url) {
        case .image: all = ["jpg", "png", "webp", "heic", "tiff", "avif", "gif", "pdf"]
        case .video: all = ["mp4", "mov", "mkv", "webm", "gif", "mp3"]
        case .audio: all = ["mp3", "m4a", "wav", "flac", "opus", "ogg", "aiff"]
        case .pdf: all = ["png", "jpg", "txt"]
        case .doc:
            switch e {
            case "docx": all = ["pdf", "txt", "rtf", "html", "md", "epub"]
            case "doc": all = ["docx", "pdf", "txt", "rtf", "html"]
            case "rtf": all = ["docx", "pdf", "txt", "html", "md"]
            case "txt": all = ["docx", "pdf", "rtf", "html"]
            case "html": all = ["docx", "pdf", "txt", "rtf", "md"]
            case "md": all = ["docx", "html", "pdf", "epub", "txt"]
            case "epub": all = ["txt", "md", "docx", "html"]
            default: all = ["docx", "pdf", "txt", "html"]
            }
        case .archive: return ["extract"]
        case .folder: return ["zip", "tar.gz"]
        case .other: return []
        }
        return all.filter { $0 != e }
    }

    static func items(mode: String, urls: [URL]) -> [Item] {
        guard let first = urls.first else { return [] }
        let kinds = Set(urls.map { kind(of: $0) })
        switch mode {
        case "convert":
            guard kinds.count == 1 else { return [] }
            // intersection of targets across the selection
            var targets = convertTargets(for: first)
            for u in urls.dropFirst() { targets = targets.filter(Set(convertTargets(for: u)).contains) }
            return targets.map { Item(id: "convert:\($0)", title: $0 == "extract" ? "Extraire" : $0.uppercased()) }
        case "tools":
            var out: [Item] = []
            if urls.count >= 2, kinds == [.image] { out.append(Item(id: "tool:imagesToPDF", title: "Créer un PDF")) }
            if urls.count >= 2, kinds == [.pdf] { out.append(Item(id: "tool:mergePDF", title: "Fusionner PDF")) }
            if kinds.count == 1 {
                switch first_kind(kinds) {
                case .image: out += [Item(id: "tool:compress", title: "Compresser"), Item(id: "tool:resize50", title: "Réduire 50 %"), Item(id: "tool:strip", title: "Sans métadonnées")]
                case .video: out += [Item(id: "tool:compress", title: "Compresser"), Item(id: "tool:mute", title: "Couper le son"), Item(id: "tool:strip", title: "Sans métadonnées")]
                case .audio: out += [Item(id: "tool:compress", title: "Compresser"), Item(id: "tool:strip", title: "Sans métadonnées")]
                default: break
                }
            }
            return out
        default:
            return [Item(id: "act:copypath", title: "Copier le chemin"), Item(id: "act:copy", title: "Copier"),
                    Item(id: "act:airdrop", title: "AirDrop"), Item(id: "act:move", title: "Déplacer…"),
                    Item(id: "act:terminal", title: "Terminal")]
        }
    }
    private static func first_kind(_ k: Set<Kind>) -> Kind { k.first! }

    // MARK: process helpers
    @discardableResult
    static func run(_ exe: String, _ args: [String], stdoutTo: URL? = nil) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        let errURL = FileManager.default.temporaryDirectory.appendingPathComponent("mandarine-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: errURL.path, contents: nil)
        let errH = try FileHandle(forWritingTo: errURL)
        p.standardError = errH
        if let o = stdoutTo {
            FileManager.default.createFile(atPath: o.path, contents: nil)
            p.standardOutput = try FileHandle(forWritingTo: o)
        } else { p.standardOutput = errH }
        do { try p.run() } catch { throw EngineError("Impossible de lancer \((exe as NSString).lastPathComponent)") }
        p.waitUntilExit()
        try? errH.close()
        let log = (try? String(contentsOf: errURL, encoding: .utf8)) ?? ""
        try? FileManager.default.removeItem(at: errURL)
        if p.terminationStatus != 0 {
            if let o = stdoutTo { try? FileManager.default.removeItem(at: o) }
            let last = log.split(separator: "\n").suffix(2).joined(separator: " ")
            throw EngineError("\((exe as NSString).lastPathComponent) a échoué: \(last)")
        }
        return log
    }

    static func uniqueURL(dir: URL, base: String, ext: String) -> URL {
        let fm = FileManager.default
        let suffix = ext.isEmpty ? "" : "." + ext
        var u = dir.appendingPathComponent(base + suffix)
        var i = 1
        while fm.fileExists(atPath: u.path) { u = dir.appendingPathComponent("\(base) (\(i))\(suffix)"); i += 1 }
        return u
    }

    static func tmp(_ ext: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("mandarine-\(UUID().uuidString).\(ext)")
    }

    // MARK: dispatch
    static func perform(_ id: String, urls: [URL]) throws -> [URL] {
        let parts = id.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { throw EngineError("action inconnue") }
        switch parts[0] {
        case "convert": return try urls.map { try convert($0, to: parts[1]) }
        case "tool": return try tool(parts[1], urls: urls)
        default: return []
        }
    }

    static func convert(_ src: URL, to t: String) throws -> URL {
        switch kind(of: src) {
        case .image: return try convertImage(src, to: t)
        case .video: return try convertVideo(src, to: t)
        case .audio: return try convertAudio(src, to: t)
        case .pdf: return try convertPDF(src, to: t)
        case .doc: return try convertDoc(src, to: t)
        case .archive: return try extract(src)
        case .folder: return try compressFolder(src, to: t)
        case .other: throw EngineError("format non pris en charge")
        }
    }

    static func outURL(_ src: URL, ext: String, suffix: String = "") -> URL {
        uniqueURL(dir: src.deletingLastPathComponent(), base: src.deletingPathExtension().lastPathComponent + suffix, ext: ext)
    }

    // MARK: images
    static let sipsFormats = ["jpg": "jpeg", "png": "png", "tiff": "tiff", "gif": "gif", "bmp": "bmp", "heic": "heic", "pdf": "pdf"]

    static func convertImage(_ src: URL, to t: String) throws -> URL {
        let out = outURL(src, ext: t)
        if let f = sipsFormats[t] {
            try run("/usr/bin/sips", ["-s", "format", f, src.path, "--out", out.path])
        } else { // webp / avif via ffmpeg
            var input = src
            var tmpFile: URL?
            if !["png", "jpg", "jpeg", "tiff", "tif", "bmp", "gif", "webp"].contains(src.pathExtension.lowercased()) {
                let t = tmp("png")
                try run("/usr/bin/sips", ["-s", "format", "png", src.path, "--out", t.path])
                input = t; tmpFile = t
            }
            defer { if let t = tmpFile { try? FileManager.default.removeItem(at: t) } }
            let codec: [String] = t == "webp"
                ? ["-c:v", "libwebp", "-quality", "85"]
                : ["-c:v", "libaom-av1", "-still-picture", "1", "-crf", "28", "-cpu-used", "6", "-pix_fmt", "yuv420p"]
            try run(ffmpeg, ["-y", "-loglevel", "error", "-i", input.path] + codec + [out.path])
        }
        return out
    }

    // MARK: video / audio
    static func convertVideo(_ src: URL, to t: String) throws -> URL {
        let out = outURL(src, ext: t)
        var a = ["-y", "-loglevel", "error", "-i", src.path]
        switch t {
        case "mp4", "mov":
            a += ["-c:v", "libx264", "-crf", "20", "-preset", "medium", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart"]
        case "mkv":
            a += ["-c:v", "libx264", "-crf", "20", "-preset", "medium", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k"]
        case "webm":
            a += ["-c:v", "libvpx-vp9", "-crf", "32", "-b:v", "0", "-row-mt", "1", "-c:a", "libopus", "-b:a", "128k"]
        case "gif":
            a += ["-vf", "fps=15,scale=480:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse", "-loop", "0"]
        case "mp3":
            a += ["-vn", "-c:a", "libmp3lame", "-q:a", "2"]
        default: throw EngineError("format vidéo inconnu: \(t)")
        }
        try run(ffmpeg, a + [out.path])
        return out
    }

    static func convertAudio(_ src: URL, to t: String) throws -> URL {
        let out = outURL(src, ext: t)
        var a = ["-y", "-loglevel", "error", "-i", src.path, "-vn"]
        switch t {
        case "mp3": a += ["-c:a", "libmp3lame", "-q:a", "2"]
        case "m4a": a += ["-c:a", "aac", "-b:a", "192k"]
        case "wav": a += ["-c:a", "pcm_s16le"]
        case "flac": a += ["-c:a", "flac"]
        case "opus", "ogg": a += ["-c:a", "libopus", "-b:a", "128k"]
        case "aiff": a += ["-c:a", "pcm_s16be"]
        default: throw EngineError("format audio inconnu: \(t)")
        }
        try run(ffmpeg, a + [out.path])
        return out
    }

    // MARK: PDF
    static func convertPDF(_ src: URL, to t: String) throws -> URL {
        guard let doc = PDFDocument(url: src) else { throw EngineError("PDF illisible") }
        if t == "txt" {
            let out = outURL(src, ext: "txt")
            try (doc.string ?? "").write(to: out, atomically: true, encoding: .utf8)
            return out
        }
        let type: NSBitmapImageRep.FileType = t == "jpg" ? .jpeg : .png
        func render(_ page: PDFPage) throws -> Data {
            let b = page.bounds(for: .mediaBox)
            let s = 300.0 / 72.0
            let img = page.thumbnail(of: NSSize(width: b.width * s, height: b.height * s), for: .mediaBox)
            guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let d = NSBitmapImageRep(cgImage: cg).representation(using: type, properties: [.compressionFactor: 0.9])
            else { throw EngineError("rendu de page impossible") }
            return d
        }
        if doc.pageCount == 1, let p = doc.page(at: 0) {
            let out = outURL(src, ext: t)
            try render(p).write(to: out)
            return out
        }
        let dir = uniqueURL(dir: src.deletingLastPathComponent(), base: src.deletingPathExtension().lastPathComponent, ext: "")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for i in 0..<doc.pageCount {
            guard let p = doc.page(at: i) else { continue }
            try render(p).write(to: dir.appendingPathComponent(String(format: "page-%02d.%@", i + 1, t)))
        }
        return dir
    }

    // MARK: documents

    /// Rend un document texte riche (docx, doc, rtf, html, txt, odt) en PDF paginé (Core Text, thread-safe).
    static func attributedToPDF(_ input: URL, out: URL) throws {
        let ext = input.pathExtension.lowercased()
        var opts: [NSAttributedString.DocumentReadingOptionKey: Any] = [:]
        switch ext {
        case "docx": opts[.documentType] = NSAttributedString.DocumentType.officeOpenXML
        case "doc": opts[.documentType] = NSAttributedString.DocumentType.docFormat
        case "rtf": opts[.documentType] = NSAttributedString.DocumentType.rtf
        case "html": opts[.documentType] = NSAttributedString.DocumentType.html
        case "odt": opts[.documentType] = NSAttributedString.DocumentType.officeOpenXML
        default: opts[.documentType] = NSAttributedString.DocumentType.plain
        }
        let data = try Data(contentsOf: input)
        let attr: NSAttributedString
        if ext == "txt" {
            let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            attr = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 12)])
        } else if let a = try? NSAttributedString(data: data, options: opts, documentAttributes: nil) {
            attr = a
        } else { throw EngineError("document illisible") }

        var page = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
        let margin: CGFloat = 54
        guard let ctx = CGContext(out as CFURL, mediaBox: &page, nil) else { throw EngineError("écriture du PDF impossible") }
        let fs = CTFramesetterCreateWithAttributedString(attr as CFAttributedString)
        let box = page.insetBy(dx: margin, dy: margin)
        var loc = 0
        let total = attr.length
        repeat {
            ctx.beginPDFPage(nil)
            let path = CGPath(rect: box, transform: nil)
            let frame = CTFramesetterCreateFrame(fs, CFRange(location: loc, length: 0), path, nil)
            CTFrameDraw(frame, ctx)
            let vis = CTFrameGetVisibleStringRange(frame)
            ctx.endPDFPage()
            if vis.length == 0 { break }
            loc += vis.length
        } while loc < total
        ctx.closePDF()
    }
    static func convertDoc(_ src: URL, to t: String) throws -> URL {
        let e = normExt(src.pathExtension)
        let out = outURL(src, ext: t)
        let textutilIn: Set<String> = ["docx", "doc", "rtf", "txt", "html", "odt"]
        var cleanup: [URL] = []
        defer { cleanup.forEach { try? FileManager.default.removeItem(at: $0) } }

        func viaPandoc(_ input: URL, to fmt: String, output: URL) throws {
            var a = [input.path, "-o", output.path]
            if fmt == "txt" { a += ["-t", "plain"] }
            if fmt == "md" { a += ["-t", "gfm"] }
            try run(pandoc, a)
        }

        if t == "pdf" {
            var input = src
            if !textutilIn.contains(e) {
                let t = tmp("docx"); cleanup.append(t)
                try viaPandoc(src, to: "docx", output: t); input = t
            }
            try attributedToPDF(input, out: out)
            return out
        }
        if t == "md" || t == "epub" || e == "md" || e == "epub" {
            var input = src
            if e == "doc" || e == "rtf" {
                let t = tmp("docx"); cleanup.append(t)
                try run("/usr/bin/textutil", ["-convert", "docx", src.path, "-output", t.path]); input = t
            }
            try viaPandoc(input, to: t, output: out)
            return out
        }
        try run("/usr/bin/textutil", ["-convert", t, src.path, "-output", out.path])
        return out
    }

    // MARK: archives
    static func extract(_ src: URL) throws -> URL {
        let dir = uniqueURL(dir: src.deletingLastPathComponent(), base: src.deletingPathExtension().lastPathComponent, ext: "")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if src.pathExtension.lowercased() == "zip" {
            try run("/usr/bin/ditto", ["-x", "-k", src.path, dir.path])
        } else {
            try run("/usr/bin/tar", ["-xf", src.path, "-C", dir.path])
        }
        return dir
    }

    static func compressFolder(_ src: URL, to t: String) throws -> URL {
        if t == "zip" {
            let out = outURL(src, ext: "zip")
            try run("/usr/bin/ditto", ["-c", "-k", "--keepParent", src.path, out.path])
            return out
        }
        let out = uniqueURL(dir: src.deletingLastPathComponent(), base: src.lastPathComponent, ext: "tar.gz")
        try run("/usr/bin/tar", ["-czf", out.path, "-C", src.deletingLastPathComponent().path, src.lastPathComponent])
        return out
    }

    // MARK: tools
    static func tool(_ name: String, urls: [URL]) throws -> [URL] {
        switch name {
        case "imagesToPDF":
            let doc = PDFDocument()
            for u in urls {
                guard let img = NSImage(contentsOf: u), let page = PDFPage(image: img) else { throw EngineError("image illisible: \(u.lastPathComponent)") }
                doc.insert(page, at: doc.pageCount)
            }
            let out = outURL(urls[0], ext: "pdf")
            guard doc.write(to: out) else { throw EngineError("écriture du PDF impossible") }
            return [out]
        case "mergePDF":
            let doc = PDFDocument()
            for u in urls {
                guard let d = PDFDocument(url: u) else { throw EngineError("PDF illisible: \(u.lastPathComponent)") }
                for i in 0..<d.pageCount { if let p = d.page(at: i) { doc.insert(p, at: doc.pageCount) } }
            }
            let out = outURL(urls[0], ext: "pdf", suffix: "-fusion")
            guard doc.write(to: out) else { throw EngineError("écriture du PDF impossible") }
            return [out]
        default:
            return try urls.map { try toolOne(name, $0) }
        }
    }

    static func toolOne(_ name: String, _ src: URL) throws -> URL {
        let k = kind(of: src)
        let e = normExt(src.pathExtension)
        let suffix: String
        switch name {
        case "compress": suffix = "-compressé"
        case "resize50": suffix = "-50pct"
        case "mute": suffix = "-muet"
        default: suffix = "-propre"
        }
        let out = outURL(src, ext: src.pathExtension, suffix: suffix)
        switch (name, k) {
        case ("compress", .image):
            if e == "jpg" || e == "heic" {
                try run("/usr/bin/sips", ["-s", "formatOptions", "55", src.path, "--out", out.path])
            } else if e == "png" {
                try run(ffmpeg, ["-y", "-loglevel", "error", "-i", src.path, "-vf", "split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=bayer", out.path])
            } else if e == "webp" {
                try run(ffmpeg, ["-y", "-loglevel", "error", "-i", src.path, "-c:v", "libwebp", "-quality", "60", out.path])
            } else { throw EngineError("compression non supportée pour .\(e)") }
        case ("resize50", .image):
            let info = try run("/usr/bin/sips", ["-g", "pixelWidth", src.path])
            guard let w = info.split(separator: " ").last.flatMap({ Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }) else { throw EngineError("taille illisible") }
            try run("/usr/bin/sips", ["-Z", String(max(w / 2, 1)), src.path, "--out", out.path])
        case ("compress", .video):
            try run(ffmpeg, ["-y", "-loglevel", "error", "-i", src.path, "-c:v", "libx264", "-crf", "28", "-preset", "medium", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart", out.path])
        case ("compress", .audio):
            let o2 = outURL(src, ext: "mp3", suffix: suffix)
            try run(ffmpeg, ["-y", "-loglevel", "error", "-i", src.path, "-vn", "-c:a", "libmp3lame", "-b:a", "128k", o2.path])
            return o2
        case ("mute", .video):
            try run(ffmpeg, ["-y", "-loglevel", "error", "-i", src.path, "-an", "-c:v", "copy", out.path])
        case ("strip", .image), ("strip", .video), ("strip", .audio):
            try run(ffmpeg, ["-y", "-loglevel", "error", "-i", src.path, "-map_metadata", "-1", "-map", "0", "-c", "copy", out.path])
        default: throw EngineError("outil indisponible pour ce type de fichier")
        }
        return out
    }
}
