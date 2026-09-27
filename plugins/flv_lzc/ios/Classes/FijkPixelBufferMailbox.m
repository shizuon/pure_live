#import "FijkPixelBufferMailbox.h"

@implementation FijkPixelBufferMailbox {
    NSLock *_lock;
    CVPixelBufferRef _pending;
    BOOL _closed;
}
- (instancetype)init {
    if ((self = [super init])) {
        _lock = [[NSLock alloc] init];
        _pending = NULL;
        _closed = NO;
    }
    return self;
}
- (BOOL)publish:(CVPixelBufferRef)buffer {
    if (buffer == NULL) return NO;
    [_lock lock];
    if (_closed) {
        [_lock unlock];
        return NO;
    }
    // Even if the address is the same, this is a new ownership transfer.
    CVPixelBufferRetain(buffer);
    CVPixelBufferRef previous = _pending;
    _pending = buffer;
    [_lock unlock];
    if (previous != NULL) CVPixelBufferRelease(previous);
    return YES;
}
- (CVPixelBufferRef)copyPixelBuffer {
    [_lock lock];
    CVPixelBufferRef buffer = _pending;
    _pending = NULL;
    [_lock unlock];
    return buffer; // Transfer the mailbox's +1 ownership to Flutter.
}
- (void)close {
    [_lock lock];
    _closed = YES;
    CVPixelBufferRef buffer = _pending;
    _pending = NULL;
    [_lock unlock];
    if (buffer != NULL) CVPixelBufferRelease(buffer);
}
- (void)dealloc {
    [self close];
}
@end
