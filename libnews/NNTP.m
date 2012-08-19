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
#include "utils.h"

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

typedef NSInteger (^NNTPOnDone)(NSError *error);

@class NNTPCommandGroup;

@interface NNTP () <NSStreamDelegate>
{
    @public
    NSInputStream    *_istream;
    NSOutputStream   *_ostream;
    NNTPCommandGroup *_commands;

    int               _nntpVersion;
    NSString         *_implementation;
    uint64_t          _capabilities;
    NNTPStatus        _status;
}

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode;
@end

@protocol NNTPCommand <DListNode>
@property(readonly) BOOL isPipelinable;
@property(readonly) BOOL hasPendingWrite;
@property(readonly) BOOL hasPendingRead;

- (NSInteger)send;
- (NSInteger)read:(NSErrorRef *)error;

- (void)abort:(NSError *)error;
@end

@interface NNTPCommand : NSObject <NNTPCommand>
{
    @public
    const struct NNTPCommandParams *_params;
    NNTP * __unsafe_unretained _nntp;

    NSInteger    _commandLineLen;
    char         _commandLine[513];
    BOOL         _sent;
    BOOL         _done;
    BOOL         _gotHeader;

    int          _code;
    NSString    *_message;

    NNTPOnDone   _onDone;
}


+ (NNTPCommand *)command:(NNTPCommandType)type withNNTP:(NNTP *)nntp
                 andArgs:(NSArray *)args onDone:(NNTPOnDone)onDone;
- (NSInteger)send;
- (NSInteger)readHeader:(NSString *)line error:(NSErrorRef *)error;
- (NSInteger)read:(NSErrorRef *)error;

- (void)abort:(NSError *)error;
- (NSInteger)onDone:(NSError *)error;

/* To be inherited */
- (NSInteger)readLine:(NSString *)line error:(NSErrorRef *)error;
@end

@interface NNTPCapabilitiesCommand: NNTPCommand
@end

@interface NNTPCommandGroup : NSObject <NNTPCommand>
{
    @public
    NNTP * __unsafe_unretained _nntp;
    DList *_commands;

    BOOL     _sealed;
    BOOL     _done;
    NSError *_error;

    NNTPOnDone _onDone;
}

+ (NNTPCommandGroup *)root:(NNTP *)nntp;

- (NNTPCommandGroup *)addGroup:(NNTPOnDone)onDone;
- (NNTPCommand *)addCommand:(NNTPCommandType)type andArgs:(NSArray *)args
                     onDone:(NNTPOnDone)onDone;
- (NNTPCommand *)addCommand:(NNTPCommand *)command;
- (void)seal;

- (NSInteger)send;
- (NSInteger)read:(NSErrorRef *)error;
- (void)abort:(NSError *)error;
- (NSInteger)onDone:(NSError *)error;
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
@dynamic isPipelinable, hasPendingRead, hasPendingWrite;

+ (NNTPCommand *)command:(NNTPCommandType)type withNNTP:(NNTP *)nntp
                 andArgs:(NSArray *)args onDone:(NNTPOnDone)onDone
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
    command->_onDone  = onDone;

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

- (BOOL)hasPendingRead
{
    return _sent && !_done;
}

- (BOOL)hasPendingWrite
{
    return !_sent;
}

- (NSInteger)send
{
    if (!_sent && [_nntp->_ostream hasCapacityAvailable:_commandLineLen]) {
        NSLog(@"<< %.*s", (int)_commandLineLen - 2, _commandLine);
        [_nntp->_ostream write:(const uint8_t *)_commandLine
                     maxLength:_commandLineLen];
        _sent = YES;
        return 1;
    }
    return 0;
}

- (NSInteger)error:(NSInteger)code forLine:(NSString *)line error:(NSErrorRef *)error
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

    *error = [NSError errorWithDomain:NNTPErrorDomain code:code userInfo:dict];
    return -1;
}

- (NSInteger)readHeader:(NSString *)line error:(NSErrorRef *)error
{
    if (line.length < 5) {
        return [self error:NNTPProtocoleError forLine:line error:error];
    }

    NSString *code = [line substringToIndex:3];
    NSScanner *scanner = [NSScanner scannerWithString:code];

    [scanner setCharactersToBeSkipped:nil];
    if (![scanner scanInt:&_code] || ![scanner isAtEnd] || _code < 0
        || _code >= 600)
    {
        _code = 0;
        return [self error:NNTPProtocoleError forLine:line error:error];
    }

    _message = [line substringFromIndex:4];
    for (int i = 0; _params->validCodes[i] != 0; i++) {
        if (_params->validCodes[i] == _code) {
            return 0;
        }
    }
    return [self error:NNTPUnexpectedResponseAnswerError forLine:line error:error];
}

- (NSInteger)readLine:(NSString *)line error:(NSErrorRef *)error
{
    [NSException raise:@"unimplemented"
                format:@"not implemented in main class"];
    return -1;
}

- (NSInteger)read:(NSErrorRef *)error
{
    NSString *line;

    while ((line = [_nntp->_istream readLine])) {
        NSLog(@">> %@", line);

        if (!_gotHeader) {
            _gotHeader = YES;

            IGNORE(RETHROW([self readHeader:line error:error]));
            if (!_params->isMultiline) {
                return [self onDone:nil];
            }
        } else if ([line isEqualToString:@"."]) {
            return [self onDone:nil];
        } else {
            NSString *l = line;

            if ([line characterAtIndex:0] == '.') {
                l = [line substringFromIndex:1];
            }
            IGNORE(RETHROW([self readLine:l error:error]));
        }
    }
    return 0;
}

- (BOOL)isPipelinable
{
    return _params->isPipelinable;
}

- (NSInteger)onDone:(NSError *)error
{
    NNTPOnDone cb = _onDone;

    assert (!_done);
    _done   = YES;
    _onDone = nil;
    if (cb) {
        return cb(error);
    }
    return error ? -1 : 0;
}

- (void)abort:(NSError *)error
{
    [self onDone:error];
}

- (NSString *)description
{
    if (_params->type == NNTPConnect) {
        return @"CONNECT";
    } else {
        return [NSString stringWithFormat:@"%.*s", (int)_commandLineLen - 2,
                _commandLine];
    }
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

- (NSInteger)send
{
    NSInteger res = RETHROW([super send]);

    if (res > 0) {
        _nntp->_nntpVersion    = 0;
        _nntp->_implementation = nil;
        _nntp->_capabilities   = 0;
        _nntp->_status         = NNTPConnected;
    }
    return res;
}

- (NSInteger)readLine:(NSString *)line error:(NSErrorRef *)error
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
        return 0;
    } else if ([entry isKindOfClass:[NSNumber class]]) {
        uint64_t v = [(NSNumber *)entry unsignedLongLongValue];

        if (v == NNTPCapVersion) {
            if (![scanner scanInt:&_nntp->_nntpVersion]) {
                return [self error:NNTPInvalidDataError forLine:line error:error];
            }
            return 0;
        } else if (v == NNTPCapImplementation) {
            _nntp->_implementation = [scanner remainder];
            return 0;
        } else {
            _nntp->_capabilities |= v;
            return 0;
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
    return 0;
}
@end


/** Group of commands
 */

@implementation NNTPCommandGroup
@synthesize prev, next, refs;
@dynamic hasPendingRead, hasPendingWrite, isPipelinable;

+ (NNTPCommandGroup *)root:(NNTP *)nntp
{
    NNTPCommandGroup *group = [NNTPCommandGroup new];
    group->_nntp = nntp;
    return group;
}

- (id)init
{
    _commands = [DList new];
    return self;
}

- (NNTPCommandGroup *)addGroup:(NNTPOnDone)onDone
{
    if (_sealed) {
        return nil;
    }
    NNTPCommandGroup *group = [NNTPCommandGroup root:_nntp];
    group->_onDone = onDone;
    [_commands addTail:group];
    return group;
}

- (NNTPCommand *)addCommand:(NNTPCommand *)command
{
    if (_sealed) {
        return nil;
    }
    [_commands addTail:command];
    return command;
}

- (NNTPCommand *)addCommand:(NNTPCommandType)type andArgs:(NSArray *)args
                     onDone:(NNTPOnDone)onDone
{
    if (_sealed) {
        return nil;
    }

    NNTPCommand *command = [NNTPCommand command:type withNNTP:_nntp
                                        andArgs:args onDone:onDone];
    if (!command) {
        return nil;
    }
    return [self addCommand:command];
}

- (void)seal
{
    BOOL needRefresh = NO;
    for (id<NNTPCommand> c in _commands) {
        if ([c isKindOfClass:[NNTPCommandGroup class]]) {
            [(NNTPCommandGroup *)c seal];
            continue;
        }

        NNTPCommand *command = (NNTPCommand *)c;
        if (command->_params->requireCapRefresh) {
            needRefresh = YES;
        } else if (command->_params->type == NNTPCapabilities) {
            needRefresh = NO;
        }
    }

    if (needRefresh) {
        [self addCommand:NNTPCapabilities andArgs:nil onDone:nil];
    }
    _sealed = YES;
}

- (BOOL)hasPendingWrite
{
    for (id<NNTPCommand> command in _commands) {
        if ([command hasPendingWrite]) {
            return YES;
        }
        if (![command isPipelinable]) {
            return NO;
        }
    }
    return NO;
}

- (BOOL)hasPendingRead
{
    for (id<NNTPCommand> command in _commands) {
        if ([command hasPendingRead]) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)isPipelinable
{
    if (!_sealed) {
        return NO;
    }
    return [(id<NNTPCommand>)[_commands tail] isPipelinable];
}

- (NSInteger)send
{
    NSInteger sent = 0;

    for (id<NNTPCommand> command in _commands) {
        if (command.hasPendingWrite) {
            if (!RETHROW([command send])) {
                return sent;
            }
            sent++;
        }
        if (!command.isPipelinable) {
            return sent;
        }
    }
    return sent;
}

- (NSInteger)read:(NSErrorRef *)error
{
    while (YES) {
        id<NNTPCommand> command = (id<NNTPCommand>)_commands.head;

        if (!command) {
            return [self onDone:nil];
        }
        if (!command.hasPendingRead) {
            return 0;
        }

        NSInteger res = [command read:error];
        if (!command.hasPendingRead || res < 0) {
            [_commands popHead];
            if (res < 0) {
                IGNORE(RETHROW([self onDone:*error]));
                [self abort:*error];
                *error = nil;
            }
            [self send];
        } else {
            return 0;
        }
    }
}

- (NSInteger)onDone:(NSError *)error
{
    NNTPOnDone cb = _onDone;

    if (_done) {
        return 0;
    }
    _done   = YES;
    _onDone = nil;
    if (cb) {
        return cb(error);
    }
    return error ? -1 : 0;
}

- (void)abort:(NSError *)error
{
    for (id<NNTPCommand> cmd in _commands) {
        [cmd abort:error];
        if (![cmd hasPendingRead]) {
            [_commands remove:cmd];
        }
    }
    [self onDone:error];
}

- (NSString *)description
{
    NSMutableString *str = [NSMutableString string];
    BOOL first = YES;

    [str appendString:@"("];
    for (id i in _commands) {
        if (!first) {
            [str appendString:@", "];
        }
        first = NO;
        [str appendString:[i description]];
    }
    [str appendString:@")"];
    return str;
}
@end


/** The NNTP interface implements the Stream delegation
 */

@implementation NNTP
@synthesize status = _status;

- (id)init
{
    _commands = [NNTPCommandGroup root:self];
    return self;
}

- (BOOL)sendCommand:(NNTPCommandType)type withArgs:(NSArray *)array
             onDone:(NNTPOnDone)onDone
{
    NNTPCommand *command = [_commands addCommand:type andArgs:array onDone:onDone];
    if (!command) {
        return NO;
    }

    if (command->_params->requireCapRefresh) {
    }
    if (_ostream.hasSpaceAvailable) {
        [_commands send];
    }
    return YES;
}

- (void)sendCommand:(NNTPCommandType)type
{
    [self sendCommand:type withArgs:nil onDone:nil];
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

    _capabilities = NNTPCapModeReader;

    NNTP * __unsafe_unretained weakSelf = self;
    NNTPCommandGroup *group = [_commands addGroup:^NSInteger (NSError *error) {
        if (error) {
            return -1;
        }
        if (weakSelf->_capabilities & NNTPCapReader) {
            weakSelf->_status = NNTPReady;
            return 0;
        }
        return -1;
    }];
    [group addCommand:NNTPConnect andArgs:nil onDone:nil];
    [group addCommand:NNTPModeReader andArgs:nil onDone:nil];
    [group seal];
}

- (void)authenticate:(NSString *)login password:(NSString *)password
{
    NNTP * __unsafe_unretained weakSelf = self;
    NNTPCommandGroup *group = [_commands addGroup:^NSInteger (NSError *error) {
        if (error) {
            [weakSelf.delegate nntp:weakSelf
                        handleEvent:NNTPEventAuthenticationFailed];
        } else {
            [weakSelf.delegate nntp:weakSelf
                        handleEvent:NNTPEventAuthenticated];
        }
        return 0;
    }];

    [group addCommand:NNTPAuthinfoUser andArgs:@[ login] onDone:nil];
    if (password) {
        [group addCommand:NNTPAuthinfoPass andArgs:@[ password ] onDone:nil];
    }
    [group seal];
}

- (void)close
{
    [self sendCommand:NNTPQuit];
}

- (void)streamError:(NSString *)message
{
    NSLog(@"%@", message);
    NSError *error = [NSError errorWithDomain:NNTPErrorDomain
                                         code:NNTPAbortedError
                                     userInfo:nil];
    [_commands abort:error];
    [self.delegate nntp:self handleEvent:NNTPEventError];
    [self close];
}

- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)eventCode
{
    NSErrorRef   error;

    switch (eventCode) {
        case NSStreamEventOpenCompleted:
            _status = NNTPConnected;
            [self.delegate nntp:self handleEvent:NNTPEventConnected];
            break;

        case NSStreamEventHasSpaceAvailable:
            assert (stream == _ostream);
            [_commands send];
            break;

        case NSStreamEventHasBytesAvailable:
            if ([_commands read:&error] && error) {
                [self streamError:@"unhandled error"];
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
