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
    NNTPConnected,
    NNTPDisconnected,
    NNTPError,
} NNTPStatus;

@protocol NNTPDelegate <NSObject>
- (void)nntp:(NNTP *)nntp handleEvent:(NNTPEvent)event;
@end


@interface NNTPCommand : NSObject
@end

/** The NNTP class implements RFC3977: Network News Transfer Protocol
 */
@interface NNTP : NSObject
@property           id<NNTPDelegate> delegate;
@property(readonly) NNTPStatus       status;

+ (NNTP *)connectTo:(NSString *)host port:(UInt32)port ssl:(BOOL)ssl;
+ (NNTP *)connectSyncTo:(NSString *)host port:(UInt32)port ssl:(BOOL)ssl
             beforeDate:(NSDate *)date;

- (void)close;
@end
