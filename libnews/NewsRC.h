//
//  NewsRC.h
//  libnews
//
//  Created by Florent Bruneau on 29/07/12.
//  Copyright (c) 2012 Florent Bruneau. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NewsRC : NSObject
{
    @private
    NSMutableDictionary *groups;
}

- (id)init;

- (BOOL)subscribe:(NSString *)group;
- (BOOL)unsubscribe:(NSString *)group;
- (BOOL)isSubcribed:(NSString *)group;

- (BOOL)isMarkedAsRead:(NSString *)group article:(UInt32)article;
- (void)markAsRead:(NSString *)group article:(UInt32)article;
- (void)markAsRead:(NSString *)group from:(UInt32)from to:(UInt32)to;
- (void)markAsUnread:(NSString *)group article:(UInt32)article;
- (void)markAsUnread:(NSString *)group from:(UInt32)from to:(UInt32)to;

- (NSString *)getNewsRCForGroup:(NSString *)group;
- (NSString *)getNewsRC;
@end
