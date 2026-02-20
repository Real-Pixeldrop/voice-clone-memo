#!/usr/bin/env python3
"""Generate VoiceCloneMemo app icon as .icns using CoreGraphics via PyObjC."""

import subprocess
import os
import sys
import tempfile

def generate_icon_png(size, output_path):
    """Generate a single PNG icon at the given size."""
    # Use sips + CoreImage via a small swift script
    pass

def main():
    icon_dir = os.path.join(tempfile.gettempdir(), "VoiceCloneMemo.iconset")
    os.makedirs(icon_dir, exist_ok=True)

    # Generate icon using Swift (access to CoreGraphics natively)
    swift_code = r'''
import Cocoa

func drawIcon(size: Int, scale: Int, path: String) {
    let s = CGFloat(size * scale)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()

    let ctx = NSGraphicsContext.current!.cgContext

    // Background: rounded rect with gradient
    let rect = CGRect(x: 0, y: 0, width: s, height: s)
    let cornerRadius = s * 0.22
    let bgPath = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.addPath(bgPath)
    ctx.clip()

    // Gradient: deep purple to blue
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let colors = [
        CGColor(red: 0.35, green: 0.10, blue: 0.85, alpha: 1.0),
        CGColor(red: 0.15, green: 0.45, blue: 0.95, alpha: 1.0)
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])
    }

    // Waveform bars (voice visualization)
    let barCount = 7
    let barWidth = s * 0.055
    let maxBarHeight = s * 0.45
    let centerY = s * 0.52
    let startX = s * 0.22
    let spacing = s * 0.085

    let heights: [CGFloat] = [0.3, 0.55, 0.8, 1.0, 0.75, 0.5, 0.25]

    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))

    for i in 0..<barCount {
        let h = maxBarHeight * heights[i]
        let x = startX + CGFloat(i) * spacing
        let y = centerY - h / 2
        let barRect = CGRect(x: x, y: y, width: barWidth, height: h)
        let barPath = CGPath(roundedRect: barRect, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil)
        ctx.addPath(barPath)
        ctx.fillPath()
    }

    // Microphone icon (right side)
    let micX = s * 0.72
    let micY = s * 0.38
    let micW = s * 0.12
    let micH = s * 0.22

    // Mic body
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
    let micRect = CGRect(x: micX, y: micY, width: micW, height: micH)
    let micPath = CGPath(roundedRect: micRect, cornerWidth: micW / 2, cornerHeight: micW / 2, transform: nil)
    ctx.addPath(micPath)
    ctx.fillPath()

    // Mic arc
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.8))
    ctx.setLineWidth(s * 0.02)
    let arcCenter = CGPoint(x: micX + micW / 2, y: micY)
    let arcRadius = micW * 0.85
    ctx.addArc(center: arcCenter, radius: arcRadius, startAngle: .pi * 0.15, endAngle: .pi * 0.85, clockwise: false)
    ctx.strokePath()

    // Mic stand
    let standX = micX + micW / 2 - s * 0.01
    let standRect = CGRect(x: standX, y: micY - s * 0.08, width: s * 0.02, height: s * 0.08)
    ctx.fill(standRect)

    // Stand base
    let baseRect = CGRect(x: micX + micW / 2 - s * 0.04, y: micY - s * 0.10, width: s * 0.08, height: s * 0.025)
    let basePath = CGPath(roundedRect: baseRect, cornerWidth: s * 0.01, cornerHeight: s * 0.01, transform: nil)
    ctx.addPath(basePath)
    ctx.fillPath()

    image.unlockFocus()

    // Save as PNG
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        return
    }
    try? pngData.write(to: URL(fileURLWithPath: path))
}

let iconsetDir = CommandLine.arguments[1]
let sizes = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]

for (size, scale) in sizes {
    let suffix = scale == 1 ? "" : "@2x"
    let filename = "icon_\(size)x\(size)\(suffix).png"
    let path = "\(iconsetDir)/\(filename)"
    drawIcon(size: size, scale: scale, path: path)
    print("Generated \(filename)")
}
'''

    # Write and run the Swift script
    swift_path = os.path.join(tempfile.gettempdir(), "gen_icon.swift")
    with open(swift_path, "w") as f:
        f.write(swift_code)

    result = subprocess.run(
        ["swift", swift_path, icon_dir],
        capture_output=True, text=True
    )
    print(result.stdout)
    if result.stderr:
        print(result.stderr, file=sys.stderr)

    if result.returncode != 0:
        print("Error generating icon PNGs", file=sys.stderr)
        sys.exit(1)

    # Convert iconset to icns
    output_icns = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "AppIcon.icns")
    subprocess.run(["iconutil", "-c", "icns", icon_dir, "-o", output_icns], check=True)
    print(f"Generated {output_icns}")

if __name__ == "__main__":
    main()
