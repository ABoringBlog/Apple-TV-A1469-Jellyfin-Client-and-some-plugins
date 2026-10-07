#import "JFSeriesMetadata.h"
#import <CoreFoundation/CoreFoundation.h>
#include <math.h>

static BOOL JFSeriesInteger(id value, long long minimum, long long maximum, long long *out) {
    if (![value isKindOfClass:[NSNumber class]] || CFGetTypeID((CFTypeRef)value)==CFBooleanGetTypeID()) return NO;
    double n=[value doubleValue];
    if (!isfinite(n) || n<(double)minimum || n>(double)maximum || floor(n)!=n) return NO;
    if (out) *out=(long long)n;
    return YES;
}
static NSString *JFSeriesName(NSDictionary *item, NSString *fallback) {
    id name=[item isKindOfClass:[NSDictionary class]] ? item[@"Name"] : nil;
    return [name isKindOfClass:[NSString class]] && [name length] ? name : fallback;
}
NSString *JFSeasonRowTitle(NSDictionary *item) {
    NSString *name=JFSeriesName(item,nil);
    if (name.length) return name;
    long long season=0;
    if (JFSeriesInteger(item[@"IndexNumber"],0,999,&season)) return [NSString stringWithFormat:@"Season %lld",season];
    return @"Season";
}
NSString *JFEpisodeRowTitle(NSDictionary *item) {
    NSString *name=JFSeriesName(item,@"Untitled");
    long long season=0, episode=0;
    BOOL hasSeason=JFSeriesInteger(item[@"ParentIndexNumber"],0,999,&season);
    BOOL hasEpisode=JFSeriesInteger(item[@"IndexNumber"],0,9999,&episode);
    if (hasSeason && hasEpisode) return [NSString stringWithFormat:@"S%02lldE%02lld  %@",season,episode,name];
    if (hasEpisode) return [NSString stringWithFormat:@"E%02lld  %@",episode,name];
    return name;
}
