// JumpQuest 아이콘: 하늘 + 풀밭 위에 귀여운 버섯 몬스터.
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

let W = 1024
let Wf = CGFloat(W)
let cs = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [r, g, b, a])!
}

guard let ctx = CGContext(
    data: nil, width: W, height: W,
    bitsPerComponent: 8, bytesPerRow: 0, space: cs,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("컨텍스트 생성 실패") }

// 둥근 배경에 클립
let margin = Wf * 0.085
let inner = CGRect(x: margin, y: margin, width: Wf - 2*margin, height: Wf - 2*margin)
let corner = inner.width * 0.235
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: inner, cornerWidth: corner, cornerHeight: corner, transform: nil))
ctx.clip()

// 1) 하늘 그라데이션
let sky = CGGradient(colorsSpace: cs,
                     colors: [rgb(0.66, 0.89, 1.0), rgb(0.33, 0.64, 0.96)] as CFArray,
                     locations: [0, 1])!
ctx.drawLinearGradient(sky,
                       start: CGPoint(x: inner.midX, y: inner.maxY),
                       end: CGPoint(x: inner.midX, y: inner.minY),
                       options: [])

// 2) 풀밭
ctx.setFillColor(rgb(0.40, 0.78, 0.42))
ctx.fill(CGRect(x: inner.minX, y: inner.minY, width: inner.width, height: 250))
ctx.setFillColor(rgb(0.33, 0.68, 0.36))
ctx.fill(CGRect(x: inner.minX, y: inner.minY + 226, width: inner.width, height: 26))

let cx = Wf / 2

// 3) 버섯 기둥(다리)
let stemW: CGFloat = 250
let stemBottom: CGFloat = 300
let stemTop: CGFloat = 600
ctx.setFillColor(rgb(0.97, 0.91, 0.80))
ctx.addPath(CGPath(roundedRect: CGRect(x: cx - stemW/2, y: stemBottom, width: stemW, height: stemTop - stemBottom),
                   cornerWidth: 55, cornerHeight: 55, transform: nil))
ctx.fillPath()

// 4) 버섯 갓 (위쪽 반원만 보이게 클립 후 타원)
let capCenterY: CGFloat = 585
let capW: CGFloat = 470
let capH: CGFloat = 300
ctx.saveGState()
ctx.clip(to: CGRect(x: 0, y: capCenterY, width: Wf, height: Wf))
ctx.setFillColor(rgb(0.97, 0.55, 0.18))   // 주황
ctx.fillEllipse(in: CGRect(x: cx - capW/2, y: capCenterY - capH, width: capW, height: capH * 2))
// 갓 위 흰 점
ctx.setFillColor(rgb(1, 1, 1, 0.95))
let spots: [(CGFloat, CGFloat, CGFloat)] = [(-120, 70, 40), (50, 120, 52), (160, 45, 32), (-25, 35, 28)]
for (dx, dy, r) in spots {
    ctx.fillEllipse(in: CGRect(x: cx + dx - r, y: capCenterY + dy - r, width: r*2, height: r*2))
}
ctx.restoreGState()

// 5) 눈
let dark = rgb(0.16, 0.17, 0.19)
let eyeY: CGFloat = 470
ctx.setFillColor(dark)
for ex in [cx - 72, cx + 72] {
    ctx.fillEllipse(in: CGRect(x: ex - 26, y: eyeY - 34, width: 52, height: 68))
}
ctx.setFillColor(rgb(1, 1, 1))
for ex in [cx - 72, cx + 72] {
    ctx.fillEllipse(in: CGRect(x: ex - 2, y: eyeY + 10, width: 18, height: 18))
}

// 6) 입 (작은 미소)
ctx.setStrokeColor(dark)
ctx.setLineWidth(11)
ctx.setLineCap(.round)
ctx.addArc(center: CGPoint(x: cx, y: 430), radius: 42,
           startAngle: .pi * 1.22, endAngle: .pi * 1.78, clockwise: false)
ctx.strokePath()

ctx.restoreGState()

// 저장
guard let img = ctx.makeImage() else { fatalError("이미지 생성 실패") }
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon1024.png"
let url = URL(fileURLWithPath: outPath)
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
else { fatalError("저장 대상 생성 실패") }
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
print("아이콘 저장됨: \(url.path)")
