#import "JFPlaybackTrace.h"
#include <fcntl.h>
#include <unistd.h>

void JFPlaybackTrace(NSString *event) {
    if (![event isKindOfClass:[NSString class]] || !event.length || event.length>256) return;
    if ([event rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]].location!=NSNotFound) return;
    NSData *data=[[event stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
    if (!data.length) return;
    int fd=open("/tmp/Jellyfin-ATV3.playbacktrace",O_WRONLY|O_CREAT|O_APPEND,0600);
    if (fd<0) return;
    (void)write(fd,data.bytes,data.length);
    (void)close(fd);
}
