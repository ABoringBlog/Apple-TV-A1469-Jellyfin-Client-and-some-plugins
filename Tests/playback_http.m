#import <Foundation/Foundation.h>
#import "API/JFClient.h"
#import "Playback/JFPlaybackModel.h"
static int checks;
#define CHECK(...) do { checks++; if (!(__VA_ARGS__)) { fprintf(stderr,"FAIL playback HTTP line %d\n",__LINE__); return 1; } } while(0)
int main(int argc,char **argv) { @autoreleasepool {
    if (argc!=2) return 2;
    JFClient *client=[[[JFClient alloc] initWithURL:[NSURL URLWithString:[NSString stringWithUTF8String:argv[1]]] deviceID:@"test-device"] autorelease];
    NSError *error=nil;
    CHECK([client login:@"测试用户" password:@"p\"ass" error:&error]);
    NSDictionary *info=[client playbackInfo:@"movie1" startTicks:100 subtitleIndex:-1 error:&error]; CHECK(info);
    NSDictionary *plan=JFPlaybackPlan(info,@"movie1",100,&error); CHECK(plan); CHECK([client playbackRequest:plan error:&error]);
    for (NSString *event in @[@"Playing",@"Progress",@"Stopped"]) CHECK([client reportPlayback:event body:JFPlaybackReport(plan,100,NO) error:&error]);
    CHECK([client subtitleData:@"movie1" mediaSource:@"source1" index:2 error:&error]);
    CHECK(![client subtitleData:@"movie1" mediaSource:@"source1" index:99 error:&error]);
    for (NSString *item in @[@"empty",@"malformed"]) { NSDictionary *bad=[client playbackInfo:item startTicks:0 subtitleIndex:-1 error:&error]; CHECK(!JFPlaybackPlan(bad,item,0,&error)); }
    CHECK(![client playbackInfo:@"oversized" startTicks:0 subtitleIndex:-1 error:&error] && error.code==413);
    CHECK(![client imageData:@"oversized" backdrop:NO width:320 cache:nil error:&error] && error.code==413);
    CHECK(![client imageData:@"broken" backdrop:NO width:320 cache:nil error:&error] && error.code==1009);
    CHECK(![client playbackInfo:@"disconnect" startTicks:0 subtitleIndex:-1 error:&error]);
    client.timeout=0.1;
    CHECK(![client playbackInfo:@"slow" startTicks:0 subtitleIndex:-1 error:&error] && error.code==NSURLErrorTimedOut);
    client.timeout=15;
    CHECK(![client playbackInfo:@"expired" startTicks:0 subtitleIndex:-1 error:&error] && error.code==401); CHECK(!client.hasSession);
    printf("PASS: %d playback HTTP assertions\n",checks);
} return 0; }
