//
//  NNTPTest.m
//  libnews
//
//  Created by Florent Bruneau on 03/08/12.
//  Copyright (c) 2012 Florent Bruneau. All rights reserved.
//

#import "NNTPTest.h"
#import "NNTP.h"

@implementation NNTPTest
- (void)testConnect
{
    NNTP *nntp = [NNTP connectSyncTo:@"news.intersec.com"
                                port:563
                                 ssl:YES
                          beforeDate:[NSDate dateWithTimeIntervalSinceNow:10]];

    STAssertNotNil(nntp, @"");
}

@end
