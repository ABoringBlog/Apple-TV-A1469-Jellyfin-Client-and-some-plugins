#import "MusicBackRow.h"

#import <objc/runtime.h>
#import <objc/message.h>
#include <stdio.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreText/CoreText.h>
#import <ImageIO/ImageIO.h>
#import <AVFoundation/AVFoundation.h>
#include <string.h>

#ifndef CLOUDTUNE_LANG_EN
#define CLOUDTUNE_LANG_EN 0
#endif

static NSString *CloudTuneL(NSString *zh, NSString *en)
{
    return CLOUDTUNE_LANG_EN ? en : zh;
}

static NSString *CloudTuneBridgeBaseURLString(void)
{
    NSString *value=[NSString stringWithContentsOfFile:@"/var/root/.atv3-cloudtune-bridge-url"
                                              encoding:NSUTF8StringEncoding
                                                 error:NULL];
    if (![value isKindOfClass:[NSString class]]) return nil;
    value=[value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    while ([value hasSuffix:@"/"] && [value length]>0)
        value=[value substringToIndex:[value length]-1];
    if (![value length]) return nil;

    NSURL *url=[NSURL URLWithString:value];
    NSString *scheme=[[url scheme] lowercaseString];
    if (!url || ![url host] ||
        !([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])) return nil;
    return value;
}

static NSURL *CloudTuneBridgeURL(NSString *path)
{
    NSString *base=CloudTuneBridgeBaseURLString();
    if (![base length] || ![path isKindOfClass:[NSString class]] || ![path hasPrefix:@"/"]) return nil;
    return [NSURL URLWithString:[base stringByAppendingString:path]];
}

static NSURL *CloudTuneMediaURL(NSString *value)
{
    if (![value isKindOfClass:[NSString class]] || ![value length]) return nil;
    if ([value hasPrefix:@"https://"]) return [NSURL URLWithString:value];
    if ([value hasPrefix:@"http://"]) {
        NSURL *candidate=[NSURL URLWithString:value];
        NSString *host=[candidate host];
        NSString *bridgeHost=[[NSURL URLWithString:CloudTuneBridgeBaseURLString()] host];
        if ([host length] && [bridgeHost length] && [host isEqualToString:bridgeHost]) return candidate;
        return nil;
    }
    if ([value hasPrefix:@"/v1/music/cover?"]) return CloudTuneBridgeURL(value);
    return nil;
}

// Scoped BackRow screensaver suppression, based on the ATVSettingsFacade ABI.
static BOOL appSaverHeld=NO;
static NSInteger appSaverOriginal=0;
static id AppSaverFacade(void) {
    Class cls=objc_getClass("ATVSettingsFacade");
    if(!cls || ![cls respondsToSelector:NSSelectorFromString(@"singleton")])return nil;
    id settings=((id(*)(id,SEL))objc_msgSend)(cls,NSSelectorFromString(@"singleton"));
    if(![settings respondsToSelector:NSSelectorFromString(@"screenSaverTimeout")] ||
       ![settings respondsToSelector:NSSelectorFromString(@"setScreenSaverTimeout:")])return nil;
    return settings;
}
static void AppSaverSet(BOOL inhibit) {
    id settings=AppSaverFacade();if(!settings)return;
    if(inhibit && !appSaverHeld) {
        appSaverOriginal=((int(*)(id,SEL))objc_msgSend)(settings,NSSelectorFromString(@"screenSaverTimeout"));
        appSaverHeld=YES;
        ((void(*)(id,SEL,int))objc_msgSend)(settings,NSSelectorFromString(@"setScreenSaverTimeout:"),-1);
    } else if(!inhibit && appSaverHeld) {
        ((void(*)(id,SEL,int))objc_msgSend)(settings,NSSelectorFromString(@"setScreenSaverTimeout:"),(int)appSaverOriginal);
        appSaverHeld=NO;
    }
    if([settings respondsToSelector:NSSelectorFromString(@"flushDiskChanges")])
        ((void(*)(id,SEL))objc_msgSend)(settings,NSSelectorFromString(@"flushDiskChanges"));
}

static char cloudtuneTimerKey;
static char musicSearchEditorKey;
static NSMutableArray *musicRows;
static NSString *musicPage=@"Home";
static BOOL musicConsumedMenuPress=NO;
static NSInteger musicSelected=0;
static AVPlayer *musicPlayer=nil;
static NSString *musicNowPlaying=nil;
static NSArray *musicLyricsLines=nil;
static NSString *musicLyricSongID=nil;
static NSString *musicReturnPage=@"Tracks";
static NSTimeInterval musicOKDownAt=0;
static NSUInteger musicOKHoldToken=0;
static BOOL musicOKHoldDone=NO;
static NSMutableDictionary *musicRecommendArts=nil;
static NSMutableSet *musicRecommendArtPending=nil;
static BOOL musicLoading=NO;
static NSString *musicStatus=nil;
static NSString *musicQuery=nil;
static NSMutableString *musicSearchText=nil;
static NSInteger musicLetterIndex=0;
static NSString *musicAlphabet=@"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ";
static NSString *musicCountry=nil;
static NSString *musicTag=nil;
static NSDictionary *musicPlayingStation=nil;
static BOOL musicPaused=NO;
static NSInteger musicRetryCount=0;
static NSString *musicLastError=nil;
static NSString *musicLastStationPage=nil;
static NSInteger musicLastStationIndex=0;
static id musicObserver=nil;
static NSTimeInterval musicNextRetry=0;
static NSTimeInterval musicStartedAt=0;
static NSData *musicAlbumArt=nil;
static NSString *musicArtSongID=nil;
static CGImageRef musicCachedCover=NULL;
static void MusicAlbumArtBackground(id controller,id track) {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc]init];
    NSString *urlString=[track objectForKey:@"cover_url"];
    NSString *songID=[track objectForKey:@"id"];
    NSData *data=nil;
    NSURL *resolvedArtURL=CloudTuneMediaURL(urlString);
    if(resolvedArtURL && [urlString length]<900) {
        NSURL *url=resolvedArtURL;
        NSMutableURLRequest *req=[NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReturnCacheDataElseLoad timeoutInterval:10];
        data=[NSURLConnection sendSynchronousRequest:req returningResponse:NULL error:NULL];
    }
    if(data.length && data.length<1500000) {
        @synchronized([NSObject class]) {
            if([songID isEqualToString:musicArtSongID]){
                [musicAlbumArt release];musicAlbumArt=[data copy];
                if(musicCachedCover){CGImageRelease(musicCachedCover);musicCachedCover=NULL;}
                CGImageSourceRef src=CGImageSourceCreateWithData((CFDataRef)data,NULL);
                if(src){musicCachedCover=CGImageSourceCreateImageAtIndex(src,0,NULL);CFRelease(src);}
            }
        }
        [controller performSelectorOnMainThread:NSSelectorFromString(@"cloudtuneApplyFreshData") withObject:nil waitUntilDone:NO];
    }
    [pool drain];
}
static void MusicAlbumArtSelector(id self,SEL cmd,id track){(void)cmd;MusicAlbumArtBackground(self,track);}
static BOOL musicReady=NO;
static NSArray *musicQueue=nil;
static NSInteger musicQueueIndex=-1;
static NSInteger musicPlayMode=0; /* 0 loop, 1 one-track, 2 shuffle */
static NSInteger musicPlayerFocus=0; /* 0 pause, 1 mode, 2 favorite, 3 queue */
static BOOL musicShowingQueue=NO;
static NSInteger musicQueueFocus=0;
static NSMutableSet *musicLikedIDs=nil;
static BOOL musicLikeLoaded=NO;

static NSUInteger musicPlayGeneration=0;
static id musicActiveController=nil;
static void MusicQueueAdvance(id controller,NSInteger delta);
static void MusicQueueAdvanceAutomatic(id controller);
static void MusicRefresh(id self,SEL cmd);
static void MusicQueuePlay(id controller);

static NSTimeInterval musicNextPressedAt=0;
static NSUInteger musicNextPressToken=0;
static BOOL musicNextHoldTriggered=NO;
static void MusicLogRemote(NSInteger action,NSInteger value,NSInteger origin,const char *decision) {
    FILE *f=fopen("/var/tmp/cloudtune_remote_diag.log","a");
    if(f){fprintf(f,"%.3f action=%ld value=%ld origin=%ld state=%s queue=%ld\n",[NSDate timeIntervalSinceReferenceDate],(long)action,(long)value,(long)origin,decision,(long)musicQueueIndex);fclose(f);}
}
static void MusicNextHoldTimeout(id self,SEL cmd,id token) {
    (void)cmd;
    if([token unsignedIntegerValue]!=musicNextPressToken || musicNextHoldTriggered || musicNextPressedAt<=0)return;
    /* No release/repeat event: treat as a single next. Never make the menu wait. */
    musicNextHoldTriggered=YES;
    musicNextPressedAt=0;
    MusicLogRemote(10,1,1,"next-fallback");
    MusicQueueAdvance(self,1);
}
static void MusicNextKey(id controller,NSInteger action,NSInteger value) {
    if(![musicQueue count])return;
    if(![musicPage isEqual:@"Tracks"]){if(value==1)MusicQueueAdvance(controller,1);return;}
    NSTimeInterval now=[NSDate timeIntervalSinceReferenceDate];
    if(value==1){
        if(musicNextPressedAt>0 && now-musicNextPressedAt>=0.45 && !musicNextHoldTriggered){
            musicNextHoldTriggered=YES;musicNextPressedAt=0;musicNextPressToken++;
            MusicLogRemote(action,value,1,"long-prev");MusicQueueAdvance(controller,-1);return;
        }
        if(musicNextPressedAt>0)return;
        musicNextPressedAt=now;musicNextHoldTriggered=NO;musicNextPressToken++;
        MusicLogRemote(action,value,1,"next-down");
        [controller performSelector:NSSelectorFromString(@"cloudtuneNextHoldTimeout:") withObject:@(musicNextPressToken) afterDelay:0.55];
    } else if(value==0 && musicNextPressedAt>0){
        NSTimeInterval duration=now-musicNextPressedAt;
        musicNextPressedAt=0;musicNextPressToken++;
        if(duration>=0.45){musicNextHoldTriggered=YES;MusicLogRemote(action,value,1,"release-long-prev");MusicQueueAdvance(controller,-1);}
        else {musicNextHoldTriggered=YES;MusicLogRemote(action,value,1,"release-short-next");MusicQueueAdvance(controller,1);}
    }
}



static void MusicRefresh(id self, SEL cmd);
static void MusicPlayStation(id controller,NSDictionary *item);
@interface MusicPlaybackMonitor : NSObject
- (void)playerFailed:(NSNotification *)note;
- (void)playerStatus:(NSNotification *)note;
- (void)playerEnded:(NSNotification *)note;
@end
@implementation MusicPlaybackMonitor
- (void)playerEnded:(NSNotification *)note {
    if(musicPlayer && [note object]==musicPlayer.currentItem && musicActiveController)
        MusicQueueAdvanceAutomatic(musicActiveController);
}

- (void)playerFailed:(NSNotification *)note {
    NSError *error=[[note userInfo] objectForKey:AVPlayerItemFailedToPlayToEndTimeErrorKey];
    musicStatus=[[NSString stringWithFormat:CloudTuneL(@"播放失败：%@", @"Playback failed: %@"),error.localizedDescription?:CloudTuneL(@"未知错误", @"Unknown error")] copy];
    NSLog(@"Music: playback failed %@",error);
}
- (void)playerStatus:(NSNotification *)note {
    if (musicPlayer.currentItem.status==AVPlayerItemStatusFailed) {
        musicStatus=[[NSString stringWithFormat:CloudTuneL(@"播放失败：%@", @"Playback failed: %@"),musicPlayer.currentItem.error.localizedDescription?:CloudTuneL(@"格式不受支持", @"Unsupported format")] copy];
        NSLog(@"Music: player item failed %@",musicPlayer.currentItem.error);
    }
}
@end
static void MusicStopPlayback(void) {
    if (musicPlayer.currentItem && musicObserver) {
        [[NSNotificationCenter defaultCenter] removeObserver:musicObserver name:AVPlayerItemFailedToPlayToEndTimeNotification object:musicPlayer.currentItem];
        [[NSNotificationCenter defaultCenter] removeObserver:musicObserver name:AVPlayerItemDidPlayToEndTimeNotification object:musicPlayer.currentItem];
        /* Status is polled on the main run loop; do not register KVO without observeValueForKeyPath:. */
    }
    [musicPlayer pause];[musicPlayer release];musicPlayer=nil;musicPaused=NO;musicReady=NO;
}
static void MusicPlayStation(id controller,NSDictionary *item) {
    NSString *stream=[item objectForKey:@"url_resolved"];
    NSURL *url=[stream isKindOfClass:[NSString class]]?[NSURL URLWithString:stream]:nil;
    if (!url || ![@[@"http",@"https"] containsObject:[url.scheme lowercaseString]]) {musicStatus=CloudTuneL(@"该歌曲无法播放", @"This track cannot be played");return;}
    MusicStopPlayback();
    AVPlayerItem *playerItem=[AVPlayerItem playerItemWithURL:url];
    musicPlayer=[[AVPlayer playerWithPlayerItem:playerItem] retain];
    if (!musicObserver)musicObserver=[[MusicPlaybackMonitor alloc]init];
    [[NSNotificationCenter defaultCenter] addObserver:musicObserver selector:@selector(playerFailed:) name:AVPlayerItemFailedToPlayToEndTimeNotification object:playerItem];
    [[NSNotificationCenter defaultCenter] addObserver:musicObserver selector:@selector(playerEnded:) name:AVPlayerItemDidPlayToEndTimeNotification object:playerItem];
    /* Status polling avoids KVO crashes on legacy ATV3 AVFoundation. */
    [musicPlayer play];
    musicStartedAt=[NSDate timeIntervalSinceReferenceDate];musicReady=NO;
    [musicPlayingStation release];musicPlayingStation=[item copy];
    [musicNowPlaying release];musicNowPlaying=[[item objectForKey:@"name"] copy];
    [musicArtSongID release];musicArtSongID=[[item objectForKey:@"id"] copy];
    [musicLyricsLines release];musicLyricsLines=nil;
    if(musicArtSongID.length)
        [NSThread detachNewThreadSelector:NSSelectorFromString(@"cloudtuneLyricsLoad:") toTarget:controller withObject:musicArtSongID];
    if(musicArtSongID.length)
        [NSThread detachNewThreadSelector:NSSelectorFromString(@"cloudtuneHistoryRecord:") toTarget:controller withObject:musicArtSongID];
    [musicAlbumArt release];musicAlbumArt=nil;
    @synchronized([NSObject class]){if(musicCachedCover){CGImageRelease(musicCachedCover);musicCachedCover=NULL;}}
    if([[item objectForKey:@"cover_url"] isKindOfClass:[NSString class]])
        [NSThread detachNewThreadSelector:NSSelectorFromString(@"cloudtuneAlbumArt:") toTarget:controller withObject:item];
    musicStatus=CloudTuneL(@"正在连接歌曲…", @"Connecting to track...");musicPaused=NO;
}

static NSString *MusicEscape(NSString *s) { return [[s stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding] stringByReplacingOccurrencesOfString:@"+" withString:@"%2B"]; }
static NSDictionary *MusicAPI(NSString *path) {
    NSURL *url=CloudTuneBridgeURL(path);
    if (!url) return nil;
    NSMutableURLRequest *req=[NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:12];
    NSData *data=[NSURLConnection sendSynchronousRequest:req returningResponse:NULL error:NULL];
    if (!data) return nil;
    id result=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    return [result isKindOfClass:[NSDictionary class]] ? result : nil;
}
static NSArray *musicSavedPlaylists=nil;
static NSMutableDictionary *musicSafeTrackCache=nil;
static NSString *musicSelectedPlaylistID=nil;
static NSInteger musicSavedPlaylistIndex=0;
static NSString *musicQRToken=nil;
static NSData *musicQRImage=nil;
static BOOL musicQRBusy=NO;
static NSTimeInterval musicLastQRCheck=0;
static void MusicStartQRBackground(id controller) {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc]init];
    NSDictionary *result=MusicAPI(@"/v1/music/auth/qr/start");
    NSString *token=[result objectForKey:@"token"];
    if ([token isKindOfClass:[NSString class]] && token.length) {
        NSString *path=[NSString stringWithFormat:@"/v1/music/auth/qr/image?token=%@",MusicEscape(token)];
        NSURL *url=CloudTuneBridgeURL(path);
        if (!url) { @synchronized([NSObject class]) { musicQRBusy=NO; musicStatus=CloudTuneL(@"Bridge 地址未配置", @"Bridge URL is not configured"); } [pool drain]; return; }
        NSData *png=[NSData dataWithContentsOfURL:url];
        @synchronized([NSObject class]) {
            [musicQRToken release];musicQRToken=[token copy];
            [musicQRImage release];musicQRImage=[png copy];
            musicStatus=png.length?CloudTuneL(@"打开网易云音乐 App 扫码并确认", @"Open the NetEase Cloud Music app to scan and confirm"):CloudTuneL(@"二维码图片无法加载", @"Unable to load QR image");
            musicQRBusy=NO;
        }
    } else {
        @synchronized([NSObject class]) {musicQRBusy=NO;musicStatus=CloudTuneL(@"二维码服务暂时不可用", @"QR login service is temporarily unavailable");}
    }
    [controller performSelectorOnMainThread:NSSelectorFromString(@"cloudtuneApplyFreshData") withObject:nil waitUntilDone:NO];
    [pool drain];
}
static void MusicQRCheckBackground(id controller) {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc]init];
    NSString *token=nil;@synchronized([NSObject class]){token=[musicQRToken copy];}
    NSDictionary *data=MusicAPI([NSString stringWithFormat:@"/v1/music/auth/qr/status?token=%@",MusicEscape(token?:@"")]);
    NSString *state=[data objectForKey:@"status"];
    @synchronized([NSObject class]) {
        if ([musicQRToken isEqualToString:token]) {
            if ([state isEqualToString:@"authorized"]) {musicStatus=CloudTuneL(@"扫码授权成功，账号已连接", @"Authorization successful. Account connected");[musicQRToken release];musicQRToken=nil;}
            else if ([state isEqualToString:@"waiting_confirm"])musicStatus=CloudTuneL(@"请在手机网易云音乐中确认登录", @"Confirm sign-in in the NetEase Cloud Music app");
            else if ([state isEqualToString:@"expired"]) {musicStatus=CloudTuneL(@"二维码已过期，按确认键重新生成", @"QR code expired. Press Select to create a new one");[musicQRToken release];musicQRToken=nil;}
            else if ([state isEqualToString:@"waiting_scan"])musicStatus=CloudTuneL(@"请用网易云音乐 App 扫描二维码", @"Scan the QR code with the NetEase Cloud Music app");
        }
        musicQRBusy=NO;
    }
    [controller performSelectorOnMainThread:NSSelectorFromString(@"cloudtuneApplyFreshData") withObject:nil waitUntilDone:NO];
    [token release];[pool drain];
}
static void MusicQRStartSelector(id self,SEL cmd,id unused){(void)cmd;(void)unused;MusicStartQRBackground(self);}
static void MusicQRCheckSelector(id self,SEL cmd,id unused){(void)cmd;(void)unused;MusicQRCheckBackground(self);}
/* Background threads only fetch immutable responses. All UI and cache mutations on main thread. */
static void MusicLibraryResult(id self,SEL cmd,id payload) {
    (void)cmd;
    NSString *kind=[payload objectForKey:@"kind"];
    NSDictionary *reply=[payload objectForKey:@"reply"];
    if(![[reply objectForKey:@"ok"] boolValue] || [[reply objectForKey:@"loading"] boolValue]){
        if([kind isEqual:@"playlists"] && [musicPage isEqual:@"Playlists"]){musicLoading=NO;musicStatus=CloudTuneL(@"歌单加载失败，请返回重试", @"Failed to load playlists. Go back and retry");MusicRefresh(self,NULL);}
        return;
    }
    if([kind isEqual:@"playlists"]){
        NSArray *items=[reply objectForKey:@"playlists"];
        if(![items isKindOfClass:[NSArray class]])return;
        [musicSavedPlaylists release];musicSavedPlaylists=[items copy];
        if([musicPage isEqual:@"Playlists"]){
            NSString *current=nil;
            if(musicSelected>=0 && musicSelected<(NSInteger)musicRows.count){
                id oldID=[[musicRows objectAtIndex:musicSelected] objectForKey:@"id"];
                if([oldID isKindOfClass:[NSString class]])current=[oldID copy];
            }
            [musicRows release];musicRows=[[NSMutableArray alloc]initWithArray:items];
            musicSelected=MIN(musicSelected,MAX(0,(NSInteger)musicRows.count-1));
            for(NSInteger i=0;i<(NSInteger)musicRows.count;i++)if([[[musicRows objectAtIndex:i] objectForKey:@"id"] isEqual:current]){musicSelected=i;break;}
            [current release];
            musicStatus=CloudTuneL(@"歌单已加载", @"Playlists loaded");musicLoading=NO;
        }
    } else if([kind isEqual:@"tracks"]){
        NSString *identifier=[payload objectForKey:@"identifier"];
        NSArray *rawTracks=[reply objectForKey:@"tracks"];
        if(![identifier isKindOfClass:[NSString class]] || ![rawTracks isKindOfClass:[NSArray class]])return;
        NSMutableArray *safeTracks=[NSMutableArray arrayWithCapacity:[rawTracks count]];
        for(id entry in rawTracks){
            if(![entry isKindOfClass:[NSDictionary class]])continue;
            NSMutableDictionary *row=[NSMutableDictionary dictionaryWithDictionary:entry];
            id name=[row objectForKey:@"name"];
            if(![name isKindOfClass:[NSString class]])[row setObject:CloudTuneL(@"歌曲信息不可用", @"Track information unavailable") forKey:@"name"];
            id artists=[row objectForKey:@"artists"];
            NSMutableArray *names=[NSMutableArray array];
            if([artists isKindOfClass:[NSArray class]])for(id artist in artists)if([artist isKindOfClass:[NSString class]])[names addObject:artist];
            [row setObject:names forKey:@"artists"];
            [safeTracks addObject:row];
        }
        NSArray *tracks=safeTracks;
        if(!musicSafeTrackCache)musicSafeTrackCache=[[NSMutableDictionary alloc]init];
        [musicSafeTrackCache setObject:tracks forKey:identifier];
        if([musicPage isEqual:@"Tracks"] && [musicSelectedPlaylistID isEqualToString:identifier]){
            NSString *current=nil;
            if(musicSelected>=0 && musicSelected<(NSInteger)musicRows.count){
                id oldID=[[musicRows objectAtIndex:musicSelected] objectForKey:@"id"];
                if([oldID isKindOfClass:[NSString class]])current=[oldID copy];
            }
            [musicRows release];musicRows=[[NSMutableArray alloc]initWithArray:tracks];
            musicSelected=MIN(musicSelected,MAX(0,(NSInteger)musicRows.count-1));
            for(NSInteger i=0;i<(NSInteger)musicRows.count;i++)if([[[musicRows objectAtIndex:i] objectForKey:@"id"] isEqual:current]){musicSelected=i;break;}
            [current release];
            musicStatus=[[NSString stringWithFormat:CloudTuneL(@"歌曲列表：%lu 首", @"Track list: %lu tracks"),(unsigned long)tracks.count] copy];musicLoading=NO;
        }
    }
    MusicRefresh(self,NULL);
}
static void MusicPlaylistsBackground(id controller) {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc]init];
    NSDictionary *reply=MusicAPI(@"/v1/music/playlists");
    NSDictionary *payload=@{@"kind":@"playlists",@"reply":reply?:@{}};
    [controller performSelectorOnMainThread:NSSelectorFromString(@"cloudtuneLibraryResult:") withObject:payload waitUntilDone:NO];
    [pool drain];
}
static void MusicTracksBackground(id controller) {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc]init];
    NSString *identifier=nil;
    @synchronized([NSObject class]) { identifier=[musicSelectedPlaylistID copy]; }
    NSDictionary *reply=MusicAPI([NSString stringWithFormat:@"/v1/music/playlists/%@/tracks",MusicEscape(identifier?:@"")]);
    NSDictionary *payload=@{@"kind":@"tracks",@"identifier":identifier?:@"",@"reply":reply?:@{}};
    [controller performSelectorOnMainThread:NSSelectorFromString(@"cloudtuneLibraryResult:") withObject:payload waitUntilDone:NO];
    [identifier release];[pool drain];
}
static void MusicTracksSelector(id self,SEL cmd,id unused){(void)cmd;(void)unused;MusicTracksBackground(self);}
static void MusicPlaylistsSelector(id self,SEL cmd,id unused){(void)cmd;(void)unused;MusicPlaylistsBackground(self);}
static void MusicPlaybackResolved(id controller,SEL cmd,id payload) {
    (void)cmd;
    if([[payload objectForKey:@"generation"] unsignedIntegerValue]!=musicPlayGeneration)return;
    NSDictionary *item=[payload objectForKey:@"item"];
    NSDictionary *reply=[payload objectForKey:@"reply"];
    if ([[reply objectForKey:@"ok"] boolValue] && [[reply objectForKey:@"url_resolved"] isKindOfClass:[NSString class]]) {
        NSMutableDictionary *play=[NSMutableDictionary dictionaryWithDictionary:item];
        [play setObject:[reply objectForKey:@"url_resolved"] forKey:@"url_resolved"];
        MusicPlayStation(controller,play);
    } else musicStatus=CloudTuneL(@"无法播放：资源不可用或账号没有授权", @"Cannot play: unavailable or not authorized for this account");
    MusicRefresh(controller,NULL);
}
static void MusicResolveTrackBackground(id controller,id request) {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc]init];
    NSDictionary *selected=[request objectForKey:@"item"];
    NSString *song=[selected objectForKey:@"id"];
    if([song isKindOfClass:[NSString class]] && song.length){
        NSDictionary *response=MusicAPI([NSString stringWithFormat:@"/v1/music/tracks/%@/playback?quality=exhigh",MusicEscape(song)]);
        NSDictionary *payload=@{@"item":selected,@"reply":response?:@{},@"generation":[request objectForKey:@"generation"]};
        [controller performSelectorOnMainThread:NSSelectorFromString(@"cloudtunePlaybackResolved:") withObject:payload waitUntilDone:NO];
    }
    [pool drain];
}
static void MusicResolveTrackSelector(id self,SEL cmd,id request){(void)cmd;MusicResolveTrackBackground(self,request);}
static void MusicPlaybackResolvedSelector(id self,SEL cmd,id payload){MusicPlaybackResolved(self,cmd,payload);}
static void MusicPrefetchNextBackground(id self,SEL cmd,id ids){
    (void)self;(void)cmd;
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc]init];
    if([ids isKindOfClass:[NSString class]] && [ids length])
        MusicAPI([@"/v1/music/playback/prefetch?ids=" stringByAppendingString:ids]);
    [pool drain];
}
static void MusicQueuePlay(id controller) {
    if(musicQueueIndex<0 || musicQueueIndex>=(NSInteger)[musicQueue count])return;
    musicPlayGeneration++;
    if([musicPage isEqual:@"Tracks"] && musicQueueIndex<(NSInteger)[musicRows count] && musicQueueIndex>=0) {
        NSDictionary *queueTrack=[musicQueue objectAtIndex:musicQueueIndex];
        NSDictionary *screenTrack=[musicRows objectAtIndex:musicQueueIndex];
        if([[queueTrack objectForKey:@"id"] isEqual:[screenTrack objectForKey:@"id"]])musicSelected=musicQueueIndex;
    }
    musicActiveController=controller;
    musicStatus=CloudTuneL(@"正在获取歌曲播放地址…", @"Resolving playback URL...");
    NSDictionary *request=@{@"item":[musicQueue objectAtIndex:musicQueueIndex],@"generation":@(musicPlayGeneration)};
    [NSThread detachNewThreadSelector:NSSelectorFromString(@"cloudtuneResolveTrack:") toTarget:controller withObject:request];
    NSMutableArray *ids=[NSMutableArray array];
    for(NSInteger i=musicQueueIndex+1;i<(NSInteger)[musicQueue count] && i<=musicQueueIndex+3;i++){
        NSString *sid=[[musicQueue objectAtIndex:i] objectForKey:@"id"];
        if([sid isKindOfClass:[NSString class]] && sid.length)[ids addObject:sid];
    }
    if(ids.count)[NSThread detachNewThreadSelector:NSSelectorFromString(@"cloudtunePrefetchNext:") toTarget:controller withObject:[ids componentsJoinedByString:@","]];
}
static void MusicQueueAdvanceWithMode(id controller,NSInteger delta,BOOL automatic) {
    NSInteger count=(NSInteger)musicQueue.count;
    if(!count)return;
    NSInteger next=musicQueueIndex;
    if(automatic && delta>0 && musicPlayMode==1){
        /* Single-track repeat, preserve current position. */
    }else if(delta>0 && musicPlayMode==2 && count>1){
        next=(musicQueueIndex+1+arc4random_uniform((u_int32_t)(count-1)))%count;
    }else{
        next+=delta;
        if(next>=count)next=0;
        if(next<0)next=count-1;
    }
    musicQueueIndex=next;
    MusicQueuePlay(controller);
    MusicRefresh(controller,NULL);
}
static void MusicQueueAdvance(id controller,NSInteger delta) {
    MusicQueueAdvanceWithMode(controller,delta,NO);
}
static void MusicQueueAdvanceAutomatic(id controller) {
    MusicQueueAdvanceWithMode(controller,1,YES);
}
static void MusicLoadBackground(id controller) {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc]init];
    NSString *query=nil;
    @synchronized([NSObject class]) {query=[musicQuery copy];}
    NSDictionary *result=MusicAPI([@"/v1/music/search?q=" stringByAppendingString:MusicEscape(query?:@"")]);
    @synchronized([NSObject class]) {
        if ([musicPage isEqual:@"Results"] && [musicQuery isEqualToString:query]) {
            NSArray *tracks=[result objectForKey:@"tracks"];
            [musicRows release];musicRows=[[NSMutableArray alloc]initWithArray:[tracks isKindOfClass:[NSArray class]]?tracks:@[]];
            musicSelected=0;musicLoading=NO;
            musicStatus=[result objectForKey:@"ok"] && [[result objectForKey:@"ok"] boolValue]?CloudTuneL(@"搜索完成", @"Search complete"):CloudTuneL(@"搜索失败，请检查 Mac Bridge", @"Search failed. Check the Mac Bridge");
        }
    }
    [controller performSelectorOnMainThread:NSSelectorFromString(@"cloudtuneApplyFreshData") withObject:nil waitUntilDone:NO];
    [query release];[pool drain];
}
static void MusicLoad(id controller) {
    musicLoading=YES;musicStatus=CloudTuneL(@"正在搜索歌曲…", @"Searching tracks...");
    [NSThread detachNewThreadSelector:NSSelectorFromString(@"cloudtuneLoadPage:") toTarget:controller withObject:nil];
}
static void MusicRecord(NSString *action,NSDictionary *station) {
    if (!station)return;
    NSDictionary *payload=@{@"station":station};
    NSData *body=[NSJSONSerialization dataWithJSONObject:payload options:0 error:NULL];
    NSURL *url=CloudTuneBridgeURL([@"/v1/music/" stringByAppendingString:action]);
    if (!url) return;
    NSMutableURLRequest *req=[NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:3];
    [req setHTTPMethod:@"POST"];[req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];[req setHTTPBody:body];
    [NSURLConnection sendSynchronousRequest:req returningResponse:NULL error:NULL];
}


/* ---------------------------------------------------------
   Generic ABI helpers
   --------------------------------------------------------- */

static BOOL MusicSignature(id target, SEL sel, const char *result, NSArray *args)
{
    if (!target || ![target respondsToSelector:sel])
        return NO;

    NSMethodSignature *s = [target methodSignatureForSelector:sel];

    if (!s ||
        strcmp([s methodReturnType], result) ||
        [s numberOfArguments] != [args count] + 2)
        return NO;

    for (NSUInteger i = 0; i < [args count]; i++) {
        if (strcmp([s getArgumentTypeAtIndex:i + 2],
                   [[args objectAtIndex:i] UTF8String]))
            return NO;
    }

    return YES;
}

static id MusicObject(id target, NSString *name)
{
    SEL sel = NSSelectorFromString(name);

    if (!MusicSignature(target, sel, @encode(id), @[]))
        return nil;

    return ((id(*)(id,SEL))objc_msgSend)(target, sel);
}

static id MusicNew(Class cls)
{
    if (!cls)
        return nil;

    return [[cls alloc] init];
}

static IMP MusicControllerSuper(SEL selector)
{
    Class cls = objc_getClass("ATVCloudTuneController");

    if (!cls)
        return NULL;

    Class base = class_getSuperclass(cls);

    return base ? class_getMethodImplementation(base, selector) : NULL;
}

static IMP MusicApplianceSuper(SEL selector)
{
    Class cls = objc_getClass("CloudTuneAppliance");

    if (!cls)
        return NULL;

    Class base = class_getSuperclass(cls);

    return base ? class_getMethodImplementation(base, selector) : NULL;
}

/* ---------------------------------------------------------
   Music display
   --------------------------------------------------------- */

static NSDictionary *MusicBridgeData(void)
{
    return nil;
}

static NSDictionary *cloudtuneCachedSnapshot = nil;
static NSTimeInterval cloudtuneCachedAt = 0;
static BOOL cloudtuneFetchInFlight = NO;

static NSString *MusicCachePath(void)
{
    return @"/var/mobile/Library/Caches/org.atv3.cloudtune.snapshot.json";
}

static void MusicStoreSnapshot(NSDictionary *fresh)
{
    if (![fresh isKindOfClass:[NSDictionary class]]) return;
    @synchronized([NSObject class]) {
        [cloudtuneCachedSnapshot release];
        cloudtuneCachedSnapshot=[fresh retain];
        cloudtuneCachedAt=[NSDate timeIntervalSinceReferenceDate];
    }
    NSData *data=[NSJSONSerialization dataWithJSONObject:fresh options:0 error:NULL];
    if ([data length]) [data writeToFile:MusicCachePath() atomically:YES];
}

static NSDictionary *MusicSnapshot(void)
{
    @synchronized([NSObject class]) {
        if (!cloudtuneCachedSnapshot) {
            NSData *data=[NSData dataWithContentsOfFile:MusicCachePath()];
            if ([data length]) {
                id obj=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
                if ([obj isKindOfClass:[NSDictionary class]]) cloudtuneCachedSnapshot=[obj retain];
            }
        }
        return cloudtuneCachedSnapshot;
    }
}

static void MusicFetchAsync(id controller)
{
    @synchronized([NSObject class]) {
        if (cloudtuneFetchInFlight) return;
        cloudtuneFetchInFlight=YES;
    }
    [NSThread detachNewThreadSelector:NSSelectorFromString(@"cloudtuneBackgroundFetch:")
                             toTarget:controller withObject:nil];
}

static NSString *MusicConditionMark(NSNumber *code, NSNumber *isDay)
{
    NSInteger c=[code integerValue]; BOOL day=!isDay || [isDay boolValue];
    if (c==0) return day ? @"SUN" : @"MOON";
    if (c==1 || c==2) return @"SUN/CLOUD";
    if (c==3) return @"CLOUD";
    if (c==45 || c==48) return @"FOG";
    if ((c>=51 && c<=67) || (c>=80 && c<=82)) return @"RAIN";
    if ((c>=71 && c<=77) || c==85 || c==86) return @"SNOW";
    if (c>=95) return @"STORM";
    return @"WEATHER";
}

static NSString *MusicChineseCondition(NSInteger code);

static NSString *MusicCurrentTime(void)
{
    return CloudTuneL(@"云律音乐", @"CloudTune");
}

static NSString *MusicCurrentDate(void)
{
    return musicStatus ?: CloudTuneL(@"云律音乐已就绪", @"CloudTune is ready");
}

static NSString *MusicHourlySummary(void) { return @""; }
static NSString *MusicDailySummary(void) { return @""; }

static void MusicRoundedRect(CGContextRef c, CGRect r, CGFloat radius)
{
    CGFloat x=CGRectGetMinX(r), y=CGRectGetMinY(r), w=CGRectGetWidth(r), h=CGRectGetHeight(r);
    CGContextBeginPath(c);
    CGContextMoveToPoint(c,x+radius,y);
    CGContextAddLineToPoint(c,x+w-radius,y);
    CGContextAddArc(c,x+w-radius,y+radius,radius,-M_PI_2,0,0);
    CGContextAddLineToPoint(c,x+w,y+h-radius);
    CGContextAddArc(c,x+w-radius,y+h-radius,radius,0,M_PI_2,0);
    CGContextAddLineToPoint(c,x+radius,y+h);
    CGContextAddArc(c,x+radius,y+h-radius,radius,M_PI_2,M_PI,0);
    CGContextAddLineToPoint(c,x,y+radius);
    CGContextAddArc(c,x+radius,y+radius,radius,M_PI,3*M_PI_2,0);
    CGContextClosePath(c);
}

static CTFontRef MusicCTFont(CGFloat size)
{
    CTFontRef font=CTFontCreateWithName(CFSTR("STHeitiSC-Light"),size,NULL);
    if (!font) font=CTFontCreateWithName(CFSTR("STHeiti-Light"),size,NULL);
    if (!font) font=CTFontCreateWithName(CFSTR("STHeitiSC-Medium"),size,NULL);
    if (!font) font=CTFontCreateWithName(CFSTR("STHeiti-Medium"),size,NULL);
    if (!font) font=CTFontCreateWithName(CFSTR("HelveticaNeue"),size,NULL);
    return font;
}

static CTLineRef MusicCTLine(NSString *text, CGFloat size, CGFloat gray)
{
    if (![text isKindOfClass:[NSString class]] || ![text length]) return NULL;
    @try {
    CTFontRef font=MusicCTFont(size);
    if (!font) return NULL;
    CGColorSpaceRef cs=CGColorSpaceCreateDeviceRGB();
    CGFloat comps[4]={gray,gray,gray,1.0f};
    CGColorRef color=CGColorCreate(cs,comps);
    NSDictionary *attrs=[NSDictionary dictionaryWithObjectsAndKeys:
        (id)font,(id)kCTFontAttributeName,
        (id)color,(id)kCTForegroundColorAttributeName,nil];
    NSAttributedString *as=[[[NSAttributedString alloc] initWithString:text attributes:attrs] autorelease];
    CTLineRef line=CTLineCreateWithAttributedString((CFAttributedStringRef)as);
    CGColorRelease(color); CGColorSpaceRelease(cs); CFRelease(font);
    return line;
    } @catch(NSException *exception) {
        FILE *f=fopen("/var/tmp/cloudtune_text_exception.log","a");
        if(f){fprintf(f,"text exception=%s text=%s\n",[[exception name] UTF8String],[[text description] UTF8String]);fclose(f);}
        return NULL;
    }
}

static void MusicText(CGContextRef c, NSString *text, CGFloat x, CGFloat y, CGFloat size, CGFloat gray)
{
    CTLineRef line=MusicCTLine(text,size,gray);
    if (!line) return;
    CGContextSaveGState(c);
    CGContextSetTextMatrix(c,CGAffineTransformIdentity);
    CGContextSetTextPosition(c,x,y);
    CTLineDraw(line,c);
    CGContextRestoreGState(c);
    CFRelease(line);
}

static void MusicHeartText(CGContextRef c,NSString *text,CGFloat x,CGFloat y,BOOL liked){
    CTFontRef font=MusicCTFont(23);
    if(!font)return;
    CGColorSpaceRef cs=CGColorSpaceCreateDeviceRGB();
    CGFloat rgba[4]={liked?0.96:0.93,liked?0.13:0.93,liked?0.20:0.93,1.0};
    CGColorRef color=CGColorCreate(cs,rgba);
    NSDictionary *attrs=@{(id)kCTFontAttributeName:(id)font,(id)kCTForegroundColorAttributeName:(id)color};
    NSAttributedString *str=[[[NSAttributedString alloc]initWithString:text attributes:attrs]autorelease];
    CTLineRef line=CTLineCreateWithAttributedString((CFAttributedStringRef)str);
    CGContextSaveGState(c);CGContextSetTextPosition(c,x,y);CTLineDraw(line,c);CGContextRestoreGState(c);
    CFRelease(line);CGColorRelease(color);CGColorSpaceRelease(cs);CFRelease(font);
}

static CGFloat MusicTextWidth(NSString *text, CGFloat size)
{
    CTLineRef line=MusicCTLine(text,size,1.0f);
    if (!line) return 0.0f;
    double width=CTLineGetTypographicBounds(line,NULL,NULL,NULL);
    CFRelease(line);
    return (CGFloat)width;
}

static void MusicCenteredText(CGContextRef c, NSString *text, CGFloat centerX,
                                CGFloat y, CGFloat size, CGFloat gray)
{
    MusicText(c,text,centerX-MusicTextWidth(text,size)*0.5f,y,size,gray);
}

static CGFloat MusicIconVisualCenter(NSInteger code, CGFloat scale)
{
    BOOL rain=((code>=51&&code<=67)||(code>=80&&code<=82));
    BOOL snow=((code>=71&&code<=77)||code==85||code==86);
    BOOL storm=(code>=95);
    BOOL fog=(code==45||code==48);
    BOOL cloudy=(code>=1&&code<=3)||rain||snow||storm||fog;
    if (cloudy) return 75.0f*scale;
    return 37.0f*scale;
}

static void MusicIcon(CGContextRef c, NSInteger code, BOOL day, CGFloat x, CGFloat y, CGFloat scale)
{
    BOOL rain=((code>=51&&code<=67)||(code>=80&&code<=82));
    BOOL snow=((code>=71&&code<=77)||code==85||code==86);
    BOOL storm=(code>=95);
    BOOL fog=(code==45||code==48);
    BOOL cloudy=(code>=1&&code<=3)||rain||snow||storm||fog;

    if (code==0 || code==1 || code==2) {
        CGContextSetRGBFillColor(c,1.0,0.78,0.12,1.0);
        if (day) {
            CGContextFillEllipseInRect(c,CGRectMake(x+15*scale,y+28*scale,42*scale,42*scale));
            CGContextSetLineWidth(c,4*scale); CGContextSetRGBStrokeColor(c,1.0,0.78,0.12,1.0);
            for(int i=0;i<8;i++){ CGFloat a=i*M_PI/4.0; CGContextMoveToPoint(c,x+(36+29*cos(a))*scale,y+(49+29*sin(a))*scale); CGContextAddLineToPoint(c,x+(36+39*cos(a))*scale,y+(49+39*sin(a))*scale); }
            CGContextStrokePath(c);
        } else {
            CGContextFillEllipseInRect(c,CGRectMake(x+16*scale,y+27*scale,44*scale,44*scale));
            CGContextSetRGBFillColor(c,0.12,0.24,0.43,1.0);
            CGContextFillEllipseInRect(c,CGRectMake(x+29*scale,y+36*scale,40*scale,40*scale));
        }
    }
    if (cloudy) {
        CGContextSetRGBFillColor(c,0.88,0.92,0.97,1.0);
        CGContextFillEllipseInRect(c,CGRectMake(x+34*scale,y+37*scale,42*scale,32*scale));
        CGContextFillEllipseInRect(c,CGRectMake(x+55*scale,y+27*scale,46*scale,43*scale));
        CGContextFillEllipseInRect(c,CGRectMake(x+78*scale,y+40*scale,38*scale,29*scale));
        CGContextFillRect(c,CGRectMake(x+45*scale,y+48*scale,60*scale,22*scale));
    }
    if (rain || storm) {
        CGContextSetRGBStrokeColor(c,0.32,0.70,1.0,1.0); CGContextSetLineWidth(c,4*scale);
        for(int i=0;i<3;i++){ CGFloat dx=(55+i*20)*scale; CGContextMoveToPoint(c,x+dx,y+78*scale); CGContextAddLineToPoint(c,x+(dx-7*scale),y+94*scale); } CGContextStrokePath(c);
    }
    if (snow) {
        CGContextSetRGBFillColor(c,0.85,0.94,1.0,1.0);
        for(int i=0;i<3;i++) CGContextFillEllipseInRect(c,CGRectMake(x+(50+i*23)*scale,y+82*scale,7*scale,7*scale));
    }
    if (fog) {
        CGContextSetRGBStrokeColor(c,0.75,0.80,0.86,1.0); CGContextSetLineWidth(c,3*scale);
        for(int i=0;i<3;i++){ CGContextMoveToPoint(c,x+35*scale,y+(78+i*9)*scale); CGContextAddLineToPoint(c,x+110*scale,y+(78+i*9)*scale); } CGContextStrokePath(c);
    }
    if (storm) {
        CGContextSetRGBFillColor(c,1.0,0.78,0.12,1.0);
        CGContextBeginPath(c); CGContextMoveToPoint(c,x+76*scale,y+70*scale); CGContextAddLineToPoint(c,x+60*scale,y+94*scale); CGContextAddLineToPoint(c,x+73*scale,y+92*scale); CGContextAddLineToPoint(c,x+64*scale,y+110*scale); CGContextAddLineToPoint(c,x+91*scale,y+82*scale); CGContextAddLineToPoint(c,x+77*scale,y+84*scale); CGContextClosePath(c); CGContextFillPath(c);
    }
}

static NSArray *MusicHomeOptions(void) {return CLOUDTUNE_LANG_EN ? @[@"Recommended",@"Search",@"My Playlists",@"Recently Played",@"Account & Settings"] : @[@"推荐音乐",@"搜索歌曲",@"我的歌单",@"最近播放",@"账号与设置"];}
static NSString *MusicDisplayPage(NSString *page) {
    NSDictionary *names=CLOUDTUNE_LANG_EN ? @{@"Home":@"Discover",@"Recommend":@"Recommended",@"Search":@"Search",@"Playlists":@"My Playlists",@"Charts":@"Charts",@"Recent":@"Recently Played",@"Account":@"Account & Settings",@"Results":@"Search Results",@"Tracks":@"Playlist Tracks"} : @{@"Home":@"发现音乐",@"Recommend":@"推荐音乐",@"Search":@"搜索歌曲",@"Playlists":@"我的歌单",@"Charts":@"排行榜",@"Recent":@"最近播放",@"Account":@"账号与设置",@"Results":@"搜索结果",@"Tracks":@"歌单歌曲"};
    return [names objectForKey:page]?:page;
}
static NSData *MusicRenderImage(void)
{
    NSTimeInterval renderStart=[NSDate timeIntervalSinceReferenceDate];
    const size_t width=1280,height=720;
    CGColorSpaceRef cs=CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx=CGBitmapContextCreate(NULL,width,height,8,width*4,cs,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(cs);if(!ctx)return nil;
    CGContextSetRGBFillColor(ctx,0.055,0.055,0.070,1);CGContextFillRect(ctx,CGRectMake(0,0,width,height));
    CGContextSetRGBFillColor(ctx,0.095,0.095,0.115,1);CGContextFillRect(ctx,CGRectMake(0,0,285,720));
    MusicText(ctx,CloudTuneL(@"云律音乐", @"CloudTune"),34,647,32,1);
    NSString *page=nil,*status=nil;NSArray *rows=nil;NSString *search=nil;NSInteger selected=0;
    @synchronized([NSObject class]) {page=[musicPage copy];status=[musicStatus copy];rows=[musicRows copy];search=[musicSearchText copy];selected=musicSelected;}
    NSArray *options=MusicHomeOptions();
    for(NSInteger i=0;i<(NSInteger)[options count];i++){
        CGFloat y=538-i*72;
        BOOL focus=[page isEqual:@"Home"]&&selected==i;
        BOOL active=![page isEqual:@"Home"]&&[MusicDisplayPage(page) isEqual:[options objectAtIndex:i]];
        if(focus||active){CGContextSetRGBFillColor(ctx,0.72,0.12,0.18,focus?0.94:0.40);MusicRoundedRect(ctx,CGRectMake(19,y-14,248,58),12);CGContextFillPath(ctx);}
        MusicText(ctx,[options objectAtIndex:i],48,y,27,focus||active?1:0.70);
    }
    CGContextSetRGBFillColor(ctx,0.13,0.13,0.15,1);MusicRoundedRect(ctx,CGRectMake(312,113,934,490),20);CGContextFillPath(ctx);
    MusicText(ctx,MusicDisplayPage(page),333,641,41,1);
    if(musicPlayer && musicNowPlaying) {
        NSString *current=[NSString stringWithFormat:CloudTuneL(@"%@：%@", @"%@: %@"),musicPaused?CloudTuneL(@"已暂停", @"Paused"):CloudTuneL(@"正在播放", @"Now Playing"),musicNowPlaying];
        if(current.length>27)current=[[current substringToIndex:26] stringByAppendingString:@"…"];
        MusicText(ctx,current,337,572,24,0.9);
    } else MusicText(ctx,CloudTuneL(@"音乐随心听", @"Music, your way"),337,572,26,0.72);
    CGContextSetRGBFillColor(ctx,0.23,0.075,0.105,1);MusicRoundedRect(ctx,CGRectMake(342,300,876,229),20);CGContextFillPath(ctx);
    if ([page isEqual:@"Search"]) {
        MusicText(ctx,CloudTuneL(@"输入歌曲或歌手名称", @"Enter a track or artist"),374,455,32,1);
        MusicText(ctx,search.length?search:@"_",374,396,32,1);
        MusicText(ctx,CloudTuneL(@"按确认键打开搜索；已支持 iPhone 遥控器键盘输入", @"Press Select to search; iPhone Remote keyboard input is supported"),374,345,27,1);
    } else if([page isEqual:@"NowPlaying"]){
        CGContextSetRGBFillColor(ctx,0.055,0.055,0.070,1);CGContextFillRect(ctx,CGRectMake(0,0,1280,720));
        CGImageRef art=NULL;
        @synchronized([NSObject class]){if(musicCachedCover)art=CGImageRetain(musicCachedCover);}
        if(art){CGContextDrawImage(ctx,CGRectMake(86,173,420,420),art);CGImageRelease(art);}
        MusicText(ctx,musicNowPlaying?:CloudTuneL(@"云律音乐", @"CloudTune"),85,625,39,1);
        NSArray *lyrics=[musicLyricsLines copy];
        Float64 seconds=musicPlayer?CMTimeGetSeconds(musicPlayer.currentTime):0;
        if(!isfinite(seconds)||seconds<0)seconds=0;
        NSInteger active=-1;
        for(NSInteger i=0;i<(NSInteger)lyrics.count;i++)if([[[lyrics objectAtIndex:i] objectForKey:@"time"] doubleValue]<=seconds)active=i;
        if(!lyrics.count)MusicText(ctx,CloudTuneL(@"暂无同步歌词", @"No synced lyrics"),620,380,30,0.75);
        else for(NSInteger delta=-3;delta<=3;delta++){
            NSInteger index=MAX(0,active)+delta;
            if(index<0||index>=(NSInteger)lyrics.count)continue;
            id line=[[lyrics objectAtIndex:index] objectForKey:@"text"];
            if(![line isKindOfClass:[NSString class]])continue;
            if([line length]>35)line=[[line substringToIndex:35] stringByAppendingString:@"…"];
            MusicText(ctx,line,610,393-delta*57,delta==0?28:24,delta==0?1.0:0.57);
            if(delta==0){
                id translation=[[lyrics objectAtIndex:index] objectForKey:@"translation"];
                if([translation isKindOfClass:[NSString class]] && [translation length]){
                    if([translation length]>33)translation=[[translation substringToIndex:33] stringByAppendingString:@"…"];
                    MusicText(ctx,translation,610,357,23,0.84);
                }
            }
        }
        [lyrics release];
        Float64 duration=musicPlayer?CMTimeGetSeconds(musicPlayer.currentItem.duration):0;
        if(!isfinite(duration)||duration<=0){
            id ms=[musicPlayingStation objectForKey:@"duration_ms"];
            duration=[ms respondsToSelector:@selector(doubleValue)]?[ms doubleValue]/1000.0:0;
        }
        if(duration>0){
            CGFloat fraction=MIN(1.0,MAX(0.0,seconds/duration));
            CGContextSetRGBFillColor(ctx,0.27,0.27,0.30,1);CGContextFillRect(ctx,CGRectMake(610,147,540,10));
            (void)fraction; /* progress is a native BackRow image-control overlay */
            MusicText(ctx,[NSString stringWithFormat:@"%02d:%02d",(int)seconds/60,(int)seconds%60],610,169,22,1);
            MusicText(ctx,[NSString stringWithFormat:@"%02d:%02d",(int)duration/60,(int)duration%60],1085,169,22,1);
        }
        NSArray *modes=CLOUDTUNE_LANG_EN ? @[@"Repeat Queue",@"Repeat One",@"Shuffle"] : @[@"列表循环",@"单曲循环",@"随机播放"];
        NSArray *controls=@[musicPaused?CloudTuneL(@"▶ 继续", @"▶ Resume"):CloudTuneL(@"Ⅱ 暂停", @"Ⅱ Pause"),[modes objectAtIndex:musicPlayMode],
                            [musicLikedIDs containsObject:[musicPlayingStation objectForKey:@"id"]]?CloudTuneL(@"♥ 已喜欢", @"♥ Liked"):CloudTuneL(@"♡ 喜欢", @"♡ Like"),
                            CloudTuneL(@"播放队列", @"Queue")];
        for(NSInteger i=0;i<4;i++){
            CGFloat x=620+i*138;
            BOOL focus=i==musicPlayerFocus;
            CGContextSetRGBFillColor(ctx,focus?0.73:0.18,focus?0.15:0.18,focus?0.22:0.22,1);
            MusicRoundedRect(ctx,CGRectMake(x,66,128,49),9);CGContextFillPath(ctx);
            if(i==2)MusicHeartText(ctx,[musicLikedIDs containsObject:[musicPlayingStation objectForKey:@"id"]]?CloudTuneL(@"♥ 已喜欢", @"♥ Liked"):CloudTuneL(@"♡ 喜欢", @"♡ Like"),x+7,81,[musicLikedIDs containsObject:[musicPlayingStation objectForKey:@"id"]]);
            else MusicText(ctx,[controls objectAtIndex:i],x+7,81,20,1);
        }
        MusicText(ctx,CloudTuneL(@"上下选按钮  确认执行  左右快进退  Menu返回", @"Up/Down: control   Select: activate   Left/Right: seek   Menu: back"),625,35,18,0.78);
        if(musicShowingQueue){
            CGContextSetRGBFillColor(ctx,0.08,0.08,0.11,0.97);CGContextFillRect(ctx,CGRectMake(596,204,620,415));
            MusicText(ctx,CloudTuneL(@"接下来播放", @"Up Next"),625,575,28,1);
            NSInteger first=MAX(0,musicQueueFocus-2);
            for(NSInteger j=first;j<(NSInteger)musicQueue.count && j<first+6;j++){
                id song=[musicQueue objectAtIndex:j];id title=[song objectForKey:@"name"];
                if(![title isKindOfClass:[NSString class]])title=CloudTuneL(@"未知歌曲", @"Unknown Track");
                if([title length]>27)title=[[title substringToIndex:27] stringByAppendingString:@"…"];
                MusicText(ctx,[NSString stringWithFormat:@"%@ %@",j==musicQueueFocus?@"▶":@" ",title],625,527-(j-first)*51,22,j==musicQueueFocus?1:0.69);
            }
        }
    } else if ([page isEqual:@"Account"]) {
        NSData *png=nil;
        @synchronized([NSObject class]) {png=[musicQRImage retain];}
        if (png.length) {
            CGImageSourceRef src=CGImageSourceCreateWithData((CFDataRef)png,NULL);
            if(src){CGImageRef qr=CGImageSourceCreateImageAtIndex(src,0,NULL);
                if(qr){CGContextSetRGBFillColor(ctx,1,1,1,1);CGContextFillRect(ctx,CGRectMake(665,312,205,205));
                    CGContextDrawImage(ctx,CGRectMake(677,324,181,181),qr);CGImageRelease(qr);}
                CFRelease(src);}
        } else MusicText(ctx,CloudTuneL(@"按确认键生成网易云音乐登录二维码", @"Press Select to create a NetEase Cloud Music login QR code"),355,426,27,1);
        [png release];
    } else if ([page isEqual:@"Recommend"]){
        NSInteger start=(selected/3)*3;
        for(NSInteger k=0;k<3;k++){
            NSInteger i=start+k;if(i<0 || i>=(NSInteger)rows.count)continue;
            NSDictionary *song=[rows objectAtIndex:i];
            CGFloat x=361+k*280;
            BOOL focus=(i==selected);
            CGContextSetRGBFillColor(ctx,focus?0.57:0.22,focus?0.14:0.20,focus?0.19:0.24,1);
            MusicRoundedRect(ctx,CGRectMake(x,320,263,218),12);CGContextFillPath(ctx);
            if(focus){
            }
            CGImageRef img=NULL;
            NSString *sid=[song objectForKey:@"id"];
            @synchronized([NSObject class]){
                NSValue *stored=[musicRecommendArts objectForKey:sid];
                if(stored)img=CGImageRetain((CGImageRef)[stored pointerValue]);
            }
            if(img){CGContextDrawImage(ctx,CGRectMake(x+54,387,154,139),img);CGImageRelease(img);}
            id title=[song objectForKey:@"name"];
            if(![title isKindOfClass:[NSString class]])title=CloudTuneL(@"未知歌曲", @"Unknown Track");
            if([title length]>13)title=[[title substringToIndex:13] stringByAppendingString:@"…"];
            MusicText(ctx,title,x+12,362,20,1);
            id names=[song objectForKey:@"artists"];
            NSString *artist=[names isKindOfClass:[NSArray class]]?[names componentsJoinedByString:@" / "]:@"";
            if(artist.length>17)artist=[[artist substringToIndex:17] stringByAppendingString:@"…"];
            MusicText(ctx,artist,x+12,337,17,0.75);
        }
        MusicText(ctx,[NSString stringWithFormat:CloudTuneL(@"%ld / %lu  左右切换歌曲", @"%ld / %lu  Left/Right to change track"),(long)(selected+1),(unsigned long)rows.count],364,544,22,0.85);
    } else if ([page isEqual:@"Playlists"] || [page isEqual:@"Tracks"] || [page isEqual:@"Recent"]) {
        NSInteger start=selected>4?selected-4:0;
        for(NSInteger i=start;i<(NSInteger)[rows count] && i<start+5;i++) {
            NSDictionary *playlist=[rows objectAtIndex:i];
            id rawName=[playlist objectForKey:@"name"];
            NSString *name=[rawName isKindOfClass:[NSString class]]?rawName:CloudTuneL(@"未知歌曲", @"Unknown Track");
            id rawArtists=[playlist objectForKey:@"artists"];
            NSMutableArray *validArtists=[NSMutableArray array];
            if([rawArtists isKindOfClass:[NSArray class]])for(id artist in rawArtists)if([artist isKindOfClass:[NSString class]])[validArtists addObject:artist];
            NSString *line=![page isEqual:@"Playlists"]?[NSString stringWithFormat:@"%@  —  %@",name,[validArtists componentsJoinedByString:@" / "]]:[NSString stringWithFormat:CloudTuneL(@"%@  (%@首)", @"%@  (%@ tracks)"),name,[playlist objectForKey:@"track_count"]?:@0];
            NSInteger row=i-start;
            if(i==selected){CGContextSetRGBFillColor(ctx,0.74,0.16,0.22,1);MusicRoundedRect(ctx,CGRectMake(365,473-row*45,828,43),8);CGContextFillPath(ctx);}
            MusicText(ctx,line,378,482-row*45,23,1);
        }
    } else if ([page isEqual:@"Results"]) {
        for (NSInteger i=0;i<(NSInteger)[rows count] && i<5;i++) {
            NSDictionary *track=[rows objectAtIndex:i];
            NSString *name=[track objectForKey:@"name"]?:@"";
            NSArray *artists=[track objectForKey:@"artists"];
            NSString *artist=[artists isKindOfClass:[NSArray class]]?[artists componentsJoinedByString:@" / "]:@"";
            NSString *line=[NSString stringWithFormat:@"%@  —  %@",name,artist];
            if(i==selected){CGContextSetRGBFillColor(ctx,0.74,0.16,0.22,1);MusicRoundedRect(ctx,CGRectMake(365,473-i*45,828,43),8);CGContextFillPath(ctx);}
            MusicText(ctx,line,378,482-i*45,23,1);
        }
    } else {
        MusicText(ctx,CloudTuneL(@"欢迎使用云律音乐", @"Welcome to CloudTune"),374,447,38,1);
        MusicText(ctx,CloudTuneL(@"Apple TV 3 原生客户端", @"Native Apple TV 3 client"),374,394,26,0.85);
        MusicText(ctx,[page isEqual:@"Account"]?CloudTuneL(@"通过 Mac Bridge 登录并访问你的音乐库", @"Sign in and access your library through the Mac Bridge"):CloudTuneL(@"这是第一版，下一版将重点更新 UI", @"This is v1. The next release will focus on a redesigned UI"),374,343,24,0.88);
    }
    if(![page isEqual:@"NowPlaying"] && musicPlayer && musicNowPlaying) {
        CGImageRef art=NULL;
        @synchronized([NSObject class]){if(musicCachedCover)art=CGImageRetain(musicCachedCover);}
        if(art){CGContextDrawImage(ctx,CGRectMake(1039,135,156,156),art);CGImageRelease(art);}
        MusicText(ctx,musicNowPlaying,349,269,24,1);
        Float64 elapsed=CMTimeGetSeconds([musicPlayer currentTime]);
        Float64 length=CMTimeGetSeconds(musicPlayer.currentItem.duration);
        if(!isfinite(elapsed)||elapsed<0)elapsed=0;
        if(!isfinite(length)||length<=0){id duration=[musicPlayingStation objectForKey:@"duration_ms"];length=[duration respondsToSelector:@selector(doubleValue)]?[duration doubleValue]/1000.0:0;}
        if(length>0) {
            CGFloat fraction=MIN(1.0,MAX(0.0,elapsed/length));
            CGContextSetRGBFillColor(ctx,0.25,0.25,0.28,1);CGContextFillRect(ctx,CGRectMake(350,219,650,9));
            CGContextSetRGBFillColor(ctx,0.84,0.16,0.22,1);CGContextFillRect(ctx,CGRectMake(350,219,650*fraction,9));
            MusicText(ctx,[NSString stringWithFormat:@"%02d:%02d / %02d:%02d",(int)elapsed/60,(int)elapsed%60,(int)length/60,(int)length%60],351,239,20,0.9);
        }
    } else if(![page isEqual:@"NowPlaying"])MusicText(ctx,CloudTuneL(@"选择歌曲后显示封面及播放进度", @"Select a track to show artwork and playback progress"),347,230,24,0.68);
    if(![page isEqual:@"NowPlaying"])MusicText(ctx,status?:CloudTuneL(@"等待连接音乐服务", @"Waiting for music service"),347,171,21,0.72);
    if(![page isEqual:@"NowPlaying"])MusicText(ctx,[page isEqual:@"Search"]?CloudTuneL(@"上下：换字符  确认：输入  右：搜索  左：删除  Menu：返回", @"Up/Down: character   Select: input   Right: search   Left: delete   Menu: back"):CloudTuneL(@"上下：选择    确认：进入    Menu：返回／退出", @"Up/Down: select   Select: enter   Menu: back/exit"),329,56,22,0.68);
    BOOL cacheHome=[page isEqual:@"Home"] && !musicPlayer && !musicNowPlaying;
    [page release];[status release];[rows release];[search release];
    CGImageRef image=CGBitmapContextCreateImage(ctx);CGContextRelease(ctx);if(!image)return nil;
    NSMutableData *data=[NSMutableData data];CGImageDestinationRef dest=CGImageDestinationCreateWithData((CFMutableDataRef)data,CFSTR("public.jpeg"),1,NULL);
    if(!dest){CGImageRelease(image);return nil;}
    NSDictionary *quality=@{(id)kCGImageDestinationLossyCompressionQuality:@(0.78)};
    CGImageDestinationAddImage(dest,image,(CFDictionaryRef)quality);BOOL ok=CGImageDestinationFinalize(dest);
    NSTimeInterval renderMs=([NSDate timeIntervalSinceReferenceDate]-renderStart)*1000.0;
    if(renderMs>120.0){FILE *f=fopen("/var/tmp/cloudtune_render_perf.log","a");if(f){fprintf(f,"render_ms=%.1f bytes=%lu\n",renderMs,(unsigned long)[data length]);fclose(f);}}
    CFRelease(dest);CGImageRelease(image);
    if(ok && cacheHome && [data length]>1000 && [data length]<500000)
        [data writeToFile:@"/var/tmp/netease_home_firstframe.jpg" atomically:YES];
    return ok?data:nil;
}

static id MusicCreateImageControl(void)
{
    NSData *data = MusicRenderImage();

    if (![data length])
        return nil;

    Class imageClass = NSClassFromString(@"ATVImage");
    Class controlClass = NSClassFromString(@"BRAsyncImageControl");

    if (!imageClass || !controlClass)
        return nil;

    SEL imageSel = NSSelectorFromString(@"imageWithData:");

    if (!MusicSignature(imageClass,
                        imageSel,
                        @encode(id),
                        @[@"@"]))
        return nil;

    id image =
        ((id(*)(id,SEL,id))objc_msgSend)(imageClass,
                                         imageSel,
                                         data);

    if (!image)
        return nil;

    id control = MusicNew(controlClass);

    if (!control)
        return nil;

    SEL cropSel = NSSelectorFromString(@"setCropAndFill:");

    if (MusicSignature(control,
                       cropSel,
                       @encode(void),
                       @[[NSString stringWithUTF8String:@encode(BOOL)]])) {

        ((void(*)(id,SEL,BOOL))objc_msgSend)(control,
                                             cropSel,
                                             NO);
    }

    SEL setImageSel = NSSelectorFromString(@"setImage:");

    if (!MusicSignature(control,
                        setImageSel,
                        @encode(void),
                        @[@"@"])) {
        [control release];
        return nil;
    }

    ((void(*)(id,SEL,id))objc_msgSend)(control,
                                       setImageSel,
                                       image);

    return [control autorelease];
}


static char MusicImageControlKey;

static id MusicMakeATVImage(void)
{
    NSData *data = MusicRenderImage();

    if (![data length])
        return nil;

    Class imageClass = NSClassFromString(@"ATVImage");

    if (!imageClass)
        return nil;

    SEL sel = NSSelectorFromString(@"imageWithData:");

    if (!MusicSignature(imageClass,
                        sel,
                        @encode(id),
                        @[@"@"]))
        return nil;

    return ((id(*)(id,SEL,id))objc_msgSend)(
        imageClass,
        sel,
        data);
}

/*
 * Shared ATV3 layout rule:
 * BackRow owns the display geometry.  Never query UIScreen and never encode
 * monitor-specific pixel compensation in an appliance.  CGRect is a struct
 * return on armv7, so use NSInvocation rather than a guessed objc_msgSend ABI.
 */
static BOOL MusicBackRowBounds(id host, CGRect *outBounds)
{
    if (!host || !outBounds) return NO;

    SEL sel = NSSelectorFromString(@"bounds");
    NSMethodSignature *sig = [host methodSignatureForSelector:sel];
    if (!sig || strcmp([sig methodReturnType], @encode(CGRect)) ||
        [sig numberOfArguments] != 2) return NO;

    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:host];
    [inv setSelector:sel];
    [inv invoke];

    CGRect bounds = CGRectZero;
    [inv getReturnValue:&bounds];
    if (bounds.size.width <= 0.0f || bounds.size.height <= 0.0f) return NO;

    *outBounds = bounds;
    return YES;
}

static BOOL MusicBackRowSetFrame(id control, CGRect frame)
{
    if (!control) return NO;

    SEL sel = NSSelectorFromString(@"setFrame:");
    NSMethodSignature *sig = [control methodSignatureForSelector:sel];
    if (!sig || strcmp([sig methodReturnType], @encode(void)) ||
        [sig numberOfArguments] != 3 ||
        strcmp([sig getArgumentTypeAtIndex:2], @encode(CGRect))) return NO;

    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:control];
    [inv setSelector:sel];
    [inv setArgument:&frame atIndex:2];
    [inv invoke];
    return YES;
}

static id MusicCreateFullscreenControl(id host)
{
    Class controlClass = NSClassFromString(@"BRImageControl");
    if (!controlClass) return nil;

    id control = MusicNew(controlClass);
    if (!control) return nil;

    CGRect frame = CGRectZero;
    if (!MusicBackRowBounds(host, &frame) ||
        !MusicBackRowSetFrame(control, frame)) {
        [control release];
        return nil;
    }

    NSLog(@"Music: BackRow-owned bounds %.0fx%.0f at %.0f,%.0f",
          frame.size.width, frame.size.height, frame.origin.x, frame.origin.y);

    return [control autorelease];
}

static void MusicInstallFullscreenControl(id self)
{
    id control =
        objc_getAssociatedObject(
            self,
            &MusicImageControlKey);

    if (control)
        return;

    control = MusicCreateFullscreenControl(self);

    if (!control)
        return;

    objc_setAssociatedObject(
        self,
        &MusicImageControlKey,
        control,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    SEL addSubviewSel =
        NSSelectorFromString(@"addSubview:");

    if ([self respondsToSelector:addSubviewSel]) {
        ((void(*)(id,SEL,id))objc_msgSend)(
            self,
            addSubviewSel,
            control);
    }
}

static void MusicUpdateFullscreenControl(id self)
{
    AppSaverSet(YES);
    MusicInstallFullscreenControl(self);

    id control =
        objc_getAssociatedObject(
            self,
            &MusicImageControlKey);

    if (!control)
        return;

    id image = MusicMakeATVImage();

    if (!image)
        return;

    SEL setImageSel =
        NSSelectorFromString(@"setImage:");

    if ([control respondsToSelector:setImageSel]) {
        ((void(*)(id,SEL,id))objc_msgSend)(
            control,
            setImageSel,
            image);
    }
}


static char MusicProgressNativeKey;
static id MusicSolidProgressImage(void){
    unsigned char pixels[4*4*4];
    for(int i=0;i<16;i++){pixels[i*4]=214;pixels[i*4+1]=41;pixels[i*4+2]=56;pixels[i*4+3]=255;}
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGContextRef context=CGBitmapContextCreate(pixels,4,4,8,16,space,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if(!context)return nil;
    CGImageRef pic=CGBitmapContextCreateImage(context);CGContextRelease(context);
    if(!pic)return nil;
    NSMutableData *data=[NSMutableData data];
    CGImageDestinationRef destination=CGImageDestinationCreateWithData((CFMutableDataRef)data,CFSTR("public.png"),1,NULL);
    if(!destination){CGImageRelease(pic);return nil;}
    CGImageDestinationAddImage(destination,pic,NULL);
    BOOL ok=CGImageDestinationFinalize(destination);CFRelease(destination);CGImageRelease(pic);
    Class imageClass=NSClassFromString(@"ATVImage");
    return ok && imageClass?((id(*)(id,SEL,id))objc_msgSend)(imageClass,NSSelectorFromString(@"imageWithData:"),data):nil;
}
static void MusicProgressFrame(id self){
    id control=objc_getAssociatedObject(self,&MusicProgressNativeKey);
    if(!control)return;
    CGRect bounds=CGRectZero;
    if(!MusicBackRowBounds(self,&bounds))return;
    double sec=musicPlayer?CMTimeGetSeconds(musicPlayer.currentTime):0;
    double length=musicPlayer?CMTimeGetSeconds(musicPlayer.currentItem.duration):0;
    if(!isfinite(length)||length<=0){id ms=[musicPlayingStation objectForKey:@"duration_ms"];length=[ms respondsToSelector:@selector(doubleValue)]?[ms doubleValue]/1000.:0;}
    BOOL visible=[musicPage isEqual:@"NowPlaying"]&&length>0&&isfinite(sec);
    double fract=visible?fmax(0.,fmin(1.,sec/length)):0.;
    CGRect frame=CGRectMake(bounds.origin.x+bounds.size.width*610./1280.,bounds.origin.y+bounds.size.height*147./720.,bounds.size.width*(540.*fract)/1280.,bounds.size.height*10./720.);
    if(!visible)frame.size.width=0;
    MusicBackRowSetFrame(control,frame);
}
static void MusicProgressInstall(id self){
    if(objc_getAssociatedObject(self,&MusicProgressNativeKey))return;
    id view=MusicNew(NSClassFromString(@"BRImageControl"));
    id img=MusicSolidProgressImage();
    if(!view||!img){[view release];return;}
    SEL set=NSSelectorFromString(@"setImage:");
    if(![view respondsToSelector:set]||![self respondsToSelector:NSSelectorFromString(@"addSubview:")]){[view release];return;}
    ((void(*)(id,SEL,id))objc_msgSend)(view,set,img);
    ((void(*)(id,SEL,id))objc_msgSend)(self,NSSelectorFromString(@"addSubview:"),view);
    objc_setAssociatedObject(self,&MusicProgressNativeKey,view,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [view release];
    MusicProgressFrame(self);
}
static char MusicTimeTextKey;
static char MusicDateTextKey;
static char MusicHourlyTextKey;
static char MusicDailyTextKey;
static char MusicHourlyLabelKey;
static char MusicDailyLabelKey;

static id MusicObjectCall(id target, NSString *name)
{
    if (!target)
        return nil;

    SEL sel = NSSelectorFromString(name);

    if (![target respondsToSelector:sel])
        return nil;

    return ((id(*)(id,SEL))objc_msgSend)(target, sel);
}

static BOOL MusicSetFrame(id control, CGRect frame)
{
    if (!control)
        return NO;

    SEL sel = NSSelectorFromString(@"setFrame:");

    if (![control respondsToSelector:sel])
        return NO;

    ((void(*)(id,SEL,CGRect))objc_msgSend)(
        control, sel, frame);

    return YES;
}

static BOOL MusicSetText(id control,
                         NSString *text,
                         id attrs)
{
    if (!control || !text)
        return NO;

    SEL sel =
        NSSelectorFromString(@"setText:withAttributes:");

    if (!MusicSignature(control,
                        sel,
                        @encode(void),
                        @[@"@", @"@"]))
        return NO;

    ((void(*)(id,SEL,id,id))objc_msgSend)(
        control,
        sel,
        text,
        attrs ?: @{});

    return YES;
}

static id MusicThemeTextAttributes(void)
{
    Class themeClass =
        NSClassFromString(@"BRThemeInfo");

    if (!themeClass)
        return @{};

    id theme =
        MusicObjectCall(themeClass, @"sharedTheme");

    if (!theme)
        return @{};

    id attrs =
        MusicObjectCall(theme,
                        @"menuTitleTextAttributes");

    static BOOL dumped = NO;

    if (!dumped) {
        dumped = YES;

        NSString *dump =
            [NSString stringWithFormat:
                @"class=%@\nattrs=%@\n",
                attrs ? NSStringFromClass([attrs class]) : @"nil",
                attrs ?: @"nil"];

        [dump writeToFile:@"/var/tmp/cloudtune_text_attrs.txt"
               atomically:YES
                 encoding:NSUTF8StringEncoding
                    error:NULL];
    }

    return attrs ?: @{};
}

static id MusicCreateTextControl(void)
{
    Class cls =
        NSClassFromString(@"BRTextControl");

    if (!cls)
        return nil;

    return [MusicNew(cls) autorelease];
}

static void MusicInstallTextControls(id self)
{
    id timeControl =
        objc_getAssociatedObject(
            self,
            &MusicTimeTextKey);

    if (timeControl)
        return;

    timeControl = MusicCreateTextControl();
    id dateControl = MusicCreateTextControl();
    id hourlyControl = MusicCreateTextControl();
    id dailyControl = MusicCreateTextControl();
    id hourlyLabel = MusicCreateTextControl();
    id dailyLabel = MusicCreateTextControl();

    if (!timeControl || !dateControl || !hourlyControl || !dailyControl || !hourlyLabel || !dailyLabel)
        return;

    /*
     * First validation layout.
     * Once BRTextControl is confirmed on-device,
     * we'll replace these temporary frames with
     * measured final cloudtune geometry.
     */
    MusicSetFrame(
        timeControl,
        CGRectMake(190.0f,
                   440.0f,
                   900.0f,
                   180.0f));

    MusicSetFrame(
        dateControl,
        CGRectMake(190.0f,
                   365.0f,
                   900.0f,
                   60.0f));

    MusicSetFrame(hourlyLabel, CGRectMake(190.0f, 320.0f, 900.0f, 30.0f));
    MusicSetFrame(hourlyControl, CGRectMake(190.0f, 275.0f, 900.0f, 48.0f));
    MusicSetFrame(dailyLabel, CGRectMake(190.0f, 225.0f, 900.0f, 30.0f));
    MusicSetFrame(dailyControl, CGRectMake(190.0f, 180.0f, 900.0f, 48.0f));

    SEL addSubviewSel =
        NSSelectorFromString(@"addSubview:");

    if (![self respondsToSelector:addSubviewSel])
        return;

    ((void(*)(id,SEL,id))objc_msgSend)(
        self,
        addSubviewSel,
        timeControl);

    ((void(*)(id,SEL,id))objc_msgSend)(
        self,
        addSubviewSel,
        dateControl);

    ((void(*)(id,SEL,id))objc_msgSend)(self, addSubviewSel, hourlyLabel);
    ((void(*)(id,SEL,id))objc_msgSend)(self, addSubviewSel, hourlyControl);
    ((void(*)(id,SEL,id))objc_msgSend)(self, addSubviewSel, dailyLabel);
    ((void(*)(id,SEL,id))objc_msgSend)(self, addSubviewSel, dailyControl);

    objc_setAssociatedObject(
        self,
        &MusicTimeTextKey,
        timeControl,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    objc_setAssociatedObject(
        self,
        &MusicDateTextKey,
        dateControl,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    objc_setAssociatedObject(self, &MusicHourlyLabelKey, hourlyLabel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &MusicHourlyTextKey, hourlyControl, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &MusicDailyLabelKey, dailyLabel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &MusicDailyTextKey, dailyControl, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void MusicUpdateTextControls(id self)
{
    MusicInstallTextControls(self);

    id timeControl =
        objc_getAssociatedObject(
            self,
            &MusicTimeTextKey);

    id dateControl =
        objc_getAssociatedObject(
            self,
            &MusicDateTextKey);

    id hourlyLabel = objc_getAssociatedObject(self, &MusicHourlyLabelKey);
    id hourlyControl = objc_getAssociatedObject(self, &MusicHourlyTextKey);
    id dailyLabel = objc_getAssociatedObject(self, &MusicDailyLabelKey);
    id dailyControl = objc_getAssociatedObject(self, &MusicDailyTextKey);

    if (!timeControl || !dateControl || !hourlyLabel || !hourlyControl || !dailyLabel || !dailyControl)
        return;

    NSDictionary *baseAttrs =
        MusicThemeTextAttributes();

    NSMutableDictionary *timeAttrs =
        [NSMutableDictionary dictionaryWithDictionary:
            baseAttrs ?: @{}];

    NSMutableDictionary *dateAttrs =
        [NSMutableDictionary dictionaryWithDictionary:
            baseAttrs ?: @{}];

    [timeAttrs setObject:@82
                  forKey:@"BRFontPointSize"];

    [dateAttrs setObject:@30
                  forKey:@"BRFontPointSize"];

    NSMutableDictionary *forecastAttrs=[NSMutableDictionary dictionaryWithDictionary:baseAttrs ?: @{}];
    [forecastAttrs setObject:@24 forKey:@"BRFontPointSize"];
    [forecastAttrs setObject:@1 forKey:@"BRTextAlignmentKey"];
    NSMutableDictionary *labelAttrs=[NSMutableDictionary dictionaryWithDictionary:baseAttrs ?: @{}];
    [labelAttrs setObject:@19 forKey:@"BRFontPointSize"];
    [labelAttrs setObject:@1 forKey:@"BRTextAlignmentKey"];

    /*
     * Keep the native BackRow alignment value discovered
     * from the real Apple TV theme.
     */
    [timeAttrs setObject:@1
                  forKey:@"BRTextAlignmentKey"];

    [dateAttrs setObject:@1
                  forKey:@"BRTextAlignmentKey"];

    MusicSetText(
        timeControl,
        MusicCurrentTime(),
        timeAttrs);

    MusicSetText(
        dateControl,
        MusicCurrentDate(),
        dateAttrs);

    MusicSetText(hourlyLabel, @"", labelAttrs);
    MusicSetText(hourlyControl, MusicHourlySummary(), forecastAttrs);
    MusicSetText(dailyLabel, @"", labelAttrs);
    MusicSetText(dailyControl, MusicDailySummary(), forecastAttrs);

    /*
     * BRTextControl owns part of its BackRow layout.
     * Give it an explicit text-layout area instead of
     * trying to reposition the glyphs with UIView frame.x.
     */
    SEL maxSizeSel =
        NSSelectorFromString(@"setMaxSize:");

    if ([timeControl respondsToSelector:maxSizeSel]) {
        ((void(*)(id,SEL,CGSize))objc_msgSend)(
            timeControl,
            maxSizeSel,
            CGSizeMake(900.0f, 180.0f));
    }

    if ([dateControl respondsToSelector:maxSizeSel]) {
        ((void(*)(id,SEL,CGSize))objc_msgSend)(
            dateControl,
            maxSizeSel,
            CGSizeMake(900.0f, 60.0f));
    }

    if ([hourlyControl respondsToSelector:maxSizeSel]) ((void(*)(id,SEL,CGSize))objc_msgSend)(hourlyControl,maxSizeSel,CGSizeMake(900.0f,55.0f));
    if ([dailyControl respondsToSelector:maxSizeSel]) ((void(*)(id,SEL,CGSize))objc_msgSend)(dailyControl,maxSizeSel,CGSizeMake(900.0f,55.0f));

    SEL verticalSel =
        NSSelectorFromString(@"setVerticallyCenterAdjustedText:");

    if ([timeControl respondsToSelector:verticalSel]) {
        ((void(*)(id,SEL,BOOL))objc_msgSend)(
            timeControl,
            verticalSel,
            YES);
    }

    if ([dateControl respondsToSelector:verticalSel]) {
        ((void(*)(id,SEL,BOOL))objc_msgSend)(
            dateControl,
            verticalSel,
            YES);
    }
}

static void MusicRefresh(id self, SEL cmd)
{
    (void)cmd;

    MusicUpdateFullscreenControl(self);
    MusicProgressInstall(self);
    MusicProgressFrame(self);

    NSString *time = MusicCurrentTime();
    NSString *date = MusicCurrentDate();

    /*
     * Keep the proven menu controller alive for 0.2.
     * The generated cloudtune image is used through the preview-control path.
     */
    NSString *title =
        [NSString stringWithFormat:@"%@     %@", time, date];

    NSArray *selectors = @[@"setListTitle:", @"setTitle:"];

    for (NSString *name in selectors) {

        SEL sel = NSSelectorFromString(name);

        if (MusicSignature(self, sel, @encode(void), @[@"@"])) {
            ((void(*)(id,SEL,id))objc_msgSend)(self, sel, title);
            break;
        }
    }

    SEL reloadSel = NSSelectorFromString(@"reload");

    SEL listSel = NSSelectorFromString(@"list");

    if (MusicSignature(self, listSel, @encode(id), @[])) {

        id list =
            ((id(*)(id,SEL))objc_msgSend)(self, listSel);

        if (list &&
            MusicSignature(list,
                           reloadSel,
                           @encode(void),
                           @[])) {

            ((void(*)(id,SEL))objc_msgSend)(list,
                                            reloadSel);
        }
    }

    NSLog(@"Music: refresh %@ %@", time, date);
}

static id MusicPreview(id self, SEL cmd, long item)
{
    (void)self;
    (void)cmd;
    (void)item;

    return MusicCreateImageControl();
}

static NSTimeInterval musicLastTimerPaint=0;
static NSTimeInterval musicLastMirrorPoll=0;
static BOOL musicMirrorActive=NO;
static void MusicMirrorStartBackground(id self,SEL cmd,id unused){
    (void)self;(void)cmd;(void)unused;
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc]init];
    MusicAPI(@"/v1/music/mirror/start");[pool drain];
}
static void MusicTimerFire(id self, SEL cmd, id timer)
{
    (void)cmd;
    (void)timer;

    NSTimeInterval now=[NSDate timeIntervalSinceReferenceDate];
    if (musicPlayer && !musicPaused) {
        AVPlayerItem *item=musicPlayer.currentItem;
        if (item.status==AVPlayerItemStatusReadyToPlay && musicPlayer.rate>0.0f) {
            musicReady=YES;musicRetryCount=0;musicStatus=CloudTuneL(@"正在播放", @"Playing");
        } else if (item.status==AVPlayerItemStatusFailed || (now-musicStartedAt>25.0 && !musicReady)) {
            if (musicRetryCount<3 && now>=musicNextRetry && musicPlayingStation) {
                NSDictionary *station=[musicPlayingStation retain];
                musicRetryCount++;musicNextRetry=now+5.0*musicRetryCount;
                MusicPlayStation(self,station);[station release];
                musicStatus=[[NSString stringWithFormat:CloudTuneL(@"连接失败，正在重试（%ld/3）", @"Connection failed, retrying (%ld/3)"),(long)musicRetryCount] copy];
            } else if (musicRetryCount>=3)musicStatus=CloudTuneL(@"播放失败，请重新选择歌曲", @"Playback failed. Choose another track");
        }
    }
    if ([musicPage isEqual:@"Account"] && musicQRToken && !musicQRBusy && now-musicLastQRCheck>=3.0) {
        musicQRBusy=YES;musicLastQRCheck=now;
        [NSThread detachNewThreadSelector:NSSelectorFromString(@"cloudtuneQRCheck:") toTarget:self withObject:nil];
    }
    if(musicMirrorActive && now-musicLastMirrorPoll>8.0){
        musicLastMirrorPoll=now;
        if([musicPage isEqual:@"Playlists"]){
            [NSThread detachNewThreadSelector:NSSelectorFromString(@"cloudtunePlaylistsLoad:") toTarget:self withObject:nil];
        }else if([musicPage isEqual:@"Tracks"]){
            [NSThread detachNewThreadSelector:NSSelectorFromString(@"cloudtuneTracksLoad:") toTarget:self withObject:nil];
        }
    }
    /* Remote actions and incoming data always repaint immediately. The 1-second
       watchdog still checks playback, but only repaints progress every 3 seconds.
       Idle/library views need no continuous full-screen image encoding. */
    MusicProgressFrame(self);
    NSTimeInterval interval=(musicPlayer && !musicPaused)?1.0:30.0;
    if(now-musicLastTimerPaint>=interval){
        musicLastTimerPaint=now;
        MusicRefresh(self,NULL);
    }
}

static void MusicBackgroundFetch(id self, SEL cmd, id unused)
{
    (void)cmd; (void)unused;
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
    NSDictionary *fresh=MusicBridgeData();
    if (fresh) MusicStoreSnapshot(fresh);
    @synchronized([NSObject class]) { cloudtuneFetchInFlight=NO; }
    if (fresh) [self performSelectorOnMainThread:NSSelectorFromString(@"cloudtuneApplyFreshData") withObject:nil waitUntilDone:NO];
    [pool drain];
}

static void MusicApplyFreshData(id self, SEL cmd)
{
    (void)cmd;
    MusicRefresh(self,NULL);
}

static void MusicEnsureTimerSelector(void);

/* ---------------------------------------------------------
   Controller lifecycle
   --------------------------------------------------------- */

static id MusicControllerInit(id self, SEL cmd)
{
    IMP superIMP = MusicControllerSuper(cmd);

    if (!superIMP)
        return nil;

    self = ((id(*)(id,SEL))superIMP)(self, cmd);

    if (!self)
        return nil;

    MusicEnsureTimerSelector();
    if (!musicStatus) musicStatus=CloudTuneL(@"云律音乐已就绪", @"CloudTune is ready");
    musicPage=@"Home";musicSelected=0;

    NSTimer *timer =
        [NSTimer scheduledTimerWithTimeInterval:0.033
                                        target:self
                                      selector:NSSelectorFromString(@"cloudtuneTimerFire:")
                                      userInfo:nil
                                       repeats:YES];

    objc_setAssociatedObject(self,
                             &cloudtuneTimerKey,
                             timer,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    NSLog(@"Music: controller initialized");

    return self;
}

static void MusicActivated(id self, SEL cmd)
{
    IMP superIMP = MusicControllerSuper(cmd);

    if (superIMP)
        ((void(*)(id,SEL))superIMP)(self, cmd);

    musicMirrorActive=YES;
    [NSThread detachNewThreadSelector:NSSelectorFromString(@"cloudtuneLoadLikes:") toTarget:self withObject:nil];
    musicLastMirrorPoll=[NSDate timeIntervalSinceReferenceDate];
    [NSThread detachNewThreadSelector:NSSelectorFromString(@"cloudtuneMirrorStart:") toTarget:self withObject:nil];
    MusicInstallFullscreenControl(self);
    NSData *cached=[NSData dataWithContentsOfFile:@"/var/tmp/netease_home_firstframe.jpg"];
    id control=objc_getAssociatedObject(self,&MusicImageControlKey);
    Class imageClass=NSClassFromString(@"ATVImage");
    SEL imageSel=NSSelectorFromString(@"imageWithData:");
    SEL setSel=NSSelectorFromString(@"setImage:");
    BOOL shown=NO;
    if([cached length]>1000 && [cached length]<500000 && control && imageClass &&
       MusicSignature(imageClass,imageSel,@encode(id),@[@"@"]) &&
       MusicSignature(control,setSel,@encode(void),@[@"@"])){
        id image=((id(*)(id,SEL,id))objc_msgSend)(imageClass,imageSel,cached);
        if(image){((void(*)(id,SEL,id))objc_msgSend)(control,setSel,image);shown=YES;}
    }
    if(shown){
        [self performSelector:NSSelectorFromString(@"cloudtuneApplyFreshData") withObject:nil afterDelay:0.12];
    } else MusicRefresh(self,NULL);
    NSLog(@"Music: activated cached-first-frame=%d",(int)shown);
}

static void MusicDeactivated(id self, SEL cmd)
{
    musicMirrorActive=NO;
    AppSaverSet(NO);
    MusicStopPlayback();
    musicRetryCount=0;
    NSLog(@"Music: deactivated");

    IMP superIMP = MusicControllerSuper(cmd);

    if (superIMP)
        ((void(*)(id,SEL))superIMP)(self, cmd);
}

static void MusicPopped(id self, SEL cmd)
{
    NSTimer *timer =
        (NSTimer *)objc_getAssociatedObject(self, &cloudtuneTimerKey);

    if (timer)
        [timer invalidate];

    objc_setAssociatedObject(self,
                             &cloudtuneTimerKey,
                             nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    NSLog(@"Music: popped");

    IMP superIMP = MusicControllerSuper(cmd);

    if (superIMP)
        ((void(*)(id,SEL))superIMP)(self, cmd);
}

static void MusicControllerDealloc(id self, SEL cmd)
{
    NSTimer *timer =
        (NSTimer *)objc_getAssociatedObject(self, &cloudtuneTimerKey);

    if (timer)
        [timer invalidate];

    objc_setAssociatedObject(self,
                             &cloudtuneTimerKey,
                             nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    IMP superIMP = MusicControllerSuper(cmd);

    if (superIMP)
        ((void(*)(id,SEL))superIMP)(self, cmd);
}

static void MusicPageLoader(id self,SEL cmd,id unused) {(void)cmd;(void)unused;MusicLoadBackground(self);}
static BOOL MusicEventInteger(id event,NSString *selector,NSInteger *out) {
    SEL sel=NSSelectorFromString(selector);
    if (![event respondsToSelector:sel])return NO;
    NSMethodSignature *sig=[event methodSignatureForSelector:sel];
    if (!sig || [sig numberOfArguments]!=2)return NO;
    NSInvocation *inv=[NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:event];[inv setSelector:sel];[inv invoke];
    int value=0;[inv getReturnValue:&value];*out=value;return YES;
}
static void MusicHistoryRecord(id self,SEL cmd,id sid){
    (void)self;(void)cmd;NSAutoreleasePool *pool=[[NSAutoreleasePool alloc]init];
    MusicAPI([@"/v1/music/recent/record?id=" stringByAppendingString:MusicEscape(sid)]);
    [pool drain];
}
static void MusicLyricsReady(id self,SEL cmd,id payload){
    (void)self;(void)cmd;
    NSString *sid=[payload objectForKey:@"id"];
    if(![sid isEqual:musicArtSongID])return;
    NSArray *lines=[payload objectForKey:@"lines"];
    if(![lines isKindOfClass:[NSArray class]])return;
    [musicLyricsLines release];musicLyricsLines=[lines copy];
    MusicRefresh(self,NULL);
}
static void MusicLyricsWorker(id self,SEL cmd,id sid){
    (void)cmd;
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc]init];
    NSDictionary *reply=MusicAPI([NSString stringWithFormat:@"/v1/music/tracks/%@/lyrics",MusicEscape(sid)]);
    NSString *lrc=[reply objectForKey:@"lrc"];
    NSMutableArray *lines=[NSMutableArray array];
    if([lrc isKindOfClass:[NSString class]]){
        for(NSString *raw in [lrc componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]){
            if(![raw hasPrefix:@"["])continue;
            NSRange close=[raw rangeOfString:@"]"];
            if(close.location==NSNotFound || close.location<4)continue;
            NSString *stamp=[raw substringWithRange:NSMakeRange(1,close.location-1)];
            NSArray *parts=[stamp componentsSeparatedByString:@":"];
            if(parts.count!=2)continue;
            double secs=[[parts objectAtIndex:0] doubleValue]*60+[[parts objectAtIndex:1] doubleValue];
            NSString *line=[[raw substringFromIndex:close.location+1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if(!line.length || secs<0)continue;
            [lines addObject:@{@"time":@(secs),@"text":line}];
        }
    }
    NSString *translated=[reply objectForKey:@"translated"];
    NSMutableDictionary *translations=[NSMutableDictionary dictionary];
    if([translated isKindOfClass:[NSString class]]){
        for(NSString *raw in [translated componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]){
            NSRange close=[raw rangeOfString:@"]"];
            if(![raw hasPrefix:@"["] || close.location==NSNotFound)continue;
            NSString *stamp=[raw substringWithRange:NSMakeRange(1,close.location-1)];
            NSArray *parts=[stamp componentsSeparatedByString:@":"];
            if(parts.count!=2)continue;
            double seconds=[[parts objectAtIndex:0] doubleValue]*60+[[parts objectAtIndex:1] doubleValue];
            NSString *text=[[raw substringFromIndex:close.location+1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if(text.length)[translations setObject:text forKey:@((NSInteger)llround(seconds*100.0))];
        }
    }
    NSMutableArray *combined=[NSMutableArray arrayWithCapacity:lines.count];
    for(NSDictionary *entry in lines){
        NSMutableDictionary *row=[NSMutableDictionary dictionaryWithDictionary:entry];
        NSString *translation=[translations objectForKey:@((NSInteger)llround([[entry objectForKey:@"time"] doubleValue]*100.0))];
        if(translation.length && ![translation isEqual:[entry objectForKey:@"text"]])[row setObject:translation forKey:@"translation"];
        [combined addObject:row];
    }
    lines=combined;
    NSDictionary *payload=@{@"id":sid,@"lines":lines};
    [self performSelectorOnMainThread:NSSelectorFromString(@"cloudtuneLyricsReady:") withObject:payload waitUntilDone:NO];
    [pool drain];
}
static void MusicLikeStateReady(id self,SEL cmd,id payload){
    (void)cmd;
    NSArray *ids=[payload objectForKey:@"ids"];
    if([ids isKindOfClass:[NSArray class]]){
        [musicLikedIDs release];musicLikedIDs=[[NSMutableSet alloc]initWithArray:ids];musicLikeLoaded=YES;
        MusicRefresh(self,NULL);
    }
}
static void MusicLoadLikes(id self,SEL cmd,id unused){
    (void)cmd;(void)unused;NSAutoreleasePool *pool=[[NSAutoreleasePool alloc]init];
    NSDictionary *result=MusicAPI(@"/v1/music/likes");
    if([[result objectForKey:@"ok"] boolValue])
        [self performSelectorOnMainThread:NSSelectorFromString(@"cloudtuneLikeStateReady:") withObject:result waitUntilDone:NO];
    [pool drain];
}
static void MusicLikeChangeReady(id self,SEL cmd,id payload){
    (void)cmd;
    if(![[payload objectForKey:@"ok"] boolValue]){
        musicStatus=CloudTuneL(@"收藏操作失败，请稍后重试", @"Like operation failed. Try again later");
    }else{
        NSString *sid=[payload objectForKey:@"id"];
        if([[payload objectForKey:@"like"] boolValue])[musicLikedIDs addObject:sid];
        else [musicLikedIDs removeObject:sid];
        musicStatus=[[payload objectForKey:@"like"] boolValue]?CloudTuneL(@"已添加喜欢", @"Added to Likes"):CloudTuneL(@"已取消喜欢", @"Removed from Likes");
    }
    MusicRefresh(self,NULL);
}
static void MusicLikeChange(id self,SEL cmd,id payload){
    (void)cmd;NSAutoreleasePool *pool=[[NSAutoreleasePool alloc]init];
    NSString *sid=[payload objectForKey:@"id"];
    BOOL like=[[payload objectForKey:@"like"] boolValue];
    NSDictionary *result=MusicAPI([NSString stringWithFormat:@"/v1/music/likes/set?id=%@&like=%@",MusicEscape(sid),like?@"true":@"false"]);
    NSDictionary *reply=@{@"ok":@([[result objectForKey:@"ok"] boolValue]),@"id":sid,@"like":@(like)};
    [self performSelectorOnMainThread:NSSelectorFromString(@"cloudtuneLikeChangeReady:") withObject:reply waitUntilDone:NO];
    [pool drain];
}
static void MusicFullscreenActivate(id self){
    if(musicShowingQueue){
        if(musicQueueFocus>=0 && musicQueueFocus<(NSInteger)musicQueue.count){musicQueueIndex=musicQueueFocus;MusicQueuePlay(self);}
        musicShowingQueue=NO;MusicRefresh(self,NULL);return;
    }
    if(musicPlayerFocus==1){musicPlayMode=(musicPlayMode+1)%3;MusicRefresh(self,NULL);return;}
    if(musicPlayerFocus==2){
        NSString *sid=[musicPlayingStation objectForKey:@"id"];
        if(![sid isKindOfClass:[NSString class]] || !sid.length)return;
        BOOL like=![musicLikedIDs containsObject:sid];
        musicStatus=CloudTuneL(@"正在同步红心…", @"Updating Likes...");
        [NSThread detachNewThreadSelector:NSSelectorFromString(@"cloudtuneLikeChange:") toTarget:self withObject:@{@"id":sid,@"like":@(like)}];
        MusicRefresh(self,NULL);return;
    }
    if(musicPlayerFocus==3){musicShowingQueue=!musicShowingQueue;musicQueueFocus=MIN(MAX(musicQueueIndex+1,0),(NSInteger)musicQueue.count-1);MusicRefresh(self,NULL);return;}
    if(musicPlayer){musicPaused=!musicPaused;if(musicPaused)[musicPlayer pause];else [musicPlayer play];MusicRefresh(self,NULL);}
}
static void MusicRecommendFocus(id controller);
static void MusicListReceived(id self,SEL cmd,id payload){
    (void)cmd;
    NSString *kind=[payload objectForKey:@"kind"];
    if(![musicPage isEqual:kind])return;
    NSArray *tracks=[payload objectForKey:@"tracks"];
    if(![tracks isKindOfClass:[NSArray class]])return;
    [musicRows release];musicRows=[[NSMutableArray alloc]initWithArray:tracks];
    musicSelected=0;musicLoading=NO;
    musicStatus=tracks.count?CloudTuneL(@"歌曲列表已就绪", @"Track list ready"):CloudTuneL(@"暂无可用歌曲", @"No available tracks");
    if([kind isEqual:@"Recommend"])MusicRecommendFocus(self);
    MusicRefresh(self,NULL);
}
static void MusicSpecialListWorker(id self,SEL cmd,id kind){
    (void)cmd;NSAutoreleasePool *pool=[[NSAutoreleasePool alloc]init];
    NSString *path=[kind isEqual:@"Recommend"]?@"/v1/music/recommend":@"/v1/music/recent";
    NSDictionary *result=MusicAPI(path);
    NSDictionary *payload=@{@"kind":kind,@"tracks":[result objectForKey:@"tracks"]?:@[]};
    [self performSelectorOnMainThread:NSSelectorFromString(@"cloudtuneListReceived:") withObject:payload waitUntilDone:NO];
    [pool drain];
}
static void MusicRecommendCoverWorker(id self,SEL cmd,id track){
    (void)cmd;NSAutoreleasePool *pool=[[NSAutoreleasePool alloc]init];
    NSString *url=[track objectForKey:@"cover_url"];
    NSString *sid=[track objectForKey:@"id"];
    NSURL *resolvedURL=CloudTuneMediaURL(url);
    if(resolvedURL){
        NSData *data=[NSData dataWithContentsOfURL:resolvedURL];
        if(data.length && data.length<1200000){
            CGImageSourceRef src=CGImageSourceCreateWithData((CFDataRef)data,NULL);
            CGImageRef art=src?CGImageSourceCreateImageAtIndex(src,0,NULL):NULL;
            if(src)CFRelease(src);
            if(art){
                @synchronized([NSObject class]){
                    if(!musicRecommendArts)musicRecommendArts=[[NSMutableDictionary alloc]init];
                    NSValue *previous=[musicRecommendArts objectForKey:sid];
                    if(previous){CGImageRef old=(CGImageRef)[previous pointerValue];if(old)CGImageRelease(old);}
                    [musicRecommendArts setObject:[NSValue valueWithPointer:art] forKey:sid];
                    if(musicRecommendArts.count>48){
                        /* Keep a small fixed number of already decoded covers. */
                        NSArray *keys=[musicRecommendArts allKeys];
                        for(NSString *key in keys){
                            if(musicRecommendArts.count<=32)break;
                            if([key isEqual:sid])continue;
                            CGImageRef old=(CGImageRef)[[musicRecommendArts objectForKey:key] pointerValue];
                            if(old)CGImageRelease(old);
                            [musicRecommendArts removeObjectForKey:key];
                        }
                    }
                }
                [self performSelectorOnMainThread:NSSelectorFromString(@"cloudtuneApplyFreshData") withObject:nil waitUntilDone:NO];
            }
        }
    }
    @synchronized([NSObject class]){[musicRecommendArtPending removeObject:sid?:@""];}
    [pool drain];
}
static void MusicRecommendFocus(id controller){
    if(![musicPage isEqual:@"Recommend"])return;
    NSInteger first=(musicSelected/3)*3;
    for(NSInteger i=first;i<first+3 && i<(NSInteger)musicRows.count;i++){
        id row=[musicRows objectAtIndex:i];NSString *sid=[row objectForKey:@"id"];
        if(![sid isKindOfClass:[NSString class]] || !sid.length)continue;
        BOOL wanted=NO;
        @synchronized([NSObject class]){
            if(!musicRecommendArtPending)musicRecommendArtPending=[[NSMutableSet alloc]init];
            if(![musicRecommendArts objectForKey:sid] && ![musicRecommendArtPending containsObject:sid]){
                [musicRecommendArtPending addObject:sid];wanted=YES;
            }
        }
        if(wanted)[NSThread detachNewThreadSelector:NSSelectorFromString(@"cloudtuneRecommendCover:") toTarget:controller withObject:row];
    }
}
static void MusicChoose(id controller);
static NSUInteger musicSingleOKToken=0;
static NSTimeInterval musicLastPairAt=0;
static void MusicShortConfirm(id self){
    if([musicPage isEqual:@"NowPlaying"])MusicFullscreenActivate(self);
    else MusicChoose(self);
    MusicRefresh(self,NULL);
}
static void MusicSingleOKFallback(id self,SEL cmd,id token){
    (void)cmd;
    if([token unsignedIntegerValue]!=musicSingleOKToken || musicOKDownAt>0)return;
    if(musicOKDownAt>0)return;
    if([NSDate timeIntervalSinceReferenceDate]-musicLastPairAt<0.7)return;
    MusicShortConfirm(self);
}
static void MusicOKReset(id self,SEL cmd,id token){
    (void)self;(void)cmd;
    if([token unsignedIntegerValue]==musicOKHoldToken){musicOKDownAt=0;musicOKHoldDone=NO;}
}
static void MusicOpenFullscreen(id self,SEL cmd,id token){
    (void)cmd;
    if([token unsignedIntegerValue]!=musicOKHoldToken || musicOKHoldDone || musicOKDownAt<=0 || !musicPlayer ||
       !([musicPage isEqual:@"Tracks"] || [musicPage isEqual:@"Recommend"] || [musicPage isEqual:@"Recent"] || [musicPage isEqual:@"Results"]))return;
    musicOKHoldDone=YES;
    musicOKDownAt=0;
    if(![musicPage isEqual:@"NowPlaying"]){musicReturnPage=musicPage;musicPage=@"NowPlaying";MusicRefresh(self,NULL);}
}
static void MusicSearchEditorFinished(id self,SEL cmd,id sender){
    (void)cmd;
    id editor=objc_getAssociatedObject(self,&musicSearchEditorKey);
    if(!editor)return;
    id inner=((id(*)(id,SEL))objc_msgSend)(editor,NSSelectorFromString(@"editor"));
    id field=((id(*)(id,SEL))objc_msgSend)(inner,NSSelectorFromString(@"textField"));
    if(sender!=field)return;
    id value=((id(*)(id,SEL))objc_msgSend)(field,NSSelectorFromString(@"stringValue"));
    NSString *query=[value isKindOfClass:[NSString class]]?[value copy]:[@"" copy];
    ((void(*)(id,SEL,id))objc_msgSend)(editor,NSSelectorFromString(@"setTextFieldDelegate:"),nil);
    id stack=((id(*)(id,SEL))objc_msgSend)(self,NSSelectorFromString(@"stack"));
    objc_setAssociatedObject(self,&musicSearchEditorKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if(stack && [stack respondsToSelector:NSSelectorFromString(@"popController")])
        ((void(*)(id,SEL))objc_msgSend)(stack,NSSelectorFromString(@"popController"));
    NSString *trim=[query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if(trim.length && trim.length<=80){
        [musicQuery release];musicQuery=[trim copy];
        musicPage=@"Results";musicSelected=0;MusicLoad(self);
    }
    [query release];MusicRefresh(self,NULL);
}
static void MusicSearchEditorChanged(id self,SEL cmd,id sender){(void)self;(void)cmd;(void)sender;}
static void MusicOpenSearchEditor(id self,SEL cmd){
    (void)cmd;
    if(objc_getAssociatedObject(self,&musicSearchEditorKey))return;
    Class cls=NSClassFromString(@"BRTextEntryController");
    SEL initSel=NSSelectorFromString(@"initWithTextEntryStyle:");
    if(!cls || !class_getInstanceMethod(cls,initSel)){
        musicStatus=CloudTuneL(@"文字输入暂不可用", @"Text input is currently unavailable");MusicRefresh(self,NULL);return;
    }
    id editor=((id(*)(id,SEL,int))objc_msgSend)([cls alloc],initSel,4);
    id stack=[self respondsToSelector:NSSelectorFromString(@"stack")]?((id(*)(id,SEL))objc_msgSend)(self,NSSelectorFromString(@"stack")):nil;
    SEL push=NSSelectorFromString(@"pushController:");
    SEL fieldDelegate=NSSelectorFromString(@"setTextFieldDelegate:");
    SEL label=NSSelectorFromString(@"setTextEntryTextFieldLabel:");
    SEL initial=NSSelectorFromString(@"setInitialTextEntryText:");
    if(!editor || !stack || ![stack respondsToSelector:push] || ![editor respondsToSelector:fieldDelegate] ||
       ![editor respondsToSelector:label] || ![editor respondsToSelector:initial]){
        [editor release];musicStatus=CloudTuneL(@"文字输入暂不可用", @"Text input is currently unavailable");MusicRefresh(self,NULL);return;
    }
    ((void(*)(id,SEL,id))objc_msgSend)(editor,label,CloudTuneL(@"搜索歌曲或歌手", @"Search tracks or artists"));
    ((void(*)(id,SEL,id))objc_msgSend)(editor,initial,@"");
    ((void(*)(id,SEL,id))objc_msgSend)(editor,fieldDelegate,self);
    objc_setAssociatedObject(self,&musicSearchEditorKey,editor,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    ((void(*)(id,SEL,id))objc_msgSend)(stack,push,editor);
    [editor release];
}
static void MusicChoose(id controller) {
    (void)controller;
    if([musicPage isEqual:@"Search"]){
        [controller performSelector:NSSelectorFromString(@"cloudtuneOpenSearchEditor")];
        return;
    }
    if([musicPage isEqual:@"Account"]){
        if (!musicQRBusy) {musicQRBusy=YES;musicStatus=CloudTuneL(@"正在生成二维码…", @"Creating login QR code...");
            [musicQRToken release];musicQRToken=nil;
            [musicQRImage release];musicQRImage=nil;
            [NSThread detachNewThreadSelector:NSSelectorFromString(@"cloudtuneQRStart:") toTarget:controller withObject:nil];
        }
        return;
    }
    if([musicPage isEqual:@"Playlists"]){
        if(musicSelected<0 || musicSelected>=(NSInteger)[musicRows count])return;
        NSDictionary *item=[musicRows objectAtIndex:musicSelected];
        NSString *identifier=[item objectForKey:@"id"];
        if (![identifier isKindOfClass:[NSString class]] || !identifier.length)return;
        [musicSavedPlaylists release];musicSavedPlaylists=[musicRows copy];
        musicSavedPlaylistIndex=musicSelected;
        [musicSelectedPlaylistID release];musicSelectedPlaylistID=[identifier copy];
        musicPage=@"Tracks";musicSelected=0;musicStatus=CloudTuneL(@"正在读取歌曲缓存…", @"Loading cached tracks...");
        NSArray *cached=[musicSafeTrackCache objectForKey:identifier];
        [musicRows release];musicRows=[[NSMutableArray alloc]initWithArray:cached?:@[]];
        [NSThread detachNewThreadSelector:NSSelectorFromString(@"cloudtuneTracksLoad:") toTarget:controller withObject:nil];return;
    }
    if([musicPage isEqual:@"Tracks"] || [musicPage isEqual:@"Recommend"] || [musicPage isEqual:@"Recent"] || [musicPage isEqual:@"Results"]){
        if(musicSelected<0 || musicSelected>=(NSInteger)[musicRows count])return;
        NSDictionary *candidate=[musicRows objectAtIndex:musicSelected];
        NSString *candidateID=[candidate objectForKey:@"id"];
        NSString *playingID=[musicPlayingStation objectForKey:@"id"];
        if(musicPlayer && [candidateID isKindOfClass:[NSString class]] && [candidateID isEqualToString:playingID]) {
            musicPaused=!musicPaused;
            if(musicPaused){[musicPlayer pause];musicStatus=CloudTuneL(@"已暂停", @"Paused");}
            else {[musicPlayer play];musicStatus=CloudTuneL(@"正在播放", @"Playing");}
            return;
        }
        [musicQueue release];musicQueue=[musicRows copy];musicQueueIndex=musicSelected;
        musicReturnPage=musicPage;
        MusicQueuePlay(controller);
        return;
    }

    if([musicPage isEqual:@"Home"]){
        NSArray *pages=@[@"Recommend",@"Search",@"Playlists",@"Recent",@"Account"];
        if(musicSelected>=0&&musicSelected<(NSInteger)[pages count])musicPage=[pages objectAtIndex:musicSelected];
        if([musicPage isEqual:@"Search"]){
            [controller performSelector:NSSelectorFromString(@"cloudtuneOpenSearchEditor")];
            return;
        }
        if([musicPage isEqual:@"Recommend"] || [musicPage isEqual:@"Recent"]){
            [musicRows release];musicRows=[[NSMutableArray alloc]init];
            musicSelected=0;musicLoading=YES;musicStatus=CloudTuneL(@"正在读取歌曲…", @"Loading tracks...");
            [NSThread detachNewThreadSelector:NSSelectorFromString(@"cloudtuneSpecialList:") toTarget:controller withObject:musicPage];return;
        }
        if([musicPage isEqual:@"Playlists"]){musicSelected=0;musicLoading=YES;musicStatus=CloudTuneL(@"正在读取我的歌单…", @"Loading my playlists...");
            if(musicSavedPlaylists.count){[musicRows release];musicRows=[[NSMutableArray alloc]initWithArray:musicSavedPlaylists];musicLoading=NO;musicStatus=CloudTuneL(@"歌单已加载", @"Playlists loaded");}[NSThread detachNewThreadSelector:NSSelectorFromString(@"cloudtunePlaylistsLoad:") toTarget:controller withObject:nil];return;}
    }
    if ([musicPage isEqual:@"Account"] && !musicQRBusy && !musicQRToken) {
        musicQRBusy=YES;musicStatus=CloudTuneL(@"正在生成登录二维码…", @"Creating login QR code...");
        [NSThread detachNewThreadSelector:NSSelectorFromString(@"cloudtuneQRStart:") toTarget:controller withObject:nil];
        return;
    }
    musicStatus=CloudTuneL(@"等待音乐服务授权与连接", @"Waiting for authorization and music service");
}
static void MusicRecordPlayed(id self,SEL cmd,id station) {(void)self;(void)cmd;NSAutoreleasePool *pool=[[NSAutoreleasePool alloc]init];MusicRecord(@"played",station);[pool drain];}
static void MusicRecordFavorite(id self,SEL cmd,id station) {(void)self;(void)cmd;NSAutoreleasePool *pool=[[NSAutoreleasePool alloc]init];MusicRecord(@"favorite",station);[pool drain];}
/* Let native BackRow own Menu/navigation. */

static BOOL MusicEvent(id self, SEL cmd, id event)
{
    NSInteger action=0,value=0,origin=0;
    if(MusicEventInteger(event,@"originator",&origin)&&MusicEventInteger(event,@"remoteAction",&action)&&MusicEventInteger(event,@"value",&value)) {
        if(action==5||action==9||action==10||action==11||action==12||action==22||action==23||action==24) MusicLogRemote(action,value,origin,"raw");
    }
    if ((action==3 || action==4) && (origin==1 || origin==3)) {
        FILE *f=fopen("/var/tmp/cloudtune_direction_diag.log","a");
        if(f){fprintf(f,"direction action=%ld value=%ld origin=%ld selected=%ld page=%s rows=%ld\n",(long)action,(long)value,(long)origin,(long)musicSelected,[musicPage UTF8String],(long)musicRows.count);fclose(f);}
    }
    // BackRow sends separate press/release events. If this appliance handles
    // a Menu press internally, its release must not reach the superclass and
    // unexpectedly pop the whole appliance after a page transition.
    if ((origin==1 || origin==3) && (action==1 || action==2)) {
        if (value==1) musicConsumedMenuPress=![musicPage isEqual:@"Home"];
        else if (value==0 && musicConsumedMenuPress) {
            musicConsumedMenuPress=NO;
            return YES;
        }
    }
    BOOL songPage=[musicPage isEqual:@"Tracks"] || [musicPage isEqual:@"Recommend"] || [musicPage isEqual:@"Recent"] || [musicPage isEqual:@"Results"] || [musicPage isEqual:@"NowPlaying"];
    if((origin==1 || origin==3) && songPage && (action==22 || action==23)){
        musicSingleOKToken++;
        musicLastPairAt=[NSDate timeIntervalSinceReferenceDate];
        if(action==22 && value==1){
            if(musicOKDownAt<=0){
                musicOKDownAt=musicLastPairAt;
                musicOKHoldDone=NO;musicOKHoldToken++;
                [self performSelector:NSSelectorFromString(@"cloudtuneOKHold:") withObject:@(musicOKHoldToken) afterDelay:0.7];
            }
        }else if(action==23){
            BOOL shortPress=musicOKDownAt>0 && !musicOKHoldDone &&
                musicLastPairAt-musicOKDownAt<0.7;
            BOOL longPress=musicOKDownAt>0 && !musicOKHoldDone && !shortPress;
            musicOKDownAt=0;musicOKHoldToken++;musicOKHoldDone=NO;
            if(longPress && musicPlayer && ![musicPage isEqual:@"NowPlaying"]){
                musicReturnPage=musicPage;musicPage=@"NowPlaying";MusicRefresh(self,NULL);
            }else if(shortPress)MusicShortConfirm(self);
        }
        return YES;
    }
    if((origin==1 || origin==3) && action==5 && songPage){
        if(value==1){
            musicSingleOKToken++;
            musicOKDownAt=[NSDate timeIntervalSinceReferenceDate];
            musicOKHoldDone=NO;
            musicOKHoldToken++;
            [self performSelector:NSSelectorFromString(@"cloudtuneOKHold:") withObject:@(musicOKHoldToken) afterDelay:0.7];
            // Legacy DMAP select may never send release. Keep its short-click fallback.
            [self performSelector:NSSelectorFromString(@"cloudtuneSingleOKFallback:") withObject:@(musicSingleOKToken) afterDelay:0.48];
        } else if(value==0 && musicOKDownAt>0){
            BOOL quick=!musicOKHoldDone && ([NSDate timeIntervalSinceReferenceDate]-musicOKDownAt<0.7);
            musicOKDownAt=0;
            musicOKHoldToken++;
            musicOKHoldDone=NO;
            musicSingleOKToken++;
            if(quick)MusicShortConfirm(self);
        }
        return YES;
    }
    if((origin==1 || origin==3) && (action==5 || action==22 || action==23) && value==0 && !songPage){return YES;}
    if((origin==1 || origin==3) && (action==9 || action==12) && value==1 && [musicQueue count]) {
        MusicQueueAdvance(self,action==9?-1:1);
        MusicRefresh(self,NULL);
        return YES;
    }
    if((origin==1 || origin==3) && action==12 && value==0)return YES;
    if((origin==1 || origin==3) && action==10 && (value==0 || value==1) && [musicQueue count]) {
        MusicNextKey(self,action,value);
        MusicRefresh(self,NULL);
        return YES;
    }
    if ((origin==1 || origin==3) && (value==1 || (value==2 && (action==3 || action==4)))) {
        if([musicPage isEqual:@"NowPlaying"] && (action==1||action==2)){
            musicPage=musicReturnPage?:@"Tracks";MusicRefresh(self,NULL);return YES;
        }
        if([musicPage isEqual:@"NowPlaying"] && action==5){MusicFullscreenActivate(self);return YES;}
        if([musicPage isEqual:@"NowPlaying"] && (action==3||action==4)){
            if(musicShowingQueue){
                NSInteger count=(NSInteger)musicQueue.count;
                if(count)musicQueueFocus=MIN(count-1,MAX(0,musicQueueFocus+(action==4?1:-1)));
            }else musicPlayerFocus=(musicPlayerFocus+(action==4?1:3))%4;
            MusicRefresh(self,NULL);return YES;
        }
        if([musicPage isEqual:@"NowPlaying"] && musicShowingQueue && action==6){musicShowingQueue=NO;MusicRefresh(self,NULL);return YES;}
        if([musicPage isEqual:@"NowPlaying"] && musicShowingQueue && action==7){
            if(musicQueueFocus>=0 && musicQueueFocus<(NSInteger)musicQueue.count){musicQueueIndex=musicQueueFocus;MusicQueuePlay(self);}
            musicShowingQueue=NO;MusicRefresh(self,NULL);return YES;
        }
        if([musicPage isEqual:@"NowPlaying"] && (action==6||action==7)){
            if(musicPlayer){
                Float64 current=CMTimeGetSeconds(musicPlayer.currentTime);
                Float64 duration=CMTimeGetSeconds(musicPlayer.currentItem.duration);
                if(!isfinite(current))current=0;
                Float64 target=MAX(0,current+(action==7?10:-10));
                if(isfinite(duration)&&duration>0)target=MIN(duration,target);
                [musicPlayer seekToTime:CMTimeMakeWithSeconds(target,600)];MusicRefresh(self,NULL);
            }
            return YES;
        }
        if((action==7 || action==6) && musicPlayer && musicPlayer.currentItem.status==AVPlayerItemStatusReadyToPlay && [musicPage isEqual:@"Tracks"]) {
            Float64 pos=CMTimeGetSeconds([musicPlayer currentTime]);
            Float64 duration=CMTimeGetSeconds(musicPlayer.currentItem.duration);
            if(!isfinite(pos))pos=0;
            Float64 newPos=MAX(0,pos+(action==7?10:-10));
            if(isfinite(duration)&&duration>0)newPos=MIN(duration,newPos);
            [musicPlayer seekToTime:CMTimeMakeWithSeconds(newPos,600)];
            musicStatus=CloudTuneL(@"已跳转播放进度", @"Playback position updated");
        }
        else if ((action==9 || action==10 || action==11 || action==12) && [musicQueue count]) {
            if(action==9||action==11)MusicQueueAdvance(self,-1);
            else MusicQueueAdvance(self,1);
        }
        else if ([musicPage isEqual:@"Recommend"] && (action==6||action==7||action==3||action==4)){
            NSInteger count=(NSInteger)musicRows.count;
            NSInteger delta=(action==6||action==3)?-1:1;
            if(count)musicSelected=MIN(count-1,MAX(0,musicSelected+delta));
            MusicRecommendFocus(self);
        }
        else if ([musicPage isEqual:@"Search"] && (action==3||action==4)) { /* Native editor owns text navigation. */ }
        else if (([musicPage isEqual:@"Results"] || [musicPage isEqual:@"Playlists"] || [musicPage isEqual:@"Tracks"]) && (action==3||action==4)) {NSInteger count=[musicRows count];if(count)musicSelected=(musicSelected+(action==3?-1:1)+count)%count;}
        else if (action==3||action==4) {
            NSInteger max=[musicPage isEqual:@"Home"]?5:0;
            if (max>0)musicSelected=(musicSelected+(action==3?-1:1)+max)%max;
        } else if (action==5)MusicChoose(self);
        else if (action==6) {
            if ([musicPage isEqual:@"Search"] && musicSearchText.length)[musicSearchText deleteCharactersInRange:NSMakeRange(musicSearchText.length-1,1)];
            else if ([musicPage isEqual:@"Tracks"]) {
                musicPage=@"Playlists";
                [musicRows release];musicRows=[[NSMutableArray alloc]initWithArray:musicSavedPlaylists?:@[]];
                musicSelected=musicSavedPlaylistIndex;musicStatus=CloudTuneL(@"歌单列表", @"Playlist list");
            } else {musicPage=@"Home";musicSelected=0;musicCountry=nil;musicTag=nil;musicQuery=nil;}
        }
        else if (action==7 && [musicPage isEqual:@"Search"] && musicSearchText.length) {
            [musicQuery release];musicQuery=[musicSearchText copy];musicPage=@"Results";musicSelected=0;MusicLoad(self);
        } else if (action==7) {musicStatus=CloudTuneL(@"该功能尚未开放", @"This feature is not available yet");}
        else if (action==1 || action==2) {
            if ([musicPage isEqual:@"Tracks"]) {
                musicPage=@"Playlists";[musicRows release];musicRows=[[NSMutableArray alloc]initWithArray:musicSavedPlaylists?:@[]];
                musicSelected=musicSavedPlaylistIndex;musicStatus=CloudTuneL(@"歌单列表", @"Playlist list");MusicRefresh(self,NULL);return YES;
            }
            if (![musicPage isEqual:@"Home"]) {
                NSString *oldPage=musicPage;
                musicPage=@"Home";
                NSArray *pages=@[@"Recommend",@"Search",@"Playlists",@"Recent",@"Account"];
                NSInteger index=[pages indexOfObject:oldPage];
                if([oldPage isEqual:@"Tracks"] || [oldPage isEqual:@"Playlists"])index=2;
                else if([oldPage isEqual:@"Results"])index=1;
                musicSelected=(index==NSNotFound)?0:index;
                MusicRefresh(self,NULL);return YES;}
            /* Root Menu must be passed to BackRow's native navigation handler.
               Never swallow it with a successful return from this override. */
            Class cls=objc_getClass("ATVCloudTuneController");
            Class base=cls?class_getSuperclass(cls):Nil;
            Method method=base?class_getInstanceMethod(base,cmd):NULL;
            return method?((BOOL(*)(id,SEL,id))method_getImplementation(method))(self,cmd,event):NO;
        }
        else return NO;
        MusicRefresh(self,NULL);return YES;
    }
    Class cls=objc_getClass("ATVCloudTuneController");Class base=cls?class_getSuperclass(cls):Nil;
    Method method=base?class_getInstanceMethod(base,cmd):NULL;
    return method?((BOOL(*)(id,SEL,id))method_getImplementation(method))(self,cmd,event):NO;
}

/* ---------------------------------------------------------
   Appliance information
   --------------------------------------------------------- */

static NSString *MusicMenuIconURLForResolution(NSInteger resolution)
{
    NSBundle *bundle = [NSBundle bundleWithIdentifier:@"org.atv3.cloudtune"];
    NSString *name = (resolution >= 1080) ? @"AppIcon@1080" : @"AppIcon";
    NSString *path = [bundle pathForResource:name ofType:@"png"];
    if (![path length])
        path = (resolution >= 1080) ? @"/Applications/Music.frappliance/AppIcon@1080.png" : @"/Applications/Music.frappliance/AppIcon.png";
    return [[NSURL fileURLWithPath:path] absoluteString];
}

static NSString *MusicMenuIconURL(void)
{
    return MusicMenuIconURLForResolution(1080);
}

static id MusicInfoMenuIconURLs(id self, SEL cmd)
{
    (void)self;
    (void)cmd;

    static unsigned long callCount = 0;
    callCount++;

    NSString *probeLine =
        [NSString stringWithFormat:
            @"menuIconURLs call=%lu time=%@\n",
            callCount, [NSDate date]];

    NSFileHandle *probe =
        [NSFileHandle fileHandleForWritingAtPath:
            @"/var/tmp/cloudtune_icon_probe.log"];

    if (!probe) {
        [[NSData data] writeToFile:
            @"/var/tmp/cloudtune_icon_probe.log"
            atomically:YES];

        probe =
            [NSFileHandle fileHandleForWritingAtPath:
                @"/var/tmp/cloudtune_icon_probe.log"];
    }

    if (probe) {
        [probe seekToEndOfFile];
        [probe writeData:
            [probeLine dataUsingEncoding:NSUTF8StringEncoding]];
        [probe closeFile];
    }

    NSString *url = MusicMenuIconURLForResolution(720);
    if (![url length]) return @{};
    return @{
        @"720": url, @"1080": url,
        [NSNumber numberWithInteger:720]: url,
        [NSNumber numberWithInteger:1080]: url
    };
}

static id MusicInfoMenuIconURLVersion(id self, SEL cmd)
{
    (void)self;
    (void)cmd;

    static unsigned long callCount = 0;
    callCount++;

    NSString *probeLine =
        [NSString stringWithFormat:
            @"menuIconURLVersion call=%lu time=%@\n",
            callCount, [NSDate date]];

    NSFileHandle *probe =
        [NSFileHandle fileHandleForWritingAtPath:
            @"/var/tmp/cloudtune_icon_probe.log"];

    if (!probe) {
        [[NSData data] writeToFile:
            @"/var/tmp/cloudtune_icon_probe.log"
            atomically:YES];

        probe =
            [NSFileHandle fileHandleForWritingAtPath:
                @"/var/tmp/cloudtune_icon_probe.log"];
    }

    if (probe) {
        [probe seekToEndOfFile];
        [probe writeData:
            [probeLine dataUsingEncoding:NSUTF8StringEncoding]];
        [probe closeFile];
    }

    NSBundle *bundle =
        [NSBundle bundleWithIdentifier:@"org.atv3.cloudtune"];

    id version =
        [bundle objectForInfoDictionaryKey:@"CFBundleVersion"];

    return [version isKindOfClass:[NSString class]] &&
           [version length] ? version : @"1";
}

static Class MusicApplianceInfoClass(void)
{
    Class existing =
        objc_getClass("CloudTuneApplianceInfo");

    if (existing)
        return existing;

    Class base =
        objc_getClass("BRApplianceInfo");

    if (!base)
        return Nil;

    Method urlsMethod =
        class_getInstanceMethod(
            base,
            NSSelectorFromString(@"menuIconURLs"));

    Method versionMethod =
        class_getInstanceMethod(
            base,
            NSSelectorFromString(@"menuIconURLVersion"));

    if (!urlsMethod || !versionMethod)
        return Nil;

    Class cls =
        objc_allocateClassPair(
            base,
            "CloudTuneApplianceInfo",
            0);

    if (!cls)
        return Nil;

    BOOL ok =
        class_addMethod(
            cls,
            NSSelectorFromString(@"menuIconURLs"),
            (IMP)MusicInfoMenuIconURLs,
            method_getTypeEncoding(urlsMethod))
        &&
        class_addMethod(
            cls,
            NSSelectorFromString(@"menuIconURLVersion"),
            (IMP)MusicInfoMenuIconURLVersion,
            method_getTypeEncoding(versionMethod));

    if (!ok) {
        objc_disposeClassPair(cls);
        return Nil;
    }

    objc_registerClassPair(cls);

    return cls;
}

static id MusicSyntheticApplianceInfo(void)
{
    Class infoClass =
        MusicApplianceInfoClass();

    if (!infoClass)
        return nil;

    id info = [infoClass alloc];

    SEL init =
        NSSelectorFromString(@"_initWithMutableDictionary:");

    if (!MusicSignature(info,
                        init,
                        @encode(id),
                        @[@"@"])) {
        [info release];
        return nil;
    }

    NSMutableDictionary *values =
        [NSMutableDictionary dictionary];

    [values setObject:@"cloudtune"
               forKey:@"FRApplianceIdentifier"];

    [values setObject:CloudTuneL(@"云律音乐", @"CloudTune")
               forKey:@"FRApplianceName"];

    [values setObject:@6
               forKey:@"FRAppliancePreferedOrderValue"];

    [values setObject:@"CloudTuneAppliance"
               forKey:@"FRPrincipalClass"];

    [values setObject:@NO
               forKey:@"FRHideIfNoCategories"];

    [values setObject:@[]
               forKey:@"FRApplianceSupportedMediaTypes"];

    [values setObject:@[]
               forKey:@"FRApplianceRequiredRemoteMediaTypes"];

    info =
        ((id(*)(id,SEL,id))objc_msgSend)(
            info,
            init,
            values);

    return [info autorelease];
}

static id MusicApplianceInit(id self,
                             SEL cmd,
                             id incoming)
{
    id info =
        incoming ?: MusicSyntheticApplianceInfo();

    IMP superIMP =
        MusicApplianceSuper(cmd);

    if (!superIMP)
        return nil;

    return ((id(*)(id,SEL,id))superIMP)(
        self,
        cmd,
        info);
}

/* ---------------------------------------------------------
   Categories / controller
   --------------------------------------------------------- */

static BOOL MusicCategoryAvailable(void)
{
    return MusicSignature(
        objc_getClass("BRApplianceCategory"),
        NSSelectorFromString(
            @"categoryWithName:identifier:preferredOrder:"),
        @encode(id),
        @[@"@", @"@", @"f"]);
}

static id MusicCategories(id self, SEL cmd)
{
    (void)self;
    (void)cmd;

    if (!MusicCategoryAvailable()) {
        NSLog(@"Music: category ABI unavailable");
        return @[];
    }

    Class cls =
        objc_getClass("BRApplianceCategory");

    SEL sel =
        NSSelectorFromString(
            @"categoryWithName:identifier:preferredOrder:");

    NSInvocation *invocation =
        [NSInvocation invocationWithMethodSignature:
            [cls methodSignatureForSelector:sel]];

    [invocation setTarget:cls];
    [invocation setSelector:sel];

    id name = CloudTuneL(@"云律音乐", @"CloudTune");
    id identifier = @"cloudtune";
    float order = 0.0f;

    [invocation setArgument:&name atIndex:2];
    [invocation setArgument:&identifier atIndex:3];
    [invocation setArgument:&order atIndex:4];

    [invocation invoke];

    id result = nil;

    [invocation getReturnValue:&result];

    return result ? @[result] : @[];
}

static id MusicControllerForIdentifier(id self,
                                       SEL cmd,
                                       id identifier,
                                       id args)
{
    (void)self;
    (void)cmd;
    (void)args;

    if (![identifier isEqual:@"cloudtune"])
        return nil;

    return [MusicNew(
        objc_getClass("ATVCloudTuneController"))
        autorelease];
}

static id MusicApplianceController(id self,
                                   SEL cmd)
{
    (void)self;
    (void)cmd;

    return [MusicNew(
        objc_getClass("ATVCloudTuneController"))
        autorelease];
}

/* ---------------------------------------------------------
   Beigelist legacy root bridge
   --------------------------------------------------------- */

static IMP cloudtuneOriginalLegacyRootController = NULL;

static BOOL MusicIsLegacyMerchant(id self)
{
    id info =
        MusicObject(self, @"info");

    id merchantID =
        MusicObject(info, @"merchantID");

    if ([merchantID isKindOfClass:[NSString class]] &&
        [merchantID isEqualToString:@"org.atv3.cloudtune"])
        return YES;

    id identifier =
        MusicObject(self, @"identifier");

    if ([identifier isKindOfClass:[NSString class]] &&
        ([identifier isEqualToString:@"org.atv3.cloudtune"] ||
         [identifier isEqualToString:
             @"merchant.org.atv3.cloudtune"]))
        return YES;

    id legacyClass =
        MusicObject(self, @"legacyApplianceClass");

    return legacyClass ==
        objc_getClass("CloudTuneAppliance");
}

static id MusicLegacyRootController(id self,
                                    SEL cmd)
{
    if (MusicIsLegacyMerchant(self)) {

        id controller =
            [MusicNew(
                objc_getClass("ATVCloudTuneController"))
                autorelease];

        if (controller)
            return controller;
    }

    return cloudtuneOriginalLegacyRootController
        ? ((id(*)(id,SEL))
            cloudtuneOriginalLegacyRootController)(
                self,
                cmd)
        : nil;
}

static BOOL MusicInstallLegacyRootBridge(void)
{
    Class cls =
        objc_getClass("BLAppLegacyMerchant");

    if (!cls)
        return NO;

    SEL sel =
        NSSelectorFromString(@"rootController");

    Method method =
        class_getInstanceMethod(cls, sel);

    if (!method)
        return NO;

    const char *encoding =
        method_getTypeEncoding(method);

    NSMethodSignature *sig =
        [NSMethodSignature
            signatureWithObjCTypes:encoding];

    if (strcmp([sig methodReturnType],
               @encode(id)) ||
        [sig numberOfArguments] != 2)
        return NO;

    IMP current =
        method_getImplementation(method);

    if (!current)
        return NO;

    if (current ==
        (IMP)MusicLegacyRootController)
        return YES;

    cloudtuneOriginalLegacyRootController =
        current;

    if (class_addMethod(
            cls,
            sel,
            (IMP)MusicLegacyRootController,
            encoding))
        return YES;

    Class super =
        class_getSuperclass(cls);

    IMP superIMP =
        super
        ? class_getMethodImplementation(
            super,
            sel)
        : NULL;

    method =
        class_getInstanceMethod(cls, sel);

    if (!method ||
        method_getImplementation(method) ==
            superIMP) {

        cloudtuneOriginalLegacyRootController =
            NULL;

        return NO;
    }

    cloudtuneOriginalLegacyRootController =
        method_setImplementation(
            method,
            (IMP)MusicLegacyRootController);

    return
        cloudtuneOriginalLegacyRootController != NULL;
}

/* ---------------------------------------------------------
   BLAppMerchantInfo icon compatibility bridge
   --------------------------------------------------------- */


/* ---------------------------------------------------------
   Dynamic Home Screen Music Icon
   188x108 canvas, centered 92x92 cloudtune face
   --------------------------------------------------------- */

static NSString *MusicDynamicIconPath(void)
{
    NSDateFormatter *formatter =
        [[[NSDateFormatter alloc] init] autorelease];

    [formatter setDateFormat:@"yyyyMMddHHmmss"];

    NSString *stamp =
        [formatter stringFromDate:[NSDate date]];

    return [NSString stringWithFormat:
        @"/var/tmp/MusicDynamicIcon-%@.png",
        stamp];
}

static BOOL MusicRenderDynamicHomeIcon(void)
{
    const size_t width = 188;
    const size_t height = 108;

    CGColorSpaceRef cs =
        CGColorSpaceCreateDeviceRGB();

    if (!cs)
        return NO;

    CGContextRef ctx =
        CGBitmapContextCreate(NULL,
                             width,
                             height,
                             8,
                             width * 4,
                             cs,
                             kCGImageAlphaPremultipliedLast |
                             kCGBitmapByteOrder32Big);

    CGColorSpaceRelease(cs);

    if (!ctx)
        return NO;

    /* Transparent 188x108 canvas. */
    CGContextClearRect(ctx, CGRectMake(0, 0, width, height));

    const CGFloat cx = 94.0f;
    const CGFloat cy = 54.0f;
    const CGFloat radius = 46.0f;

    /* Light cloudtune face. */
    CGContextSetRGBFillColor(ctx, 0.97, 0.97, 0.97, 1.0);
    CGContextFillEllipseInRect(
        ctx,
        CGRectMake(cx - radius,
                   cy - radius,
                   radius * 2.0f,
                   radius * 2.0f));

    /* Outer rim. */
    CGContextSetRGBStrokeColor(ctx, 0.12, 0.12, 0.12, 1.0);
    CGContextSetLineWidth(ctx, 1.5f);
    CGContextStrokeEllipseInRect(
        ctx,
        CGRectMake(cx - radius,
                   cy - radius,
                   radius * 2.0f,
                   radius * 2.0f));

    const CGFloat pi = 3.14159265358979323846f;

    /* 60 tick marks. */
    for (int i = 0; i < 60; i++) {

        CGFloat angle =
            ((CGFloat)i / 60.0f) *
            2.0f * pi -
            pi / 2.0f;

        BOOL major = ((i % 5) == 0);

        CGFloat outer = radius - 4.0f;
        CGFloat inner =
            outer - (major ? 8.0f : 3.5f);

        CGFloat x1 =
            cx + cosf(angle) * inner;
        CGFloat y1 =
            cy + sinf(angle) * inner;

        CGFloat x2 =
            cx + cosf(angle) * outer;
        CGFloat y2 =
            cy + sinf(angle) * outer;

        CGContextSetRGBStrokeColor(
            ctx, 0.10, 0.10, 0.10, 1.0);

        CGContextSetLineWidth(
            ctx, major ? 1.8f : 0.7f);

        CGContextMoveToPoint(ctx, x1, y1);
        CGContextAddLineToPoint(ctx, x2, y2);
        CGContextStrokePath(ctx);
    }

    NSDate *now = [NSDate date];

    NSCalendar *calendar =
        [NSCalendar currentCalendar];

    NSDateComponents *parts =
        [calendar components:
            (NSCalendarUnitHour |
             NSCalendarUnitMinute |
             NSCalendarUnitSecond)
                    fromDate:now];

    NSInteger hour = [parts hour] % 12;
    NSInteger minute = [parts minute];
    NSInteger second = [parts second];

    NSString *debug =
        [NSString stringWithFormat:
            @"date=%@ timezone=%@ hour=%ld minute=%ld second=%ld\\n",
            now,
            [[NSTimeZone localTimeZone] name],
            (long)hour,
            (long)minute,
            (long)second];

    [debug writeToFile:
        @"/var/tmp/cloudtune_dynamic_time.log"
        atomically:YES
        encoding:NSUTF8StringEncoding
        error:NULL];

    CGFloat secondAngle =
        ((CGFloat)second / 60.0f) *
        2.0f * pi -
        pi / 2.0f;

    CGFloat minuteAngle =
        (((CGFloat)minute +
          (CGFloat)second / 60.0f) /
         60.0f) *
        2.0f * pi -
        pi / 2.0f;

    CGFloat hourAngle =
        (((CGFloat)hour +
          (CGFloat)minute / 60.0f) /
         12.0f) *
        2.0f * pi -
        pi / 2.0f;

    /* Hour hand. */
    CGContextSetRGBStrokeColor(
        ctx, 0.08, 0.08, 0.08, 1.0);

    CGContextSetLineCap(ctx, kCGLineCapRound);
    CGContextSetLineWidth(ctx, 4.2f);

    CGContextMoveToPoint(ctx, cx, cy);
    CGContextAddLineToPoint(
        ctx,
        cx + cosf(hourAngle) * 21.0f,
        cy + sinf(hourAngle) * 21.0f);

    CGContextStrokePath(ctx);

    /* Minute hand. */
    CGContextSetLineWidth(ctx, 3.0f);

    CGContextMoveToPoint(ctx, cx, cy);
    CGContextAddLineToPoint(
        ctx,
        cx + cosf(minuteAngle) * 34.0f,
        cy + sinf(minuteAngle) * 34.0f);

    CGContextStrokePath(ctx);

    /* Red second hand. */
    CGContextSetRGBStrokeColor(
        ctx, 0.90, 0.05, 0.05, 1.0);

    CGContextSetLineWidth(ctx, 1.3f);

    CGContextMoveToPoint(
        ctx,
        cx - cosf(secondAngle) * 40.0f,
        cy - sinf(secondAngle) * 40.0f);

    CGContextAddLineToPoint(
        ctx,
        cx + cosf(secondAngle) * 37.0f,
        cy + sinf(secondAngle) * 37.0f);

    CGContextStrokePath(ctx);

    /* Center pin. */
    CGContextSetRGBFillColor(
        ctx, 0.90, 0.05, 0.05, 1.0);

    CGContextFillEllipseInRect(
        ctx,
        CGRectMake(cx - 2.5f,
                   cy - 2.5f,
                   5.0f,
                   5.0f));

    CGImageRef image =
        CGBitmapContextCreateImage(ctx);

    CGContextRelease(ctx);

    if (!image)
        return NO;

    NSMutableData *png =
        [NSMutableData data];

    CGImageDestinationRef dest =
        CGImageDestinationCreateWithData(
            (CFMutableDataRef)png,
            CFSTR("public.png"),
            1,
            NULL);

    if (!dest) {
        CGImageRelease(image);
        return NO;
    }

    CGImageDestinationAddImage(dest,
                               image,
                               NULL);

    BOOL ok =
        CGImageDestinationFinalize(dest);

    CFRelease(dest);
    CGImageRelease(image);

    if (!ok || ![png length])
        return NO;

    NSString *path =
        MusicDynamicIconPath();

    NSString *tmp =
        [path stringByAppendingString:@".tmp"];

    if (![png writeToFile:tmp atomically:YES])
        return NO;

    NSFileManager *fm =
        [NSFileManager defaultManager];

    [fm removeItemAtPath:path error:NULL];

    if (![fm moveItemAtPath:tmp
                     toPath:path
                      error:NULL])
        return NO;

    return YES;
}

static NSString *MusicDynamicIconURL(void)
{
    if (MusicRenderDynamicHomeIcon()) {
        return [[NSURL fileURLWithPath:
            MusicDynamicIconPath()]
            absoluteString];
    }

    /* Stable 0.1.3 icon is always the fallback. */
    return MusicMenuIconURL();
}

static NSString *MusicDynamicIconVersion(void)
{
    NSDateFormatter *formatter =
        [[[NSDateFormatter alloc] init]
            autorelease];

    [formatter setDateFormat:
        @"yyyyMMddHHmmss"];

    return [formatter stringFromDate:
        [NSDate date]];
}


static void MusicProbeMerchantCoordinatorClass(void)
{
    Class cls = objc_getClass("ATVMerchantCoordinator");
    FILE *fp = fopen("/var/tmp/cloudtune_coordinator_class.txt", "w");
    if (!fp) return;
    if (!cls) { fprintf(fp, "NOT FOUND\n"); fclose(fp); return; }
    unsigned int n = 0;
    Method *ms = class_copyMethodList(object_getClass(cls), &n);
    for (unsigned int i=0; i<n; i++)
        fprintf(fp, "%s | %s\n", sel_getName(method_getName(ms[i])), method_getTypeEncoding(ms[i]));
    if (ms) free(ms);
    fclose(fp);
}


static void MusicPulseMerchantCoordinator(void)
{
    Class cls = objc_getClass("ATVMerchantCoordinator");
    SEL sharedSel = NSSelectorFromString(@"sharedInstance");
    if (!cls || ![cls respondsToSelector:sharedSel]) return;
    id coordinator = ((id(*)(id,SEL))objc_msgSend)(cls, sharedSel);
    if (!coordinator) return;
    SEL merchantSel = NSSelectorFromString(@"merchantWithIdentifier:");
    SEL changedSel = NSSelectorFromString(@"merchantChanged:");
    if (![coordinator respondsToSelector:merchantSel] ||
        ![coordinator respondsToSelector:changedSel]) return;
    id merchant = ((id(*)(id,SEL,id))objc_msgSend)(coordinator, merchantSel, @"org.atv3.cloudtune");
    if (merchant)
        ((void(*)(id,SEL,id))objc_msgSend)(coordinator, changedSel, merchant);
}

static void MusicHomeIconTimerFire(id self, SEL cmd, NSTimer *timer)
{
    (void)self; (void)cmd; (void)timer;
    MusicPulseMerchantCoordinator();
}

static void MusicStartHomeIconTimer(void)
{
    static NSTimer *timer = nil;
    if (timer) return;
    Class timerClass = objc_getClass("CloudTuneHomeIconTimerTarget");
    if (!timerClass) {
        timerClass = objc_allocateClassPair([NSObject class], "CloudTuneHomeIconTimerTarget", 0);
        if (!timerClass) return;
        class_addMethod(timerClass, NSSelectorFromString(@"fire:"), (IMP)MusicHomeIconTimerFire, "v@:@");
        objc_registerClassPair(timerClass);
    }
    static id target = nil;
    if (!target) target = [[timerClass alloc] init];
    timer = [[NSTimer scheduledTimerWithTimeInterval:5.0
                                              target:target
                                            selector:NSSelectorFromString(@"fire:")
                                            userInfo:nil
                                             repeats:YES] retain];
}

static IMP cloudtuneSuperMerchantInfoValueForKey = NULL;

static BOOL MusicIsMerchantInfo(id self)
{
    id merchantID =
        MusicObject(self, @"merchantID");

    return
        [merchantID isKindOfClass:[NSString class]] &&
        [merchantID isEqualToString:@"org.atv3.cloudtune"];
}

static id MusicMerchantInfoValueForKey(id self, SEL cmd, id key)
{
    if ([key isKindOfClass:[NSString class]] && MusicIsMerchantInfo(self)) {
        if ([key isEqualToString:@"menu-icon-url"]) {
            NSString *url = MusicMenuIconURLForResolution(720);
            if (![url length]) return nil;
            return @{
                @"720": url, @"1080": url,
                [NSNumber numberWithInteger:720]: url,
                [NSNumber numberWithInteger:1080]: url
            };
        }
        if ([key isEqualToString:@"menu-icon-url-version"]) {
            NSBundle *bundle = [NSBundle bundleWithIdentifier:@"org.atv3.cloudtune"];
            id version = [bundle objectForInfoDictionaryKey:@"CFBundleVersion"];
            return ([version isKindOfClass:[NSString class]] && [version length]) ? version : @"1";
        }
    }
    return cloudtuneSuperMerchantInfoValueForKey
        ? ((id(*)(id,SEL,id))cloudtuneSuperMerchantInfoValueForKey)(self,cmd,key)
        : nil;
}

static BOOL MusicInstallMerchantInfoBridge(void)
{
    Class cls =
        objc_getClass("BLAppMerchantInfo");

    if (!cls)
        return NO;

    Class super =
        class_getSuperclass(cls);

    SEL sel =
        NSSelectorFromString(@"valueForKey:");

    Method inherited =
        class_getInstanceMethod(cls, sel);

    Method superMethod =
        super
        ? class_getInstanceMethod(super, sel)
        : NULL;

    if (!inherited || !superMethod)
        return NO;

    const char *encoding =
        method_getTypeEncoding(inherited);

    NSMethodSignature *sig =
        [NSMethodSignature
            signatureWithObjCTypes:encoding];

    if (strcmp([sig methodReturnType],
               @encode(id)) ||
        [sig numberOfArguments] != 3 ||
        strcmp([sig getArgumentTypeAtIndex:2],
               @encode(id)))
        return NO;

    /* Multiple third-party appliances share BLAppMerchantInfo in the same
       AppleTV process. Chain the implementation that is active right now
       instead of assuming we are the first appliance to install a bridge. */
    IMP current = method_getImplementation(inherited);
    if (!current || current == (IMP)MusicMerchantInfoValueForKey)
        return current == (IMP)MusicMerchantInfoValueForKey;

    cloudtuneSuperMerchantInfoValueForKey = current;
    method_setImplementation(inherited, (IMP)MusicMerchantInfoValueForKey);
    return YES;
}

/* ---------------------------------------------------------
   Runtime class registration
   --------------------------------------------------------- */

static BOOL MusicAddOverride(Class cls,
                             NSString *name,
                             IMP imp,
                             const char *result,
                             NSArray *args)
{
    SEL sel =
        NSSelectorFromString(name);

    Method method =
        class_getInstanceMethod(
            class_getSuperclass(cls),
            sel);

    if (!method) {
        NSLog(@"Music: missing %@", name);
        return NO;
    }

    NSMethodSignature *sig =
        [NSMethodSignature
            signatureWithObjCTypes:
                method_getTypeEncoding(method)];

    if (strcmp([sig methodReturnType],
               result) ||
        [sig numberOfArguments] !=
            [args count] + 2)
        return NO;

    for (NSUInteger i = 0;
         i < [args count];
         i++) {

        if (strcmp(
            [sig getArgumentTypeAtIndex:i + 2],
            [[args objectAtIndex:i] UTF8String]))
            return NO;
    }

    return class_addMethod(
        cls,
        sel,
        imp,
        method_getTypeEncoding(method));
}


static void MusicDumpRuntimeClass(FILE *fp, const char *name)
{
    Class cls = objc_getClass(name);

    fprintf(fp, "\n========== %s ==========\n", name);

    if (!cls) {
        fprintf(fp, "NOT FOUND\n");
        return;
    }

    Class super = class_getSuperclass(cls);

    fprintf(fp,
            "class=%s superclass=%s\n",
            class_getName(cls),
            super ? class_getName(super) : "(none)");

    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);

    fprintf(fp, "method_count=%u\n", count);

    for (unsigned int i = 0; i < count; i++) {
        SEL sel = method_getName(methods[i]);
        const char *types = method_getTypeEncoding(methods[i]);

        fprintf(fp,
                "%s | %s\n",
                sel_getName(sel),
                types ? types : "");
    }

    if (methods)
        free(methods);
}

static void MusicDumpRuntime(void)
{
    FILE *fp = fopen("/var/tmp/cloudtune_runtime.txt", "w");

    if (!fp)
        return;

    const char *classes[] = {
        "BRController",
        "BRMediaMenuController",
        "BRControl",
        "BRImageControl",
        "BRAsyncImageControl",
        "BRTextControl",
        "BRWindow",
        "BRView",
        "ATVMerchantCoordinator",
        "ATVMerchant",
        "BRMerchant",
        "BRMerchantInfo",
        "BLAppMerchantInfo",
        "BLAppLegacyMerchant"
    };

    unsigned int count =
        sizeof(classes) / sizeof(classes[0]);

    for (unsigned int i = 0; i < count; i++)
        MusicDumpRuntimeClass(fp, classes[i]);

    fflush(fp);
    fclose(fp);
}


static void MusicDumpHomeIconRuntime(void)
{
    FILE *fp =
        fopen("/var/tmp/cloudtune_home_icon_runtime.txt", "w");

    if (!fp)
        return;

    int count = objc_getClassList(NULL, 0);

    if (count <= 0) {
        fclose(fp);
        return;
    }

    Class *classes =
        (Class *)malloc(sizeof(Class) * count);

    if (!classes) {
        fclose(fp);
        return;
    }

    count = objc_getClassList(classes, count);

    const char *words[] = {
        "Icon",
        "Shelf",
        "Merchant",
        "Appliance",
        "MenuItem",
        "Image"
    };

    unsigned int wordCount =
        sizeof(words) / sizeof(words[0]);

    for (int i = 0; i < count; i++) {

        Class cls = classes[i];

        if (!cls)
            continue;

        const char *name = class_getName(cls);

        if (!name)
            continue;

        BOOL interesting = NO;

        for (unsigned int w = 0;
             w < wordCount;
             w++) {

            if (strstr(name, words[w])) {
                interesting = YES;
                break;
            }
        }

        if (!interesting)
            continue;

        fprintf(fp,
                "\n===== %s =====\n",
                name);

        Class super = class_getSuperclass(cls);

        fprintf(fp,
                "super=%s\n",
                super
                    ? class_getName(super)
                    : "(none)");

        unsigned int methodCount = 0;

        Method *methods =
            class_copyMethodList(
                cls,
                &methodCount);

        for (unsigned int m = 0;
             m < methodCount;
             m++) {

            SEL sel =
                method_getName(methods[m]);

            const char *selName =
                sel_getName(sel);

            if (!selName)
                continue;

            if (strstr(selName, "icon") ||
                strstr(selName, "Icon") ||
                strstr(selName, "image") ||
                strstr(selName, "Image") ||
                strstr(selName, "reload") ||
                strstr(selName, "Reload") ||
                strstr(selName, "refresh") ||
                strstr(selName, "Refresh") ||
                strstr(selName, "update") ||
                strstr(selName, "Update") ||
                strstr(selName, "merchant") ||
                strstr(selName, "Merchant") ||
                strstr(selName, "appliance") ||
                strstr(selName, "Appliance") ||
                strstr(selName, "control") ||
                strstr(selName, "Control")) {

                fprintf(fp,
                        "%s | %s\n",
                        selName,
                        method_getTypeEncoding(
                            methods[m]));
            }
        }

        if (methods)
            free(methods);
    }

    free(classes);

    fflush(fp);
    fclose(fp);
}


BOOL MusicRegisterBackRowClasses(void)
{
    MusicProbeMerchantCoordinatorClass();
    MusicDumpHomeIconRuntime();
    MusicDumpRuntime();
    if (objc_getClass("CloudTuneAppliance")) {
        MusicInstallLegacyRootBridge();
        return YES;
    }

    if (!MusicCategoryAvailable()) {
        NSLog(@"Music: category ABI unavailable");
        return NO;
    }

    Class applianceBase =
        objc_getClass("BRBaseAppliance");

    Class controllerBase =
        objc_getClass("BRController");

    if (!applianceBase ||
        !controllerBase) {

        NSLog(@"Music: BackRow unavailable");
        return NO;
    }

    Class appliance =
        objc_allocateClassPair(
            applianceBase,
            "CloudTuneAppliance",
            0);

    Class controller =
        objc_allocateClassPair(
            controllerBase,
            "ATVCloudTuneController",
            0);

    if (!appliance || !controller) {

        if (appliance)
            objc_disposeClassPair(appliance);

        if (controller)
            objc_disposeClassPair(controller);

        return NO;
    }

    BOOL ok =
        MusicAddOverride(
            appliance,
            @"initWithApplianceInfo:",
            (IMP)MusicApplianceInit,
            @encode(id),
            @[@"@"])
        &&
        MusicAddOverride(
            appliance,
            @"applianceCategories",
            (IMP)MusicCategories,
            @encode(id),
            @[])
        &&
        MusicAddOverride(
            appliance,
            @"controllerForIdentifier:args:",
            (IMP)MusicControllerForIdentifier,
            @encode(id),
            @[@"@", @"@"])
        &&
        MusicAddOverride(
            appliance,
            @"applianceController",
            (IMP)MusicApplianceController,
            @encode(id),
            @[])
        &&
        MusicAddOverride(
            controller,
            @"brEventAction:",
            (IMP)MusicEvent,
            @encode(BOOL),
            @[@"@"]);

    if (ok) {

        ok =
            MusicAddOverride(
                controller,
                @"init",
                (IMP)MusicControllerInit,
                @encode(id),
                @[])
            &&
            MusicAddOverride(
                controller,
                @"controlWasActivated",
                (IMP)MusicActivated,
                @encode(void),
                @[])
            &&
            MusicAddOverride(
                controller,
                @"controlWasDeactivated",
                (IMP)MusicDeactivated,
                @encode(void),
                @[])
            &&
            MusicAddOverride(
                controller,
                @"wasPopped",
                (IMP)MusicPopped,
                @encode(void),
                @[])
            &&
            MusicAddOverride(
                controller,
                @"dealloc",
                (IMP)MusicControllerDealloc,
                @encode(void),
                @[]);

    }

    if (!ok) {

        objc_disposeClassPair(appliance);
        objc_disposeClassPair(controller);

        NSLog(@"Music: incompatible BackRow ABI");

        return NO;
    }

    /* Register controller first, same proven order as Jellyfin. */
    objc_registerClassPair(controller);
    objc_registerClassPair(appliance);

    MusicInstallMerchantInfoBridge();
    MusicInstallLegacyRootBridge();

    NSLog(@"Music: BackRow classes registered");

    return YES;
}

/* Dynamic NSTimer target selector */
__attribute__((constructor))
static void MusicInstallTimerSelector(void)
{
    /* Installed after MusicController is dynamically created,
       so actual selector installation occurs lazily below. */
}

static void MusicEnsureTimerSelector(void)
{
    Class cls =
        objc_getClass("ATVCloudTuneController");

    if (!cls)
        return;
    class_addMethod(cls,NSSelectorFromString(@"cloudtuneOpenSearchEditor"),(IMP)MusicOpenSearchEditor,"v@:");
    class_addMethod(cls,NSSelectorFromString(@"textDidEndEditing:"),(IMP)MusicSearchEditorFinished,"v@:@");
    class_addMethod(cls,NSSelectorFromString(@"textDidChange:"),(IMP)MusicSearchEditorChanged,"v@:@");
    class_addMethod(cls,NSSelectorFromString(@"cloudtuneQRStart:"),(IMP)MusicQRStartSelector,"v@:@");
    class_addMethod(cls,NSSelectorFromString(@"cloudtuneQRCheck:"),(IMP)MusicQRCheckSelector,"v@:@");
    class_addMethod(cls,NSSelectorFromString(@"cloudtunePlaylistsLoad:"),(IMP)MusicPlaylistsSelector,"v@:@");
    class_addMethod(cls,NSSelectorFromString(@"cloudtuneTracksLoad:"),(IMP)MusicTracksSelector,"v@:@");
    class_addMethod(cls,NSSelectorFromString(@"cloudtuneLibraryResult:"),(IMP)MusicLibraryResult,"v@:@");
    class_addMethod(cls,NSSelectorFromString(@"cloudtuneResolveTrack:"),(IMP)MusicResolveTrackSelector,"v@:@");
    class_addMethod(cls,NSSelectorFromString(@"cloudtunePrefetchNext:"),(IMP)MusicPrefetchNextBackground,"v@:@");
    class_addMethod(cls,NSSelectorFromString(@"cloudtuneLyricsLoad:"),(IMP)MusicLyricsWorker,"v@:@");
    class_addMethod(cls,NSSelectorFromString(@"cloudtuneLyricsReady:"),(IMP)MusicLyricsReady,"v@:@");
    class_addMethod(cls,NSSelectorFromString(@"cloudtuneHistoryRecord:"),(IMP)MusicHistoryRecord,"v@:@");
    class_addMethod(cls,NSSelectorFromString(@"cloudtuneSpecialList:"),(IMP)MusicSpecialListWorker,"v@:@");
    class_addMethod(cls,NSSelectorFromString(@"cloudtuneListReceived:"),(IMP)MusicListReceived,"v@:@");
    class_addMethod(cls,NSSelectorFromString(@"cloudtuneRecommendCover:"),(IMP)MusicRecommendCoverWorker,"v@:@");
    class_addMethod(cls,NSSelectorFromString(@"cloudtuneOKHold:"),(IMP)MusicOpenFullscreen,"v@:@");
    class_addMethod(cls,NSSelectorFromString(@"cloudtuneSingleOKFallback:"),(IMP)MusicSingleOKFallback,"v@:@");
    class_addMethod(cls,NSSelectorFromString(@"cloudtuneMirrorStart:"),(IMP)MusicMirrorStartBackground,"v@:@");
    class_addMethod(cls,NSSelectorFromString(@"cloudtuneLoadLikes:"),(IMP)MusicLoadLikes,"v@:@");
    class_addMethod(cls,NSSelectorFromString(@"cloudtuneLikeStateReady:"),(IMP)MusicLikeStateReady,"v@:@");
    class_addMethod(cls,NSSelectorFromString(@"cloudtuneLikeChange:"),(IMP)MusicLikeChange,"v@:@");
    class_addMethod(cls,NSSelectorFromString(@"cloudtuneLikeChangeReady:"),(IMP)MusicLikeChangeReady,"v@:@");
    class_addMethod(cls,NSSelectorFromString(@"cloudtuneOKReset:"),(IMP)MusicOKReset,"v@:@");
    class_addMethod(cls,NSSelectorFromString(@"cloudtunePlaybackResolved:"),(IMP)MusicPlaybackResolvedSelector,"v@:@");
    class_addMethod(cls,NSSelectorFromString(@"cloudtuneAlbumArt:"),(IMP)MusicAlbumArtSelector,"v@:@");
    class_addMethod(cls,NSSelectorFromString(@"cloudtuneNextHoldTimeout:"),(IMP)MusicNextHoldTimeout,"v@:@");

    SEL sel =
        NSSelectorFromString(@"cloudtuneTimerFire:");

    if (!class_getInstanceMethod(cls, sel)) {
        class_addMethod(cls,sel,(IMP)MusicTimerFire,"v@:@");
    }
    SEL fetchSel=NSSelectorFromString(@"cloudtuneBackgroundFetch:");
    if (!class_getInstanceMethod(cls,fetchSel)) {
        class_addMethod(cls,fetchSel,(IMP)MusicBackgroundFetch,"v@:@");
    }
    class_addMethod(cls,NSSelectorFromString(@"cloudtuneLoadPage:"),(IMP)MusicPageLoader,"v@:@");
    class_addMethod(cls,NSSelectorFromString(@"cloudtuneRecordPlayed:"),(IMP)MusicRecordPlayed,"v@:@");
    class_addMethod(cls,NSSelectorFromString(@"cloudtuneRecordFavorite:"),(IMP)MusicRecordFavorite,"v@:@");
    SEL applySel=NSSelectorFromString(@"cloudtuneApplyFreshData");
    if (!class_getInstanceMethod(cls,applySel)) {
        class_addMethod(cls,applySel,(IMP)MusicApplyFreshData,"v@:");
    }
}
