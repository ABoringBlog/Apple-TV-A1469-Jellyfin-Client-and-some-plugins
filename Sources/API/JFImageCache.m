#import "JFImageCache.h"
#import <CommonCrypto/CommonDigest.h>
#import <ImageIO/ImageIO.h>
#include <math.h>
BOOL JFValidImage(NSData *data) {
    if (!data.length || data.length>8*1024*1024) return NO;
    CGImageSourceRef source=CGImageSourceCreateWithData((CFDataRef)data,NULL);
    if (!source) return NO;
    NSDictionary *properties=(NSDictionary *)CGImageSourceCopyPropertiesAtIndex(source,0,NULL);
    double w=[properties[(id)kCGImagePropertyPixelWidth] doubleValue], h=[properties[(id)kCGImagePropertyPixelHeight] doubleValue];
    BOOL valid=w>0 && h>0 && w*h<=16*1024*1024;
    CGImageRef image=valid ? CGImageSourceCreateImageAtIndex(source,0,NULL) : NULL;
    valid=image!=NULL;
    if (image) CGImageRelease(image);
    [properties release]; CFRelease(source); return valid;
}
@implementation JFImageCache
- (id)initWithDirectory:(NSString *)directory ttl:(NSTimeInterval)ttl {
    if ((self=[super init])) {
        if (!directory.length || !isfinite(ttl) || ttl<=0) { [self release]; return nil; }
        _directory=[directory copy]; _ttl=ttl; _memory=[NSMutableDictionary new];
        if (![[NSFileManager defaultManager] createDirectoryAtPath:_directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:NULL]) { [self release]; return nil; }
    } return self;
}
- (NSString *)path:(NSString *)key {
    NSData *bytes=[key dataUsingEncoding:NSUTF8StringEncoding]; unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(bytes.bytes,(CC_LONG)bytes.length,digest); NSMutableString *name=[NSMutableString string];
    for (NSUInteger i=0;i<sizeof(digest);i++) [name appendFormat:@"%02x",digest[i]];
    return [_directory stringByAppendingPathComponent:name];
}
- (void)purgeMemory { [_memory removeAllObjects]; _memoryBytes=0; }
- (NSArray *)files { return [[NSFileManager defaultManager] contentsOfDirectoryAtPath:_directory error:NULL]; }
- (BOOL)ownedName:(NSString *)name {
    return name.length==64 && [name rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet]].location==NSNotFound;
}
- (void)invalidate {
    [self purgeMemory];
    for (NSString *name in [self files]) if ([self ownedName:name]) [[NSFileManager defaultManager] removeItemAtPath:[_directory stringByAppendingPathComponent:name] error:NULL];
}
- (void)remember:(NSData *)data path:(NSString *)path date:(NSDate *)date {
    if (_memoryBytes+data.length>8*1024*1024) [self purgeMemory];
    NSDictionary *old=_memory[path]; _memoryBytes-=[old[@"data"] length];
    _memory[path]=@{@"data":data,@"date":date}; _memoryBytes+=data.length;
}
- (NSData *)dataForKey:(NSString *)key {
    if (!key.length) return nil;
    NSString *path=[self path:key]; NSDictionary *entry=_memory[path];
    NSDictionary *attr=[[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
    NSDate *date=entry[@"date"] ?: attr[NSFileModificationDate];
    if (!date || -date.timeIntervalSinceNow>=_ttl || date.timeIntervalSinceNow>1) {
        if (entry) { _memoryBytes-=[entry[@"data"] length]; [_memory removeObjectForKey:path]; }
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL]; return nil;
    }
    if (entry) return entry[@"data"];
    if (![attr[NSFileType] isEqual:NSFileTypeRegular] || [attr[NSFileSize] unsignedLongLongValue]>8*1024*1024) return nil;
    NSData *data=[NSData dataWithContentsOfFile:path];
    if (!JFValidImage(data)) { [[NSFileManager defaultManager] removeItemAtPath:path error:NULL]; return nil; }
    [self remember:data path:path date:date]; return data;
}
- (void)storeData:(NSData *)data forKey:(NSString *)key {
    if (!key.length || !JFValidImage(data)) return;
    NSString *path=[self path:key];
    // Bound disk usage to 32 MiB; remove expired and oldest entries before writing.
    NSFileManager *fm=[NSFileManager defaultManager]; NSMutableArray *entries=[NSMutableArray array]; unsigned long long total=0;
    for (NSString *name in [self files]) {
        if (![self ownedName:name]) continue;
        NSString *p=[_directory stringByAppendingPathComponent:name]; NSDictionary *a=[fm attributesOfItemAtPath:p error:NULL];
        if ([p isEqual:path] || ![a[NSFileType] isEqual:NSFileTypeRegular] || -[a[NSFileModificationDate] timeIntervalSinceNow]>=_ttl) { [fm removeItemAtPath:p error:NULL]; continue; }
        total+=[a[NSFileSize] unsignedLongLongValue]; [entries addObject:@{@"path":p,@"date":a[NSFileModificationDate],@"size":a[NSFileSize]}];
    }
    [entries sortUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"date" ascending:YES]]];
    for (NSDictionary *e in entries) { if (total+data.length<=32*1024*1024) break; [fm removeItemAtPath:e[@"path"] error:NULL]; total-=[e[@"size"] unsignedLongLongValue]; }
    if ([data writeToFile:path options:NSDataWritingAtomic error:NULL]) [fm setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:path error:NULL];
    [self remember:data path:path date:[NSDate date]];
}
- (void)dealloc { [_directory release]; [_memory release]; [super dealloc]; }
@end
