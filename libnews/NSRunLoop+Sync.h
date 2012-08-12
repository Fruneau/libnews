//
//  NSRunLoop+Sync.h
//  libnews
//
//  Created by Florent Bruneau on 12/08/12.
//  Copyright (c) 2012 Florent Bruneau. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSRunLoop (Sync)
- (BOOL)runUntilDate:(NSDate *)date orCondition:(BOOL (^)(void))condition;
- (BOOL)runUntilTimeout:(NSTimeInterval)to orCondition:(BOOL (^)(void))condition;
@end
