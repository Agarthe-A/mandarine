import Foundation
import AppKit
import PDFKit

/// Stratégie de conversion pour un type de fichier (`Kind`).
/// Pour ajouter un type : créer un `struct XxxConverter: Converter` et l'ajouter à `Converters.all`.
protocol Converter {
    var kind: Kind { get }
    /// Extensions de sortie proposées pour ce fichier (sans l'extension d'origine).
    func targets(for url: URL) -> [String]
    func convert(_ src: URL, to t: String) throws -> URL
}

enum Converters {
    static let all: [Converter] = [
        ImageConverter(), VideoConverter(), AudioConverter(), PDFConverter(), DocConverter(),
        ArchiveConverter(), FolderConverter(), SubtitleConverter(), TableConverter(),
    ]
    static func converter(for kind: Kind) -> Converter? { all.first { $0.kind == kind } }
}

private func without(_ all: [String], _ url: URL) -> [String] {
    let e = Engine.normExt(url.pathExtension)
    return all.filter { $0 != e }
}

// MARK: images
struct ImageConverter: Converter {
    let kind = Kind.image
    static let sipsFormats = ["jpg": "jpeg", "png": "png", "tiff": "tiff", "gif": "gif", "bmp": "bmp", "heic": "heic", "pdf": "pdf"]

    func targets(for url: URL) -> [String] {
        without(["jpg", "png", "webp", "heic", "tiff", "avif", "gif", "pdf"], url)
    }

    func convert(_ src: URL, to t: String) throws -> URL {
        let out = Engine.outURL(src, ext: t)
        if let f = Self.sipsFormats[t] {
            try Engine.run("/usr/bin/sips", ["-s", "format", f, src.path, "--out", out.path])
        } else { // webp / avif via ffmpeg
            var input = src
            var tmpFile: URL?
            if !["png", "jpg", "jpeg", "tiff", "tif", "bmp", "gif", "webp"].contains(src.pathExtension.lowercased()) {
                let t = Engine.tmp("png")
                try Engine.run("/usr/bin/sips", ["-s", "format", "png", src.path, "--out", t.path])
                input = t; tmpFile = t
            }
            defer { if let t = tmpFile { try? FileManager.default.removeItem(at: t) } }
            let codec: [String] = t == "webp"
                ? ["-c:v", "libwebp", "-quality", "85"]
                : ["-c:v", "libaom-av1", "-still-picture", "1", "-crf", "28", "-cpu-used", "6", "-pix_fmt", "yuv420p"]
            try Engine.ff(["-i", input.path] + codec + [out.path])
        }
        return out
    }
}

// MARK: vidéo
struct VideoConverter: Converter {
    let kind = Kind.video
    func targets(for url: URL) -> [String] { without(["mp4", "mov", "mkv", "webm", "gif", "mp3"], url) }

    func convert(_ src: URL, to t: String) throws -> URL {
        let out = Engine.outURL(src, ext: t)
        var a = ["-i", src.path]
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
        try Engine.ff(a + [out.path])
        return out
    }
}

// MARK: audio
struct AudioConverter: Converter {
    let kind = Kind.audio
    func targets(for url: URL) -> [String] { without(["mp3", "m4a", "wav", "flac", "opus", "ogg", "aiff"], url) }

    func convert(_ src: URL, to t: String) throws -> URL {
        let out = Engine.outURL(src, ext: t)
        var a = ["-i", src.path, "-vn"]
        switch t {
        case "mp3": a += ["-c:a", "libmp3lame", "-q:a", "2"]
        case "m4a": a += ["-c:a", "aac", "-b:a", "192k"]
        case "wav": a += ["-c:a", "pcm_s16le"]
        case "flac": a += ["-c:a", "flac"]
        case "opus", "ogg": a += ["-c:a", "libopus", "-b:a", "128k"]
        case "aiff": a += ["-c:a", "pcm_s16be"]
        default: throw EngineError("format audio inconnu: \(t)")
        }
        try Engine.ff(a + [out.path])
        return out
    }
}

// MARK: PDF
struct PDFConverter: Converter {
    let kind = Kind.pdf
    func targets(for url: URL) -> [String] { ["png", "jpg", "txt"] }

    func convert(_ src: URL, to t: String) throws -> URL {
        guard let doc = PDFDocument(url: src) else { throw EngineError("PDF illisible") }
        if t == "txt" {
            let out = Engine.outURL(src, ext: "txt")
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
            let out = Engine.outURL(src, ext: t)
            try render(p).write(to: out)
            return out
        }
        let dir = Engine.uniqueURL(dir: src.deletingLastPathComponent(), base: src.deletingPathExtension().lastPathComponent, ext: "")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for i in 0..<doc.pageCount {
            guard let p = doc.page(at: i) else { continue }
            try render(p).write(to: dir.appendingPathComponent(String(format: "page-%02d.%@", i + 1, t)))
        }
        return dir
    }
}

// MARK: documents
struct DocConverter: Converter {
    let kind = Kind.doc

    func targets(for url: URL) -> [String] {
        let all: [String]
        switch Engine.normExt(url.pathExtension) {
        case "docx": all = ["pdf", "txt", "rtf", "html", "md", "epub"]
        case "doc": all = ["docx", "pdf", "txt", "rtf", "html"]
        case "rtf": all = ["docx", "pdf", "txt", "html", "md"]
        case "txt": all = ["docx", "pdf", "rtf", "html"]
        case "html": all = ["docx", "pdf", "txt", "rtf", "md"]
        case "md": all = ["docx", "html", "pdf", "epub", "txt"]
        case "epub": all = ["txt", "md", "docx", "html"]
        default: all = ["docx", "pdf", "txt", "html"]
        }
        return without(all, url)
    }

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

    func convert(_ src: URL, to t: String) throws -> URL {
        let e = Engine.normExt(src.pathExtension)
        let out = Engine.outURL(src, ext: t)
        let textutilIn: Set<String> = ["docx", "doc", "rtf", "txt", "html", "odt"]
        var cleanup: [URL] = []
        defer { cleanup.forEach { try? FileManager.default.removeItem(at: $0) } }

        func viaPandoc(_ input: URL, to fmt: String, output: URL) throws {
            var a = [input.path, "-o", output.path]
            if fmt == "txt" { a += ["-t", "plain"] }
            if fmt == "md" { a += ["-t", "gfm"] }
            if fmt == "html" { a += ["-s", "--metadata", "pagetitle=" + input.deletingPathExtension().lastPathComponent] }
            try Engine.run(Engine.pandoc, a)
        }

        if t == "pdf" {
            var input = src
            if !textutilIn.contains(e) {
                let t = Engine.tmp("docx"); cleanup.append(t)
                try viaPandoc(src, to: "docx", output: t); input = t
            }
            try Self.attributedToPDF(input, out: out)
            return out
        }
        if t == "md" || t == "epub" || e == "md" || e == "epub" {
            var input = src
            if e == "doc" || e == "rtf" {
                let t = Engine.tmp("docx"); cleanup.append(t)
                try Engine.run("/usr/bin/textutil", ["-convert", "docx", src.path, "-output", t.path]); input = t
            }
            try viaPandoc(input, to: t, output: out)
            return out
        }
        try Engine.run("/usr/bin/textutil", ["-convert", t, src.path, "-output", out.path])
        return out
    }
}

// MARK: archives & dossiers
struct ArchiveConverter: Converter {
    let kind = Kind.archive
    func targets(for url: URL) -> [String] { ["extract"] }

    func convert(_ src: URL, to t: String) throws -> URL {
        let dir = Engine.uniqueURL(dir: src.deletingLastPathComponent(), base: src.deletingPathExtension().lastPathComponent, ext: "")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if src.pathExtension.lowercased() == "zip" {
            try Engine.run("/usr/bin/ditto", ["-x", "-k", src.path, dir.path])
        } else {
            try Engine.run("/usr/bin/tar", ["-xf", src.path, "-C", dir.path])
        }
        return dir
    }
}

struct FolderConverter: Converter {
    let kind = Kind.folder
    func targets(for url: URL) -> [String] { ["zip", "tar.gz"] }

    func convert(_ src: URL, to t: String) throws -> URL {
        if t == "zip" {
            let out = Engine.outURL(src, ext: "zip")
            try Engine.run("/usr/bin/ditto", ["-c", "-k", "--keepParent", src.path, out.path])
            return out
        }
        let out = Engine.uniqueURL(dir: src.deletingLastPathComponent(), base: src.lastPathComponent, ext: "tar.gz")
        try Engine.run("/usr/bin/tar", ["-czf", out.path, "-C", src.deletingLastPathComponent().path, src.lastPathComponent])
        return out
    }
}

// MARK: sous-titres (srt ↔ vtt)
struct SubtitleConverter: Converter {
    let kind = Kind.subtitle
    func targets(for url: URL) -> [String] { Engine.normExt(url.pathExtension) == "srt" ? ["vtt"] : ["srt"] }

    func convert(_ src: URL, to t: String) throws -> URL {
        guard t == "srt" || t == "vtt" else { throw EngineError("format de sous-titres inconnu: \(t)") }
        let out = Engine.outURL(src, ext: t)
        try Engine.ff(["-i", src.path, out.path])
        return out
    }
}

// MARK: tableurs texte (csv ↔ tsv)
struct TableConverter: Converter {
    let kind = Kind.table
    func targets(for url: URL) -> [String] { Engine.normExt(url.pathExtension) == "csv" ? ["tsv"] : ["csv"] }

    func convert(_ src: URL, to t: String) throws -> URL {
        guard t == "csv" || t == "tsv" else { throw EngineError("format de tableau inconnu: \(t)") }
        let data = try Data(contentsOf: src)
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { throw EngineError("fichier illisible") }
        let from: Character = t == "tsv" ? "," : "\t"
        let to: Character = t == "tsv" ? "\t" : ","
        let rows = Self.parse(text, sep: from)
        let result = rows.map { row in row.map { Self.encode($0, sep: to) }.joined(separator: String(to)) }.joined(separator: "\n") + "\n"
        let out = Engine.outURL(src, ext: t)
        try result.write(to: out, atomically: true, encoding: .utf8)
        return out
    }

    /// Analyse CSV/TSV avec guillemets (RFC 4180) ; fins de ligne \n, \r\n ou \r.
    static func parse(_ s: String, sep: Character) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = ""
        var inQuotes = false, sawAny = false
        let chars = Array(s.unicodeScalars.map { Character($0) })
        var i = 0
        if chars.first == "\u{FEFF}" { i = 1 }
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 1 } else { inQuotes = false }
                } else { field.append(c) }
            } else if c == "\"" && field.isEmpty { inQuotes = true; sawAny = true }
            else if c == sep { row.append(field); field = ""; sawAny = true }
            else if c == "\r\n" || c == "\n" || c == "\r" {
                if sawAny || !field.isEmpty { row.append(field); rows.append(row) }
                row = []; field = ""; sawAny = false
            } else { field.append(c); sawAny = true }
            i += 1
        }
        if sawAny || !field.isEmpty { row.append(field); rows.append(row) }
        return rows
    }

    static func encode(_ f: String, sep: Character) -> String {
        if sep == "\t" { // TSV : pas de guillemets, tabulations/retours remplacés par des espaces
            return f.map { $0 == "\t" || $0 == "\n" || $0 == "\r" || $0 == "\r\n" ? " " : String($0) }.joined()
        }
        if f.contains(",") || f.contains("\"") || f.contains("\n") || f.contains("\r") {
            return "\"" + f.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return f
    }
}
