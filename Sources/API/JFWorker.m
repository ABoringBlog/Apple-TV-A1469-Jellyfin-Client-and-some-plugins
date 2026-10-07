#import "JFWorker.h"
static NSString * const TaskKey = @"org.jellyfin.atv3.currentTask";
BOOL JFWorkCancelled(void) {
    return [[[[NSThread currentThread] threadDictionary] objectForKey:TaskKey] isCancelled];
}
@implementation JFTask
- (void)cancel { @synchronized(self) { _deliveryCancelled=YES; } [super cancel]; }
- (BOOL)isCancelled { @synchronized(self) { return _deliveryCancelled || [super isCancelled]; } }
- (BOOL)needsTracking { @synchronized(self) { return ![self isFinished] || (!_deliveryConsumed && ![self isCancelled]); } }
- (id)initWithWork:(id (^)(NSError **))work completion:(void (^)(id, NSError *))completion {
    if ((self=[super init])) { _work=[work copy]; _delivery=[completion copy]; }
    return self;
}
- (void)main {
    @autoreleasepool {
        if ([self isCancelled]) return;
        NSMutableDictionary *context=[[NSThread currentThread] threadDictionary];
        [context setObject:self forKey:TaskKey];
        NSError *error=nil; id result=nil;
        @try { result=[_work(&error) retain]; [error retain]; }
        @finally { [context removeObjectForKey:TaskKey]; [_work release]; _work=nil; }
        if (![self isCancelled] && _delivery) {
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                if (![self isCancelled]) _delivery(result,error);
                [_delivery release]; _delivery=nil;
                @synchronized(self) { _deliveryConsumed=YES; }
            }];
        } else {
            [_delivery release]; _delivery=nil;
            @synchronized(self) { _deliveryConsumed=YES; }
        }
        [result release]; [error release];
    }
}
- (void)dealloc { [_work release]; [_delivery release]; [super dealloc]; }
@end
@implementation JFWorker
- (id)init { if ((self=[super init])) { _tasks=[NSMutableArray new]; _queue=[NSOperationQueue new]; [_queue setMaxConcurrentOperationCount:1]; } return self; }
- (JFTask *)perform:(id (^)(NSError **))work completion:(void (^)(id, NSError *))completion {
    if (!work) return nil;
    JFTask *task=[[[JFTask alloc] initWithWork:work completion:completion] autorelease];
    @synchronized(self) {
        for (JFTask *old in [[_tasks copy] autorelease]) if (![old needsTracking]) [_tasks removeObjectIdenticalTo:old];
        [_tasks addObject:task]; [_queue addOperation:task];
    }
    return task;
}
- (void)cancelAll { @synchronized(self) { for (JFTask *task in _tasks) [task cancel]; [_tasks removeAllObjects]; } }
- (void)dealloc { [self cancelAll]; [_queue release]; [_tasks release]; [super dealloc]; }
@end
