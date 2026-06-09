// bamtistory 아이콘: 웃는 군밤(군고구마 아님!).
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon1024.png"
let W = 1024
let Wf = CGFloat(W)
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
func rgb(_ r: CGFloat,_ g: CGFloat,_ b: CGFloat,_ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: cs, components: [r,g,b,a])! }
guard let ctx = CGContext(data: nil, width: W, height: W, bitsPerComponent: 8, bytesPerRow: 0,
                          space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError() }

// 둥근 사각 클립
let margin = Wf*0.085
let inner = CGRect(x: margin, y: margin, width: Wf-2*margin, height: Wf-2*margin)
let corner = inner.width*0.235
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: inner, cornerWidth: corner, cornerHeight: corner, transform: nil))
ctx.clip()

// 배경: 따뜻한 그라데이션 (크림 → 살구)
let bg = CGGradient(colorsSpace: cs, colors: [rgb(1.0,0.95,0.82), rgb(1.0,0.80,0.55)] as CFArray, locations: [0,1])!
ctx.drawLinearGradient(bg, start: CGPoint(x:0,y:Wf), end: CGPoint(x:0,y:0), options: [])

// 군밤 몸통 path (밑 넓고 위 뾰족한 돔; y는 아래가 0)
let cx: CGFloat = 512
let body = CGMutablePath()
body.move(to: CGPoint(x: cx, y: 300))
body.addQuadCurve(to: CGPoint(x: 345, y: 380), control: CGPoint(x: 392, y: 308))
body.addQuadCurve(to: CGPoint(x: 372, y: 610), control: CGPoint(x: 300, y: 500))
body.addQuadCurve(to: CGPoint(x: cx, y: 720), control: CGPoint(x: 432, y: 702))
body.addQuadCurve(to: CGPoint(x: 652, y: 610), control: CGPoint(x: 592, y: 702))
body.addQuadCurve(to: CGPoint(x: 679, y: 380), control: CGPoint(x: 724, y: 500))
body.addQuadCurve(to: CGPoint(x: cx, y: 300), control: CGPoint(x: 632, y: 308))
body.closeSubpath()

// 그림자
ctx.saveGState()
ctx.addPath(body); ctx.setShadow(offset: CGSize(width:0,height:-14), blur: 34, color: rgb(0.3,0.15,0.05,0.45))
ctx.setFillColor(rgb(0.5,0.3,0.16)); ctx.fillPath()
ctx.restoreGState()

// 몸통 그라데이션 (아래 진한밤 → 위 밝은밤)
ctx.saveGState()
ctx.addPath(body); ctx.clip()
let bodyGrad = CGGradient(colorsSpace: cs, colors: [rgb(0.40,0.22,0.10), rgb(0.70,0.44,0.23)] as CFArray, locations: [0,1])!
ctx.drawLinearGradient(bodyGrad, start: CGPoint(x:0,y:290), end: CGPoint(x:0,y:730), options: [])
// 좌상 하이라이트
let hi = CGGradient(colorsSpace: cs, colors: [rgb(1,0.85,0.6,0.45), rgb(1,0.85,0.6,0)] as CFArray, locations: [0,1])!
ctx.drawRadialGradient(hi, startCenter: CGPoint(x:435,y:600), startRadius: 0, endCenter: CGPoint(x:435,y:600), endRadius: 190, options: [])
ctx.restoreGState()

// 바닥 hilum (껍질 벗긴 밝은 면)
ctx.setFillColor(rgb(0.88,0.76,0.56)); ctx.fillEllipse(in: CGRect(x: cx-118, y: 286, width: 236, height: 82))
ctx.setFillColor(rgb(0.80,0.66,0.46)); ctx.fillEllipse(in: CGRect(x: cx-80, y: 300, width: 160, height: 44))

// 군 칼집(cut) — 위쪽 크림 슬릿 두 줄
ctx.setStrokeColor(rgb(0.97,0.87,0.62)); ctx.setLineWidth(13); ctx.setLineCap(.round)
ctx.move(to: CGPoint(x: 548, y: 686)); ctx.addLine(to: CGPoint(x: 602, y: 612)); ctx.strokePath()
ctx.move(to: CGPoint(x: 470, y: 666)); ctx.addLine(to: CGPoint(x: 505, y: 616)); ctx.strokePath()

// 얼굴
ctx.setFillColor(rgb(1.0,0.55,0.5,0.45))   // 볼터치
ctx.fillEllipse(in: CGRect(x: 392, y: 432, width: 62, height: 40))
ctx.fillEllipse(in: CGRect(x: 570, y: 432, width: 62, height: 40))
for ex in [CGFloat(442), CGFloat(560)] {   // 눈
  ctx.setFillColor(rgb(0.15,0.08,0.04)); ctx.fillEllipse(in: CGRect(x: ex-25, y: 474, width: 50, height: 60))
  ctx.setFillColor(rgb(1,1,1)); ctx.fillEllipse(in: CGRect(x: ex+3, y: 508, width: 17, height: 17))
}
// 웃는 입
ctx.setStrokeColor(rgb(0.15,0.08,0.04)); ctx.setLineWidth(16); ctx.setLineCap(.round)
let mouth = CGMutablePath()
mouth.move(to: CGPoint(x: 468, y: 444)); mouth.addQuadCurve(to: CGPoint(x: 556, y: 444), control: CGPoint(x: 512, y: 404))
ctx.addPath(mouth); ctx.strokePath()

ctx.restoreGState()  // unclip

let img = ctx.makeImage()!
let url = URL(fileURLWithPath: outPath)
let dst = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dst, img, nil); CGImageDestinationFinalize(dst)
print("icon -> \(outPath)")
