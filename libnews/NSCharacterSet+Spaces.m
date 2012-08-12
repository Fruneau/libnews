//
//  NSCharacterSet+Spaces.m
//  libnews
//
//  Created by Florent Bruneau on 12/08/12.
//  Copyright (c) 2012 Florent Bruneau. All rights reserved.
//

#import "NSCharacterSet+Spaces.h"

NSCharacterSet *spaceSet;

@implementation NSCharacterSet (Spaces)
+ (NSCharacterSet *)spaceCharacter
{
    if (!spaceSet) {
        spaceSet = [NSCharacterSet characterSetWithCharactersInString:@" "];
    }
    return spaceSet;
}
@end
