import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

@_silgen_name("MeowRefreshCursor") func MeowRefreshCursor() -> Int32

let cream = Color(red: 0.99, green: 0.97, blue: 0.93)
let accent = Color(red: 0.74, green: 0.39, blue: 0.13)
let apricot = Color(red: 1, green: 0.87, blue: 0.67)
let ink = Color(red: 0.26, green: 0.26, blue: 0.28)
let roles = ["arrow", "pointing", "text", "wait"]
let symbols = ["arrow": "cursorarrow", "pointing": "hand.point.up.left", "text": "character.cursor.ibeam", "wait": "hourglass"]

struct Slot: Codable, Identifiable, Equatable {
    var role: String
    var asset: String = ""
    var preview: String = ""
    var filename: String = ""
    var size: Double = 32
    var hotspot: [Double]? = nil
    var id: String { role }
}
struct Profile: Codable, Identifiable {
    var id = UUID().uuidString
    var name: String
    var slots: [Slot] = roles.map { Slot(role: $0) }
    var whiteOutline: Bool? = nil
}
struct Library: Codable {
    var profiles: [Profile] = []
    var selected: String = ""
    var backupsByTheme: [String: String] = [:]
    var undoProfiles: [String: Profile] = [:]
    var appliedProfiles: [String: Profile] = [:]
    var english = false
    enum CodingKeys: String, CodingKey { case profiles, selected, backupsByTheme, undoProfiles, appliedProfiles, english }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        profiles = try c.decode([Profile].self, forKey: .profiles)
        selected = try c.decodeIfPresent(String.self, forKey: .selected) ?? ""
        backupsByTheme = try c.decodeIfPresent([String: String].self, forKey: .backupsByTheme) ?? [:]
        undoProfiles = try c.decodeIfPresent([String: Profile].self, forKey: .undoProfiles) ?? [:]
        appliedProfiles = try c.decodeIfPresent([String: Profile].self, forKey: .appliedProfiles) ?? [:]
        english = try c.decodeIfPresent(Bool.self, forKey: .english) ?? false
    }
}
struct PreviewInfo: Decodable {
    var aligned_canvas_px: [Double]
    var hotspot_points: [Double]
    var playback_frames: [Int]
    var frame_duration_seconds: Double
}
struct PreviewAsset {
    var info: PreviewInfo
    var frames: [CGImage]
}
final class PreviewOutlineCache {
    private let frames = NSCache<NSString, CGImage>()

    init() {
        frames.totalCostLimit = 48 * 1024 * 1024
    }

    func image(_ original: CGImage, source: String, frame: Int, width: Int, height: Int, density: Int) -> CGImage? {
        let key = "\(source)/\(density)-\(width)x\(height)-\(frame)" as NSString
        if let cached = frames.object(forKey: key) { return cached }
        guard let outlined = CursorOutline(density: density).render(original, width: width, height: height) else { return nil }
        frames.setObject(outlined, forKey: key, cost: outlined.bytesPerRow * outlined.height)
        return outlined
    }
}
struct AppFailure: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

func runProcess(_ executable: URL, _ arguments: [String]) async throws -> String {
    try await Task.detached {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: output, as: UTF8.self)
        guard process.terminationStatus == 0 else { throw AppFailure(message: text.isEmpty ? "Process failed" : text) }
        return text
    }.value
}

@MainActor final class Studio: ObservableObject {
    @Published var library = Library()
    @Published var role = "arrow"
    @Published var busy = false
    @Published var status: String?
    @Published var error: String?
    // Only a successful apply in this running session establishes this snapshot.
    @Published var activeApplication: Profile?
    var isApplied: Bool {
        guard let current = profile, let applied = activeApplication else { return false }
        return current.id == applied.id && current.slots == applied.slots
            && (current.whiteOutline == true) == (applied.whiteOutline == true)
    }
    var canApply: Bool { !busy && !isApplied && (profile?.slots.contains { !$0.asset.isEmpty } ?? false) }
    @Published var ready = false
    @Published var cache: [String: PreviewAsset] = [:]
    let outlineCache = PreviewOutlineCache()
    let root: URL
    let resources = Bundle.main.resourceURL!
    var profile: Profile? { library.profiles.first { $0.id == library.selected } }
    var slot: Slot? { profile?.slots.first { $0.role == role } }
    var converter: URL { resources.appendingPathComponent("anicore") }
    var translations: [String: String] {
        let path = resources.appendingPathComponent(library.english ? "en.json" : "zh-Hant.json")
        return (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: path))) ?? [:]
    }
    func t(_ key: String) -> String { translations[key] ?? key }
    func toggleLanguage() { library.english.toggle(); save() }
    func refresh() {
        let result = MeowRefreshCursor()
        if result != 0 { status = "refreshWarning" }
    }
    var tool: URL { resources.appendingPathComponent("cursorctl") }

    init() {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--data-dir"), args.count > index + 1 {
            root = URL(fileURLWithPath: args[index + 1], isDirectory: true)
        } else {
            root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("AniOnMac", isDirectory: true)
        }
        Task { await load() }
    }
    func persist() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(library).write(to: root.appendingPathComponent("library.json"), options: .atomic)
    }
    func save() {
        do { try persist() } catch { self.error = t("saveFailed") + "\n" + error.localizedDescription }
    }
    func load() async {
        busy = true
        defer { busy = false }
        do {
            // Migrate only on this Mac, never package user data in the app.
            if !FileManager.default.fileExists(atPath: root.path), !CommandLine.arguments.contains("--data-dir") {
                let candidates = ["CursorShift", "MeowCursor"].map { root.deletingLastPathComponent().appendingPathComponent($0) }
                if let old = candidates.first(where: { FileManager.default.fileExists(atPath: $0.appendingPathComponent("library.json").path) }) {
                    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                    let oldLibrary = try JSONDecoder().decode(Library.self, from: Data(contentsOf: old.appendingPathComponent("library.json")))
                    for relative in Set(oldLibrary.backupsByTheme.values) {
                        let source = old.appendingPathComponent(relative).standardizedFileURL
                        guard source.path.hasPrefix(old.standardizedFileURL.path + "/"), FileManager.default.fileExists(atPath: source.path) else { continue }
                        let destination = root.appendingPathComponent(relative)
                        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try FileManager.default.copyItem(at: source, to: destination)
                    }
                    for name in ["assets", "previews", "library.json"] {
                        let source = old.appendingPathComponent(name)
                        if FileManager.default.fileExists(atPath: source.path) { try FileManager.default.copyItem(at: source, to: root.appendingPathComponent(name)) }
                    }
                }
            }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let file = root.appendingPathComponent("library.json")
            if FileManager.default.fileExists(atPath: file.path) {
                library = try JSONDecoder().decode(Library.self, from: Data(contentsOf: file))
                guard !library.profiles.isEmpty, library.profiles.allSatisfy({ Set($0.slots.map(\.role)) == Set(roles) && $0.slots.count == 4 }) else {
                    throw AppFailure(message: t("invalidLibrary"))
                }
                if profile == nil { library.selected = library.profiles[0].id }
                for p in library.profiles {
                    for s in p.slots where !s.preview.isEmpty {
                        do { try loadPreview(s) }
                        catch { self.error = t("previewFailed") + "\n" + error.localizedDescription }
                    }
                }
            } else {
                let initial = Profile(name: t("newTheme"))
                library.profiles = [initial]
                library.selected = initial.id
                try persist()
            }
            ready = true
            status = nil
        } catch { self.error = error.localizedDescription; status = "loadFailed" }
    }
    func loadPreview(_ slot: Slot) throws {
        let dir = root.appendingPathComponent(slot.preview)
        let info = try JSONDecoder().decode(PreviewInfo.self, from: Data(contentsOf: dir.appendingPathComponent("preview.json")))
        let count = (info.playback_frames.max() ?? 0) + 1
        var frames: [CGImage] = []
        for n in 0..<count {
            let url = dir.appendingPathComponent(String(format: "frame-%03d.png", n))
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw AppFailure(message: t("missingPreview") + " " + slot.filename)
            }
            frames.append(image)
        }
        cache[slot.preview] = PreviewAsset(info: info, frames: frames)
    }
    func imported(_ url: URL, role: String, size: Double) async throws -> Slot {
        guard url.pathExtension.lowercased() == "ani" else { throw AppFailure(message: t("chooseANI")) }
        let id = UUID().uuidString
        let asset = "assets/\(id).ani"
        let preview = "previews/\(id)"
        try FileManager.default.createDirectory(at: root.appendingPathComponent("assets"), withIntermediateDirectories: true)
        let copied = root.appendingPathComponent(asset)
        try FileManager.default.copyItem(at: url, to: copied)
        do {
            let output = try await runProcess(converter, ["preview", copied.path, root.appendingPathComponent(preview).path])
            let data = Data(output.utf8)
            _ = try JSONDecoder().decode(PreviewInfo.self, from: data)
            try data.write(to: root.appendingPathComponent(preview).appendingPathComponent("preview.json"), options: .atomic)
            let result = Slot(role: role, asset: asset, preview: preview, filename: url.lastPathComponent, size: size)
            try loadPreview(result)
            return result
        } catch {
            try? FileManager.default.removeItem(at: copied)
            try? FileManager.default.removeItem(at: root.appendingPathComponent(preview))
            throw error
        }
    }
    func importFile(_ url: URL) {
        guard !busy, let p = profile, let s = slot else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                let result = try await imported(url, role: s.role, size: s.size)
                guard let pi = library.profiles.firstIndex(where: { $0.id == p.id }), let si = library.profiles[pi].slots.firstIndex(where: { $0.role == s.role }) else { return }
                recordEditUndo(library.profiles[pi])
                library.profiles[pi].slots[si] = result
                try persist()
                status = "imported"
            } catch { self.error = error.localizedDescription }
        }
    }
    func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "ani") ?? .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in if response == .OK, let url = panel.url { Task { @MainActor in self.importFile(url) } } }
    }
    func select(_ id: String) { library.selected = id; save() }
    func rename(_ name: String) {
        guard let i = library.profiles.firstIndex(where: { $0.id == library.selected }) else { return }
        library.profiles[i].name = name; save()
    }
    func size(_ value: Double) {
        guard let pi = library.profiles.firstIndex(where: { $0.id == library.selected }), let si = library.profiles[pi].slots.firstIndex(where: { $0.role == role }) else { return }
        library.profiles[pi].slots[si].size = value.rounded(); save()
    }
    func add(copy: Bool) {
        var p = copy ? (profile ?? Profile(name: t("newTheme"))) : Profile(name: t("newTheme"))
        p.id = UUID().uuidString
        p.name = copy ? p.name + " " + t("copySuffix") : t("newTheme")
        library.profiles.append(p); library.selected = p.id; save()
    }
    func remove() {
        guard library.profiles.count > 1 else { return }
        let removed = library.selected
        if let backup = library.backupsByTheme.removeValue(forKey: removed) { try? FileManager.default.removeItem(at: root.appendingPathComponent(backup)) }
        library.undoProfiles.removeValue(forKey: removed)
        library.appliedProfiles.removeValue(forKey: removed)
        library.profiles.removeAll { $0.id == removed }
        library.selected = library.profiles[0].id; save()
    }
    func setHotspot(_ point: [Double]?) {
        guard let pi = library.profiles.firstIndex(where: { $0.id == library.selected }), let si = library.profiles[pi].slots.firstIndex(where: { $0.role == role }) else { return }
        library.profiles[pi].slots[si].hotspot = point?.map { min(0.999999, max(0, $0)) }
        save()
    }
    func setWhiteOutline(_ enabled: Bool) {
        guard !busy, let index = library.profiles.firstIndex(where: { $0.id == library.selected }) else { return }
        library.profiles[index].whiteOutline = enabled ? true : nil
        save()
    }
    func hotNormalized(_ slot: Slot) -> [Double] {
        if let h = slot.hotspot { return h }
        guard let info = cache[slot.preview]?.info else { return [0, 0] }
        let maximum = info.aligned_canvas_px.max()!
        return zip(info.hotspot_points, info.aligned_canvas_px).map { $0.0 / (128 * $0.1 / maximum) }
    }
    func allSizes() {
        guard let pi = library.profiles.firstIndex(where: { $0.id == library.selected }), let size = slot?.size else { return }
        for i in library.profiles[pi].slots.indices { library.profiles[pi].slots[i].size = size }
        save(); status = "sizesUpdated"
    }
    func recordEditUndo(_ p: Profile) {
        library.undoProfiles[p.id] = p
        if let backup = library.backupsByTheme.removeValue(forKey: p.id) {
            try? FileManager.default.removeItem(at: root.appendingPathComponent(backup))
        }
    }
    func clearSlot() {
        guard let pi = library.profiles.firstIndex(where: { $0.id == library.selected }), let si = library.profiles[pi].slots.firstIndex(where: { $0.role == role }) else { return }
        recordEditUndo(library.profiles[pi])
        library.profiles[pi].slots[si] = Slot(role: role)
        save()
    }
    func performApply(cape: URL, theme: String) async throws {
        let backup = "backups/\(theme).cape"
        try FileManager.default.createDirectory(at: root.appendingPathComponent("backups"), withIntermediateDirectories: true)
        if let p = profile { library.undoProfiles[theme] = library.appliedProfiles[theme] ?? library.undoProfiles[theme] ?? p }
        library.backupsByTheme[theme] = backup
        try persist()
        activeApplication = nil
        _ = try await runProcess(tool, ["apply-replace", cape.path, root.appendingPathComponent(backup).path])
        if let p = profile { library.appliedProfiles[theme] = p; activeApplication = p }
        try persist()
        status = "applied"
        refresh()
    }
    func apply() {
        guard canApply, let p = profile else { return }
        busy = true
        Task {
            let job = root.appendingPathComponent("work/\(UUID().uuidString)")
            defer { busy = false; try? FileManager.default.removeItem(at: job) }
            do {
                try FileManager.default.createDirectory(at: job, withIntermediateDirectories: true)
                let slots: [[String: Any]] = p.slots.filter { !$0.asset.isEmpty }.map { slot in
                    var d: [String: Any] = ["role": slot.role, "path": root.appendingPathComponent(slot.asset).path, "size": slot.size]
                    if let hotspot = slot.hotspot { d["hotspot"] = hotspot }
                    return d
                }
                let config: [String: Any] = ["id": p.id, "name": p.name, "whiteOutline": p.whiteOutline == true, "slots": slots]
                let input = job.appendingPathComponent("input.json")
                try JSONSerialization.data(withJSONObject: config).write(to: input)
                _ = try await runProcess(converter, ["export", input.path, job.appendingPathComponent("converted").path])
                try await performApply(cape: job.appendingPathComponent("converted/theme.cape"), theme: p.id)
            } catch { self.error = error.localizedDescription; status = "applyFailed" }
        }
    }
    var lastBackup: String? {
        guard let path = library.backupsByTheme[library.selected], FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path) else { return nil }
        return path
    }
    var canUndo: Bool { lastBackup != nil || library.undoProfiles[library.selected] != nil }
    func restore() {
        guard !busy, canUndo else { return }
        let backup = lastBackup
        let theme = library.selected
        busy = true
        Task {
            defer { busy = false }
            do {
                if let backup { activeApplication = nil; _ = try await runProcess(tool, ["restore", root.appendingPathComponent(backup).path]) }
                if let previous = library.undoProfiles.removeValue(forKey: theme), let index = library.profiles.firstIndex(where: { $0.id == theme }) {
                    library.profiles[index] = previous
                    if backup != nil { library.appliedProfiles[theme] = previous }
                }
                library.backupsByTheme.removeValue(forKey: theme); try persist()
                if let backup { try? FileManager.default.removeItem(at: root.appendingPathComponent(backup)) }
                status = "restored"
                if backup != nil { refresh() }
            } catch { self.error = error.localizedDescription }
        }
    }
    func restoreNative() {
        guard !busy else { return }
        busy = true
        Task {
            let job = root.appendingPathComponent("work/\(UUID().uuidString)")
            defer { busy = false; try? FileManager.default.removeItem(at: job) }
            do {
                try FileManager.default.createDirectory(at: job, withIntermediateDirectories: true)
                let cape = job.appendingPathComponent("native.cape")
                _ = try await runProcess(tool, ["defaults-export", cape.path])
                // Native reset is independent of the selected custom theme.
                activeApplication = nil
                _ = try await runProcess(tool, ["apply-replace", cape.path, root.appendingPathComponent("native-reset-recovery.cape").path])
                status = "nativeRestored"; refresh()
            } catch { self.error = error.localizedDescription; status = "applyFailed" }
        }
    }
}
