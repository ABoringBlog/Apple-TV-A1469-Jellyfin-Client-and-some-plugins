#import "JFDetailMetadata.h"
#import "JFMovieMetadata.h"
#import "JFSeriesMetadata.h"
#import <CoreFoundation/CoreFoundation.h>
#include <math.h>
#include <limits.h>

static BOOL JFDetailNumber(id value, double *out) {
    if (![value isKindOfClass:[NSNumber class]] || CFGetTypeID((CFTypeRef)value)==CFBooleanGetTypeID()) return NO;
    double n=[value doubleValue];
    if (!isfinite(n)) return NO;
    if (out) *out=n;
    return YES;
}
static BOOL JFDetailInteger(id value, long long minimum, long long maximum, long long *out) {
    double n=0;
    if (!JFDetailNumber(value,&n) || n<(double)minimum || n>(double)maximum || floor(n)!=n) return NO;
    if (out) *out=(long long)n;
    return YES;
}
static NSString *JFDetailDuration(id value) {
    long long ticks=0;
    if (!JFDetailInteger(value,1,LLONG_MAX,&ticks)) return nil;
    long long minutes=(ticks+300000000LL)/600000000LL;
    if (minutes<1) minutes=1;
    if (minutes>=60) return [NSString stringWithFormat:@"%lldh %02lldm",minutes/60,minutes%60];
    return [NSString stringWithFormat:@"%lld min",minutes];
}
NSString *JFDetailTitle(NSDictionary *item) {
    if (![item isKindOfClass:[NSDictionary class]]) return @"Jellyfin — Details";
    if ([item[@"Type"] isEqual:@"Movie"]) return JFMovieRowTitle(item);
    if ([item[@"Type"] isEqual:@"Episode"]) return JFEpisodeRowTitle(item);
    NSString *name=[item[@"Name"] isKindOfClass:[NSString class]] ? item[@"Name"] : nil;
    return name.length ? name : @"Jellyfin — Details";
}
NSString *JFDetailFacts(NSDictionary *item) {
    if (![item isKindOfClass:[NSDictionary class]]) return nil;
    NSMutableArray *parts=[NSMutableArray array];
    long long year=0;
    if (JFDetailInteger(item[@"ProductionYear"],1800,3000,&year)) [parts addObject:[NSString stringWithFormat:@"%lld",year]];
    NSString *duration=JFDetailDuration(item[@"RunTimeTicks"]); if (duration) [parts addObject:duration];
    double rating=0;
    if (JFDetailNumber(item[@"CommunityRating"],&rating) && rating>=0.0 && rating<=10.0)
        [parts addObject:[NSString stringWithFormat:@"%.1f/10",rating]];
    NSString *official=[item[@"OfficialRating"] isKindOfClass:[NSString class]] ? item[@"OfficialRating"] : nil;
    NSString *custom=[item[@"CustomRating"] isKindOfClass:[NSString class]] ? item[@"CustomRating"] : nil;
    NSString *contentRating=official.length ? official : (custom.length ? custom : nil);
    if (contentRating) [parts addObject:contentRating];
    return parts.count ? [parts componentsJoinedByString:@"  •  "] : nil;
}
NSString *JFDetailGenres(NSDictionary *item) {
    id genres=[item isKindOfClass:[NSDictionary class]] ? item[@"Genres"] : nil;
    if (![genres isKindOfClass:[NSArray class]]) return nil;
    NSMutableArray *clean=[NSMutableArray array];
    for (id value in genres) if ([value isKindOfClass:[NSString class]] && [value length] && ![clean containsObject:value]) [clean addObject:value];
    return clean.count ? [clean componentsJoinedByString:@", "] : nil;
}
