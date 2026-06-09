import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation
let cs=CGColorSpace(name:CGColorSpace.sRGB)!
let RAW="/Users/tony/test_app/JumpQuest/tools/fetched_char/raw"
let OUT="/tmp/char_built"
try? FileManager.default.removeItem(atPath:OUT)
try? FileManager.default.createDirectory(atPath:OUT,withIntermediateDirectories:true)
func loadCG(_ p:String)->CGImage?{ guard let s=CGImageSourceCreateWithURL(URL(fileURLWithPath:p) as CFURL,nil) else {return nil}; return CGImageSourceCreateImageAtIndex(s,0,nil)}
struct Buf{var w:Int;var h:Int;var p:[UInt8]}   // row0=TOP
func toBuf(_ img:CGImage)->Buf{ let w=img.width,h=img.height; var d=[UInt8](repeating:0,count:w*h*4)
 let ctx=CGContext(data:&d,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
 ctx.draw(img,in:CGRect(x:0,y:0,width:w,height:h)); return Buf(w:w,h:h,p:d) }
@inline(__always) func al(_ b:Buf,_ x:Int,_ y:Int)->Int{ Int(b.p[(y*b.w+x)*4+3]) }
func feet(_ b:Buf)->Int{ for y in stride(from:b.h-1,through:0,by:-1){for x in 0..<b.w{if al(b,x,y)>25{return y}}}; return b.h-1 }
// 전체 불투명 무게중심 (얇은 칼은 픽셀수 적어 무시됨)
func centroid(_ b:Buf)->(Double,Double){ var sx=0,sy=0,c=0; for y in 0..<b.h{for x in 0..<b.w{ if al(b,x,y)>60{sx+=x;sy+=y;c+=1}}}; return c>0 ?(Double(sx)/Double(c),Double(sy)/Double(c)):(Double(b.w)/2,Double(b.h)/2) }
let actions:[(String,Int,String)]=[("stand1",4,"stand"),("walk1",4,"walk"),("jump",1,"jump"),("rope",2,"climb"),("swingT1",3,"attack"),("prone",1,"prone")]
let FW=480,FH=380
let CX=Double(FW)/2, CY=Double(FH)*0.52   // 무게중심 목표
var outBufs:[(String,[UInt8])]=[]
var standFeetFinal = 0
func place(_ img:CGImage,_ isStand:Bool)->[UInt8]{
 let b=toBuf(img); let (cx,cy)=centroid(b)
 let offX=Int((CX-cx).rounded()), offY=Int((CY-cy).rounded())
 if isStand { standFeetFinal=max(standFeetFinal, feet(b)+offY) }   // fromTop in FW×FH
 var out=[UInt8](repeating:0,count:FW*FH*4)
 for y in 0..<b.h{ let oy=y+offY; if oy<0||oy>=FH{continue}
  for x in 0..<b.w{ let ox=x+offX; if ox<0||ox>=FW{continue}
   let si=(y*b.w+x)*4; if b.p[si+3]==0{continue}
   let di=(oy*FW+ox)*4; out[di]=b.p[si];out[di+1]=b.p[si+1];out[di+2]=b.p[si+2];out[di+3]=b.p[si+3] } }
 return out
}
for (raw,cnt,name) in actions{ for f in 0..<cnt{ if let img=loadCG("\(RAW)/\(raw)_\(f).png"){ outBufs.append(("player_\(name)\(f)",place(img,name=="stand"))) } } }
var uminX=FW,umaxX=0,uminY=FH,umaxY=0
for (_,buf) in outBufs{ for y in 0..<FH{for x in 0..<FW{ if buf[(y*FW+x)*4+3]>15{if x<uminX{uminX=x};if x>umaxX{umaxX=x};if y<uminY{uminY=y};if y>umaxY{umaxY=y}}}}}
let cw=umaxX-uminX+1, ch=umaxY-uminY+1
let feetInCrop=standFeetFinal-uminY
let feetFromBottom=ch-1-feetInCrop
let centerXcrop=Int(CX)-uminX
print("crop \(cw)x\(ch)  standFeetFromBottom=\(feetFromBottom)  centerX_preflip=\(centerXcrop)")
print("ANCHORX_FRAC=\(Double(cw-1-centerXcrop)/Double(cw))  FEET_FRAC=\(Double(feetFromBottom)/Double(ch))")
func save(_ buf:[UInt8],_ name:String){
 var crop=[UInt8](repeating:0,count:cw*ch*4)
 for y in 0..<ch{ for x in 0..<cw{ let sx=umaxX-x, sy=uminY+y      // 가로flip
   let si=(sy*FW+sx)*4, di=(y*cw+x)*4
   crop[di]=buf[si];crop[di+1]=buf[si+1];crop[di+2]=buf[si+2];crop[di+3]=buf[si+3] } }
 let prov=CGDataProvider(data:Data(crop) as CFData)!
 let img=CGImage(width:cw,height:ch,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:cw*4,space:cs,bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),provider:prov,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
 let u=URL(fileURLWithPath:"\(OUT)/\(name).png")
 let d=CGImageDestinationCreateWithURL(u as CFURL,UTType.png.identifier as CFString,1,nil)!
 CGImageDestinationAddImage(d,img,nil); CGImageDestinationFinalize(d)
}
for (name,buf) in outBufs{ save(buf,name) }
print("saved \(outBufs.count)")
