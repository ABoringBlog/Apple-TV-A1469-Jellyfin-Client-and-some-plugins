#import <Foundation/Foundation.h>
// A serial owner for client/model work. Do not also access those objects on another thread.
// Work captures retain their objects until completion. Delivery runs on the main queue.
// Cancellation suppresses delivery, including delivery already queued on the main queue.
// A UI owner must cancel its tasks before closing; avoid retaining that owner in callbacks.
@interface JFTask : NSOperation {
    BOOL _deliveryCancelled, _deliveryConsumed;
    id (^_work)(NSError **);
    void (^_delivery)(id, NSError *);
}
@end
@interface JFWorker : NSObject {
    NSOperationQueue *_queue;
    NSMutableArray *_tasks;
}
- (JFTask *)perform:(id (^)(NSError **error))work completion:(void (^)(id result, NSError *error))completion;
- (void)cancelAll;
@end
BOOL JFWorkCancelled(void);
