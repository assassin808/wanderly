// 生成 1024×1024 的 App 图标（不透明 PNG）。用法：swift scripts/make-icon.swift <输出路径>
// 图形：绿色背景上一张折角便签，一支橙色铅笔正写到最后一行。
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

let gradient = CGGradient(colorsSpace: space, colors: [rgb(0x4E9273), rgb(0x2A5B45)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])

// 之后的坐标以左上角为原点。
ctx.translateBy(x: 0, y: CGFloat(size))
ctx.scaleBy(x: 1, y: -1)

func withShadow(blur: CGFloat = 40, offsetY: CGFloat = 16, color: CGColor = rgb(0x0B2A1E, 0.25), _ draw: () -> Void) {
    ctx.saveGState()
    // 阴影偏移用的是设备坐标（y 向上），负值表示向下。
    ctx.setShadow(offset: CGSize(width: 0, height: -offsetY), blur: blur, color: color)
    draw()
    ctx.restoreGState()
}

// 便签：右上角折起。
let card = CGRect(x: 232, y: 196, width: 520, height: 632)
let fold: CGFloat = 150
let radius: CGFloat = 52
let paper = CGMutablePath()
paper.move(to: CGPoint(x: card.minX + radius, y: card.minY))
paper.addLine(to: CGPoint(x: card.maxX - fold, y: card.minY))
paper.addLine(to: CGPoint(x: card.maxX, y: card.minY + fold))
paper.addLine(to: CGPoint(x: card.maxX, y: card.maxY - radius))
paper.addQuadCurve(to: CGPoint(x: card.maxX - radius, y: card.maxY), control: CGPoint(x: card.maxX, y: card.maxY))
paper.addLine(to: CGPoint(x: card.minX + radius, y: card.maxY))
paper.addQuadCurve(to: CGPoint(x: card.minX, y: card.maxY - radius), control: CGPoint(x: card.minX, y: card.maxY))
paper.addLine(to: CGPoint(x: card.minX, y: card.minY + radius))
paper.addQuadCurve(to: CGPoint(x: card.minX + radius, y: card.minY), control: CGPoint(x: card.minX, y: card.minY))
paper.closeSubpath()
withShadow { ctx.addPath(paper); ctx.setFillColor(rgb(0xFFFCF4)); ctx.fillPath() }

let flap = CGMutablePath()
flap.move(to: CGPoint(x: card.maxX - fold, y: card.minY))
flap.addLine(to: CGPoint(x: card.maxX - fold, y: card.minY + fold - 40))
flap.addQuadCurve(to: CGPoint(x: card.maxX - fold + 40, y: card.minY + fold), control: CGPoint(x: card.maxX - fold, y: card.minY + fold))
flap.addLine(to: CGPoint(x: card.maxX, y: card.minY + fold))
flap.closeSubpath()
ctx.addPath(flap)
ctx.setFillColor(rgb(0xE3DCCB))
ctx.fillPath()

// 文字行。
ctx.saveGState()
ctx.setStrokeColor(rgb(0x3C765C, 0.22))
ctx.setLineWidth(20)
ctx.setLineCap(.round)
for (y, width) in zip([310, 410, 500, 590, 680] as [CGFloat], [170, 364, 364, 364, 190] as [CGFloat]) {
    ctx.move(to: CGPoint(x: 310, y: y))
    ctx.addLine(to: CGPoint(x: 310 + width, y: y))
}
ctx.strokePath()
ctx.restoreGState()

// 铅笔：笔尖在最后一行末尾，向右上方延伸。
let tip = CGPoint(x: 520, y: 700)
let length: CGFloat = 440
let w: CGFloat = 92
ctx.saveGState()
ctx.translateBy(x: tip.x, y: tip.y)
ctx.rotate(by: -.pi * 0.28)
let cone = w * 1.15, ferrule = w * 0.55, bodyEnd = length - ferrule - w * 0.62

let silhouette = CGMutablePath()
silhouette.move(to: .zero)
silhouette.addLine(to: CGPoint(x: cone, y: -w / 2))
silhouette.addLine(to: CGPoint(x: length - w * 0.3, y: -w / 2))
silhouette.addQuadCurve(to: CGPoint(x: length - w * 0.3, y: w / 2), control: CGPoint(x: length + w * 0.15, y: 0))
silhouette.addLine(to: CGPoint(x: cone, y: w / 2))
silhouette.closeSubpath()
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x0B2A1E, 0.28))
ctx.addPath(silhouette)
ctx.setFillColor(rgb(0xF29B4B))
ctx.fillPath()
ctx.restoreGState()

let wood = CGMutablePath()
wood.move(to: .zero)
wood.addLine(to: CGPoint(x: cone, y: -w / 2))
wood.addLine(to: CGPoint(x: cone, y: w / 2))
wood.closeSubpath()
ctx.addPath(wood)
ctx.setFillColor(rgb(0xF4D3A5))
ctx.fillPath()

let lead = CGMutablePath()
lead.move(to: .zero)
lead.addLine(to: CGPoint(x: cone * 0.36, y: -w * 0.18))
lead.addLine(to: CGPoint(x: cone * 0.36, y: w * 0.18))
lead.closeSubpath()
ctx.addPath(lead)
ctx.setFillColor(rgb(0x3B3F45))
ctx.fillPath()

ctx.setFillColor(rgb(0xF7B677)); ctx.fill(CGRect(x: cone, y: -w / 2, width: bodyEnd - cone, height: w / 3))
ctx.setFillColor(rgb(0xF29B4B)); ctx.fill(CGRect(x: cone, y: -w / 6, width: bodyEnd - cone, height: w / 3))
ctx.setFillColor(rgb(0xD97F2F)); ctx.fill(CGRect(x: cone, y: w / 6, width: bodyEnd - cone, height: w / 3))

ctx.setFillColor(rgb(0xCBD2DA)); ctx.fill(CGRect(x: bodyEnd, y: -w / 2, width: ferrule, height: w))
ctx.setFillColor(rgb(0xA3ADB8))
ctx.fill(CGRect(x: bodyEnd + ferrule * 0.28, y: -w / 2, width: ferrule * 0.13, height: w))
ctx.fill(CGRect(x: bodyEnd + ferrule * 0.6, y: -w / 2, width: ferrule * 0.13, height: w))

let eraser = CGMutablePath()
eraser.move(to: CGPoint(x: bodyEnd + ferrule, y: -w / 2))
eraser.addLine(to: CGPoint(x: length - w * 0.3, y: -w / 2))
eraser.addQuadCurve(to: CGPoint(x: length - w * 0.3, y: w / 2), control: CGPoint(x: length + w * 0.15, y: 0))
eraser.addLine(to: CGPoint(x: bodyEnd + ferrule, y: w / 2))
eraser.closeSubpath()
ctx.addPath(eraser)
ctx.setFillColor(rgb(0xF2A0A6))
ctx.fillPath()
ctx.restoreGState()

let url = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, ctx.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("write failed") }
