import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

struct ConversionError: LocalizedError {
    let text: String
    var errorDescription: String? { text }
}
func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw ConversionError(text: message) }
}
struct Bytes {
    var data: Data
    func uint(_ offset: Int, _ length: Int = 4) throws -> Int {
        try require(offset >= 0 && offset + length <= data.count, "Truncated ANI data")
        return (0..<length).reduce(0) { $0 | Int(data[offset + $1]) << ($1 * 8) }
    }
    func chunks(_ start: Int, _ end: Int) throws -> [(String, Data)] {
        var result: [(String, Data)] = [], offset = start
        while offset < end {
            try require(offset + 8 <= end, "Truncated RIFF header")
            let size = try uint(offset + 4), next = offset + 8 + size
            try require(next <= end, "RIFF chunk exceeds container")
            result.append((String(decoding: data[offset..<offset + 4], as: UTF8.self), data.subdata(in: offset + 8..<next)))
            offset = next + size % 2
        }
        return result
    }
}
func le(_ value: Int, _ length: Int) -> Data { Data((0..<length).map { UInt8((value >> ($0 * 8)) & 255) }) }
struct ANIFrame { let image: CGImage; let x: Int; let y: Int }
struct ANI {
    let frames: [ANIFrame]
    let sequence: [Int]
    let rates: [Int]
    init(url: URL) throws {
        let b = Bytes(data: try Data(contentsOf: url))
        try require(b.data.count >= 12 && b.data.count <= 64 * 1024 * 1024, "ANI size must be between 12 bytes and 64 MiB")
        try require(String(decoding: b.data.prefix(4), as: UTF8.self) == "RIFF" && String(decoding: b.data[8..<12], as: UTF8.self) == "ACON", "Expected a Windows ANI file")
        try require(try b.uint(4) + 8 == b.data.count, "RIFF size mismatch")
        var fields: [String: Data] = [:], images: [ANIFrame] = []
        for (tag, payload) in try b.chunks(12, b.data.count) {
            if tag == "LIST", String(decoding: payload.prefix(4), as: UTF8.self) == "fram" {
                for (kind, frame) in try Bytes(data: payload).chunks(4, payload.count) where kind == "icon" {
                    try require(images.count < 1024, "Too many ANI frames")
                    images.append(try Self.decodeCUR(frame))
                }
            } else if ["anih", "rate", "seq "].contains(tag) {
                try require(fields[tag] == nil, "Duplicate ANI metadata")
                fields[tag] = payload
            }
        }
        guard let header = fields["anih"], header.count == 36 else { throw ConversionError(text: "Unsupported ANI header") }
        let h = Bytes(data: header), count = try h.uint(4), steps = try h.uint(8), flags = try h.uint(32)
        try require(try h.uint(0) == 36 && flags & 1 == 1 && count == images.count && count > 0 && steps > 0 && steps <= 4096, "Invalid ANI frame count or flags")
        func values(_ field: String, fallback: [Int]) throws -> [Int] {
            guard let raw = fields[field] else { return fallback }
            try require(raw.count == steps * 4, "Invalid ANI sequence or rate count")
            return try (0..<steps).map { try Bytes(data: raw).uint($0 * 4) }
        }
        if flags & 2 != 0 { try require(fields["seq "] != nil, "Missing ANI sequence") }
        let sequence = flags & 2 != 0 ? try values("seq ", fallback: []) : Array(0..<count)
        let rates = try values("rate", fallback: Array(repeating: try h.uint(28), count: steps))
        try require(sequence.count == steps && sequence.allSatisfy { $0 < count }, "Invalid animation sequence")
        try require(rates.allSatisfy { $0 > 0 && $0 <= 36000 }, "Invalid animation timing")
        self.frames = images; self.sequence = sequence; self.rates = rates
    }
    static func decodeCUR(_ data: Data) throws -> ANIFrame {
        let b = Bytes(data: data), count = try b.uint(4, 2)
        try require(try b.uint(0, 2) == 0 && b.uint(2, 2) == 2 && count > 0 && count <= 128 && 6 + 16 * count <= data.count, "Expected CUR frames with hotspots")
        var best: (Int, Int, Int, Int, Data)?
        for i in 0..<count {
            let o = 6 + 16 * i
            let w0 = try b.uint(o, 1), h0 = try b.uint(o + 1, 1)
            let w = w0 == 0 ? 256 : w0, h = h0 == 0 ? 256 : h0
            let x = try b.uint(o + 4, 2), y = try b.uint(o + 6, 2), size = try b.uint(o + 8), start = try b.uint(o + 12)
            try require(start >= 6 + 16 * count && start + size <= data.count && x < w && y < h, "Invalid CUR bounds or hotspot")
            if best == nil || w * h > best!.0 * best!.1 { best = (w, h, x, y, data.subdata(in: start..<start + size)) }
        }
        let (w, h, x, y, pixels) = best!
        var ico = le(0, 2) + le(1, 2) + le(1, 2)
        ico.append(contentsOf: [UInt8(w % 256), UInt8(h % 256), 0, 0])
        ico += le(1, 2) + le(32, 2) + le(pixels.count, 4) + le(22, 4) + pixels
        let encoded = pixels.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) ? pixels : ico
        guard let source = CGImageSourceCreateWithData(encoded as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw ConversionError(text: "macOS could not decode the CUR image") }
        try require(image.width == w && image.height == h, "CUR dimensions disagree")
        return ANIFrame(image: image, x: x, y: y)
    }
}
func canvas(_ w: Int, _ h: Int) throws -> CGContext {
    try require(w > 0 && h > 0 && w * h <= 32 * 1024 * 1024, "Cursor bitmap is too large")
    guard let context = cursorBitmap(width: w, height: h) else { throw ConversionError(text: "Cannot create bitmap") }
    return context
}
func png(_ image: CGImage) throws -> Data {
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { throw ConversionError(text: "Cannot encode PNG") }
    CGImageDestinationAddImage(dest, image, nil)
    try require(CGImageDestinationFinalize(dest), "PNG encoding failed")
    return data as Data
}
func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
let cursorIDs = ["arrow": "com.apple.coregraphics.Arrow", "pointing": "com.apple.cursor.13", "text": "com.apple.coregraphics.IBeam", "wait": "com.apple.coregraphics.Wait"]

func convert(_ source: URL, to output: URL, size: Double, hotspot: [Double]? = nil, whiteOutline: Bool = false) throws -> ([String: Any], [String: Any]) {
    try require(size.isFinite && size >= 8 && size <= 128, "Size must be 8–128 points")
    let ani = try ANI(url: source)
    let left = ani.frames.map(\.x).max()!, top = ani.frames.map(\.y).max()!
    let width = left + ani.frames.map { $0.image.width - $0.x }.max()!
    let height = top + ani.frames.map { $0.image.height - $0.y }.max()!
    let scale = size / Double(max(width, height))
    let points = [Double(width) * scale, Double(height) * scale]
    var hot = [Double(left) * scale, Double(top) * scale]
    if let h = hotspot {
        try require(h.count == 2 && h.allSatisfy { $0.isFinite && $0 >= 0 && $0 < 1 }, "Hotspot must lie inside the image")
        hot = [h[0] * points[0], h[1] * points[1]]
    }
    let tick = ani.rates.reduce(0, gcd)
    let total = ani.rates.reduce(0) { $0 + $1 / tick }
    try require(total <= 25, "This version of AniOnMac accepts at most 25 animation steps; preserving this ANI timing would exceed that limit")
    var playback = zip(ani.sequence, ani.rates).flatMap { Array(repeating: $0.0, count: $0.1 / tick) }
    // 25-step registration fails on the tested WindowServer. Prefer removing
    // an adjacent duplicate; otherwise resample by omitting the last step.
    if playback.count == 25 {
        let repeated = (1..<playback.count).first { playback[$0] == playback[$0 - 1] }
        playback.remove(at: repeated ?? (playback.count - 1))
    }
    let outputSteps = playback.count
    let frameDuration = Double(tick * total) / 60 / Double(outputSteps)
    try require(!FileManager.default.fileExists(atPath: output.path), "Output folder already exists")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    var aligned: [CGImage] = []
    for (index, frame) in ani.frames.enumerated() {
        let context = try canvas(width, height)
        context.draw(frame.image, in: CGRect(x: left - frame.x, y: height - (top - frame.y) - frame.image.height, width: frame.image.width, height: frame.image.height))
        let image = context.makeImage()!
        aligned.append(image)
        try png(image).write(to: output.appendingPathComponent(String(format: "frame-%03d.png", index)))
    }
    var reps: [Data] = []
    for density in [1, 2] {
        let w = max(1, Int((points[0] * Double(density)).rounded())), h = max(1, Int((points[1] * Double(density)).rounded()))
        let renderer = whiteOutline ? CursorOutline(density: density) : nil
        let padding = renderer?.padding ?? 0
        let frameWidth = w + 2 * padding, frameHeight = h + 2 * padding
        let context = try canvas(frameWidth, frameHeight * outputSteps)
        var outlined: [Int: CGImage] = [:]
        if let renderer {
            for index in Set(playback) {
                guard let image = renderer.render(aligned[index], width: w, height: h) else {
                    throw ConversionError(text: "Cannot render cursor outline")
                }
                outlined[index] = image
            }
        }
        for (step, index) in playback.enumerated() {
            let rect = CGRect(x: 0, y: (outputSteps - 1 - step) * frameHeight, width: frameWidth, height: frameHeight)
            context.draw(outlined[index] ?? aligned[index], in: rect)
        }
        reps.append(try png(context.makeImage()!))
    }
    let metadata: [String: Any] = ["aligned_canvas_px": [width, height], "hotspot_points": hot, "playback_frames": playback, "frame_duration_seconds": frameDuration, "source_steps": total]
    let inset = whiteOutline ? Double(CursorOutline.widthInPoints) : 0
    let cursor: [String: Any] = ["PointsWide": points[0] + 2 * inset, "PointsHigh": points[1] + 2 * inset, "HotSpotX": hot[0] + inset, "HotSpotY": hot[1] + inset, "FrameCount": outputSteps, "FrameDuration": frameDuration, "Representations": reps]
    return (metadata, cursor)
}

@main
struct ANIConverter {
    static func main() {
        do {
            let args = CommandLine.arguments
            try require(args.count == 4, "Usage: anicore preview ANI OUTPUT | export CONFIG OUTPUT")
            let input = URL(fileURLWithPath: args[2]), output = URL(fileURLWithPath: args[3])
            var response: [String: Any]
            if args[1] == "preview" {
                response = try convert(input, to: output, size: 128).0
            } else {
                try require(args[1] == "export", "Unknown converter command")
                guard let config = try JSONSerialization.jsonObject(with: Data(contentsOf: input)) as? [String: Any], let slots = config["slots"] as? [[String: Any]] else { throw ConversionError(text: "Invalid theme configuration") }
                try require(!slots.isEmpty && slots.count <= 4, "Select at least one cursor")
                let whiteOutline = config["whiteOutline"] as? Bool ?? false
                var cursors: [String: Any] = [:]
                for slot in slots {
                    guard let role = slot["role"] as? String, let identifier = cursorIDs[role], let path = slot["path"] as? String, let size = slot["size"] as? Double else { throw ConversionError(text: "Invalid cursor configuration") }
                    try require(cursors[identifier] == nil, "Duplicate cursor mode")
                    cursors[identifier] = try convert(URL(fileURLWithPath: path), to: output.appendingPathComponent(role), size: size,
                                                      hotspot: slot["hotspot"] as? [Double], whiteOutline: whiteOutline).1
                }
                let cape: [String: Any] = ["Cursors": cursors, "CapeName": config["name"] as? String ?? "Theme", "Version": 2.0, "MinimumVersion": 2.0]
                let path = output.appendingPathComponent("theme.cape")
                try PropertyListSerialization.data(fromPropertyList: cape, format: .xml, options: 0).write(to: path)
                response = ["cape": path.path]
            }
            print(String(decoding: try JSONSerialization.data(withJSONObject: response, options: .sortedKeys), as: UTF8.self))
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            exit(1)
        }
    }
}
