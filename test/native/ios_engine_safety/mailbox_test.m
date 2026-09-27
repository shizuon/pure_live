#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>
#import "FijkPixelBufferMailbox.h"

int main(void) {
    @autoreleasepool {
        FijkPixelBufferMailbox *mailbox = [[FijkPixelBufferMailbox alloc] init];
        NSCAssert(![mailbox publish:NULL], @"Null decoder frames are ignored");
        CVPixelBufferRef frame = NULL;
        CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault, 16, 16,
            kCVPixelFormatType_32BGRA, NULL, &frame);
        NSCAssert(status == kCVReturnSuccess, @"Fixture allocation");
        // Decoder may publish the same native address repeatedly. Each
        // Flutter consumption owns a distinct retain, even for that address.
        for (int i = 0; i < 1000; i++) {
            NSCAssert([mailbox publish:frame], @"Publish");
            CVPixelBufferRef owned = [mailbox copyPixelBuffer];
            NSCAssert(owned == frame, @"Ownership transfer");
            NSCAssert(CVPixelBufferGetWidth(owned) == 16, @"Still alive");
            CVPixelBufferRelease(owned);
        }
        dispatch_apply(1000, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^(size_t index) {
            if (index % 2 == 0) [mailbox publish:frame];
            else {
                CVPixelBufferRef owned = [mailbox copyPixelBuffer];
                if (owned) CVPixelBufferRelease(owned);
            }
        });
        [mailbox close];
        NSCAssert([mailbox copyPixelBuffer] == NULL, @"Close drains pending frame");
        NSCAssert(![mailbox publish:frame], @"Close prevents late decoder publish");
        [mailbox close];
        CVPixelBufferRelease(frame);
        puts("iOS IJK pixel-buffer ownership: passed");
    }
    return 0;
}
