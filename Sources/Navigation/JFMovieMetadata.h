#import <Foundation/Foundation.h>

// Normalizes optional movie-list metadata. Required Id/Name/Type validation
// remains in JFClient. Invalid optional values are ignored, not fatal.
NSDictionary *JFMovieMetadata(NSDictionary *item);
NSString *JFMovieRowTitle(NSDictionary *item);
