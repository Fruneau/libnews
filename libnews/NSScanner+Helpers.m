//
//  NSScanner+Helpers.m
//  libnews
//
//  Created by Florent Bruneau on 12/08/12.
//  Copyright (c) 2012 Florent Bruneau. All rights reserved.
//

#import "NSScanner+Helpers.h"

@implementation NSScanner (Helpers)
- (NSString *)remainder
{
    return [[self string] substringToIndex:[self scanLocation]];
}
@end
