#!/usr/bin/env swift
// Draws Kitbag's app icons and their previews for the settings screen.
//
//   swift tools/make_icons.swift App/Resources
//
// For each design it writes <Name>.appiconset (light, dark and tinted, 1024 x 1024, no transparency, no text; iOS
// rounds the corners) to Assets.xcassets, and a 512 px preview to IconPreviews.xcassets. "AppIcon" is the main icon;
// the others are alternates (project.yml lists them in ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES).
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size: CGFloat = 1024

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
  CGColor(
    red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255,
    alpha: alpha)
}

struct Palette {
  let backgroundTop: CGColor
  let backgroundBottom: CGColor
  let ink: CGColor
  let ink2: CGColor
  let accent: CGColor
  let shadow: CGColor
}

/// The grey version that iOS tints: white on black.
let tinted = Palette(
  backgroundTop: rgb(0x000000), backgroundBottom: rgb(0x000000), ink: rgb(0xFFFFFF), ink2: rgb(0xFFFFFF, 0.65),
  accent: rgb(0xFFFFFF, 0.85), shadow: rgb(0x000000, 0))

struct Design {
  let name: String
  let preview: String
  let light: Palette
  let dark: Palette
  let draw: (CGContext, Palette) -> Void
}

// MARK: Drawing helpers

func path(_ points: [CGPoint]) -> CGPath {
  let path = CGMutablePath()
  path.addLines(between: points)
  path.closeSubpath()
  return path
}

func fill(_ ctx: CGContext, _ path: CGPath, _ color: CGColor, shadow: CGColor? = nil, blur: CGFloat = 30, dy: CGFloat = 14) {
  ctx.saveGState()
  if let shadow { ctx.setShadow(offset: CGSize(width: 0, height: dy), blur: blur, color: shadow) }
  ctx.setFillColor(color)
  ctx.addPath(path)
  ctx.fillPath()
  ctx.restoreGState()
}

// MARK: Designs

/// A mortarboard: a diamond board over a cap, with a tassel.
let cap = Design(
  name: "AppIcon", preview: "IconPreviewCap",
  light: Palette(
    backgroundTop: rgb(0x2B4180), backgroundBottom: rgb(0x0E1738), ink: rgb(0xF7F2E6), ink2: rgb(0xCFC7B0),
    accent: rgb(0xE5B958), shadow: rgb(0x050A1E, 0.45)),
  dark: Palette(
    backgroundTop: rgb(0x121A38), backgroundBottom: rgb(0x070B1B), ink: rgb(0xE9E3D2), ink2: rgb(0x9C957F),
    accent: rgb(0xD9AE55), shadow: rgb(0x000000, 0.5)),
  draw: { ctx, p in
    // The cap under the board.
    let base = CGMutablePath()
    base.move(to: CGPoint(x: 296, y: 500))
    base.addLine(to: CGPoint(x: 296, y: 650))
    base.addQuadCurve(to: CGPoint(x: 728, y: 650), control: CGPoint(x: 512, y: 790))
    base.addLine(to: CGPoint(x: 728, y: 500))
    base.closeSubpath()
    fill(ctx, base, p.ink2, shadow: p.shadow)
    // The board.
    let board = path([
      CGPoint(x: 512, y: 236), CGPoint(x: 906, y: 424), CGPoint(x: 512, y: 612), CGPoint(x: 118, y: 424),
    ])
    fill(ctx, board, p.ink, shadow: p.shadow, blur: 40, dy: 18)
    // The tassel: a button, a cord and a fringe.
    ctx.setStrokeColor(p.accent)
    ctx.setLineWidth(16)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: 512, y: 424))
    ctx.addLine(to: CGPoint(x: 800, y: 470))
    ctx.addLine(to: CGPoint(x: 800, y: 640))
    ctx.strokePath()
    fill(ctx, CGPath(ellipseIn: CGRect(x: 484, y: 396, width: 56, height: 56), transform: nil), p.accent)
    fill(ctx, CGPath(roundedRect: CGRect(x: 776, y: 628, width: 48, height: 70), cornerWidth: 12, cornerHeight: 12, transform: nil), p.accent)
    ctx.setLineWidth(8)
    for dx in stride(from: -16, through: 16, by: 8) {
      ctx.move(to: CGPoint(x: 800 + CGFloat(dx), y: 690))
      ctx.addLine(to: CGPoint(x: 800 + CGFloat(dx) * 1.3, y: 750))
    }
    ctx.strokePath()
  })

/// An open book with a few lines of text.
let book = Design(
  name: "IconBook", preview: "IconPreviewBook",
  light: Palette(
    backgroundTop: rgb(0x27948B), backgroundBottom: rgb(0x0F4B5A), ink: rgb(0xF8F4EA), ink2: rgb(0x0F4B5A, 0.35),
    accent: rgb(0xF0C46A), shadow: rgb(0x03232B, 0.45)),
  dark: Palette(
    backgroundTop: rgb(0x0F3A3F), backgroundBottom: rgb(0x071E26), ink: rgb(0xDCEBE6), ink2: rgb(0x071E26, 0.55),
    accent: rgb(0xD9AE55), shadow: rgb(0x000000, 0.5)),
  draw: { ctx, p in
    // The cover shows as a darker edge under the pages.
    let cover = path([
      CGPoint(x: 512, y: 410), CGPoint(x: 196, y: 330), CGPoint(x: 196, y: 760), CGPoint(x: 512, y: 840),
      CGPoint(x: 828, y: 760), CGPoint(x: 828, y: 330),
    ])
    fill(ctx, cover, p.ink2, shadow: p.shadow, blur: 36, dy: 16)
    let left = CGMutablePath()
    left.move(to: CGPoint(x: 512, y: 396))
    left.addQuadCurve(to: CGPoint(x: 232, y: 318), control: CGPoint(x: 360, y: 318))
    left.addLine(to: CGPoint(x: 232, y: 716))
    left.addQuadCurve(to: CGPoint(x: 512, y: 794), control: CGPoint(x: 360, y: 716))
    left.closeSubpath()
    let right = CGMutablePath()
    right.move(to: CGPoint(x: 512, y: 396))
    right.addQuadCurve(to: CGPoint(x: 792, y: 318), control: CGPoint(x: 664, y: 318))
    right.addLine(to: CGPoint(x: 792, y: 716))
    right.addQuadCurve(to: CGPoint(x: 512, y: 794), control: CGPoint(x: 664, y: 716))
    right.closeSubpath()
    fill(ctx, left, p.ink)
    fill(ctx, right, p.ink)
    // Lines of text.
    ctx.setStrokeColor(p.ink2)
    ctx.setLineWidth(18)
    ctx.setLineCap(.round)
    for (i, y) in [430, 500, 570, 640].enumerated() {
      let inset: CGFloat = i == 3 ? 90 : 0
      ctx.move(to: CGPoint(x: 290, y: CGFloat(y)))
      ctx.addLine(to: CGPoint(x: 450 - inset, y: CGFloat(y) + 22))
      ctx.move(to: CGPoint(x: 574, y: CGFloat(y) + 22))
      ctx.addLine(to: CGPoint(x: 734 - inset, y: CGFloat(y)))
    }
    ctx.strokePath()
    // A ribbon.
    fill(ctx, path([CGPoint(x: 600, y: 770), CGPoint(x: 650, y: 770), CGPoint(x: 650, y: 880), CGPoint(x: 625, y: 855), CGPoint(x: 600, y: 880)]), p.accent)
  })

/// A pencil laid across the icon.
let pencil = Design(
  name: "IconPencil", preview: "IconPreviewPencil",
  light: Palette(
    backgroundTop: rgb(0xF5A83D), backgroundBottom: rgb(0xD25A1B), ink: rgb(0xFFF6DC), ink2: rgb(0xE9C58B),
    accent: rgb(0xF06B7A), shadow: rgb(0x5A1E05, 0.4)),
  dark: Palette(
    backgroundTop: rgb(0x5A3A12), backgroundBottom: rgb(0x2B1308), ink: rgb(0xF0DDB0), ink2: rgb(0xC09A5E),
    accent: rgb(0xD8586A), shadow: rgb(0x000000, 0.5)),
  draw: { ctx, p in
    ctx.translateBy(x: 512, y: 512)
    ctx.rotate(by: -.pi / 4)
    ctx.scaleBy(x: 1.14, y: 1.14)
    let w: CGFloat = 150
    // Eraser, ferrule, body, wood and lead, from the top end to the tip.
    fill(ctx, CGPath(roundedRect: CGRect(x: -330, y: -w / 2, width: 80, height: w), cornerWidth: 28, cornerHeight: 28, transform: nil), p.accent, shadow: p.shadow, blur: 30, dy: 12)
    fill(ctx, CGPath(rect: CGRect(x: -250, y: -w / 2, width: 70, height: w), transform: nil), p.ink2)
    fill(ctx, CGPath(rect: CGRect(x: -180, y: -w / 2, width: 330, height: w), transform: nil), p.ink)
    fill(ctx, CGPath(rect: CGRect(x: -180, y: -22, width: 330, height: 44), transform: nil), p.ink2.copy(alpha: 0.45)!)
    fill(ctx, path([CGPoint(x: 150, y: -w / 2), CGPoint(x: 330, y: 0), CGPoint(x: 150, y: w / 2)]), p.ink2)
    fill(ctx, path([CGPoint(x: 262, y: -26), CGPoint(x: 330, y: 0), CGPoint(x: 262, y: 26)]), rgb(0x3A2B22))
  })

/// A serif K, like a monogram on a book cover.
let monogram = Design(
  name: "IconMonogram", preview: "IconPreviewMonogram",
  light: Palette(
    backgroundTop: rgb(0xA23A46), backgroundBottom: rgb(0x4A1420), ink: rgb(0xFAF3E3), ink2: rgb(0xFAF3E3),
    accent: rgb(0xE5B958), shadow: rgb(0x2A0709, 0.45)),
  dark: Palette(
    backgroundTop: rgb(0x3A1219), backgroundBottom: rgb(0x1B070B), ink: rgb(0xEBDDC2), ink2: rgb(0xEBDDC2),
    accent: rgb(0xD9AE55), shadow: rgb(0x000000, 0.5)),
  draw: { ctx, p in
    // A thin frame, as on a cover.
    ctx.setStrokeColor(p.accent.copy(alpha: 0.75)!)
    ctx.setLineWidth(10)
    ctx.addPath(CGPath(roundedRect: CGRect(x: 96, y: 96, width: 832, height: 832), cornerWidth: 70, cornerHeight: 70, transform: nil))
    ctx.strokePath()
    // The letter, centred on its outline.
    let font = CTFontCreateWithName("Georgia-Bold" as CFString, 700, nil)
    var glyph = CTFontGetGlyphWithName(font, "K" as CFString)
    guard let outline = CTFontCreatePathForGlyph(font, glyph, nil) else { return }
    let box = outline.boundingBoxOfPath
    var flip = CGAffineTransform(scaleX: 1, y: -1)
      .concatenating(CGAffineTransform(translationX: 512 - box.midX, y: 512 + box.midY))
    guard let placed = outline.copy(using: &flip) else { return }
    _ = glyph
    glyph = 0
    fill(ctx, placed, p.ink, shadow: p.shadow, blur: 34, dy: 14)
  })

/// The original bag.
let bag = Design(
  name: "IconBag", preview: "IconPreviewBag",
  light: Palette(
    backgroundTop: rgb(0x34B3A6), backgroundBottom: rgb(0x155A73), ink: rgb(0xFFFFFF), ink2: rgb(0x1B7488),
    accent: rgb(0xFFFFFF), shadow: rgb(0x07283A, 0.35)),
  dark: Palette(
    backgroundTop: rgb(0x10302F), backgroundBottom: rgb(0x07161C), ink: rgb(0x5FD6C8), ink2: rgb(0x0B2427),
    accent: rgb(0x5FD6C8), shadow: rgb(0x000000, 0.5)),
  draw: { ctx, p in
    ctx.setStrokeColor(p.ink)
    ctx.setLineWidth(58)
    ctx.setLineCap(.round)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 16), blur: 36, color: p.shadow)
    ctx.addPath(CGPath(roundedRect: CGRect(x: 390, y: 205, width: 244, height: 300), cornerWidth: 110, cornerHeight: 110, transform: nil))
    ctx.strokePath()
    ctx.setFillColor(p.ink)
    ctx.addPath(CGPath(roundedRect: CGRect(x: 238, y: 360, width: 548, height: 500), cornerWidth: 130, cornerHeight: 130, transform: nil))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.setStrokeColor(p.ink2)
    ctx.setLineWidth(40)
    ctx.move(to: CGPoint(x: 288, y: 560))
    ctx.addQuadCurve(to: CGPoint(x: 736, y: 560), control: CGPoint(x: 512, y: 720))
    ctx.strokePath()
    ctx.setFillColor(p.ink2)
    ctx.addPath(CGPath(roundedRect: CGRect(x: 462, y: 622, width: 100, height: 96), cornerWidth: 28, cornerHeight: 28, transform: nil))
    ctx.fillPath()
  })

let designs = [cap, book, pencil, monogram, bag]

// MARK: Rendering and writing

func render(_ design: Design, palette: Palette, pixels: Int) -> CGImage {
  let space = CGColorSpaceCreateDeviceRGB()
  let ctx = CGContext(
    data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
  // Draw from the top left in a 1024-point canvas, whatever the size in pixels.
  let scale = CGFloat(pixels) / size
  ctx.translateBy(x: 0, y: CGFloat(pixels))
  ctx.scaleBy(x: scale, y: -scale)
  let gradient = CGGradient(colorsSpace: space, colors: [palette.backgroundTop, palette.backgroundBottom] as CFArray, locations: [0, 1])!
  ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size), options: [])
  design.draw(ctx, palette)
  return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
  let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(destination, image, nil)
  guard CGImageDestinationFinalize(destination) else { fatalError("could not write \(url.path)") }
}

let rootPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let root = URL(fileURLWithPath: rootPath, isDirectory: true)
let fileManager = FileManager.default
let catalogInfo = #"{ "info" : { "author" : "xcode", "version" : 1 } }"# + "\n"
let iconsCatalog = root.appendingPathComponent("Assets.xcassets")
let previewsCatalog = root.appendingPathComponent("IconPreviews.xcassets")
try fileManager.createDirectory(at: previewsCatalog, withIntermediateDirectories: true)
try catalogInfo.write(to: previewsCatalog.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

let iconContents = """
  {
    "images" : [
      { "filename" : "icon-light.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
      {
        "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ],
        "filename" : "icon-dark.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024"
      },
      {
        "appearances" : [ { "appearance" : "luminosity", "value" : "tinted" } ],
        "filename" : "icon-tinted.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024"
      }
    ],
    "info" : { "author" : "xcode", "version" : 1 }
  }
  """

for design in designs {
  let set = iconsCatalog.appendingPathComponent("\(design.name).appiconset")
  try fileManager.createDirectory(at: set, withIntermediateDirectories: true)
  writePNG(render(design, palette: design.light, pixels: 1024), to: set.appendingPathComponent("icon-light.png"))
  writePNG(render(design, palette: design.dark, pixels: 1024), to: set.appendingPathComponent("icon-dark.png"))
  writePNG(render(design, palette: tinted, pixels: 1024), to: set.appendingPathComponent("icon-tinted.png"))
  try iconContents.write(to: set.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

  let preview = previewsCatalog.appendingPathComponent("\(design.preview).imageset")
  try fileManager.createDirectory(at: preview, withIntermediateDirectories: true)
  writePNG(render(design, palette: design.light, pixels: 512), to: preview.appendingPathComponent("preview.png"))
  let previewContents = #"{ "images" : [ { "filename" : "preview.png", "idiom" : "universal" } ], "info" : { "author" : "xcode", "version" : 1 } }"# + "\n"
  try previewContents.write(to: preview.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}
print("wrote \(designs.count) icons to \(root.path)")
