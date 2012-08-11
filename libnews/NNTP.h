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
    NNTPEventError,
} NNTPEvent;

typedef enum NNTPStatus {
    NNTPDisconnected,
    NNTPConnecting,
    NNTPConnected,
    NNTPError,
} NNTPStatus;

@protocol NNTPDelegate <NSObject>
- (void)nntp:(NNTP *)nntp handleEvent:(NNTPEvent)event;
@end

/** The NNTP class implements RFC3977: Network News Transfer Protocol
 */
@interface NNTP : NSObject
@property(strong)   id<NNTPDelegate> delegate;
@property(readonly) NNTPStatus       status;

- (void)setSync:(NSInteger)timeout;
- (void)setAsync;

- (void)connect:(NSString *)host port:(UInt32)port ssl:(BOOL)ssl;
- (void)close;
@end
