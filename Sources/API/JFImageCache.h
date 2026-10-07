#import <Foundation/Foundation.h>
BOOL JFValidImage(NSData *data);
// Worker-confined. Dedicated directory, no URLs/headers/credentials on disk.
// TTL is absolute since insertion. Eviction is oldest insertion first.
@interface JFImageCache : NSObject {
    NSString *_directory;
    NSMutableDictionary *_memory;
    NSUInteger _memoryBytes;
    NSTimeInterval _ttl;
}
- (id)initWithDirectory:(NSString *)directory ttl:(NSTimeInterval)ttl;
- (NSData *)dataForKey:(NSString *)key;
- (void)storeData:(NSData *)data forKey:(NSString *)key;
- (void)purgeMemory;
- (void)invalidate; // Call on logout, server changes, or explicit image refresh.
@end
