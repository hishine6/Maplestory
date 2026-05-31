// 앱 아이콘(1024x1024 PNG)을 코드로 그려요.
// AppKit/화면 없이 CoreGraphics만 써서, 어떤 환경에서도 동작해요.
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

let W = 1024
let Wf = CGFloat(W)
let cs = CGColorSpace(name: CGColorSpace.sRGB)!

// 색을 만드는 작은 도우미 (R,G,B,A는 0~1)
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [r, g, b, a])!
}

guard let ctx = CGContext(
    data: nil, width: W, height: W,
    bitsPerComponent: 8, bytesPerRow: 0, space: cs,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("그래픽 컨텍스트 생성 실패") }

// 1) 둥근 사각형 배경 + 보라색 그라데이션
let margin = Wf * 0.085
let inner = CGRect(x: margin, y: margin, width: Wf - 2*margin, height: Wf - 2*margin)
let corner = inner.width * 0.235
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: inner, cornerWidth: corner, cornerHeight: corner, transform: nil))
ctx.clip()
let grad = CGGradient(colorsSpace: cs,
                      colors: [rgb(0.40, 0.32, 0.95), rgb(0.62, 0.28, 0.86)] as CFArray,
                      locations: [0, 1])!
ctx.drawLinearGradient(grad,
                       start: CGPoint(x: inner.minX, y: inner.maxY),
                       end: CGPoint(x: inner.maxX, y: inner.minY),
                       options: [])
ctx.restoreGState()

// 2) 흰색 스톱워치 그리기
let white = rgb(1, 1, 1)
let cx = Wf/2
let cy = Wf/2 - Wf*0.02
let R  = Wf * 0.30

// 위쪽 버튼(크라운)
ctx.setFillColor(white)
let cw = Wf*0.085, ch = Wf*0.06
ctx.addPath(CGPath(roundedRect: CGRect(x: cx - cw/2, y: cy + R + Wf*0.015, width: cw, height: ch),
                   cornerWidth: cw*0.3, cornerHeight: cw*0.3, transform: nil))
ctx.fillPath()

// 바깥 원(테두리)
ctx.setStrokeColor(white)
ctx.setLineWidth(Wf * 0.040)
ctx.addArc(center: CGPoint(x: cx, y: cy), radius: R, startAngle: 0, endAngle: .pi*2, clockwise: false)
ctx.strokePath()

// 눈금 12개 (3·6·9·12시는 길게)
ctx.setLineCap(.round)
for i in 0..<12 {
    let a = CGFloat(i) / 12 * .pi * 2
    let outer = R - Wf*0.045
    let len = (i % 3 == 0) ? Wf*0.05 : Wf*0.028
    let p1 = CGPoint(x: cx + cos(a)*outer,         y: cy + sin(a)*outer)
    let p2 = CGPoint(x: cx + cos(a)*(outer - len), y: cy + sin(a)*(outer - len))
    ctx.setLineWidth((i % 3 == 0) ? Wf*0.018 : Wf*0.011)
    ctx.move(to: p1); ctx.addLine(to: p2); ctx.strokePath()
}

// 시계 바늘 두 개
ctx.setLineWidth(Wf*0.024)
ctx.move(to: CGPoint(x: cx, y: cy)); ctx.addLine(to: CGPoint(x: cx, y: cy + R*0.72)); ctx.strokePath()
let ha = CGFloat.pi/2 - (2.0/12.0) * (.pi*2)   // 2시 방향
ctx.setLineWidth(Wf*0.026)
ctx.move(to: CGPoint(x: cx, y: cy))
ctx.addLine(to: CGPoint(x: cx + cos(ha)*R*0.45, y: cy + sin(ha)*R*0.45)); ctx.strokePath()

// 가운데 점
ctx.setFillColor(white)
ctx.addArc(center: CGPoint(x: cx, y: cy), radius: Wf*0.022, startAngle: 0, endAngle: .pi*2, clockwise: false)
ctx.fillPath()

// 3) PNG로 저장
guard let img = ctx.makeImage() else { fatalError("이미지 생성 실패") }
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon1024.png"
let url = URL(fileURLWithPath: outPath)
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
else { fatalError("저장 대상 생성 실패") }
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
print("아이콘 저장됨: \(url.path)")
