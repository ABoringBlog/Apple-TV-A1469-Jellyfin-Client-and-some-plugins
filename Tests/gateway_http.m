#import <Foundation/Foundation.h>
#import "Playback/JFMediaGateway.h"
static unsigned checks;
#define CHECK(x) do { checks++; if (!(x)) { fprintf(stderr,"gateway FAIL line %d\n",__LINE__); exit(1); } } while(0)
static NSData *Fetch(NSString *url, NSInteger *status) {
    NSURLRequest *request=[NSURLRequest requestWithURL:[NSURL URLWithString:url] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:20];
    NSURLResponse *response=nil; NSError *error=nil;
    NSData *data=[NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
    *status=[(NSHTTPURLResponse *)response statusCode]; return data;
}
static NSString *Text(NSData *data) { return [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease]; }
static NSString *FirstURL(NSData *data) {
    for (NSString *line in [Text(data) componentsSeparatedByString:@"\n"]) if ([line hasPrefix:@"http://"]) return line;
    return nil;
}
int main(int argc, const char **argv) { @autoreleasepool {
    CHECK(argc==2);
    NSString *base=[NSString stringWithUTF8String:argv[1]];
    for (NSString *path in @[@"/plain/clip.mp4",@"/plain/master.m3u8",@"/encrypted/master.m3u8",@"/same/master.m3u8",@"/cross/master.m3u8",@"/child/master.m3u8",@"/segment-redirect/master.m3u8"]) {
        @autoreleasepool {
            NSMutableURLRequest *source=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:[base stringByAppendingString:path]]];
            [source setValue:@"Bearer JF-PROBE-ONLY-12H1006" forHTTPHeaderField:@"Authorization"];
            JFMediaGateway *gateway=[[JFMediaGateway alloc] initWithRequest:source];
            CHECK([gateway start:NULL]); NSInteger status=0;
            NSData *data=Fetch(gateway.localRequest.URL.absoluteString,&status);
            if ([path hasPrefix:@"/same/"] || [path hasPrefix:@"/cross/"]) CHECK(status==502);
            else {
                CHECK(status==200 && data.length>0);
                if ([path hasSuffix:@"m3u8"]) {
                    CHECK(![Text(data) containsString:@"JF-PROBE"]);
                    NSString *mediaURL=FirstURL(data); CHECK(mediaURL!=nil);
                    NSData *media=Fetch(mediaURL,&status);
                    if ([path hasPrefix:@"/child/"]) CHECK(status==502);
                    else {
                        CHECK(status==200);
                        if ([path hasPrefix:@"/encrypted/"]) {
                            NSRegularExpression *re=[NSRegularExpression regularExpressionWithPattern:@"URI=\"([^\"]*)\"" options:0 error:NULL];
                            NSTextCheckingResult *m=[re firstMatchInString:Text(media) options:0 range:NSMakeRange(0,Text(media).length)]; CHECK(m!=nil);
                            NSData *key=Fetch([Text(media) substringWithRange:[m rangeAtIndex:1]],&status); CHECK(status==200 && key.length==16);
                        }
                        for (NSString *segment in [Text(media) componentsSeparatedByString:@"\n"]) if ([segment hasPrefix:@"http://"]) {
                            NSData *bytes=Fetch(segment,&status);
                            if ([path hasPrefix:@"/segment-redirect/"]) CHECK(status==502);
                            else CHECK(status==200 && bytes.length>0);
                        }
                    }
                }
            }
            [gateway stop]; [gateway release];
        }
    }
    fprintf(stdout,"PASS: %u gateway HTTP assertions\n",checks);
} return 0; }
