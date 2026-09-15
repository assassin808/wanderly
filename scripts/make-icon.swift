// 生成 1024×1024 的 App 图标（不透明 PNG）。用法：swift scripts/make-icon.swift <输出路径>
// 图形：一个绕了点路的对勾，终点是橙色圆点：先记下，绕一圈完善，最后做完。
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

let gradient = CGGradient(colorsSpace: space, colors: [
    CGColor(srgbRed: 0.29, green: 0.55, blue: 0.43, alpha: 1),
    CGColor(srgbRed: 0.17, green: 0.36, blue: 0.27, alpha: 1),
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])

// 之后的坐标以左上角为原点。
ctx.translateBy(x: 0, y: CGFloat(size))
ctx.scaleBy(x: 1, y: -1)

let path = CGMutablePath()
path.move(to: CGPoint(x: 250, y: 560))
path.addLine(to: CGPoint(x: 420, y: 720))
path.addCurve(to: CGPoint(x: 690, y: 360), control1: CGPoint(x: 590, y: 600), control2: CGPoint(x: 500, y: 400))
ctx.addPath(path)
ctx.setStrokeColor(CGColor(srgbRed: 0.99, green: 0.97, blue: 0.93, alpha: 1))
ctx.setLineWidth(92)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.strokePath()

ctx.setFillColor(CGColor(srgbRed: 0.94, green: 0.61, blue: 0.35, alpha: 1))
ctx.fillEllipse(in: CGRect(x: 720, y: 220, width: 124, height: 124))

let url = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, ctx.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("write failed") }
