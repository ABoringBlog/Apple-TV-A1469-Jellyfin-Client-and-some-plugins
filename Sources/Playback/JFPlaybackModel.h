#import <Foundation/Foundation.h>
// Pure, conservative planning. All hardware capabilities remain PROVISIONAL.
BOOL JFMediaID(id value);
BOOL JFTicks(id value);
NSDictionary *JFProvisionalDeviceProfile(void);
NSDictionary *JFPlaybackBody(long long startTicks, NSInteger subtitleIndex);
NSDictionary *JFPlaybackPlan(NSDictionary *info, NSString *itemID, long long startTicks, NSError **error);
NSDictionary *JFPlaybackPlanForSource(NSDictionary *info, NSString *itemID, long long startTicks, NSString *sourceID, NSError **error);
NSDictionary *JFPlaybackReport(NSDictionary *plan, long long ticks, BOOL paused);
