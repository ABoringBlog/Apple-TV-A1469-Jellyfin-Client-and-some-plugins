#import "JFPlaybackModel.h"
#include <math.h>
BOOL JFMediaID(id value) {
    return [value isKindOfClass:[NSString class]] && [value length]>0 && [value length]<=256 &&
        [value rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"] invertedSet]].location==NSNotFound;
}
BOOL JFTicks(id value) {
    return [value isKindOfClass:[NSNumber class]] && CFGetTypeID((CFTypeRef)value)!=CFBooleanGetTypeID() &&
        isfinite([value doubleValue]) && [value doubleValue]>=0 && [value doubleValue]<=9007199254740991.0 &&
        [value doubleValue]==(double)[value longLongValue];
}
static NSDictionary *Condition(NSString *property, NSString *value) {
    return @{@"Condition":@"LessThanEqual",@"Property":property,@"Value":value,@"IsRequired":@YES};
}
NSDictionary *JFProvisionalDeviceProfile(void) {
    return @{@"Name":@"Apple TV 3 — PROVISIONAL, no device playback evidence", @"MaxStreamingBitrate":@10000000,
        @"DirectPlayProfiles":@[@{@"Container":@"mp4,m4v,mov",@"Type":@"Video",@"VideoCodec":@"h264",@"AudioCodec":@"aac"}],
        @"TranscodingProfiles":@[@{@"Container":@"ts",@"Type":@"Video",@"Protocol":@"hls",@"VideoCodec":@"h264",@"AudioCodec":@"aac",@"MaxAudioChannels":@"2",@"Context":@"Streaming"}],
        @"CodecProfiles":@[@{@"Type":@"Video",@"Codec":@"h264",@"Conditions":@[Condition(@"Width",@"1920"),Condition(@"Height",@"1080"),Condition(@"VideoBitDepth",@"8"),Condition(@"VideoFramerate",@"30"),Condition(@"VideoLevel",@"40"),@{@"Condition":@"Equals",@"Property":@"VideoRangeType",@"Value":@"SDR",@"IsRequired":@YES}]},
            @{@"Type":@"VideoAudio",@"Codec":@"aac",@"Conditions":@[Condition(@"AudioChannels",@"2"),Condition(@"AudioSampleRate",@"48000")]}],
        // No subtitle renderer or AC3 capability is claimed.
        @"SubtitleProfiles":@[]};
}
NSDictionary *JFPlaybackBody(long long start, NSInteger subtitle) {
    if (start<0 || start>9007199254740991LL || subtitle < -1 || subtitle>10000) return nil;
    return @{@"DeviceProfile":JFProvisionalDeviceProfile(),@"StartTimeTicks":@(start),@"SubtitleStreamIndex":@(subtitle),
        @"MaxStreamingBitrate":@10000000,@"MaxAudioChannels":@2,@"EnableDirectPlay":@YES,@"EnableDirectStream":@YES,
        @"EnableTranscoding":@YES,@"AllowVideoStreamCopy":@YES,@"AllowAudioStreamCopy":@YES,@"AutoOpenLiveStream":@NO};
}
static BOOL Bounded(id n, double maximum) { return [n isKindOfClass:[NSNumber class]] && isfinite([n doubleValue]) && [n doubleValue]>0 && [n doubleValue]<=maximum; }
static BOOL Flag(id v) { return v && CFGetTypeID((CFTypeRef)v)==CFBooleanGetTypeID() && [v boolValue]; }
static BOOL ContainerOnlyRemuxReason(id value) {
    if (![value isKindOfClass:[NSString class]] || ![value length]) return NO;
    NSURLComponents *parts=[NSURLComponents componentsWithString:value];
    NSString *reason=nil;
    for (NSURLQueryItem *item in parts.queryItems)
        if ([item.name.lowercaseString isEqual:@"transcodereasons"]) { reason=item.value; break; }
    if (!reason.length) return NO;
    BOOL found=NO;
    for (NSString *raw in [reason componentsSeparatedByString:@","]) {
        NSString *part=[raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!part.length) continue;
        found=YES;
        if (![part isEqual:@"ContainerNotSupported"]) return NO;
    }
    return found;
}
static id Invalid(NSError **error, NSInteger code) { if (error) *error=[NSError errorWithDomain:@"JFPlayback" code:code userInfo:nil]; return nil; }
NSDictionary *JFPlaybackPlan(NSDictionary *info, NSString *item, long long start, NSError **error) {
    return JFPlaybackPlanForSource(info,item,start,nil,error);
}
NSDictionary *JFPlaybackPlanForSource(NSDictionary *info, NSString *item, long long start, NSString *preferredSource, NSError **error) {
    if (error) *error=nil;
    if ((preferredSource && !JFMediaID(preferredSource)) || !JFMediaID(item) || !JFTicks(@(start)) || ![info isKindOfClass:[NSDictionary class]] || !JFMediaID(info[@"PlaySessionId"]) ||
        ![info[@"MediaSources"] isKindOfClass:[NSArray class]] || ![info[@"MediaSources"] count] || [info[@"MediaSources"] count]>64 || (info[@"ErrorCode"] && info[@"ErrorCode"]!=[NSNull null])) return Invalid(error,2001);
    NSMutableArray *candidates=[NSMutableArray array];
    for (id value in info[@"MediaSources"]) {
        if (![value isKindOfClass:[NSDictionary class]]) return Invalid(error,2001);
        NSDictionary *s=value;
        if (!JFMediaID(s[@"Id"]) || !JFTicks(s[@"RunTimeTicks"]) || [s[@"RunTimeTicks"] longLongValue]==0 ||
            ![s[@"MediaStreams"] isKindOfClass:[NSArray class]] || [s[@"MediaStreams"] count]>256) return Invalid(error,2001);
        if (preferredSource && ![s[@"Id"] isEqual:preferredSource]) continue;
        if (start>[s[@"RunTimeTicks"] longLongValue]) continue;
        if (Flag(s[@"RequiresOpening"]) || Flag(s[@"IsInfiniteStream"])) continue;
        NSDictionary *video=nil,*audio=nil; NSUInteger videos=0,audios=0;
        for (id stream in s[@"MediaStreams"]) {
            if (![stream isKindOfClass:[NSDictionary class]] || ![stream[@"Type"] isKindOfClass:[NSString class]]) return Invalid(error,2001);
            if ([stream[@"Type"] isEqual:@"Video"]) { video=stream; videos++; }
            if ([stream[@"Type"] isEqual:@"Audio"]) { audio=stream; audios++; }
        }
        // Ambiguous audio/video tracks are negotiated through the server, never assumed direct.
        BOOL v=videos==1 && [video[@"Codec"] isEqual:@"h264"] && Bounded(video[@"Width"],1920) && Bounded(video[@"Height"],1080) &&
            Bounded(video[@"BitDepth"],8) && Bounded(video[@"RealFrameRate"],30) && Bounded(video[@"Level"],40) &&
            [video[@"VideoRange"] isEqual:@"SDR"];
        BOOL a=audios==1 && [audio[@"Codec"] isEqual:@"aac"] && Bounded(audio[@"Channels"],2) && Bounded(audio[@"SampleRate"],48000);
        BOOL container=[@[@"mp4",@"m4v",@"mov"] containsObject:s[@"Container"] ?: @""];
        NSString *method=nil;
        BOOL hasHLS=[s[@"TranscodingUrl"] isKindOfClass:[NSString class]] && [s[@"TranscodingUrl"] length];
        // Jellyfin currently disables video SupportsDirectStream in normal PlaybackInfo responses.
        // Recover only the safe remux case the server itself identified as container-only:
        // codecs already satisfy the ATV3 profile and no subtitle/codec/bitrate reason is present.
        BOOL safeContainerRemux=v && a && Flag(s[@"SupportsTranscoding"]) && hasHLS && ContainerOnlyRemuxReason(s[@"TranscodingUrl"]);
        if (v && a && container && Flag(s[@"SupportsDirectPlay"])) method=@"DirectPlay";
        else if (v && a && hasHLS && (Flag(s[@"SupportsDirectStream"]) || safeContainerRemux)) method=@"DirectStream";
        else if (Flag(s[@"SupportsTranscoding"]) && hasHLS) method=@"Transcode";
        if (!method) continue;
        [candidates addObject:@{@"itemID":item,@"sourceID":s[@"Id"],@"playSessionID":info[@"PlaySessionId"],@"method":method,
            @"durationTicks":s[@"RunTimeTicks"],@"startTicks":@(start),@"provisional":@YES,@"source":s}];
    }
    for (NSString *method in @[@"DirectPlay",@"DirectStream",@"Transcode"])
        for (NSDictionary *plan in candidates) if ([plan[@"method"] isEqual:method]) return plan;
    return Invalid(error,2002);
}
NSDictionary *JFPlaybackReport(NSDictionary *plan, long long ticks, BOOL paused) {
    if (!JFMediaID(plan[@"itemID"]) || !JFMediaID(plan[@"sourceID"]) || !JFMediaID(plan[@"playSessionID"]) ||
        !JFTicks(@(ticks)) || ticks>[plan[@"durationTicks"] longLongValue]) return nil;
    NSMutableDictionary *report=[NSMutableDictionary dictionaryWithDictionary:@{@"ItemId":plan[@"itemID"],@"MediaSourceId":plan[@"sourceID"],@"PlaySessionId":plan[@"playSessionID"],
        @"PositionTicks":@(ticks),@"IsPaused":@(paused),@"CanSeek":@YES,@"PlayMethod":plan[@"method"]}];
    if (JFTicks(plan[@"audioStreamIndex"]) && [plan[@"audioStreamIndex"] integerValue]<=10000) report[@"AudioStreamIndex"]=plan[@"audioStreamIndex"];
    if (JFTicks(plan[@"subtitleStreamIndex"]) && [plan[@"subtitleStreamIndex"] integerValue]<=10000) report[@"SubtitleStreamIndex"]=plan[@"subtitleStreamIndex"];
    return report;
}
