#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>

/// One owned reference per pending frame. Flutter consumes that reference;
/// decoder-owned frames are never borrowed across threads.
@interface FijkPixelBufferMailbox : NSObject
- (BOOL)publish:(CVPixelBufferRef _Nullable)buffer;
- (CVPixelBufferRef _Nullable)copyPixelBuffer CF_RETURNS_RETAINED;
- (void)close;
@end
