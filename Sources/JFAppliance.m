#import "BackRow/JFBackRow.h"
#import "Playback/JFATV3PlaybackProbe.h"
// Real class keeps bundleForClass available without referencing private classes.
@interface JFBundleAnchor : NSObject @end
@implementation JFBundleAnchor @end
__attribute__((constructor)) static void JellyfinEntry(void) {
    @autoreleasepool { JFRegisterBackRowClasses(); JFATV3SchedulePlaybackProbeIfEnabled(); }
}
