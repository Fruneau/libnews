//
//  NNTP.m
//  libnews
//
//  Created by Florent Bruneau on 02/08/12.
//  Copyright (c) 2012 Florent Bruneau. All rights reserved.
//

#import "NNTP.h"
#import "BufferedStream.h"


/** NSRunLoop extensions.
 *
 * Provide some extentions to NSRuntool in order to allow synchronous
 * event processing.
 */
@interface NSRunLoop (Sync)
- (void)runUntilDate:(NSDate *)date orCondition:(bool (^)(void))condition;
@end

@implementation NSRunLoop (Sync)
- (void)runUntilDate:(NSDate *)date orCondition:(bool (^)(void))condition
{
    while (!condition() && [date compare:[NSDate date]] == NSOrderedDescending)
    {
        [self runMode:NSDefaultRunLoopMode beforeDate:date];
    }
}
@end


/** The NNTP interface implements the Stream delegation
 */

@interface NNTP () <NSStreamDelegate>
@property (strong) NSInputStream  *istream;
@property (strong) NSOutputStream *ostream;

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode;
@end


@implementation NNTP
@dynamic status;

- (id)initWithHost:(NSString *)host port:(UInt32)port ssl:(BOOL)ssl
{
    CFReadStreamRef cfistream;
    CFWriteStreamRef cfostream;
    NSRunLoop *loop = [NSRunLoop currentRunLoop];

    CFStreamCreatePairWithSocketToHost(NULL, (__bridge CFStringRef)(host),
                                       port, &cfistream, &cfostream);
    self.istream = (NSInputStream *)CFBridgingRelease(cfistream);
    self.ostream = (NSOutputStream *)CFBridgingRelease(cfostream);
    self.istream = [NSInputStream fromStream:self.istream
                                     maxSize:2u << 20];
    self.ostream = [NSOutputStream toStream:self.ostream
                                    maxSize:2u << 20];
    self.istream.delegate = self;
    self.ostream.delegate = self;
    
    [self.istream scheduleInRunLoop:loop forMode:NSDefaultRunLoopMode];
    [self.ostream scheduleInRunLoop:loop forMode:NSDefaultRunLoopMode];
    
    if (ssl) {
        [self.istream setProperty:NSStreamSocketSecurityLevelNegotiatedSSL
                           forKey:NSStreamSocketSecurityLevelKey];
    }
    
    [self.istream open];
    [self.ostream open];
    return self;    
}

- (void)close
{
    [self.istream close];
    [self.ostream close];
}

- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)eventCode
{
    switch (eventCode) {
        case NSStreamEventOpenCompleted:
            NSLog(@"OpenCompleted");
            [self.delegate nntp:self handleEvent:NNTPEventConnected];
            break;
        case NSStreamEventHasSpaceAvailable:
            NSLog(@"SpaceAvailable");
            assert (stream == self.ostream);
            break;
        case NSStreamEventHasBytesAvailable:
            NSLog(@"BytesAvailable");
            assert (stream == self.istream);
            break;
        case NSStreamEventEndEncountered:
            NSLog(@"EndEncountered");
            [self.delegate nntp:self handleEvent:NNTPEventDisconnected];
            break;
        case NSStreamEventErrorOccurred:
            NSLog(@"ErrorOccured");
            [self.delegate nntp:self handleEvent:NNTPEventError];
            break;
        default:
            break;
    }
}

- (NNTPStatus)status
{
    NSStreamStatus ostatus = self.ostream.streamStatus;
    NSStreamStatus istatus = self.istream.streamStatus;
    
    if (ostatus == NSStreamStatusError || istatus == NSStreamStatusError) {
        return NNTPError;
    } else if (ostatus == NSStreamStatusOpening
               || istatus == NSStreamStatusOpening)
    {
        return NNTPConnecting;
    } else if (ostatus == NSStreamStatusNotOpen
               || ostatus == NSStreamStatusClosed
               || istatus == NSStreamStatusClosed
               || istatus == NSStreamStatusNotOpen)
    {
        return NNTPDisconnected;
    }
    return NNTPConnected;
}

+ (NNTP *)connectTo:(NSString *)host port:(UInt32)port ssl:(BOOL)ssl
{
    return [[NNTP alloc] initWithHost:host port:port ssl:ssl];
}

+ (NNTP *)connectSyncTo:(NSString *)host port:(UInt32)port ssl:(BOOL)ssl
             beforeDate:(NSDate *)date
{
    NNTP *nntp = [NNTP connectTo:host port:port ssl:ssl];
    
    [[NSRunLoop currentRunLoop] runUntilDate:date
                                 orCondition:^bool (void) {
                                     return [nntp status] == NNTPConnected;
                                 }];
    if ([nntp status] == NNTPConnected) {
        return nntp;
    }
    [nntp close];
    return nil;
}

@end
