#import <Foundation/Foundation.h>
#import "MusicBackRow.h"
#include <stdio.h>
#include <unistd.h>

@interface MusicBundleAnchor : NSObject
@end

@implementation MusicBundleAnchor
@end

__attribute__((constructor))
static void MusicEntry(void)
{
    @autoreleasepool {
        NSLog(@"CloudTune: entry");
        FILE *f=fopen("/var/tmp/cloudtune_diag.log","a"); if(f){fprintf(f,"entry pid=%d\n",getpid());fclose(f);}
        BOOL ok = MusicRegisterBackRowClasses();
        NSLog(@"CloudTune: BackRow registration %@", ok ? @"OK" : @"FAILED");
        f=fopen("/var/tmp/cloudtune_diag.log","a"); if(f){fprintf(f,"register pid=%d ok=%d\n",getpid(),ok);fclose(f);}
    }
}
