import AppKit
import Foundation
// Original icon for RetroReel3; designed independently without third-party marks.
// Run: swift Branding/GenerateIcons.swift
let size=NSSize(width:188, height:108)
func color(_ r:CGFloat,_ g:CGFloat,_ b:CGFloat,_ a:CGFloat=1)->NSColor {
  NSColor(calibratedRed:r/255,green:g/255,blue:b/255,alpha:a)
}
func rounded(_ rect:NSRect,_ radius:CGFloat,_ fill:NSColor) {
  fill.setFill(); NSBezierPath(roundedRect:rect,xRadius:radius,yRadius:radius).fill()
}
func text(_ string:String, _ rect:NSRect, _ size:CGFloat, _ fill:NSColor) {
  let attributes:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:size,weight:.heavy),.foregroundColor:fill]
  NSAttributedString(string:string,attributes:attributes).draw(in:rect)
}
guard let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:188,pixelsHigh:108,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),
      let context=NSGraphicsContext(bitmapImageRep:bitmap) else { fatalError("bitmap") }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current=context
context.shouldAntialias=true
let background=NSBezierPath(roundedRect:NSRect(x:2,y:2,width:184,height:104),xRadius:20,yRadius:20)
NSGradient(starting:color(19,33,54),ending:color(8,13,25))!.draw(in:background,angle:90)
// Film strip, reel and typography. No triangle/nested triangle shapes.
rounded(NSRect(x:13,y:20,width:59,height:68),13,color(244,130,79))
rounded(NSRect(x:20,y:28,width:45,height:52),9,color(26,39,58))
for j in 0..<3 {
  let ypos=CGFloat(34+j*18)
  rounded(NSRect(x:17,y:ypos,width:5,height:8),2,color(255,221,192))
  rounded(NSRect(x:63,y:ypos,width:5,height:8),2,color(255,221,192))
}
color(255,221,192).setFill()
NSBezierPath(ovalIn:NSRect(x:29,y:41,width:26,height:26)).fill()
color(26,39,58).setFill()
NSBezierPath(ovalIn:NSRect(x:37,y:49,width:10,height:10)).fill()
text("RETRO",NSRect(x:81,y:54,width:102,height:32),23,color(255,244,229))
text("REEL 3",NSRect(x:81,y:25,width:104,height:32),22,color(244,130,79))
rounded(NSRect(x:82,y:19,width:78,height:2),1,color(85,157,169))
context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()
guard let png=bitmap.representation(using:.png,properties:[:]) else { fatalError("png") }
for file in ["AppIcon.png","TopRowIcon.png"] {
  let url=URL(fileURLWithPath:"Jellyfin.frappliance").appendingPathComponent(file)
  try png.write(to:url,options:.atomic)
  print(file,png.count)
}