#import <Foundation/Foundation.h>
@class JFClient, JFWorker, JFTask, JFPlaybackDelivery;
// Every backend callback and command runs on main. The 12H1006 native adapter is runtime-gated.
typedef void (^JFBackendEvent)(NSString *event, long long ticks);
@protocol JFPlaybackBackend <NSObject>
- (void)startRequest:(NSURLRequest *)request positionTicks:(long long)ticks event:(JFBackendEvent)event;
- (void)pause;
- (void)resume;
- (void)seek:(long long)ticks event:(JFBackendEvent)event;
- (void)stop;
@end
extern NSString * const JFPlaybackChanged;
@interface JFPlaybackController : NSObject {
    JFClient *_client;
    JFWorker *_worker;
    JFTask *_setupTask;
    JFPlaybackDelivery *_delivery;
    id<JFPlaybackBackend> _backend;
    NSDictionary *_plan;
    NSString *_state, *_errorKind;
    NSUInteger _generation;
    long long _position;
    BOOL _closed, _reportedStart, _reportBusy;
    long long _lastReported;
    void (^_progress)(long long);
    void (^_failure)(NSString *);
}
// Client/worker must have the same exclusive serial owner (the enclosing JFSession).
- (id)initWithClient:(JFClient *)client worker:(JFWorker *)worker backend:(id<JFPlaybackBackend>)backend;
@property(nonatomic, readonly, copy) NSString *currentState; // idle/setup/playing/paused/stopped/failed/closed
@property(nonatomic, readonly, copy) NSString *errorKind;
@property(nonatomic, readonly) long long positionTicks;
@property(nonatomic, copy) void (^progressCallback)(long long ticks);
@property(nonatomic, copy) void (^failureCallback)(NSString *kind);
- (BOOL)playItem:(NSString *)item startTicks:(long long)ticks;
- (BOOL)playItem:(NSString *)item startTicks:(long long)ticks mediaSourceID:(NSString *)source audioIndex:(NSInteger)audioIndex;
- (BOOL)playItem:(NSString *)item startTicks:(long long)ticks mediaSourceID:(NSString *)source audioIndex:(NSInteger)audioIndex subtitleIndex:(NSInteger)subtitleIndex;
// Returns a locally retained resume point only when it belongs to this exact item and is inside duration.
- (long long)resumeTicksForItem:(NSString *)item;
- (BOOL)pause;
- (BOOL)resume;
- (BOOL)seek:(long long)ticks;
- (BOOL)stop;
- (void)invalidateSession;
- (void)close;
@end
// Deliberately inert until tests call emit:; never decodes or opens a media URL.
@interface JFMockPlaybackBackend : NSObject <JFPlaybackBackend> {
    JFBackendEvent _event;
    NSUInteger _starts, _stops;
}
@property(nonatomic, readonly) NSUInteger starts;
@property(nonatomic, readonly) NSUInteger stops;
- (void)emit:(NSString *)event ticks:(long long)ticks;
- (JFBackendEvent)capturedEvent;
@end
