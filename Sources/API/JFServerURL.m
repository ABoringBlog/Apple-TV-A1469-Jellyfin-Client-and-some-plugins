#import "JFServerURL.h"
#include <arpa/inet.h>
static NSString *InvalidAddress(NSError **error) {
    if (error) *error=[NSError errorWithDomain:@"JellyfinConfiguration" code:1
        userInfo:@{NSLocalizedDescriptionKey:@"Enter a valid HTTP or HTTPS server address, without credentials, query or fragment"}];
    return nil;
}
NSString *JFNormalizeServerAddress(NSString *input, NSError **error) {
    if (error) *error=nil;
    if (![input isKindOfClass:[NSString class]]) return InvalidAddress(error);
    NSString *text=[input stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!text.length || text.length>2048 || [text rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].location!=NSNotFound ||
        [text rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location!=NSNotFound || [text containsString:@"\\"]) return InvalidAddress(error);
    if (![text containsString:@"://"]) {
        if ([text.lowercaseString hasPrefix:@"http:"] || [text.lowercaseString hasPrefix:@"https:"]) return InvalidAddress(error);
        text=[@"https://" stringByAppendingString:text];
    }
    // Do not let newer Foundation silently repair malformed percent escapes.
    NSCharacterSet *hex=[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"];
    for (NSUInteger i=0;i<text.length;i++) if ([text characterAtIndex:i]=='%') {
        if (i+2>=text.length || ![hex characterIsMember:[text characterAtIndex:i+1]] || ![hex characterIsMember:[text characterAtIndex:i+2]]) return InvalidAddress(error);
        i+=2;
    }
    NSURLComponents *parts=[NSURLComponents componentsWithString:text];
    NSString *scheme=parts.scheme.lowercaseString, *host=parts.host.lowercaseString;
    if (![@[@"http",@"https"] containsObject:scheme] || !host.length || parts.user!=nil || parts.password!=nil || parts.query!=nil || parts.fragment!=nil)
        return InvalidAddress(error);
    // Validate the authority as written; an empty/non-numeric port must not vanish.
    NSString *authority=[[text componentsSeparatedByString:@"://"][1] componentsSeparatedByString:@"/"][0];
    NSString *portText=nil;
    if ([authority hasPrefix:@"["]) {
        NSRange end=[authority rangeOfString:@"]"];
        if (end.location==NSNotFound) return InvalidAddress(error);
        NSString *suffix=[authority substringFromIndex:end.location+1];
        if (suffix.length) { if (![suffix hasPrefix:@":"]) return InvalidAddress(error); portText=[suffix substringFromIndex:1]; }
    } else {
        NSArray *pieces=[authority componentsSeparatedByString:@":"];
        if (pieces.count>2) return InvalidAddress(error);
        if (pieces.count==2) portText=pieces[1];
    }
    if (portText && (!portText.length || [portText rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location!=NSNotFound ||
        portText.longLongValue<1 || portText.longLongValue>65535)) return InvalidAddress(error);
    NSString *plainHost=host;
    if ([host hasPrefix:@"["] && [host hasSuffix:@"]"]) plainHost=[host substringWithRange:NSMakeRange(1,host.length-2)];
    if ([plainHost containsString:@":"]) {
        struct in6_addr address;
        if (inet_pton(AF_INET6,plainHost.UTF8String,&address)!=1) return InvalidAddress(error);
    } else {
        NSCharacterSet *allowed=[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789.-"];
        if ([host rangeOfCharacterFromSet:allowed.invertedSet].location!=NSNotFound || host.length>253) return InvalidAddress(error);
        NSString *name=[host hasSuffix:@"."] ? [host substringToIndex:host.length-1] : host;
        for (NSString *label in [name componentsSeparatedByString:@"."])
            if (!label.length || label.length>63 || [label hasPrefix:@"-"] || [label hasSuffix:@"-"]) return InvalidAddress(error);
        if ([host rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789."] invertedSet]].location==NSNotFound) {
            struct in_addr address;
            if (inet_pton(AF_INET,host.UTF8String,&address)!=1) return InvalidAddress(error);
        }
    }
    NSString *path=parts.percentEncodedPath ?: @"";
    for (NSString *segment in [path componentsSeparatedByString:@"/"]) {
        NSString *decoded=[segment stringByRemovingPercentEncoding];
        if (!decoded || [decoded isEqual:@"."] || [decoded isEqual:@".."] || [decoded containsString:@"/"] || [decoded containsString:@"\\"] ||
            [decoded rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location!=NSNotFound) return InvalidAddress(error);
    }
    while ([path hasSuffix:@"/"]) path=[path substringToIndex:path.length-1];
    parts.scheme=scheme; parts.host=host; parts.percentEncodedPath=path;
    if (portText) parts.port=@(portText.integerValue);
    if (([scheme isEqual:@"https"] && parts.port.integerValue==443) || ([scheme isEqual:@"http"] && parts.port.integerValue==80)) parts.port=nil;
    return parts.URL ? parts.string : InvalidAddress(error);
}
