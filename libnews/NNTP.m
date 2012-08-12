//
//  NNTP.m
//  libnews
//
//  Created by Florent Bruneau on 02/08/12.
//  Copyright (c) 2012 Florent Bruneau. All rights reserved.
//

#import "NNTP.h"
#import "NSStream+Buffered.h"
#import "List.h"

/* Global stuff
 */
NSString * const NNTPErrorDomain     = @"NNTPErrorDomain";
NSString * const NNTPConnectionKey   = @"NNTPConnectionKey";
NSString * const NNTPCommandKey      = @"NNTPCommandKey";
NSString * const NNTPReplyLineKey    = @"NNTPReplyLineKey";
NSString * const NNTPReplyCodeKey    = @"NNTPReplyCodeKey";
NSString * const NNTPReplyMessageKey = @"NNTPReplyMessageKey";

/** NNTP command.
 */

typedef NSError * __autoreleasing NSErrorRef;

@interface NNTPCommand : NSObject <DListNode>
{
    @public
    NNTP __weak *_nntp;

    NSString  *_command;
    NSArray   *_validCodes;
    
    BOOL       _acceptUnknownCodes;
    BOOL       _sent;
    BOOL       _gotHeader;
    BOOL       _done;
    BOOL       _pipelinable;

    int        _code;
    NSString  *_message;
    
    BOOL (^_on_header)(NSUInteger code, NSString *message, NSErrorRef *error);
    BOOL (^_on_line)(NSString *line, NSErrorRef *error);
    void (^_on_done)(NSError *error);
}

- (NNTPCommand *)init:(NSString *)command withNNTP:(NNTP *)nntp;
+ (NNTPCommand *)command:(NSString *)command withNNTP:(NNTP *)nntp;

- (BOOL)send:(NSOutputStream *)stream;
- (BOOL)readLine:(NSString *)line error:(NSErrorRef *)error;
@end

@implementation NNTPCommand
@synthesize prev;
@synthesize next;
@synthesize refs;

- (NNTPCommand *)init:(NSString *)command withNNTP:(NNTP *)nntp
{
    _command = command;
    _nntp    = nntp;
    return self;
}

+ (NNTPCommand *)command:(NSString *)command withNNTP:(NNTP *)nntp
{
    return [[NNTPCommand alloc] init:command withNNTP:nntp];
}

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

- (NSError *)error:(NSInteger)code forLine:(NSString *)line
{
    NSDictionary *dict;

    if (_code > 0) {
        dict = @{
            NNTPConnectionKey: _nntp,
            NNTPCommandKey: _command,
            NNTPReplyLineKey: line,
            NNTPReplyCodeKey: @(_code),
            NNTPReplyMessageKey: _message
        };
    } else {
        dict = @{
            NNTPConnectionKey: _nntp,
            NNTPCommandKey: _command,
            NNTPReplyLineKey: line,
        };
    }

    return [NSError errorWithDomain:NNTPErrorDomain code:code userInfo:dict];
}

- (BOOL)readLine:(NSString *)line error:(NSErrorRef *)error
{
    if (!_gotHeader) {
        if (line.length < 5) {
            *error = [self error:NNTPProtocoleError forLine:line];
            return NO;
        }
        _gotHeader = YES;
        
        NSString *code = [line substringToIndex:3];
        NSScanner *scanner = [NSScanner scannerWithString:code];

        [scanner setCharactersToBeSkipped:nil];
        if (![scanner scanInt:&_code] || ![scanner isAtEnd] || _code < 0
            || _code >= 600)
        {
            _code = 0;
            *error = [self error:NNTPProtocoleError forLine:line];
            return NO;
        }

        if (!_on_line) {
            _done = YES;
        }
        _message = [line substringFromIndex:4];
        for (NSNumber *number in _validCodes) {
            if ([number intValue] == _code) {
                if (_on_header) {
                    return _on_header(_code, _message, error);
                }
                return YES;
            }
        }
        if (!_acceptUnknownCodes) {
            *error = [self error:NNTPUnexpectedResponseAnswerError forLine:line];
            return NO;
        }
        return YES;
    } else {
        if (!_on_line) {
            *error = [self error:NNTPProtocoleError forLine:line];
            return NO;
        }

        if ([line isEqualToString:@"."]) {
            _done = YES;
        } else if ([line characterAtIndex:0] == '.') {
            return _on_line([line substringFromIndex:1], error);
        } else {
            return _on_line(line, error);
        }
    }
    return YES;
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
@synthesize status = _status;

- (id)init
{
    _commands = [DList new];
    return self;
}

- (void)refreshCapabilities:(void (^)(void))on_done
{
    _nntpVersion    = 0;
    _implementation = nil;
    bzero(&_capabilities, sizeof(_capabilities));
    _status = NNTPConnected;

    NNTPCommand *command = [NNTPCommand command:@"CAPABILITIES\r\n" withNNTP:self];
    NNTPCommand __weak *cmd2 = command;
    command->_validCodes   = @[ @101 ];
    command->_sent         = NO;
    command->_pipelinable  = NO;
    command->_done         = NO;
    command->_on_line = ^(NSString *line, NSErrorRef *error) {
        NSCharacterSet *space;
        NSScanner *scanner = [NSScanner scannerWithString:line];
        NSString  * __autoreleasing capability;


        space = [NSCharacterSet characterSetWithCharactersInString:@" "];
        [scanner setCharactersToBeSkipped:nil];
        [scanner scanUpToCharactersFromSet:space intoString:&capability];
        [scanner scanCharactersFromSet:space intoString:NULL];
        
        if (_nntpVersion == 0) {
            if ([capability caseInsensitiveCompare:@"VERSION"]) {
                *error = [cmd2 error:NNTPProtocoleError forLine:line];
                return NO;
            }
            if (![scanner scanInt:&_nntpVersion]) {
                *error = [cmd2 error:NNTPProtocoleError forLine:line];
                return NO;
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
        return YES;
    };
    command->_on_done = ^ (NSError *error) {
        if (error) {
            return;
        }
        if (_capabilities.reader) {
            _status = NNTPReady;
        }
        if (on_done) {
            on_done();
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
    _istream = [NSInputStream fromStream:_istream maxSize:2u << 20];
    _ostream = [NSOutputStream toStream:_ostream maxSize:2u << 20];
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
    
    NNTPCommand *command = [NNTPCommand command:nil withNNTP:self];
    command->_validCodes   = @[ @200, @201, @400, @502 ];
    command->_sent         = YES;
    command->_pipelinable  = NO;
    command->_done         = NO;
    [self sendCommand:command];
    
    [self refreshCapabilities:^{
        if (!_capabilities.reader && !_capabilities.modeReader) {
            [self close];
            [NSException raise:@"invalid server"
                        format:@"cannot post on that server"];
        } else if (!_capabilities.reader) {
            NNTPCommand *command2 = [NNTPCommand command:@"MODE READER\r\n"
                                                withNNTP:self];
            command2->_validCodes  = @[ @200, @201, @502 ];
            [self sendCommand:command2];

            [self refreshCapabilities:nil];
        }
    }];
}

- (void)close
{
    NNTPCommand *command = [NNTPCommand command:@"QUIT\r\n" withNNTP:self];
    command->_validCodes = @[ @205 ];
    [self sendCommand:command];
}

- (void)flushCommands
{
    for (NNTPCommand *command in _commands) {
        if (!command->_sent) {
            if (![command send:_ostream]) {
                return;
            }
        }
        if (!command->_done && !command->_pipelinable) {
            return;
        }
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
    NSError *error = [NSError errorWithDomain:NNTPErrorDomain
                                         code:NNTPAbortedError
                                     userInfo:nil];
    for (NNTPCommand *command in _commands) {
        if (command->_on_done) {
            command->_on_done(error);
        }
    }
    [self.delegate nntp:self handleEvent:NNTPEventError];
    [self close];
}

- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)eventCode
{
    NSString    *line;
    NNTPCommand *command;

    switch (eventCode) {
        case NSStreamEventOpenCompleted:
            _status = NNTPConnected;
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

                NSError * __autoreleasing error;
                if (![command readLine:line error:&error]) {
                    if (command->_on_done) {
                        command->_on_done(error);
                    }
                    [_commands popHead];
                    [self flushCommands];
                }

                if (command->_done) {
                    if (command->_on_done) {
                        command->_on_done(nil);
                    }

                    [_commands popHead];
                    command = nil;
                    [self flushCommands];
                }
            }
            break;

        case NSStreamEventEndEncountered:
            NSLog(@"EndEncountered");
            _status = NNTPDisconnected;
            [self.delegate nntp:self handleEvent:NNTPEventDisconnected];
            break;

        case NSStreamEventErrorOccurred:
            _status = NNTPError;
            [self streamError:[[stream streamError] description]];
            break;

        default:
            break;
    }
}

- (NNTPStatus)status
{
    return _status;
}
@end
