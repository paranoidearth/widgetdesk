#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/apps/macos-host/Resources"
ICONSET="$OUT_DIR/AppIcon.iconset"
ICNS="$OUT_DIR/AppIcon.icns"
TMP_SWIFT="$(mktemp "${TMPDIR:-/tmp}/widgetdesk-icon.XXXXXX.swift")"

cleanup() {
  rm -f "$TMP_SWIFT"
}
trap cleanup EXIT

mkdir -p "$OUT_DIR"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

cat >"$TMP_SWIFT" <<'SWIFT'
import AppKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    rect.fill()

    let shadow = NSShadow()
    shadow.shadowBlurRadius = size * 0.055
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.018)
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.24)
    shadow.set()

    let tileRect = rect.insetBy(dx: size * 0.09, dy: size * 0.09)
    let tilePath = NSBezierPath(roundedRect: tileRect, xRadius: size * 0.18, yRadius: size * 0.18)
    NSGradient(colors: [
        NSColor(calibratedRed: 0.12, green: 0.18, blue: 0.24, alpha: 1),
        NSColor(calibratedRed: 0.06, green: 0.09, blue: 0.12, alpha: 1)
    ])?.draw(in: tilePath, angle: 315)

    NSGraphicsContext.current?.shouldAntialias = true
    NSColor(calibratedRed: 0.53, green: 0.95, blue: 0.86, alpha: 1).setStroke()
    let widgetPath = NSBezierPath(
        roundedRect: tileRect.insetBy(dx: size * 0.16, dy: size * 0.19),
        xRadius: size * 0.06,
        yRadius: size * 0.06
    )
    widgetPath.lineWidth = max(2, size * 0.024)
    widgetPath.stroke()

    NSColor.white.withAlphaComponent(0.92).setFill()
    let dotRadius = max(2, size * 0.018)
    for row in 0..<2 {
        for column in 0..<3 {
            let x = size * 0.39 + CGFloat(column) * size * 0.09
            let y = size * 0.44 + CGFloat(row) * size * 0.075
            NSBezierPath(ovalIn: NSRect(x: x, y: y, width: dotRadius, height: dotRadius)).fill()
        }
    }

    NSColor(calibratedRed: 0.53, green: 0.95, blue: 0.86, alpha: 1).setFill()
    let sparkle = NSBezierPath()
    sparkle.move(to: NSPoint(x: size * 0.68, y: size * 0.75))
    sparkle.line(to: NSPoint(x: size * 0.71, y: size * 0.66))
    sparkle.line(to: NSPoint(x: size * 0.80, y: size * 0.63))
    sparkle.line(to: NSPoint(x: size * 0.71, y: size * 0.60))
    sparkle.line(to: NSPoint(x: size * 0.68, y: size * 0.51))
    sparkle.line(to: NSPoint(x: size * 0.65, y: size * 0.60))
    sparkle.line(to: NSPoint(x: size * 0.56, y: size * 0.63))
    sparkle.line(to: NSPoint(x: size * 0.65, y: size * 0.66))
    sparkle.close()
    sparkle.fill()

    return image
}

func writePNG(size: Int, name: String) throws {
    let image = drawIcon(size: CGFloat(size))
    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "WidgetDeskIcon", code: 1)
    }
    try png.write(to: output.appendingPathComponent(name))
}

let files: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

for file in files {
    try writePNG(size: file.0, name: file.1)
}
SWIFT

swift "$TMP_SWIFT" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$ICNS"

echo "Generated $ICNS"
