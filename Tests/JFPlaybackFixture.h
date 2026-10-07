#import <Foundation/Foundation.h>
@interface JFPlaybackFixture : NSURLProtocol
+ (void)setMode:(NSString *)mode;
+ (NSArray *)reports;
+ (NSDictionary *)lastBody;
@end
