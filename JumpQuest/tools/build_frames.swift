import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation
let dir = "/Users/tony/test_app/JumpQuest/maple_body_pale"
let outDir = "/Users/tony/test_app/JumpQuest/Sources/JumpQuest/sprites"
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
func load(_ i:Int)->CGImage{
    let p=dir+"/"+String(format:"pale-%03d.png",i)
    let s=CGImageSourceCreateWithURL(URL(fileURLWithPath:p) as CFURL,nil)!
    return CGImageSourceCreateImageAtIndex(s,0,nil)!
}
let CW=92, CH=96, footY=4
func mkPNG(_ img:CGImage,_ path:String){
    let u=URL(fileURLWithPath:path)
    let d=CGImageDestinationCreateWithURL(u as CFURL,UTType.png.identifier as CFString,1,nil)!
    CGImageDestinationAddImage(d,img,nil); CGImageDestinationFinalize(d)
}
func flipH(_ img:CGImage)->CGImage{
    let w=img.width,h=img.height
    let c=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:0,space:cs,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.interpolationQuality = .none; c.translateBy(x:CGFloat(w),y:0); c.scaleBy(x:-1,y:1)
    c.draw(img,in:CGRect(x:0,y:0,width:w,height:h)); return c.makeImage()!
}
struct Spec { let name:String; let body:Int; let headDY:Int; let headId:Int
              let arm:Int; let armDX:Int; let armDY:Int
              let hand:Int; let handDX:Int; let handDY:Int }
func S(_ n:String,_ b:Int,_ hdy:Int,head:Int = 23,arm:Int = 0,_ adx:Int = 0,_ ady:Int = 0,hand:Int = 0,_ hdx:Int = 0,_ hdyy:Int = 0)->Spec{
    Spec(name:n,body:b,headDY:hdy,headId:head,arm:arm,armDX:adx,armDY:ady,hand:hand,handDX:hdx,handDY:hdyy)
}
func render(_ s:Spec)->CGContext{
    let ctx=CGContext(data:nil,width:CW,height:CH,bitsPerComponent:8,bytesPerRow:CW*4,space:cs,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .none
    let body=load(s.body); let bw=body.width, bh=body.height
    ctx.draw(body,in:CGRect(x:(CW-bw)/2,y:footY,width:bw,height:bh))
    var armCX=CW/2, armBottomY=footY
    if s.arm>0 { let a=load(s.arm)
        armCX=(CW-a.width)/2+s.armDX; armBottomY=footY+bh-a.height+s.armDY
        ctx.draw(a,in:CGRect(x:armCX,y:armBottomY,width:a.width,height:a.height))
    }
    if s.hand>0 { let h=load(s.hand)
        // 주먹 = 팔 끝(아래) 중심에 배치
        let baseX = s.arm>0 ? armCX + load(s.arm).width/2 - h.width/2 : (CW-h.width)/2
        let baseY = s.arm>0 ? armBottomY : footY
        ctx.draw(h,in:CGRect(x:baseX+s.handDX,y:baseY+s.handDY,width:h.width,height:h.height))
    }
    let head=load(s.headId)
    ctx.draw(head,in:CGRect(x:(CW-head.width)/2,y:footY+bh-s.headDY,width:head.width,height:head.height))
    return ctx
}
// idle: 002/006/010 + 팔 + 주먹(팔 끝)
let idleSpecs=[S("idle0",2,6,arm:1,5,-3,hand:3,0,-1), S("idle1",6,6,arm:5,5,-3,hand:7,0,-1), S("idle2",10,6,arm:9,5,-3,hand:11,0,-1)]
// walk: 185.. + 팔 스윙(001/005/009 순환) + 주먹
let wa=[1,5,9,1,5,9], wh=[3,7,11,3,7,11], wbody=[185,189,191,194,197,200]
var walkSpecs:[Spec]=[]
for k in 0..<6 { walkSpecs.append(S("walk\(k)",wbody[k],6,arm:wa[k],5,-3,hand:wh[k],0,-1)) }
// attack: 준비(041) → 런지 스윙(061). 팔 내장.
let attackSpecs=[S("attack0",41,6),S("attack1",61,6)]
// jump: 도약 자세(016)
let jumpSpecs=[S("jump0",16,8)]
// climb: 036/037, 머리는 뒤통수(013), 더 붙임(headDY 큼)
let climbSpecs=[S("climb0",36,14,head:13),S("climb1",37,14,head:13)]
let all=idleSpecs+walkSpecs+attackSpecs+jumpSpecs+climbSpecs
let names=all.map{$0.name}
var uminX=CW,uminY=CH,umaxX=0,umaxY=0
var ctxs:[(String,CGContext)]=[]
for s in all {
    let ctx=render(s)
    let p=ctx.data!.bindMemory(to:UInt8.self,capacity:CW*CH*4)
    for y in 0..<CH{for x in 0..<CW{ if p[(y*CW+x)*4+3]>8 {
        if x<uminX{uminX=x}; if x>umaxX{umaxX=x}; if y<uminY{uminY=y}; if y>umaxY{umaxY=y} }}}
    ctxs.append((s.name,ctx))
}
let cw=umaxX-uminX+1, ch=umaxY-uminY+1
print("union \(cw)x\(ch)")
var byName:[String:CGImage]=[:]
for (name,ctx) in ctxs {
    let crop=flipH(ctx.makeImage()!.cropping(to:CGRect(x:uminX,y:uminY,width:cw,height:ch))!)
    byName[name]=crop
    mkPNG(crop,"\(outDir)/player_\(name).png")
}
print("saved \(byName.count) frames")
let Sx=4, gap=6
let W=(cw*Sx+gap)*names.count+gap, H=ch*Sx+gap*2
let t=CGContext(data:nil,width:W,height:H,bitsPerComponent:8,bytesPerRow:0,space:cs,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
for yy in 0..<(H/16+1){for xx in 0..<(W/16+1){let on=(xx+yy)%2==0
 t.setFillColor(CGColor(colorSpace:cs,components:on ?[0.82,0.82,0.84,1]:[0.66,0.66,0.69,1])!); t.fill(CGRect(x:xx*16,y:yy*16,width:16,height:16))}}
t.interpolationQuality = .none
for (k,n) in names.enumerated(){ t.draw(byName[n]!,in:CGRect(x:gap+(cw*Sx+gap)*k,y:gap,width:cw*Sx,height:ch*Sx)) }
mkPNG(t.makeImage()!,"/tmp/frames_check.png")
print("check /tmp/frames_check.png  \(cw)x\(ch)")
