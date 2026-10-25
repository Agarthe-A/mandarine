import Foundation
import AppKit
import PDFKit

enum Kind { case image, video, audio, pdf, doc, archive, folder, subtitle, table, other }

struct Item: Equatable {
    let id: String      // "convert:png", "tool:compress", "act:copypath"
    let title: String
}

struct EngineError: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) { description = d }
}

/// Noyau du moteur : classification des fichiers, utilitaires (processus, noms de sortie)
/// et dispatch vers les registres `Converters` (Converters.swift) et `Tools` (Tools.swift).
enum Engine {
    static let imageExts: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "webp", "avif", "gif", "bmp"]
    static let videoExts: Set<String> = ["mp4", "mov", "mkv", "webm", "avi", "wmv", "m4v", "flv"]
    static let audioExts: Set<String> = ["mp3", "m4a", "wav", "flac", "ogg", "opus", "aiff", "aif", "wma", "aac", "caf"]
    static let docExts: Set<String> = ["docx", "doc", "rtf", "txt", "html", "htm", "md", "markdown", "epub", "odt"]
    static let archiveExts: Set<String> = ["zip", "tar", "gz", "tgz"]
    static let subtitleExts: Set<String> = ["srt", "vtt"]
    static let tableExts: Set<String> = ["csv", "tsv"]

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
    /// Ghostscript (optionnel) : sert uniquement à « Compresser » un PDF.
    static let ghostscript: String? = {
        ["/opt/homebrew/bin/gs", "/usr/local/bin/gs"].first { FileManager.default.isExecutableFile(atPath: $0) }
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
        if subtitleExts.contains(e) { return .subtitle }
        if tableExts.contains(e) { return .table }
        return .other
    }

    // MARK: liste des entrées de la roue
    static func convertTargets(for url: URL) -> [String] {
        Converters.converter(for: kind(of: url))?.targets(for: url) ?? []
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
            return Tools.all.filter { $0.applies(to: urls, kinds: kinds) }.map { Item(id: "tool:\($0.id)", title: $0.title) }
        default:
            return [Item(id: "act:copypath", title: "Copier le chemin"), Item(id: "act:float", title: "Flotter"), Item(id: "act:copy", title: "Copier"),
                    Item(id: "act:airdrop", title: "AirDrop"), Item(id: "act:move", title: "Déplacer…"),
                    Item(id: "act:terminal", title: "Terminal")]
        }
    }

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

    /// ffmpeg avec les options communes (-y, erreurs seulement).
    static func ff(_ args: [String]) throws {
        try run(ffmpeg, ["-y", "-loglevel", "error"] + args)
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

    static func outURL(_ src: URL, ext: String, suffix: String = "") -> URL {
        uniqueURL(dir: src.deletingLastPathComponent(), base: src.deletingPathExtension().lastPathComponent + suffix, ext: ext)
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
        guard let c = Converters.converter(for: kind(of: src)) else { throw EngineError("format non pris en charge") }
        return try c.convert(src, to: t)
    }

    static func tool(_ name: String, urls: [URL]) throws -> [URL] {
        guard let t = Tools.all.first(where: { $0.id == name }) else {
            throw EngineError("outil indisponible pour ce type de fichier")
        }
        return try t.run(urls)
    }
}
