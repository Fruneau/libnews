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
{
    NSMutableData       *_data;
    NSUInteger           _skipped;
    NSInputStream       *_source;
    NSUInteger           _maxSize;
    BOOL                 _inError;
    id<NSStreamDelegate> _delegate;
}

- (id)initFromStream:(NSInputStream *)source maxSize:(NSUInteger)max;
@end


@implementation BufferedInputStream
- (id)initFromStream:(NSInputStream *)source maxSize:(NSUInteger)max
{
    _source = source;
    _source.delegate = self;
    _maxSize = max;
    _data    = [NSMutableData dataWithCapacity:MIN(max, 2u << 20)];
    return self;
}

- (void)fillBuffer
{
    while (_data.length - _skipped < _maxSize) {
        uint8_t *bytes;
        NSUInteger remain = _skipped;
        NSInteger  res;
        
        if (remain) {
            bytes = _data.mutableBytes;
            memmove(bytes, bytes + remain, _data.length - remain);
            _skipped = 0;
        } else {
            remain = MIN(4u << 10, _maxSize - _data.length);
            _data.length += remain;
            bytes = _data.mutableBytes;
        }
        
        bytes += _data.length - remain;
        res = [_source read:bytes maxLength:remain];
        _data.length -= (remain - MAX(res, 0));
        if (res <= (NSInteger)remain || ![_source hasBytesAvailable]) {
            if (res < 0) {
                _inError = YES;
            }
            return;
        }
    }
}

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode
{
    assert (aStream == _source || aStream == self);
    if (aStream == self) {
        return;
    }
    if (eventCode != NSStreamEventHasBytesAvailable) {
        if (eventCode != NSStreamEventErrorOccurred) {
            _inError = NO;
        }
        [_delegate stream:self handleEvent:eventCode];
        return;
    }
    
    NSUInteger oldLength = _data.length - _skipped;
    [self fillBuffer];
    if (oldLength == 0 && _data.length != _skipped) {
        [_delegate stream:self handleEvent:eventCode];
    }
}

- (NSInteger)read:(uint8_t *)buffer maxLength:(NSUInteger)len
{
    NSRange range = {
        .location = _skipped,
        .length   = MIN(len, _data.length - _skipped)
    };
    
    if (range.length == 0) {
        if (_inError) {
            return -1;
        }
        return 0;
    }
    [_data getBytes:buffer range:range];
    _skipped += range.length;
    return range.length;
}

- (BOOL)getBuffer:(uint8_t **)buffer length:(NSUInteger *)len
{
    *buffer = (uint8_t *)_data.mutableBytes + _skipped;
    *len    = _data.length - _skipped;
    _skipped = _data.length;
    
    return YES;
}

- (NSString *)readLine:(NSUInteger)maxLength
{
    const char *data = (const char *)_data.mutableBytes + _skipped;
    NSUInteger  len  = MIN(maxLength, _data.length - _skipped);
    const char *b = data;
    
    if (len == 0) {
        return nil;
    }
    
    do {
        b = memchr(b, '\r', len - (b - data) - 1);
        if (b) {
            b++;
        }
    } while (b && *b != '\n');
    
    if (!b) {
        return nil;
    }

    NSString *res = [NSString alloc];
    res = [res initWithBytes:data
                      length:(b - data) - 1
                    encoding:NSUTF8StringEncoding];
    _skipped += (b - data) + 1;
    return res;
}

- (BOOL)hasBytesAvailable
{
    return _data.length > _skipped;
}

- (void)open
{
    [_source open];
}

- (void)close
{
    [_source close];
    _skipped = 0;
    _data.length = 0;
}

- (void)setDelegate:(id<NSStreamDelegate>)delegate
{
    if (delegate == nil) {
        _delegate = self;
    } else {
        _delegate = delegate;
    }
}

- (id<NSStreamDelegate>)delegate
{
    return _delegate;
}

- (id)propertyForKey:(NSString *)key
{
    return [_source propertyForKey:key];
}

- (BOOL)setProperty:(id)property forKey:(NSString *)key
{
    return [_source setProperty:property forKey:key];
}

- (NSStreamStatus)streamStatus
{
    return [_source streamStatus];
}

- (NSError *)streamError
{
    return [_source streamError];
}

- (void)scheduleInRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode
{
    [_source scheduleInRunLoop:aRunLoop forMode:mode];
}

- (void)removeFromRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode
{
    [_source removeFromRunLoop:aRunLoop forMode:mode];
}
@end


/* Output buffered stream
 */

@interface BufferedOutputStream : NSOutputStream <NSStreamDelegate>
{
    id<NSStreamDelegate> _delegate;
    NSMutableData       *_data;
    NSUInteger           _skipped;
    NSOutputStream      *_dest;
    NSUInteger           _maxSize;
    BOOL                 _inError;
}

- (id)initToStream:(NSOutputStream *)dest maxSize:(NSUInteger)max;
@end

@implementation BufferedOutputStream
- (id)initToStream:(NSOutputStream *)dest maxSize:(NSUInteger)max
{
    _dest = dest;
    _dest.delegate = self;
    _maxSize = max;
    _data = [NSMutableData dataWithCapacity:MAX(max, 2u << 20)];
    return self;
}

- (void)flushBuffer
{
    uint8_t *buffer = (uint8_t *)_data.mutableBytes + _skipped;
    NSUInteger len  = _data.length - _skipped;
    NSInteger res   = [_dest write:buffer  maxLength:len];
    
    if (res < 0) {
        _inError = YES;
        return;
    }
    _skipped += res;
}

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode
{
    assert (aStream == _dest || aStream == self);
    if (aStream == self) {
        return;
    }
    if (eventCode != NSStreamEventHasSpaceAvailable) {
        if (eventCode != NSStreamEventErrorOccurred) {
            _inError = NO;
        }
        [_delegate stream:self handleEvent:eventCode];
        return;
    }

    [self flushBuffer];
    if (!_inError && _data.length == 0) {
        if ([_dest hasSpaceAvailable]) {
            [_delegate stream:self handleEvent:eventCode];
        }
    }
}

- (BOOL)hasSpaceAvailable
{
    if (_inError) {
        return NO;
    }
    return _data.length - _skipped < _maxSize
        || _dest.hasSpaceAvailable;
}

- (BOOL)hasCapacityAvailable:(NSUInteger)length
{
    return !_inError && _data.length - _skipped >= length;
}

- (NSInteger)write:(const uint8_t *)buffer maxLength:(NSUInteger)len
{
    if (_inError) {
        return -1;
    }
    if ([_dest hasSpaceAvailable]) {
        [self flushBuffer];
    }
    if (_inError) {
        return -1;
    }
    
    if (_skipped) {
        uint8_t *bytes = _data.mutableBytes;
        memmove(bytes, bytes + _skipped, _data.length - _skipped);
        _data.length -= _skipped;
        _skipped = 0;
    }

    NSInteger res = [_dest write:buffer maxLength:len];
    if (res < 0) {
        return res;
    } else if (res == (NSInteger)len) {
        return len;
    }
    buffer += res;
    len -= res;
    
    NSInteger toWrite = MIN(len, _maxSize - _data.length);
    [_data appendBytes:buffer length:toWrite];
    return res + toWrite;
}

- (void)open
{
    [_dest open];
}

- (void)close
{
    [_dest close];
    _skipped = 0;
    _data.length = 0;
}

- (void)setDelegate:(id<NSStreamDelegate>)delegate
{
    if (delegate == nil) {
        _delegate = self;
    } else {
        _delegate = delegate;
    }
}

- (id<NSStreamDelegate>)delegate
{
    return _delegate;
}

- (id)propertyForKey:(NSString *)key
{
    return [_dest propertyForKey:key];
}

- (BOOL)setProperty:(id)property forKey:(NSString *)key
{
    return [_dest setProperty:property forKey:key];
}

- (NSStreamStatus)streamStatus
{
    return [_dest streamStatus];
}

- (NSError *)streamError
{
    return [_dest streamError];
}

- (void)scheduleInRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode
{
    [_dest scheduleInRunLoop:aRunLoop forMode:mode];
}

- (void)removeFromRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode
{
    [_dest removeFromRunLoop:aRunLoop forMode:mode];
}
@end


/* Expose factories
 */

@implementation NSInputStream (Buffered)
+ (NSInputStream *)fromStream:(NSInputStream *)source maxSize:(NSUInteger)max
{
    return [[BufferedInputStream alloc] initFromStream:source maxSize:max];
}

- (NSString *)readLine:(NSUInteger)maxLength
{
    [NSException raise:@"abstract" format:@"you should implement the method"];
    return nil;
}

- (NSString *)readLine
{
    return [self readLine:1000];
}
@end


@implementation NSOutputStream (Buffered)
+ (NSOutputStream *)toStream:(NSOutputStream *)dest maxSize:(NSUInteger)max
{
    return [[BufferedOutputStream alloc] initToStream:dest maxSize:max];
}

- (BOOL)hasCapacityAvailable:(NSUInteger)length
{
    if (length == 1 && [self hasSpaceAvailable]) {
        return YES;
    }
    return NO;
}
@end
