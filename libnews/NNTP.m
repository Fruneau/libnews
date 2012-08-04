//
//  NNTP.m
//  libnews
//
//  Created by Florent Bruneau on 02/08/12.
//  Copyright (c) 2012 Florent Bruneau. All rights reserved.
//

#import "NNTP.h"


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

@interface NNTP (Private) < NSStreamDelegate >
- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode;
@end


@implementation NNTP
@dynamic status;
@synthesize delegate;

- (id)initWithHost:(NSString *)host port:(UInt32)port ssl:(BOOL)ssl
{
    CFReadStreamRef cfistream;
    CFWriteStreamRef cfostream;
    NSRunLoop *loop = [NSRunLoop currentRunLoop];

    CFStreamCreatePairWithSocketToHost(NULL, (__bridge CFStringRef)(host),
                                       port, &cfistream, &cfostream);
    istream = (NSInputStream *)CFBridgingRelease(cfistream);
    ostream = (NSOutputStream *)CFBridgingRelease(cfostream);

    istreamStatus = NNTPDisconnected;
    ostreamStatus = NNTPDisconnected;
    [istream setDelegate:self];
    [ostream setDelegate:self];
    
    [istream scheduleInRunLoop:loop forMode:NSDefaultRunLoopMode];
    [ostream scheduleInRunLoop:loop forMode:NSDefaultRunLoopMode];
    
    if (ssl) {
        [istream setProperty:NSStreamSocketSecurityLevelNegotiatedSSL
                      forKey:NSStreamSocketSecurityLevelKey];
    }
    
    [istream open];
    [ostream open];
    return self;    
}

- (NNTPStatus)status
{
    if (istreamStatus == NNTPError || ostreamStatus == NNTPError) {
        return NNTPError;
    } else if (istreamStatus == NNTPConnected
               && ostreamStatus == NNTPConnected)
    {
        return NNTPConnected;
    }
    return NNTPDisconnected;
}

- (void)close
{
    [istream close];
    [ostream close];
}

- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)eventCode
{
    NNTPStatus prevStatus = [self status];
    
    switch (eventCode) {
        case NSStreamEventOpenCompleted:
            NSLog(@"OpenCompleted");
            if (stream == istream) {
                istreamStatus = NNTPConnected;
            } else {
                ostreamStatus = NNTPConnected;
            }
            if (prevStatus != NNTPConnected
                && [self status] == NNTPConnected)
            {
                [delegate nntp:self handleEvent:NNTPEventConnected];
            }
            break;
        case NSStreamEventHasSpaceAvailable:
            NSLog(@"SpaceAvailable");
            assert (stream == ostream);
            break;
        case NSStreamEventHasBytesAvailable:
            NSLog(@"BytesAvailable");
            assert (stream == istream);
            break;
        case NSStreamEventEndEncountered:
            NSLog(@"EndEncountered");
            if (stream == istream) {
                istreamStatus = NNTPDisconnected;
            } else {
                ostreamStatus = NNTPDisconnected;
            }
            if (prevStatus != NNTPDisconnected
                && [self status] == NNTPDisconnected)
            {
                [delegate nntp:self handleEvent:NNTPEventDisconnected];
            }
            break;
        case NSStreamEventErrorOccurred:
            NSLog(@"ErrorOccured");
            if (stream == istream) {
                istreamStatus = NNTPError;
            } else {
                ostreamStatus = NNTPError;
            }
            if (prevStatus != NNTPError && [self status] == NNTPError) {
                [delegate nntp:self handleEvent:NNTPEventError];
            }
            break;
        default:
            break;
    }
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
