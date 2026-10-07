#import <Foundation/Foundation.h>
typedef NS_ENUM(NSInteger, JFButton) { JFUnknown, JFUp, JFDown, JFLeft, JFRight, JFSelect, JFMenu };
@interface JFRemote : NSObject {
    NSInteger _active; NSTimeInterval _started; BOOL _held;
}
// Returns button/phase (press, release, hold, repeat); unknown events return nil.
- (NSDictionary *)action:(NSInteger)action value:(NSInteger)value time:(NSTimeInterval)time;
@end
