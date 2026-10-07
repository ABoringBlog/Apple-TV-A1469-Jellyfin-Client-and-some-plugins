#import <Foundation/Foundation.h>
// Pure validation/label policy for selectable audio streams. No playback side effects.
NSArray *JFAudioTracks(NSArray *sources, NSError **error);
NSDictionary *JFAudioDefaultTrack(NSArray *tracks);
NSString *JFAudioTrackLabel(NSDictionary *track);
