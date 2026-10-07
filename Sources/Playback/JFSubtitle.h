#import <Foundation/Foundation.h>
// Data/selection policy only. No device subtitle support is asserted.
NSArray *JFSubtitleTracks(NSArray *streams, NSError **error);
NSArray *JFSubtitleTracksForSources(NSArray *sources, NSError **error);
NSDictionary *JFSubtitleSelection(NSArray *tracks, NSInteger index, BOOL preserveStyling, NSError **error);
NSString *JFSubtitleTrackLabel(NSDictionary *track);
NSString *JFSubtitleText(NSData *data, NSError **error);
