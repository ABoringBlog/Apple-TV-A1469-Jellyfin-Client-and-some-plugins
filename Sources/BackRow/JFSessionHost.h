#import <Foundation/Foundation.h>
@class JFSession;
typedef NS_ENUM(NSInteger, JFHostEventResult) {
    JFHostEventUnhandled, JFHostEventConsumed, JFHostEventExitRequested
};
// Firmware-independent boundary for a future controller. No runtime selectors.
// Main-thread only; the controller owns this adapter and observes its session.
@interface JFSessionHost : NSObject {
    JFSession *_session;
    BOOL _closed;
}
- (id)initWithSession:(JFSession *)session;
// Accepts normalized JFRemote button/phase dictionaries, not private BackRow events.
// Busy input is consumed/dropped. Root Menu press requests host exit without popping.
- (JFHostEventResult)handleRemoteEvent:(NSDictionary *)event;
// Host calls after removing UI observers, before actual removal/replacement.
- (void)close;
@end
