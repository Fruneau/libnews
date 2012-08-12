//
//  NNTPTest.m
//  libnews
//
//  Created by Florent Bruneau on 03/08/12.
//  Copyright (c) 2012 Florent Bruneau. All rights reserved.
//

#import "NNTPTest.h"
#import "NNTP.h"
#import "NSRunLoop+Sync.h"

static BOOL runUntilStatus(NNTP *nntp, NNTPStatus status)
{
    NSRunLoop *loop = [NSRunLoop currentRunLoop];
    return [loop runUntilTimeout:10
                     orCondition:^BOOL (void) {
                         return nntp.status == status;
                     }];
}

@implementation NNTPTest
- (void)testConnect
{
    NNTP *nntp = [NNTP new];
    [nntp connect:@"news.intersec.com" port:563 ssl:YES];
    STAssertTrue(runUntilStatus(nntp, NNTPReady), @"cannot connect");

    [nntp close];
    STAssertTrue(runUntilStatus(nntp, NNTPDisconnected), @"cannot disconnect");
}
@end
