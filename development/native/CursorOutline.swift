import CoreGraphics
import Foundation

func cursorBitmap(width: Int, height: Int) -> CGContext? {
    let format = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: format)
    context?.interpolationQuality = .high
    return context
}

struct CursorOutline {
    static let widthInPoints = 1
    let padding: Int
    private let samples: [(x: Int, y: Int, weight: Int)]

    init(density: Int) {
        let radius = Self.widthInPoints * density
        padding = radius
        var samples: [(Int, Int, Int)] = []
        for y in -radius...radius {
            for x in -radius...radius where x != 0 || y != 0 {
                let distance = hypot(Double(x), Double(y))
                let coverage = min(1, max(0, Double(radius + 1) - distance))
                let weight = Int((255 * coverage).rounded())
                if weight > 0 { samples.append((x, y, weight)) }
            }
        }
        self.samples = samples
    }

    func render(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        let paddedWidth = width + 2 * padding
        let paddedHeight = height + 2 * padding
        guard let context = cursorBitmap(width: paddedWidth, height: paddedHeight), let data = context.data else { return nil }
        context.draw(image, in: CGRect(x: padding, y: padding, width: width, height: height))

        let pixelCount = paddedWidth * paddedHeight
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        let neighbors = samples.map { (offset: $0.y * paddedWidth + $0.x, weight: $0.weight) }
        var outline = [UInt8](repeating: 0, count: pixelCount)
        for y in padding..<(padding + height) {
            for x in padding..<(padding + width) {
                let index = y * paddedWidth + x
                let alpha = Int(pixels[4 * index + 3])
                guard alpha > 0 else { continue }
                for (offset, weight) in neighbors {
                    let neighbor = index + offset
                    let opacity = UInt8((alpha * weight + 127) / 255)
                    outline[neighbor] = max(outline[neighbor], opacity)
                }
            }
        }

        // Add white only for coverage outside the source alpha. These pixels use premultiplied RGBA.
        for index in 0..<pixelCount {
            let offset = 4 * index
            let alpha = pixels[offset + 3]
            guard outline[index] > alpha else { continue }
            let white = outline[index] - alpha
            pixels[offset] += white
            pixels[offset + 1] += white
            pixels[offset + 2] += white
            pixels[offset + 3] = outline[index]
        }
        return context.makeImage()
    }
}
