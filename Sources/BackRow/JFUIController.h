#import "JFBRMenu.h"
#import "Playback/JFPlaybackController.h"
@class JFSession, JFSessionHost;
// Presentation/controller bridge only; networking and model state stay in JFSession.
@interface JFUIController : JFBRMenu {
    JFSession *_session;
    id<JFPlaybackBackend> _playbackBackend;
    JFSessionHost *_host;
    NSString *_server, *_username, *_password, *_message;
    NSUserDefaults *_configurationDefaults;
    id _editor;
    NSData *_previewSourceData, *_previewDisplayData;
    NSUInteger _editKind;
    NSInteger _page;
    BOOL _allowHTTP, _observing, _passwordEntered, _previewSideInset;
}
- (BOOL)configurePlaybackBackend:(id<JFPlaybackBackend>)backend;
@property(nonatomic, readonly) JFPlaybackController *playback;
- (id)previewControlForRow:(long)row;
- (void)textDidChange:(id)sender;
- (void)textDidEndEditing:(id)sender;
@end
