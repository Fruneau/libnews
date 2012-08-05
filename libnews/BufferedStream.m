//
//  BufferedStream.m
//  libnews
//
//  Created by Florent Bruneau on 05/08/12.
//  Copyright (c) 2012 Florent Bruneau. All rights reserved.
//

#import "BufferedStream.h"

/* Input buffered stream
 */

@interface BufferedInputStream : NSInputStream <NSStreamDelegate>
@property (strong) NSMutableData *data;
@property (assign) NSUInteger     skipped;
@property (strong) NSInputStream *source;
@property (assign) NSUInteger     maxSize;
@property (assign) BOOL           inError;

- (id)initFromStream:(NSInputStream *)source maxSize:(NSUInteger)max;
@end


@implementation BufferedInputStream
- (id)initFromStream:(NSInputStream *)source maxSize:(NSUInteger)max
{
    self.source = source;
    self.source.delegate = self;
    self.maxSize = max;
    self.data    = [NSMutableData dataWithCapacity:MIN(max, 2u << 20)];
    return self;
}

- (void)forwardInvocation:(NSInvocation *)anInvocation
{
    [anInvocation invokeWithTarget:self.source];
}

- (void)fillBuffer
{
    while (self.data.length - self.skipped < self.maxSize) {
        uint8_t *bytes;
        NSUInteger remain = self.skipped;
        NSInteger  res;
        
        if (remain) {
            bytes = self.data.mutableBytes;
            memmove(bytes, bytes + remain, self.data.length - remain);
            self.skipped = 0;
        } else {
            remain = MIN(4u << 10, self.maxSize - self.data.length);
            self.data.length += remain;
            bytes = self.data.mutableBytes;
        }
        
        bytes += self.data.length - remain;
        res = [self.source read:bytes maxLength:remain];
        self.data.length -= (remain + MAX(res, 0));
        if (res <= 0) {
            if (res < 0) {
                self.inError = YES;
            }
            return;
        }
    }
}

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode
{
    assert (aStream == self.source);
    if (eventCode != NSStreamEventHasBytesAvailable) {
        if (eventCode != NSStreamEventErrorOccurred) {
            self.inError = NO;
        }
        [self.delegate stream:self handleEvent:eventCode];
        return;
    }
    
    NSUInteger oldLength = self.data.length - self.skipped;
    [self fillBuffer];
    if (oldLength == 0 && self.data.length != self.skipped) {
        [self.delegate stream:self handleEvent:eventCode];
    }
}

- (NSInteger)read:(uint8_t *)buffer maxLength:(NSUInteger)len
{
    NSRange range = {
        .location = self.skipped,
        .length   = MIN(len, self.data.length - self.skipped)
    };
    
    if (range.length == 0) {
        if (self.inError) {
            return -1;
        }
        return 0;
    }
    [self.data getBytes:buffer range:range];
    self.skipped += range.length;
    return range.length;
}

- (BOOL)getBuffer:(uint8_t **)buffer length:(NSUInteger *)len
{
    *buffer = (uint8_t *)self.data.mutableBytes + self.skipped;
    *len    = self.data.length - self.skipped;
    self.skipped = self.data.length;
    
    return YES;
}

- (BOOL)hasBytesAvailable
{
    return self.data.length > self.skipped;
}
@end


/* Output buffered stream
 */

@interface BufferedOutputStream : NSOutputStream <NSStreamDelegate>
@property (strong) NSMutableData  *data;
@property (assign) NSUInteger      skipped;
@property (strong) NSOutputStream *dest;
@property (assign) NSUInteger      maxSize;
@property (assign) BOOL            inError;

- (id)initToStream:(NSOutputStream *)dest maxSize:(NSUInteger)max;
@end

@implementation BufferedOutputStream
- (id)initToStream:(NSOutputStream *)dest maxSize:(NSUInteger)max
{
    self.dest = dest;
    self.dest.delegate = self;
    self.maxSize = max;
    self.data = [NSMutableData dataWithCapacity:MAX(max, 2u << 20)];
    return self;
}

- (void)forwardInvocation:(NSInvocation *)anInvocation
{
    [anInvocation invokeWithTarget:self.dest];
}

- (void)flushBuffer
{
    uint8_t *buffer = (uint8_t *)self.data.mutableBytes + self.skipped;
    NSUInteger len  = self.data.length - self.skipped;
    NSInteger res   = [self.dest write:buffer  maxLength:len];
    
    if (res < 0) {
        self.inError = YES;
        return;
    }
    self.skipped += res;
}

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode
{
    assert (aStream == self.dest);
    if (eventCode != NSStreamEventHasSpaceAvailable) {
        if (eventCode != NSStreamEventErrorOccurred) {
            self.inError = NO;
        }
        [self.delegate stream:self handleEvent:eventCode];
        return;
    }

    [self flushBuffer];
    if (!self.inError && self.data.length == 0) {
        if ([self.dest hasSpaceAvailable]) {
            [self.delegate stream:self handleEvent:eventCode];
        }
    }
}

- (BOOL)hasSpaceAvailable
{
    return self.data.length - self.skipped < self.maxSize
        || self.dest.hasSpaceAvailable;
}

- (NSInteger)write:(const uint8_t *)buffer maxLength:(NSUInteger)len
{
    if (self.inError) {
        return -1;
    }
    if ([self.dest hasSpaceAvailable]) {
        [self flushBuffer];
    }
    if (self.inError) {
        return -1;
    }
    
    if (self.skipped) {
        uint8_t *bytes = self.data.mutableBytes;
        memmove(bytes, bytes + self.skipped, self.data.length - self.skipped);
        self.data.length -= self.skipped;
        self.skipped = 0;
    }

    NSInteger res = [self.dest write:buffer maxLength:len];
    if (res < 0) {
        return res;
    } else if (res == (NSInteger)len) {
        return len;
    }
    buffer += res;
    len -= res;
    
    NSInteger toWrite = MIN(len, self.maxSize - self.data.length);
    [self.data appendBytes:buffer length:toWrite];
    return res + toWrite;
}
@end


/* Expose factories
 */

@implementation NSInputStream (Buffered)
+ (NSInputStream *)fromStream:(NSInputStream *)source maxSize:(NSUInteger)max
{
    return [[BufferedInputStream alloc] initFromStream:source maxSize:max];
}
@end


@implementation NSOutputStream (Buffered)
+ (NSOutputStream *)toStream:(NSOutputStream *)dest maxSize:(NSUInteger)max
{
    return [[BufferedOutputStream alloc] initToStream:dest maxSize:max];
}
@end