//
//  NNTP.m
//  libnews
//
//  Created by Florent Bruneau on 02/08/12.
//  Copyright (c) 2012 Florent Bruneau. All rights reserved.
//

#import "NNTP.h"
#import "BufferedStream.h"
#import "List.h"


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


/** NNTP command.
 */

@interface NNTPCommand : NSObject <DListNode>
@property (strong) NSString *command;
@property (assign) BOOL isMultiline;
@property (assign) BOOL sent;
@property (assign) BOOL done;
@property (assign) BOOL pipelinable;

@property (assign) NSUInteger replyCode;
@property (strong) NSString  *replyMessage;

- (BOOL)send:(NSOutputStream *)stream;
- (BOOL)readLine:(NSString *)line;
@end

@implementation NNTPCommand
@synthesize prev;
@synthesize next;
@synthesize refs;

- (BOOL)send:(NSOutputStream *)ostream
{
    if (!self.sent && [ostream hasCapacityAvailable:self.command.length + 2]) {
        [ostream write:(const uint8_t *)[self.command UTF8String]
             maxLength:self.command.length];
        [ostream write:(const uint8_t *)"\r\n"
             maxLength:2];
        self.sent = YES;
        return YES;
    }
    return NO;
}

- (BOOL)readLine:(NSString *)line
{
    if (self.replyCode == 0) {
        if (line.length < 5) {
            [NSException raise:@"invalid reply"
                        format:@"excepted \"code reply\", got \"%@\"", line];
        }
        
        NSString *code = [line substringToIndex:3];
        int icode;
        NSScanner *scanner = [NSScanner scannerWithString:code];
        
        if (![scanner scanInt:&icode] || ![scanner isAtEnd] || icode < 0
            || icode >= 600)
        {
            [NSException raise:@"invalid reply"
                        format:@"invalid reply code %@", line];
        }
        
        self.replyCode    = icode;
        self.replyMessage = [line substringFromIndex:4];
    }
    
    if (!self.isMultiline || [line isEqualToString:@"."]) {
        self.done = YES;
        return YES;
    }
    return NO;
}
@end

/** The NNTP interface implements the Stream delegation
 */

@interface NNTP () <NSStreamDelegate>
@property (strong) NSInputStream  *istream;
@property (strong) NSOutputStream *ostream;
@property (strong) DList *commands;
@property (assign) NSUInteger syncTimeout;

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode;
@end


@implementation NNTP
@dynamic status;

- (id)init
{
    self.commands = [DList new];
    return self;
}

- (void)setSync:(UInt32)timeout
{
    self.syncTimeout = timeout;
}

- (void)setAsync
{
    self.syncTimeout = 0;
}

- (void)waitForCondition:(bool (^)(void))condition
{
    if (!self.syncTimeout) {
        return;
    }

    NSDate *date = [NSDate dateWithTimeIntervalSinceNow:self.syncTimeout];
    [[NSRunLoop currentRunLoop] runUntilDate:date orCondition:condition];
    
    if (!condition()) {
        [NSException raise:@"Timeout" format:@"reached timeout"];
    }
}

- (void)connect:(NSString *)host port:(UInt32)port ssl:(BOOL)ssl
{
    [self close];
    
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
    
    NNTPCommand *command = [NNTPCommand new];
    command.sent         = YES;
    command.isMultiline  = NO;
    command.pipelinable  = NO;
    command.done         = NO;
    [self sendCommand:command];
}

- (void)close
{
    [self.istream close];
    [self.ostream close];
}

- (void)flushCommands
{
    for (NNTPCommand *command in self.commands) {
        if (!command.sent) {
            if (![command send:self.ostream]) {
                return;
            }
        }
        if (!command.done) {
            [self waitForCondition:^bool (void) {
                return [command done];
            }];
        }
        if (!command.done && !command.pipelinable) {
            return;
        }
    }
}

- (void)sendCommand:(NNTPCommand *)command
{
    [self.commands addTail:command];
    if (self.ostream.hasSpaceAvailable) {
        [self flushCommands];
    }
}

- (void)streamError:(NSString *)message
{
    NSLog(@"Stream error encountered: %@", message);
    [self.delegate nntp:self handleEvent:NNTPEventError];
    [self close];
}

- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)eventCode
{
    NSString    *line;
    NNTPCommand *command;

    switch (eventCode) {
        case NSStreamEventOpenCompleted:
            NSLog(@"OpenCompleted");
            [self.delegate nntp:self handleEvent:NNTPEventConnected];
            break;
        case NSStreamEventHasSpaceAvailable:
            NSLog(@"SpaceAvailable");
            assert (stream == self.ostream);
            [self flushCommands];
            break;
        case NSStreamEventHasBytesAvailable:
            NSLog(@"BytesAvailable");
            while ((line = [self.istream readLine])) {
                NSLog(@"read line: %@", line);

                command = (NNTPCommand *)self.commands.head;
                if (command == nil || !command.sent) {
                    [self streamError:@"Received spurious data"];
                    return;
                }

                if (![command readLine:line]) {
                    [self streamError:@"Invalid data received"];
                    return;
                }
                
                if (command.done) {
                    /* TODO: do something with the command */
                    [self.commands popHead];
                    [self flushCommands];
                }
            }
            break;

        case NSStreamEventEndEncountered:
            NSLog(@"EndEncountered");
            [self.delegate nntp:self handleEvent:NNTPEventDisconnected];
            break;

        case NSStreamEventErrorOccurred:
            NSLog(@"ErrorOccured");
            [self streamError:[[stream streamError] description]];
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
@end
