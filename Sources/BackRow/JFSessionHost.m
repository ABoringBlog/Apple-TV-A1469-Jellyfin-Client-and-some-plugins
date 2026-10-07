#import "JFSessionHost.h"
#import "Navigation/JFSession.h"
#import "Navigation/JFBrowser.h"
@implementation JFSessionHost
- (id)initWithSession:(JFSession *)session {
    if ((self=[super init])) {
        if (![NSThread isMainThread] || !session || session.closed) { [self release]; return nil; }
        _session=[session retain];
    }
    return self;
}
- (JFHostEventResult)handleRemoteEvent:(NSDictionary *)event {
    if (![NSThread isMainThread] || _closed || _session.closed || ![event isKindOfClass:[NSDictionary class]]) return JFHostEventUnhandled;
    id button=event[@"button"], phase=event[@"phase"];
    if (![button isKindOfClass:[NSNumber class]] || ![phase isKindOfClass:[NSString class]] ||
        ![@[@"press",@"release",@"repeat",@"hold"] containsObject:phase]) return JFHostEventUnhandled;
    NSInteger b=[button integerValue];
    if (b<JFUp || b>JFMenu || ![button isEqualToNumber:@(b)]) return JFHostEventUnhandled;
    // Do not turn a busy navigation rejection into an accidental controller pop.
    if (_session.busy) return JFHostEventConsumed;
    NSInteger page=[_session.snapshot[@"page"] integerValue];
    if (b==JFMenu) {
        if ([phase isEqual:@"press"]) {
            if (page==JFLoginPage || page==JFLibrariesPage) return JFHostEventExitRequested;
            [_session goBack];
        }
        return JFHostEventConsumed;
    }
    if (b==JFSelect && [phase isEqual:@"press"] && page>=JFMediaPage && page!=JFDetailPage) {
        NSInteger index=[_session.snapshot[@"mediaIndex"] integerValue];
        if (index!=NSNotFound && index>=0) [_session openMediaAtIndex:(NSUInteger)index];
    } else [_session handleEvent:event];
    // Library type selection, login entry and playback are explicit host actions.
    return JFHostEventConsumed;
}
- (void)close {
    if (![NSThread isMainThread] || _closed) return;
    _closed=YES; [_session close];
}
- (void)dealloc {
    NSAssert([NSThread isMainThread], @"Release JFSessionHost on main thread");
    [self close]; [_session release]; [super dealloc];
}
@end
