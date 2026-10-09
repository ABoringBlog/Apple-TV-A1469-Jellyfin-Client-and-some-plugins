#import "WeatherBackRow.h"

#import <objc/runtime.h>
#import <objc/message.h>
#include <stdio.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreText/CoreText.h>
#import <ImageIO/ImageIO.h>
#include <string.h>

#ifndef WEATHER_LANG_EN
#define WEATHER_LANG_EN 0
#endif

static NSString *WeatherLocalized(NSString *zh, NSString *en)
{
    return WEATHER_LANG_EN ? en : zh;
}

static char weatherTimerKey;

/* ---------------------------------------------------------
   Generic ABI helpers
   --------------------------------------------------------- */

static BOOL WeatherSignature(id target, SEL sel, const char *result, NSArray *args)
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

static id WeatherObject(id target, NSString *name)
{
    SEL sel = NSSelectorFromString(name);

    if (!WeatherSignature(target, sel, @encode(id), @[]))
        return nil;

    return ((id(*)(id,SEL))objc_msgSend)(target, sel);
}

static id WeatherNew(Class cls)
{
    if (!cls)
        return nil;

    return [[cls alloc] init];
}

static IMP WeatherControllerSuper(SEL selector)
{
    Class cls = objc_getClass("WeatherController");

    if (!cls)
        return NULL;

    Class base = class_getSuperclass(cls);

    return base ? class_getMethodImplementation(base, selector) : NULL;
}

static IMP WeatherApplianceSuper(SEL selector)
{
    Class cls = objc_getClass("WeatherAppliance");

    if (!cls)
        return NULL;

    Class base = class_getSuperclass(cls);

    return base ? class_getMethodImplementation(base, selector) : NULL;
}

/* ---------------------------------------------------------
   Weather display
   --------------------------------------------------------- */

static NSString *WeatherBridgeURLString(void)
{
    NSString *path = @"/var/root/.atv3-weather-bridge-url";
    NSString *value = [NSString stringWithContentsOfFile:path
                                               encoding:NSUTF8StringEncoding
                                                  error:NULL];
    if (![value isKindOfClass:[NSString class]]) return nil;
    value = [value stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (![value length]) return nil;
    NSURL *url = [NSURL URLWithString:value];
    NSString *scheme = [[url scheme] lowercaseString];
    if (!url || ![url host] ||
        !([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])) return nil;
    return value;
}

static NSDictionary *WeatherBridgeData(void)
{
    NSString *endpoint=WeatherBridgeURLString();
    if (![endpoint length]) return nil;
    NSURL *url=[NSURL URLWithString:endpoint];
    NSData *data=[NSData dataWithContentsOfURL:url];
    if (![data length]) return nil;
    id obj=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    return [obj isKindOfClass:[NSDictionary class]] ? obj : nil;
}

static NSDictionary *weatherCachedSnapshot = nil;
static NSTimeInterval weatherCachedAt = 0;
static BOOL weatherFetchInFlight = NO;

static NSString *WeatherCachePath(void)
{
    return @"/var/mobile/Library/Caches/org.atv3.weather.snapshot.json";
}

static void WeatherStoreSnapshot(NSDictionary *fresh)
{
    if (![fresh isKindOfClass:[NSDictionary class]]) return;
    @synchronized([NSObject class]) {
        [weatherCachedSnapshot release];
        weatherCachedSnapshot=[fresh retain];
        weatherCachedAt=[NSDate timeIntervalSinceReferenceDate];
    }
    NSData *data=[NSJSONSerialization dataWithJSONObject:fresh options:0 error:NULL];
    if ([data length]) [data writeToFile:WeatherCachePath() atomically:YES];
}

static NSDictionary *WeatherSnapshot(void)
{
    @synchronized([NSObject class]) {
        if (!weatherCachedSnapshot) {
            NSData *data=[NSData dataWithContentsOfFile:WeatherCachePath()];
            if ([data length]) {
                id obj=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
                if ([obj isKindOfClass:[NSDictionary class]]) weatherCachedSnapshot=[obj retain];
            }
        }
        return weatherCachedSnapshot;
    }
}

static void WeatherFetchAsync(id controller)
{
    @synchronized([NSObject class]) {
        if (weatherFetchInFlight) return;
        weatherFetchInFlight=YES;
    }
    [NSThread detachNewThreadSelector:NSSelectorFromString(@"weatherBackgroundFetch:")
                             toTarget:controller withObject:nil];
}

static NSString *WeatherConditionMark(NSNumber *code, NSNumber *isDay)
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

static NSString *WeatherLocalizedCondition(NSInteger code);

static NSString *WeatherCurrentTime(void)
{
    NSDictionary *w = WeatherSnapshot();
    NSNumber *temp = [w objectForKey:@"temperature_c"];
    if (!w || !temp) return WeatherLocalized(@"天气不可用", @"Weather unavailable");
    NSInteger code=[[w objectForKey:@"weather_code"] integerValue];
    NSString *condition=WeatherLocalizedCondition(code);
    return [NSString stringWithFormat:@"%.0f C   %@", [temp doubleValue], condition ?: @""];
}

static NSString *WeatherCurrentDate(void)
{
    NSDictionary *w = WeatherSnapshot();
    if (!w) return @"ATV3Bridge offline";
    NSString *location = [w objectForKey:@"location"] ?: @"Weather";
    NSNumber *feels = [w objectForKey:@"feels_like_c"];
    NSNumber *humidity = [w objectForKey:@"humidity"];
    NSNumber *wind = [w objectForKey:@"wind_kmh"];
    return WEATHER_LANG_EN ? [NSString stringWithFormat:@"%@   Feels %.0f C   Humidity %.0f%%   Wind %.0f km/h", location, [feels doubleValue], [humidity doubleValue], [wind doubleValue]] : [NSString stringWithFormat:@"%@   体感 %.0f C   湿度 %.0f%%   风速 %.0f km/h", location, [feels doubleValue], [humidity doubleValue], [wind doubleValue]];
}

static NSString *WeatherHourLabel(NSString *iso)
{
    if (![iso isKindOfClass:[NSString class]] || [iso length] < 13) return @"--";
    NSInteger h = [[iso substringWithRange:NSMakeRange(11,2)] integerValue];
    return WEATHER_LANG_EN ? [NSString stringWithFormat:@"%02ld:00", (long)h] : [NSString stringWithFormat:@"%ld时", (long)h];
}

static NSString *WeatherDayLabel(NSString *iso)
{
    if (![iso isKindOfClass:[NSString class]] || [iso length] < 10) return @"---";
    NSInteger y=[[iso substringWithRange:NSMakeRange(0,4)] integerValue];
    NSInteger m=[[iso substringWithRange:NSMakeRange(5,2)] integerValue];
    NSInteger d=[[iso substringWithRange:NSMakeRange(8,2)] integerValue];
    if (m<3) { m+=12; y-=1; }
    NSInteger k=y%100, j=y/100;
    NSInteger h=(d+(13*(m+1))/5+k+k/4+j/4+5*j)%7;
    static NSString *daysZH[]={@"周六",@"周日",@"周一",@"周二",@"周三",@"周四",@"周五"}; static NSString *daysEN[]={@"Sat",@"Sun",@"Mon",@"Tue",@"Wed",@"Thu",@"Fri"};
    if (h<0 || h>6) return @"---";
    return WEATHER_LANG_EN ? daysEN[h] : daysZH[h];
}

static NSString *WeatherLocalizedCondition(NSInteger code)
{
    if (code==0) return WeatherLocalized(@"晴", @"Clear");
    if (code==1) return WeatherLocalized(@"大致晴朗", @"Mostly clear");
    if (code==2) return WeatherLocalized(@"局部多云", @"Partly cloudy");
    if (code==3) return WeatherLocalized(@"多云", @"Cloudy");
    if (code==45 || code==48) return WeatherLocalized(@"有雾", @"Fog");
    if (code>=51 && code<=57) return WeatherLocalized(@"毛毛雨", @"Drizzle");
    if (code>=61 && code<=67) return WeatherLocalized(@"有雨", @"Rain");
    if (code>=71 && code<=77) return WeatherLocalized(@"有雪", @"Snow");
    if (code>=80 && code<=82) return WeatherLocalized(@"阵雨", @"Showers");
    if (code==85 || code==86) return WeatherLocalized(@"阵雪", @"Snow showers");
    if (code>=95) return WeatherLocalized(@"雷暴", @"Thunderstorm");
    return WeatherLocalized(@"天气", @"Weather");
}

static NSString *WeatherHourlySummary(void)
{
    NSDictionary *w=WeatherSnapshot(); NSArray *a=[w objectForKey:@"hourly"];
    if (![a isKindOfClass:[NSArray class]] || ![a count]) return @"";
    NSString *updated=[w objectForKey:@"updated"]; NSUInteger start=0;
    if ([updated isKindOfClass:[NSString class]] && [updated length]>=13) {
        NSString *hour=[updated substringToIndex:13];
        for (NSUInteger i=0;i<[a count];i++) { NSString *t=[[a objectAtIndex:i] objectForKey:@"time"]; if ([t hasPrefix:hour]) { start=i; break; } }
    }
    NSMutableArray *heads=[NSMutableArray array], *temps=[NSMutableArray array], *details=[NSMutableArray array];
    for (NSUInteger j=0;j<6 && start+j<[a count];j++) {
        NSDictionary *x=[a objectAtIndex:start+j];
        NSString *label=j==0?WeatherLocalized(@"现在", @"Now"):WeatherHourLabel([x objectForKey:@"time"]);
        NSString *cond=WeatherLocalizedCondition([[x objectForKey:@"weather_code"] integerValue]);
        [heads addObject:[NSString stringWithFormat:@"%@ %@",label,cond]];
        [temps addObject:[NSString stringWithFormat:@"%.0f°",[[x objectForKey:@"temperature_2m"] doubleValue]]];
        [details addObject:[NSString stringWithFormat:WeatherLocalized(@"雨%.0f%%  风%.0f", @"Rain %.0f%%  Wind %.0f"),[[x objectForKey:@"precipitation_probability"] doubleValue],[[x objectForKey:@"wind_speed_10m"] doubleValue]]];
    }
    return [NSString stringWithFormat:@"%@\n%@\n%@",[heads componentsJoinedByString:@"      "],[temps componentsJoinedByString:@"             "],[details componentsJoinedByString:@"        "]];
}

static NSString *WeatherDailySummary(void)
{
    NSDictionary *w=WeatherSnapshot(); NSArray *a=[w objectForKey:@"daily"];
    if (![a isKindOfClass:[NSArray class]] || ![a count]) return @"";
    NSMutableArray *heads=[NSMutableArray array], *temps=[NSMutableArray array], *details=[NSMutableArray array];
    for (NSUInteger i=0;i<7 && i<[a count];i++) {
        NSDictionary *x=[a objectAtIndex:i];
        NSString *label=i==0?WeatherLocalized(@"今天", @"Today"):WeatherDayLabel([x objectForKey:@"time"]);
        NSString *cond=WeatherLocalizedCondition([[x objectForKey:@"weather_code"] integerValue]);
        [heads addObject:[NSString stringWithFormat:@"%@ %@",label,cond]];
        [temps addObject:[NSString stringWithFormat:@"%.0f°/%.0f°",[[x objectForKey:@"temperature_2m_max"] doubleValue],[[x objectForKey:@"temperature_2m_min"] doubleValue]]];
        [details addObject:[NSString stringWithFormat:WeatherLocalized(@"雨%.0f%%", @"Rain %.0f%%"),[[x objectForKey:@"precipitation_probability_max"] doubleValue]]];
    }
    return [NSString stringWithFormat:@"%@\n%@\n%@",[heads componentsJoinedByString:@"    "],[temps componentsJoinedByString:@"       "],[details componentsJoinedByString:@"          "]];
}

static void WeatherRoundedRect(CGContextRef c, CGRect r, CGFloat radius)
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

static CTFontRef WeatherCTFont(CGFloat size)
{
    CTFontRef font=CTFontCreateWithName(CFSTR("STHeitiSC-Light"),size,NULL);
    if (!font) font=CTFontCreateWithName(CFSTR("STHeiti-Light"),size,NULL);
    if (!font) font=CTFontCreateWithName(CFSTR("STHeitiSC-Medium"),size,NULL);
    if (!font) font=CTFontCreateWithName(CFSTR("STHeiti-Medium"),size,NULL);
    if (!font) font=CTFontCreateWithName(CFSTR("HelveticaNeue"),size,NULL);
    return font;
}

static CTLineRef WeatherCTLine(NSString *text, CGFloat size, CGFloat gray)
{
    if (![text length]) return NULL;
    CTFontRef font=WeatherCTFont(size);
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

static void WeatherText(CGContextRef c, NSString *text, CGFloat x, CGFloat y, CGFloat size, CGFloat gray)
{
    CTLineRef line=WeatherCTLine(text,size,gray);
    if (!line) return;
    CGContextSaveGState(c);
    CGContextSetTextMatrix(c,CGAffineTransformIdentity);
    CGContextSetTextPosition(c,x,y);
    CTLineDraw(line,c);
    CGContextRestoreGState(c);
    CFRelease(line);
}

static CGFloat WeatherTextWidth(NSString *text, CGFloat size)
{
    CTLineRef line=WeatherCTLine(text,size,1.0f);
    if (!line) return 0.0f;
    double width=CTLineGetTypographicBounds(line,NULL,NULL,NULL);
    CFRelease(line);
    return (CGFloat)width;
}

static void WeatherCenteredText(CGContextRef c, NSString *text, CGFloat centerX,
                                CGFloat y, CGFloat size, CGFloat gray)
{
    WeatherText(c,text,centerX-WeatherTextWidth(text,size)*0.5f,y,size,gray);
}

static CGFloat WeatherIconVisualCenter(NSInteger code, CGFloat scale)
{
    BOOL rain=((code>=51&&code<=67)||(code>=80&&code<=82));
    BOOL snow=((code>=71&&code<=77)||code==85||code==86);
    BOOL storm=(code>=95);
    BOOL fog=(code==45||code==48);
    BOOL cloudy=(code>=1&&code<=3)||rain||snow||storm||fog;
    if (cloudy) return 75.0f*scale;
    return 37.0f*scale;
}

static void WeatherIcon(CGContextRef c, NSInteger code, BOOL day, CGFloat x, CGFloat y, CGFloat scale)
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

static NSData *WeatherRenderImage(void)
{
    const size_t width=1280,height=720;
    CGColorSpaceRef cs=CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx=CGBitmapContextCreate(NULL,width,height,8,width*4,cs,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(cs); if(!ctx) return nil;

    /* Deep blue Apple-Weather-like background. */
    CGFloat comps[8]={0.06,0.18,0.34,1.0, 0.12,0.39,0.66,1.0};
    CGFloat locs[2]={0.0,1.0};
    CGColorSpaceRef gcs=CGColorSpaceCreateDeviceRGB();
    CGGradientRef grad=CGGradientCreateWithColorComponents(gcs,comps,locs,2);
    CGContextDrawLinearGradient(ctx,grad,CGPointMake(0,0),CGPointMake(0,720),0);
    CGGradientRelease(grad); CGColorSpaceRelease(gcs);

    NSDictionary *w=WeatherSnapshot();
    NSString *loc=[w objectForKey:@"location"] ?: @"Weather";
    NSNumber *temp=[w objectForKey:@"temperature_c"];
    NSNumber *feels=[w objectForKey:@"feels_like_c"];
    NSNumber *hum=[w objectForKey:@"humidity"];
    NSNumber *wind=[w objectForKey:@"wind_kmh"];
    NSInteger code=[[w objectForKey:@"weather_code"] integerValue];
    BOOL day=[[w objectForKey:@"is_day"] boolValue];
    NSString *cond=WeatherLocalizedCondition(code);

    WeatherText(ctx,loc,72,650,34,1.0);
    CGContextSaveGState(ctx);
    CGContextTranslateCTM(ctx,0.0f,2.0f*(485.0f+55.0f*1.15f));
    CGContextScaleCTM(ctx,1.0f,-1.0f);
    WeatherIcon(ctx,code,day,70,485,1.15);
    CGContextRestoreGState(ctx);
    WeatherText(ctx,[NSString stringWithFormat:@"%.0f C",[temp doubleValue]],235,535,92,1.0);
    WeatherText(ctx,cond,240,495,31,0.92);
    WeatherText(ctx,WEATHER_LANG_EN ? [NSString stringWithFormat:@"Feels %.0f C   Humidity %.0f%%   Wind %.0f km/h",[feels doubleValue],[hum doubleValue],[wind doubleValue]] : [NSString stringWithFormat:@"体感 %.0f C   湿度 %.0f%%   风速 %.0f km/h",[feels doubleValue],[hum doubleValue],[wind doubleValue]],74,445,25,0.86);
    NSArray *daily=[w objectForKey:@"daily"];
    if ([daily count]) {
        NSDictionary *today=[daily objectAtIndex:0];
        NSString *sunrise=[today objectForKey:@"sunrise"];
        NSString *sunset=[today objectForKey:@"sunset"];
        NSString *rise=([sunrise length]>=16)?[sunrise substringWithRange:NSMakeRange(11,5)]:@"--:--";
        NSString *set=([sunset length]>=16)?[sunset substringWithRange:NSMakeRange(11,5)]:@"--:--";
        WeatherText(ctx,[NSString stringWithFormat:WeatherLocalized(@"日出 %@   日落 %@", @"Sunrise %@   Sunset %@"),rise,set],760,445,22,0.82);
    }

    /* Hourly card */
    CGContextSetRGBFillColor(ctx,1,1,1,0.11); WeatherRoundedRect(ctx,CGRectMake(58,238,1164,177),24); CGContextFillPath(ctx);
    WeatherText(ctx,WeatherLocalized(@"每小时天气", @"Hourly Forecast"),82,385,18,0.82);
    NSArray *hourly=[w objectForKey:@"hourly"]; NSString *updated=[w objectForKey:@"updated"]; NSUInteger start=0;
    if ([updated length]>=13) { NSString *hh=[updated substringToIndex:13]; for(NSUInteger i=0;i<[hourly count];i++){ if([[[hourly objectAtIndex:i] objectForKey:@"time"] hasPrefix:hh]){start=i;break;} } }
    for(NSUInteger j=0;j<6 && start+j<[hourly count];j++){
        NSDictionary *x=[hourly objectAtIndex:start+j];
        /* Six equal-width columns across the full card content area.
           Every element in one column uses this exact center X. */
        const CGFloat left=76.0f, right=1204.0f;
        const CGFloat colW=(right-left)/6.0f;
        CGFloat cx=left+(j+0.5f)*colW;
        NSString *label=j==0?WeatherLocalized(@"现在", @"Now"):WeatherHourLabel([x objectForKey:@"time"]);
        NSString *tempText=[NSString stringWithFormat:@"%.0f C",[[x objectForKey:@"temperature_2m"] doubleValue]];
        NSString *rainText=[NSString stringWithFormat:@"%.0f%%",[[x objectForKey:@"precipitation_probability"] doubleValue]];
        NSString *detailText=WEATHER_LANG_EN ? [NSString stringWithFormat:@"Feels %.0f° Wind %.0f",[[x objectForKey:@"apparent_temperature"] doubleValue],[[x objectForKey:@"wind_speed_10m"] doubleValue]] : [NSString stringWithFormat:@"体%.0f° 风%.0f",[[x objectForKey:@"apparent_temperature"] doubleValue],[[x objectForKey:@"wind_speed_10m"] doubleValue]];
        WeatherCenteredText(ctx,label,cx,350,21,1.0);
        NSInteger hcode=[[x objectForKey:@"weather_code"] integerValue];
        NSNumber *hourDay=[x objectForKey:@"is_day"];
        BOOL hday=hourDay ? [hourDay boolValue] : day;
        CGContextSaveGState(ctx);
        CGContextTranslateCTM(ctx,0.0f,2.0f*(285.0f+55.0f*0.48f));
        CGContextScaleCTM(ctx,1.0f,-1.0f);
        WeatherIcon(ctx,hcode,hday,cx-WeatherIconVisualCenter(hcode,0.48f),285,0.48);
        CGContextRestoreGState(ctx);
        WeatherCenteredText(ctx,tempText,cx,270,23,1.0);
        WeatherCenteredText(ctx,rainText,cx,252,13,0.78);
        WeatherCenteredText(ctx,detailText,cx,239,11,0.68);
    }

    /* Daily card */
    CGContextSetRGBFillColor(ctx,1,1,1,0.11); WeatherRoundedRect(ctx,CGRectMake(58,40,1164,185),24); CGContextFillPath(ctx);
    WeatherText(ctx,WeatherLocalized(@"7天天气预报", @"7-Day Forecast"),82,195,18,0.82);
    for(NSUInteger i=0;i<7 && i<[daily count];i++){
        NSDictionary *x=[daily objectAtIndex:i];
        /* Seven equal-width columns; weekday, icon, temperature and
           precipitation all share one immutable vertical center axis. */
        const CGFloat left=72.0f, right=1208.0f;
        const CGFloat colW=(right-left)/7.0f;
        CGFloat cx=left+(i+0.5f)*colW;
        NSString *label=i==0?WeatherLocalized(@"今天", @"Today"):WeatherDayLabel([x objectForKey:@"time"]);
        NSString *tempText=[NSString stringWithFormat:@"%.0f / %.0f",[[x objectForKey:@"temperature_2m_max"] doubleValue],[[x objectForKey:@"temperature_2m_min"] doubleValue]];
        NSString *rainText=[NSString stringWithFormat:@"%.0f%%",[[x objectForKey:@"precipitation_probability_max"] doubleValue]];
        NSString *windText=[NSString stringWithFormat:WeatherLocalized(@"风%.0f", @"Wind %.0f"),[[x objectForKey:@"wind_speed_10m_max"] doubleValue]];
        WeatherCenteredText(ctx,label,cx,160,20,1.0);
        /* Flip only the daily icon around its own vertical center; the old
           daily rendering was visually upside-down on the ATV3. */
        NSInteger dcode=[[x objectForKey:@"weather_code"] integerValue];
        CGContextSaveGState(ctx);
        CGFloat iconCenterY=92.0f+55.0f*0.45f;
        CGContextTranslateCTM(ctx,0.0f,2.0f*iconCenterY);
        CGContextScaleCTM(ctx,1.0f,-1.0f);
        WeatherIcon(ctx,dcode,YES,cx-WeatherIconVisualCenter(dcode,0.45f),92,0.45);
        CGContextRestoreGState(ctx);
        WeatherCenteredText(ctx,tempText,cx,72,19,1.0);
        WeatherCenteredText(ctx,rainText,cx,53,13,0.75);
        WeatherCenteredText(ctx,windText,cx,42,10,0.65);
    }

    CGImageRef image=CGBitmapContextCreateImage(ctx); CGContextRelease(ctx); if(!image)return nil;
    NSMutableData *data=[NSMutableData data];
    CGImageDestinationRef dest=CGImageDestinationCreateWithData((CFMutableDataRef)data,CFSTR("public.jpeg"),1,NULL);
    if(!dest){CGImageRelease(image);return nil;} NSDictionary *options=@{(id)kCGImageDestinationLossyCompressionQuality:@(0.83)}; CGImageDestinationAddImage(dest,image,(CFDictionaryRef)options); BOOL ok=CGImageDestinationFinalize(dest); CFRelease(dest); CGImageRelease(image);
    return ok?data:nil;
}

static id WeatherCreateImageControl(void)
{
    NSData *data = WeatherRenderImage();

    if (![data length])
        return nil;

    Class imageClass = NSClassFromString(@"ATVImage");
    Class controlClass = NSClassFromString(@"BRAsyncImageControl");

    if (!imageClass || !controlClass)
        return nil;

    SEL imageSel = NSSelectorFromString(@"imageWithData:");

    if (!WeatherSignature(imageClass,
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

    id control = WeatherNew(controlClass);

    if (!control)
        return nil;

    SEL cropSel = NSSelectorFromString(@"setCropAndFill:");

    if (WeatherSignature(control,
                       cropSel,
                       @encode(void),
                       @[[NSString stringWithUTF8String:@encode(BOOL)]])) {

        ((void(*)(id,SEL,BOOL))objc_msgSend)(control,
                                             cropSel,
                                             NO);
    }

    SEL setImageSel = NSSelectorFromString(@"setImage:");

    if (!WeatherSignature(control,
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


static char WeatherImageControlKey;
static char WeatherNativeBackgroundKey;
static char WeatherCurrentIconKey;
static char WeatherHourlyIconsKey;
static char WeatherDailyIconsKey;
static char WeatherHourlyColumnsKey;
static char WeatherDailyColumnsKey;

static id WeatherMakeATVImage(void)
{
    NSData *data = WeatherRenderImage();

    if (![data length])
        return nil;

    Class imageClass = NSClassFromString(@"ATVImage");

    if (!imageClass)
        return nil;

    SEL sel = NSSelectorFromString(@"imageWithData:");

    if (!WeatherSignature(imageClass,
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
static BOOL WeatherBackRowBounds(id host, CGRect *outBounds)
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

static BOOL WeatherBackRowSetFrame(id control, CGRect frame)
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

static id WeatherCreateFullscreenControl(id host)
{
    Class controlClass = NSClassFromString(@"BRImageControl");
    if (!controlClass) return nil;

    id control = WeatherNew(controlClass);
    if (!control) return nil;

    CGRect frame = CGRectZero;
    if (!WeatherBackRowBounds(host, &frame) ||
        !WeatherBackRowSetFrame(control, frame)) {
        [control release];
        return nil;
    }

    NSLog(@"Weather: BackRow-owned bounds %.0fx%.0f at %.0f,%.0f",
          frame.size.width, frame.size.height, frame.origin.x, frame.origin.y);

    return [control autorelease];
}

static void WeatherInstallFullscreenControl(id self)
{
    id control =
        objc_getAssociatedObject(
            self,
            &WeatherImageControlKey);

    if (control)
        return;

    control = WeatherCreateFullscreenControl(self);

    if (!control)
        return;

    objc_setAssociatedObject(
        self,
        &WeatherImageControlKey,
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

static void WeatherUpdateFullscreenControl(id self)
{
    WeatherInstallFullscreenControl(self);

    id control =
        objc_getAssociatedObject(
            self,
            &WeatherImageControlKey);

    if (!control)
        return;

    id image = WeatherMakeATVImage();

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


static char WeatherTimeTextKey;
static char WeatherDateTextKey;
static char WeatherHourlyTextKey;
static char WeatherDailyTextKey;
static char WeatherHourlyLabelKey;
static char WeatherDailyLabelKey;
static char WeatherLocationTextKey;
static char WeatherConditionTextKey;
static char WeatherDetailsTextKey;
static char WeatherSunTextKey;

static id WeatherObjectCall(id target, NSString *name)
{
    if (!target)
        return nil;

    SEL sel = NSSelectorFromString(name);

    if (![target respondsToSelector:sel])
        return nil;

    return ((id(*)(id,SEL))objc_msgSend)(target, sel);
}

static BOOL WeatherSetFrame(id control, CGRect frame)
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

static BOOL WeatherSetText(id control,
                         NSString *text,
                         id attrs)
{
    if (!control || !text)
        return NO;

    SEL sel =
        NSSelectorFromString(@"setText:withAttributes:");

    if (!WeatherSignature(control,
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

static id WeatherThemeTextAttributes(void)
{
    Class themeClass =
        NSClassFromString(@"BRThemeInfo");

    if (!themeClass)
        return @{};

    id theme =
        WeatherObjectCall(themeClass, @"sharedTheme");

    if (!theme)
        return @{};

    id attrs =
        WeatherObjectCall(theme,
                        @"menuTitleTextAttributes");

    static BOOL dumped = NO;

    if (!dumped) {
        dumped = YES;

        NSString *dump =
            [NSString stringWithFormat:
                @"class=%@\nattrs=%@\n",
                attrs ? NSStringFromClass([attrs class]) : @"nil",
                attrs ?: @"nil"];

        [dump writeToFile:@"/var/tmp/weather_text_attrs.txt"
               atomically:YES
                 encoding:NSUTF8StringEncoding
                    error:NULL];
    }

    return attrs ?: @{};
}

static id WeatherCreateTextControl(void)
{
    Class cls =
        NSClassFromString(@"BRTextControl");

    if (!cls)
        return nil;

    return [WeatherNew(cls) autorelease];
}

static void WeatherInstallNativeBackground(id self)
{
    if (objc_getAssociatedObject(self, &WeatherNativeBackgroundKey)) return;
    NSString *path=[[NSBundle bundleWithIdentifier:@"org.atv3.weather"] pathForResource:@"NativeBackground" ofType:@"png"];
    NSData *data=path ? [NSData dataWithContentsOfFile:path] : nil;
    Class imageClass=NSClassFromString(@"ATVImage");
    Class controlClass=NSClassFromString(@"BRImageControl");
    if (![data length] || !imageClass || !controlClass) return;
    SEL imageSel=NSSelectorFromString(@"imageWithData:");
    if (!WeatherSignature(imageClass,imageSel,@encode(id),@[@"@"])) return;
    id image=((id(*)(id,SEL,id))objc_msgSend)(imageClass,imageSel,data);
    id control=WeatherNew(controlClass);
    if (!image || !control) { [control release]; return; }
    SEL setImageSel=NSSelectorFromString(@"setImage:");
    if ([control respondsToSelector:setImageSel])
        ((void(*)(id,SEL,id))objc_msgSend)(control,setImageSel,image);
    CGRect frame=CGRectZero;
    if (!WeatherBackRowBounds(self,&frame) || !WeatherBackRowSetFrame(control,frame)) { [control release]; return; }
    SEL addSel=NSSelectorFromString(@"addSubview:");
    if ([self respondsToSelector:addSel]) ((void(*)(id,SEL,id))objc_msgSend)(self,addSel,control);
    objc_setAssociatedObject(self,&WeatherNativeBackgroundKey,control,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [control release];
}

static NSString *WeatherSmallIconName(NSInteger code)
{
    if (code>=95) return @"WeatherIconStorm";
    if ((code>=71 && code<=77) || code==85 || code==86) return @"WeatherIconSnow";
    if (code==45 || code==48) return @"WeatherIconFog";
    if ((code>=51 && code<=67) || (code>=80 && code<=82)) return @"WeatherIconRain";
    if (code>=1) return @"WeatherIconCloud";
    return @"WeatherIconSunny";
}

static void WeatherInstallCurrentIcon(id self)
{
    id old=objc_getAssociatedObject(self,&WeatherCurrentIconKey);
    if (old) return;
    NSDictionary *w=WeatherSnapshot();
    NSInteger code=[[w objectForKey:@"weather_code"] integerValue];
    NSString *path=[[NSBundle bundleWithIdentifier:@"org.atv3.weather"] pathForResource:WeatherSmallIconName(code) ofType:@"png"];
    NSData *data=path ? [NSData dataWithContentsOfFile:path] : nil;
    Class imageClass=NSClassFromString(@"ATVImage"), controlClass=NSClassFromString(@"BRImageControl");
    if (![data length] || !imageClass || !controlClass) return;
    SEL imageSel=NSSelectorFromString(@"imageWithData:");
    if (!WeatherSignature(imageClass,imageSel,@encode(id),@[@"@"])) return;
    id image=((id(*)(id,SEL,id))objc_msgSend)(imageClass,imageSel,data);
    id control=WeatherNew(controlClass);
    if (!image || !control) { [control release]; return; }
    SEL setImageSel=NSSelectorFromString(@"setImage:");
    if ([control respondsToSelector:setImageSel]) ((void(*)(id,SEL,id))objc_msgSend)(control,setImageSel,image);
    WeatherSetFrame(control,CGRectMake(70.0f,485.0f,132.0f,132.0f));
    SEL addSel=NSSelectorFromString(@"addSubview:");
    if ([self respondsToSelector:addSel]) ((void(*)(id,SEL,id))objc_msgSend)(self,addSel,control);
    objc_setAssociatedObject(self,&WeatherCurrentIconKey,control,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [control release];
}

static id WeatherSmallImageControl(NSString *name, CGRect frame)
{
    NSString *path=[[NSBundle bundleWithIdentifier:@"org.atv3.weather"] pathForResource:name ofType:@"png"];
    NSData *data=path ? [NSData dataWithContentsOfFile:path] : nil;
    Class imageClass=NSClassFromString(@"ATVImage"), controlClass=NSClassFromString(@"BRImageControl");
    if (![data length] || !imageClass || !controlClass) return nil;
    SEL imageSel=NSSelectorFromString(@"imageWithData:");
    if (!WeatherSignature(imageClass,imageSel,@encode(id),@[@"@"])) return nil;
    id image=((id(*)(id,SEL,id))objc_msgSend)(imageClass,imageSel,data);
    id control=WeatherNew(controlClass);
    if (!image || !control) { [control release]; return nil; }
    SEL setImageSel=NSSelectorFromString(@"setImage:");
    if ([control respondsToSelector:setImageSel]) ((void(*)(id,SEL,id))objc_msgSend)(control,setImageSel,image);
    WeatherSetFrame(control,frame);
    return [control autorelease];
}

static void WeatherInstallForecastIcons(id self)
{
    if (objc_getAssociatedObject(self,&WeatherHourlyIconsKey)) return;
    NSDictionary *w=WeatherSnapshot(); NSArray *hourly=[w objectForKey:@"hourly"], *daily=[w objectForKey:@"daily"];
    SEL addSel=NSSelectorFromString(@"addSubview:");
    if (![self respondsToSelector:addSel]) return;
    NSMutableArray *hs=[NSMutableArray array], *ds=[NSMutableArray array];
    NSUInteger start=0; NSString *updated=[w objectForKey:@"updated"];
    if ([updated isKindOfClass:[NSString class]] && [updated length]>=13) {
        NSString *hh=[updated substringToIndex:13];
        for(NSUInteger i=0;i<[hourly count];i++){ if([[[hourly objectAtIndex:i] objectForKey:@"time"] hasPrefix:hh]){start=i;break;} }
    }
    const CGFloat hleft=76.0f, hwidth=(1204.0f-76.0f)/6.0f;
    for(NSUInteger j=0;j<6 && start+j<[hourly count];j++){
        NSInteger code=[[[hourly objectAtIndex:start+j] objectForKey:@"weather_code"] integerValue];
        CGFloat cx=hleft+(j+0.5f)*hwidth;
        id c=WeatherSmallImageControl(WeatherSmallIconName(code),CGRectMake(cx-22.0f,285.0f,44.0f,44.0f));
        if(c){((void(*)(id,SEL,id))objc_msgSend)(self,addSel,c);[hs addObject:c];}
    }
    const CGFloat dleft=72.0f, dwidth=(1208.0f-72.0f)/7.0f;
    for(NSUInteger i=0;i<7 && i<[daily count];i++){
        NSInteger code=[[[daily objectAtIndex:i] objectForKey:@"weather_code"] integerValue];
        CGFloat cx=dleft+(i+0.5f)*dwidth;
        id c=WeatherSmallImageControl(WeatherSmallIconName(code),CGRectMake(cx-20.0f,92.0f,40.0f,40.0f));
        if(c){((void(*)(id,SEL,id))objc_msgSend)(self,addSel,c);[ds addObject:c];}
    }
    objc_setAssociatedObject(self,&WeatherHourlyIconsKey,hs,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self,&WeatherDailyIconsKey,ds,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static id WeatherColumnText(CGRect frame)
{
    id c=WeatherCreateTextControl();
    if (c) WeatherSetFrame(c,frame);
    return c;
}
static void WeatherInstallForecastColumns(id self)
{
    if (objc_getAssociatedObject(self,&WeatherHourlyColumnsKey)) return;
    SEL addSel=NSSelectorFromString(@"addSubview:");
    if (![self respondsToSelector:addSel]) return;
    NSMutableArray *hs=[NSMutableArray array], *ds=[NSMutableArray array];
    CGFloat hw=(1204.0f-76.0f)/6.0f;
    for(NSUInteger i=0;i<6;i++){
        id c=WeatherColumnText(CGRectMake(76.0f+i*hw,239.0f,hw,112.0f));
        if(c){((void(*)(id,SEL,id))objc_msgSend)(self,addSel,c);[hs addObject:c];}
    }
    CGFloat dw=(1208.0f-72.0f)/7.0f;
    for(NSUInteger i=0;i<7;i++){
        id c=WeatherColumnText(CGRectMake(72.0f+i*dw,42.0f,dw,120.0f));
        if(c){((void(*)(id,SEL,id))objc_msgSend)(self,addSel,c);[ds addObject:c];}
    }
    objc_setAssociatedObject(self,&WeatherHourlyColumnsKey,hs,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self,&WeatherDailyColumnsKey,ds,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void WeatherUpdateForecastColumns(id self)
{
    WeatherInstallForecastColumns(self);
    NSArray *hs=objc_getAssociatedObject(self,&WeatherHourlyColumnsKey), *ds=objc_getAssociatedObject(self,&WeatherDailyColumnsKey);
    NSDictionary *w=WeatherSnapshot(); NSArray *hourly=[w objectForKey:@"hourly"], *daily=[w objectForKey:@"daily"];
    NSDictionary *base=WeatherThemeTextAttributes();
    NSMutableDictionary *attrs=[NSMutableDictionary dictionaryWithDictionary:base ?: @{}];
    [attrs setObject:@16 forKey:@"BRFontPointSize"]; [attrs setObject:@1 forKey:@"BRTextAlignmentKey"];
    NSUInteger start=0; NSString *updated=[w objectForKey:@"updated"];
    if([updated isKindOfClass:[NSString class]] && [updated length]>=13){
        NSString *hh=[updated substringToIndex:13];
        for(NSUInteger i=0;i<[hourly count];i++) if([[[hourly objectAtIndex:i] objectForKey:@"time"] hasPrefix:hh]){start=i;break;}
    }
    for(NSUInteger j=0;j<[hs count];j++){
        NSString *txt=@"";
        if(start+j<[hourly count]){
            NSDictionary *x=[hourly objectAtIndex:start+j];
            txt=[NSString stringWithFormat:WeatherLocalized(@"%@\n%.0f°\n雨 %.0f%%", @"%@\n%.0f°\nRain %.0f%%"),j==0?WeatherLocalized(@"现在", @"Now"):WeatherHourLabel([x objectForKey:@"time"]),[[x objectForKey:@"temperature_2m"] doubleValue],[[x objectForKey:@"precipitation_probability"] doubleValue]];
        }
        id c=[hs objectAtIndex:j]; WeatherSetText(c,txt,attrs);
        SEL m=NSSelectorFromString(@"setMaxSize:"); if([c respondsToSelector:m])((void(*)(id,SEL,CGSize))objc_msgSend)(c,m,CGSizeMake(180,100));
    }
    for(NSUInteger i=0;i<[ds count];i++){
        NSString *txt=@"";
        if(i<[daily count]){
            NSDictionary *x=[daily objectAtIndex:i];
            txt=[NSString stringWithFormat:WeatherLocalized(@"%@\n%.0f°/%.0f°\n雨 %.0f%%", @"%@\n%.0f°/%.0f°\nRain %.0f%%"),i==0?WeatherLocalized(@"今天", @"Today"):WeatherDayLabel([x objectForKey:@"time"]),[[x objectForKey:@"temperature_2m_max"] doubleValue],[[x objectForKey:@"temperature_2m_min"] doubleValue],[[x objectForKey:@"precipitation_probability_max"] doubleValue]];
        }
        id c=[ds objectAtIndex:i]; WeatherSetText(c,txt,attrs);
        SEL m=NSSelectorFromString(@"setMaxSize:"); if([c respondsToSelector:m])((void(*)(id,SEL,CGSize))objc_msgSend)(c,m,CGSizeMake(155,110));
    }
}

static void WeatherInstallTextControls(id self)
{
    id timeControl =
        objc_getAssociatedObject(
            self,
            &WeatherTimeTextKey);

    if (timeControl)
        return;

    timeControl = WeatherCreateTextControl();
    id dateControl = WeatherCreateTextControl();
    id hourlyControl = WeatherCreateTextControl();
    id dailyControl = WeatherCreateTextControl();
    id hourlyLabel = WeatherCreateTextControl();
    id dailyLabel = WeatherCreateTextControl();
    id locationControl = WeatherCreateTextControl();
    id conditionControl = WeatherCreateTextControl();
    id detailsControl = WeatherCreateTextControl();
    id sunControl = WeatherCreateTextControl();

    if (!timeControl || !dateControl || !hourlyControl || !dailyControl || !hourlyLabel || !dailyLabel || !locationControl || !conditionControl || !detailsControl || !sunControl)
        return;

    /*
     * First validation layout.
     * Once BRTextControl is confirmed on-device,
     * we'll replace these temporary frames with
     * measured final weather geometry.
     */
    WeatherSetFrame(locationControl, CGRectMake(72.0f, 642.0f, 1136.0f, 45.0f));
    WeatherSetFrame(timeControl, CGRectMake(235.0f, 525.0f, 500.0f, 105.0f));
    WeatherSetFrame(conditionControl, CGRectMake(240.0f, 486.0f, 500.0f, 42.0f));
    WeatherSetFrame(detailsControl, CGRectMake(74.0f, 438.0f, 680.0f, 36.0f));
    WeatherSetFrame(sunControl, CGRectMake(760.0f, 438.0f, 440.0f, 34.0f));
    WeatherSetFrame(dateControl, CGRectMake(0.0f, 0.0f, 1.0f, 1.0f));
    WeatherSetFrame(hourlyLabel, CGRectMake(82.0f, 382.0f, 1136.0f, 28.0f));
    WeatherSetFrame(hourlyControl, CGRectMake(0.0f, 0.0f, 1.0f, 1.0f));
    WeatherSetFrame(dailyLabel, CGRectMake(82.0f, 192.0f, 1136.0f, 28.0f));
    WeatherSetFrame(dailyControl, CGRectMake(0.0f, 0.0f, 1.0f, 1.0f));

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
    ((void(*)(id,SEL,id))objc_msgSend)(self, addSubviewSel, locationControl);
    ((void(*)(id,SEL,id))objc_msgSend)(self, addSubviewSel, conditionControl);
    ((void(*)(id,SEL,id))objc_msgSend)(self, addSubviewSel, detailsControl);
    ((void(*)(id,SEL,id))objc_msgSend)(self, addSubviewSel, sunControl);

    objc_setAssociatedObject(
        self,
        &WeatherTimeTextKey,
        timeControl,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    objc_setAssociatedObject(
        self,
        &WeatherDateTextKey,
        dateControl,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    objc_setAssociatedObject(self, &WeatherHourlyLabelKey, hourlyLabel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &WeatherHourlyTextKey, hourlyControl, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &WeatherDailyLabelKey, dailyLabel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &WeatherDailyTextKey, dailyControl, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &WeatherLocationTextKey, locationControl, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &WeatherConditionTextKey, conditionControl, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &WeatherDetailsTextKey, detailsControl, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &WeatherSunTextKey, sunControl, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void WeatherUpdateTextControls(id self)
{
    WeatherInstallTextControls(self);

    id timeControl =
        objc_getAssociatedObject(
            self,
            &WeatherTimeTextKey);

    id dateControl =
        objc_getAssociatedObject(
            self,
            &WeatherDateTextKey);

    id hourlyLabel = objc_getAssociatedObject(self, &WeatherHourlyLabelKey);
    id hourlyControl = objc_getAssociatedObject(self, &WeatherHourlyTextKey);
    id dailyLabel = objc_getAssociatedObject(self, &WeatherDailyLabelKey);
    id dailyControl = objc_getAssociatedObject(self, &WeatherDailyTextKey);
    id locationControl=objc_getAssociatedObject(self,&WeatherLocationTextKey);
    id conditionControl=objc_getAssociatedObject(self,&WeatherConditionTextKey);
    id detailsControl=objc_getAssociatedObject(self,&WeatherDetailsTextKey);
    id sunControl=objc_getAssociatedObject(self,&WeatherSunTextKey);

    if (!timeControl || !dateControl || !hourlyLabel || !hourlyControl || !dailyLabel || !dailyControl || !locationControl || !conditionControl || !detailsControl || !sunControl)
        return;

    NSDictionary *baseAttrs =
        WeatherThemeTextAttributes();

    NSMutableDictionary *timeAttrs =
        [NSMutableDictionary dictionaryWithDictionary:
            baseAttrs ?: @{}];

    NSMutableDictionary *dateAttrs =
        [NSMutableDictionary dictionaryWithDictionary:
            baseAttrs ?: @{}];

    [timeAttrs setObject:@92
                  forKey:@"BRFontPointSize"];

    [dateAttrs setObject:@25
                  forKey:@"BRFontPointSize"];

    NSMutableDictionary *forecastAttrs=[NSMutableDictionary dictionaryWithDictionary:baseAttrs ?: @{}];
    [forecastAttrs setObject:@18 forKey:@"BRFontPointSize"];
    [forecastAttrs setObject:@1 forKey:@"BRTextAlignmentKey"];
    NSMutableDictionary *labelAttrs=[NSMutableDictionary dictionaryWithDictionary:baseAttrs ?: @{}];
    [labelAttrs setObject:@18 forKey:@"BRFontPointSize"];
    [labelAttrs setObject:@1 forKey:@"BRTextAlignmentKey"];

    /*
     * Keep the native BackRow alignment value discovered
     * from the real Apple TV theme.
     */
    [timeAttrs setObject:@1
                  forKey:@"BRTextAlignmentKey"];

    [dateAttrs setObject:@1
                  forKey:@"BRTextAlignmentKey"];

    NSDictionary *snap=WeatherSnapshot();
    NSString *location=[snap objectForKey:@"location"] ?: @"Weather";
    NSNumber *temp=[snap objectForKey:@"temperature_c"];
    NSNumber *feels=[snap objectForKey:@"feels_like_c"];
    NSNumber *humidity=[snap objectForKey:@"humidity"];
    NSNumber *wind=[snap objectForKey:@"wind_kmh"];
    NSString *condition=WeatherLocalizedCondition([[snap objectForKey:@"weather_code"] integerValue]);
    NSArray *days=[snap objectForKey:@"daily"]; NSString *rise=@"--:--", *set=@"--:--";
    if([days count]){
        NSString *r=[[days objectAtIndex:0] objectForKey:@"sunrise"], *ss=[[days objectAtIndex:0] objectForKey:@"sunset"];
        if([r length]>=16) rise=[r substringWithRange:NSMakeRange(11,5)];
        if([ss length]>=16) set=[ss substringWithRange:NSMakeRange(11,5)];
    }
    NSMutableDictionary *locAttrs=[NSMutableDictionary dictionaryWithDictionary:baseAttrs ?: @{}]; [locAttrs setObject:@34 forKey:@"BRFontPointSize"];
    NSMutableDictionary *condAttrs=[NSMutableDictionary dictionaryWithDictionary:baseAttrs ?: @{}]; [condAttrs setObject:@31 forKey:@"BRFontPointSize"];
    NSMutableDictionary *detailAttrs=[NSMutableDictionary dictionaryWithDictionary:baseAttrs ?: @{}]; [detailAttrs setObject:@25 forKey:@"BRFontPointSize"];
    NSMutableDictionary *sunAttrs=[NSMutableDictionary dictionaryWithDictionary:baseAttrs ?: @{}]; [sunAttrs setObject:@22 forKey:@"BRFontPointSize"];
    WeatherSetText(locationControl,location,locAttrs);
    WeatherSetText(timeControl,[NSString stringWithFormat:@"%.0f C",[temp doubleValue]],timeAttrs);
    WeatherSetText(conditionControl,condition,condAttrs);
    WeatherSetText(detailsControl,WEATHER_LANG_EN ? [NSString stringWithFormat:@"Feels %.0f C   Humidity %.0f%%   Wind %.0f km/h",[feels doubleValue],[humidity doubleValue],[wind doubleValue]] : [NSString stringWithFormat:@"体感 %.0f C   湿度 %.0f%%   风速 %.0f km/h",[feels doubleValue],[humidity doubleValue],[wind doubleValue]],detailAttrs);
    WeatherSetText(sunControl,[NSString stringWithFormat:WeatherLocalized(@"日出 %@   日落 %@", @"Sunrise %@   Sunset %@"),rise,set],sunAttrs);
    WeatherSetText(dateControl,@"",dateAttrs);

    WeatherSetText(hourlyLabel, WeatherLocalized(@"每小时天气", @"Hourly Forecast"), labelAttrs);
    WeatherSetText(hourlyControl, @"", forecastAttrs);
    WeatherSetText(dailyLabel, WeatherLocalized(@"7天天气预报", @"7-Day Forecast"), labelAttrs);
    WeatherSetText(dailyControl, @"", forecastAttrs);
    WeatherUpdateForecastColumns(self);

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
            CGSizeMake(1136.0f, 120.0f));
    }

    if ([dateControl respondsToSelector:maxSizeSel]) {
        ((void(*)(id,SEL,CGSize))objc_msgSend)(
            dateControl,
            maxSizeSel,
            CGSizeMake(1136.0f, 55.0f));
    }

    if ([hourlyControl respondsToSelector:maxSizeSel]) ((void(*)(id,SEL,CGSize))objc_msgSend)(hourlyControl,maxSizeSel,CGSizeMake(1136.0f,105.0f));
    if ([dailyControl respondsToSelector:maxSizeSel]) ((void(*)(id,SEL,CGSize))objc_msgSend)(dailyControl,maxSizeSel,CGSizeMake(1136.0f,105.0f));

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

static void WeatherRefresh(id self, SEL cmd)
{
    (void)cmd;

    WeatherUpdateFullscreenControl(self);

    NSString *time = WeatherCurrentTime();
    NSString *date = WeatherCurrentDate();

    /*
     * Keep the proven menu controller alive for 0.2.
     * The generated weather image is used through the preview-control path.
     */
    NSString *title =
        [NSString stringWithFormat:@"%@     %@", time, date];

    NSArray *selectors = @[@"setListTitle:", @"setTitle:"];

    for (NSString *name in selectors) {

        SEL sel = NSSelectorFromString(name);

        if (WeatherSignature(self, sel, @encode(void), @[@"@"])) {
            ((void(*)(id,SEL,id))objc_msgSend)(self, sel, title);
            break;
        }
    }

    SEL reloadSel = NSSelectorFromString(@"reload");

    SEL listSel = NSSelectorFromString(@"list");

    if (WeatherSignature(self, listSel, @encode(id), @[])) {

        id list =
            ((id(*)(id,SEL))objc_msgSend)(self, listSel);

        if (list &&
            WeatherSignature(list,
                           reloadSel,
                           @encode(void),
                           @[])) {

            ((void(*)(id,SEL))objc_msgSend)(list,
                                            reloadSel);
        }
    }

    NSLog(@"Weather: refresh %@ %@", time, date);
}

static id WeatherPreview(id self, SEL cmd, long item)
{
    (void)self;
    (void)cmd;
    (void)item;

    return WeatherCreateImageControl();
}

static void WeatherTimerFire(id self, SEL cmd, id timer)
{
    (void)cmd;
    (void)timer;

    WeatherUpdateTextControls(self);
    NSTimeInterval now=[NSDate timeIntervalSinceReferenceDate];
    if (!WeatherSnapshot() || (now-weatherCachedAt)>=45.0) WeatherFetchAsync(self);
}

static void WeatherBackgroundFetch(id self, SEL cmd, id unused)
{
    (void)cmd; (void)unused;
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
    NSDictionary *fresh=WeatherBridgeData();
    if (fresh) WeatherStoreSnapshot(fresh);
    @synchronized([NSObject class]) { weatherFetchInFlight=NO; }
    if (fresh) [self performSelectorOnMainThread:NSSelectorFromString(@"weatherApplyFreshData") withObject:nil waitUntilDone:NO];
    [pool drain];
}

static void WeatherApplyFreshData(id self, SEL cmd)
{
    (void)cmd;
    NSLog(@"Weather: data updated; bitmap refresh deferred to next open");
}

static void WeatherEnsureTimerSelector(void);

/* ---------------------------------------------------------
   Controller lifecycle
   --------------------------------------------------------- */

static id WeatherControllerInit(id self, SEL cmd)
{
    IMP superIMP = WeatherControllerSuper(cmd);

    if (!superIMP)
        return nil;

    self = ((id(*)(id,SEL))superIMP)(self, cmd);

    if (!self)
        return nil;

    WeatherEnsureTimerSelector();

    NSTimer *timer =
        [NSTimer scheduledTimerWithTimeInterval:60.0
                                        target:self
                                      selector:NSSelectorFromString(@"weatherTimerFire:")
                                      userInfo:nil
                                       repeats:YES];

    objc_setAssociatedObject(self,
                             &weatherTimerKey,
                             timer,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    NSLog(@"Weather: controller initialized");

    return self;
}

static void WeatherActivated(id self, SEL cmd)
{
    IMP superIMP=WeatherControllerSuper(cmd);
    if(superIMP) ((void(*)(id,SEL))superIMP)(self,cmd);
    WeatherUpdateFullscreenControl(self);
    NSLog(@"Weather: restored bitmap layout");
}

static void WeatherDeactivated(id self, SEL cmd)
{
    NSLog(@"Weather: deactivated");

    IMP superIMP = WeatherControllerSuper(cmd);

    if (superIMP)
        ((void(*)(id,SEL))superIMP)(self, cmd);
}

static void WeatherPopped(id self, SEL cmd)
{
    NSTimer *timer =
        (NSTimer *)objc_getAssociatedObject(self, &weatherTimerKey);

    if (timer)
        [timer invalidate];

    objc_setAssociatedObject(self,
                             &weatherTimerKey,
                             nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    NSLog(@"Weather: popped");

    IMP superIMP = WeatherControllerSuper(cmd);

    if (superIMP)
        ((void(*)(id,SEL))superIMP)(self, cmd);
}

static void WeatherControllerDealloc(id self, SEL cmd)
{
    NSTimer *timer =
        (NSTimer *)objc_getAssociatedObject(self, &weatherTimerKey);

    if (timer)
        [timer invalidate];

    objc_setAssociatedObject(self,
                             &weatherTimerKey,
                             nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    IMP superIMP = WeatherControllerSuper(cmd);

    if (superIMP)
        ((void(*)(id,SEL))superIMP)(self, cmd);
}

/* Let native BackRow own Menu/navigation. */

static BOOL WeatherEvent(id self, SEL cmd, id event)
{
    Class cls = objc_getClass("WeatherController");
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

static NSString *WeatherMenuIconURLForResolution(NSInteger resolution)
{
    NSBundle *bundle = [NSBundle bundleWithIdentifier:@"org.atv3.weather"];
    NSString *name = (resolution >= 1080) ? @"AppIcon@1080" : @"AppIcon";
    NSString *path = [bundle pathForResource:name ofType:@"png"];
    if (![path length])
        path = (resolution >= 1080) ? @"/Applications/Weather.frappliance/AppIcon@1080.png" : @"/Applications/Weather.frappliance/AppIcon.png";
    return [[NSURL fileURLWithPath:path] absoluteString];
}

static NSString *WeatherMenuIconURL(void)
{
    return WeatherMenuIconURLForResolution(1080);
}

static id WeatherInfoMenuIconURLs(id self, SEL cmd)
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
            @"/var/tmp/weather_icon_probe.log"];

    if (!probe) {
        [[NSData data] writeToFile:
            @"/var/tmp/weather_icon_probe.log"
            atomically:YES];

        probe =
            [NSFileHandle fileHandleForWritingAtPath:
                @"/var/tmp/weather_icon_probe.log"];
    }

    if (probe) {
        [probe seekToEndOfFile];
        [probe writeData:
            [probeLine dataUsingEncoding:NSUTF8StringEncoding]];
        [probe closeFile];
    }

    NSString *url = WeatherMenuIconURLForResolution(720);
    if (![url length]) return @{};
    return @{
        @"720": url, @"1080": url,
        [NSNumber numberWithInteger:720]: url,
        [NSNumber numberWithInteger:1080]: url
    };
}

static id WeatherInfoMenuIconURLVersion(id self, SEL cmd)
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
            @"/var/tmp/weather_icon_probe.log"];

    if (!probe) {
        [[NSData data] writeToFile:
            @"/var/tmp/weather_icon_probe.log"
            atomically:YES];

        probe =
            [NSFileHandle fileHandleForWritingAtPath:
                @"/var/tmp/weather_icon_probe.log"];
    }

    if (probe) {
        [probe seekToEndOfFile];
        [probe writeData:
            [probeLine dataUsingEncoding:NSUTF8StringEncoding]];
        [probe closeFile];
    }

    NSBundle *bundle =
        [NSBundle bundleWithIdentifier:@"org.atv3.weather"];

    id version =
        [bundle objectForInfoDictionaryKey:@"CFBundleVersion"];

    return [version isKindOfClass:[NSString class]] &&
           [version length] ? version : @"1";
}

static Class WeatherApplianceInfoClass(void)
{
    Class existing =
        objc_getClass("WeatherApplianceInfo");

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
            "WeatherApplianceInfo",
            0);

    if (!cls)
        return Nil;

    BOOL ok =
        class_addMethod(
            cls,
            NSSelectorFromString(@"menuIconURLs"),
            (IMP)WeatherInfoMenuIconURLs,
            method_getTypeEncoding(urlsMethod))
        &&
        class_addMethod(
            cls,
            NSSelectorFromString(@"menuIconURLVersion"),
            (IMP)WeatherInfoMenuIconURLVersion,
            method_getTypeEncoding(versionMethod));

    if (!ok) {
        objc_disposeClassPair(cls);
        return Nil;
    }

    objc_registerClassPair(cls);

    return cls;
}

static id WeatherSyntheticApplianceInfo(void)
{
    Class infoClass =
        WeatherApplianceInfoClass();

    if (!infoClass)
        return nil;

    id info = [infoClass alloc];

    SEL init =
        NSSelectorFromString(@"_initWithMutableDictionary:");

    if (!WeatherSignature(info,
                        init,
                        @encode(id),
                        @[@"@"])) {
        [info release];
        return nil;
    }

    NSMutableDictionary *values =
        [NSMutableDictionary dictionary];

    [values setObject:@"weather"
               forKey:@"FRApplianceIdentifier"];

    [values setObject:@"Weather"
               forKey:@"FRApplianceName"];

    [values setObject:@6
               forKey:@"FRAppliancePreferedOrderValue"];

    [values setObject:@"WeatherAppliance"
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

static id WeatherApplianceInit(id self,
                             SEL cmd,
                             id incoming)
{
    id info =
        incoming ?: WeatherSyntheticApplianceInfo();

    IMP superIMP =
        WeatherApplianceSuper(cmd);

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

static BOOL WeatherCategoryAvailable(void)
{
    return WeatherSignature(
        objc_getClass("BRApplianceCategory"),
        NSSelectorFromString(
            @"categoryWithName:identifier:preferredOrder:"),
        @encode(id),
        @[@"@", @"@", @"f"]);
}

static id WeatherCategories(id self, SEL cmd)
{
    (void)self;
    (void)cmd;

    if (!WeatherCategoryAvailable()) {
        NSLog(@"Weather: category ABI unavailable");
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

    id name = @"Weather";
    id identifier = @"weather";
    float order = 0.0f;

    [invocation setArgument:&name atIndex:2];
    [invocation setArgument:&identifier atIndex:3];
    [invocation setArgument:&order atIndex:4];

    [invocation invoke];

    id result = nil;

    [invocation getReturnValue:&result];

    return result ? @[result] : @[];
}

static id WeatherControllerForIdentifier(id self,
                                       SEL cmd,
                                       id identifier,
                                       id args)
{
    (void)self;
    (void)cmd;
    (void)args;

    if (![identifier isEqual:@"weather"])
        return nil;

    return [WeatherNew(
        objc_getClass("WeatherController"))
        autorelease];
}

static id WeatherApplianceController(id self,
                                   SEL cmd)
{
    (void)self;
    (void)cmd;

    return [WeatherNew(
        objc_getClass("WeatherController"))
        autorelease];
}

/* ---------------------------------------------------------
   Beigelist legacy root bridge
   --------------------------------------------------------- */

static IMP weatherOriginalLegacyRootController = NULL;

static BOOL WeatherIsLegacyMerchant(id self)
{
    id info =
        WeatherObject(self, @"info");

    id merchantID =
        WeatherObject(info, @"merchantID");

    if ([merchantID isKindOfClass:[NSString class]] &&
        [merchantID isEqualToString:@"org.atv3.weather"])
        return YES;

    id identifier =
        WeatherObject(self, @"identifier");

    if ([identifier isKindOfClass:[NSString class]] &&
        ([identifier isEqualToString:@"org.atv3.weather"] ||
         [identifier isEqualToString:
             @"merchant.org.atv3.weather"]))
        return YES;

    id legacyClass =
        WeatherObject(self, @"legacyApplianceClass");

    return legacyClass ==
        objc_getClass("WeatherAppliance");
}

static id WeatherLegacyRootController(id self,
                                    SEL cmd)
{
    if (WeatherIsLegacyMerchant(self)) {

        id controller =
            [WeatherNew(
                objc_getClass("WeatherController"))
                autorelease];

        if (controller)
            return controller;
    }

    return weatherOriginalLegacyRootController
        ? ((id(*)(id,SEL))
            weatherOriginalLegacyRootController)(
                self,
                cmd)
        : nil;
}

static BOOL WeatherInstallLegacyRootBridge(void)
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
        (IMP)WeatherLegacyRootController)
        return YES;

    weatherOriginalLegacyRootController =
        current;

    if (class_addMethod(
            cls,
            sel,
            (IMP)WeatherLegacyRootController,
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

        weatherOriginalLegacyRootController =
            NULL;

        return NO;
    }

    weatherOriginalLegacyRootController =
        method_setImplementation(
            method,
            (IMP)WeatherLegacyRootController);

    return
        weatherOriginalLegacyRootController != NULL;
}

/* ---------------------------------------------------------
   BLAppMerchantInfo icon compatibility bridge
   --------------------------------------------------------- */


/* ---------------------------------------------------------
   Dynamic Home Screen Weather Icon
   188x108 canvas, centered 92x92 weather face
   --------------------------------------------------------- */

static NSString *WeatherDynamicIconPath(void)
{
    NSDateFormatter *formatter =
        [[[NSDateFormatter alloc] init] autorelease];

    [formatter setDateFormat:@"yyyyMMddHHmmss"];

    NSString *stamp =
        [formatter stringFromDate:[NSDate date]];

    return [NSString stringWithFormat:
        @"/var/tmp/WeatherDynamicIcon-%@.png",
        stamp];
}

static BOOL WeatherRenderDynamicHomeIcon(void)
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

    /* Light weather face. */
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
        @"/var/tmp/weather_dynamic_time.log"
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
        WeatherDynamicIconPath();

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

static NSString *WeatherDynamicIconURL(void)
{
    if (WeatherRenderDynamicHomeIcon()) {
        return [[NSURL fileURLWithPath:
            WeatherDynamicIconPath()]
            absoluteString];
    }

    /* Stable 0.1.3 icon is always the fallback. */
    return WeatherMenuIconURL();
}

static NSString *WeatherDynamicIconVersion(void)
{
    NSDateFormatter *formatter =
        [[[NSDateFormatter alloc] init]
            autorelease];

    [formatter setDateFormat:
        @"yyyyMMddHHmmss"];

    return [formatter stringFromDate:
        [NSDate date]];
}


static void WeatherProbeMerchantCoordinatorClass(void)
{
    Class cls = objc_getClass("ATVMerchantCoordinator");
    FILE *fp = fopen("/var/tmp/weather_coordinator_class.txt", "w");
    if (!fp) return;
    if (!cls) { fprintf(fp, "NOT FOUND\n"); fclose(fp); return; }
    unsigned int n = 0;
    Method *ms = class_copyMethodList(object_getClass(cls), &n);
    for (unsigned int i=0; i<n; i++)
        fprintf(fp, "%s | %s\n", sel_getName(method_getName(ms[i])), method_getTypeEncoding(ms[i]));
    if (ms) free(ms);
    fclose(fp);
}


static void WeatherPulseMerchantCoordinator(void)
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
    id merchant = ((id(*)(id,SEL,id))objc_msgSend)(coordinator, merchantSel, @"org.atv3.weather");
    if (merchant)
        ((void(*)(id,SEL,id))objc_msgSend)(coordinator, changedSel, merchant);
}

static void WeatherHomeIconTimerFire(id self, SEL cmd, NSTimer *timer)
{
    (void)self; (void)cmd; (void)timer;
    WeatherPulseMerchantCoordinator();
}

static void WeatherStartHomeIconTimer(void)
{
    static NSTimer *timer = nil;
    if (timer) return;
    Class timerClass = objc_getClass("WeatherHomeIconTimerTarget");
    if (!timerClass) {
        timerClass = objc_allocateClassPair([NSObject class], "WeatherHomeIconTimerTarget", 0);
        if (!timerClass) return;
        class_addMethod(timerClass, NSSelectorFromString(@"fire:"), (IMP)WeatherHomeIconTimerFire, "v@:@");
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

static IMP weatherSuperMerchantInfoValueForKey = NULL;

static BOOL WeatherIsMerchantInfo(id self)
{
    id merchantID =
        WeatherObject(self, @"merchantID");

    return
        [merchantID isKindOfClass:[NSString class]] &&
        [merchantID isEqualToString:@"org.atv3.weather"];
}

static id WeatherMerchantInfoValueForKey(id self, SEL cmd, id key)
{
    if ([key isKindOfClass:[NSString class]] && WeatherIsMerchantInfo(self)) {
        if ([key isEqualToString:@"menu-icon-url"]) {
            NSString *url = WeatherMenuIconURLForResolution(720);
            if (![url length]) return nil;
            return @{
                @"720": url, @"1080": url,
                [NSNumber numberWithInteger:720]: url,
                [NSNumber numberWithInteger:1080]: url
            };
        }
        if ([key isEqualToString:@"menu-icon-url-version"]) {
            NSBundle *bundle = [NSBundle bundleWithIdentifier:@"org.atv3.weather"];
            id version = [bundle objectForInfoDictionaryKey:@"CFBundleVersion"];
            return ([version isKindOfClass:[NSString class]] && [version length]) ? version : @"1";
        }
    }
    return weatherSuperMerchantInfoValueForKey
        ? ((id(*)(id,SEL,id))weatherSuperMerchantInfoValueForKey)(self,cmd,key)
        : nil;
}

static BOOL WeatherInstallMerchantInfoBridge(void)
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
    if (!current || current == (IMP)WeatherMerchantInfoValueForKey)
        return current == (IMP)WeatherMerchantInfoValueForKey;

    weatherSuperMerchantInfoValueForKey = current;
    method_setImplementation(inherited, (IMP)WeatherMerchantInfoValueForKey);
    return YES;
}

/* ---------------------------------------------------------
   Runtime class registration
   --------------------------------------------------------- */

static BOOL WeatherAddOverride(Class cls,
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
        NSLog(@"Weather: missing %@", name);
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


static void WeatherDumpRuntimeClass(FILE *fp, const char *name)
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

static void WeatherDumpRuntime(void)
{
    FILE *fp = fopen("/var/tmp/weather_runtime.txt", "w");

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
        WeatherDumpRuntimeClass(fp, classes[i]);

    fflush(fp);
    fclose(fp);
}


static void WeatherDumpHomeIconRuntime(void)
{
    FILE *fp =
        fopen("/var/tmp/weather_home_icon_runtime.txt", "w");

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


BOOL WeatherRegisterBackRowClasses(void)
{
    WeatherProbeMerchantCoordinatorClass();
    WeatherDumpHomeIconRuntime();
    WeatherDumpRuntime();
    if (objc_getClass("WeatherAppliance")) {
        WeatherInstallLegacyRootBridge();
        return YES;
    }

    if (!WeatherCategoryAvailable()) {
        NSLog(@"Weather: category ABI unavailable");
        return NO;
    }

    Class applianceBase =
        objc_getClass("BRBaseAppliance");

    Class controllerBase =
        objc_getClass("BRController");

    if (!applianceBase ||
        !controllerBase) {

        NSLog(@"Weather: BackRow unavailable");
        return NO;
    }

    Class appliance =
        objc_allocateClassPair(
            applianceBase,
            "WeatherAppliance",
            0);

    Class controller =
        objc_allocateClassPair(
            controllerBase,
            "WeatherController",
            0);

    if (!appliance || !controller) {

        if (appliance)
            objc_disposeClassPair(appliance);

        if (controller)
            objc_disposeClassPair(controller);

        return NO;
    }

    BOOL ok =
        WeatherAddOverride(
            appliance,
            @"initWithApplianceInfo:",
            (IMP)WeatherApplianceInit,
            @encode(id),
            @[@"@"])
        &&
        WeatherAddOverride(
            appliance,
            @"applianceCategories",
            (IMP)WeatherCategories,
            @encode(id),
            @[])
        &&
        WeatherAddOverride(
            appliance,
            @"controllerForIdentifier:args:",
            (IMP)WeatherControllerForIdentifier,
            @encode(id),
            @[@"@", @"@"])
        &&
        WeatherAddOverride(
            appliance,
            @"applianceController",
            (IMP)WeatherApplianceController,
            @encode(id),
            @[])
        &&
        WeatherAddOverride(
            controller,
            @"brEventAction:",
            (IMP)WeatherEvent,
            @encode(BOOL),
            @[@"@"]);

    if (ok) {

        ok =
            WeatherAddOverride(
                controller,
                @"init",
                (IMP)WeatherControllerInit,
                @encode(id),
                @[])
            &&
            WeatherAddOverride(
                controller,
                @"controlWasActivated",
                (IMP)WeatherActivated,
                @encode(void),
                @[])
            &&
            WeatherAddOverride(
                controller,
                @"controlWasDeactivated",
                (IMP)WeatherDeactivated,
                @encode(void),
                @[])
            &&
            WeatherAddOverride(
                controller,
                @"wasPopped",
                (IMP)WeatherPopped,
                @encode(void),
                @[])
            &&
            WeatherAddOverride(
                controller,
                @"dealloc",
                (IMP)WeatherControllerDealloc,
                @encode(void),
                @[]);

    }

    if (!ok) {

        objc_disposeClassPair(appliance);
        objc_disposeClassPair(controller);

        NSLog(@"Weather: incompatible BackRow ABI");

        return NO;
    }

    /* Register controller first, same proven order as Jellyfin. */
    objc_registerClassPair(controller);
    objc_registerClassPair(appliance);

    WeatherInstallMerchantInfoBridge();
    WeatherInstallLegacyRootBridge();

    NSLog(@"Weather: BackRow classes registered");

    return YES;
}

/* Dynamic NSTimer target selector */
__attribute__((constructor))
static void WeatherInstallTimerSelector(void)
{
    /* Installed after WeatherController is dynamically created,
       so actual selector installation occurs lazily below. */
}

static void WeatherEnsureTimerSelector(void)
{
    Class cls =
        objc_getClass("WeatherController");

    if (!cls)
        return;

    SEL sel =
        NSSelectorFromString(@"weatherTimerFire:");

    if (!class_getInstanceMethod(cls, sel)) {
        class_addMethod(cls,sel,(IMP)WeatherTimerFire,"v@:@");
    }
    SEL fetchSel=NSSelectorFromString(@"weatherBackgroundFetch:");
    if (!class_getInstanceMethod(cls,fetchSel)) {
        class_addMethod(cls,fetchSel,(IMP)WeatherBackgroundFetch,"v@:@");
    }
    SEL applySel=NSSelectorFromString(@"weatherApplyFreshData");
    if (!class_getInstanceMethod(cls,applySel)) {
        class_addMethod(cls,applySel,(IMP)WeatherApplyFreshData,"v@:");
    }
}
