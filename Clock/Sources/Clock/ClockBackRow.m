#import "ClockBackRow.h"

#import <objc/runtime.h>
#import <objc/message.h>
#include <stdio.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#include <string.h>

static char clockTimerKey;

/* ---------------------------------------------------------
   Generic ABI helpers
   --------------------------------------------------------- */

static BOOL ClockSignature(id target, SEL sel, const char *result, NSArray *args)
{
    if (!target || ![target respondsToSelector:sel])
        return NO;

    NSMethodSignature *s = [target methodSignatureForSelector:sel];

    if (!s ||
        strcmp([s methodReturnType], result) ||
        [s numberOfArguments] != [args count] + 2)
        return NO;

    for (NSUInteger i = 0; i < [args count]; i++) {
        if (strcmp([s getArgumentTypeAtIndex:i + 2],
                   [[args objectAtIndex:i] UTF8String]))
            return NO;
    }

    return YES;
}

static id ClockObject(id target, NSString *name)
{
    SEL sel = NSSelectorFromString(name);

    if (!ClockSignature(target, sel, @encode(id), @[]))
        return nil;

    return ((id(*)(id,SEL))objc_msgSend)(target, sel);
}

static id ClockNew(Class cls)
{
    if (!cls)
        return nil;

    return [[cls alloc] init];
}

static IMP ClockControllerSuper(SEL selector)
{
    Class cls = objc_getClass("ClockController");

    if (!cls)
        return NULL;

    Class base = class_getSuperclass(cls);

    return base ? class_getMethodImplementation(base, selector) : NULL;
}

static IMP ClockApplianceSuper(SEL selector)
{
    Class cls = objc_getClass("ClockAppliance");

    if (!cls)
        return NULL;

    Class base = class_getSuperclass(cls);

    return base ? class_getMethodImplementation(base, selector) : NULL;
}

/* ---------------------------------------------------------
   Clock display
   --------------------------------------------------------- */

static NSString *ClockCurrentTime(void)
{
    NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];

    [formatter setLocale:[NSLocale currentLocale]];
    [formatter setTimeZone:[NSTimeZone localTimeZone]];
    [formatter setDateFormat:@"HH:mm:ss"];

    return [formatter stringFromDate:[NSDate date]];
}

static NSString *ClockCurrentDate(void)
{
    NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];

    [formatter setLocale:[NSLocale currentLocale]];
    [formatter setTimeZone:[NSTimeZone localTimeZone]];
    [formatter setDateFormat:@"EEEE, MMMM d, yyyy"];

    return [formatter stringFromDate:[NSDate date]];
}

static NSData *ClockRenderImage(void)
{
    const size_t width = 1280;
    const size_t height = 720;

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    if (!cs) return nil;

    CGContextRef ctx =
        CGBitmapContextCreate(NULL,
                              width,
                              height,
                              8,
                              width * 4,
                              cs,
                              kCGImageAlphaPremultipliedLast |
                              kCGBitmapByteOrder32Big);

    CGColorSpaceRelease(cs);

    if (!ctx)
        return nil;

    /* Black background */
    CGContextSetRGBFillColor(ctx, 0.0, 0.0, 0.0, 1.0);
    CGContextFillRect(ctx, CGRectMake(0, 0, width, height));

    NSString *time = ClockCurrentTime();
    NSString *date = ClockCurrentDate();

    /*
     * CoreGraphics bitmap context + UIKit is deliberately avoided.
     * CoreText gives us native text rendering without depending on UIKit.
     */

    CGContextSetRGBFillColor(ctx, 1.0, 1.0, 1.0, 1.0);

    CGContextSelectFont(ctx,
                        "HelveticaNeue-UltraLight",
                        150.0,
                        kCGEncodingMacRoman);

    CGContextSetTextDrawingMode(ctx, kCGTextFill);

    const char *timeUTF8 = [time UTF8String];
    size_t timeLength = strlen(timeUTF8);

    CGContextSetTextPosition(ctx, 350.0, 390.0);
    CGContextShowText(ctx, timeUTF8, timeLength);

    CGContextSetRGBFillColor(ctx, 0.72, 0.72, 0.72, 1.0);

    CGContextSelectFont(ctx,
                        "HelveticaNeue",
                        38.0,
                        kCGEncodingMacRoman);

    const char *dateUTF8 = [date UTF8String];
    size_t dateLength = strlen(dateUTF8);

    CGContextSetTextPosition(ctx, 410.0, 300.0);
    CGContextShowText(ctx, dateUTF8, dateLength);

    CGImageRef image = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);

    if (!image)
        return nil;

    NSMutableData *data = [NSMutableData data];

    CGImageDestinationRef dest =
        CGImageDestinationCreateWithData((CFMutableDataRef)data,
                                         CFSTR("public.png"),
                                         1,
                                         NULL);

    if (!dest) {
        CGImageRelease(image);
        return nil;
    }

    CGImageDestinationAddImage(dest, image, NULL);

    BOOL ok = CGImageDestinationFinalize(dest);

    CFRelease(dest);
    CGImageRelease(image);

    return ok ? data : nil;
}

static id ClockCreateImageControl(void)
{
    NSData *data = ClockRenderImage();

    if (![data length])
        return nil;

    Class imageClass = NSClassFromString(@"ATVImage");
    Class controlClass = NSClassFromString(@"BRAsyncImageControl");

    if (!imageClass || !controlClass)
        return nil;

    SEL imageSel = NSSelectorFromString(@"imageWithData:");

    if (!ClockSignature(imageClass,
                        imageSel,
                        @encode(id),
                        @[@"@"]))
        return nil;

    id image =
        ((id(*)(id,SEL,id))objc_msgSend)(imageClass,
                                         imageSel,
                                         data);

    if (!image)
        return nil;

    id control = ClockNew(controlClass);

    if (!control)
        return nil;

    SEL cropSel = NSSelectorFromString(@"setCropAndFill:");

    if (ClockSignature(control,
                       cropSel,
                       @encode(void),
                       @[[NSString stringWithUTF8String:@encode(BOOL)]])) {

        ((void(*)(id,SEL,BOOL))objc_msgSend)(control,
                                             cropSel,
                                             NO);
    }

    SEL setImageSel = NSSelectorFromString(@"setImage:");

    if (!ClockSignature(control,
                        setImageSel,
                        @encode(void),
                        @[@"@"])) {
        [control release];
        return nil;
    }

    ((void(*)(id,SEL,id))objc_msgSend)(control,
                                       setImageSel,
                                       image);

    return [control autorelease];
}


static char ClockImageControlKey;

static id ClockMakeATVImage(void)
{
    NSData *data = ClockRenderImage();

    if (![data length])
        return nil;

    Class imageClass = NSClassFromString(@"ATVImage");

    if (!imageClass)
        return nil;

    SEL sel = NSSelectorFromString(@"imageWithData:");

    if (!ClockSignature(imageClass,
                        sel,
                        @encode(id),
                        @[@"@"]))
        return nil;

    return ((id(*)(id,SEL,id))objc_msgSend)(
        imageClass,
        sel,
        data);
}

static id ClockCreateFullscreenControl(void)
{
    Class controlClass =
        NSClassFromString(@"BRImageControl");

    if (!controlClass)
        return nil;

    id image = ClockMakeATVImage();

    if (!image)
        return nil;

    id control = ClockNew(controlClass);

    if (!control)
        return nil;

    SEL setImageSel =
        NSSelectorFromString(@"setImage:");

    if (!ClockSignature(control,
                        setImageSel,
                        @encode(void),
                        @[@"@"])) {
        [control release];
        return nil;
    }

    ((void(*)(id,SEL,id))objc_msgSend)(
        control,
        setImageSel,
        image);

    /*
     * BRControl is a UIView subclass on the real ATV3,
     * so use UIView's frame API directly.
     */
    SEL frameSel =
        NSSelectorFromString(@"setFrame:");

    if ([control respondsToSelector:frameSel]) {
        CGRect frame =
            CGRectMake(0.0f, 0.0f, 1280.0f, 720.0f);

        ((void(*)(id,SEL,CGRect))objc_msgSend)(
            control,
            frameSel,
            frame);
    }

    return [control autorelease];
}

static void ClockInstallFullscreenControl(id self)
{
    id control =
        objc_getAssociatedObject(
            self,
            &ClockImageControlKey);

    if (control)
        return;

    control = ClockCreateFullscreenControl();

    if (!control)
        return;

    objc_setAssociatedObject(
        self,
        &ClockImageControlKey,
        control,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    SEL addSubviewSel =
        NSSelectorFromString(@"addSubview:");

    if ([self respondsToSelector:addSubviewSel]) {
        ((void(*)(id,SEL,id))objc_msgSend)(
            self,
            addSubviewSel,
            control);
    }
}

static void ClockUpdateFullscreenControl(id self)
{
    ClockInstallFullscreenControl(self);

    id control =
        objc_getAssociatedObject(
            self,
            &ClockImageControlKey);

    if (!control)
        return;

    id image = ClockMakeATVImage();

    if (!image)
        return;

    SEL setImageSel =
        NSSelectorFromString(@"setImage:");

    if ([control respondsToSelector:setImageSel]) {
        ((void(*)(id,SEL,id))objc_msgSend)(
            control,
            setImageSel,
            image);
    }
}


static char ClockTimeTextKey;
static char ClockDateTextKey;

static id ClockObjectCall(id target, NSString *name)
{
    if (!target)
        return nil;

    SEL sel = NSSelectorFromString(name);

    if (![target respondsToSelector:sel])
        return nil;

    return ((id(*)(id,SEL))objc_msgSend)(target, sel);
}

static BOOL ClockSetFrame(id control, CGRect frame)
{
    if (!control)
        return NO;

    SEL sel = NSSelectorFromString(@"setFrame:");

    if (![control respondsToSelector:sel])
        return NO;

    ((void(*)(id,SEL,CGRect))objc_msgSend)(
        control, sel, frame);

    return YES;
}

static BOOL ClockSetText(id control,
                         NSString *text,
                         id attrs)
{
    if (!control || !text)
        return NO;

    SEL sel =
        NSSelectorFromString(@"setText:withAttributes:");

    if (!ClockSignature(control,
                        sel,
                        @encode(void),
                        @[@"@", @"@"]))
        return NO;

    ((void(*)(id,SEL,id,id))objc_msgSend)(
        control,
        sel,
        text,
        attrs ?: @{});

    return YES;
}

static id ClockThemeTextAttributes(void)
{
    Class themeClass =
        NSClassFromString(@"BRThemeInfo");

    if (!themeClass)
        return @{};

    id theme =
        ClockObjectCall(themeClass, @"sharedTheme");

    if (!theme)
        return @{};

    id attrs =
        ClockObjectCall(theme,
                        @"menuTitleTextAttributes");

    static BOOL dumped = NO;

    if (!dumped) {
        dumped = YES;

        NSString *dump =
            [NSString stringWithFormat:
                @"class=%@\nattrs=%@\n",
                attrs ? NSStringFromClass([attrs class]) : @"nil",
                attrs ?: @"nil"];

        [dump writeToFile:@"/var/tmp/clock_text_attrs.txt"
               atomically:YES
                 encoding:NSUTF8StringEncoding
                    error:NULL];
    }

    return attrs ?: @{};
}

static id ClockCreateTextControl(void)
{
    Class cls =
        NSClassFromString(@"BRTextControl");

    if (!cls)
        return nil;

    return [ClockNew(cls) autorelease];
}

static void ClockInstallTextControls(id self)
{
    id timeControl =
        objc_getAssociatedObject(
            self,
            &ClockTimeTextKey);

    if (timeControl)
        return;

    timeControl = ClockCreateTextControl();
    id dateControl = ClockCreateTextControl();

    if (!timeControl || !dateControl)
        return;

    /*
     * First validation layout.
     * Once BRTextControl is confirmed on-device,
     * we'll replace these temporary frames with
     * measured final clock geometry.
     */
    ClockSetFrame(
        timeControl,
        CGRectMake(190.0f,
                   440.0f,
                   900.0f,
                   300.0f));

    ClockSetFrame(
        dateControl,
        CGRectMake(190.0f,
                   375.0f,
                   900.0f,
                   80.0f));

    SEL addSubviewSel =
        NSSelectorFromString(@"addSubview:");

    if (![self respondsToSelector:addSubviewSel])
        return;

    ((void(*)(id,SEL,id))objc_msgSend)(
        self,
        addSubviewSel,
        timeControl);

    ((void(*)(id,SEL,id))objc_msgSend)(
        self,
        addSubviewSel,
        dateControl);

    objc_setAssociatedObject(
        self,
        &ClockTimeTextKey,
        timeControl,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    objc_setAssociatedObject(
        self,
        &ClockDateTextKey,
        dateControl,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void ClockUpdateTextControls(id self)
{
    ClockInstallTextControls(self);

    id timeControl =
        objc_getAssociatedObject(
            self,
            &ClockTimeTextKey);

    id dateControl =
        objc_getAssociatedObject(
            self,
            &ClockDateTextKey);

    if (!timeControl || !dateControl)
        return;

    NSDictionary *baseAttrs =
        ClockThemeTextAttributes();

    NSMutableDictionary *timeAttrs =
        [NSMutableDictionary dictionaryWithDictionary:
            baseAttrs ?: @{}];

    NSMutableDictionary *dateAttrs =
        [NSMutableDictionary dictionaryWithDictionary:
            baseAttrs ?: @{}];

    [timeAttrs setObject:@150
                  forKey:@"BRFontPointSize"];

    [dateAttrs setObject:@39
                  forKey:@"BRFontPointSize"];

    /*
     * Keep the native BackRow alignment value discovered
     * from the real Apple TV theme.
     */
    [timeAttrs setObject:@1
                  forKey:@"BRTextAlignmentKey"];

    [dateAttrs setObject:@1
                  forKey:@"BRTextAlignmentKey"];

    ClockSetText(
        timeControl,
        ClockCurrentTime(),
        timeAttrs);

    ClockSetText(
        dateControl,
        ClockCurrentDate(),
        dateAttrs);

    /*
     * BRTextControl owns part of its BackRow layout.
     * Give it an explicit text-layout area instead of
     * trying to reposition the glyphs with UIView frame.x.
     */
    SEL maxSizeSel =
        NSSelectorFromString(@"setMaxSize:");

    if ([timeControl respondsToSelector:maxSizeSel]) {
        ((void(*)(id,SEL,CGSize))objc_msgSend)(
            timeControl,
            maxSizeSel,
            CGSizeMake(1575.0f, 300.0f));
    }

    if ([dateControl respondsToSelector:maxSizeSel]) {
        ((void(*)(id,SEL,CGSize))objc_msgSend)(
            dateControl,
            maxSizeSel,
            CGSizeMake(1575.0f, 80.0f));
    }

    SEL verticalSel =
        NSSelectorFromString(@"setVerticallyCenterAdjustedText:");

    if ([timeControl respondsToSelector:verticalSel]) {
        ((void(*)(id,SEL,BOOL))objc_msgSend)(
            timeControl,
            verticalSel,
            YES);
    }

    if ([dateControl respondsToSelector:verticalSel]) {
        ((void(*)(id,SEL,BOOL))objc_msgSend)(
            dateControl,
            verticalSel,
            YES);
    }
}

static void ClockRefresh(id self, SEL cmd)
{
    (void)cmd;

    ClockUpdateTextControls(self);

    NSString *time = ClockCurrentTime();
    NSString *date = ClockCurrentDate();

    /*
     * Keep the proven menu controller alive for 0.2.
     * The generated clock image is used through the preview-control path.
     */
    NSString *title =
        [NSString stringWithFormat:@"%@     %@", time, date];

    NSArray *selectors = @[@"setListTitle:", @"setTitle:"];

    for (NSString *name in selectors) {

        SEL sel = NSSelectorFromString(name);

        if (ClockSignature(self, sel, @encode(void), @[@"@"])) {
            ((void(*)(id,SEL,id))objc_msgSend)(self, sel, title);
            break;
        }
    }

    SEL reloadSel = NSSelectorFromString(@"reload");

    SEL listSel = NSSelectorFromString(@"list");

    if (ClockSignature(self, listSel, @encode(id), @[])) {

        id list =
            ((id(*)(id,SEL))objc_msgSend)(self, listSel);

        if (list &&
            ClockSignature(list,
                           reloadSel,
                           @encode(void),
                           @[])) {

            ((void(*)(id,SEL))objc_msgSend)(list,
                                            reloadSel);
        }
    }

    NSLog(@"Clock: refresh %@ %@", time, date);
}

static id ClockPreview(id self, SEL cmd, long item)
{
    (void)self;
    (void)cmd;
    (void)item;

    return ClockCreateImageControl();
}

static void ClockTimerFire(id self, SEL cmd, id timer)
{
    (void)cmd;
    (void)timer;

    ClockRefresh(self, NULL);
}

static void ClockEnsureTimerSelector(void);

/* ---------------------------------------------------------
   Controller lifecycle
   --------------------------------------------------------- */

static id ClockControllerInit(id self, SEL cmd)
{
    IMP superIMP = ClockControllerSuper(cmd);

    if (!superIMP)
        return nil;

    self = ((id(*)(id,SEL))superIMP)(self, cmd);

    if (!self)
        return nil;

    ClockRefresh(self, NULL);

    ClockEnsureTimerSelector();

    NSTimer *timer =
        [NSTimer scheduledTimerWithTimeInterval:1.0
                                        target:self
                                      selector:NSSelectorFromString(@"clockTimerFire:")
                                      userInfo:nil
                                       repeats:YES];

    objc_setAssociatedObject(self,
                             &clockTimerKey,
                             timer,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    NSLog(@"Clock: controller initialized");

    return self;
}

static void ClockActivated(id self, SEL cmd)
{
    IMP superIMP = ClockControllerSuper(cmd);

    if (superIMP)
        ((void(*)(id,SEL))superIMP)(self, cmd);

    ClockRefresh(self, NULL);

    NSLog(@"Clock: activated");
}

static void ClockDeactivated(id self, SEL cmd)
{
    NSLog(@"Clock: deactivated");

    IMP superIMP = ClockControllerSuper(cmd);

    if (superIMP)
        ((void(*)(id,SEL))superIMP)(self, cmd);
}

static void ClockPopped(id self, SEL cmd)
{
    NSTimer *timer =
        (NSTimer *)objc_getAssociatedObject(self, &clockTimerKey);

    if (timer)
        [timer invalidate];

    objc_setAssociatedObject(self,
                             &clockTimerKey,
                             nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    NSLog(@"Clock: popped");

    IMP superIMP = ClockControllerSuper(cmd);

    if (superIMP)
        ((void(*)(id,SEL))superIMP)(self, cmd);
}

static void ClockControllerDealloc(id self, SEL cmd)
{
    NSTimer *timer =
        (NSTimer *)objc_getAssociatedObject(self, &clockTimerKey);

    if (timer)
        [timer invalidate];

    objc_setAssociatedObject(self,
                             &clockTimerKey,
                             nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    IMP superIMP = ClockControllerSuper(cmd);

    if (superIMP)
        ((void(*)(id,SEL))superIMP)(self, cmd);
}

/* Let native BackRow own Menu/navigation. */

static BOOL ClockEvent(id self, SEL cmd, id event)
{
    Class cls = objc_getClass("ClockController");
    Class base = cls ? class_getSuperclass(cls) : Nil;

    Method method =
        base ? class_getInstanceMethod(base, cmd) : NULL;

    if (!method)
        return NO;

    return ((BOOL(*)(id,SEL,id))
            method_getImplementation(method))(self, cmd, event);
}

/* ---------------------------------------------------------
   Appliance information
   --------------------------------------------------------- */

static NSString *ClockMenuIconURL(void)
{
    NSBundle *bundle =
        [NSBundle bundleWithIdentifier:@"org.atv3.clock"];

    NSString *path =
        [bundle pathForResource:@"AppIcon"
                         ofType:@"png"];

    if (![path length])
        path = @"/Applications/Clock.frappliance/AppIcon.png";

    return [[NSURL fileURLWithPath:path] absoluteString];
}

static id ClockInfoMenuIconURLs(id self, SEL cmd)
{
    (void)self;
    (void)cmd;

    static unsigned long callCount = 0;
    callCount++;

    NSString *probeLine =
        [NSString stringWithFormat:
            @"menuIconURLs call=%lu time=%@\n",
            callCount, [NSDate date]];

    NSFileHandle *probe =
        [NSFileHandle fileHandleForWritingAtPath:
            @"/var/tmp/clock_icon_probe.log"];

    if (!probe) {
        [[NSData data] writeToFile:
            @"/var/tmp/clock_icon_probe.log"
            atomically:YES];

        probe =
            [NSFileHandle fileHandleForWritingAtPath:
                @"/var/tmp/clock_icon_probe.log"];
    }

    if (probe) {
        [probe seekToEndOfFile];
        [probe writeData:
            [probeLine dataUsingEncoding:NSUTF8StringEncoding]];
        [probe closeFile];
    }

    NSString *url = ClockMenuIconURL();

    if (![url length])
        return @{};

    return @{
        @"720": url,
        @"1080": url,
        [NSNumber numberWithInteger:720]: url,
        [NSNumber numberWithInteger:1080]: url
    };
}

static id ClockInfoMenuIconURLVersion(id self, SEL cmd)
{
    (void)self;
    (void)cmd;

    static unsigned long callCount = 0;
    callCount++;

    NSString *probeLine =
        [NSString stringWithFormat:
            @"menuIconURLVersion call=%lu time=%@\n",
            callCount, [NSDate date]];

    NSFileHandle *probe =
        [NSFileHandle fileHandleForWritingAtPath:
            @"/var/tmp/clock_icon_probe.log"];

    if (!probe) {
        [[NSData data] writeToFile:
            @"/var/tmp/clock_icon_probe.log"
            atomically:YES];

        probe =
            [NSFileHandle fileHandleForWritingAtPath:
                @"/var/tmp/clock_icon_probe.log"];
    }

    if (probe) {
        [probe seekToEndOfFile];
        [probe writeData:
            [probeLine dataUsingEncoding:NSUTF8StringEncoding]];
        [probe closeFile];
    }

    NSBundle *bundle =
        [NSBundle bundleWithIdentifier:@"org.atv3.clock"];

    id version =
        [bundle objectForInfoDictionaryKey:@"CFBundleVersion"];

    return [version isKindOfClass:[NSString class]] &&
           [version length] ? version : @"1";
}

static Class ClockApplianceInfoClass(void)
{
    Class existing =
        objc_getClass("ClockApplianceInfo");

    if (existing)
        return existing;

    Class base =
        objc_getClass("BRApplianceInfo");

    if (!base)
        return Nil;

    Method urlsMethod =
        class_getInstanceMethod(
            base,
            NSSelectorFromString(@"menuIconURLs"));

    Method versionMethod =
        class_getInstanceMethod(
            base,
            NSSelectorFromString(@"menuIconURLVersion"));

    if (!urlsMethod || !versionMethod)
        return Nil;

    Class cls =
        objc_allocateClassPair(
            base,
            "ClockApplianceInfo",
            0);

    if (!cls)
        return Nil;

    BOOL ok =
        class_addMethod(
            cls,
            NSSelectorFromString(@"menuIconURLs"),
            (IMP)ClockInfoMenuIconURLs,
            method_getTypeEncoding(urlsMethod))
        &&
        class_addMethod(
            cls,
            NSSelectorFromString(@"menuIconURLVersion"),
            (IMP)ClockInfoMenuIconURLVersion,
            method_getTypeEncoding(versionMethod));

    if (!ok) {
        objc_disposeClassPair(cls);
        return Nil;
    }

    objc_registerClassPair(cls);

    return cls;
}

static id ClockSyntheticApplianceInfo(void)
{
    Class infoClass =
        ClockApplianceInfoClass();

    if (!infoClass)
        return nil;

    id info = [infoClass alloc];

    SEL init =
        NSSelectorFromString(@"_initWithMutableDictionary:");

    if (!ClockSignature(info,
                        init,
                        @encode(id),
                        @[@"@"])) {
        [info release];
        return nil;
    }

    NSMutableDictionary *values =
        [NSMutableDictionary dictionary];

    [values setObject:@"clock"
               forKey:@"FRApplianceIdentifier"];

    [values setObject:@"Clock"
               forKey:@"FRApplianceName"];

    [values setObject:@6
               forKey:@"FRAppliancePreferedOrderValue"];

    [values setObject:@"ClockAppliance"
               forKey:@"FRPrincipalClass"];

    [values setObject:@NO
               forKey:@"FRHideIfNoCategories"];

    [values setObject:@[]
               forKey:@"FRApplianceSupportedMediaTypes"];

    [values setObject:@[]
               forKey:@"FRApplianceRequiredRemoteMediaTypes"];

    info =
        ((id(*)(id,SEL,id))objc_msgSend)(
            info,
            init,
            values);

    return [info autorelease];
}

static id ClockApplianceInit(id self,
                             SEL cmd,
                             id incoming)
{
    id info =
        incoming ?: ClockSyntheticApplianceInfo();

    IMP superIMP =
        ClockApplianceSuper(cmd);

    if (!superIMP)
        return nil;

    return ((id(*)(id,SEL,id))superIMP)(
        self,
        cmd,
        info);
}

/* ---------------------------------------------------------
   Categories / controller
   --------------------------------------------------------- */

static BOOL ClockCategoryAvailable(void)
{
    return ClockSignature(
        objc_getClass("BRApplianceCategory"),
        NSSelectorFromString(
            @"categoryWithName:identifier:preferredOrder:"),
        @encode(id),
        @[@"@", @"@", @"f"]);
}

static id ClockCategories(id self, SEL cmd)
{
    (void)self;
    (void)cmd;

    if (!ClockCategoryAvailable()) {
        NSLog(@"Clock: category ABI unavailable");
        return @[];
    }

    Class cls =
        objc_getClass("BRApplianceCategory");

    SEL sel =
        NSSelectorFromString(
            @"categoryWithName:identifier:preferredOrder:");

    NSInvocation *invocation =
        [NSInvocation invocationWithMethodSignature:
            [cls methodSignatureForSelector:sel]];

    [invocation setTarget:cls];
    [invocation setSelector:sel];

    id name = @"Clock";
    id identifier = @"clock";
    float order = 0.0f;

    [invocation setArgument:&name atIndex:2];
    [invocation setArgument:&identifier atIndex:3];
    [invocation setArgument:&order atIndex:4];

    [invocation invoke];

    id result = nil;

    [invocation getReturnValue:&result];

    return result ? @[result] : @[];
}

static id ClockControllerForIdentifier(id self,
                                       SEL cmd,
                                       id identifier,
                                       id args)
{
    (void)self;
    (void)cmd;
    (void)args;

    if (![identifier isEqual:@"clock"])
        return nil;

    return [ClockNew(
        objc_getClass("ClockController"))
        autorelease];
}

static id ClockApplianceController(id self,
                                   SEL cmd)
{
    (void)self;
    (void)cmd;

    return [ClockNew(
        objc_getClass("ClockController"))
        autorelease];
}

/* ---------------------------------------------------------
   Beigelist legacy root bridge
   --------------------------------------------------------- */

static IMP clockOriginalLegacyRootController = NULL;

static BOOL ClockIsLegacyMerchant(id self)
{
    id info =
        ClockObject(self, @"info");

    id merchantID =
        ClockObject(info, @"merchantID");

    if ([merchantID isKindOfClass:[NSString class]] &&
        [merchantID isEqualToString:@"org.atv3.clock"])
        return YES;

    id identifier =
        ClockObject(self, @"identifier");

    if ([identifier isKindOfClass:[NSString class]] &&
        ([identifier isEqualToString:@"org.atv3.clock"] ||
         [identifier isEqualToString:
             @"merchant.org.atv3.clock"]))
        return YES;

    id legacyClass =
        ClockObject(self, @"legacyApplianceClass");

    return legacyClass ==
        objc_getClass("ClockAppliance");
}

static id ClockLegacyRootController(id self,
                                    SEL cmd)
{
    if (ClockIsLegacyMerchant(self)) {

        id controller =
            [ClockNew(
                objc_getClass("ClockController"))
                autorelease];

        if (controller)
            return controller;
    }

    return clockOriginalLegacyRootController
        ? ((id(*)(id,SEL))
            clockOriginalLegacyRootController)(
                self,
                cmd)
        : nil;
}

static BOOL ClockInstallLegacyRootBridge(void)
{
    Class cls =
        objc_getClass("BLAppLegacyMerchant");

    if (!cls)
        return NO;

    SEL sel =
        NSSelectorFromString(@"rootController");

    Method method =
        class_getInstanceMethod(cls, sel);

    if (!method)
        return NO;

    const char *encoding =
        method_getTypeEncoding(method);

    NSMethodSignature *sig =
        [NSMethodSignature
            signatureWithObjCTypes:encoding];

    if (strcmp([sig methodReturnType],
               @encode(id)) ||
        [sig numberOfArguments] != 2)
        return NO;

    IMP current =
        method_getImplementation(method);

    if (!current)
        return NO;

    if (current ==
        (IMP)ClockLegacyRootController)
        return YES;

    clockOriginalLegacyRootController =
        current;

    if (class_addMethod(
            cls,
            sel,
            (IMP)ClockLegacyRootController,
            encoding))
        return YES;

    Class super =
        class_getSuperclass(cls);

    IMP superIMP =
        super
        ? class_getMethodImplementation(
            super,
            sel)
        : NULL;

    method =
        class_getInstanceMethod(cls, sel);

    if (!method ||
        method_getImplementation(method) ==
            superIMP) {

        clockOriginalLegacyRootController =
            NULL;

        return NO;
    }

    clockOriginalLegacyRootController =
        method_setImplementation(
            method,
            (IMP)ClockLegacyRootController);

    return
        clockOriginalLegacyRootController != NULL;
}

/* ---------------------------------------------------------
   BLAppMerchantInfo icon compatibility bridge
   --------------------------------------------------------- */


/* ---------------------------------------------------------
   Dynamic Home Screen Clock Icon
   188x108 canvas, centered 92x92 clock face
   --------------------------------------------------------- */

static NSString *ClockDynamicIconPath(void)
{
    NSDateFormatter *formatter =
        [[[NSDateFormatter alloc] init] autorelease];

    [formatter setDateFormat:@"yyyyMMddHHmmss"];

    NSString *stamp =
        [formatter stringFromDate:[NSDate date]];

    return [NSString stringWithFormat:
        @"/var/tmp/ClockDynamicIcon-%@.png",
        stamp];
}

static BOOL ClockRenderDynamicHomeIcon(void)
{
    const size_t width = 188;
    const size_t height = 108;

    CGColorSpaceRef cs =
        CGColorSpaceCreateDeviceRGB();

    if (!cs)
        return NO;

    CGContextRef ctx =
        CGBitmapContextCreate(NULL,
                             width,
                             height,
                             8,
                             width * 4,
                             cs,
                             kCGImageAlphaPremultipliedLast |
                             kCGBitmapByteOrder32Big);

    CGColorSpaceRelease(cs);

    if (!ctx)
        return NO;

    /* Transparent 188x108 canvas. */
    CGContextClearRect(ctx, CGRectMake(0, 0, width, height));

    const CGFloat cx = 94.0f;
    const CGFloat cy = 54.0f;
    const CGFloat radius = 46.0f;

    /* Light clock face. */
    CGContextSetRGBFillColor(ctx, 0.97, 0.97, 0.97, 1.0);
    CGContextFillEllipseInRect(
        ctx,
        CGRectMake(cx - radius,
                   cy - radius,
                   radius * 2.0f,
                   radius * 2.0f));

    /* Outer rim. */
    CGContextSetRGBStrokeColor(ctx, 0.12, 0.12, 0.12, 1.0);
    CGContextSetLineWidth(ctx, 1.5f);
    CGContextStrokeEllipseInRect(
        ctx,
        CGRectMake(cx - radius,
                   cy - radius,
                   radius * 2.0f,
                   radius * 2.0f));

    const CGFloat pi = 3.14159265358979323846f;

    /* 60 tick marks. */
    for (int i = 0; i < 60; i++) {

        CGFloat angle =
            ((CGFloat)i / 60.0f) *
            2.0f * pi -
            pi / 2.0f;

        BOOL major = ((i % 5) == 0);

        CGFloat outer = radius - 4.0f;
        CGFloat inner =
            outer - (major ? 8.0f : 3.5f);

        CGFloat x1 =
            cx + cosf(angle) * inner;
        CGFloat y1 =
            cy + sinf(angle) * inner;

        CGFloat x2 =
            cx + cosf(angle) * outer;
        CGFloat y2 =
            cy + sinf(angle) * outer;

        CGContextSetRGBStrokeColor(
            ctx, 0.10, 0.10, 0.10, 1.0);

        CGContextSetLineWidth(
            ctx, major ? 1.8f : 0.7f);

        CGContextMoveToPoint(ctx, x1, y1);
        CGContextAddLineToPoint(ctx, x2, y2);
        CGContextStrokePath(ctx);
    }

    NSDate *now = [NSDate date];

    NSCalendar *calendar =
        [NSCalendar currentCalendar];

    NSDateComponents *parts =
        [calendar components:
            (NSCalendarUnitHour |
             NSCalendarUnitMinute |
             NSCalendarUnitSecond)
                    fromDate:now];

    NSInteger hour = [parts hour] % 12;
    NSInteger minute = [parts minute];
    NSInteger second = [parts second];

    NSString *debug =
        [NSString stringWithFormat:
            @"date=%@ timezone=%@ hour=%ld minute=%ld second=%ld\\n",
            now,
            [[NSTimeZone localTimeZone] name],
            (long)hour,
            (long)minute,
            (long)second];

    [debug writeToFile:
        @"/var/tmp/clock_dynamic_time.log"
        atomically:YES
        encoding:NSUTF8StringEncoding
        error:NULL];

    CGFloat secondAngle =
        ((CGFloat)second / 60.0f) *
        2.0f * pi -
        pi / 2.0f;

    CGFloat minuteAngle =
        (((CGFloat)minute +
          (CGFloat)second / 60.0f) /
         60.0f) *
        2.0f * pi -
        pi / 2.0f;

    CGFloat hourAngle =
        (((CGFloat)hour +
          (CGFloat)minute / 60.0f) /
         12.0f) *
        2.0f * pi -
        pi / 2.0f;

    /* Hour hand. */
    CGContextSetRGBStrokeColor(
        ctx, 0.08, 0.08, 0.08, 1.0);

    CGContextSetLineCap(ctx, kCGLineCapRound);
    CGContextSetLineWidth(ctx, 4.2f);

    CGContextMoveToPoint(ctx, cx, cy);
    CGContextAddLineToPoint(
        ctx,
        cx + cosf(hourAngle) * 21.0f,
        cy + sinf(hourAngle) * 21.0f);

    CGContextStrokePath(ctx);

    /* Minute hand. */
    CGContextSetLineWidth(ctx, 3.0f);

    CGContextMoveToPoint(ctx, cx, cy);
    CGContextAddLineToPoint(
        ctx,
        cx + cosf(minuteAngle) * 34.0f,
        cy + sinf(minuteAngle) * 34.0f);

    CGContextStrokePath(ctx);

    /* Red second hand. */
    CGContextSetRGBStrokeColor(
        ctx, 0.90, 0.05, 0.05, 1.0);

    CGContextSetLineWidth(ctx, 1.3f);

    CGContextMoveToPoint(
        ctx,
        cx - cosf(secondAngle) * 40.0f,
        cy - sinf(secondAngle) * 40.0f);

    CGContextAddLineToPoint(
        ctx,
        cx + cosf(secondAngle) * 37.0f,
        cy + sinf(secondAngle) * 37.0f);

    CGContextStrokePath(ctx);

    /* Center pin. */
    CGContextSetRGBFillColor(
        ctx, 0.90, 0.05, 0.05, 1.0);

    CGContextFillEllipseInRect(
        ctx,
        CGRectMake(cx - 2.5f,
                   cy - 2.5f,
                   5.0f,
                   5.0f));

    CGImageRef image =
        CGBitmapContextCreateImage(ctx);

    CGContextRelease(ctx);

    if (!image)
        return NO;

    NSMutableData *png =
        [NSMutableData data];

    CGImageDestinationRef dest =
        CGImageDestinationCreateWithData(
            (CFMutableDataRef)png,
            CFSTR("public.png"),
            1,
            NULL);

    if (!dest) {
        CGImageRelease(image);
        return NO;
    }

    CGImageDestinationAddImage(dest,
                               image,
                               NULL);

    BOOL ok =
        CGImageDestinationFinalize(dest);

    CFRelease(dest);
    CGImageRelease(image);

    if (!ok || ![png length])
        return NO;

    NSString *path =
        ClockDynamicIconPath();

    NSString *tmp =
        [path stringByAppendingString:@".tmp"];

    if (![png writeToFile:tmp atomically:YES])
        return NO;

    NSFileManager *fm =
        [NSFileManager defaultManager];

    [fm removeItemAtPath:path error:NULL];

    if (![fm moveItemAtPath:tmp
                     toPath:path
                      error:NULL])
        return NO;

    return YES;
}

static NSString *ClockDynamicIconURL(void)
{
    if (ClockRenderDynamicHomeIcon()) {
        return [[NSURL fileURLWithPath:
            ClockDynamicIconPath()]
            absoluteString];
    }

    /* Stable 0.1.3 icon is always the fallback. */
    return ClockMenuIconURL();
}

static NSString *ClockDynamicIconVersion(void)
{
    NSDateFormatter *formatter =
        [[[NSDateFormatter alloc] init]
            autorelease];

    [formatter setDateFormat:
        @"yyyyMMddHHmmss"];

    return [formatter stringFromDate:
        [NSDate date]];
}


static void ClockProbeMerchantCoordinatorClass(void)
{
    Class cls = objc_getClass("ATVMerchantCoordinator");
    FILE *fp = fopen("/var/tmp/clock_coordinator_class.txt", "w");
    if (!fp) return;
    if (!cls) { fprintf(fp, "NOT FOUND\n"); fclose(fp); return; }
    unsigned int n = 0;
    Method *ms = class_copyMethodList(object_getClass(cls), &n);
    for (unsigned int i=0; i<n; i++)
        fprintf(fp, "%s | %s\n", sel_getName(method_getName(ms[i])), method_getTypeEncoding(ms[i]));
    if (ms) free(ms);
    fclose(fp);
}


static void ClockPulseMerchantCoordinator(void)
{
    Class cls = objc_getClass("ATVMerchantCoordinator");
    SEL sharedSel = NSSelectorFromString(@"sharedInstance");
    if (!cls || ![cls respondsToSelector:sharedSel]) return;
    id coordinator = ((id(*)(id,SEL))objc_msgSend)(cls, sharedSel);
    if (!coordinator) return;
    SEL merchantSel = NSSelectorFromString(@"merchantWithIdentifier:");
    SEL changedSel = NSSelectorFromString(@"merchantChanged:");
    if (![coordinator respondsToSelector:merchantSel] ||
        ![coordinator respondsToSelector:changedSel]) return;
    id merchant = ((id(*)(id,SEL,id))objc_msgSend)(coordinator, merchantSel, @"org.atv3.clock");
    if (merchant)
        ((void(*)(id,SEL,id))objc_msgSend)(coordinator, changedSel, merchant);
}

static void ClockHomeIconTimerFire(id self, SEL cmd, NSTimer *timer)
{
    (void)self; (void)cmd; (void)timer;
    ClockPulseMerchantCoordinator();
}

static void ClockStartHomeIconTimer(void)
{
    static NSTimer *timer = nil;
    if (timer) return;
    Class timerClass = objc_getClass("ClockHomeIconTimerTarget");
    if (!timerClass) {
        timerClass = objc_allocateClassPair([NSObject class], "ClockHomeIconTimerTarget", 0);
        if (!timerClass) return;
        class_addMethod(timerClass, NSSelectorFromString(@"fire:"), (IMP)ClockHomeIconTimerFire, "v@:@");
        objc_registerClassPair(timerClass);
    }
    static id target = nil;
    if (!target) target = [[timerClass alloc] init];
    timer = [[NSTimer scheduledTimerWithTimeInterval:1.0
                                              target:target
                                            selector:NSSelectorFromString(@"fire:")
                                            userInfo:nil
                                             repeats:YES] retain];
}

static IMP clockSuperMerchantInfoValueForKey = NULL;

static BOOL ClockIsMerchantInfo(id self)
{
    id merchantID =
        ClockObject(self, @"merchantID");

    return
        [merchantID isKindOfClass:[NSString class]] &&
        [merchantID isEqualToString:@"org.atv3.clock"];
}

static id ClockMerchantInfoValueForKey(id self, SEL cmd, id key)
{
    if ([key isKindOfClass:[NSString class]] && ClockIsMerchantInfo(self)) {
        if ([key isEqualToString:@"menu-icon-url"]) {
            NSString *url = ClockMenuIconURL();
            if (![url length]) return nil;
            return @{
                @"720": url,
                @"1080": url,
                [NSNumber numberWithInteger:720]: url,
                [NSNumber numberWithInteger:1080]: url
            };
        }
        if ([key isEqualToString:@"menu-icon-url-version"]) {
            NSBundle *bundle = [NSBundle bundleWithIdentifier:@"org.atv3.clock"];
            id version = [bundle objectForInfoDictionaryKey:@"CFBundleVersion"];
            return ([version isKindOfClass:[NSString class]] && [version length]) ? version : @"1";
        }
    }
    return clockSuperMerchantInfoValueForKey
        ? ((id(*)(id,SEL,id))clockSuperMerchantInfoValueForKey)(self,cmd,key)
        : nil;
}

static BOOL ClockInstallMerchantInfoBridge(void)
{
    Class cls =
        objc_getClass("BLAppMerchantInfo");

    if (!cls)
        return NO;

    Class super =
        class_getSuperclass(cls);

    SEL sel =
        NSSelectorFromString(@"valueForKey:");

    Method inherited =
        class_getInstanceMethod(cls, sel);

    Method superMethod =
        super
        ? class_getInstanceMethod(super, sel)
        : NULL;

    if (!inherited || !superMethod)
        return NO;

    const char *encoding =
        method_getTypeEncoding(inherited);

    NSMethodSignature *sig =
        [NSMethodSignature
            signatureWithObjCTypes:encoding];

    if (strcmp([sig methodReturnType],
               @encode(id)) ||
        [sig numberOfArguments] != 3 ||
        strcmp([sig getArgumentTypeAtIndex:2],
               @encode(id)))
        return NO;

    clockSuperMerchantInfoValueForKey =
        method_getImplementation(superMethod);

    if (!clockSuperMerchantInfoValueForKey)
        return NO;

    if (!class_addMethod(
            cls,
            sel,
            (IMP)ClockMerchantInfoValueForKey,
            encoding))
        return NO;

    return YES;
}

/* ---------------------------------------------------------
   Runtime class registration
   --------------------------------------------------------- */

static BOOL ClockAddOverride(Class cls,
                             NSString *name,
                             IMP imp,
                             const char *result,
                             NSArray *args)
{
    SEL sel =
        NSSelectorFromString(name);

    Method method =
        class_getInstanceMethod(
            class_getSuperclass(cls),
            sel);

    if (!method) {
        NSLog(@"Clock: missing %@", name);
        return NO;
    }

    NSMethodSignature *sig =
        [NSMethodSignature
            signatureWithObjCTypes:
                method_getTypeEncoding(method)];

    if (strcmp([sig methodReturnType],
               result) ||
        [sig numberOfArguments] !=
            [args count] + 2)
        return NO;

    for (NSUInteger i = 0;
         i < [args count];
         i++) {

        if (strcmp(
            [sig getArgumentTypeAtIndex:i + 2],
            [[args objectAtIndex:i] UTF8String]))
            return NO;
    }

    return class_addMethod(
        cls,
        sel,
        imp,
        method_getTypeEncoding(method));
}


static void ClockDumpRuntimeClass(FILE *fp, const char *name)
{
    Class cls = objc_getClass(name);

    fprintf(fp, "\n========== %s ==========\n", name);

    if (!cls) {
        fprintf(fp, "NOT FOUND\n");
        return;
    }

    Class super = class_getSuperclass(cls);

    fprintf(fp,
            "class=%s superclass=%s\n",
            class_getName(cls),
            super ? class_getName(super) : "(none)");

    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);

    fprintf(fp, "method_count=%u\n", count);

    for (unsigned int i = 0; i < count; i++) {
        SEL sel = method_getName(methods[i]);
        const char *types = method_getTypeEncoding(methods[i]);

        fprintf(fp,
                "%s | %s\n",
                sel_getName(sel),
                types ? types : "");
    }

    if (methods)
        free(methods);
}

static void ClockDumpRuntime(void)
{
    FILE *fp = fopen("/var/tmp/clock_runtime.txt", "w");

    if (!fp)
        return;

    const char *classes[] = {
        "BRController",
        "BRMediaMenuController",
        "BRControl",
        "BRImageControl",
        "BRAsyncImageControl",
        "BRTextControl",
        "BRWindow",
        "BRView",
        "ATVMerchantCoordinator",
        "ATVMerchant",
        "BRMerchant",
        "BRMerchantInfo",
        "BLAppMerchantInfo",
        "BLAppLegacyMerchant"
    };

    unsigned int count =
        sizeof(classes) / sizeof(classes[0]);

    for (unsigned int i = 0; i < count; i++)
        ClockDumpRuntimeClass(fp, classes[i]);

    fflush(fp);
    fclose(fp);
}


static void ClockDumpHomeIconRuntime(void)
{
    FILE *fp =
        fopen("/var/tmp/clock_home_icon_runtime.txt", "w");

    if (!fp)
        return;

    int count = objc_getClassList(NULL, 0);

    if (count <= 0) {
        fclose(fp);
        return;
    }

    Class *classes =
        (Class *)malloc(sizeof(Class) * count);

    if (!classes) {
        fclose(fp);
        return;
    }

    count = objc_getClassList(classes, count);

    const char *words[] = {
        "Icon",
        "Shelf",
        "Merchant",
        "Appliance",
        "MenuItem",
        "Image"
    };

    unsigned int wordCount =
        sizeof(words) / sizeof(words[0]);

    for (int i = 0; i < count; i++) {

        Class cls = classes[i];

        if (!cls)
            continue;

        const char *name = class_getName(cls);

        if (!name)
            continue;

        BOOL interesting = NO;

        for (unsigned int w = 0;
             w < wordCount;
             w++) {

            if (strstr(name, words[w])) {
                interesting = YES;
                break;
            }
        }

        if (!interesting)
            continue;

        fprintf(fp,
                "\n===== %s =====\n",
                name);

        Class super = class_getSuperclass(cls);

        fprintf(fp,
                "super=%s\n",
                super
                    ? class_getName(super)
                    : "(none)");

        unsigned int methodCount = 0;

        Method *methods =
            class_copyMethodList(
                cls,
                &methodCount);

        for (unsigned int m = 0;
             m < methodCount;
             m++) {

            SEL sel =
                method_getName(methods[m]);

            const char *selName =
                sel_getName(sel);

            if (!selName)
                continue;

            if (strstr(selName, "icon") ||
                strstr(selName, "Icon") ||
                strstr(selName, "image") ||
                strstr(selName, "Image") ||
                strstr(selName, "reload") ||
                strstr(selName, "Reload") ||
                strstr(selName, "refresh") ||
                strstr(selName, "Refresh") ||
                strstr(selName, "update") ||
                strstr(selName, "Update") ||
                strstr(selName, "merchant") ||
                strstr(selName, "Merchant") ||
                strstr(selName, "appliance") ||
                strstr(selName, "Appliance") ||
                strstr(selName, "control") ||
                strstr(selName, "Control")) {

                fprintf(fp,
                        "%s | %s\n",
                        selName,
                        method_getTypeEncoding(
                            methods[m]));
            }
        }

        if (methods)
            free(methods);
    }

    free(classes);

    fflush(fp);
    fclose(fp);
}


BOOL ClockRegisterBackRowClasses(void)
{
    ClockProbeMerchantCoordinatorClass();
    ClockDumpHomeIconRuntime();
    ClockDumpRuntime();
    if (objc_getClass("ClockAppliance")) {
        ClockInstallLegacyRootBridge();
        return YES;
    }

    if (!ClockCategoryAvailable()) {
        NSLog(@"Clock: category ABI unavailable");
        return NO;
    }

    Class applianceBase =
        objc_getClass("BRBaseAppliance");

    Class controllerBase =
        objc_getClass("BRController");

    if (!applianceBase ||
        !controllerBase) {

        NSLog(@"Clock: BackRow unavailable");
        return NO;
    }

    Class appliance =
        objc_allocateClassPair(
            applianceBase,
            "ClockAppliance",
            0);

    Class controller =
        objc_allocateClassPair(
            controllerBase,
            "ClockController",
            0);

    if (!appliance || !controller) {

        if (appliance)
            objc_disposeClassPair(appliance);

        if (controller)
            objc_disposeClassPair(controller);

        return NO;
    }

    BOOL ok =
        ClockAddOverride(
            appliance,
            @"initWithApplianceInfo:",
            (IMP)ClockApplianceInit,
            @encode(id),
            @[@"@"])
        &&
        ClockAddOverride(
            appliance,
            @"applianceCategories",
            (IMP)ClockCategories,
            @encode(id),
            @[])
        &&
        ClockAddOverride(
            appliance,
            @"controllerForIdentifier:args:",
            (IMP)ClockControllerForIdentifier,
            @encode(id),
            @[@"@", @"@"])
        &&
        ClockAddOverride(
            appliance,
            @"applianceController",
            (IMP)ClockApplianceController,
            @encode(id),
            @[])
        &&
        ClockAddOverride(
            controller,
            @"brEventAction:",
            (IMP)ClockEvent,
            @encode(BOOL),
            @[@"@"]);

    if (ok) {

        ok =
            ClockAddOverride(
                controller,
                @"init",
                (IMP)ClockControllerInit,
                @encode(id),
                @[])
            &&
            ClockAddOverride(
                controller,
                @"controlWasActivated",
                (IMP)ClockActivated,
                @encode(void),
                @[])
            &&
            ClockAddOverride(
                controller,
                @"controlWasDeactivated",
                (IMP)ClockDeactivated,
                @encode(void),
                @[])
            &&
            ClockAddOverride(
                controller,
                @"wasPopped",
                (IMP)ClockPopped,
                @encode(void),
                @[])
            &&
            ClockAddOverride(
                controller,
                @"dealloc",
                (IMP)ClockControllerDealloc,
                @encode(void),
                @[]);

    }

    if (!ok) {

        objc_disposeClassPair(appliance);
        objc_disposeClassPair(controller);

        NSLog(@"Clock: incompatible BackRow ABI");

        return NO;
    }

    /* Register controller first, same proven order as Jellyfin. */
    objc_registerClassPair(controller);
    objc_registerClassPair(appliance);

    ClockInstallMerchantInfoBridge();
    ClockInstallLegacyRootBridge();

    NSLog(@"Clock: BackRow classes registered");

    return YES;
}

/* Dynamic NSTimer target selector */
__attribute__((constructor))
static void ClockInstallTimerSelector(void)
{
    /* Installed after ClockController is dynamically created,
       so actual selector installation occurs lazily below. */
}

static void ClockEnsureTimerSelector(void)
{
    Class cls =
        objc_getClass("ClockController");

    if (!cls)
        return;

    SEL sel =
        NSSelectorFromString(@"clockTimerFire:");

    if (!class_getInstanceMethod(cls, sel)) {

        class_addMethod(
            cls,
            sel,
            (IMP)ClockTimerFire,
            "v@:@");
    }
}
