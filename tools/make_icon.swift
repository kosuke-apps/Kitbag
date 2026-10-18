#!/usr/bin/env swift
// Draws the Kitbag app icon: a bag with a handle, a flap and a clasp.
//
//   swift tools/make_icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset
//
// Writes icon-light.png, icon-dark.png and icon-tinted.png (1024 x 1024, no transparency, no text) and the matching
// Contents.json. iOS rounds the corners itself.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size: CGFloat = 1024

struct Variant {
  let name: String
  let backgroundTop: CGColor
  let backgroundBottom: CGColor
  let bag: CGColor
  let cutout: CGColor
  let shadow: CGColor
}

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
  CGColor(
    red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255,
    alpha: alpha)
}

let variants = [
  Variant(
    name: "light", backgroundTop: rgb(0x34B3A6), backgroundBottom: rgb(0x155A73), bag: rgb(0xFFFFFF),
    cutout: rgb(0x1B7488), shadow: rgb(0x07283A, 0.35)),
  Variant(
    name: "dark", backgroundTop: rgb(0x10302F), backgroundBottom: rgb(0x07161C), bag: rgb(0x5FD6C8),
    cutout: rgb(0x0B2427), shadow: rgb(0x000000, 0.5)),
  Variant(
    name: "tinted", backgroundTop: rgb(0x000000), backgroundBottom: rgb(0x000000), bag: rgb(0xFFFFFF),
    cutout: rgb(0x000000), shadow: rgb(0x000000, 0.0)),
]

func render(_ v: Variant) -> CGImage {
  let space = CGColorSpaceCreateDeviceRGB()
  let ctx = CGContext(
    data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0, space: space,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
  // Draw from the top left.
  ctx.translateBy(x: 0, y: size)
  ctx.scaleBy(x: 1, y: -1)

  let gradient = CGGradient(colorsSpace: space, colors: [v.backgroundTop, v.backgroundBottom] as CFArray, locations: [0, 1])!
  ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: size), options: [])

  ctx.setShadow(offset: CGSize(width: 0, height: 16), blur: 36, color: v.shadow)

  // The handle: the top of a rounded loop, mostly hidden behind the body.
  ctx.setStrokeColor(v.bag)
  ctx.setLineWidth(58)
  ctx.setLineCap(.round)
  ctx.addPath(CGPath(roundedRect: CGRect(x: 390, y: 205, width: 244, height: 300), cornerWidth: 110, cornerHeight: 110, transform: nil))
  ctx.strokePath()

  // The body.
  ctx.setFillColor(v.bag)
  ctx.addPath(CGPath(roundedRect: CGRect(x: 238, y: 360, width: 548, height: 500), cornerWidth: 130, cornerHeight: 130, transform: nil))
  ctx.fillPath()
  ctx.setShadow(offset: .zero, blur: 0, color: nil)

  // The flap: a curve across the body.
  ctx.setStrokeColor(v.cutout)
  ctx.setLineWidth(40)
  ctx.setLineCap(.round)
  ctx.move(to: CGPoint(x: 288, y: 560))
  ctx.addQuadCurve(to: CGPoint(x: 736, y: 560), control: CGPoint(x: 512, y: 720))
  ctx.strokePath()

  // The clasp.
  ctx.setFillColor(v.cutout)
  ctx.addPath(CGPath(roundedRect: CGRect(x: 462, y: 622, width: 100, height: 96), cornerWidth: 28, cornerHeight: 28, transform: nil))
  ctx.fillPath()

  return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
  let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(destination, image, nil)
  guard CGImageDestinationFinalize(destination) else { fatalError("could not write \(url.path)") }
}

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let output = URL(fileURLWithPath: outputPath, isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for variant in variants {
  writePNG(render(variant), to: output.appendingPathComponent("icon-\(variant.name).png"))
}

let contents = """
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
try contents.write(to: output.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("wrote 3 icons to \(output.path)")
