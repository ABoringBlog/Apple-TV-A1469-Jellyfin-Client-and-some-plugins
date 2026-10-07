#import <Foundation/Foundation.h>
#import "RadioBackRow.h"

@interface RadioBundleAnchor : NSObject
@end

@implementation RadioBundleAnchor
@end

__attribute__((constructor))
static void RadioEntry(void)
{
    @autoreleasepool {
        NSLog(@"Radio: entry");
        BOOL ok = RadioRegisterBackRowClasses();
        NSLog(@"Radio: BackRow registration %@", ok ? @"OK" : @"FAILED");
    }
}
