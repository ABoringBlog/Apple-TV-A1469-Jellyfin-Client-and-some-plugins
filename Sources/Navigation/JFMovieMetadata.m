#import "JFMovieMetadata.h"
#import <CoreFoundation/CoreFoundation.h>
#include <math.h>
#include <limits.h>

static BOOL JFNumber(id value, double *out) {
    if (![value isKindOfClass:[NSNumber class]]) return NO;
    if (CFGetTypeID((CFTypeRef)value)==CFBooleanGetTypeID()) return NO;
    double n=[value doubleValue];
    if (!isfinite(n)) return NO;
    if (out) *out=n;
    return YES;
}
static BOOL JFInteger(id value, long long minimum, long long maximum, long long *out) {
    double n=0;
    if (!JFNumber(value,&n) || n<(double)minimum || n>(double)maximum || floor(n)!=n) return NO;
    if (out) *out=(long long)n;
    return YES;
}
static BOOL JFPlayed(id value) {
    if (![value isKindOfClass:[NSNumber class]]) return NO;
    if (CFGetTypeID((CFTypeRef)value)==CFBooleanGetTypeID()) return [value boolValue];
    double n=[value doubleValue];
    return isfinite(n) && (n==0.0 || n==1.0) ? [value boolValue] : NO;
}
static NSNumber *JFResumePercent(NSDictionary *item, NSDictionary *user, BOOL played) {
    if (played) return nil;
    long long runtime=0, position=0;
    if (JFInteger(item[@"RunTimeTicks"],1,LLONG_MAX,&runtime) &&
        JFInteger(user[@"PlaybackPositionTicks"],0,LLONG_MAX,&position) &&
        position>0 && position<runtime) {
        long double ratio=((long double)position*100.0L)/(long double)runtime;
        NSUInteger percent=(NSUInteger)floorl(ratio);
        if (percent<1) percent=1;
        if (percent>99) percent=99;
        return @(percent);
    }
    double percentage=0;
    if (JFNumber(user[@"PlayedPercentage"],&percentage) && percentage>0.0 && percentage<100.0) {
        NSUInteger percent=(NSUInteger)floor(percentage);
        if (percent<1) percent=1;
        if (percent>99) percent=99;
        return @(percent);
    }
    return nil;
}
NSDictionary *JFMovieMetadata(NSDictionary *item) {
    if (![item isKindOfClass:[NSDictionary class]]) return @{};
    NSString *name=[item[@"Name"] isKindOfClass:[NSString class]] && [item[@"Name"] length] ? item[@"Name"] : @"Untitled";
    NSMutableDictionary *result=[NSMutableDictionary dictionaryWithObject:name forKey:@"name"];

    long long year=0;
    if (JFInteger(item[@"ProductionYear"],1800,3000,&year)) result[@"year"]=@(year);

    NSDictionary *user=[item[@"UserData"] isKindOfClass:[NSDictionary class]] ? item[@"UserData"] : @{};
    BOOL played=JFPlayed(user[@"Played"]);
    result[@"watched"]=@(played);

    NSNumber *resume=JFResumePercent(item,user,played);
    if (resume) result[@"resumePercent"]=resume;

    NSDictionary *tags=[item[@"ImageTags"] isKindOfClass:[NSDictionary class]] ? item[@"ImageTags"] : nil;
    NSString *primary=[tags[@"Primary"] isKindOfClass:[NSString class]] && [tags[@"Primary"] length] ? tags[@"Primary"] : nil;
    if (primary) result[@"primaryImageTag"]=primary;
    return result;
}
NSString *JFMovieRowTitle(NSDictionary *item) {
    NSDictionary *meta=JFMovieMetadata(item);
    NSMutableString *title=[NSMutableString stringWithString:meta[@"name"] ?: @"Untitled"];
    NSNumber *year=meta[@"year"];
    if (year) [title appendFormat:@"  %@",year];
    return title;
}
