#import <Foundation/Foundation.h>
#import "API/JFClient.h"
#import "Input/JFRemote.h"
typedef NS_ENUM(NSInteger, JFPage) { JFLoginPage, JFLibrariesPage, JFLibraryPage, JFMediaPage, JFSeasonsPage, JFEpisodesPage, JFDetailPage };
// Serial worker-thread model. UI must marshal snapshots to its own thread.
// Independent navigation only; no BackRow view or player is attached.
@interface JFBrowser : NSObject {
    JFClient *_client;
    NSArray *_libraries, *_media;
    NSMutableArray *_history;
    NSDictionary *_detail;
    NSString *_seriesID, *_parentID, *_mediaType;
    NSUInteger _offset;
    BOOL _hasMore;
    NSInteger _mediaIndex;
    NSInteger _index;
    JFPage _page;
}
@property(nonatomic, readonly) JFPage page;
@property(nonatomic, readonly) NSInteger index;
@property(nonatomic, readonly) NSArray *libraries;
@property(nonatomic, readonly) NSDictionary *selectedLibrary;
- (id)initWithClient:(JFClient *)client;
- (BOOL)login:(NSString *)username password:(NSString *)password error:(NSError **)error;
- (BOOL)authenticateToken:(NSString *)token error:(NSError **)error;
- (NSString *)sessionToken;
- (BOOL)refresh:(NSError **)error;
- (BOOL)handleEvent:(NSDictionary *)event;
@property(nonatomic, readonly) NSArray *media;
@property(nonatomic, readonly) NSDictionary *detail;
@property(nonatomic, readonly) NSInteger mediaIndex;
@property(nonatomic, readonly) BOOL hasMore;
- (BOOL)openLibraryWithType:(NSString *)type error:(NSError **)error;
- (BOOL)openMediaAtIndex:(NSUInteger)index error:(NSError **)error;
- (BOOL)loadMore:(NSError **)error;
- (BOOL)goBack;
// Copy of model state suitable for main-thread delivery via JFWorker.
- (NSDictionary *)snapshot;
- (BOOL)signOut:(NSError **)error;
- (void)logout;
@end
