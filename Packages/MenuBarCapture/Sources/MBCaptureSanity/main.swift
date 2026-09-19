// Read-only sanity check: one capture of the real bar, one Accessibility
// read of MenuBarAgent's own extras, printed, then exit. Launches nothing,
// moves nothing, writes no Accessibility attribute, adds no menu bar item.
import AppKit
import IceCore
import MenuBarCapture

guard let screen = NSScreen.main else {
    print("no main screen")
    exit(1)
}
guard let geometry = BarGeometry(screen: screen) else {
    print("could not derive bar geometry from NSScreen.main (no safe-area top inset?)")
    exit(1)
}
print("geometry: widthPt=\(geometry.widthPt) heightPt=\(geometry.heightPt) scale=\(geometry.scale) notch=\(String(describing: geometry.notch))")

let capturer = CGWindowListStripCapturer()
if let strip = capturer.capture() {
    let nonZero = strip.bytes.contains { $0 != 0 }
    print("capture: \(strip.width)x\(strip.height) px, scale \(strip.scale), non-zero bytes: \(nonZero)")
} else {
    print("capture failed (permission not granted, or no display)")
}

let axReader = LiveMenuBarAXReader()
if let snapshot = axReader.read(items: [:]) {
    print("MenuBarAgent frames read: \(snapshot.agentFrames.count)")
    for frame in snapshot.agentFrames.sorted(by: { $0.minX < $1.minX }) {
        print("  x=\(frame.minX) y=\(frame.minY) w=\(frame.width)")
    }
} else {
    print("AX read failed (Accessibility not trusted, or MenuBarAgent not found)")
}
