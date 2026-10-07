#import "JFPosterTrace.h"
#include <fcntl.h>
#include <unistd.h>

void JFPosterTrace(NSString *event) {
    if (![event isKindOfClass:[NSString class]] || !event.length) return;
    NSString *line=[event stringByAppendingString:@"\n"];
    NSData *data=[line dataUsingEncoding:NSUTF8StringEncoding];
    if (!data.length) return;
    int fd=open("/tmp/Jellyfin-ATV3.postertrace",O_WRONLY|O_CREAT|O_APPEND,0600);
    if (fd<0) return;
    (void)write(fd,[data bytes],[data length]);
    (void)close(fd);
}
