// 生成 1024×1024 的 App 图标（不透明 PNG）。用法：swift scripts/make-icon.swift <输出路径>
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

/// 四角星：四个尖端之间用靠近中心的控制点连成内凹曲线。
func sparkle(center: CGPoint, radius: CGFloat, pinch: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let tips = (0..<4).map { i -> CGPoint in
        let angle = CGFloat(i) * .pi / 2
        return CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
    }
    path.move(to: tips[0])
    for i in 0..<4 {
        let angle = CGFloat(i) * .pi / 2 + .pi / 4
        let control = CGPoint(x: center.x + cos(angle) * radius * pinch, y: center.y + sin(angle) * radius * pinch)
        path.addQuadCurve(to: tips[(i + 1) % 4], control: control)
    }
    path.closeSubpath()
    return path
}

ctx.setFillColor(CGColor(srgbRed: 0.99, green: 0.97, blue: 0.93, alpha: 1))
ctx.addPath(sparkle(center: CGPoint(x: 492, y: 492), radius: 320, pinch: 0.13))
ctx.fillPath()

ctx.setFillColor(CGColor(srgbRed: 0.94, green: 0.61, blue: 0.35, alpha: 1))
ctx.addPath(sparkle(center: CGPoint(x: 760, y: 770), radius: 92, pinch: 0.15))
ctx.fillPath()

let url = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, ctx.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("write failed") }
