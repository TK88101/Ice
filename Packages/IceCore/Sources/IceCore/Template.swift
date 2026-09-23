/// Where Accessibility says an item is, in points on the bar's own axes.
///
/// A hint for cutting a template, never evidence of where an item is drawn:
/// for an overflowed item the frame is stacked on its neighbours, and which
/// frame it reports depends on the path the layout took there.
public struct ItemFrame: Equatable, Sendable {
    public let id: String
    public let minX: Double
    public let minY: Double
    public let width: Double
    public let height: Double

    public init(id: String, minX: Double, minY: Double, width: Double, height: Double) {
        self.id = id
        self.minX = minX
        self.minY = minY
        self.width = width
        self.height = height
    }

    public var span: PtSpan { PtSpan(lo: minX, hi: minX + max(0, width)) }

    var isFinite: Bool { minX.isFinite && minY.isFinite && width.isFinite && height.isFinite }
}

/// Why an item has no template. A rejected item is never sighted, so the
/// decision layer reports `notObserved` for it rather than guessing.
public enum Rejection: Equatable, Sendable {
    case nonFiniteFrame
    case outsideStrip
    /// The frame is below the bar: the owning app parked its own item.
    case offBar
    case tooNarrow
    case overlapsAnotherItem
    case overlapsAgentItem
    case noInk
    /// So little ink that an empty slot would match it.
    case tooLittleInk
    /// So little clear background that any ink in the right places would match.
    case tooLittleBackground
    /// The cut matches somewhere other than where it was taken.
    case notUniqueAtBaseline
    /// The fold was up when the baseline was taken, so frames cannot be trusted.
    case foldNotAbsentAtBaseline
    /// The two Accessibility reads of the baseline disagree about this item.
    case readsDisagree
    /// The item appears in one read and not the other.
    case notInEveryRead
    case baselineTooShort
    case capturesDiffer
    case inkUnknown
}

/// One item's glyph, reduced to what decides a match: which pixels are its ink,
/// which are clearly not, and which are neither and therefore ignored.
public struct ItemTemplate: Equatable, Sendable {
    /// Cell classes, one per pixel of the cut.
    enum Cell: UInt8, Equatable, Sendable {
        case edge
        case ink
        case background
    }

    public let id: String
    /// The cut's left edge where it was taken, in points.
    public let originXPt: Double
    /// The cut's top row, in pixels from the top of the strip.
    public let originYPx: Int
    public let widthPx: Int
    public let heightPx: Int
    public let scale: Double
    let cells: [Cell]
    public let inkCount: Int
    public let backgroundCount: Int
    /// Its look changed while the baseline was being taken, so a later failure
    /// to find it proves nothing.
    public let isDynamic: Bool

    init(id: String, originXPt: Double, originYPx: Int, widthPx: Int, heightPx: Int, scale: Double, cells: [Cell], isDynamic: Bool) {
        precondition(cells.count == widthPx * heightPx, "one cell per pixel")
        self.id = id
        self.originXPt = originXPt
        self.originYPx = originYPx
        self.widthPx = widthPx
        self.heightPx = heightPx
        self.scale = scale
        self.cells = cells
        self.inkCount = cells.filter { $0 == .ink }.count
        self.backgroundCount = cells.filter { $0 == .background }.count
        self.isDynamic = isDynamic
    }

    /// Pixels that decide a match: ink and clear background, never edges.
    public var caredCount: Int { inkCount + backgroundCount }

    public var widthPt: Double { Double(widthPx) / scale }

    public var span: PtSpan { PtSpan(lo: originXPt, hi: originXPt + widthPt) }

    /// The same template, marked dynamic.
    func markedDynamic() -> ItemTemplate {
        ItemTemplate(id: id, originXPt: originXPt, originYPx: originYPx, widthPx: widthPx, heightPx: heightPx, scale: scale, cells: cells, isDynamic: true)
    }

    subscript(dx: Int, dy: Int) -> Cell { cells[dy * widthPx + dx] }

    /// What cutting produced: a template, or the reason there is none.
    public struct CutResult: Equatable, Sendable {
        public let template: ItemTemplate?
        public let rejection: Rejection?
    }

    /// Cuts `frame`'s glyph out of `image`.
    ///
    /// The cut is the glyph's ink bounding box plus a margin, not the whole
    /// frame: a frame is mostly backdrop, and a template that is mostly backdrop
    /// matches its own empty slot once the glyph is gone.
    public static func cut(
        _ frame: ItemFrame,
        from image: StripImage,
        ink: Ink,
        geometry: BarGeometry,
        parameters: DetectorParameters
    ) -> CutResult {
        guard frame.isFinite else { return CutResult(template: nil, rejection: .nonFiniteFrame) }
        guard frame.minY >= 0, frame.minY < geometry.heightPt else {
            return CutResult(template: nil, rejection: .offBar)
        }
        guard frame.minX >= 0, frame.minX + frame.width <= geometry.widthPt else {
            return CutResult(template: nil, rejection: .outsideStrip)
        }
        guard frame.width >= parameters.minTemplateWidthPt else {
            return CutResult(template: nil, rejection: .tooNarrow)
        }

        let frameLo = max(0, Int((frame.minX * image.scale).rounded(.down)))
        let frameHi = min(image.width, Int(((frame.minX + frame.width) * image.scale).rounded(.up)))
        guard frameLo < frameHi else { return CutResult(template: nil, rejection: .outsideStrip) }

        guard let box = inkBoundingBox(in: image, ink: ink, columns: frameLo..<frameHi, geometry: geometry) else {
            return CutResult(template: nil, rejection: .noInk)
        }

        let margin = parameters.templateMarginPx
        let x0 = max(frameLo, box.columns.lowerBound - margin)
        let x1 = min(frameHi, box.columns.upperBound + margin)
        let y0 = max(0, box.rows.lowerBound - margin)
        let y1 = min(image.height, box.rows.upperBound + margin)
        guard x0 < x1, y0 < y1 else { return CutResult(template: nil, rejection: .noInk) }

        var cells = [Cell]()
        cells.reserveCapacity((x1 - x0) * (y1 - y0))
        for y in y0..<y1 {
            for x in x0..<x1 {
                let pixel = image.pixel(x: x, y: y)
                if ink.isInk(pixel) {
                    cells.append(.ink)
                } else if ink.isClearlyBackground(pixel) {
                    cells.append(.background)
                } else {
                    cells.append(.edge)
                }
            }
        }

        let template = ItemTemplate(
            id: frame.id,
            originXPt: Double(x0) / image.scale,
            originYPx: y0,
            widthPx: x1 - x0,
            heightPx: y1 - y0,
            scale: image.scale,
            cells: cells,
            isDynamic: false
        )

        let cared = Double(template.caredCount)
        guard Double(template.inkCount) >= parameters.coreInkFactor * parameters.foundThreshold * cared else {
            return CutResult(template: nil, rejection: .tooLittleInk)
        }
        let backgroundFloor = max(Double(template.inkCount), parameters.coreBackgroundFraction * cared)
        guard Double(template.backgroundCount) >= backgroundFloor else {
            return CutResult(template: nil, rejection: .tooLittleBackground)
        }
        return CutResult(template: template, rejection: nil)
    }

    private static func inkBoundingBox(in image: StripImage, ink: Ink, columns: Range<Int>, geometry: BarGeometry) -> (columns: Range<Int>, rows: Range<Int>)? {
        var minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min
        for y in 0..<image.height {
            for x in columns where !geometry.isNotchColumn(x) && ink.isInk(image.pixel(x: x, y: y)) {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return (minX..<(maxX + 1), minY..<(maxY + 1))
    }
}
