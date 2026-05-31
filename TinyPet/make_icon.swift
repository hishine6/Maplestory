// TinyPet 앱 아이콘: 초록 배경 위에 귀여운 알 캐릭터.
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
) else { fatalError("그래픽 컨텍스트 생성 실패") }

// 1) 둥근 사각형 배경 + 초록/민트 그라데이션
let margin = Wf * 0.085
let inner = CGRect(x: margin, y: margin, width: Wf - 2*margin, height: Wf - 2*margin)
let corner = inner.width * 0.235
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: inner, cornerWidth: corner, cornerHeight: corner, transform: nil))
ctx.clip()
let grad = CGGradient(colorsSpace: cs,
                      colors: [rgb(0.22, 0.83, 0.66), rgb(0.10, 0.60, 0.47)] as CFArray,
                      locations: [0, 1])!
ctx.drawLinearGradient(grad,
                       start: CGPoint(x: inner.minX, y: inner.maxY),
                       end: CGPoint(x: inner.maxX, y: inner.minY),
                       options: [])
ctx.restoreGState()

// 2) 흰색 알(타원)
let cx = Wf/2
let cy = Wf/2 - Wf*0.01
let eggW = Wf*0.40
let eggH = Wf*0.50
ctx.setFillColor(rgb(1, 1, 1))
ctx.fillEllipse(in: CGRect(x: cx - eggW/2, y: cy - eggH/2, width: eggW, height: eggH))

// 3) 볼터치 (분홍, 반투명)
ctx.setFillColor(rgb(1.0, 0.55, 0.6, 0.55))
let cheekR = eggW*0.085
let cheekY = cy - eggH*0.02
ctx.fillEllipse(in: CGRect(x: cx - eggW*0.26 - cheekR, y: cheekY - cheekR, width: cheekR*2, height: cheekR*2))
ctx.fillEllipse(in: CGRect(x: cx + eggW*0.26 - cheekR, y: cheekY - cheekR, width: cheekR*2, height: cheekR*2))

// 4) 눈 두 개 (검정)
let dark = rgb(0.16, 0.18, 0.20)
ctx.setFillColor(dark)
let eyeR = eggW*0.055
let eyeY = cy + eggH*0.07
ctx.fillEllipse(in: CGRect(x: cx - eggW*0.16 - eyeR, y: eyeY - eyeR, width: eyeR*2, height: eyeR*2))
ctx.fillEllipse(in: CGRect(x: cx + eggW*0.16 - eyeR, y: eyeY - eyeR, width: eyeR*2, height: eyeR*2))

// 5) 웃는 입 (아래로 볼록한 호)
ctx.setStrokeColor(dark)
ctx.setLineWidth(Wf*0.016)
ctx.setLineCap(.round)
ctx.addArc(center: CGPoint(x: cx, y: cy + eggH*0.02),
           radius: eggW*0.18,
           startAngle: .pi * 1.18,
           endAngle: .pi * 1.82,
           clockwise: false)
ctx.strokePath()

// 6) PNG로 저장
guard let img = ctx.makeImage() else { fatalError("이미지 생성 실패") }
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon1024.png"
let url = URL(fileURLWithPath: outPath)
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
else { fatalError("저장 대상 생성 실패") }
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
print("아이콘 저장됨: \(url.path)")
