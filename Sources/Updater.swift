import Foundation
import CryptoKit

// Mise à jour automatique : lit la dernière release GitHub, télécharge le .dmg, vérifie, remplace l'app.
// Garde-fous : HTTPS vers github.com uniquement, SHA-256 obligatoire (annoncée dans les notes de la release),
// bundle id + version + signature contrôlés avant tout remplacement, remplacement avec retour arrière.

struct ReleaseInfo {
    let version: String
    let dmgURL: URL
    let sha256: String?
    let notes: String
}

struct UpdateError: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) { description = d }
}

enum Updater {
    static let defaultAPI = "https://api.github.com/repos/Agarthe-A/mandarine/releases/latest"
    static let allowedPrefix = "https://github.com/Agarthe-A/mandarine/releases/download/"
    static let releasesPage = URL(string: "https://github.com/Agarthe-A/mandarine/releases/latest")!
    static let bundleID = "fr.julian.mandarine"

    static func version(of app: URL) -> String? {
        NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))?["CFBundleShortVersionString"] as? String
    }
    static var current: String { version(of: Bundle.main.bundleURL) ?? "0" }

    static var autoCheck: Bool {
        get { UserDefaults.standard.object(forKey: "autoUpdateCheck") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "autoUpdateCheck") }
    }

    // MARK: versions
    static func parts(_ v: String) -> [Int] {
        var s = v.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        return s.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }
    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    // MARK: réseau
    static func fetch(_ url: URL, timeout: TimeInterval, accept: String) throws -> Data {
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        req.setValue("Mandarine/\(current)", forHTTPHeaderField: "User-Agent")
        req.setValue(accept, forHTTPHeaderField: "Accept")
        let sem = DispatchSemaphore(value: 0)
        var result: Result<Data, Error> = .failure(UpdateError("pas de réponse"))
        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err = err { result = .failure(err) }
            else if let h = resp as? HTTPURLResponse, h.statusCode != 200 { result = .failure(UpdateError("HTTP \(h.statusCode)")) }
            else { result = .success(data ?? Data()) }
            sem.signal()
        }.resume()
        sem.wait()
        return try result.get()
    }

    static func latest(api: String = defaultAPI) throws -> ReleaseInfo {
        guard let u = URL(string: api) else { throw UpdateError("adresse invalide") }
        let data = try fetch(u, timeout: 20, accept: "application/vnd.github+json")
        guard let j = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = j["tag_name"] as? String else { throw UpdateError("réponse inattendue du serveur") }
        let assets = j["assets"] as? [[String: Any]] ?? []
        guard let a = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".dmg") == true }),
              let s = a["browser_download_url"] as? String, let du = URL(string: s)
        else { throw UpdateError("aucun .dmg dans la version \(tag)") }
        let notes = j["body"] as? String ?? ""
        var sha: String?
        if let r = notes.range(of: "SHA-256:\\s*[0-9a-fA-F]{64}", options: .regularExpression) {
            sha = String(notes[r].suffix(64)).lowercased()
        }
        var v = tag; if v.hasPrefix("v") || v.hasPrefix("V") { v.removeFirst() }
        return ReleaseInfo(version: v, dmgURL: du, sha256: sha, notes: notes)
    }

    static func shortNotes(_ n: String) -> String {
        let lines = n.split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init).filter { !$0.contains("SHA-256") && !$0.contains("FFmpeg") }
        let s = lines.joined(separator: "\n")
        return s.count > 600 ? String(s.prefix(600)) + "…" : s
    }

    // MARK: installation
    @discardableResult
    static func run(_ exe: String, _ args: [String]) throws -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
        let out = Pipe(); p.standardOutput = out; p.standardError = out
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let s = String(decoding: data, as: UTF8.self)
        if p.terminationStatus != 0 {
            throw UpdateError("\(URL(fileURLWithPath: exe).lastPathComponent) a échoué : \(s.suffix(200))")
        }
        return s
    }

    /// Remplace `target` (un .app) par la version annoncée dans `r`. Ne relance rien.
    static func install(_ r: ReleaseInfo, target: URL, strict: Bool, log: (String) -> Void = { _ in }) throws {
        let fm = FileManager.default
        let cur = version(of: target) ?? current
        guard isNewer(r.version, than: cur) else { throw UpdateError("déjà à jour (\(cur))") }
        if strict, !r.dmgURL.absoluteString.hasPrefix(allowedPrefix) {
            throw UpdateError("adresse de téléchargement non autorisée")
        }
        guard let want = r.sha256 else {
            throw UpdateError("empreinte SHA-256 absente de la version : mise à jour refusée")
        }
        if target.path.contains("/AppTranslocation/") {
            throw UpdateError("Mandarine tourne depuis un emplacement temporaire : glisse-la dans Applications, puis relance-la")
        }
        let parent = target.deletingLastPathComponent()
        guard fm.isWritableFile(atPath: parent.path) else {
            throw UpdateError("pas le droit d'écrire dans \(parent.path)")
        }
        let work = fm.temporaryDirectory.appendingPathComponent("mandarine-update-\(UUID().uuidString.prefix(8))")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        log("téléchargement…")
        let data = try fetch(r.dmgURL, timeout: 600, accept: "application/octet-stream")
        let got = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard got == want else { throw UpdateError("empreinte SHA-256 incorrecte : fichier refusé") }
        let dmg = work.appendingPathComponent("Mandarine.dmg")
        try data.write(to: dmg)

        log("vérification…")
        let mnt = work.appendingPathComponent("mnt")
        try fm.createDirectory(at: mnt, withIntermediateDirectories: true)
        try run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mnt.path, dmg.path])
        defer { _ = try? run("/usr/bin/hdiutil", ["detach", "-force", mnt.path]) }

        let src = mnt.appendingPathComponent("Mandarine.app")
        let info = NSDictionary(contentsOf: src.appendingPathComponent("Contents/Info.plist"))
        guard info?["CFBundleIdentifier"] as? String == bundleID else { throw UpdateError("le .dmg ne contient pas Mandarine") }
        guard info?["CFBundleShortVersionString"] as? String == r.version else {
            throw UpdateError("la version du .dmg ne correspond pas à l'annonce")
        }

        let pid = ProcessInfo.processInfo.processIdentifier
        let stage = parent.appendingPathComponent(".Mandarine-update-\(pid).app")
        let backup = parent.appendingPathComponent(".Mandarine-old-\(pid).app")
        try? fm.removeItem(at: stage); try? fm.removeItem(at: backup)
        try run("/usr/bin/ditto", [src.path, stage.path])
        do {
            try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", stage.path])
            guard fm.isExecutableFile(atPath: stage.appendingPathComponent("Contents/MacOS/Mandarine").path) else {
                throw UpdateError("exécutable manquant dans le .dmg")
            }
        } catch { try? fm.removeItem(at: stage); throw error }
        _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", stage.path])

        log("installation…")
        do {
            if fm.fileExists(atPath: target.path) { try fm.moveItem(at: target, to: backup) }
            do { try fm.moveItem(at: stage, to: target) }
            catch {
                if fm.fileExists(atPath: backup.path) { try? fm.moveItem(at: backup, to: target) }
                throw error
            }
        } catch { try? fm.removeItem(at: stage); throw error }
        try? fm.removeItem(at: backup)
    }

    static func relaunch(_ app: URL) {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open -n \"$1\"", "sh", app.path]
        try? p.run()
    }
}
