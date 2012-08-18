//
//  NNTP.m
//  libnews
//
//  Created by Florent Bruneau on 02/08/12.
//  Copyright (c) 2012 Florent Bruneau. All rights reserved.
//

#import "NNTP.h"
#import "NSStream+Buffered.h"
#import "NSCharacterSet+Spaces.h"
#import "NSScanner+Helpers.h"
#import "List.h"

/* Global stuff
 */
NSString * const NNTPErrorDomain     = @"NNTPErrorDomain";
NSString * const NNTPConnectionKey   = @"NNTPConnectionKey";
NSString * const NNTPCommandKey      = @"NNTPCommandKey";
NSString * const NNTPReplyLineKey    = @"NNTPReplyLineKey";
NSString * const NNTPReplyCodeKey    = @"NNTPReplyCodeKey";
NSString * const NNTPReplyMessageKey = @"NNTPReplyMessageKey";

/** Declaring stuff.
 */

typedef NSError * __autoreleasing NSErrorRef;

typedef enum NNTPCommandType {
    /* RFC 3977: NNTP Version 2 */
    NNTPConnect,
    NNTPCapabilities,
    NNTPModeReader,
    NNTPQuit,
    NNTPGroup,
    NNTPListGroup,
    NNTPLast,
    NNTPNext,
    NNTPArticle,
    NNTPHead,
    NNTPBody,
    NNTPStat,
    NNTPPost,
    NNTPIhave,
    NNTPDate,
    NNTPHelp,
    NNTPNewgroups,
    NNTPNewnews,
    NNTPListActive,
    NNTPListActiveTimes,
    NNTPListDistribPats,
    NNTPListHeaders,
    NNTPListNewsgroups,
    NNTPListOverviewFmt,
    NNTPOver,
    NNTPHdr,
    

    /* RCP 4642: StartTLS */
    NNTPStartTls,

    /* RFC 4643: NNTP Authentication */
    NNTPAuthinfoUser,
    NNTPAuthinfoPass,
    NNTPAuthinfoSASL,

    /* Count */
    NNTPCommand_count,
} NNTPCommandType;

typedef enum NNTPCapability {
    /* RFC 3977: NNTP Version 2 */
    NNTPCapModeReader      = 1ul << 0,
    NNTPCapReader          = 1ul << 1,
    NNTPCapIhave           = 1ul << 2,
    NNTPCapPost            = 1ul << 3,
    NNTPCapNewnews         = 1ul << 4,
    NNTPCapHdr             = 1ul << 5,
    NNTPCapOver            = 1ul << 6,
    NNTPCapListActive      = 1ul << 7,
    NNTPCapListActiveTimes = 1ul << 8,
    NNTPCapListDistribPats = 1ul << 9,
    NNTPCapListHeaders     = 1ul << 10,
    NNTPCapListNewsgroups  = 1ul << 11,
    NNTPCapListOverviewFmt = 1ul << 12,

    /* RFC 4642: STARTTLS */
    NNTPCapStartTls        = 1ul << 16,

    /* RFC 4643: NNTP Authentication */
    NNTPCapAuthinfoUser    = 1ul << 17,
    NNTPCapAuthinfoSASL    = 1ul << 18,

    /* SASL mechanism: 
     * http://www.iana.org/assignments/sasl-mechanisms/sasl-mechanisms.xml
     */
    NNTPCapSaslPlain       = 1ul << 19,
    NNTPCapSaslLogin       = 1ul << 20,
    NNTPCapSaslCramMd5     = 1ul << 21,
    NNTPCapSaslNtml        = 1ul << 22,
    NNTPCapSaslDigestMd5   = 1ul << 23,
    
    /* RFC 4644: NNTP Streaming extension */
    NNTPCapStreaming       = 1ul << 32,

    /* Special capabilities */
    NNTPCapVersion         = 1ul << 62,
    NNTPCapImplementation  = 1ul << 63,
} NNTPCapability;

/* Interfaces
 */

@interface NNTP () <NSStreamDelegate>
{
    NSInputStream  *_istream;
    NSOutputStream *_ostream;
    DList          *_commands;

    @public
    int             _nntpVersion;
    NSString       *_implementation;
    uint64_t        _capabilities;
}

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode;
@end


@interface NNTPCommand : NSObject <DListNode>
{
    @public
    const struct NNTPCommandParams *_params;
    NNTP * __weak _nntp;

    NSInteger    _commandLineLen;
    char         _commandLine[513];
    unsigned     _sent      : 1;
    unsigned     _gotHeader : 1;

    int          _code;
    NSString    *_message;

    void (^_onDone)(NSError *error);
}


+ (NNTPCommand *)command:(NNTPCommandType)type withNNTP:(NNTP *)nntp
                 andArgs:(NSArray *)args;
- (BOOL)send:(NSOutputStream *)stream;
- (BOOL)readHeader:(NSString *)line error:(NSErrorRef *)error;
- (BOOL)readFromStream:(NSInputStream *)stream error:(NSErrorRef *)error;

/* To be inherited */
- (BOOL)readLine:(NSString *)line error:(NSErrorRef *)error;
@end

@interface NNTPCapabilitiesCommand: NNTPCommand
@end


/* Command descriptors
 */

NSDictionary *nntpCapabilitiesMap = nil;

struct NNTPCommandParams {
    NNTPCommandType type;
    const char     *command;
    const char     *className;
    const uint16_t *validCodes;
    uint64_t        capabilities;

    unsigned        isMultiline         : 1;
    unsigned        isPipelinable       : 1;
    unsigned        requireCapRefresh   : 1;
} const commandParams[] = {
    [NNTPConnect] = {
        .type               = NNTPConnect,
        .validCodes         = (const uint16_t[]){ 200, 201, 400, 502, 0 },
        .requireCapRefresh  = YES,
    },

    [NNTPCapabilities] = {
        .type               = NNTPCapabilities,
        .command            = "CAPABILITIES",
        .className          = "NNTPCapabilitiesCommand",
        .validCodes         = (const uint16_t[]){ 101, 0 },
        .isMultiline        = YES,
    },

    [NNTPModeReader] = {
        .type               = NNTPModeReader,
        .command            = "MODE READER",
        .validCodes         = (const uint16_t[]){ 200, 201, 502, 0 },
        .capabilities       = NNTPCapModeReader,
        .requireCapRefresh  = YES,
    },

    [NNTPQuit] = {
        .type               = NNTPQuit,
        .command            = "QUIT",
        .validCodes         = (const uint16_t[]){ 205, 0 },
    },

    
    /* Group and article selection */

    [NNTPGroup] = {
        .type               = NNTPGroup,
        .command            = "GROUP",
        .validCodes         = (const uint16_t[]){ 211, 411, 0 },
        .capabilities       = NNTPCapReader,
        .isPipelinable      = YES,
    },

    [NNTPListGroup] = {
        .type               = NNTPListGroup,
        .command            = "LISTGROUP",
        .validCodes         = (const uint16_t[]){ 211, 411, 412, 0 },
        .capabilities       = NNTPCapReader,
        .isPipelinable      = YES,
        .isMultiline        = YES,
    },

    [NNTPLast] = {
        .type               = NNTPLast,
        .command            = "LAST",
        .validCodes         = (const uint16_t[]){ 223, 412, 420, 422, 0 },
        .capabilities       = NNTPCapReader,
        .isPipelinable      = YES,
    },

    [NNTPNext] = {
        .type               = NNTPNext,
        .command            = "NEXT",
        .validCodes         = (const uint16_t[]){ 223, 412, 420, 421, 0 },
        .capabilities       = NNTPCapReader,
        .isPipelinable      = YES,
    },


    /* Article retrieval */

    [NNTPArticle] = {
        .type               = NNTPArticle,
        .command            = "ARTICLE",
        .validCodes         = (const uint16_t[]){ 220, 412, 420, 423, 430, 0 },
        .capabilities       = NNTPCapReader,
        .isPipelinable      = YES,
        .isMultiline        = YES,
    },

    [NNTPHead] = {
        .type               = NNTPHead,
        .command            = "HEAD",
        .validCodes         = (const uint16_t[]){ 221, 412, 420, 423, 430, 0 },
        .isPipelinable      = YES,
        .isMultiline        = YES,
    },

    [NNTPBody] = {
        .type               = NNTPBody,
        .command            = "BODY",
        .validCodes         = (const uint16_t[]){ 222, 412, 420, 423, 430, 0 },
        .capabilities       = NNTPCapReader,
        .isPipelinable      = YES,
        .isMultiline        = YES,
    },

    [NNTPStat] = {
        .type               = NNTPStat,
        .command            = "STAT",
        .validCodes         = (const uint16_t[]){ 223, 412, 420, 423, 430, 0 },
        .isPipelinable      = YES,
        .isMultiline        = YES,
    },

    
    /* Posting */

    [NNTPPost] = {
        .type               = NNTPPost,
        .command            = "POST",
        .validCodes         = (const uint16_t[]){ 340, 440, 0 },
        .capabilities       = NNTPCapPost,
    },

    [NNTPIhave] = {
        .type               = NNTPIhave,
        .command            = "IHAVE",
        .validCodes         = (const uint16_t[]){ 335, 435, 436, 0 },
        .capabilities       = NNTPCapIhave,
    },


    /* Information */
    
    [NNTPDate] = {
        .type               = NNTPDate,
        .command            = "DATE",
        .validCodes         = (const uint16_t[]){ 111, 0 },
        .capabilities       = NNTPCapReader,
        .isPipelinable      = YES,
    },

    [NNTPHelp] = {
        .type               = NNTPHelp,
        .command            = "HELP",
        .validCodes         = (const uint16_t[]){ 100, 0 },
        .isPipelinable      = YES,
        .isMultiline        = YES,
    },

    [NNTPNewgroups] = {
        .type               = NNTPNewgroups,
        .command            = "NEWGROUPS",
        .validCodes         = (const uint16_t[]){ 231, 0 },
        .capabilities       = NNTPCapReader,
        .isPipelinable      = YES,
        .isMultiline        = YES,
    },

    [NNTPNewnews] = {
        .type               = NNTPNewnews,
        .command            = "NEWNEWS",
        .validCodes         = (const uint16_t[]){ 230, 0 },
        .capabilities       = NNTPCapNewnews,
        .isPipelinable      = YES,
        .isMultiline        = YES,
    },


    /* List */

    [NNTPListActive] = {
        .type               = NNTPListActive,
        .command            = "LIST ACTIVE",
        .validCodes         = (const uint16_t[]){ 215, 0 },
        .capabilities       = NNTPCapListActive,
        .isPipelinable      = YES,
        .isMultiline        = YES,
    },

    [NNTPListActiveTimes] = {
        .type               = NNTPListActiveTimes,
        .command            = "LIST ACTIVE.TIMES",
        .validCodes         = (const uint16_t[]){ 215, 0 },
        .capabilities       = NNTPCapListActiveTimes,
        .isPipelinable      = YES,
        .isMultiline        = YES,
    },

    [NNTPListDistribPats] = {
        .type               = NNTPListDistribPats,
        .command            = "LIST DISTRIB.PATS",
        .validCodes         = (const uint16_t[]){ 215, 0 },
        .capabilities       = NNTPCapListDistribPats,
        .isPipelinable      = YES,
        .isMultiline        = YES,
    },

    [NNTPListNewsgroups] = {
        .type               = NNTPListNewsgroups,
        .command            = "LIST NEWSGROUPS",
        .validCodes         = (const uint16_t[]){ 215, 0 },
        .capabilities       = NNTPCapListNewsgroups,
        .isPipelinable      = YES,
        .isMultiline        = YES,
    },

    
    /* Article field access */

    [NNTPOver] = {
        .type               = NNTPOver,
        .command            = "OVER",
        .validCodes         = (const uint16_t[]){ 224, 412, 420, 423, 430, 0 },
        .capabilities       = NNTPCapOver,
        .isPipelinable      = YES,
        .isMultiline        = YES,
    },

    [NNTPListOverviewFmt] = {
        .type               = NNTPListOverviewFmt,
        .command            = "LIST OVERVIEW.FMT",
        .validCodes         = (const uint16_t[]){ 215, 0 },
        .capabilities       = NNTPCapListOverviewFmt,
        .isPipelinable      = YES,
        .isMultiline        = YES,
    },

    [NNTPHdr] = {
        .type               = NNTPHdr,
        .command            = "HDR",
        .validCodes         = (const uint16_t[]){ 225, 412, 420, 423, 430, 0 },
        .capabilities       = NNTPCapHdr,
        .isPipelinable      = YES,
        .isMultiline        = YES,
    },

    [NNTPListHeaders] = {
        .type               = NNTPListHeaders,
        .command            = "LIST HEADERS",
        .validCodes         = (const uint16_t[]){ 215, 0 },
        .capabilities       = NNTPCapListHeaders,
        .isPipelinable      = YES,
        .isMultiline        = YES,
    },


    /* Authentication */

    [NNTPAuthinfoUser] = {
        .type               = NNTPAuthinfoUser,
        .command            = "AUTHINFO USER",
        .validCodes         = (const uint16_t[]){ 281, 381, 481, 482, 502, 0 },
        .capabilities       = NNTPCapAuthinfoUser,
    },

    [NNTPAuthinfoPass] = {
        .type               = NNTPAuthinfoPass,
        .command            = "AUTHINFO PASS",
        .validCodes         = (const uint16_t[]){ 281, 481, 482, 502, 0 },
        .capabilities       = NNTPCapAuthinfoUser,
        .requireCapRefresh  = YES,
    },

    [NNTPAuthinfoSASL] = {
        .type               = NNTPAuthinfoSASL,
        .command            = "AUTHINFO SASL",
        .validCodes         = (const uint16_t[]){ 281, 283, 383, 481, 482, 502, 0 },
        .capabilities       = NNTPCapAuthinfoSASL,
    }
};

/* NNTP Command implementation
 */

@implementation NNTPCommand
@synthesize prev;
@synthesize next;
@synthesize refs;

+ (NNTPCommand *)command:(NNTPCommandType)type withNNTP:(NNTP *)nntp
                 andArgs:(NSArray *)args
{
    static Class commandClasses[NNTPCommand_count];
    const struct NNTPCommandParams *param = &commandParams[type];
    NNTPCommand *command;
    
    if ((nntp->_capabilities & param->capabilities) != param->capabilities) {
        NSLog(@"/!\\ the server does not support that command: %s",
              param->command);
        return nil;
    }
    if (!commandClasses[type] && param->className) {
        NSString *className = [NSString stringWithUTF8String:param->className];

        commandClasses[type] = NSClassFromString(className);
        if (!commandClasses[type]) {
            abort();
        }
    } else if (!commandClasses[type]) {
        commandClasses[type] = [NNTPCommand class];
    }
    command = [commandClasses[type] new];
    command->_nntp    = nntp;
    command->_params  = param;

    if (param->command) {
        strcpy(command->_commandLine, param->command);
        command->_commandLineLen = strlen(command->_commandLine);

        for (id arg in args) {
            NSString *desc    = [arg description];
            const char *chars = [desc UTF8String];
            NSInteger   len   = strlen(chars);

            command->_commandLine[command->_commandLineLen++] = ' ';
            if (len > 510 - command->_commandLineLen) {
                NSLog(@"line too long");
                return nil;
            }
            strcpy(command->_commandLine + command->_commandLineLen, chars);
            command->_commandLineLen += len;
        }

        command->_commandLine[command->_commandLineLen++] = '\r';
        command->_commandLine[command->_commandLineLen++] = '\n';
        command->_commandLine[command->_commandLineLen]   = '\0';
    } else {
        command->_sent = YES;
    }
    return command;
}

- (BOOL)send:(NSOutputStream *)ostream
{
    if (!_sent && [ostream hasCapacityAvailable:_commandLineLen]) {
        NSLog(@"<< %.*s", (int)_commandLineLen - 2, _commandLine);
        [ostream write:(const uint8_t *)_commandLine maxLength:_commandLineLen];
        _sent = YES;
        return YES;
    }
    return NO;
}

- (NSError *)error:(NSInteger)code forLine:(NSString *)line
{
    NSDictionary *dict;
    NSString     *cmd = [NSString stringWithUTF8String:_commandLine];

    if (_code > 0) {
        dict = @{
            NNTPConnectionKey:   _nntp,
            NNTPCommandKey:      cmd,
            NNTPReplyLineKey:    line,
            NNTPReplyCodeKey:    @(_code),
            NNTPReplyMessageKey: _message
        };
    } else {
        dict = @{
            NNTPConnectionKey: _nntp,
            NNTPCommandKey:    cmd,
            NNTPReplyLineKey:  line,
        };
    }

    return [NSError errorWithDomain:NNTPErrorDomain code:code userInfo:dict];
}

- (BOOL)readHeader:(NSString *)line error:(NSErrorRef *)error
{
    if (line.length < 5) {
        *error = [self error:NNTPProtocoleError forLine:line];
        return NO;
    }

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

    _message = [line substringFromIndex:4];
    for (int i = 0; _params->validCodes[i] != 0; i++) {
        if (_params->validCodes[i] == _code) {
            return YES;
        }
    }
    *error = [self error:NNTPUnexpectedResponseAnswerError forLine:line];
    return NO;
}

- (BOOL)readLine:(NSString *)line error:(NSErrorRef *)error
{
    [NSException raise:@"unimplemented"
                format:@"not implemented in main class"];
    return NO;
}

- (BOOL)readFromStream:(NSInputStream *)stream error:(NSErrorRef *)error
{
    NSString *line;

    while ((line = [stream readLine])) {
        NSLog(@">> %@", line);

        if (!_gotHeader) {
            _gotHeader = YES;

            if (![self readHeader:line error:error] || !_params->isMultiline) {
                return YES;
            }
        } else if ([line isEqualToString:@"."]) {
            return YES;
        } else {
            NSString *l = line;

            if ([line characterAtIndex:0] == '.') {
                l = [line substringFromIndex:1];
            }
            if (![self readLine:l error:error]) {
                return YES;
            }
        }
    }
    return NO;
}

- (NSString *)description
{
    return [NSString stringWithUTF8String:_commandLine];
}
@end

@implementation NNTPCapabilitiesCommand
- (id)init
{
    if (!nntpCapabilitiesMap) {
        nntpCapabilitiesMap = @{
            /* RFC 3977: NNTP Version 2 */
            @"VERSION":         @(NNTPCapVersion),
            @"IMPLEMENTATION":  @(NNTPCapImplementation),
            @"MODE-READER":     @(NNTPCapModeReader),
            @"READER":          @(NNTPCapReader),
            @"IHAVE":           @(NNTPCapIhave),
            @"POST":            @(NNTPCapPost),
            @"NEWNEWS":         @(NNTPCapNewnews),
            @"HDR":             @(NNTPCapHdr),
            @"OVER":            @(NNTPCapOver),
                @"LIST":            @{
                @"ACTIVE":          @(NNTPCapListActive),
                @"ACTIVE.TIMES":    @(NNTPCapListActiveTimes),
                @"DISTRIB.PATS":    @(NNTPCapListDistribPats),
                @"HEADERS":         @(NNTPCapListHeaders),
                @"NEWSGROUPS":      @(NNTPCapListNewsgroups),
                @"OVERVIEW.FMT":    @(NNTPCapListOverviewFmt),
            },

            /* RFC 4642: STARTTLS */
            @"STARTTLS":        @(NNTPCapStartTls),

            /* RFC 4643: NNTP Authentication */
            @"AUTHINFO":        @{
                @"USER":            @(NNTPCapAuthinfoUser),
                @"SASL":            @(NNTPCapAuthinfoSASL),
            },
            /* SASL Mechanisms */
            @"SASL":            @{
                @"PLAIN":           @(NNTPCapSaslPlain),
                @"LOGIN":           @(NNTPCapSaslLogin),
                @"CRAM-MD5":        @(NNTPCapSaslCramMd5),
                @"NTLM":            @(NNTPCapSaslNtml),
                @"DIGEST-MD5":      @(NNTPCapSaslDigestMd5),
            },

            /* RFC 4644: NNTP Streaming */
            @"STREAMING":       @(NNTPCapStreaming),
        };
    }
    return self;
}

- (BOOL)readLine:(NSString *)line error:(NSErrorRef *)error
{
    NSCharacterSet *space = [NSCharacterSet whitespaceCharacterSet];
    NSScanner *scanner = [NSScanner scannerWithString:line];
    NSString  * __autoreleasing capability;

    [scanner setCharactersToBeSkipped:nil];
    [scanner scanUpToCharactersFromSet:space intoString:&capability];
    capability = [capability uppercaseString];
    [scanner setCharactersToBeSkipped:space];

    id entry = nntpCapabilitiesMap[capability];
    if (entry == nil) {
        NSLog(@"unsupported capability: %@", line);
        return YES;
    } else if ([entry isKindOfClass:[NSNumber class]]) {
        uint64_t v = [(NSNumber *)entry unsignedLongLongValue];

        if (v == NNTPCapVersion) {
            if (![scanner scanInt:&_nntp->_nntpVersion]) {
                *error = [self error:NNTPInvalidDataError forLine:line];
                return NO;
            }
            return YES;
        } else if (v == NNTPCapImplementation) {
            _nntp->_implementation = [scanner remainder];
            return YES;
        } else {
            _nntp->_capabilities |= v;
            return YES;
        }
    }

    NSDictionary *sub = (NSDictionary *)entry;
    while (![scanner isAtEnd]) {
        NSString * __autoreleasing subtype;

        [scanner scanUpToCharactersFromSet:space
                                intoString:&subtype];
        subtype = [subtype uppercaseString];

        NSNumber *flag = sub[subtype];
        if (flag == nil) {
            NSLog(@"unsupported option %@ for capability %@",
                  subtype, capability);
            continue;
        }
        _nntp->_capabilities |= [(NSNumber *)flag unsignedLongLongValue];
    }
    return YES;
}
@end


/** The NNTP interface implements the Stream delegation
 */

@implementation NNTP
@synthesize status = _status;

- (id)init
{
    _commands = [DList new];
    return self;
}

- (BOOL)sendCommand:(NNTPCommandType)type withArgs:(NSArray *)array
             onDone:(void (^)(NSError *error))onDone
{
    NNTPCommand *command = [NNTPCommand command:type withNNTP:self
                                        andArgs:array];
    if (!command) {
        return NO;
    }

    if (command->_params->requireCapRefresh) {
        command->_onDone = ^(NSError *error) {
            if (!error) {
                [self refreshCapabilities:onDone];
            } else if (onDone) {
                onDone(error);
            }
        };
    } else {
        command->_onDone = onDone;
    }


    [_commands addTail:command];
    if (_ostream.hasSpaceAvailable) {
        [self flushCommands];
    }
    return YES;
}

- (void)sendCommand:(NNTPCommandType)type
{
    [self sendCommand:type withArgs:nil onDone:nil];
}

- (void)refreshCapabilities:(void (^)(NSError *error))on_done
{
    _nntpVersion    = 0;
    _implementation = nil;
    _capabilities   = 0;
    _status         = NNTPConnected;

    [self sendCommand:NNTPCapabilities
             withArgs:nil
               onDone: ^ (NSError *error) {
                   if (_capabilities & NNTPCapReader) {
                       _status = NNTPReady;
                   }
                   if (on_done) {
                       on_done(error);
                   }
               }];
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
    
    [self sendCommand:NNTPConnect withArgs:nil
               onDone:^(NSError *error) {
                   if (!error) {
                       [self sendCommand:NNTPModeReader withArgs:nil
                                  onDone:^(NSError *error2) {
                                  }];
                   }
               }];
}

- (void)authenticate:(NSString *)login password:(NSString *)password
{
    [self sendCommand:NNTPAuthinfoUser withArgs:@[ login ]
               onDone:^(NSError *error) {
                   if (error) {
                       [self.delegate nntp:self
                               handleEvent:NNTPEventAuthenticationFailed];
                       return;
                   }
               }];
    if (password) {
        [self sendCommand:NNTPAuthinfoPass withArgs:@[ password ]
                   onDone:^(NSError *error) {
                       if (!error) {
                           [self.delegate nntp:self
                                   handleEvent:NNTPEventAuthenticated];
                       } else {
                           [self.delegate nntp:self
                                   handleEvent:NNTPEventAuthenticationFailed];
                       }
                   }];
    }
}

- (void)close
{
    [self sendCommand:NNTPQuit];
}

- (void)flushCommands
{
    for (NNTPCommand *command in _commands) {
        if (!command->_sent) {
            if (![command send:_ostream]) {
                return;
            }
        }
        if (!command->_params->isPipelinable) {
            return;
        }
    }
}

- (void)streamError:(NSString *)message
{
    NSLog(@"%@", message);
    NSError *error = [NSError errorWithDomain:NNTPErrorDomain
                                         code:NNTPAbortedError
                                     userInfo:nil];
    for (NNTPCommand *command in _commands) {
        if (command->_onDone) {
            command->_onDone(error);
        }
        [_commands remove:command];
    }
    [_commands clear];
    [self.delegate nntp:self handleEvent:NNTPEventError];
    [self close];
}

- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)eventCode
{
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
            while (YES) {
                NNTPCommand *command = _commands.head;
                NSErrorRef   error;

                if (!command || !command->_sent) {
                    return;
                }
                if ([command readFromStream:_istream error:&error]) {
                    [_commands popHead];
                    if (command->_onDone) {
                        command->_onDone(error);
                    }
                    [self flushCommands];
                } else {
                    /* More data is needed by the current command */
                    break;
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
