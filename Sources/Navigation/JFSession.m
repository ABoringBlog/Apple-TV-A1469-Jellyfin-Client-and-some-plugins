#import "JFSession.h"
#import "JFPosterTrace.h"
#import "JFBrowser.h"
#import "JFMovieMetadata.h"
#import "API/JFWorker.h"
#import "Playback/JFPlaybackModel.h"
#import "Playback/JFAudio.h"
#import "Playback/JFSubtitle.h"
NSString * const JFSessionChanged = @"JFSessionChanged";
// Retained by delivery blocks, but never retains the session or host. Main thread only.
@interface JFSessionDelivery : NSObject {
@public JFSession *owner;
}
@end
@implementation JFSessionDelivery
@end
static NSDictionary *EmptySnapshot(void) {
    return @{@"page":@(JFLoginPage), @"libraries":@[], @"index":@(NSNotFound),
             @"media":@[], @"mediaIndex":@(NSNotFound), @"detail":@{}, @"hasMore":@NO};
}
static NSString *ErrorKind(NSError *error) {
    if (!error) return @"none";
    if ([error.domain isEqual:@"Jellyfin"] && (error.code==401 || error.code==1003)) return @"authentication";
    if (([error.domain isEqual:NSURLErrorDomain] || [error.domain isEqual:@"Jellyfin"]) && error.code==NSURLErrorTimedOut) return @"timeout";
    if ([error.domain isEqual:NSURLErrorDomain]) {
        if (error.code<=NSURLErrorSecureConnectionFailed && error.code>=NSURLErrorClientCertificateRequired) return @"tls";
        return @"transport";
    }
    return @"request";
}
@interface JFSession ()
- (id)initWithOwnedClient:(JFClient *)client;
- (BOOL)submit:(void (^)(JFBrowser *, NSError **))action;
- (BOOL)submitAuthentication:(void (^)(JFBrowser *, NSError **))action;
- (void)interruptPosterLoad;
- (void)clearPoster;
- (void)updatePosterForSnapshot;
- (void)clearAudioSelection;
- (NSArray *)audioTracksForDetail;
- (NSDictionary *)selectedAudioTrackForDetail;
- (void)clearSubtitleSelection;
- (NSArray *)subtitleTracksForDetail;
- (NSDictionary *)selectedSubtitleTrackForDetail;
- (NSDictionary *)defaultAudioTrackForSource:(NSString *)source tracks:(NSArray *)tracks;
@end
@implementation JFSession
@synthesize snapshot=_snapshot, errorKind=_errorKind, errorDomain=_errorDomain, errorCode=_errorCode, busy=_busy, closed=_closed;
- (NSString *)sessionToken { return [[_sessionToken copy] autorelease]; }
- (NSData *)posterData { return [[_posterData copy] autorelease]; }
- (NSString *)posterItemID { return [[_posterItemID copy] autorelease]; }
- (id)initWithURL:(NSURL *)url deviceID:(NSString *)deviceID allowHTTP:(BOOL)allowHTTP {
    JFClient *client=nil;
    if ([NSThread isMainThread] && (allowHTTP || [[url.scheme lowercaseString] isEqual:@"https"]))
        client=[[JFClient alloc] initWithURL:url deviceID:deviceID];
    self=[self initWithOwnedClient:client]; [client release]; return self;
}
// Internal test seam; no client/browser accessor exists in the public interface.
- (id)initWithOwnedClient:(JFClient *)client {
    if ((self=[super init])) {
        if (!client || ![NSThread isMainThread]) { [self release]; return nil; }
        _playbackClient=[client retain]; _browser=[[JFBrowser alloc] initWithClient:client]; _worker=[JFWorker new];
        NSArray *cacheDirs=NSSearchPathForDirectoriesInDomains(NSCachesDirectory,NSUserDomainMask,YES);
        NSString *cacheRoot=cacheDirs.count ? cacheDirs[0] : NSTemporaryDirectory();
        _artworkCache=[[JFImageCache alloc] initWithDirectory:[cacheRoot stringByAppendingPathComponent:@"Jellyfin-ATV3/Posters"] ttl:7*24*60*60];
        _delivery=[JFSessionDelivery new]; _delivery->owner=self;
        _snapshot=[EmptySnapshot() copy]; _errorKind=[@"none" copy]; _audioIndex=-1; _subtitleIndex=-1;
    }
    return self;
}
- (void)publish { [[NSNotificationCenter defaultCenter] postNotificationName:JFSessionChanged object:self]; }
- (void)interruptPosterLoad {
    if (!_posterTask) return;
    [_posterTask cancel]; [_posterTask release]; _posterTask=nil; _posterGeneration++;
    if (!_posterData) { [_posterItemID release]; _posterItemID=nil; }
}
- (void)clearPoster {
    [self interruptPosterLoad];
    [_posterData release]; _posterData=nil;
    [_posterItemID release]; _posterItemID=nil;
    _posterGeneration++;
}
- (void)updatePosterForSnapshot {
    NSInteger page=[_snapshot[@"page"] integerValue];
    BOOL posterPage=[@[@(JFMediaPage),@(JFSeasonsPage),@(JFEpisodesPage)] containsObject:@(page)];
    if (!posterPage) {
        JFPosterTrace([NSString stringWithFormat:@"POSTER_SKIP page=%ld",(long)page]);
        [self interruptPosterLoad];
        if (page!=JFDetailPage) { [_posterData release]; _posterData=nil; [_posterItemID release]; _posterItemID=nil; }
        return;
    }
    NSArray *items=_snapshot[@"media"]; NSInteger index=[_snapshot[@"mediaIndex"] integerValue];
    if (index<0 || index==(NSInteger)NSNotFound || (NSUInteger)index>=items.count) {
        JFPosterTrace(@"POSTER_CLEAR invalid-selection"); [self clearPoster]; return;
    }
    NSDictionary *item=items[(NSUInteger)index];
    if (![@[@"Movie",@"Series",@"Season",@"Episode"] containsObject:item[@"Type"]] || ![item[@"Id"] isKindOfClass:[NSString class]]) {
        JFPosterTrace(@"POSTER_CLEAR unsupported-type-or-id"); [self clearPoster]; return;
    }
    NSString *identifier=item[@"Id"];
    NSDictionary *meta=JFMovieMetadata(item);
    BOOL hasPrimary=[meta[@"primaryImageTag"] isKindOfClass:[NSString class]];
    BOOL seasonFallback=NO;
    NSString *sourceID=identifier;
    if (!hasPrimary && [item[@"Type"] isEqual:@"Season"]) {
        NSString *seriesID=_snapshot[@"seriesID"];
        if ([seriesID isKindOfClass:[NSString class]] && seriesID.length) {
            sourceID=seriesID; seasonFallback=YES;
        }
    }
    JFPosterTrace([NSString stringWithFormat:@"POSTER_SELECT index=%ld primary=%d seasonFallback=%d",(long)index,hasPrimary,seasonFallback]);
    if ([_posterItemID isEqual:identifier]) { JFPosterTrace(@"POSTER_SKIP same-item"); return; }

    [self clearPoster];
    _posterItemID=[identifier copy];
    if (!hasPrimary && !seasonFallback) { JFPosterTrace(@"POSTER_SKIP no-primary"); return; }

    NSUInteger posterGeneration=++_posterGeneration;
    NSInteger selectedIndex=index;
    NSString *itemID=[[identifier copy] autorelease];
    NSString *requestID=[[sourceID copy] autorelease];
    JFClient *client=_playbackClient; JFImageCache *cache=_artworkCache; JFSessionDelivery *delivery=_delivery;
    JFPosterTrace([NSString stringWithFormat:@"POSTER_REQUEST_START index=%ld width=360 fallback=%d",(long)selectedIndex,seasonFallback]);
    _posterTask=[[_worker perform:^id(NSError **error) {
        return [client imageData:requestID backdrop:NO width:360 cache:cache error:error];
    } completion:^(id result,NSError *error) {
        JFSession *session=delivery->owner;
        NSUInteger bytes=[result isKindOfClass:[NSData class]] ? [result length] : 0;
        JFPosterTrace([NSString stringWithFormat:@"POSTER_REQUEST_DONE index=%ld bytes=%lu error=%ld",(long)selectedIndex,(unsigned long)bytes,(long)error.code]);
        if (!session || session->_closed || session->_posterGeneration!=posterGeneration ||
            ![session->_posterItemID isEqual:itemID]) { JFPosterTrace(@"POSTER_CALLBACK_STALE"); return; }
        [session->_posterTask release]; session->_posterTask=nil;
        if ([error.domain isEqual:@"Jellyfin"] && error.code==401) {
            JFPosterTrace(@"POSTER_AUTH_FAILURE"); [session logout]; return;
        }
        if (![result isKindOfClass:[NSData class]] || ![result length]) {
            JFPosterTrace(@"POSTER_DATA_INVALID"); return;
        }
        [session->_posterData release]; session->_posterData=[result copy];
        JFPosterTrace([NSString stringWithFormat:@"POSTER_DATA_READY bytes=%lu",(unsigned long)[session->_posterData length]]);
        [session publish];
    }] retain];
}
- (void)clearAudioSelection {
    [_audioItemID release]; _audioItemID=nil;
    [_audioSourceID release]; _audioSourceID=nil;
    _audioIndex=-1;
}
- (NSArray *)audioTracksForDetail {
    if (_closed || [_snapshot[@"page"] integerValue]!=JFDetailPage) return @[];
    NSDictionary *detail=_snapshot[@"detail"];
    NSError *error=nil;
    NSArray *tracks=JFAudioTracks(detail[@"MediaSources"],&error);
    return tracks ?: @[];
}
- (NSDictionary *)selectedAudioTrackForDetail {
    if (_closed || [_snapshot[@"page"] integerValue]!=JFDetailPage) return nil;
    NSDictionary *detail=_snapshot[@"detail"];
    NSString *item=[detail[@"Id"] isKindOfClass:[NSString class]] ? detail[@"Id"] : nil;
    if (!item.length) return nil;
    NSArray *tracks=[self audioTracksForDetail];
    if (![_audioItemID isEqual:item]) {
        [self clearAudioSelection]; _audioItemID=[item copy];
    }
    for (NSDictionary *track in tracks)
        if ([_audioSourceID isEqual:track[@"sourceID"]] && _audioIndex==[track[@"index"] integerValue]) return track;
    NSDictionary *selected=JFAudioDefaultTrack(tracks);
    [_audioSourceID release]; _audioSourceID=[selected[@"sourceID"] copy];
    _audioIndex=selected ? [selected[@"index"] integerValue] : -1;
    return selected;
}
- (NSDictionary *)defaultAudioTrackForSource:(NSString *)source tracks:(NSArray *)tracks {
    if (!JFMediaID(source) || ![tracks isKindOfClass:[NSArray class]]) return nil;
    NSDictionary *first=nil;
    for (NSDictionary *track in tracks) {
        if (![track[@"sourceID"] isEqual:source]) continue;
        if (!first) first=track;
        if ([track[@"default"] boolValue]) return track;
    }
    return first;
}
- (void)clearSubtitleSelection {
    [_subtitleItemID release]; _subtitleItemID=nil;
    [_subtitleSourceID release]; _subtitleSourceID=nil;
    _subtitleIndex=-1;
}
- (NSArray *)subtitleTracksForDetail {
    if (_closed || [_snapshot[@"page"] integerValue]!=JFDetailPage) return @[];
    NSError *error=nil;
    NSArray *tracks=JFSubtitleTracksForSources(_snapshot[@"detail"][@"MediaSources"],&error);
    return tracks ?: @[];
}
- (NSDictionary *)selectedSubtitleTrackForDetail {
    if (_closed || [_snapshot[@"page"] integerValue]!=JFDetailPage) return nil;
    NSDictionary *detail=_snapshot[@"detail"];
    NSString *item=[detail[@"Id"] isKindOfClass:[NSString class]] ? detail[@"Id"] : nil;
    if (!item.length) return nil;
    if (![_subtitleItemID isEqual:item]) {
        [self clearSubtitleSelection]; _subtitleItemID=[item copy];
    }
    if (_subtitleIndex<0 || !_subtitleSourceID) return nil;
    for (NSDictionary *track in [self subtitleTracksForDetail])
        if ([_subtitleSourceID isEqual:track[@"sourceID"]] && _subtitleIndex==[track[@"index"] integerValue]) return track;
    [_subtitleSourceID release]; _subtitleSourceID=nil; _subtitleIndex=-1;
    return nil;
}
- (NSUInteger)audioTrackCount {
    if (![NSThread isMainThread] || _closed) return 0;
    return [[self audioTracksForDetail] count];
}
- (NSString *)audioSelectionLabel {
    if (![NSThread isMainThread] || _closed || [self audioTrackCount]<2) return nil;
    NSString *label=JFAudioTrackLabel([self selectedAudioTrackForDetail]);
    return label.length ? [@"Audio: " stringByAppendingString:label] : nil;
}
- (BOOL)cycleAudioTrack {
    if (![NSThread isMainThread] || _closed || _busy || [_snapshot[@"page"] integerValue]!=JFDetailPage) return NO;
    NSArray *tracks=[self audioTracksForDetail];
    if (tracks.count<2) return NO;
    NSDictionary *current=[self selectedAudioTrackForDetail];
    NSUInteger at=NSNotFound;
    for (NSUInteger i=0;i<tracks.count;i++) {
        NSDictionary *track=tracks[i];
        if ([track[@"sourceID"] isEqual:current[@"sourceID"]] && [track[@"index"] isEqual:current[@"index"]]) { at=i; break; }
    }
    if (at==NSNotFound) at=0;
    NSDictionary *next=tracks[(at+1)%tracks.count];
    NSDictionary *detail=_snapshot[@"detail"];
    NSString *item=[detail[@"Id"] isKindOfClass:[NSString class]] ? detail[@"Id"] : nil;
    if (!item.length) return NO;
    NSString *state=_playback.currentState;
    BOOL active=[@[@"playing",@"paused"] containsObject:state ?: @""];
    long long ticks=active ? _playback.positionTicks : [self resumeTicksForDetail];
    if (active && ![_playback stop]) return NO;
    [_audioSourceID release]; _audioSourceID=[next[@"sourceID"] copy]; _audioIndex=[next[@"index"] integerValue];
    if (_subtitleSourceID && ![_subtitleSourceID isEqual:_audioSourceID]) {
        [_subtitleSourceID release]; _subtitleSourceID=nil; _subtitleIndex=-1;
    }
    [self publish];
    if (active) return [_playback playItem:item startTicks:ticks mediaSourceID:_audioSourceID audioIndex:_audioIndex subtitleIndex:_subtitleIndex];
    return YES;
}
- (NSUInteger)subtitleTrackCount {
    if (![NSThread isMainThread] || _closed) return 0;
    return [[self subtitleTracksForDetail] count];
}
- (NSString *)subtitleSelectionLabel {
    if (![NSThread isMainThread] || _closed || [self subtitleTrackCount]==0) return nil;
    NSDictionary *track=[self selectedSubtitleTrackForDetail];
    if (!track) return @"Subtitles: Off";
    NSString *label=JFSubtitleTrackLabel(track);
    return label.length ? [@"Subtitles: " stringByAppendingString:label] : @"Subtitles: Off";
}
- (BOOL)cycleSubtitleTrack {
    if (![NSThread isMainThread] || _closed || _busy || [_snapshot[@"page"] integerValue]!=JFDetailPage) return NO;
    NSArray *tracks=[self subtitleTracksForDetail];
    if (!tracks.count) return NO;
    NSDictionary *current=[self selectedSubtitleTrackForDetail], *next=nil;
    if (!current) next=tracks[0];
    else {
        NSUInteger at=NSNotFound;
        for (NSUInteger i=0;i<tracks.count;i++) {
            NSDictionary *track=tracks[i];
            if ([track[@"sourceID"] isEqual:current[@"sourceID"]] && [track[@"index"] isEqual:current[@"index"]]) { at=i; break; }
        }
        if (at!=NSNotFound && at+1<tracks.count) next=tracks[at+1];
    }
    NSDictionary *detail=_snapshot[@"detail"];
    NSString *item=[detail[@"Id"] isKindOfClass:[NSString class]] ? detail[@"Id"] : nil;
    if (!item.length) return NO;
    NSString *state=_playback.currentState;
    BOOL active=[@[@"playing",@"paused"] containsObject:state ?: @""];
    long long ticks=active ? _playback.positionTicks : [self resumeTicksForDetail];
    if (active && ![_playback stop]) return NO;
    if (next) {
        [_subtitleSourceID release]; _subtitleSourceID=[next[@"sourceID"] copy]; _subtitleIndex=[next[@"index"] integerValue];
        NSArray *audio=[self audioTracksForDetail];
        NSDictionary *selected=[self selectedAudioTrackForDetail];
        if (selected && ![selected[@"sourceID"] isEqual:_subtitleSourceID]) {
            NSDictionary *replacement=[self defaultAudioTrackForSource:_subtitleSourceID tracks:audio];
            [_audioSourceID release]; _audioSourceID=[replacement[@"sourceID"] copy];
            _audioIndex=replacement ? [replacement[@"index"] integerValue] : -1;
        }
    } else {
        [_subtitleSourceID release]; _subtitleSourceID=nil; _subtitleIndex=-1;
    }
    [self publish];
    if (active) {
        NSString *source=_subtitleSourceID ?: _audioSourceID;
        return [_playback playItem:item startTicks:ticks mediaSourceID:source audioIndex:_audioIndex subtitleIndex:_subtitleIndex];
    }
    return YES;
}
- (void)resetSnapshot {
    [self clearPoster]; [self clearAudioSelection]; [self clearSubtitleSelection];
    [_snapshot release]; _snapshot=[EmptySnapshot() copy];
    [_errorKind release]; _errorKind=[@"none" copy];
    [_errorDomain release]; _errorDomain=nil; _errorCode=0;
}
- (BOOL)submit:(void (^)(JFBrowser *, NSError **))action {
    if (![NSThread isMainThread] || _closed || _busy) return NO;
    _busy=YES; [_errorKind release]; _errorKind=[@"none" copy]; [_errorDomain release]; _errorDomain=nil; _errorCode=0;
    NSUInteger generation=_generation;
    JFBrowser *browser=_browser; JFSessionDelivery *delivery=_delivery;
    [_worker perform:^id(NSError **error) {
        action(browser,error);
        return [browser snapshot];
    } completion:^(id result, NSError *error) {
        JFSession *session=delivery->owner;
        if (!session || session->_closed || session->_generation!=generation) return;
        [session->_snapshot release]; session->_snapshot=[result copy];
        NSString *kind=ErrorKind(error);
        [session->_errorKind release]; session->_errorKind=[kind copy];
        [session->_errorDomain release]; session->_errorDomain=[error.domain copy]; session->_errorCode=error.code;
        if ([kind isEqual:@"authentication"]) { [session->_sessionToken release]; session->_sessionToken=nil; }
        session->_busy=NO;
        [session updatePosterForSnapshot];
        [session publish];
    }];
    [self publish]; return YES;
}
- (BOOL)submitAuthentication:(void (^)(JFBrowser *, NSError **))action {
    if (![NSThread isMainThread] || _closed || _busy) return NO;
    _busy=YES; [_errorKind release]; _errorKind=[@"none" copy]; [_errorDomain release]; _errorDomain=nil; _errorCode=0;
    NSUInteger generation=_generation;
    JFBrowser *browser=_browser; JFSessionDelivery *delivery=_delivery;
    [_worker perform:^id(NSError **error) {
        action(browser,error);
        id token=[browser sessionToken] ?: [NSNull null];
        return @{ @"snapshot":[browser snapshot], @"token":token };
    } completion:^(id result, NSError *error) {
        JFSession *session=delivery->owner;
        if (!session || session->_closed || session->_generation!=generation) return;
        NSDictionary *payload=[result isKindOfClass:[NSDictionary class]] ? result : @{};
        id snapshot=payload[@"snapshot"], token=payload[@"token"];
        [session->_snapshot release]; session->_snapshot=[snapshot isKindOfClass:[NSDictionary class]] ? [snapshot copy] : [EmptySnapshot() copy];
        [session->_sessionToken release]; session->_sessionToken=[token isKindOfClass:[NSString class]] ? [token copy] : nil;
        [session->_errorKind release]; session->_errorKind=[ErrorKind(error) copy];
        [session->_errorDomain release]; session->_errorDomain=[error.domain copy]; session->_errorCode=error.code;
        session->_busy=NO;
        [session updatePosterForSnapshot];
        [session publish];
    }];
    [self publish]; return YES;
}
- (BOOL)login:(NSString *)username password:(NSString *)password {
    if (![NSThread isMainThread] || _closed || ![username isKindOfClass:[NSString class]] || !username.length || ![password isKindOfClass:[NSString class]]) return NO;
    // Copy mutable caller inputs before crossing threads.
    NSString *name=[[username copy] autorelease], *secret=[[password copy] autorelease];
    _generation++; [_worker cancelAll]; [_playback invalidateSession]; _busy=NO; [self resetSnapshot];
    [_sessionToken release]; _sessionToken=nil;
    return [self submitAuthentication:^(JFBrowser *browser, NSError **error) { [browser login:name password:secret error:error]; }];
}
- (BOOL)authenticateToken:(NSString *)token {
    if (![NSThread isMainThread] || _closed || ![token isKindOfClass:[NSString class]] || !token.length) return NO;
    NSString *credential=[[token copy] autorelease];
    _generation++; [_worker cancelAll]; [_playback invalidateSession]; _busy=NO; [self resetSnapshot];
    [_sessionToken release]; _sessionToken=nil;
    return [self submitAuthentication:^(JFBrowser *browser, NSError **error) { [browser authenticateToken:credential error:error]; }];
}
- (BOOL)refresh {
    if (![NSThread isMainThread] || _closed || _busy) return NO;
    if ([_snapshot[@"page"] integerValue]!=JFLibrariesPage) return NO;
    return [self submit:^(JFBrowser *browser, NSError **error) { [browser refresh:error]; }];
}
- (BOOL)openLibraryWithType:(NSString *)type {
    if (![NSThread isMainThread] || _closed || _busy) return NO;
    if (![@[@"Movie",@"Series"] containsObject:type] || ![@[@(JFLibrariesPage),@(JFLibraryPage)] containsObject:_snapshot[@"page"]] || [_snapshot[@"index"] integerValue]==NSNotFound) return NO;
    NSString *copy=[[type copy] autorelease];
    return [self submit:^(JFBrowser *browser, NSError **error) { [browser openLibraryWithType:copy error:error]; }];
}
- (BOOL)openMediaAtIndex:(NSUInteger)index {
    if (![NSThread isMainThread] || _closed || _busy) return NO;
    NSInteger page=[_snapshot[@"page"] integerValue];
    if (page<JFMediaPage || page==JFDetailPage || index>=[_snapshot[@"media"] count]) return NO;
    return [self submit:^(JFBrowser *browser, NSError **error) { [browser openMediaAtIndex:index error:error]; }];
}
- (BOOL)loadMore {
    if (![NSThread isMainThread] || _closed || _busy) return NO;
    if ([_snapshot[@"page"] integerValue]!=JFMediaPage || ![_snapshot[@"hasMore"] boolValue]) return NO;
    return [self submit:^(JFBrowser *browser, NSError **error) { [browser loadMore:error]; }];
}
- (BOOL)handleEvent:(NSDictionary *)event {
    if (![NSThread isMainThread] || _closed || _busy || ![event isKindOfClass:[NSDictionary class]]) return NO;
    id button=event[@"button"], phase=event[@"phase"];
    if (![button isKindOfClass:[NSNumber class]] || ![@[@"press",@"repeat",@"hold",@"release"] containsObject:phase]) return NO;
    NSInteger b=[button integerValue], page=[_snapshot[@"page"] integerValue];
    if (b==JFMenu && [phase isEqual:@"press"]) return [self goBack];
    // Network selection must be explicit: library type is chosen by the host.
    BOOL movement=(b==JFUp || b==JFDown) && ![phase isEqual:@"release"];
    BOOL librarySelect=b==JFSelect && [phase isEqual:@"press"] && page==JFLibrariesPage;
    if (!(movement || librarySelect) || page==JFLoginPage || page==JFDetailPage || page==JFLibraryPage) return NO;
    if ((page==JFLibrariesPage ? [_snapshot[@"libraries"] count] : [_snapshot[@"media"] count])==0) return NO;
    NSDictionary *copy=@{@"button":@([button integerValue]),@"phase":[[phase copy] autorelease]};
    return [self submit:^(JFBrowser *browser, NSError **error) { [browser handleEvent:copy]; }];
}
- (BOOL)goBack {
    if (![NSThread isMainThread] || _closed || _busy) return NO;
    NSInteger page=[_snapshot[@"page"] integerValue];
    if (page==JFLoginPage || page==JFLibrariesPage) return NO;
    return [self submit:^(JFBrowser *browser, NSError **error) {
        if (browser.page==JFLibraryPage) [browser handleEvent:@{@"button":@(JFMenu),@"phase":@"press"}];
        else [browser goBack];
    }];
}
- (JFPlaybackController *)playback { return _playback; }
- (BOOL)configurePlaybackBackend:(id<JFPlaybackBackend>)backend {
    if (![NSThread isMainThread] || _closed || _busy || _playback || !backend) return NO;
    _playback=[[JFPlaybackController alloc] initWithClient:_playbackClient worker:_worker backend:backend];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playbackChanged:) name:JFPlaybackChanged object:_playback];
    return _playback!=nil;
}
- (void)playbackChanged:(NSNotification *)notification {
    if (_closed || notification.object!=_playback) return;
    if ([_playback.errorKind isEqual:@"authentication"] && [_playback.currentState isEqual:@"failed"]) {
        if ([self logout]) { [_errorKind release]; _errorKind=[@"authentication" copy]; [self publish]; }
        return;
    }
    [self publish];
}
- (long long)resumeTicksForDetail {
    if (![NSThread isMainThread] || _closed || [_snapshot[@"page"] integerValue]!=JFDetailPage) return 0;
    NSDictionary *detail=_snapshot[@"detail"];
    NSString *item=[detail[@"Id"] isKindOfClass:[NSString class]] ? detail[@"Id"] : nil;
    if (!item.length) return 0;
    long long local=[_playback resumeTicksForItem:item];
    if (local>0) return local;
    NSDictionary *user=[detail[@"UserData"] isKindOfClass:[NSDictionary class]] ? detail[@"UserData"] : nil;
    id ticks=user[@"PlaybackPositionTicks"], runtime=detail[@"RunTimeTicks"];
    if (!JFTicks(ticks) || [ticks longLongValue]<=0) return 0;
    long long value=[ticks longLongValue];
    if (JFTicks(runtime) && [runtime longLongValue]>0 && value>=[runtime longLongValue]) return 0;
    return value;
}
- (BOOL)playDetail {
    if (![NSThread isMainThread] || _closed || _busy || [_snapshot[@"page"] integerValue]!=JFDetailPage) return NO;
    NSDictionary *detail=_snapshot[@"detail"];
    [self selectedAudioTrackForDetail]; [self selectedSubtitleTrackForDetail];
    if (_subtitleSourceID && _audioSourceID && ![_subtitleSourceID isEqual:_audioSourceID]) {
        [_subtitleSourceID release]; _subtitleSourceID=nil; _subtitleIndex=-1;
    }
    NSString *source=_subtitleSourceID ?: _audioSourceID;
    return [_playback playItem:detail[@"Id"] startTicks:[self resumeTicksForDetail] mediaSourceID:source audioIndex:_audioIndex subtitleIndex:_subtitleIndex];
}
- (BOOL)resumeDetailPlayback {
    if (![NSThread isMainThread] || _closed || _busy || [_snapshot[@"page"] integerValue]!=JFDetailPage || !_playback) return NO;
    NSDictionary *detail=_snapshot[@"detail"];
    NSString *item=[detail[@"Id"] isKindOfClass:[NSString class]] ? detail[@"Id"] : nil;
    if (!item.length) return NO;
    long long ticks=[self resumeTicksForDetail];
    NSString *state=_playback.currentState;
    if ([@[@"setup",@"playing",@"paused"] containsObject:state ?: @""] && ![_playback stop]) return NO;
    [self selectedAudioTrackForDetail]; [self selectedSubtitleTrackForDetail];
    if (_subtitleSourceID && _audioSourceID && ![_subtitleSourceID isEqual:_audioSourceID]) {
        [_subtitleSourceID release]; _subtitleSourceID=nil; _subtitleIndex=-1;
    }
    NSString *source=_subtitleSourceID ?: _audioSourceID;
    return [_playback playItem:item startTicks:ticks mediaSourceID:source audioIndex:_audioIndex subtitleIndex:_subtitleIndex];
}
- (BOOL)signOut {
    if (![NSThread isMainThread] || _closed) return NO;
    _generation++; [_worker cancelAll]; [_playback invalidateSession]; _busy=NO; [self resetSnapshot];
    [_sessionToken release]; _sessionToken=nil;
    return [self submit:^(JFBrowser *browser, NSError **error) { [browser signOut:error]; }];
}
- (BOOL)logout {
    if (![NSThread isMainThread] || _closed) return NO;
    _generation++; [_worker cancelAll]; [_playback invalidateSession]; _busy=NO; [self resetSnapshot];
    [_sessionToken release]; _sessionToken=nil;
    return [self submit:^(JFBrowser *browser, NSError **error) { [browser logout]; }];
}
- (void)close {
    if (![NSThread isMainThread] || _closed) return;
    _closed=YES; _generation++; _busy=NO;
    [self clearPoster];
    if (_delivery) _delivery->owner=nil;
    [_worker cancelAll];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:JFPlaybackChanged object:_playback];
    [_playback close]; [self resetSnapshot]; [_sessionToken release]; _sessionToken=nil;
    JFBrowser *browser=_browser; JFWorker *worker=_worker;
    // Work retains worker until cleanup executes even when the host releases session.
    // Its work block is released by JFTask after execution, breaking this temporary cycle.
    [worker perform:^id(NSError **error) { [browser logout]; (void)[worker class]; return nil; } completion:nil];
}
- (void)dealloc {
    NSAssert([NSThread isMainThread], @"Release JFSession on main thread");
    [self close]; [_playback release]; [_playbackClient release]; [_artworkCache release]; [_delivery release]; [_worker release]; [_browser release];
    [_posterTask release]; [_posterData release]; [_posterItemID release];
    [_audioItemID release]; [_audioSourceID release];
    [_subtitleItemID release]; [_subtitleSourceID release];
    [_snapshot release]; [_errorKind release]; [_errorDomain release]; [_sessionToken release]; [super dealloc];
}
@end
