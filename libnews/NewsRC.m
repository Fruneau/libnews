//
//  NewsRC.m
//  libnews
//
//  Created by Florent Bruneau on 29/07/12.
//  Copyright (c) 2012 Florent Bruneau. All rights reserved.
//

#import "NewsRC.h"

@interface NewsRange : NSObject
@property (assign) UInt32 from;
@property (assign) UInt32 to;
@end

@interface NewsGroupRC : NSObject
@property (copy)   NSString       *name;
@property (assign) BOOL            subscribed;
@property (strong) NSMutableArray *ranges;
@end

@interface NewsRC ()
@property (strong) NSMutableDictionary *groups;
@end


@implementation NewsRange
@end

@implementation NewsGroupRC
- (id)initWithName:(NSString *)n
{
    self.name       = n;
    self.subscribed = NO;
    self.ranges     = [NSMutableArray new];
    return self;
}
@end

@implementation NewsRC

- (id)init
{
    self.groups = [NSMutableDictionary new];
    return self;
}

- (NewsGroupRC *)getOrCreateGroup:(NSString *)name
{
    NewsGroupRC *group = self.groups[name];

    if (group == nil) {
        group = [[NewsGroupRC alloc] initWithName:name];
        self.groups[group.name] = group;
    }
    return group;
}

- (BOOL)subscribe:(NSString *)name
{
    NewsGroupRC *group = [self getOrCreateGroup:name];
    BOOL res = NO;
    
    res = group.subscribed;
    group.subscribed = YES;
    return res;
}

- (BOOL)unsubscribe:(NSString *)name
{
    NewsGroupRC *group = self.groups[name];
    BOOL res = NO;
    
    if (group == nil) {
        return NO;
    }
    res = group.subscribed;
    group.subscribed = NO;
    return res;
}

- (BOOL)isSubcribed:(NSString *)name
{
    NewsGroupRC *group = self.groups[name];
    
    if (group == nil) {
        return NO;
    }
    return group.subscribed;
}

#define SWAP(a, b)  do {                                                     \
        typeof(a) const __tmp = a;                                           \
        a = b;                                                               \
        b = __tmp;                                                           \
    } while (0)

- (BOOL)isMarkedAsRead:(NSString *)name article:(UInt32)article
{
    NewsGroupRC *group = self.groups[name];
    if (group == nil) {
        return NO;
    }

    NSUInteger idx;
    NSRange range = { .location = 0, .length = group.ranges.count };
    
    idx = [group.ranges indexOfObject:group
                        inSortedRange:range
                              options:NSBinarySearchingFirstEqual
                      usingComparator:^(id obj1, id obj2) {
                          NewsRange *elt = (NewsRange *)obj1;
                          
                          if (article < elt.from) {
                              return (NSComparisonResult)NSOrderedDescending;
                          } else if (elt.to < article) {
                              return (NSComparisonResult)NSOrderedAscending;
                          }
                          return (NSComparisonResult)NSOrderedSame;
                      }];
    return idx != NSNotFound;
}

- (void)markAsRead:(NSString *)name from:(UInt32)from to:(UInt32)to
{
    NewsGroupRC *group = [self getOrCreateGroup:name];
    const NSUInteger count = group.ranges.count;
    NSUInteger idx;
    NewsRange *entry;
    NSRange range = { .location = 0, .length = count };

    if (to < from) {
        SWAP(from, to);
    }
    
    idx = [group.ranges indexOfObject:group
                        inSortedRange:range
                              options:NSBinarySearchingInsertionIndex | NSBinarySearchingFirstEqual
                      usingComparator:^(id obj1, id obj2) {
                          NewsRange *elt = (NewsRange *)obj1;
                          
                          if (to + 1 < elt.from) {
                              return (NSComparisonResult)NSOrderedDescending;
                          } else if (from > elt.to + 1) {
                              return (NSComparisonResult)NSOrderedAscending;
                          }
                          return (NSComparisonResult)NSOrderedSame;
                      }];
    
    if (idx == count) {
        entry = [NewsRange new];
        entry.from = from;
        entry.to   = to;
        group.ranges[count]= entry;
        return;
    }
    
    entry = group.ranges[idx];
    if (to + 1 < entry.from || from > entry.to + 1) {
        entry = [NewsRange new];
        entry.from = from;
        entry.to   = to;
        [group.ranges insertObject:entry atIndex:idx];
        return;
    }
    
    entry.from = MIN(entry.from, from);
    if (entry.to >= to) {
        return;
    }
    
    range.location = idx + 1;
    range.length  -= idx + 1;
    idx = [group.ranges indexOfObject:group
                        inSortedRange:range
                              options:NSBinarySearchingLastEqual
                      usingComparator:^(id obj1, id obj2) {
                          NewsRange *elt = (NewsRange *)obj1;
                          
                          if (to + 1 >= elt.from) {
                              return (NSComparisonResult)NSOrderedSame;
                          } else if (to < elt.from) {
                              return (NSComparisonResult)NSOrderedDescending;
                          }
                          return (NSComparisonResult)NSOrderedAscending;
                      }];
    if (idx != NSNotFound) {
        NewsRange *end = group.ranges[idx];
        
        if (to + 1 >= end.from) {
            to = end.to;
        } else {
            idx--;
        }
        range.length = idx - range.location + 1;
        [group.ranges removeObjectsInRange:range];
    }
    entry.to = to;
}


- (void)markAsRead:(NSString *)group article:(UInt32)from
{
    [self markAsRead:group from:from to:from];
}

- (void)markAsUnread:(NSString *)name from:(UInt32)from to:(UInt32)to
{
    NewsGroupRC *group = self.groups[name];
    if (group == nil) {
        return;
    }
    if (to < from) {
        SWAP(from, to);
    }
    
    const NSUInteger count = group.ranges.count;
    NSUInteger start, end;
    NewsRange *first_entry;
    NewsRange *last_entry;
    NSRange range = { .location = 0, .length = count };
    NSComparator cmp = ^(id obj1, id obj2) {
        NewsRange *elt = (NewsRange *)obj1;
        
        if (to < elt.from) {
            return (NSComparisonResult)NSOrderedDescending;
        } else if (from > elt.to) {
            return (NSComparisonResult)NSOrderedDescending;
        }
        return (NSComparisonResult)NSOrderedSame;
    };
    
    start = [group.ranges indexOfObject:group
                          inSortedRange:range
                                options:NSBinarySearchingFirstEqual
                        usingComparator:cmp];
    if (start == NSNotFound) {
        return;
    }
    
    first_entry = group.ranges[start];
    if (first_entry.to >= to) {
        if (from > first_entry.from && to < first_entry.to) {
            last_entry = [NewsRange new];
            last_entry.from = to + 1;
            last_entry.to   = first_entry.to;
            [group.ranges insertObject:last_entry atIndex:start + 1];
            first_entry.to = from - 1;
            return;
        }
        end = start;
    } else {
        range.location = start + 1;
        range.length  -= start + 1;
        end = [group.ranges indexOfObject:group
                            inSortedRange:range
                                  options:NSBinarySearchingLastEqual
                          usingComparator:cmp];
        if (end == NSNotFound) {
            end = start;
        }
    }
    
    last_entry = group.ranges[end];
    if (from > first_entry.from) {
        first_entry.to = from - 1;
        start++;
    }
    if (to < last_entry.to) {
        last_entry.from = to + 1;
    } else {
        end++;
    }
    if (start < end) {
        range.location = start;
        range.length   = end - start;
        [group.ranges removeObjectsInRange:range];
    }
}

- (void)markAsUnread:(NSString *)group article:(UInt32)from
{
    [self markAsUnread:group from:from to:from];
}

- (void)appendNewsRC:(NSMutableString *)outs forGroup:(NewsGroupRC *)group withName:(NSString *)name
{
    BOOL first = YES;

    if (group == nil) {
        [outs appendFormat:@"%@!", name];
        return;
    }

    [outs appendFormat:@"%@%c", name, group.subscribed ? ':' : '!'];
    for (NewsRange *range in group.ranges) {
        if (!first) {
            [outs appendString:@","];
        }
        first = NO;
        if (range.from == range.to) {
            [outs appendFormat:@"%u", range.from];
        } else {
            [outs appendFormat:@"%u-%u", range.from, range.to];
        }
    }    
}

- (NSString *)getNewsRCForGroup:(NSString *)name
{
    NSMutableString *string = [NSMutableString stringWithCapacity:64];
    
    [self appendNewsRC:string forGroup:self.groups[name] withName:name];
    return string;
}

- (NSString *)getNewsRC
{
    NSMutableString *string = [NSMutableString stringWithCapacity:1024];
    
    [self.groups enumerateKeysAndObjectsUsingBlock:^(id key, id obj,
                                                     BOOL *stop) {
        [self appendNewsRC:string forGroup:obj withName:key];
        [string appendString:@"\n"];
    }];
    return string;
}

- (NSString *)description
{
    NSMutableString *string = [NSMutableString stringWithCapacity:1024];
    
    [self.groups enumerateKeysAndObjectsUsingBlock:^(id key, id obj,
                                                     BOOL *stop) {
        [self appendNewsRC:string forGroup:obj withName:key];
        [string appendString:@"; "];
    }];
    return string; 
}
@end
