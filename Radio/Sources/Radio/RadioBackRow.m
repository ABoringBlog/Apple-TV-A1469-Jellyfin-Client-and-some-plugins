#import "RadioBackRow.h"

#import <objc/runtime.h>
#import <objc/message.h>
#include <stdio.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreText/CoreText.h>
#import <ImageIO/ImageIO.h>
#import <AVFoundation/AVFoundation.h>
#include <string.h>

#ifndef RADIO_LANG_EN
#define RADIO_LANG_EN 0
#endif

static NSString *RadioL(NSString *zh, NSString *en)
{
    return RADIO_LANG_EN ? en : zh;
}

static NSString *RadioBridgeBaseURLString(void)
{
    NSString *value=[NSString stringWithContentsOfFile:@"/var/root/.atv3-radio-bridge-url"
                                              encoding:NSUTF8StringEncoding
                                                 error:NULL];
    if (![value isKindOfClass:[NSString class]]) return nil;
    value=[value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    while ([value hasSuffix:@"/"] && [value length]>0) value=[value substringToIndex:[value length]-1];
    if (![value length]) return nil;
    NSURL *url=[NSURL URLWithString:value];
    NSString *scheme=[[url scheme] lowercaseString];
    if (!url || ![url host] ||
        !([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])) return nil;
    return value;
}

static NSURL *RadioBridgeURL(NSString *path)
{
    NSString *base=RadioBridgeBaseURLString();
    if (![base length] || ![path isKindOfClass:[NSString class]] || ![path hasPrefix:@"/"]) return nil;
    return [NSURL URLWithString:[base stringByAppendingString:path]];
}

static char internetradioTimerKey;
static NSMutableArray *radioRows;
static NSString *radioPage=@"Home";
static NSInteger radioSelected=0;
static AVPlayer *radioPlayer=nil;
static NSString *radioNowPlaying=nil;
static BOOL radioLoading=NO;
static NSString *radioStatus=nil;
static NSString *radioQuery=nil;
static NSMutableString *radioSearchText=nil;
static NSInteger radioLetterIndex=0;
static NSString *radioAlphabet=@"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ";
static NSString *radioCountry=nil;
static NSString *radioTag=nil;
static NSDictionary *radioPlayingStation=nil;
static BOOL radioPaused=NO;
static NSInteger radioRetryCount=0;
static NSString *radioLastError=nil;
static NSString *radioLastStationPage=nil;
static NSInteger radioLastStationIndex=0;
static id radioObserver=nil;
static NSTimeInterval radioNextRetry=0;
static NSTimeInterval radioStartedAt=0;
static BOOL radioReady=NO;
static void RadioRefresh(id self, SEL cmd);
static void RadioPlayStation(id controller,NSDictionary *item);
@interface RadioPlaybackMonitor : NSObject
- (void)playerFailed:(NSNotification *)note;
- (void)playerStatus:(NSNotification *)note;
@end
@implementation RadioPlaybackMonitor
- (void)playerFailed:(NSNotification *)note {
    NSError *error=[[note userInfo] objectForKey:AVPlayerItemFailedToPlayToEndTimeErrorKey];
    radioStatus=[NSString stringWithFormat:RadioL(@"播放失败：%@", @"Playback failed: %@"),error.localizedDescription?:RadioL(@"未知错误", @"Unknown error")];
    NSLog(@"Radio: playback failed %@",error);
}
- (void)playerStatus:(NSNotification *)note {
    if (radioPlayer.currentItem.status==AVPlayerItemStatusFailed) {
        radioStatus=[NSString stringWithFormat:RadioL(@"播放失败：%@", @"Playback failed: %@"),radioPlayer.currentItem.error.localizedDescription?:RadioL(@"格式不受支持", @"Unsupported format")];
        NSLog(@"Radio: player item failed %@",radioPlayer.currentItem.error);
    }
}
@end
static void RadioStopPlayback(void) {
    if (radioPlayer.currentItem && radioObserver) {
        [[NSNotificationCenter defaultCenter] removeObserver:radioObserver name:AVPlayerItemFailedToPlayToEndTimeNotification object:radioPlayer.currentItem];
        /* Status is polled on the main run loop; do not register KVO without observeValueForKeyPath:. */
    }
    [radioPlayer pause];[radioPlayer release];radioPlayer=nil;radioPaused=NO;radioReady=NO;
}
static void RadioPlayStation(id controller,NSDictionary *item) {
    NSString *stream=[item objectForKey:@"url_resolved"];
    NSURL *url=[stream isKindOfClass:[NSString class]]?[NSURL URLWithString:stream]:nil;
    if (!url || ![@[@"http",@"https"] containsObject:[url.scheme lowercaseString]]) {radioStatus=RadioL(@"该电台无法播放", @"This station cannot be played");return;}
    RadioStopPlayback();
    AVPlayerItem *playerItem=[AVPlayerItem playerItemWithURL:url];
    radioPlayer=[[AVPlayer playerWithPlayerItem:playerItem] retain];
    if (!radioObserver)radioObserver=[[RadioPlaybackMonitor alloc]init];
    [[NSNotificationCenter defaultCenter] addObserver:radioObserver selector:@selector(playerFailed:) name:AVPlayerItemFailedToPlayToEndTimeNotification object:playerItem];
    /* Status polling avoids KVO crashes on legacy ATV3 AVFoundation. */
    [radioPlayer play];
    radioStartedAt=[NSDate timeIntervalSinceReferenceDate];radioReady=NO;
    [radioPlayingStation release];radioPlayingStation=[item copy];
    [radioNowPlaying release];radioNowPlaying=[[item objectForKey:@"name"] copy];
    radioStatus=RadioL(@"正在连接电台…", @"Connecting to station...");radioPaused=NO;
    [NSThread detachNewThreadSelector:NSSelectorFromString(@"internetradioRecordPlayed:") toTarget:controller withObject:item];
}

static NSString *RadioEscape(NSString *s) { return [[s stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding] stringByReplacingOccurrencesOfString:@"+" withString:@"%2B"]; }
static NSDictionary *RadioAPI(NSString *path) {
    NSURL *url=RadioBridgeURL(path);
    if (!url) return nil;
    NSMutableURLRequest *req=[NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:12];
    NSData *data=[NSURLConnection sendSynchronousRequest:req returningResponse:NULL error:NULL];
    if (!data) return nil;
    id result=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    return [result isKindOfClass:[NSDictionary class]] ? result : nil;
}
static void RadioLoadBackground(id controller) {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc]init];
    NSString *page=nil,*country=nil,*tag=nil,*query=nil;
    @synchronized([NSObject class]) { page=[radioPage copy]; country=[radioCountry copy]; tag=[radioTag copy]; query=[radioQuery copy]; }
    NSString *path=nil; NSString *key=nil;
    if ([page isEqual:@"Stations"]) {
        NSMutableArray *parts=[NSMutableArray arrayWithObject:@"limit=100"];
        if (country.length) [parts addObject:[@"countrycode=" stringByAppendingString:RadioEscape(country)]];
        if (tag.length) [parts addObject:[@"tag=" stringByAppendingString:RadioEscape(tag)]];
        if (query.length) [parts addObject:[@"name=" stringByAppendingString:RadioEscape(query)]];
        path=[@"/v1/radio/stations?" stringByAppendingString:[parts componentsJoinedByString:@"&"]];key=@"stations";
    } else if ([page isEqual:@"Countries"]) {path=@"/v1/radio/countries";key=@"countries";}
    else if ([page isEqual:@"Genres"]) {path=@"/v1/radio/tags";key=@"tags";}
    else if ([page isEqual:@"Favorites"]) {path=@"/v1/radio/favorites";key=@"favorites";}
    else if ([page isEqual:@"Recent"]) {path=@"/v1/radio/recent";key=@"recent";}
    NSDictionary *result=path?RadioAPI(path):nil;
    @synchronized([NSObject class]) {
        if ([radioPage isEqual:page]) {
            [radioRows release]; radioRows=[[NSMutableArray alloc]initWithArray:[result objectForKey:key]?:@[]];
            radioSelected=0;radioStatus=result?RadioL(@"加载完成", @"Loaded"):RadioL(@"无法连接桥接服务", @"Cannot reach ATV3Bridge");radioLoading=NO;
        }
    }
    [controller performSelectorOnMainThread:NSSelectorFromString(@"internetradioApplyFreshData") withObject:nil waitUntilDone:NO];
    [page release];[country release];[tag release];[query release];[pool drain];
}
static void RadioLoad(id controller) {
    radioLoading=YES;radioStatus=RadioL(@"正在加载…", @"Loading...");
    [NSThread detachNewThreadSelector:NSSelectorFromString(@"internetradioLoadPage:") toTarget:controller withObject:nil];
}
static void RadioRecord(NSString *action,NSDictionary *station) {
    if (!station)return;
    NSDictionary *payload=@{@"station":station};
    NSData *body=[NSJSONSerialization dataWithJSONObject:payload options:0 error:NULL];
    NSURL *url=RadioBridgeURL([@"/v1/radio/" stringByAppendingString:action]);
    if (!url) return;
    NSMutableURLRequest *req=[NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:3];
    [req setHTTPMethod:@"POST"];[req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];[req setHTTPBody:body];
    [NSURLConnection sendSynchronousRequest:req returningResponse:NULL error:NULL];
}


/* ---------------------------------------------------------
   Generic ABI helpers
   --------------------------------------------------------- */

static BOOL RadioSignature(id target, SEL sel, const char *result, NSArray *args)
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

static id RadioObject(id target, NSString *name)
{
    SEL sel = NSSelectorFromString(name);

    if (!RadioSignature(target, sel, @encode(id), @[]))
        return nil;

    return ((id(*)(id,SEL))objc_msgSend)(target, sel);
}

static id RadioNew(Class cls)
{
    if (!cls)
        return nil;

    return [[cls alloc] init];
}

static IMP RadioControllerSuper(SEL selector)
{
    Class cls = objc_getClass("RadioController");

    if (!cls)
        return NULL;

    Class base = class_getSuperclass(cls);

    return base ? class_getMethodImplementation(base, selector) : NULL;
}

static IMP RadioApplianceSuper(SEL selector)
{
    Class cls = objc_getClass("RadioAppliance");

    if (!cls)
        return NULL;

    Class base = class_getSuperclass(cls);

    return base ? class_getMethodImplementation(base, selector) : NULL;
}

/* ---------------------------------------------------------
   Radio display
   --------------------------------------------------------- */

static NSDictionary *RadioBridgeData(void)
{
    return nil;
}

static NSDictionary *internetradioCachedSnapshot = nil;
static NSTimeInterval internetradioCachedAt = 0;
static BOOL internetradioFetchInFlight = NO;

static NSString *RadioCachePath(void)
{
    return @"/var/mobile/Library/Caches/org.atv3.internetradio.snapshot.json";
}

static void RadioStoreSnapshot(NSDictionary *fresh)
{
    if (![fresh isKindOfClass:[NSDictionary class]]) return;
    @synchronized([NSObject class]) {
        [internetradioCachedSnapshot release];
        internetradioCachedSnapshot=[fresh retain];
        internetradioCachedAt=[NSDate timeIntervalSinceReferenceDate];
    }
    NSData *data=[NSJSONSerialization dataWithJSONObject:fresh options:0 error:NULL];
    if ([data length]) [data writeToFile:RadioCachePath() atomically:YES];
}

static NSDictionary *RadioSnapshot(void)
{
    @synchronized([NSObject class]) {
        if (!internetradioCachedSnapshot) {
            NSData *data=[NSData dataWithContentsOfFile:RadioCachePath()];
            if ([data length]) {
                id obj=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
                if ([obj isKindOfClass:[NSDictionary class]]) internetradioCachedSnapshot=[obj retain];
            }
        }
        return internetradioCachedSnapshot;
    }
}

static void RadioFetchAsync(id controller)
{
    @synchronized([NSObject class]) {
        if (internetradioFetchInFlight) return;
        internetradioFetchInFlight=YES;
    }
    [NSThread detachNewThreadSelector:NSSelectorFromString(@"internetradioBackgroundFetch:")
                             toTarget:controller withObject:nil];
}

static NSString *RadioConditionMark(NSNumber *code, NSNumber *isDay)
{
    NSInteger c=[code integerValue]; BOOL day=!isDay || [isDay boolValue];
    if (c==0) return day ? @"SUN" : @"MOON";
    if (c==1 || c==2) return @"SUN/CLOUD";
    if (c==3) return @"CLOUD";
    if (c==45 || c==48) return @"FOG";
    if ((c>=51 && c<=67) || (c>=80 && c<=82)) return @"RAIN";
    if ((c>=71 && c<=77) || c==85 || c==86) return @"SNOW";
    if (c>=95) return @"STORM";
    return @"WEATHER";
}

static NSString *RadioChineseCondition(NSInteger code);

static NSString *RadioCurrentTime(void)
{
    return RadioL(@"网络电台", @"Internet Radio");
}

static NSString *RadioCurrentDate(void)
{
    return radioStatus ?: RadioL(@"请选择分类", @"Choose a category");
}

static NSString *RadioHourlySummary(void) { return @""; }
static NSString *RadioDailySummary(void) { return @""; }

static void RadioRoundedRect(CGContextRef c, CGRect r, CGFloat radius)
{
    CGFloat x=CGRectGetMinX(r), y=CGRectGetMinY(r), w=CGRectGetWidth(r), h=CGRectGetHeight(r);
    CGContextBeginPath(c);
    CGContextMoveToPoint(c,x+radius,y);
    CGContextAddLineToPoint(c,x+w-radius,y);
    CGContextAddArc(c,x+w-radius,y+radius,radius,-M_PI_2,0,0);
    CGContextAddLineToPoint(c,x+w,y+h-radius);
    CGContextAddArc(c,x+w-radius,y+h-radius,radius,0,M_PI_2,0);
    CGContextAddLineToPoint(c,x+radius,y+h);
    CGContextAddArc(c,x+radius,y+h-radius,radius,M_PI_2,M_PI,0);
    CGContextAddLineToPoint(c,x,y+radius);
    CGContextAddArc(c,x+radius,y+radius,radius,M_PI,3*M_PI_2,0);
    CGContextClosePath(c);
}

static CTFontRef RadioCTFont(CGFloat size)
{
    CTFontRef font=CTFontCreateWithName(CFSTR("STHeitiSC-Light"),size,NULL);
    if (!font) font=CTFontCreateWithName(CFSTR("STHeiti-Light"),size,NULL);
    if (!font) font=CTFontCreateWithName(CFSTR("STHeitiSC-Medium"),size,NULL);
    if (!font) font=CTFontCreateWithName(CFSTR("STHeiti-Medium"),size,NULL);
    if (!font) font=CTFontCreateWithName(CFSTR("HelveticaNeue"),size,NULL);
    return font;
}

static CTLineRef RadioCTLine(NSString *text, CGFloat size, CGFloat gray)
{
    if (![text length]) return NULL;
    CTFontRef font=RadioCTFont(size);
    if (!font) return NULL;
    CGColorSpaceRef cs=CGColorSpaceCreateDeviceRGB();
    CGFloat comps[4]={gray,gray,gray,1.0f};
    CGColorRef color=CGColorCreate(cs,comps);
    NSDictionary *attrs=[NSDictionary dictionaryWithObjectsAndKeys:
        (id)font,(id)kCTFontAttributeName,
        (id)color,(id)kCTForegroundColorAttributeName,nil];
    NSAttributedString *as=[[[NSAttributedString alloc] initWithString:text attributes:attrs] autorelease];
    CTLineRef line=CTLineCreateWithAttributedString((CFAttributedStringRef)as);
    CGColorRelease(color); CGColorSpaceRelease(cs); CFRelease(font);
    return line;
}

static void RadioText(CGContextRef c, NSString *text, CGFloat x, CGFloat y, CGFloat size, CGFloat gray)
{
    CTLineRef line=RadioCTLine(text,size,gray);
    if (!line) return;
    CGContextSaveGState(c);
    CGContextSetTextMatrix(c,CGAffineTransformIdentity);
    CGContextSetTextPosition(c,x,y);
    CTLineDraw(line,c);
    CGContextRestoreGState(c);
    CFRelease(line);
}

static CGFloat RadioTextWidth(NSString *text, CGFloat size)
{
    CTLineRef line=RadioCTLine(text,size,1.0f);
    if (!line) return 0.0f;
    double width=CTLineGetTypographicBounds(line,NULL,NULL,NULL);
    CFRelease(line);
    return (CGFloat)width;
}

static void RadioCenteredText(CGContextRef c, NSString *text, CGFloat centerX,
                                CGFloat y, CGFloat size, CGFloat gray)
{
    RadioText(c,text,centerX-RadioTextWidth(text,size)*0.5f,y,size,gray);
}

static CGFloat RadioIconVisualCenter(NSInteger code, CGFloat scale)
{
    BOOL rain=((code>=51&&code<=67)||(code>=80&&code<=82));
    BOOL snow=((code>=71&&code<=77)||code==85||code==86);
    BOOL storm=(code>=95);
    BOOL fog=(code==45||code==48);
    BOOL cloudy=(code>=1&&code<=3)||rain||snow||storm||fog;
    if (cloudy) return 75.0f*scale;
    return 37.0f*scale;
}

static void RadioIcon(CGContextRef c, NSInteger code, BOOL day, CGFloat x, CGFloat y, CGFloat scale)
{
    BOOL rain=((code>=51&&code<=67)||(code>=80&&code<=82));
    BOOL snow=((code>=71&&code<=77)||code==85||code==86);
    BOOL storm=(code>=95);
    BOOL fog=(code==45||code==48);
    BOOL cloudy=(code>=1&&code<=3)||rain||snow||storm||fog;

    if (code==0 || code==1 || code==2) {
        CGContextSetRGBFillColor(c,1.0,0.78,0.12,1.0);
        if (day) {
            CGContextFillEllipseInRect(c,CGRectMake(x+15*scale,y+28*scale,42*scale,42*scale));
            CGContextSetLineWidth(c,4*scale); CGContextSetRGBStrokeColor(c,1.0,0.78,0.12,1.0);
            for(int i=0;i<8;i++){ CGFloat a=i*M_PI/4.0; CGContextMoveToPoint(c,x+(36+29*cos(a))*scale,y+(49+29*sin(a))*scale); CGContextAddLineToPoint(c,x+(36+39*cos(a))*scale,y+(49+39*sin(a))*scale); }
            CGContextStrokePath(c);
        } else {
            CGContextFillEllipseInRect(c,CGRectMake(x+16*scale,y+27*scale,44*scale,44*scale));
            CGContextSetRGBFillColor(c,0.12,0.24,0.43,1.0);
            CGContextFillEllipseInRect(c,CGRectMake(x+29*scale,y+36*scale,40*scale,40*scale));
        }
    }
    if (cloudy) {
        CGContextSetRGBFillColor(c,0.88,0.92,0.97,1.0);
        CGContextFillEllipseInRect(c,CGRectMake(x+34*scale,y+37*scale,42*scale,32*scale));
        CGContextFillEllipseInRect(c,CGRectMake(x+55*scale,y+27*scale,46*scale,43*scale));
        CGContextFillEllipseInRect(c,CGRectMake(x+78*scale,y+40*scale,38*scale,29*scale));
        CGContextFillRect(c,CGRectMake(x+45*scale,y+48*scale,60*scale,22*scale));
    }
    if (rain || storm) {
        CGContextSetRGBStrokeColor(c,0.32,0.70,1.0,1.0); CGContextSetLineWidth(c,4*scale);
        for(int i=0;i<3;i++){ CGFloat dx=(55+i*20)*scale; CGContextMoveToPoint(c,x+dx,y+78*scale); CGContextAddLineToPoint(c,x+(dx-7*scale),y+94*scale); } CGContextStrokePath(c);
    }
    if (snow) {
        CGContextSetRGBFillColor(c,0.85,0.94,1.0,1.0);
        for(int i=0;i<3;i++) CGContextFillEllipseInRect(c,CGRectMake(x+(50+i*23)*scale,y+82*scale,7*scale,7*scale));
    }
    if (fog) {
        CGContextSetRGBStrokeColor(c,0.75,0.80,0.86,1.0); CGContextSetLineWidth(c,3*scale);
        for(int i=0;i<3;i++){ CGContextMoveToPoint(c,x+35*scale,y+(78+i*9)*scale); CGContextAddLineToPoint(c,x+110*scale,y+(78+i*9)*scale); } CGContextStrokePath(c);
    }
    if (storm) {
        CGContextSetRGBFillColor(c,1.0,0.78,0.12,1.0);
        CGContextBeginPath(c); CGContextMoveToPoint(c,x+76*scale,y+70*scale); CGContextAddLineToPoint(c,x+60*scale,y+94*scale); CGContextAddLineToPoint(c,x+73*scale,y+92*scale); CGContextAddLineToPoint(c,x+64*scale,y+110*scale); CGContextAddLineToPoint(c,x+91*scale,y+82*scale); CGContextAddLineToPoint(c,x+77*scale,y+84*scale); CGContextClosePath(c); CGContextFillPath(c);
    }
}

static NSString *RadioDisplayPage(NSString *page) {
    NSDictionary *zh=@{@"Home":@"首页",@"Stations":@"全球电台",@"Countries":@"国家与地区",@"Genres":@"电台类型",@"Search":@"搜索",@"Favorites":@"我的收藏",@"Recent":@"最近播放"};
    NSDictionary *en=@{@"Home":@"Home",@"Stations":@"Global Stations",@"Countries":@"Countries & Regions",@"Genres":@"Genres",@"Search":@"Search",@"Favorites":@"Favorites",@"Recent":@"Recently Played"};
    NSDictionary *names=RADIO_LANG_EN ? en : zh;
    return [names objectForKey:page]?:page;
}
static NSData *RadioRenderImage(void)
{
    NSTimeInterval started=[NSDate timeIntervalSinceReferenceDate];
    const size_t width=1280,height=720;
    CGColorSpaceRef cs=CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx=CGBitmapContextCreate(NULL,width,height,8,width*4,cs,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(cs); if(!ctx) return nil;
    CGFloat comps[8]={0.025,0.05,0.10,1.0,0.08,0.24,0.42,1.0},locs[2]={0,1};
    CGColorSpaceRef gcs=CGColorSpaceCreateDeviceRGB();
    CGGradientRef grad=CGGradientCreateWithColorComponents(gcs,comps,locs,2);
    CGContextDrawLinearGradient(ctx,grad,CGPointMake(0,0),CGPointMake(0,720),0);
    CGGradientRelease(grad); CGColorSpaceRelease(gcs);
    NSString *page=nil,*status=nil,*playing=nil;NSArray *rows=nil;NSInteger selected=0;
    @synchronized([NSObject class]) {page=[radioPage copy];status=[radioStatus copy];playing=[radioNowPlaying copy];rows=[radioRows copy];selected=radioSelected;}
    RadioText(ctx,[NSString stringWithFormat:RadioL(@"网络电台  /  %@", @"Internet Radio  /  %@"),RadioDisplayPage(page)],72,640,44,1.0);
    RadioText(ctx,playing.length?[NSString stringWithFormat:RadioL(@"%@：%@", @"%@: %@"),radioPaused?RadioL(@"已暂停", @"Paused"):RadioL(@"当前电台", @"Now Playing"),playing]:RadioL(@"收听世界各地的广播电台", @"Listen to radio stations from around the world"),74,585,24,0.9);
    CGContextSetRGBFillColor(ctx,1,1,1,0.10); RadioRoundedRect(ctx,CGRectMake(60,95,1160,445),22); CGContextFillPath(ctx);
    if ([page isEqual:@"Home"]) {
        NSArray *options=RADIO_LANG_EN ? @[@"Global Stations",@"Countries & Regions",@"Genres",@"Search Stations (A-Z)",@"Favorites",@"Recently Played"] : @[@"全球电台",@"国家与地区",@"电台类型",@"搜索电台（A-Z）",@"我的收藏",@"最近播放"];
        for (NSInteger i=0;i<(NSInteger)[options count];i++) {
            if (i==selected) {CGContextSetRGBFillColor(ctx,0.16,0.48,0.85,0.8);RadioRoundedRect(ctx,CGRectMake(82,452-i*62,1080,54),12);CGContextFillPath(ctx);}
            RadioText(ctx,[options objectAtIndex:i],112,466-i*62,31,1.0);
        }
    } else if ([page isEqual:@"Search"]) {
        RadioText(ctx,RadioL(@"搜索电台名称", @"Search station name"),108,470,36,1.0);
        RadioText(ctx,radioSearchText.length?radioSearchText:@"_",108,382,34,1.0);
        NSString *letter=[radioAlphabet substringWithRange:NSMakeRange(radioLetterIndex,1)];
        RadioText(ctx,[NSString stringWithFormat:RadioL(@"选择字母： <  %@  >", @"Choose letter: <  %@  >"),letter],108,305,35,1.0);
        RadioText(ctx,RadioL(@"上下：切换字母   确认：输入   右：搜索   左：删除", @"Up/Down: letter   Select: type   Right: search   Left: delete"),108,215,23,0.9);
    } else {
        NSInteger startRow=selected>7?selected-7:0;
        for (NSInteger i=startRow;i<(NSInteger)[rows count]&&i<startRow+8;i++) {
            NSDictionary *item=[rows objectAtIndex:i];
            NSString *name=[item objectForKey:@"name"]?:RadioL(@"未知", @"Unknown");
            if ([page isEqual:@"Countries"]) name=[NSString stringWithFormat:@"%@ (%@)",name,[item objectForKey:@"stationcount"]?:@0];
            if (i==selected) {CGContextSetRGBFillColor(ctx,0.16,0.48,0.85,0.8);RadioRoundedRect(ctx,CGRectMake(82,467-(i-startRow)*49,1080,46),10);CGContextFillPath(ctx);}
            RadioText(ctx,name,108,476-(i-startRow)*49,26,1.0);
        }
        if (![rows count])RadioText(ctx,status?:RadioL(@"暂无电台", @"No stations"),108,400,30,0.9);
    }
    RadioText(ctx,RadioL(@"上下：选择  确认：播放  左：返回  右：收藏  长按确认：暂停／恢复", @"Up/Down: select   Select: play   Left: back   Right: favorite   Hold Select: pause/resume"),74,52,20,0.85);
    if (status.length && ![status isEqual:RadioL(@"加载完成", @"Loaded")])RadioText(ctx,status,710,98,20,0.95);
    [page release];[status release];[playing release];[rows release];
    CGImageRef image=CGBitmapContextCreateImage(ctx); CGContextRelease(ctx); if(!image)return nil;
    NSMutableData *data=[NSMutableData data]; CGImageDestinationRef dest=CGImageDestinationCreateWithData((CFMutableDataRef)data,CFSTR("public.jpeg"),1,NULL);
    if(!dest){CGImageRelease(image);return nil;} NSDictionary *opts=@{(id)kCGImageDestinationLossyCompressionQuality:@(0.78)}; CGImageDestinationAddImage(dest,image,(CFDictionaryRef)opts); BOOL ok=CGImageDestinationFinalize(dest);
    NSTimeInterval ms=([NSDate timeIntervalSinceReferenceDate]-started)*1000.0;
    if(ms>120){FILE *f=fopen("/var/tmp/radio_render_perf.log","a");if(f){fprintf(f,"render_ms=%.1f bytes=%lu\n",ms,(unsigned long)data.length);fclose(f);}}
    CFRelease(dest); CGImageRelease(image); return ok?data:nil;
}

static id RadioCreateImageControl(void)
{
    NSData *data = RadioRenderImage();

    if (![data length])
        return nil;

    Class imageClass = NSClassFromString(@"ATVImage");
    Class controlClass = NSClassFromString(@"BRAsyncImageControl");

    if (!imageClass || !controlClass)
        return nil;

    SEL imageSel = NSSelectorFromString(@"imageWithData:");

    if (!RadioSignature(imageClass,
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

    id control = RadioNew(controlClass);

    if (!control)
        return nil;

    SEL cropSel = NSSelectorFromString(@"setCropAndFill:");

    if (RadioSignature(control,
                       cropSel,
                       @encode(void),
                       @[[NSString stringWithUTF8String:@encode(BOOL)]])) {

        ((void(*)(id,SEL,BOOL))objc_msgSend)(control,
                                             cropSel,
                                             NO);
    }

    SEL setImageSel = NSSelectorFromString(@"setImage:");

    if (!RadioSignature(control,
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


static char RadioImageControlKey;

static id RadioMakeATVImage(void)
{
    NSData *data = RadioRenderImage();

    if (![data length])
        return nil;

    Class imageClass = NSClassFromString(@"ATVImage");

    if (!imageClass)
        return nil;

    SEL sel = NSSelectorFromString(@"imageWithData:");

    if (!RadioSignature(imageClass,
                        sel,
                        @encode(id),
                        @[@"@"]))
        return nil;

    return ((id(*)(id,SEL,id))objc_msgSend)(
        imageClass,
        sel,
        data);
}

/*
 * Shared ATV3 layout rule:
 * BackRow owns the display geometry.  Never query UIScreen and never encode
 * monitor-specific pixel compensation in an appliance.  CGRect is a struct
 * return on armv7, so use NSInvocation rather than a guessed objc_msgSend ABI.
 */
static BOOL RadioBackRowBounds(id host, CGRect *outBounds)
{
    if (!host || !outBounds) return NO;

    SEL sel = NSSelectorFromString(@"bounds");
    NSMethodSignature *sig = [host methodSignatureForSelector:sel];
    if (!sig || strcmp([sig methodReturnType], @encode(CGRect)) ||
        [sig numberOfArguments] != 2) return NO;

    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:host];
    [inv setSelector:sel];
    [inv invoke];

    CGRect bounds = CGRectZero;
    [inv getReturnValue:&bounds];
    if (bounds.size.width <= 0.0f || bounds.size.height <= 0.0f) return NO;

    *outBounds = bounds;
    return YES;
}

static BOOL RadioBackRowSetFrame(id control, CGRect frame)
{
    if (!control) return NO;

    SEL sel = NSSelectorFromString(@"setFrame:");
    NSMethodSignature *sig = [control methodSignatureForSelector:sel];
    if (!sig || strcmp([sig methodReturnType], @encode(void)) ||
        [sig numberOfArguments] != 3 ||
        strcmp([sig getArgumentTypeAtIndex:2], @encode(CGRect))) return NO;

    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:control];
    [inv setSelector:sel];
    [inv setArgument:&frame atIndex:2];
    [inv invoke];
    return YES;
}

static id RadioCreateFullscreenControl(id host)
{
    Class controlClass = NSClassFromString(@"BRImageControl");
    if (!controlClass) return nil;

    id control = RadioNew(controlClass);
    if (!control) return nil;

    CGRect frame = CGRectZero;
    if (!RadioBackRowBounds(host, &frame) ||
        !RadioBackRowSetFrame(control, frame)) {
        [control release];
        return nil;
    }

    NSLog(@"Radio: BackRow-owned bounds %.0fx%.0f at %.0f,%.0f",
          frame.size.width, frame.size.height, frame.origin.x, frame.origin.y);

    return [control autorelease];
}

static void RadioInstallFullscreenControl(id self)
{
    id control =
        objc_getAssociatedObject(
            self,
            &RadioImageControlKey);

    if (control)
        return;

    control = RadioCreateFullscreenControl(self);

    if (!control)
        return;

    objc_setAssociatedObject(
        self,
        &RadioImageControlKey,
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

static void RadioUpdateFullscreenControl(id self)
{
    RadioInstallFullscreenControl(self);

    id control =
        objc_getAssociatedObject(
            self,
            &RadioImageControlKey);

    if (!control)
        return;

    id image = RadioMakeATVImage();

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


static char RadioTimeTextKey;
static char RadioDateTextKey;
static char RadioHourlyTextKey;
static char RadioDailyTextKey;
static char RadioHourlyLabelKey;
static char RadioDailyLabelKey;

static id RadioObjectCall(id target, NSString *name)
{
    if (!target)
        return nil;

    SEL sel = NSSelectorFromString(name);

    if (![target respondsToSelector:sel])
        return nil;

    return ((id(*)(id,SEL))objc_msgSend)(target, sel);
}

static BOOL RadioSetFrame(id control, CGRect frame)
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

static BOOL RadioSetText(id control,
                         NSString *text,
                         id attrs)
{
    if (!control || !text)
        return NO;

    SEL sel =
        NSSelectorFromString(@"setText:withAttributes:");

    if (!RadioSignature(control,
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

static id RadioThemeTextAttributes(void)
{
    Class themeClass =
        NSClassFromString(@"BRThemeInfo");

    if (!themeClass)
        return @{};

    id theme =
        RadioObjectCall(themeClass, @"sharedTheme");

    if (!theme)
        return @{};

    id attrs =
        RadioObjectCall(theme,
                        @"menuTitleTextAttributes");

    static BOOL dumped = NO;

    if (!dumped) {
        dumped = YES;

        NSString *dump =
            [NSString stringWithFormat:
                @"class=%@\nattrs=%@\n",
                attrs ? NSStringFromClass([attrs class]) : @"nil",
                attrs ?: @"nil"];

        [dump writeToFile:@"/var/tmp/internetradio_text_attrs.txt"
               atomically:YES
                 encoding:NSUTF8StringEncoding
                    error:NULL];
    }

    return attrs ?: @{};
}

static id RadioCreateTextControl(void)
{
    Class cls =
        NSClassFromString(@"BRTextControl");

    if (!cls)
        return nil;

    return [RadioNew(cls) autorelease];
}

static void RadioInstallTextControls(id self)
{
    id timeControl =
        objc_getAssociatedObject(
            self,
            &RadioTimeTextKey);

    if (timeControl)
        return;

    timeControl = RadioCreateTextControl();
    id dateControl = RadioCreateTextControl();
    id hourlyControl = RadioCreateTextControl();
    id dailyControl = RadioCreateTextControl();
    id hourlyLabel = RadioCreateTextControl();
    id dailyLabel = RadioCreateTextControl();

    if (!timeControl || !dateControl || !hourlyControl || !dailyControl || !hourlyLabel || !dailyLabel)
        return;

    /*
     * First validation layout.
     * Once BRTextControl is confirmed on-device,
     * we'll replace these temporary frames with
     * measured final internetradio geometry.
     */
    RadioSetFrame(
        timeControl,
        CGRectMake(190.0f,
                   440.0f,
                   900.0f,
                   180.0f));

    RadioSetFrame(
        dateControl,
        CGRectMake(190.0f,
                   365.0f,
                   900.0f,
                   60.0f));

    RadioSetFrame(hourlyLabel, CGRectMake(190.0f, 320.0f, 900.0f, 30.0f));
    RadioSetFrame(hourlyControl, CGRectMake(190.0f, 275.0f, 900.0f, 48.0f));
    RadioSetFrame(dailyLabel, CGRectMake(190.0f, 225.0f, 900.0f, 30.0f));
    RadioSetFrame(dailyControl, CGRectMake(190.0f, 180.0f, 900.0f, 48.0f));

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

    ((void(*)(id,SEL,id))objc_msgSend)(self, addSubviewSel, hourlyLabel);
    ((void(*)(id,SEL,id))objc_msgSend)(self, addSubviewSel, hourlyControl);
    ((void(*)(id,SEL,id))objc_msgSend)(self, addSubviewSel, dailyLabel);
    ((void(*)(id,SEL,id))objc_msgSend)(self, addSubviewSel, dailyControl);

    objc_setAssociatedObject(
        self,
        &RadioTimeTextKey,
        timeControl,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    objc_setAssociatedObject(
        self,
        &RadioDateTextKey,
        dateControl,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    objc_setAssociatedObject(self, &RadioHourlyLabelKey, hourlyLabel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &RadioHourlyTextKey, hourlyControl, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &RadioDailyLabelKey, dailyLabel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &RadioDailyTextKey, dailyControl, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void RadioUpdateTextControls(id self)
{
    RadioInstallTextControls(self);

    id timeControl =
        objc_getAssociatedObject(
            self,
            &RadioTimeTextKey);

    id dateControl =
        objc_getAssociatedObject(
            self,
            &RadioDateTextKey);

    id hourlyLabel = objc_getAssociatedObject(self, &RadioHourlyLabelKey);
    id hourlyControl = objc_getAssociatedObject(self, &RadioHourlyTextKey);
    id dailyLabel = objc_getAssociatedObject(self, &RadioDailyLabelKey);
    id dailyControl = objc_getAssociatedObject(self, &RadioDailyTextKey);

    if (!timeControl || !dateControl || !hourlyLabel || !hourlyControl || !dailyLabel || !dailyControl)
        return;

    NSDictionary *baseAttrs =
        RadioThemeTextAttributes();

    NSMutableDictionary *timeAttrs =
        [NSMutableDictionary dictionaryWithDictionary:
            baseAttrs ?: @{}];

    NSMutableDictionary *dateAttrs =
        [NSMutableDictionary dictionaryWithDictionary:
            baseAttrs ?: @{}];

    [timeAttrs setObject:@82
                  forKey:@"BRFontPointSize"];

    [dateAttrs setObject:@30
                  forKey:@"BRFontPointSize"];

    NSMutableDictionary *forecastAttrs=[NSMutableDictionary dictionaryWithDictionary:baseAttrs ?: @{}];
    [forecastAttrs setObject:@24 forKey:@"BRFontPointSize"];
    [forecastAttrs setObject:@1 forKey:@"BRTextAlignmentKey"];
    NSMutableDictionary *labelAttrs=[NSMutableDictionary dictionaryWithDictionary:baseAttrs ?: @{}];
    [labelAttrs setObject:@19 forKey:@"BRFontPointSize"];
    [labelAttrs setObject:@1 forKey:@"BRTextAlignmentKey"];

    /*
     * Keep the native BackRow alignment value discovered
     * from the real Apple TV theme.
     */
    [timeAttrs setObject:@1
                  forKey:@"BRTextAlignmentKey"];

    [dateAttrs setObject:@1
                  forKey:@"BRTextAlignmentKey"];

    RadioSetText(
        timeControl,
        RadioCurrentTime(),
        timeAttrs);

    RadioSetText(
        dateControl,
        RadioCurrentDate(),
        dateAttrs);

    RadioSetText(hourlyLabel, @"", labelAttrs);
    RadioSetText(hourlyControl, RadioHourlySummary(), forecastAttrs);
    RadioSetText(dailyLabel, @"", labelAttrs);
    RadioSetText(dailyControl, RadioDailySummary(), forecastAttrs);

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
            CGSizeMake(900.0f, 180.0f));
    }

    if ([dateControl respondsToSelector:maxSizeSel]) {
        ((void(*)(id,SEL,CGSize))objc_msgSend)(
            dateControl,
            maxSizeSel,
            CGSizeMake(900.0f, 60.0f));
    }

    if ([hourlyControl respondsToSelector:maxSizeSel]) ((void(*)(id,SEL,CGSize))objc_msgSend)(hourlyControl,maxSizeSel,CGSizeMake(900.0f,55.0f));
    if ([dailyControl respondsToSelector:maxSizeSel]) ((void(*)(id,SEL,CGSize))objc_msgSend)(dailyControl,maxSizeSel,CGSizeMake(900.0f,55.0f));

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

static void RadioRefresh(id self, SEL cmd)
{
    (void)cmd;

    RadioUpdateFullscreenControl(self);

    NSString *time = RadioCurrentTime();
    NSString *date = RadioCurrentDate();

    /*
     * Keep the proven menu controller alive for 0.2.
     * The generated internetradio image is used through the preview-control path.
     */
    NSString *title =
        [NSString stringWithFormat:@"%@     %@", time, date];

    NSArray *selectors = @[@"setListTitle:", @"setTitle:"];

    for (NSString *name in selectors) {

        SEL sel = NSSelectorFromString(name);

        if (RadioSignature(self, sel, @encode(void), @[@"@"])) {
            ((void(*)(id,SEL,id))objc_msgSend)(self, sel, title);
            break;
        }
    }

    SEL reloadSel = NSSelectorFromString(@"reload");

    SEL listSel = NSSelectorFromString(@"list");

    if (RadioSignature(self, listSel, @encode(id), @[])) {

        id list =
            ((id(*)(id,SEL))objc_msgSend)(self, listSel);

        if (list &&
            RadioSignature(list,
                           reloadSel,
                           @encode(void),
                           @[])) {

            ((void(*)(id,SEL))objc_msgSend)(list,
                                            reloadSel);
        }
    }

    NSLog(@"Radio: refresh %@ %@", time, date);
}

static id RadioPreview(id self, SEL cmd, long item)
{
    (void)self;
    (void)cmd;
    (void)item;

    return RadioCreateImageControl();
}

static void RadioTimerFire(id self, SEL cmd, id timer)
{
    (void)cmd;
    (void)timer;

    NSTimeInterval now=[NSDate timeIntervalSinceReferenceDate];
    if (radioPlayer && !radioPaused) {
        AVPlayerItem *item=radioPlayer.currentItem;
        if (item.status==AVPlayerItemStatusReadyToPlay && radioPlayer.rate>0.0f) {
            radioReady=YES;radioRetryCount=0;radioStatus=RadioL(@"正在播放", @"Playing");
        } else if (item.status==AVPlayerItemStatusFailed || (now-radioStartedAt>25.0 && !radioReady)) {
            if (radioRetryCount<3 && now>=radioNextRetry && radioPlayingStation) {
                NSDictionary *station=[radioPlayingStation retain];
                radioRetryCount++;radioNextRetry=now+5.0*radioRetryCount;
                RadioPlayStation(self,station);[station release];
                radioStatus=[NSString stringWithFormat:RadioL(@"连接失败，正在重试（%ld/3）", @"Connection failed, retrying (%ld/3)"),(long)radioRetryCount];
            } else if (radioRetryCount>=3)radioStatus=RadioL(@"播放失败，请重新选择电台", @"Playback failed. Please choose another station");
        }
    }
    RadioRefresh(self,NULL);
}

static void RadioBackgroundFetch(id self, SEL cmd, id unused)
{
    (void)cmd; (void)unused;
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
    NSDictionary *fresh=RadioBridgeData();
    if (fresh) RadioStoreSnapshot(fresh);
    @synchronized([NSObject class]) { internetradioFetchInFlight=NO; }
    if (fresh) [self performSelectorOnMainThread:NSSelectorFromString(@"internetradioApplyFreshData") withObject:nil waitUntilDone:NO];
    [pool drain];
}

static void RadioApplyFreshData(id self, SEL cmd)
{
    (void)cmd;
    RadioRefresh(self,NULL);
}

static void RadioEnsureTimerSelector(void);

/* ---------------------------------------------------------
   Controller lifecycle
   --------------------------------------------------------- */

static id RadioControllerInit(id self, SEL cmd)
{
    IMP superIMP = RadioControllerSuper(cmd);

    if (!superIMP)
        return nil;

    self = ((id(*)(id,SEL))superIMP)(self, cmd);

    if (!self)
        return nil;

    RadioEnsureTimerSelector();
    radioPage=@"Home";radioSelected=0;
    if (!radioStatus) radioStatus=RadioL(@"请选择分类", @"Choose a category");

    NSTimer *timer =
        [NSTimer scheduledTimerWithTimeInterval:3.0
                                        target:self
                                      selector:NSSelectorFromString(@"internetradioTimerFire:")
                                      userInfo:nil
                                       repeats:YES];

    objc_setAssociatedObject(self,
                             &internetradioTimerKey,
                             timer,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    NSLog(@"Radio: controller initialized");

    return self;
}

static void RadioActivated(id self, SEL cmd)
{
    IMP superIMP = RadioControllerSuper(cmd);

    if (superIMP)
        ((void(*)(id,SEL))superIMP)(self, cmd);

    RadioUpdateFullscreenControl(self);
    NSLog(@"Radio: activated immediate frame");
}

static void RadioDeactivated(id self, SEL cmd)
{
    RadioStopPlayback();
    radioRetryCount=0;
    NSLog(@"Radio: deactivated");

    IMP superIMP = RadioControllerSuper(cmd);

    if (superIMP)
        ((void(*)(id,SEL))superIMP)(self, cmd);
}

static void RadioPopped(id self, SEL cmd)
{
    NSTimer *timer =
        (NSTimer *)objc_getAssociatedObject(self, &internetradioTimerKey);

    if (timer)
        [timer invalidate];

    objc_setAssociatedObject(self,
                             &internetradioTimerKey,
                             nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    NSLog(@"Radio: popped");

    IMP superIMP = RadioControllerSuper(cmd);

    if (superIMP)
        ((void(*)(id,SEL))superIMP)(self, cmd);
}

static void RadioControllerDealloc(id self, SEL cmd)
{
    NSTimer *timer =
        (NSTimer *)objc_getAssociatedObject(self, &internetradioTimerKey);

    if (timer)
        [timer invalidate];

    objc_setAssociatedObject(self,
                             &internetradioTimerKey,
                             nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    IMP superIMP = RadioControllerSuper(cmd);

    if (superIMP)
        ((void(*)(id,SEL))superIMP)(self, cmd);
}

static void RadioPageLoader(id self,SEL cmd,id unused) {(void)cmd;(void)unused;RadioLoadBackground(self);}
static BOOL RadioEventInteger(id event,NSString *selector,NSInteger *out) {
    SEL sel=NSSelectorFromString(selector);
    if (![event respondsToSelector:sel])return NO;
    NSMethodSignature *sig=[event methodSignatureForSelector:sel];
    if (!sig || [sig numberOfArguments]!=2)return NO;
    NSInvocation *inv=[NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:event];[inv setSelector:sel];[inv invoke];
    int value=0;[inv getReturnValue:&value];*out=value;return YES;
}
static void RadioChoose(id controller) {
    if ([radioPage isEqual:@"Home"]) {
        NSArray *pages=@[@"Stations",@"Countries",@"Genres",@"Search",@"Favorites",@"Recent"];
        NSInteger i=radioSelected;if (i<0||i>5)return;
        radioPage=[pages objectAtIndex:i];radioSelected=0;
        if (i==3) {radioPage=@"Search";radioSearchText=[NSMutableString new];radioLetterIndex=0;radioStatus=RadioL(@"请选择字母", @"Choose a letter");}
        else RadioLoad(controller);
    } else if ([radioPage isEqual:@"Search"]) {
        if (!radioSearchText)radioSearchText=[NSMutableString new];
        [radioSearchText appendString:[radioAlphabet substringWithRange:NSMakeRange(radioLetterIndex,1)]];
    } else if ([radioPage isEqual:@"Countries"] || [radioPage isEqual:@"Genres"]) {
        if (radioSelected>=(NSInteger)[radioRows count])return;
        NSDictionary *item=[radioRows objectAtIndex:radioSelected];
        if ([radioPage isEqual:@"Countries"])radioCountry=[[item objectForKey:@"iso_3166_1"] copy];
        else radioTag=[[item objectForKey:@"name"] copy];
        radioPage=@"Stations";RadioLoad(controller);
    } else if ([radioPage isEqual:@"Stations"]||[radioPage isEqual:@"Favorites"]||[radioPage isEqual:@"Recent"]) {
        if (radioSelected>=(NSInteger)[radioRows count])return;
        NSDictionary *item=[radioRows objectAtIndex:radioSelected];
        radioLastStationPage=radioPage;radioLastStationIndex=radioSelected;
        radioRetryCount=0;radioNextRetry=0;
        RadioPlayStation(controller,item);
    }
}
static void RadioRecordPlayed(id self,SEL cmd,id station) {(void)self;(void)cmd;NSAutoreleasePool *pool=[[NSAutoreleasePool alloc]init];RadioRecord(@"played",station);[pool drain];}
static void RadioRecordFavorite(id self,SEL cmd,id station) {(void)self;(void)cmd;NSAutoreleasePool *pool=[[NSAutoreleasePool alloc]init];RadioRecord(@"favorite",station);[pool drain];}
/* Let native BackRow own Menu/navigation. */

static BOOL RadioEvent(id self, SEL cmd, id event)
{
    NSInteger action=0,value=0,origin=0;
    if (RadioEventInteger(event,@"originator",&origin)&&origin==1&&RadioEventInteger(event,@"remoteAction",&action)&&RadioEventInteger(event,@"value",&value)&&value==1) {
        if ((action==22||action==23||action==24) && radioPlayer) {
            radioPaused=!radioPaused;
            if (radioPaused)[radioPlayer pause];else [radioPlayer play];
            radioStatus=radioPaused?RadioL(@"已暂停", @"Paused"):RadioL(@"正在播放", @"Playing");
        }
        else if ([radioPage isEqual:@"Search"] && (action==3||action==4)) {NSInteger count=[radioAlphabet length];radioLetterIndex=(radioLetterIndex+(action==3?-1:1)+count)%count;}
        else if (action==3||action==4) {
            NSInteger max=[radioPage isEqual:@"Home"]?6:(NSInteger)[radioRows count];
            if (max>0)radioSelected=(radioSelected+(action==3?-1:1)+max)%max;
        } else if (action==5)RadioChoose(self);
        else if (action==6) {
            if ([radioPage isEqual:@"Search"] && radioSearchText.length)[radioSearchText deleteCharactersInRange:NSMakeRange(radioSearchText.length-1,1)];
            else {radioPage=@"Home";radioSelected=0;radioCountry=nil;radioTag=nil;radioQuery=nil;}
        }
        else if (action==7 && [radioPage isEqual:@"Search"] && radioSearchText.length) {radioQuery=[radioSearchText copy];radioPage=@"Stations";RadioLoad(self);}
        else if (action==7 && radioPlayingStation) {
            NSDictionary *favoriteStation=([radioPage isEqual:@"Stations"]||[radioPage isEqual:@"Favorites"]||[radioPage isEqual:@"Recent"]) && radioSelected<(NSInteger)[radioRows count]?[radioRows objectAtIndex:radioSelected]:radioPlayingStation;
            [NSThread detachNewThreadSelector:NSSelectorFromString(@"internetradioRecordFavorite:") toTarget:self withObject:favoriteStation];
            radioStatus=RadioL(@"正在更新收藏…", @"Updating favorites...");
        }
        else if (action==1 || action==2) {
            if (![radioPage isEqual:@"Home"]) {radioPage=@"Home";radioSelected=0;RadioRefresh(self,NULL);return YES;}
            /* Root Menu must be passed to BackRow's native navigation handler.
               Never swallow it with a successful return from this override. */
            Class cls=objc_getClass("RadioController");
            Class base=cls?class_getSuperclass(cls):Nil;
            Method method=base?class_getInstanceMethod(base,cmd):NULL;
            return method?((BOOL(*)(id,SEL,id))method_getImplementation(method))(self,cmd,event):NO;
        }
        else return NO;
        RadioRefresh(self,NULL);return YES;
    }
    Class cls=objc_getClass("RadioController");Class base=cls?class_getSuperclass(cls):Nil;
    Method method=base?class_getInstanceMethod(base,cmd):NULL;
    return method?((BOOL(*)(id,SEL,id))method_getImplementation(method))(self,cmd,event):NO;
}

/* ---------------------------------------------------------
   Appliance information
   --------------------------------------------------------- */

static NSString *RadioMenuIconURLForResolution(NSInteger resolution)
{
    NSBundle *bundle = [NSBundle bundleWithIdentifier:@"org.atv3.internetradio"];
    NSString *name = (resolution >= 1080) ? @"AppIcon@1080" : @"AppIcon";
    NSString *path = [bundle pathForResource:name ofType:@"png"];
    if (![path length])
        path = (resolution >= 1080) ? @"/Applications/Radio.frappliance/AppIcon@1080.png" : @"/Applications/Radio.frappliance/AppIcon.png";
    return [[NSURL fileURLWithPath:path] absoluteString];
}

static NSString *RadioMenuIconURL(void)
{
    return RadioMenuIconURLForResolution(1080);
}

static id RadioInfoMenuIconURLs(id self, SEL cmd)
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
            @"/var/tmp/internetradio_icon_probe.log"];

    if (!probe) {
        [[NSData data] writeToFile:
            @"/var/tmp/internetradio_icon_probe.log"
            atomically:YES];

        probe =
            [NSFileHandle fileHandleForWritingAtPath:
                @"/var/tmp/internetradio_icon_probe.log"];
    }

    if (probe) {
        [probe seekToEndOfFile];
        [probe writeData:
            [probeLine dataUsingEncoding:NSUTF8StringEncoding]];
        [probe closeFile];
    }

    NSString *url = RadioMenuIconURLForResolution(720);
    if (![url length]) return @{};
    return @{
        @"720": url, @"1080": url,
        [NSNumber numberWithInteger:720]: url,
        [NSNumber numberWithInteger:1080]: url
    };
}

static id RadioInfoMenuIconURLVersion(id self, SEL cmd)
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
            @"/var/tmp/internetradio_icon_probe.log"];

    if (!probe) {
        [[NSData data] writeToFile:
            @"/var/tmp/internetradio_icon_probe.log"
            atomically:YES];

        probe =
            [NSFileHandle fileHandleForWritingAtPath:
                @"/var/tmp/internetradio_icon_probe.log"];
    }

    if (probe) {
        [probe seekToEndOfFile];
        [probe writeData:
            [probeLine dataUsingEncoding:NSUTF8StringEncoding]];
        [probe closeFile];
    }

    NSBundle *bundle =
        [NSBundle bundleWithIdentifier:@"org.atv3.internetradio"];

    id version =
        [bundle objectForInfoDictionaryKey:@"CFBundleVersion"];

    return [version isKindOfClass:[NSString class]] &&
           [version length] ? version : @"1";
}

static Class RadioApplianceInfoClass(void)
{
    Class existing =
        objc_getClass("RadioApplianceInfo");

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
            "RadioApplianceInfo",
            0);

    if (!cls)
        return Nil;

    BOOL ok =
        class_addMethod(
            cls,
            NSSelectorFromString(@"menuIconURLs"),
            (IMP)RadioInfoMenuIconURLs,
            method_getTypeEncoding(urlsMethod))
        &&
        class_addMethod(
            cls,
            NSSelectorFromString(@"menuIconURLVersion"),
            (IMP)RadioInfoMenuIconURLVersion,
            method_getTypeEncoding(versionMethod));

    if (!ok) {
        objc_disposeClassPair(cls);
        return Nil;
    }

    objc_registerClassPair(cls);

    return cls;
}

static id RadioSyntheticApplianceInfo(void)
{
    Class infoClass =
        RadioApplianceInfoClass();

    if (!infoClass)
        return nil;

    id info = [infoClass alloc];

    SEL init =
        NSSelectorFromString(@"_initWithMutableDictionary:");

    if (!RadioSignature(info,
                        init,
                        @encode(id),
                        @[@"@"])) {
        [info release];
        return nil;
    }

    NSMutableDictionary *values =
        [NSMutableDictionary dictionary];

    [values setObject:@"internetradio"
               forKey:@"FRApplianceIdentifier"];

    [values setObject:RadioL(@"网络电台", @"Internet Radio")
               forKey:@"FRApplianceName"];

    [values setObject:@6
               forKey:@"FRAppliancePreferedOrderValue"];

    [values setObject:@"RadioAppliance"
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

static id RadioApplianceInit(id self,
                             SEL cmd,
                             id incoming)
{
    id info =
        incoming ?: RadioSyntheticApplianceInfo();

    IMP superIMP =
        RadioApplianceSuper(cmd);

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

static BOOL RadioCategoryAvailable(void)
{
    return RadioSignature(
        objc_getClass("BRApplianceCategory"),
        NSSelectorFromString(
            @"categoryWithName:identifier:preferredOrder:"),
        @encode(id),
        @[@"@", @"@", @"f"]);
}

static id RadioCategories(id self, SEL cmd)
{
    (void)self;
    (void)cmd;

    if (!RadioCategoryAvailable()) {
        NSLog(@"Radio: category ABI unavailable");
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

    id name = @"Radio";
    id identifier = @"internetradio";
    float order = 0.0f;

    [invocation setArgument:&name atIndex:2];
    [invocation setArgument:&identifier atIndex:3];
    [invocation setArgument:&order atIndex:4];

    [invocation invoke];

    id result = nil;

    [invocation getReturnValue:&result];

    return result ? @[result] : @[];
}

static id RadioControllerForIdentifier(id self,
                                       SEL cmd,
                                       id identifier,
                                       id args)
{
    (void)self;
    (void)cmd;
    (void)args;

    if (![identifier isEqual:@"internetradio"])
        return nil;

    return [RadioNew(
        objc_getClass("RadioController"))
        autorelease];
}

static id RadioApplianceController(id self,
                                   SEL cmd)
{
    (void)self;
    (void)cmd;

    return [RadioNew(
        objc_getClass("RadioController"))
        autorelease];
}

/* ---------------------------------------------------------
   Beigelist legacy root bridge
   --------------------------------------------------------- */

static IMP internetradioOriginalLegacyRootController = NULL;

static BOOL RadioIsLegacyMerchant(id self)
{
    id info =
        RadioObject(self, @"info");

    id merchantID =
        RadioObject(info, @"merchantID");

    if ([merchantID isKindOfClass:[NSString class]] &&
        [merchantID isEqualToString:@"org.atv3.internetradio"])
        return YES;

    id identifier =
        RadioObject(self, @"identifier");

    if ([identifier isKindOfClass:[NSString class]] &&
        ([identifier isEqualToString:@"org.atv3.internetradio"] ||
         [identifier isEqualToString:
             @"merchant.org.atv3.internetradio"]))
        return YES;

    id legacyClass =
        RadioObject(self, @"legacyApplianceClass");

    return legacyClass ==
        objc_getClass("RadioAppliance");
}

static id RadioLegacyRootController(id self,
                                    SEL cmd)
{
    if (RadioIsLegacyMerchant(self)) {

        id controller =
            [RadioNew(
                objc_getClass("RadioController"))
                autorelease];

        if (controller)
            return controller;
    }

    return internetradioOriginalLegacyRootController
        ? ((id(*)(id,SEL))
            internetradioOriginalLegacyRootController)(
                self,
                cmd)
        : nil;
}

static BOOL RadioInstallLegacyRootBridge(void)
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
        (IMP)RadioLegacyRootController)
        return YES;

    internetradioOriginalLegacyRootController =
        current;

    if (class_addMethod(
            cls,
            sel,
            (IMP)RadioLegacyRootController,
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

        internetradioOriginalLegacyRootController =
            NULL;

        return NO;
    }

    internetradioOriginalLegacyRootController =
        method_setImplementation(
            method,
            (IMP)RadioLegacyRootController);

    return
        internetradioOriginalLegacyRootController != NULL;
}

/* ---------------------------------------------------------
   BLAppMerchantInfo icon compatibility bridge
   --------------------------------------------------------- */


/* ---------------------------------------------------------
   Dynamic Home Screen Radio Icon
   188x108 canvas, centered 92x92 internetradio face
   --------------------------------------------------------- */

static NSString *RadioDynamicIconPath(void)
{
    NSDateFormatter *formatter =
        [[[NSDateFormatter alloc] init] autorelease];

    [formatter setDateFormat:@"yyyyMMddHHmmss"];

    NSString *stamp =
        [formatter stringFromDate:[NSDate date]];

    return [NSString stringWithFormat:
        @"/var/tmp/RadioDynamicIcon-%@.png",
        stamp];
}

static BOOL RadioRenderDynamicHomeIcon(void)
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

    /* Light internetradio face. */
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
        @"/var/tmp/internetradio_dynamic_time.log"
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
        RadioDynamicIconPath();

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

static NSString *RadioDynamicIconURL(void)
{
    if (RadioRenderDynamicHomeIcon()) {
        return [[NSURL fileURLWithPath:
            RadioDynamicIconPath()]
            absoluteString];
    }

    /* Stable 0.1.3 icon is always the fallback. */
    return RadioMenuIconURL();
}

static NSString *RadioDynamicIconVersion(void)
{
    NSDateFormatter *formatter =
        [[[NSDateFormatter alloc] init]
            autorelease];

    [formatter setDateFormat:
        @"yyyyMMddHHmmss"];

    return [formatter stringFromDate:
        [NSDate date]];
}


static void RadioProbeMerchantCoordinatorClass(void)
{
    Class cls = objc_getClass("ATVMerchantCoordinator");
    FILE *fp = fopen("/var/tmp/internetradio_coordinator_class.txt", "w");
    if (!fp) return;
    if (!cls) { fprintf(fp, "NOT FOUND\n"); fclose(fp); return; }
    unsigned int n = 0;
    Method *ms = class_copyMethodList(object_getClass(cls), &n);
    for (unsigned int i=0; i<n; i++)
        fprintf(fp, "%s | %s\n", sel_getName(method_getName(ms[i])), method_getTypeEncoding(ms[i]));
    if (ms) free(ms);
    fclose(fp);
}


static void RadioPulseMerchantCoordinator(void)
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
    id merchant = ((id(*)(id,SEL,id))objc_msgSend)(coordinator, merchantSel, @"org.atv3.internetradio");
    if (merchant)
        ((void(*)(id,SEL,id))objc_msgSend)(coordinator, changedSel, merchant);
}

static void RadioHomeIconTimerFire(id self, SEL cmd, NSTimer *timer)
{
    (void)self; (void)cmd; (void)timer;
    RadioPulseMerchantCoordinator();
}

static void RadioStartHomeIconTimer(void)
{
    static NSTimer *timer = nil;
    if (timer) return;
    Class timerClass = objc_getClass("RadioHomeIconTimerTarget");
    if (!timerClass) {
        timerClass = objc_allocateClassPair([NSObject class], "RadioHomeIconTimerTarget", 0);
        if (!timerClass) return;
        class_addMethod(timerClass, NSSelectorFromString(@"fire:"), (IMP)RadioHomeIconTimerFire, "v@:@");
        objc_registerClassPair(timerClass);
    }
    static id target = nil;
    if (!target) target = [[timerClass alloc] init];
    timer = [[NSTimer scheduledTimerWithTimeInterval:5.0
                                              target:target
                                            selector:NSSelectorFromString(@"fire:")
                                            userInfo:nil
                                             repeats:YES] retain];
}

static IMP internetradioSuperMerchantInfoValueForKey = NULL;

static BOOL RadioIsMerchantInfo(id self)
{
    id merchantID =
        RadioObject(self, @"merchantID");

    return
        [merchantID isKindOfClass:[NSString class]] &&
        [merchantID isEqualToString:@"org.atv3.internetradio"];
}

static id RadioMerchantInfoValueForKey(id self, SEL cmd, id key)
{
    if ([key isKindOfClass:[NSString class]] && RadioIsMerchantInfo(self)) {
        if ([key isEqualToString:@"menu-icon-url"]) {
            NSString *url = RadioMenuIconURLForResolution(720);
            if (![url length]) return nil;
            return @{
                @"720": url, @"1080": url,
                [NSNumber numberWithInteger:720]: url,
                [NSNumber numberWithInteger:1080]: url
            };
        }
        if ([key isEqualToString:@"menu-icon-url-version"]) {
            NSBundle *bundle = [NSBundle bundleWithIdentifier:@"org.atv3.internetradio"];
            id version = [bundle objectForInfoDictionaryKey:@"CFBundleVersion"];
            return ([version isKindOfClass:[NSString class]] && [version length]) ? version : @"1";
        }
    }
    return internetradioSuperMerchantInfoValueForKey
        ? ((id(*)(id,SEL,id))internetradioSuperMerchantInfoValueForKey)(self,cmd,key)
        : nil;
}

static BOOL RadioInstallMerchantInfoBridge(void)
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

    /* Multiple third-party appliances share BLAppMerchantInfo in the same
       AppleTV process. Chain the implementation that is active right now
       instead of assuming we are the first appliance to install a bridge. */
    IMP current = method_getImplementation(inherited);
    if (!current || current == (IMP)RadioMerchantInfoValueForKey)
        return current == (IMP)RadioMerchantInfoValueForKey;

    internetradioSuperMerchantInfoValueForKey = current;
    method_setImplementation(inherited, (IMP)RadioMerchantInfoValueForKey);
    return YES;
}

/* ---------------------------------------------------------
   Runtime class registration
   --------------------------------------------------------- */

static BOOL RadioAddOverride(Class cls,
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
        NSLog(@"Radio: missing %@", name);
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


static void RadioDumpRuntimeClass(FILE *fp, const char *name)
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

static void RadioDumpRuntime(void)
{
    FILE *fp = fopen("/var/tmp/internetradio_runtime.txt", "w");

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
        RadioDumpRuntimeClass(fp, classes[i]);

    fflush(fp);
    fclose(fp);
}


static void RadioDumpHomeIconRuntime(void)
{
    FILE *fp =
        fopen("/var/tmp/internetradio_home_icon_runtime.txt", "w");

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


BOOL RadioRegisterBackRowClasses(void)
{
    RadioProbeMerchantCoordinatorClass();
    RadioDumpHomeIconRuntime();
    RadioDumpRuntime();
    if (objc_getClass("RadioAppliance")) {
        RadioInstallLegacyRootBridge();
        return YES;
    }

    if (!RadioCategoryAvailable()) {
        NSLog(@"Radio: category ABI unavailable");
        return NO;
    }

    Class applianceBase =
        objc_getClass("BRBaseAppliance");

    Class controllerBase =
        objc_getClass("BRController");

    if (!applianceBase ||
        !controllerBase) {

        NSLog(@"Radio: BackRow unavailable");
        return NO;
    }

    Class appliance =
        objc_allocateClassPair(
            applianceBase,
            "RadioAppliance",
            0);

    Class controller =
        objc_allocateClassPair(
            controllerBase,
            "RadioController",
            0);

    if (!appliance || !controller) {

        if (appliance)
            objc_disposeClassPair(appliance);

        if (controller)
            objc_disposeClassPair(controller);

        return NO;
    }

    BOOL ok =
        RadioAddOverride(
            appliance,
            @"initWithApplianceInfo:",
            (IMP)RadioApplianceInit,
            @encode(id),
            @[@"@"])
        &&
        RadioAddOverride(
            appliance,
            @"applianceCategories",
            (IMP)RadioCategories,
            @encode(id),
            @[])
        &&
        RadioAddOverride(
            appliance,
            @"controllerForIdentifier:args:",
            (IMP)RadioControllerForIdentifier,
            @encode(id),
            @[@"@", @"@"])
        &&
        RadioAddOverride(
            appliance,
            @"applianceController",
            (IMP)RadioApplianceController,
            @encode(id),
            @[])
        &&
        RadioAddOverride(
            controller,
            @"brEventAction:",
            (IMP)RadioEvent,
            @encode(BOOL),
            @[@"@"]);

    if (ok) {

        ok =
            RadioAddOverride(
                controller,
                @"init",
                (IMP)RadioControllerInit,
                @encode(id),
                @[])
            &&
            RadioAddOverride(
                controller,
                @"controlWasActivated",
                (IMP)RadioActivated,
                @encode(void),
                @[])
            &&
            RadioAddOverride(
                controller,
                @"controlWasDeactivated",
                (IMP)RadioDeactivated,
                @encode(void),
                @[])
            &&
            RadioAddOverride(
                controller,
                @"wasPopped",
                (IMP)RadioPopped,
                @encode(void),
                @[])
            &&
            RadioAddOverride(
                controller,
                @"dealloc",
                (IMP)RadioControllerDealloc,
                @encode(void),
                @[]);

    }

    if (!ok) {

        objc_disposeClassPair(appliance);
        objc_disposeClassPair(controller);

        NSLog(@"Radio: incompatible BackRow ABI");

        return NO;
    }

    /* Register controller first, same proven order as Jellyfin. */
    objc_registerClassPair(controller);
    objc_registerClassPair(appliance);

    RadioInstallMerchantInfoBridge();
    RadioInstallLegacyRootBridge();

    NSLog(@"Radio: BackRow classes registered");

    return YES;
}

/* Dynamic NSTimer target selector */
__attribute__((constructor))
static void RadioInstallTimerSelector(void)
{
    /* Installed after RadioController is dynamically created,
       so actual selector installation occurs lazily below. */
}

static void RadioEnsureTimerSelector(void)
{
    Class cls =
        objc_getClass("RadioController");

    if (!cls)
        return;

    SEL sel =
        NSSelectorFromString(@"internetradioTimerFire:");

    if (!class_getInstanceMethod(cls, sel)) {
        class_addMethod(cls,sel,(IMP)RadioTimerFire,"v@:@");
    }
    SEL fetchSel=NSSelectorFromString(@"internetradioBackgroundFetch:");
    if (!class_getInstanceMethod(cls,fetchSel)) {
        class_addMethod(cls,fetchSel,(IMP)RadioBackgroundFetch,"v@:@");
    }
    class_addMethod(cls,NSSelectorFromString(@"internetradioLoadPage:"),(IMP)RadioPageLoader,"v@:@");
    class_addMethod(cls,NSSelectorFromString(@"internetradioRecordPlayed:"),(IMP)RadioRecordPlayed,"v@:@");
    class_addMethod(cls,NSSelectorFromString(@"internetradioRecordFavorite:"),(IMP)RadioRecordFavorite,"v@:@");
    SEL applySel=NSSelectorFromString(@"internetradioApplyFreshData");
    if (!class_getInstanceMethod(cls,applySel)) {
        class_addMethod(cls,applySel,(IMP)RadioApplyFreshData,"v@:");
    }
}
