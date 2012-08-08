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
    NNTP *nntp = [NNTP new];
    [nntp setSync:10];
    [nntp connect:@"news.intersec.com" port:563 ssl:YES];

    STAssertEquals([nntp status], NNTPConnected, @"cannot connect");
    [nntp close];
    
}

@end
