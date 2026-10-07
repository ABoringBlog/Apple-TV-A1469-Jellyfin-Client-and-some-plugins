#import <Foundation/Foundation.h>
#import "JFPlaybackController.h"
@class JFMediaGateway;

// Native 12H1006 playback adapter. All public commands and callbacks are main-thread only.
@interface JFATV3PlaybackBackend : NSObject <JFPlaybackBackend> {
    id _hostController;
    NSURLRequest *_preparedRequest;
    id _asset, _player, _playerController;
    JFMediaGateway *_gateway;
    JFBackendEvent _event;
    long long _positionTicks, _lastTicks;
    NSTimeInterval _ignoreNativeRateUntil;
    BOOL _presented, _started, _stopping, _nativePaused;
}
+ (BOOL)runtimeCompatible;
- (id)initWithHostController:(id)controller;
- (BOOL)prepareRequest:(NSURLRequest *)request positionTicks:(long long)ticks error:(NSError **)error;
- (void)discardPreparedPlayback;
@property(nonatomic, readonly) BOOL prepared;
@property(nonatomic, readonly) id preparedAsset;
@property(nonatomic, readonly) id preparedPlayer;
@property(nonatomic, readonly) id preparedPlayerController;
@end
