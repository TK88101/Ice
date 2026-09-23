// Shared fixtures for the Pixels*Tests split: background/marker colours and
// the bitmap/row-building helpers used across findMarker, count, and
// unusedColours tests.
import Testing
@testable import SafeWidthCore

// MARK: - Test fixtures

let bg = RGBA(10, 10, 10)
let leftColour = RGBA(200, 0, 0)
let rightColour = RGBA(0, 200, 0)

/// Builds a Bitmap from a grid of rows (top row first), each row a list of pixels.
/// All rows must be the same length.
func makeBitmap(_ rows: [[RGBA]], scale: Double = 2) -> Bitmap {
    let height = rows.count
    let width = rows.first?.count ?? 0
    var bytes: [UInt8] = []
    bytes.reserveCapacity(width * height * 4)
    for row in rows {
        precondition(row.count == width, "all rows must have equal width")
        for p in row {
            bytes.append(contentsOf: [p.r, p.g, p.b, p.a])
        }
    }
    return Bitmap(width: width, height: height, scale: scale, bytes: bytes)
}

/// A row of `count` background pixels.
func bgRow(_ count: Int) -> [RGBA] { Array(repeating: bg, count: count) }

/// A run of `count` pixels of `colour`.
func run(_ colour: RGBA, _ count: Int) -> [RGBA] { Array(repeating: colour, count: count) }
