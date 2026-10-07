#import <Foundation/Foundation.h>
#import "WeatherBackRow.h"

@interface WeatherBundleAnchor : NSObject
@end

@implementation WeatherBundleAnchor
@end

__attribute__((constructor))
static void WeatherEntry(void)
{
    @autoreleasepool {
        NSLog(@"Weather: entry");
        BOOL ok = WeatherRegisterBackRowClasses();
        NSLog(@"Weather: BackRow registration %@", ok ? @"OK" : @"FAILED");
    }
}
