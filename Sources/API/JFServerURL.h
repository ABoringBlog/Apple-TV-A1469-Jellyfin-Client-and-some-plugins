#import <Foundation/Foundation.h>
// Canonical address for configuration and API construction, without trailing '/'.
// A missing scheme defaults to HTTPS; allowing HTTP is a separate session policy.
NSString *JFNormalizeServerAddress(NSString *input, NSError **error);
