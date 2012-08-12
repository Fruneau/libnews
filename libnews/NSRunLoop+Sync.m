//
//  NSRunLoop+Sync.m
//  libnews
//
//  Created by Florent Bruneau on 12/08/12.
//  Copyright (c) 2012 Florent Bruneau. All rights reserved.
//

#import "NSRunLoop+Sync.h"

@implementation NSRunLoop (Sync)
- (BOOL)runUntilDate:(NSDate *)date orCondition:(BOOL (^)(void))condition
{
    BOOL cond;

    while (!(cond = condition())
    && [date compare:[NSDate date]] == NSOrderedDescending)
    {
        [self runMode:NSDefaultRunLoopMode beforeDate:date];
    }

    return cond;
}

- (BOOL)runUntilTimeout:(NSTimeInterval)to orCondition:(BOOL (^)(void))condition
{
    NSDate *date = [NSDate dateWithTimeIntervalSinceNow:to];
    return [self runUntilDate:date orCondition:condition];
}
@end
