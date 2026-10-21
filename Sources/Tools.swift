import Foundation
import AppKit
import PDFKit

/// Un outil de la roue ⌘ : id `tool:<id>`, titre affiché, types de fichiers acceptés.
/// Pour en ajouter un : créer un `Tool(...)` et l'insérer dans `Tools.all` (l'ordre = l'ordre dans la roue).
struct Tool {
    let id: String
    let title: String
    /// Types de fichiers acceptés (la sélection doit être d'un seul type).
    let kinds: Set<Kind>
    /// Nombre minimal de fichiers (2 pour fusionner, etc.).
    var minCount = 1
    /// Filtre fin optionnel (ex. extension) ; `nil` = pas de filtre.
    var accepts: ((URL) -> Bool)? = nil
    let run: ([URL]) throws -> [URL]

    func applies(to urls: [URL], kinds ks: Set<Kind>) -> Bool {
        guard urls.count >= minCount, ks.count == 1, let k = ks.first, kinds.contains(k) else { return false }
        if let accepts { return urls.allSatisfy(accepts) }
        return true
    }
}

/// Outil appliqué fichier par fichier : `body(src, kind)` renvoie le fichier produit.
private func perFile(_ body: @escaping (URL, Kind) throws -> URL) -> ([URL]) throws -> [URL] {
    { urls in try urls.map { try body($0, Engine.kind(of: $0)) } }
}

enum Tools {
    static let all: [Tool] = [
        Tool(id: "imagesToPDF", title: "Créer un PDF", kinds: [.image], minCount: 2, run: imagesToPDF),
        Tool(id: "mergePDF", title: "Fusionner PDF", kinds: [.pdf], minCount: 2, run: mergePDF),
        Tool(id: "compress", title: "Compresser", kinds: [.image, .video, .audio], run: perFile(compress)),
        Tool(id: "resize50", title: "Réduire 50 %", kinds: [.image], run: perFile(resize50)),
        Tool(id: "mute", title: "Couper le son", kinds: [.video], run: perFile(mute)),
        Tool(id: "strip", title: "Sans métadonnées", kinds: [.image, .video, .audio], run: perFile(strip)),
        // — ajoutés dans la v0.2 (tous sans paramètre) —
        Tool(id: "rotate90", title: "Pivoter 90°", kinds: [.image], accepts: { sipsEditable.contains(Engine.normExt($0.pathExtension)) }, run: perFile(rotate90)),
        Tool(id: "gray", title: "Niveaux de gris", kinds: [.image], accepts: { sipsEditable.contains(Engine.normExt($0.pathExtension)) }, run: perFile(gray)),
        Tool(id: "video720", title: "Réduire en 720p", kinds: [.video], run: perFile(video720)),
        Tool(id: "speed2", title: "Accélérer ×2", kinds: [.video], run: perFile(speed2)),
        Tool(id: "normalize", title: "Normaliser le volume", kinds: [.audio], accepts: { audioCodecs[Engine.normExt($0.pathExtension)] != nil }, run: perFile(normalize)),
        Tool(id: "trimSilence", title: "Couper les silences", kinds: [.audio], accepts: { audioCodecs[Engine.normExt($0.pathExtension)] != nil }, run: perFile(trimSilence)),
        Tool(id: "firstPage", title: "1re page", kinds: [.pdf], run: perFile(firstPage)),
        Tool(id: "compressPDF", title: "Compresser PDF", kinds: [.pdf], accepts: { _ in Engine.ghostscript != nil }, run: perFile(compressPDF)),
    ]

    /// Formats image modifiables via sips (testés : jpg, png).
    static let sipsEditable: Set<String> = ["jpg", "png"]
    /// Audio réencodable en gardant le même conteneur (testés : tous ceux listés).
    static let audioCodecs: [String: [String]] = [
        "mp3": ["-c:a", "libmp3lame", "-q:a", "2"], "m4a": ["-c:a", "aac", "-b:a", "192k"],
        "wav": ["-c:a", "pcm_s16le"], "flac": ["-c:a", "flac"],
        "opus": ["-c:a", "libopus", "-b:a", "128k"], "aiff": ["-c:a", "pcm_s16be"],
    ]

    // MARK: outils multi-fichiers
    static func imagesToPDF(_ urls: [URL]) throws -> [URL] {
        let doc = PDFDocument()
        for u in urls {
            guard let img = NSImage(contentsOf: u), let page = PDFPage(image: img) else { throw EngineError("image illisible: \(u.lastPathComponent)") }
            doc.insert(page, at: doc.pageCount)
        }
        let out = Engine.outURL(urls[0], ext: "pdf")
        guard doc.write(to: out) else { throw EngineError("écriture du PDF impossible") }
        return [out]
    }

    static func mergePDF(_ urls: [URL]) throws -> [URL] {
        let doc = PDFDocument()
        for u in urls {
            guard let d = PDFDocument(url: u) else { throw EngineError("PDF illisible: \(u.lastPathComponent)") }
            for i in 0..<d.pageCount { if let p = d.page(at: i) { doc.insert(p, at: doc.pageCount) } }
        }
        let out = Engine.outURL(urls[0], ext: "pdf", suffix: "-fusion")
        guard doc.write(to: out) else { throw EngineError("écriture du PDF impossible") }
        return [out]
    }

    // MARK: outils par fichier
    static func compress(_ src: URL, _ k: Kind) throws -> URL {
        let e = Engine.normExt(src.pathExtension)
        let out = Engine.outURL(src, ext: src.pathExtension, suffix: "-compressé")
        switch k {
        case .image:
            if e == "jpg" || e == "heic" {
                try Engine.run("/usr/bin/sips", ["-s", "formatOptions", "55", src.path, "--out", out.path])
            } else if e == "png" {
                try Engine.ff(["-i", src.path, "-vf", "split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=bayer", out.path])
            } else if e == "webp" {
                try Engine.ff(["-i", src.path, "-c:v", "libwebp", "-quality", "60", out.path])
            } else { throw EngineError("compression non supportée pour .\(e)") }
        case .video:
            try Engine.ff(["-i", src.path, "-c:v", "libx264", "-crf", "28", "-preset", "medium", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart", out.path])
        case .audio:
            let o2 = Engine.outURL(src, ext: "mp3", suffix: "-compressé")
            try Engine.ff(["-i", src.path, "-vn", "-c:a", "libmp3lame", "-b:a", "128k", o2.path])
            return o2
        default: throw EngineError("outil indisponible pour ce type de fichier")
        }
        return out
    }

    static func resize50(_ src: URL, _ k: Kind) throws -> URL {
        guard k == .image else { throw EngineError("outil indisponible pour ce type de fichier") }
        let out = Engine.outURL(src, ext: src.pathExtension, suffix: "-50pct")
        let info = try Engine.run("/usr/bin/sips", ["-g", "pixelWidth", src.path])
        guard let w = info.split(separator: " ").last.flatMap({ Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }) else { throw EngineError("taille illisible") }
        try Engine.run("/usr/bin/sips", ["-Z", String(max(w / 2, 1)), src.path, "--out", out.path])
        return out
    }

    static func mute(_ src: URL, _ k: Kind) throws -> URL {
        guard k == .video else { throw EngineError("outil indisponible pour ce type de fichier") }
        let out = Engine.outURL(src, ext: src.pathExtension, suffix: "-muet")
        try Engine.ff(["-i", src.path, "-an", "-c:v", "copy", out.path])
        return out
    }

    static func strip(_ src: URL, _ k: Kind) throws -> URL {
        guard [.image, .video, .audio].contains(k) else { throw EngineError("outil indisponible pour ce type de fichier") }
        let out = Engine.outURL(src, ext: src.pathExtension, suffix: "-propre")
        try Engine.ff(["-i", src.path, "-map_metadata", "-1", "-map", "0", "-c", "copy", out.path])
        return out
    }

    // MARK: v0.2
    static func rotate90(_ src: URL, _ k: Kind) throws -> URL {
        let out = Engine.outURL(src, ext: src.pathExtension, suffix: "-pivoté")
        try Engine.run("/usr/bin/sips", ["-r", "90", src.path, "--out", out.path])
        return out
    }

    static func gray(_ src: URL, _ k: Kind) throws -> URL {
        let profile = "/System/Library/ColorSync/Profiles/Generic Gray Profile.icc"
        guard FileManager.default.fileExists(atPath: profile) else { throw EngineError("profil de gris introuvable") }
        let out = Engine.outURL(src, ext: src.pathExtension, suffix: "-gris")
        try Engine.run("/usr/bin/sips", ["-m", profile, src.path, "--out", out.path])
        return out
    }

    /// Réduit à 720 px de haut au plus (n'agrandit jamais), sortie MP4.
    static func video720(_ src: URL, _ k: Kind) throws -> URL {
        let out = Engine.outURL(src, ext: "mp4", suffix: "-720p")
        try Engine.ff(["-i", src.path, "-vf", "scale=-2:'min(720,ih)'", "-c:v", "libx264", "-crf", "23", "-preset", "medium",
                       "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart", out.path])
        return out
    }

    static func speed2(_ src: URL, _ k: Kind) throws -> URL {
        let out = Engine.outURL(src, ext: "mp4", suffix: "-x2")
        try Engine.ff(["-i", src.path, "-vf", "setpts=PTS/2", "-af", "atempo=2", "-c:v", "libx264", "-crf", "23", "-preset", "medium",
                       "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart", out.path])
        return out
    }

    private static func audioOut(_ src: URL, suffix: String, filter: String) throws -> URL {
        let e = Engine.normExt(src.pathExtension)
        guard let codec = audioCodecs[e] else { throw EngineError("format audio non supporté pour cet outil: .\(e)") }
        let out = Engine.outURL(src, ext: src.pathExtension, suffix: suffix)
        try Engine.ff(["-i", src.path, "-vn", "-af", filter] + codec + [out.path])
        return out
    }

    /// Normalisation EBU R128 (loudnorm : -16 LUFS, pic -1,5 dB).
    static func normalize(_ src: URL, _ k: Kind) throws -> URL {
        try audioOut(src, suffix: "-normalisé", filter: "loudnorm=I=-16:TP=-1.5:LRA=11,aresample=48000")
    }

    /// Supprime le silence au début et à la fin (seuil -50 dB crête).
    static func trimSilence(_ src: URL, _ k: Kind) throws -> URL {
        let cut = "silenceremove=start_periods=1:start_threshold=-50dB:detection=peak"
        let out = try audioOut(src, suffix: "-sans-silences", filter: "\(cut),areverse,\(cut),areverse")
        let size = (try? FileManager.default.attributesOfItem(atPath: out.path)[.size] as? Int) ?? 0
        if size < 200 { try? FileManager.default.removeItem(at: out); throw EngineError("audio entièrement silencieux") }
        return out
    }

    static func firstPage(_ src: URL, _ k: Kind) throws -> URL {
        guard let d = PDFDocument(url: src), let p = d.page(at: 0) else { throw EngineError("PDF illisible: \(src.lastPathComponent)") }
        let doc = PDFDocument()
        doc.insert(p, at: 0)
        let out = Engine.outURL(src, ext: "pdf", suffix: "-page1")
        guard doc.write(to: out) else { throw EngineError("écriture du PDF impossible") }
        return out
    }

    /// Ghostscript (/ebook ≈ 150 dpi). Refuse de produire un fichier plus gros que l'original.
    static func compressPDF(_ src: URL, _ k: Kind) throws -> URL {
        guard let gs = Engine.ghostscript else { throw EngineError("Ghostscript (gs) introuvable") }
        let out = Engine.outURL(src, ext: "pdf", suffix: "-compressé")
        try Engine.run(gs, ["-sDEVICE=pdfwrite", "-dPDFSETTINGS=/ebook", "-dNOPAUSE", "-dBATCH", "-dQUIET", "-sOutputFile=" + out.path, src.path])
        func size(_ u: URL) -> Int { (try? FileManager.default.attributesOfItem(atPath: u.path)[.size] as? Int) ?? 0 }
        if size(out) >= size(src) { try? FileManager.default.removeItem(at: out); throw EngineError("PDF déjà optimisé (pas de gain)") }
        return out
    }
}
