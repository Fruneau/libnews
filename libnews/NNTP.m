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
{
    @public
    NSString  *_command;
    NSArray   *_validCodes;
    
    BOOL       _acceptUnknownCodes;
    BOOL       _sent;
    BOOL       _gotHeader;
    BOOL       _done;
    BOOL       _pipelinable;
    
    void (^_on_header)(NSUInteger code, NSString *message);
    void (^_on_line)(NSString *line);
}

- (BOOL)send:(NSOutputStream *)stream;
- (void)readLine:(NSString *)line;
@end

@implementation NNTPCommand
@synthesize prev;
@synthesize next;
@synthesize refs;

- (BOOL)send:(NSOutputStream *)ostream
{
    if (!_sent && [ostream hasCapacityAvailable:_command.length]) {
        NSLog(@"<< %@", [_command substringToIndex:_command.length - 2]);
        [ostream write:(const uint8_t *)[_command UTF8String]
             maxLength:_command.length];
        _sent = YES;
        return YES;
    }
    return NO;
}

- (void)readLine:(NSString *)line
{
    if (!_gotHeader) {
        if (line.length < 5) {
            [NSException raise:@"invalid reply"
                        format:@"excepted \"code reply\", got \"%@\"", line];
        }
        _gotHeader = YES;
        
        int icode;
        NSString *code = [line substringToIndex:3];
        NSScanner *scanner = [NSScanner scannerWithString:code];
        
        if (![scanner scanInt:&icode] || ![scanner isAtEnd] || icode < 0
            || icode >= 600)
        {
            [NSException raise:@"invalid reply"
                        format:@"invalid reply code %@", line];
        }

        if (!_on_line) {
            _done = YES;
        }
        line = [line substringFromIndex:4];
        for (NSNumber *number in _validCodes) {
            if ([number intValue] == icode) {
                if (_on_header) {
                    _on_header(icode, line);
                }
                return;
            }
        }
        if (!_acceptUnknownCodes) {
            [NSException raise:@"invalid reply"
                        format:@"code %i not accepted by this command %@",
             icode, self];
        }
        return;
    } else {
        if (!_on_line) {
            [NSException raise:@"unexpected line"
                        format:@"received data on non-multiline command"];
        }

        if ([line isEqualToString:@"."]) {
            _done = YES;
        } else if ([line characterAtIndex:0] == '.') {
            _on_line([line substringFromIndex:1]);
        } else {
            _on_line(line);
        }
    }
}

- (NSString *)description
{
    return _command;
}
@end

/** The NNTP interface implements the Stream delegation
 */

@interface NNTP () <NSStreamDelegate>
{
    NSInputStream  *_istream;
    NSOutputStream *_ostream;
    DList          *_commands;
    NSInteger       _syncTimeout;
    
    int             _nntpVersion;
    NSString       *_implementation;
    struct {
        unsigned     modeReader : 1;
        unsigned     reader     : 1;
    } _capabilities;
}

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode;
@end


@implementation NNTP
@dynamic status;

- (id)init
{
    _commands = [DList new];
    return self;
}

- (void)setSync:(NSInteger)timeout
{
    _syncTimeout = timeout;
}

- (void)setAsync
{
    _syncTimeout = 0;
}

- (void)waitForCondition:(bool (^)(void))condition
{
    if (!_syncTimeout) {
        return;
    }

    NSDate *date = [NSDate dateWithTimeIntervalSinceNow:_syncTimeout];
    [[NSRunLoop currentRunLoop] runUntilDate:date orCondition:condition];
    
    if (!condition()) {
        [NSException raise:@"Timeout" format:@"reached timeout"];
    }
}

- (void)refreshCapabilities
{
    _nntpVersion    = 0;
    _implementation = nil;
    bzero(&_capabilities, sizeof(_capabilities));

    NNTPCommand *command = [NNTPCommand new];
    command->_command      = @"CAPABILITIES\r\n";
    command->_validCodes   = @[ @101 ];
    command->_sent         = NO;
    command->_pipelinable  = NO;
    command->_done         = NO;
    command->_on_line = ^(NSString *line) {
        NSCharacterSet *space;
        NSScanner *scanner = [NSScanner scannerWithString:line];
        NSString  * __autoreleasing capability;
        
        space = [NSCharacterSet characterSetWithCharactersInString:@" "];
        [scanner scanUpToCharactersFromSet:space intoString:&capability];
        [scanner scanCharactersFromSet:space intoString:NULL];
        
        if (_nntpVersion == 0) {
            if ([capability caseInsensitiveCompare:@"VERSION"]) {
                [NSException raise:@"invalid reply"
                            format:@"expected VERSION as the first capability,"
                 "got %@", line];
            }
            if (![scanner scanInt:&_nntpVersion]) {
                [NSException raise:@"invalid reply"
                            format:@"expected version number in %@", line];
            }
        } else if (![capability caseInsensitiveCompare:@"MODE-READER"]) {
            _capabilities.modeReader = YES;
        } else if (![capability caseInsensitiveCompare:@"READER"]) {
            _capabilities.reader = YES;
        } else if (![capability caseInsensitiveCompare:@"IMPLEMENTATION"]) {
            _implementation = [line substringFromIndex:[scanner scanLocation]];
        } else {
            NSLog(@"unsupported capability: %@", line);
        }
    };
    [self sendCommand:command];
}

- (void)connect:(NSString *)host port:(UInt32)port ssl:(BOOL)ssl
{
    CFReadStreamRef cfistream;
    CFWriteStreamRef cfostream;
    NSRunLoop *loop = [NSRunLoop currentRunLoop];

    CFStreamCreatePairWithSocketToHost(NULL, (__bridge CFStringRef)(host),
                                       port, &cfistream, &cfostream);
    _istream = (NSInputStream *)CFBridgingRelease(cfistream);
    _ostream = (NSOutputStream *)CFBridgingRelease(cfostream);
    _istream = [NSInputStream fromStream:_istream
                                     maxSize:2u << 20];
    _ostream = [NSOutputStream toStream:_ostream
                                    maxSize:2u << 20];
    _istream.delegate = self;
    _ostream.delegate = self;
    
    [_istream scheduleInRunLoop:loop forMode:NSDefaultRunLoopMode];
    [_ostream scheduleInRunLoop:loop forMode:NSDefaultRunLoopMode];
    
    if (ssl) {
        [_istream setProperty:NSStreamSocketSecurityLevelNegotiatedSSL
                       forKey:NSStreamSocketSecurityLevelKey];
    }
    
    [_istream open];
    [_ostream open];
    
    NNTPCommand *command = [NNTPCommand new];
    command->_validCodes   = @[ @200, @201, @400, @502 ];
    command->_sent         = YES;
    command->_pipelinable  = NO;
    command->_done         = NO;
    [self sendCommand:command];
    
    [self refreshCapabilities];
        
    if (!_capabilities.reader && !_capabilities.modeReader) {
        [self close];
        [NSException raise:@"invalid server"
                    format:@"cannot post on that server"];
    } else if (!_capabilities.reader) {
        command = [NNTPCommand new];
        command->_command     = @"MODE READER\r\n";
        command->_validCodes  = @[ @200, @201, @502 ];
        [self sendCommand:command];
        
        [self refreshCapabilities];
    }
}

- (void)close
{
    NNTPCommand *command = [NNTPCommand new];
    command->_command = @"QUIT\r\n";
    command->_validCodes = @[ @205 ];
    [self sendCommand:command];
}

- (void)flushCommands
{
    static BOOL guard = NO;
    
    if (guard) {
        return;
    }
    guard = YES;
    
    @try {
        for (NNTPCommand *command in _commands) {
            if (!command->_sent) {
                if (![command send:_ostream]) {
                    return;
                }
            }
            if (!command->_done) {
                [self waitForCondition:^bool (void) {
                    return command->_done;
                }];
            }
            if (!command->_done && !command->_pipelinable) {
                return;
            }
        }
    } @finally {
        guard = NO;
    }
}

- (void)sendCommand:(NNTPCommand *)command
{
    [_commands addTail:command];
    if (_ostream.hasSpaceAvailable) {
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
            [self.delegate nntp:self handleEvent:NNTPEventConnected];
            break;

        case NSStreamEventHasSpaceAvailable:
            assert (stream == _ostream);
            [self flushCommands];
            break;

        case NSStreamEventHasBytesAvailable:
            while ((line = [_istream readLine])) {
                NSLog(@">> %@", line);

                command = (NNTPCommand *)_commands.head;
                if (command == nil || !command->_sent) {
                    [self streamError:@"Received spurious data"];
                    return;
                }

                [command readLine:line];
                if (command->_done) {
                    /* TODO: do something with the command */
                    [_commands popHead];
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
    NSStreamStatus ostatus = _ostream.streamStatus;
    NSStreamStatus istatus = _istream.streamStatus;
    
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
