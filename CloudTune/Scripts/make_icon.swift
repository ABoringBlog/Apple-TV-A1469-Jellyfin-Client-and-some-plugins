import AppKit

let width: CGFloat = 1128
let height: CGFloat = 636
let image = NSImage(size: NSSize(width: width, height: height))
image.lockFocus()

let rect = NSRect(x: 0, y: 0, width: width, height: height)
let bg = NSGradient(colors: [
    NSColor(calibratedRed: 0.025, green: 0.035, blue: 0.09, alpha: 1),
    NSColor(calibratedRed: 0.055, green: 0.07, blue: 0.20, alpha: 1),
    NSColor(calibratedRed: 0.10, green: 0.035, blue: 0.16, alpha: 1)
])!
bg.draw(in: rect, angle: 0)

func rounded(_ r: NSRect, _ radius: CGFloat) -> NSBezierPath {
    return NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
}

let glow = NSShadow()
glow.shadowColor = NSColor(calibratedRed: 0.35, green: 0.45, blue: 1.0, alpha: 0.45)
glow.shadowBlurRadius = 34
glow.shadowOffset = .zero
glow.set()

// Abstract cloud silhouette — original CloudTune mark.
let cloud = NSBezierPath()
cloud.move(to: NSPoint(x: 242, y: 222))
cloud.curve(to: NSPoint(x: 190, y: 346), controlPoint1: NSPoint(x: 174, y: 236), controlPoint2: NSPoint(x: 150, y: 314))
cloud.curve(to: NSPoint(x: 295, y: 419), controlPoint1: NSPoint(x: 212, y: 398), controlPoint2: NSPoint(x: 248, y: 422))
cloud.curve(to: NSPoint(x: 401, y: 492), controlPoint1: NSPoint(x: 315, y: 476), controlPoint2: NSPoint(x: 360, y: 508))
cloud.curve(to: NSPoint(x: 509, y: 428), controlPoint1: NSPoint(x: 456, y: 488), controlPoint2: NSPoint(x: 494, y: 461))
cloud.curve(to: NSPoint(x: 586, y: 382), controlPoint1: NSPoint(x: 542, y: 431), controlPoint2: NSPoint(x: 579, y: 414))
cloud.curve(to: NSPoint(x: 616, y: 300), controlPoint1: NSPoint(x: 614, y: 362), controlPoint2: NSPoint(x: 627, y: 333))
cloud.curve(to: NSPoint(x: 565, y: 223), controlPoint1: NSPoint(x: 603, y: 257), controlPoint2: NSPoint(x: 590, y: 232))
cloud.close()

let cloudGradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.18, green: 0.48, blue: 1.0, alpha: 1),
    NSColor(calibratedRed: 0.50, green: 0.22, blue: 0.95, alpha: 1),
    NSColor(calibratedRed: 1.0, green: 0.24, blue: 0.58, alpha: 1)
])!
cloudGradient.draw(in: cloud, angle: 16)

// Hollow center to make the cloud less like any existing brand.
NSColor(calibratedRed: 0.045, green: 0.045, blue: 0.13, alpha: 0.92).setFill()
let inner = NSBezierPath(ovalIn: NSRect(x: 292, y: 270, width: 230, height: 150))
inner.fill()

// Original musical note.
let noteGlow = NSShadow()
noteGlow.shadowColor = NSColor(calibratedRed: 1.0, green: 0.36, blue: 0.72, alpha: 0.55)
noteGlow.shadowBlurRadius = 22
noteGlow.shadowOffset = .zero
noteGlow.set()

let noteColor = NSColor(calibratedRed: 1.0, green: 0.67, blue: 0.82, alpha: 1)
noteColor.setFill()
rounded(NSRect(x: 392, y: 285, width: 42, height: 152), 19).fill()
let flag = NSBezierPath()
flag.move(to: NSPoint(x: 414, y: 421))
flag.curve(to: NSPoint(x: 502, y: 393), controlPoint1: NSPoint(x: 457, y: 438), controlPoint2: NSPoint(x: 493, y: 429))
flag.curve(to: NSPoint(x: 447, y: 358), controlPoint1: NSPoint(x: 499, y: 369), controlPoint2: NSPoint(x: 474, y: 356))
flag.line(to: NSPoint(x: 421, y: 365))
flag.close()
flag.fill()
NSBezierPath(ovalIn: NSRect(x: 342, y: 248, width: 104, height: 78)).fill()

// Sound bars.
let bars: [(CGFloat,CGFloat)] = [(500,54),(527,86),(554,112),(581,74),(608,42)]
for (x,h) in bars {
    let c = NSColor(calibratedRed: 0.46 + (x-500)/450, green: 0.55, blue: 1.0, alpha: 0.95)
    c.setFill()
    rounded(NSRect(x: x, y: 270, width: 18, height: h), 9).fill()
}

// Small original CT monogram to reinforce independent identity.
let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let attrs: [NSAttributedString.Key:Any] = [
    .font: NSFont.systemFont(ofSize: 64, weight: .semibold),
    .foregroundColor: NSColor(calibratedWhite: 0.97, alpha: 0.96),
    .paragraphStyle: paragraph
]
NSString(string: "CT").draw(in: NSRect(x: 695, y: 323, width: 245, height: 84), withAttributes: attrs)

let subAttrs: [NSAttributedString.Key:Any] = [
    .font: NSFont.systemFont(ofSize: 28, weight: .regular),
    .foregroundColor: NSColor(calibratedWhite: 0.80, alpha: 0.84),
    .paragraphStyle: paragraph
]
NSString(string: "CLOUDTUNE").draw(in: NSRect(x: 680, y: 274, width: 280, height: 48), withAttributes: subAttrs)

image.unlockFocus()
guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("PNG encode failed")
}
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/CloudTuneIcon@1080.png"
try png.write(to: URL(fileURLWithPath: out))
print(out)
