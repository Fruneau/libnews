//
//  NNTP.h
//  libnews
//
//  Created by Florent Bruneau on 02/08/12.
//  Copyright (c) 2012 Florent Bruneau. All rights reserved.
//

#import <Foundation/Foundation.h>

@class NNTP;

typedef enum NNTPEvent {
    NNTPEventConnected,
    NNTPEventDisconnected,
    NNTPEventAuthenticated,
    NNTPEventAuthenticationFailed,
    NNTPEventError,
} NNTPEvent;

typedef enum NNTPStatus {
    NNTPDisconnected,
    NNTPConnecting,
    NNTPConnected,
    NNTPNeedAuth,
    NNTPReady,
    NNTPReadOnly,
    NNTPError,
} NNTPStatus;

extern NSString * const NNTPErrorDomain;
extern NSString * const NNTPConnectionKey;
extern NSString * const NNTPCommandKey;
extern NSString * const NNTPReplyLineKey;
extern NSString * const NNTPReplyCodeKey;
extern NSString * const NNTPReplyMessageKey;

enum NNTPErrorCode {
    NNTPTemporaryError,
    NNTPPermanentError,
    NNTPUnexpectedResponseAnswerError,
    NNTPProtocoleError,
    NNTPInvalidDataError,
    NNTPUnsupportedCommandError,
    NNTPAbortedError,
    NNTPAuthFailedError,
};

@protocol NNTPDelegate <NSObject>
- (void)nntp:(NNTP *)nntp handleEvent:(NNTPEvent)event;
@end

/** The NNTP class implements RFC3977: Network News Transfer Protocol
 */
@interface NNTP : NSObject
@property(strong)   id<NNTPDelegate> delegate;
@property(readonly) NNTPStatus       status;

- (void)connect:(NSString *)host port:(UInt32)port ssl:(BOOL)ssl;
- (void)authenticate:(NSString *)login password:(NSString *)password;
- (void)close;
@end
