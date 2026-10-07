#import <Foundation/Foundation.h>
#import "BackRow/JFSessionHost.h"
#import "Navigation/JFSession.h"
#import "Navigation/JFBrowser.h"
static int checks;
#define CHECK(...) do { checks++; if (!(__VA_ARGS__)) { NSLog(@"FAIL line %d: %s",__LINE__,#__VA_ARGS__); exit(1); } } while(0)
static void Idle(JFSession *session) {
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:5];
    while (session.busy && deadline.timeIntervalSinceNow>0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    CHECK(!session.busy);
}
static NSDictionary *Event(JFButton button, NSString *phase) { return @{@"button":@(button),@"phase":phase}; }
// Mock host executes no BackRow selectors. Exit requests alone never pop a controller.
@interface MockHost : NSObject {
@public JFSessionHost *adapter; NSUInteger exitRequests;
}
- (JFHostEventResult)send:(NSDictionary *)event;
@end
@implementation MockHost
- (JFHostEventResult)send:(NSDictionary *)event {
    JFHostEventResult result=[adapter handleRemoteEvent:event];
    if (result==JFHostEventExitRequested) exitRequests++;
    return result;
}
- (void)dealloc { [adapter close]; [adapter release]; [super dealloc]; }
@end
int main(void) { @autoreleasepool {
    [NSURLProtocol registerClass:NSClassFromString(@"JFFixtureProtocol")];
    JFSession *session=[[JFSession alloc] initWithURL:[NSURL URLWithString:@"http://fixture.invalid/jellyfin"] deviceID:@"test-device" allowHTTP:YES];
    MockHost *host=[MockHost new]; host->adapter=[[JFSessionHost alloc] initWithSession:session];
    CHECK([host send:Event(JFMenu,@"press")]==JFHostEventExitRequested);
    CHECK(!session.closed && host->exitRequests==1);
    for (NSString *phase in @[@"release",@"repeat",@"hold"])
        CHECK([host send:Event(JFMenu,phase)]==JFHostEventConsumed);
    CHECK(host->exitRequests==1);
    for (id invalid in @[@{}, @{@"button":@99,@"phase":@"press"}, @{@"button":@1.5,@"phase":@"press"}, @{@"button":@"1",@"phase":@"press"}, @{@"button":@1,@"phase":@"invalid"}, @[]])
        CHECK([host send:invalid]==JFHostEventUnhandled);
    CHECK([session login:@"测试用户" password:@"p\"ass"]);
    CHECK([host send:Event(JFMenu,@"press")]==JFHostEventConsumed);
    CHECK([host send:Event(JFSelect,@"press")]==JFHostEventConsumed);
    CHECK(host->exitRequests==1); Idle(session);
    CHECK([session.snapshot[@"page"] integerValue]==JFLibrariesPage);
    CHECK([host send:Event(JFSelect,@"press")]==JFHostEventConsumed); Idle(session);
    CHECK([session.snapshot[@"page"] integerValue]==JFLibraryPage);
    CHECK([host send:Event(JFMenu,@"press")]==JFHostEventConsumed); Idle(session);
    CHECK([session.snapshot[@"page"] integerValue]==JFLibrariesPage);
    CHECK([session openLibraryWithType:@"Movie"]); Idle(session);
    CHECK([host send:Event(JFSelect,@"release")]==JFHostEventConsumed);
    CHECK(!session.busy && [session.snapshot[@"page"] integerValue]==JFMediaPage);
    CHECK([host send:Event(JFSelect,@"press")]==JFHostEventConsumed); Idle(session);
    CHECK([session.snapshot[@"page"] integerValue]==JFDetailPage);
    CHECK([host send:Event(JFSelect,@"press")]==JFHostEventConsumed);
    CHECK(!session.busy); // no guessed player entry point
    for (NSNumber *page in @[@(JFMediaPage),@(JFLibrariesPage)]) {
        CHECK([host send:Event(JFMenu,@"press")]==JFHostEventConsumed); Idle(session);
        CHECK([session.snapshot[@"page"] isEqual:page]);
    }
    CHECK(host->exitRequests==1);
    CHECK([host send:Event(JFMenu,@"press")]==JFHostEventExitRequested);
    CHECK(host->exitRequests==2);
    CHECK([session refresh]);
    [host release]; // host destruction closes during pending work
    CHECK(session.closed && !session.busy && [session.snapshot[@"page"] integerValue]==JFLoginPage);
    CHECK(![session refresh]);
    CHECK(![[JFSessionHost alloc] initWithSession:session]);
    [session release];
    printf("PASS: %d host boundary assertions\n",checks);
} }
