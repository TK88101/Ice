// `«` (pre-registration section 5): (a) from Accessibility, (b) from pixels
// with the template cut from K1 (reading D16 of the instrument plan).
import IceCore

public enum ChevronRule {
    /// (a): any read lists an on-bar `MenuBarAgent` frame of the frozen
    /// chevron width, 17.5 +- 0.5 pt (`DetectorParameters`).
    public static func fromAX(reads: [[AgentFrame]], barHeightPt: Double, parameters: DetectorParameters = .preRegistered) -> Bool {
        reads.contains { read in
            read.contains { frame in
                frame.minY >= 0 && frame.minY < barHeightPt
                    && abs(frame.width - parameters.chevronWidthPt) <= parameters.chevronWidthTolerancePt
            }
        }
    }
}

public enum ChevronTemplate {
    public static let id = "chevron"
    /// Columns added on each side of the AX frame before the cut.
    public static let framePaddingPx = 2
    /// Coverage below this is the backdrop's texture, not the chevron (D16).
    public static let floor = 0.2
    public static let marginPx = 2

    /// D16: coverage from each pixel's lift of its smallest channel over the
    /// cut's median, texture floored to 0, cropped to the ink plus a margin.
    public static func cut(from image: StripImage, framePt: PtSpan) throws(OracleError) -> OracleTemplate {
        let lo = max(0, Int((framePt.lo * image.scale).rounded(.down)) - framePaddingPx)
        let hi = min(image.width, Int((framePt.hi * image.scale).rounded(.up)) + framePaddingPx)
        guard lo < hi else { throw .emptyChevronCut }

        func minChannel(_ x: Int, _ y: Int) -> Int {
            let p = image.pixel(x: x, y: y)
            return Int(min(p.r, p.g, p.b))
        }
        var histogram = [Int](repeating: 0, count: 256)
        for y in 0..<image.height {
            for x in lo..<hi { histogram[minChannel(x, y)] += 1 }
        }
        let m = Oracle.lowerMedian(histogram, count: (hi - lo) * image.height)
        guard m < 255 else { throw .emptyChevronCut }

        var alpha = [[UInt8]](repeating: [UInt8](repeating: 0, count: hi - lo), count: image.height)
        var inked = [(x: Int, y: Int)]()
        for y in 0..<image.height {
            for x in lo..<hi {
                let a = min(1, max(0, Double(minChannel(x, y) - m) / Double(255 - m)))
                guard a >= floor else { continue }
                alpha[y][x - lo] = UInt8((a * 255).rounded())
                inked.append((x - lo, y))
            }
        }
        guard let minX = inked.map(\.x).min(), let maxX = inked.map(\.x).max(),
              let minY = inked.map(\.y).min(), let maxY = inked.map(\.y).max()
        else { throw .emptyChevronCut }

        let width = maxX - minX + 1 + 2 * marginPx
        let height = maxY - minY + 1 + 2 * marginPx
        var cropped = [UInt8](repeating: 0, count: width * height)
        for y in minY...maxY {
            for x in minX...maxX {
                cropped[(y - minY + marginPx) * width + (x - minX + marginPx)] = alpha[y][x]
            }
        }
        return OracleTemplate(id: id, width: width, height: height, alpha: cropped, scale: image.scale)
    }
}
