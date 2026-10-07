#import <Foundation/Foundation.h>
#import "ClockBackRow.h"

@interface ClockBundleAnchor : NSObject
@end

@implementation ClockBundleAnchor
@end

__attribute__((constructor))
static void ClockEntry(void)
{
    @autoreleasepool {
        NSLog(@"Clock: entry");
        BOOL ok = ClockRegisterBackRowClasses();
        NSLog(@"Clock: BackRow registration %@", ok ? @"OK" : @"FAILED");
    }
}
