#import "JFUIController.h"
#import "JFBackRow.h"
#import "JFPosterTrace.h"
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>
#import "Navigation/JFSession.h"
#import "Navigation/JFBrowser.h"
#import "Navigation/JFMovieMetadata.h"
#import "Navigation/JFSeriesMetadata.h"
#import "Navigation/JFDetailMetadata.h"
#import "Input/JFRemote.h"
#import "API/JFServerURL.h"
#import "Playback/JFPlaybackTrace.h"
#import <objc/message.h>
#include <string.h>
static id JFNewTextEntryController(void) {
    Class cls=NSClassFromString(@"BRTextEntryController");
#if !defined(__arm__)
    return JFBRNew(cls);
#else
    SEL selector=NSSelectorFromString(@"initWithTextEntryStyle:");
    NSMethodSignature *signature=[cls instanceMethodSignatureForSelector:selector];
    if (!signature || strcmp(signature.methodReturnType,@encode(id)) || signature.numberOfArguments!=3 || strcmp([signature getArgumentTypeAtIndex:2],@encode(int))) return nil;
    return ((id(*)(id,SEL,int))objc_msgSend)([cls alloc],selector,4);
#endif
}
static BOOL JFValidPersistedToken(id value) {
    return [value isKindOfClass:[NSString class]] && [value length] && [value length]<=8192 &&
        [value rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location==NSNotFound;
}
static NSDictionary *Row(NSString *title, NSString *action, BOOL enabled) {
    return @{@"title":title ?: @"",@"action":action,@"enabled":@(enabled)};
}
@interface JFUIController ()
- (void)refreshView;
- (void)clearEditor;
- (void)clearSession;
- (void)saveConfiguration;
- (NSString *)deviceID;
- (void)clearSessionCredential;
- (void)saveSessionCredential;
- (void)syncSessionCredential;
- (void)restoreSessionIfPossible;
- (void)signIn;
@end

static NSData *JFPosterDataWithInset(NSData *data, BOOL sideInset) {
    if (![data isKindOfClass:[NSData class]] || !data.length) return data;
    CGImageSourceRef source=CGImageSourceCreateWithData((CFDataRef)data,NULL);
    if (!source) return data;
    CGImageRef image=CGImageSourceCreateImageAtIndex(source,0,NULL);
    CFRelease(source);
    if (!image) return data;
    size_t width=CGImageGetWidth(image), height=CGImageGetHeight(image);
    if (!width || !height) { CGImageRelease(image); return data; }
    size_t insetY=(size_t)MAX(1.0,floor((double)height*0.04));
    size_t insetX=sideInset ? (size_t)MAX(1.0,floor((double)width*0.04)) : 0;
    size_t canvasWidth=width+insetX*2, canvasHeight=height+insetY*2;
    CGColorSpaceRef colorSpace=CGColorSpaceCreateDeviceRGB();
    CGContextRef context=CGBitmapContextCreate(NULL,canvasWidth,canvasHeight,8,canvasWidth*4,colorSpace,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
    if (!context) { CGImageRelease(image); return data; }
    CGContextClearRect(context,CGRectMake(0,0,canvasWidth,canvasHeight));
    CGContextDrawImage(context,CGRectMake(insetX,insetY,width,height),image);
    CGImageRef padded=CGBitmapContextCreateImage(context);
    CGContextRelease(context); CGImageRelease(image);
    if (!padded) return data;
    NSMutableData *encoded=[NSMutableData data];
    CGImageDestinationRef destination=CGImageDestinationCreateWithData((CFMutableDataRef)encoded,CFSTR("public.png"),1,NULL);
    if (!destination) { CGImageRelease(padded); return data; }
    CGImageDestinationAddImage(destination,padded,NULL);
    BOOL ok=CGImageDestinationFinalize(destination);
    CFRelease(destination); CGImageRelease(padded);
    return ok && encoded.length ? encoded : data;
}

@implementation JFUIController
+ (NSUserDefaults *)configurationDefaults {
    return [[[NSUserDefaults alloc] initWithSuiteName:@"org.jellyfin.atv3"] autorelease];
}

- (id)initWithController:(id)controller {
    if ((self=[super initWithController:controller])) {
        _configurationDefaults=[[[self class] configurationDefaults] retain];
        id saved=[_configurationDefaults objectForKey:@"ServerConfiguration"];
        NSDictionary *config=[saved isKindOfClass:[NSDictionary class]] ? saved : @{};
        NSString *address=JFNormalizeServerAddress(config[@"server"],NULL);
        _server=[(address ?: @"") copy];
        _username=[([config[@"username"] isKindOfClass:[NSString class]] ? config[@"username"] : @"") copy];
        _allowHTTP=[config[@"allowHTTP"] isKindOfClass:[NSNumber class]] && [config[@"allowHTTP"] boolValue];
        _password=[@"" copy]; _message=[@"" copy]; _page=JFLoginPage;
        [self restoreSessionIfPossible];
        [self refreshView];
    }
    return self;
}
- (JFPlaybackController *)playback { return _session.playback; }
- (id)previewControlForRow:(long)row {
    NSInteger page=_session ? [_session.snapshot[@"page"] integerValue] : -1;
    JFPosterTrace([NSString stringWithFormat:@"UI_PREVIEW_ENTER row=%ld page=%ld",row,(long)page]);
    BOOL detailPage=page==JFDetailPage;
    if (_closed || !_session || ![@[@(JFMediaPage),@(JFSeasonsPage),@(JFEpisodesPage),@(JFDetailPage)] containsObject:@(page)]) { JFPosterTrace(@"UI_PREVIEW_REJECT state"); return nil; }
    NSDictionary *item=nil;
    if (detailPage) {
        if (row<0 || (NSUInteger)row>=_rows.count) { JFPosterTrace(@"UI_PREVIEW_REJECT row"); return nil; }
        item=_session.snapshot[@"detail"];
    } else {
        if (row<0 || (NSUInteger)row>=_rows.count || ![_rows[(NSUInteger)row][@"action"] isEqual:@"media"]) { JFPosterTrace(@"UI_PREVIEW_REJECT row"); return nil; }
        NSArray *items=_session.snapshot[@"media"];
        if ((NSUInteger)row>=items.count) { JFPosterTrace(@"UI_PREVIEW_REJECT item-range"); return nil; }
        item=items[(NSUInteger)row];
    }
    if (![@[@"Movie",@"Series",@"Season",@"Episode"] containsObject:item[@"Type"]]) { JFPosterTrace(@"UI_PREVIEW_REJECT non-poster-media"); return nil; }
    if (![item[@"Id"] isEqual:_session.posterItemID]) { JFPosterTrace(@"UI_PREVIEW_REJECT poster-id-mismatch"); return nil; }
    NSData *data=_session.posterData;
    JFPosterTrace([NSString stringWithFormat:@"UI_PREVIEW_DATA bytes=%lu",(unsigned long)data.length]);
    if (!data.length) return nil;
    BOOL sideInset=[item[@"Type"] isEqual:@"Episode"];
    if (_previewSourceData!=data || _previewSideInset!=sideInset) {
        [_previewSourceData release]; _previewSourceData=[data retain];
        [_previewDisplayData release]; _previewDisplayData=[JFPosterDataWithInset(data,sideInset) retain];
        _previewSideInset=sideInset;
        JFPosterTrace([NSString stringWithFormat:@"UI_PREVIEW_INSET source=%lu display=%lu side=%d",(unsigned long)data.length,(unsigned long)_previewDisplayData.length,sideInset]);
    }
    NSData *displayData=_previewDisplayData.length ? _previewDisplayData : data;

    Class imageClass=NSClassFromString(@"ATVImage");
    Class previewClass=NSClassFromString(@"BRAsyncImageControl");
    JFPosterTrace([NSString stringWithFormat:@"UI_PREVIEW_CLASSES image=%d preview=%d",imageClass!=Nil,previewClass!=Nil]);
    id image=JFBRObjectWithObject(imageClass,@"imageWithData:",displayData);
    JFPosterTrace([NSString stringWithFormat:@"UI_PREVIEW_IMAGE created=%d",image!=nil]);
    if (!image) return nil;
    id preview=[JFBRNew(previewClass) autorelease];
    JFPosterTrace([NSString stringWithFormat:@"UI_PREVIEW_CONTROLLER created=%d",preview!=nil]);
    if (!preview) return nil;
    BOOL aspectFit=JFBRSetBool(preview,@"setCropAndFill:",NO);
    JFPosterTrace([NSString stringWithFormat:@"UI_PREVIEW_ASPECT_FIT success=%d",aspectFit]);
    if (!aspectFit) return nil;
    BOOL imageSet=JFBRCall(preview,@"setImage:",@[image]);
    JFPosterTrace([NSString stringWithFormat:@"UI_PREVIEW_SETIMAGE success=%d",imageSet]);
    if (!imageSet) return nil;
    JFPosterTrace(@"UI_PREVIEW_READY");
    return preview;
}
- (BOOL)configurePlaybackBackend:(id<JFPlaybackBackend>)backend {
    if (![NSThread isMainThread] || _closed || _playbackBackend || !backend) return NO;
    // Saved-session restore may already be running here. Keep the verified backend
    // and attach it as soon as the session leaves its busy authentication state.
    _playbackBackend=[backend retain];
    if (_session && !_session.busy && !_session.playback)
        (void)[_session configurePlaybackBackend:_playbackBackend];
    [self refreshView]; return YES;
}
- (void)setMessage:(NSString *)message { [_message release]; _message=[message copy]; }
- (void)observe {
    if (_session && !_observing) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionChanged:) name:JFSessionChanged object:_session]; _observing=YES;
    }
}
- (void)unobserve {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:JFSessionChanged object:_session]; _observing=NO;
}
- (BOOL)activate {
    if (_closed) return NO;
    // Returning from an input controller without delegate completion means cancellation.
    if (_editor) [self clearEditor];
    [self syncSessionCredential];
    [self observe]; [self refreshView];
    BOOL ready=[super activate]; if (!ready) [self unobserve]; return ready;
}
- (void)deactivate { [self unobserve]; [super deactivate]; }
- (void)saveConfiguration {
    [_configurationDefaults setObject:@{@"server":_server,@"username":_username,@"allowHTTP":@(_allowHTTP)} forKey:@"ServerConfiguration"];
    if (![_configurationDefaults synchronize]) [self setMessage:@"Could not save configuration — try again"];
}
- (NSString *)deviceID {
    NSString *device=[_configurationDefaults stringForKey:@"DeviceID"];
    NSCharacterSet *invalid=[[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"] invertedSet];
    if (!device.length || [device rangeOfCharacterFromSet:invalid].location!=NSNotFound) {
        device=[[NSUUID UUID] UUIDString];
        [_configurationDefaults setObject:device forKey:@"DeviceID"];
        [_configurationDefaults synchronize];
    }
    return device;
}
- (void)clearSessionCredential {
    [_configurationDefaults removeObjectForKey:@"SessionCredential"];
    [_configurationDefaults synchronize];
}
- (void)saveSessionCredential {
    NSString *token=_session.sessionToken;
    NSString *address=JFNormalizeServerAddress(_server,NULL);
    NSString *device=[self deviceID];
    if (!JFValidPersistedToken(token) || !address.length || !device.length) return;
    NSDictionary *credential=@{@"version":@1,@"server":address,@"deviceID":device,@"token":token};
    if (![[ _configurationDefaults objectForKey:@"SessionCredential"] isEqual:credential]) {
        [_configurationDefaults setObject:credential forKey:@"SessionCredential"];
        if (![_configurationDefaults synchronize]) [self setMessage:@"Could not save sign-in — sign in again next launch"];
    }
}
- (void)syncSessionCredential {
    if ([_session.errorKind isEqual:@"authentication"]) { [self clearSessionCredential]; return; }
    if (_session.sessionToken.length) [self saveSessionCredential];
}
- (void)restoreSessionIfPossible {
    id raw=[_configurationDefaults objectForKey:@"SessionCredential"];
    if (!raw) return;
    if (![raw isKindOfClass:[NSDictionary class]]) { [self clearSessionCredential]; return; }
    NSDictionary *credential=raw;
    NSString *token=credential[@"token"], *server=JFNormalizeServerAddress(credential[@"server"],NULL);
    NSString *device=credential[@"deviceID"], *current=JFNormalizeServerAddress(_server,NULL), *expected=[self deviceID];
    BOOL valid=[credential[@"version"] isKindOfClass:[NSNumber class]] && [credential[@"version"] integerValue]==1 &&
        JFValidPersistedToken(token) && server.length && [server isEqual:current] &&
        [device isKindOfClass:[NSString class]] && [device isEqual:expected] &&
        (_allowHTTP || ![[[NSURL URLWithString:server] scheme] isEqual:@"http"]);
    if (!valid) { [self clearSessionCredential]; return; }
    _session=[[JFSession alloc] initWithURL:[NSURL URLWithString:server] deviceID:expected allowHTTP:_allowHTTP];
    if (!_session) { [self clearSessionCredential]; return; }
    _host=[[JFSessionHost alloc] initWithSession:_session];
    if (_playbackBackend) [_session configurePlaybackBackend:_playbackBackend];
    if (![_session authenticateToken:token]) { [self clearSession]; [self clearSessionCredential]; }
}
- (void)clearSession {
    [self unobserve]; [_host close]; [_session close];
    [_host release]; _host=nil; [_session release]; _session=nil;
    [_password release]; _password=[@"" copy]; _passwordEntered=NO;
}
- (void)close {
    if (_closed) return;
    [self clearEditor]; [self clearSession];
    [_previewSourceData release]; _previewSourceData=nil; [_previewDisplayData release]; _previewDisplayData=nil; _previewSideInset=NO;
    [_server release]; _server=[@"" copy]; [_username release]; _username=[@"" copy];
    [super close];
}
- (void)sessionChanged:(NSNotification *)notification {
    if (_closed || notification.object!=_session) return;
    [self setMessage:@""]; [self syncSessionCredential];
    if (_playbackBackend && !_session.busy && !_session.playback)
        (void)[_session configurePlaybackBackend:_playbackBackend];
    [self refreshView];
    BOOL updated=JFBRCall(_controller,@"updatePreviewController",@[]);
    JFPosterTrace([NSString stringWithFormat:@"UI_UPDATE_PREVIEW invoked=%d",updated]);
}
- (void)refreshView {
    if (_closed) return;
    NSDictionary *snapshot=_session.snapshot;
    NSInteger page=snapshot ? [snapshot[@"page"] integerValue] : JFLoginPage;
    if (page!=_page) { JFBRClearRemoteState(_controller); _selection=0; _page=page; }
    BOOL busy=_session.busy;
    BOOL restoring=page==JFLoginPage && busy && [_configurationDefaults objectForKey:@"SessionCredential"]!=nil;
    NSMutableArray *rows=[NSMutableArray array]; NSString *title=@"RetroReel3";
    if (restoring) {
        title=@"Jellyfin — Restoring session…";
        [rows addObject:Row(@"Restoring saved sign-in…",@"none",NO)];
    } else if (page==JFLoginPage) {
        [rows addObject:Row(_server.length ? [@"Server: " stringByAppendingString:_server] : @"Server address",@"server",!busy)];
        [rows addObject:Row(_username.length ? [@"Username: " stringByAppendingString:_username] : @"Username",@"username",!busy)];
        [rows addObject:Row(_passwordEntered ? @"Password: Entered" : @"Password",@"password",!busy)];
        [rows addObject:Row(@"Sign in",@"signin",!busy && _server.length && _username.length && _passwordEntered)];
        [rows addObject:Row(_allowHTTP ? @"Allow HTTP: On" : @"Allow HTTP: Off",@"http",!busy)];
    } else if (page==JFLibrariesPage) {
        title=@"Jellyfin — Libraries";
        NSArray *items=snapshot[@"libraries"];
        for (NSDictionary *item in items) [rows addObject:Row(item[@"Name"],@"library",!busy)];
        if (!items.count) [rows addObject:Row(@"No libraries available",@"none",NO)];
        if (_selection<(long)items.count) _selection=[snapshot[@"index"] longValue];
        [rows addObject:Row(@"Refresh libraries",@"refresh",!busy)];
        [rows addObject:Row(@"Sign out",@"logout",!busy)];
    } else if (page==JFLibraryPage) {
        NSArray *libraries=snapshot[@"libraries"];
        NSInteger selected=[snapshot[@"index"] integerValue];
        NSDictionary *library=(selected>=0 && selected!=(NSInteger)NSNotFound && (NSUInteger)selected<libraries.count) ? libraries[(NSUInteger)selected] : nil;
        NSString *name=[library[@"Name"] isKindOfClass:[NSString class]] ? library[@"Name"] : nil;
        NSString *collection=[library[@"CollectionType"] isKindOfClass:[NSString class]] ? [library[@"CollectionType"] lowercaseString] : @"";
        title=name.length ? [@"Jellyfin — " stringByAppendingString:name] : @"Jellyfin — Browse library";
        if ([collection isEqual:@"movies"]) {
            [rows addObject:Row(@"Movies",@"movies",!busy)];
        } else if ([collection isEqual:@"tvshows"]) {
            [rows addObject:Row(@"TV shows",@"series",!busy)];
        } else if (!collection.length || [collection isEqual:@"mixed"]) {
            [rows addObject:Row(@"Movies",@"movies",!busy)];
            [rows addObject:Row(@"TV shows",@"series",!busy)];
        } else {
            [rows addObject:Row(@"This library type is not supported yet",@"none",NO)];
        }
        [rows addObject:Row(@"Back",@"back",!busy)];
    } else if (page==JFDetailPage) {
        NSDictionary *detail=snapshot[@"detail"];
        title=JFDetailTitle(detail);
        NSString *facts=JFDetailFacts(detail); if (facts.length) [rows addObject:Row(facts,@"none",NO)];
        NSString *genres=JFDetailGenres(detail); if (genres.length) [rows addObject:Row(genres,@"none",NO)];
        NSString *overview=detail[@"Overview"];
        [rows addObject:Row([overview isKindOfClass:[NSString class]] && overview.length ? overview : @"No description available",@"none",NO)];
        NSString *state=_session.playback.currentState;
        BOOL playing=[state isEqual:@"playing"], paused=[state isEqual:@"paused"], setup=[state isEqual:@"setup"];
        if (playing || paused || setup) {
            title=[title stringByAppendingFormat:@" — %@",state];
            if (!setup) {
                [rows addObject:Row(paused ? @"Resume" : @"Pause",paused ? @"resume" : @"pause",YES)];
                [rows addObject:Row(@"Seek +30 seconds",@"seek",YES)];
                NSString *audio=[_session audioSelectionLabel]; if (audio.length) [rows addObject:Row(audio,@"audio",YES)];
                NSString *subtitle=[_session subtitleSelectionLabel]; if (subtitle.length) [rows addObject:Row(subtitle,@"subtitle",YES)];
            }
            [rows addObject:Row(setup ? @"Cancel playback setup" : @"Stop",@"stop",YES)];
        } else {
            [rows addObject:Row(@"Back",@"back",!busy)];
            if (_session.playback) {
                long long resumeTicks=[_session resumeTicksForDetail];
                NSString *playTitle=[state isEqual:@"failed"] ? @"Retry playback" : (resumeTicks>0 ? @"Resume" : @"Play");
                [rows addObject:Row(playTitle,@"play",!busy)];
                NSString *audio=[_session audioSelectionLabel]; if (audio.length) [rows addObject:Row(audio,@"audio",!busy)];
                NSString *subtitle=[_session subtitleSelectionLabel]; if (subtitle.length) [rows addObject:Row(subtitle,@"subtitle",!busy)];
            }
            if ([state isEqual:@"failed"]) {
                NSString *kind=_session.playback.errorKind;
                NSString *failure=[kind isEqual:@"timeout"] ? @"Playback timed out" :
                    [kind isEqual:@"transport"] ? @"Playback network error" : @"Playback failed";
                [rows addObject:Row(failure,@"none",NO)];
            }
        }
    } else {
        title=page==JFSeasonsPage ? @"Jellyfin — Seasons" : page==JFEpisodesPage ? @"Jellyfin — Episodes" : @"Jellyfin — Media";
        NSArray *items=snapshot[@"media"];
        for (NSDictionary *item in items) {
            NSString *label=nil;
            if (page==JFMediaPage && [item[@"Type"] isEqual:@"Movie"]) label=JFMovieRowTitle(item);
            else if (page==JFSeasonsPage) label=JFSeasonRowTitle(item);
            else if (page==JFEpisodesPage) label=JFEpisodeRowTitle(item);
            else label=item[@"Name"];
            [rows addObject:Row(label,@"media",!busy)];
        }
        if (!items.count) {
            NSString *empty=page==JFSeasonsPage ? @"No seasons available" : page==JFEpisodesPage ? @"No episodes available" : @"No media available";
            [rows addObject:Row(empty,@"none",NO)];
        }
        if (_selection<(long)items.count) _selection=[snapshot[@"mediaIndex"] longValue];
        if ([snapshot[@"hasMore"] boolValue]) [rows addObject:Row(@"Load more",@"more",!busy)];
        [rows addObject:Row(@"Back",@"back",!busy)];
    }
    NSString *error=_session.errorKind;
    NSString *message=_message;
    if ([error isEqual:@"authentication"]) message=_session.errorCode ? [NSString stringWithFormat:@"Sign in again — authentication failed (%ld)",(long)_session.errorCode] : @"Sign in again — session expired or credentials rejected";
    else if ([error isEqual:@"timeout"]) message=@"Request timed out — try again";
    else if ([error isEqual:@"tls"]) message=@"Secure connection failed — check the server certificate and Apple TV date";
    else if ([error isEqual:@"transport"]) message=@"Cannot reach the server — check its address and your network";
    else if ([error isEqual:@"request"]) message=_session.errorCode ? [NSString stringWithFormat:@"Request failed (%ld)",(long)_session.errorCode] : @"Request failed — try again";
    if (message.length) [rows addObject:Row(message,@"none",NO)];
    if (busy) title=[title stringByAppendingString:@" — Loading…"];
    [self displayTitle:title rows:rows selection:_selection];
}
- (void)clearEditor {
    if (!_editor) return;
    JFBRCall(_editor,@"setTextFieldDelegate:",@[[NSNull null]]);
    JFBRCall(_editor,@"setInitialTextEntryText:",@[@""]);
    [_editor release]; _editor=nil; _editKind=0;
}
- (void)edit:(NSUInteger)kind {
    if (_editor || _closed || _session.busy) return;
    id stack=JFBRObject(_controller,@"stack");
    if (!JFBRProtocolMatches([self class],@"BRTextFieldDelegate",@[@"textDidChange:",@"textDidEndEditing:"])) {
        [self setMessage:@"Text input is unavailable"]; [self refreshView]; return;
    }
    id editor=JFNewTextEntryController();
    BOOL valid=JFBRHas(stack,@"pushController:",@encode(void),@[@"@"]) && JFBRHas(stack,@"popController",@encode(void),@[]) &&
        JFBRHas(editor,@"setTextFieldDelegate:",@encode(void),@[@"@"]) &&
        JFBRHas(editor,@"setInitialTextEntryText:",@encode(void),@[@"@"]) &&
        JFBRHas(editor,@"setTextEntryTextFieldLabel:",@encode(void),@[@"@"]) &&
        JFBRHas(editor,@"editor",@encode(id),@[]);
    id field=JFBRObject(JFBRObject(editor,@"editor"),@"textField");
    valid=valid && JFBRHas(field,@"stringValue",@encode(id),@[]);
    if (kind==3) valid=valid && JFBRSetBool(editor,@"setShowUserEnteredText:",NO);
    if (!valid) { [editor release]; [self setMessage:@"Text input is unavailable"]; [self refreshView]; return; }
    NSString *label=kind==1 ? @"Server URL" : kind==2 ? @"Username" : @"Password";
    JFBRCall(editor,@"setTextEntryTextFieldLabel:",@[label]);
    JFBRCall(editor,@"setInitialTextEntryText:",@[kind==1 ? _server : kind==2 ? _username : @""]);
    JFBRCall(editor,@"setTextFieldDelegate:",@[self]);
    _editor=editor; _editKind=kind;
    JFBRCall(stack,@"pushController:",@[editor]);
}
// Required BRTextFieldDelegate callback. Submission occurs only on end-editing.
- (void)textDidChange:(id)sender { (void)sender; }
- (void)textDidEndEditing:(id)sender {
    if (![NSThread isMainThread] || _closed || !_editor || sender!=JFBRObject(JFBRObject(_editor,@"editor"),@"textField")) return;
    id value=JFBRObject(sender,@"stringValue");
    if (![value isKindOfClass:[NSString class]]) return;
    NSString *text=[value copy]; NSUInteger kind=_editKind;
    id stack=[JFBRObject(_controller,@"stack") retain];
    [self clearEditor];
    // Retain through reentrant pop/activation callbacks.
    [self retain]; JFBRCall(stack,@"popController",@[]); [stack release];
    if (!_closed) {
        [self setMessage:@""];
        if (kind==1) {
            NSError *error=nil;
            NSString *address=text.length ? JFNormalizeServerAddress(text,&error) : @"";
            if (!address) [self setMessage:error.localizedDescription];
            else {
                if (![_server isEqual:address]) { [self clearSessionCredential]; [self clearSession]; }
                [_server release]; _server=[address copy]; [self saveConfiguration];
            }
        } else if (kind==2) {
            if (![_username isEqual:text]) { [self clearSessionCredential]; [self clearSession]; }
            [_username release]; _username=[text copy]; [self saveConfiguration];
        } else { [_password release]; _password=[text copy]; _passwordEntered=YES; }
        [self refreshView];
    }
    [text release]; [self release];
}
- (void)signIn {
    if (_closed || _session.busy || !_passwordEntered) return;
    NSString *address=JFNormalizeServerAddress(_server,NULL);
    if (!address) { [self setMessage:@"Enter a valid server address"]; [self refreshView]; return; }
    if (!_allowHTTP && [[[NSURL URLWithString:address] scheme] isEqual:@"http"]) {
        [self setMessage:@"HTTP is disabled — enable Allow HTTP or use HTTPS"]; [self refreshView]; return;
    }
    NSString *secret=[_password copy];
    [self clearSessionCredential]; [self clearSession]; [self setMessage:@""];
    NSString *device=[self deviceID];
    _session=[[JFSession alloc] initWithURL:[NSURL URLWithString:address] deviceID:device allowHTTP:_allowHTTP];
    if (_session) {
        _host=[[JFSessionHost alloc] initWithSession:_session]; [self observe];
        if (_playbackBackend) [_session configurePlaybackBackend:_playbackBackend];
        [_session login:_username password:secret];
    } else [self setMessage:@"Check the server URL; HTTP requires Allow HTTP"];
    [secret release]; [self refreshView];
}
- (void)selectRow:(long)row {
    if (![NSThread isMainThread] || !_active || _closed || _editor || _session.busy || ![self rowSelectable:row]) return;
    NSString *action=_rows[row][@"action"];
    // Native callbacks must agree with our controlled focus; never select a stale model row.
    if (([action isEqual:@"library"] || [action isEqual:@"media"]) && row!=_selection) return;
    _selection=row;
    if ([action isEqual:@"server"]) [self edit:1];
    else if ([action isEqual:@"username"]) [self edit:2];
    else if ([action isEqual:@"password"]) [self edit:3];
    else if ([action isEqual:@"signin"]) [self signIn];
    else if ([action isEqual:@"http"]) {
        _allowHTTP=!_allowHTTP;
        if (!_allowHTTP && [[[NSURL URLWithString:_server] scheme] isEqual:@"http"]) { [self clearSessionCredential]; [self clearSession]; }
        [self saveConfiguration]; [self refreshView];
    }
    else if ([action isEqual:@"library"]) {
        NSArray *libraries=_session.snapshot[@"libraries"];
        NSDictionary *library=(row>=0 && (NSUInteger)row<libraries.count) ? libraries[(NSUInteger)row] : nil;
        NSString *collection=[library[@"CollectionType"] isKindOfClass:[NSString class]] ? [library[@"CollectionType"] lowercaseString] : @"";
        if ([collection isEqual:@"movies"]) {
            if (![_session openLibraryWithType:@"Movie"]) { [self setMessage:@"Browse request did not start"]; [self refreshView]; }
        } else if ([collection isEqual:@"tvshows"]) {
            if (![_session openLibraryWithType:@"Series"]) { [self setMessage:@"Browse request did not start"]; [self refreshView]; }
        } else {
            [_host handleRemoteEvent:@{@"button":@(JFSelect),@"phase":@"press"}];
        }
    }
    else if ([action isEqual:@"media"]) [_session openMediaAtIndex:(NSUInteger)row];
    else if ([action isEqual:@"movies"]) { if (![_session openLibraryWithType:@"Movie"]) { [self setMessage:@"Browse request did not start"]; [self refreshView]; } }
    else if ([action isEqual:@"series"]) { if (![_session openLibraryWithType:@"Series"]) { [self setMessage:@"Browse request did not start"]; [self refreshView]; } }
    else if ([action isEqual:@"refresh"]) [_session refresh];
    else if ([action isEqual:@"logout"]) { [self clearSessionCredential]; [_session signOut]; }
    else if ([action isEqual:@"more"]) [_session loadMore];
    else if ([action isEqual:@"play"]) [_session playDetail];
    else if ([action isEqual:@"pause"]) [_session.playback pause];
    else if ([action isEqual:@"resume"]) [_session resumeDetailPlayback];
    else if ([action isEqual:@"seek"]) [_session.playback seek:_session.playback.positionTicks+300000000LL];
    else if ([action isEqual:@"audio"]) { if (![_session cycleAudioTrack]) [self setMessage:@"Audio track change failed"]; [self refreshView]; }
    else if ([action isEqual:@"subtitle"]) { if (![_session cycleSubtitleTrack]) [self setMessage:@"Subtitle change failed"]; [self refreshView]; }
    else if ([action isEqual:@"stop"]) [_session.playback stop];
    else if ([action isEqual:@"back"]) [_session goBack];
}
- (JFHostEventResult)handleEvent:(NSDictionary *)event {
    if (![NSThread isMainThread] || !_active || _closed || _editor || ![event isKindOfClass:[NSDictionary class]]) return JFHostEventUnhandled;
    id button=event[@"button"], phase=event[@"phase"];
    if (![button isKindOfClass:[NSNumber class]] || ![phase isKindOfClass:[NSString class]] ||
        ![@[@"press",@"release",@"hold",@"repeat"] containsObject:phase]) return JFHostEventUnhandled;
    NSInteger b=[button integerValue];
    if (b<JFUp || b>JFMenu || ![button isEqualToNumber:@(b)]) return JFHostEventUnhandled;
    if (_session.busy) return JFHostEventConsumed;
    if (b==JFMenu) {
        if (![phase isEqual:@"press"]) return JFHostEventConsumed;
        NSInteger page=[_session.snapshot[@"page"] integerValue];
        NSString *playbackState=_session.playback.currentState;
        BOOL playbackActive=[@[@"setup",@"playing",@"paused"] containsObject:playbackState ?: @""];
        if (page==JFDetailPage && playbackActive) {
            // Queue navigation before stop publishes a synchronous Detail refresh.
            // This avoids losing the second Menu press during the stopped-state redraw.
            BOOL backing=[_session goBack];
            BOOL stopped=[_session.playback stop];
            JFPlaybackTrace([NSString stringWithFormat:@"MENU_DETAIL backQueued=%d stopped=%d",backing,stopped]);
            if (backing || stopped) return JFHostEventConsumed;
        }
        if ([_session.playback stop]) return JFHostEventConsumed;
        return _host ? [_host handleRemoteEvent:event] : ([_session goBack] ? JFHostEventConsumed : JFHostEventExitRequested);
    }
    if ([phase isEqual:@"release"]) return JFHostEventConsumed;
    if (b==JFSelect) {
        if ([phase isEqual:@"press"]) [self selectRow:_selection];
        return JFHostEventConsumed;
    }
    if (b!=JFUp && b!=JFDown) return JFHostEventConsumed;
    long step=b==JFUp ? -1 : 1, next=_selection+step;
    while (next>=0 && (NSUInteger)next<_rows.count && ![self rowSelectable:next]) next+=step;
    if (next<0 || (NSUInteger)next>=_rows.count) return JFHostEventConsumed;
    NSString *action=_rows[next][@"action"], *previous=_rows[_selection][@"action"];
    if ([action isEqual:@"library"] || [action isEqual:@"media"]) {
        if ([action isEqual:previous]) {
            // Keep model ownership of media/library focus. The completion redraws it.
            [_session handleEvent:event]; return JFHostEventConsumed;
        }
        // Re-entering a list from its action rows restores the model's current focus.
        _selection=[_session.snapshot[[action isEqual:@"library"] ? @"index" : @"mediaIndex"] longValue];
    } else _selection=next;
    [self refreshView]; return JFHostEventConsumed;
}
- (void)dealloc {
    [self close]; [_previewSourceData release]; [_previewDisplayData release]; [_playbackBackend release]; [_server release]; [_username release]; [_password release]; [_configurationDefaults release]; [_message release]; [super dealloc];
}
@end
