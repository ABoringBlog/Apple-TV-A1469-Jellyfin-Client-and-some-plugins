#import "JFPlaybackController.h"
#import "JFPlaybackModel.h"
#import "JFPlaybackTrace.h"
#import "API/JFClient.h"
#import "API/JFWorker.h"
NSString * const JFPlaybackChanged=@"JFPlaybackChanged";
@interface JFPlaybackDelivery : NSObject { @public JFPlaybackController *owner; } @end
@implementation JFPlaybackDelivery @end
static NSString *Kind(NSError *error) {
    if ([error.domain isEqual:@"Jellyfin"] && (error.code==401 || error.code==1004)) return @"authentication";
    if (error.code==NSURLErrorTimedOut) return @"timeout";
    if ([error.domain isEqual:NSURLErrorDomain]) return @"transport";
    return @"playback";
}
static NSInteger JFPlaybackTraceCode(NSError **error) { return error && *error ? (*error).code : 0; }
static NSString *JFPlaybackTraceKind(NSError **error) { return Kind(error && *error ? *error : nil); }
@interface JFPlaybackController ()
- (void)backendEvent:(NSString *)event ticks:(long long)ticks generation:(NSUInteger)generation;
- (void)report:(NSString *)event;
- (void)fail:(NSString *)kind;
@end
@implementation JFPlaybackController
@synthesize currentState=_state,errorKind=_errorKind,positionTicks=_position,progressCallback=_progress,failureCallback=_failure;
- (id)initWithClient:(JFClient *)client worker:(JFWorker *)worker backend:(id<JFPlaybackBackend>)backend {
    if ((self=[super init])) {
        if (![NSThread isMainThread] || !client || !worker || !backend) { [self release]; return nil; }
        _client=[client retain]; _worker=[worker retain]; _backend=[backend retain];
        _delivery=[JFPlaybackDelivery new]; _delivery->owner=self;
        _state=[@"idle" copy]; _errorKind=[@"none" copy];
    } return self;
}
- (BOOL)active { return [_state isEqual:@"setup"] || [_state isEqual:@"playing"] || [_state isEqual:@"paused"]; }
- (void)state:(NSString *)state {
    [_state release]; _state=[state copy];
    // Retain across observers which may close/release the UI and this controller.
    [self retain]; [[NSNotificationCenter defaultCenter] postNotificationName:JFPlaybackChanged object:self]; [self release];
}
- (BOOL)playItem:(NSString *)item startTicks:(long long)ticks {
    return [self playItem:item startTicks:ticks mediaSourceID:nil audioIndex:-1 subtitleIndex:-1];
}
- (BOOL)playItem:(NSString *)item startTicks:(long long)ticks mediaSourceID:(NSString *)source audioIndex:(NSInteger)audioIndex {
    return [self playItem:item startTicks:ticks mediaSourceID:source audioIndex:audioIndex subtitleIndex:-1];
}
- (BOOL)playItem:(NSString *)item startTicks:(long long)ticks mediaSourceID:(NSString *)source audioIndex:(NSInteger)audioIndex subtitleIndex:(NSInteger)subtitleIndex {
    BOOL boundSource=source!=nil, hasAudio=audioIndex>=0, hasSubtitle=subtitleIndex>=0;
    if (![NSThread isMainThread] || _closed || [self active] || !JFMediaID(item) || !JFTicks(@(ticks)) ||
        audioIndex < -1 || audioIndex>10000 || subtitleIndex < -1 || subtitleIndex>10000 ||
        (boundSource && !JFMediaID(source)) || (!boundSource && (hasAudio || hasSubtitle))) return NO;
    [self retain]; _generation++; _position=ticks; _reportedStart=NO; _reportBusy=NO; _lastReported=ticks;
    [_plan release]; _plan=nil; [_errorKind release]; _errorKind=[@"none" copy];
    NSUInteger generation=_generation; JFClient *client=_client; JFPlaybackDelivery *delivery=_delivery;
    NSString *identifier=[[item copy] autorelease];
    NSString *selectedSource=[[source copy] autorelease];
    [_setupTask release];
    _setupTask=[[_worker perform:^id(NSError **error) {
        NSTimeInterval setupStarted=[NSProcessInfo processInfo].systemUptime;
        NSDictionary *info=[client playbackInfo:identifier startTicks:ticks mediaSourceID:selectedSource audioIndex:audioIndex subtitleIndex:subtitleIndex error:error];
        NSUInteger playbackInfoMillis=(NSUInteger)MAX(0,([NSProcessInfo processInfo].systemUptime-setupStarted)*1000.0);
        JFPlaybackTrace([NSString stringWithFormat:@"SETUP_PLAYBACKINFO_TIME ms=%lu",(unsigned long)playbackInfoMillis]);
        if (!info || JFWorkCancelled()) {
            if (!JFWorkCancelled()) JFPlaybackTrace([NSString stringWithFormat:@"SETUP_PLAYBACKINFO ok=0 kind=%@ code=%ld",JFPlaybackTraceKind(error),(long)JFPlaybackTraceCode(error)]);
            return nil;
        }
        JFPlaybackTrace(@"SETUP_PLAYBACKINFO ok=1");
        NSDictionary *plan=JFPlaybackPlanForSource(info,identifier,ticks,selectedSource,error);
        if (!plan) {
            JFPlaybackTrace([NSString stringWithFormat:@"SETUP_PLAN ok=0 kind=%@ code=%ld",JFPlaybackTraceKind(error),(long)JFPlaybackTraceCode(error)]);
            return nil;
        }
        if (selectedSource) {
            NSMutableDictionary *bound=[[plan mutableCopy] autorelease];
            if (hasAudio) bound[@"audioStreamIndex"]=@(audioIndex);
            if (hasSubtitle) bound[@"subtitleStreamIndex"]=@(subtitleIndex);
            plan=bound;
        }
        NSString *method=[plan[@"method"] isKindOfClass:[NSString class]] ? plan[@"method"] : @"none";
        JFPlaybackTrace([NSString stringWithFormat:@"SETUP_PLAN ok=1 method=%@ audioBound=%d subtitleBound=%d",method,hasAudio,hasSubtitle]);
        NSURLRequest *request=[client playbackRequest:plan error:error];
        if (!request) JFPlaybackTrace([NSString stringWithFormat:@"SETUP_REQUEST ok=0 kind=%@ code=%ld",JFPlaybackTraceKind(error),(long)JFPlaybackTraceCode(error)]);
        else JFPlaybackTrace([NSString stringWithFormat:@"SETUP_REQUEST ok=1 method=%@",method]);
        return request ? @{@"plan":plan,@"request":request} : nil;
    } completion:^(id result, NSError *error) {
        JFPlaybackController *owner=delivery->owner;
        if (!owner || owner->_closed || owner->_generation!=generation || ![owner->_state isEqual:@"setup"]) return;
        [owner retain];
        if (!result) [owner fail:Kind(error)];
        else {
            owner->_plan=[result[@"plan"] copy];
            [owner->_backend startRequest:result[@"request"] positionTicks:ticks event:^(NSString *event,long long position) {
                JFPlaybackController *target=delivery->owner;
                if (target && [NSThread isMainThread]) { [target retain]; [target backendEvent:event ticks:position generation:generation]; [target release]; }
            }];
        }
        [owner release];
    }] retain];
    [self state:@"setup"]; [self release]; return YES;
}
- (void)report:(NSString *)event {
    if (!_plan || ([event isEqual:@"Stopped"] && !_reportedStart)) return;
    JFPlaybackTrace([NSString stringWithFormat:@"PLAYBACK_REPORT event=%@ ticks=%lld",event,_position]);
    NSDictionary *body=JFPlaybackReport(_plan,_position,[_state isEqual:@"paused"]);
    if (!body) return;
    if ([event isEqual:@"Playing"]) _reportedStart=YES;
    BOOL progress=[event isEqual:@"Progress"];
    if (progress) { _reportBusy=YES; _lastReported=_position; }
    JFClient *client=_client; JFPlaybackDelivery *delivery=_delivery; NSUInteger generation=_generation;
    // Serial queue preserves start/progress/stop ordering. No retry of ambiguous POSTs.
    [_worker perform:^id(NSError **error) { return @([client reportPlayback:event body:body error:error]); }
        completion:^(id result,NSError *error) {
            JFPlaybackController *owner=delivery->owner;
            if (!owner || owner->_closed || owner->_generation!=generation) return;
            [owner retain];
            if (progress) owner->_reportBusy=NO;
            BOOL ok=[result boolValue];
            JFPlaybackTrace([NSString stringWithFormat:@"PLAYBACK_REPORT_RESULT event=%@ ok=%d kind=%@",event,ok,ok ? @"none" : Kind(error)]);
            if (!ok) [owner fail:Kind(error)];
            [owner release];
        }];
}
- (void)backendEvent:(NSString *)event ticks:(long long)ticks generation:(NSUInteger)generation {
    if (_closed || _generation!=generation || ![self active]) return;
    if ([event isEqual:@"failure"]) { [self fail:@"playback"]; return; }
    if ([event isEqual:@"started"]) {
        if (![_state isEqual:@"setup"] || !_plan) return;
        if (ticks>0 && JFTicks(@(ticks)) && ticks<=[_plan[@"durationTicks"] longLongValue]) _position=ticks;
        [self report:@"Playing"]; [self state:@"playing"]; return;
    }
    if ([_state isEqual:@"setup"]) return;
    if ([event isEqual:@"paused"]) {
        if (![_state isEqual:@"playing"]) return;
        if (JFTicks(@(ticks)) && ticks<=[_plan[@"durationTicks"] longLongValue]) _position=ticks;
        [self state:@"paused"];
        if (!_closed && [_state isEqual:@"paused"]) [self report:@"Progress"];
        return;
    }
    if ([event isEqual:@"resumed"]) {
        if (![_state isEqual:@"paused"]) return;
        if (JFTicks(@(ticks)) && ticks<=[_plan[@"durationTicks"] longLongValue]) _position=ticks;
        [self state:@"playing"];
        if (!_closed && [_state isEqual:@"playing"]) [self report:@"Progress"];
        return;
    }
    if ([event isEqual:@"ended"]) {
        // Native end notification is authoritative: natural completion is the full duration.
        _position=[_plan[@"durationTicks"] longLongValue];
        [self stop]; return;
    }
    if ([event isEqual:@"popped"]) {
        if (JFTicks(@(ticks)) && ticks<=[_plan[@"durationTicks"] longLongValue]) _position=ticks;
        [self stop]; return;
    }
    if (![event isEqual:@"progress"] || !JFTicks(@(ticks)) || ticks>[_plan[@"durationTicks"] longLongValue] || [_state isEqual:@"paused"]) return;
    BOOL movedBackward=ticks<_position;
    _position=ticks;
    if (!_reportBusy && (movedBackward || ticks<_lastReported || ticks-_lastReported>=100000000LL)) [self report:@"Progress"];
    void (^callback)(long long)=[_progress copy];
    if (callback) callback(ticks);
    [callback release];
}
- (long long)resumeTicksForItem:(NSString *)item {
    if (![NSThread isMainThread] || _closed || !JFMediaID(item) || ![_plan[@"itemID"] isEqual:item]) return 0;
    long long duration=[_plan[@"durationTicks"] longLongValue];
    return _position>0 && duration>0 && _position<duration ? _position : 0;
}
- (BOOL)pause {
    if (![NSThread isMainThread] || _closed || ![_state isEqual:@"playing"]) return NO;
    [self retain]; [_backend pause];
    if (!_closed && [_state isEqual:@"playing"]) { [self state:@"paused"]; if (!_closed && [_state isEqual:@"paused"]) [self report:@"Progress"]; }
    [self release]; return YES;
}
- (BOOL)resume {
    if (![NSThread isMainThread] || _closed || ![_state isEqual:@"paused"]) return NO;
    [self retain]; [_backend resume];
    if (!_closed && [_state isEqual:@"paused"]) { [self state:@"playing"]; if (!_closed && [_state isEqual:@"playing"]) [self report:@"Progress"]; }
    [self release]; return YES;
}
- (BOOL)seek:(long long)ticks {
    if (![NSThread isMainThread] || _closed || (![_state isEqual:@"playing"] && ![_state isEqual:@"paused"]) || !JFTicks(@(ticks)) || ticks>[_plan[@"durationTicks"] longLongValue]) return NO;
    [self retain]; _position=ticks; _generation++; _reportBusy=NO;
    NSUInteger generation=_generation; JFPlaybackDelivery *delivery=_delivery;
    [_backend seek:ticks event:^(NSString *event, long long position) {
        JFPlaybackController *target=delivery->owner;
        if (target && [NSThread isMainThread]) { [target retain]; [target backendEvent:event ticks:position generation:generation]; [target release]; }
    }];
    if (!_closed && [self active]) [self report:@"Progress"];
    [self release]; return YES;
}
- (BOOL)stop {
    if (![NSThread isMainThread] || _closed || ![self active]) return NO;
    [self retain]; [_setupTask cancel]; _generation++; // Reject synchronous/late backend callbacks before stop.
    [self report:@"Stopped"]; _reportedStart=NO;
    [_backend stop]; [self state:@"stopped"]; [self release]; return YES;
}
- (void)fail:(NSString *)kind {
    if (_closed) return;
    [self retain]; [_setupTask cancel]; _generation++;
    // A 401 invalidates the client; do not send another authenticated request.
    if (![kind isEqual:@"authentication"]) [self report:@"Stopped"];
    _reportedStart=NO; [_backend stop]; [_errorKind release]; _errorKind=[kind copy];
    [self state:@"failed"];
    void (^callback)(NSString *)=[_failure copy];
    if (!_closed && callback) callback(kind);
    [callback release]; [self release];
}
- (void)invalidateSession { if ([NSThread isMainThread] && !_closed) { [self stop]; _generation++; } }
- (void)close {
    if (![NSThread isMainThread] || _closed) return;
    // No notification on close: host removes observations before releasing ownership.
    [_setupTask cancel]; _generation++; [self report:@"Stopped"]; _reportedStart=NO;
    _closed=YES; if (_delivery) _delivery->owner=nil; [_backend stop];
    [_state release]; _state=[@"closed" copy];
    self.progressCallback=nil; self.failureCallback=nil;
}
- (void)dealloc {
    [self close]; [_setupTask release]; [_delivery release]; [_client release]; [_worker release]; [_backend release]; [_plan release]; [_state release]; [_errorKind release]; [super dealloc];
}
@end
@implementation JFMockPlaybackBackend
@synthesize starts=_starts,stops=_stops;
- (void)startRequest:(NSURLRequest *)request positionTicks:(long long)ticks event:(JFBackendEvent)event { [_event release]; _event=[event copy]; _starts++; }
- (void)pause {}
- (void)resume {}
- (void)seek:(long long)ticks event:(JFBackendEvent)event { [_event release]; _event=[event copy]; }
- (void)stop { _stops++; [_event release]; _event=nil; }
- (void)emit:(NSString *)event ticks:(long long)ticks { JFBackendEvent callback=[_event copy]; if (callback) callback(event,ticks); [callback release]; }
- (JFBackendEvent)capturedEvent { return [[_event copy] autorelease]; }
- (void)dealloc { [_event release]; [super dealloc]; }
@end
