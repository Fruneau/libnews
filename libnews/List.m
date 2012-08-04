//
//  List.m
//  libnews
//
//  Created by Florent Bruneau on 04/08/12.
//  Copyright (c) 2012 Florent Bruneau. All rights reserved.
//

#import "List.h"

/* Helpers */

static void setNextNode(id<DListNode> node, id<DListNode> next)
{
    [node setNext:next];
    if (next == nil || [next isMemberOfClass:[DList class]]) {
        [node setRefs:nil];
    } else {
        [node setRefs:next];
    }
}

static void addNode(id<DListNode> node, id<DListNode> prev, id<DListNode> next)
{
    [next setPrev:node];
    setNextNode(node, next);
    [node setPrev:prev];
    setNextNode(prev, node);
}

static void removeNode(id<DListNode> prev, id<DListNode> next)
{
    setNextNode(prev, next);
    [prev setNext:next];
}

static void detachNode(id<DListNode> node)
{
    [node setPrev:nil];
    setNextNode(node, nil);
}


/* Interfaces */

@interface DListEnumerator : NSEnumerator
{
    @private
    DList         *list;
    id<DListNode>  next;
    BOOL           reverse;
}
- (id)initWithDList:(DList *)dlist reverse:(BOOL)reverse;
@end

@interface DList (Private) <DListNode>
@end


/* Implementations */

@implementation DListEnumerator
-(id)initWithDList:(DList *)dlist reverse:(BOOL)dreverse
{
    list    = dlist;
    reverse = dreverse;
    if (reverse) {
        next = [list prev];
    } else {
        next = [list next];
    }
    return self;
}

- (id)nextObject
{
    id<DListNode> current = next;

    if (current == list) {
        return nil;
    }
    if (reverse) {
        next = [current prev];
    } else {
        next = [current next];
    }
    return current;
}
@end


/* DList implementation */

@implementation DList
@synthesize prev;
@synthesize next;
@synthesize refs;

- (id)init
{
    prev = next = self;
    refs = nil;
    return self;
}

- (BOOL)isEmpty
{
    return next == self;
}

- (BOOL)isSingular
{
    return next != self && prev == next;
}

- (BOOL)isEmptyOrSingular
{
    return prev == next;
}

- (id<DListNode>)head
{
    if ([self isEmpty]) {
        return nil;
    }
    return next;
}

- (id<DListNode>)tail
{
    if ([self isEmpty]) {
        return nil;
    }
    return prev;
}

- (BOOL)isHead:(id<DListNode>)node
{
    return node == next;
}

- (BOOL)isTail:(id<DListNode>)node
{
    return node == prev;
}

- (void)addHead:(id<DListNode>)node
{
    addNode(node, self, next);
}

- (void)addTail:(id<DListNode>)node
{
    addNode(node, prev, self);
}

- (void)add:(id<DListNode>)node before:(id<DListNode>)otherNode
{
    addNode(node, [otherNode prev], otherNode);
}

- (void)add:(id<DListNode>)node after:(id<DListNode>)otherNode
{
    addNode(node, otherNode, [otherNode next]);
}

- (void)moveToHead:(id<DListNode>)node
{
    if (node == next) {
        return;
    }
    [self remove:node];
    [self addHead:node];
}

- (void)moveToTail:(id<DListNode>)node
{
    if (node == prev) {
        return;
    }
    [self remove:node];
    [self addTail:node];
}

- (id<DListNode>)popHead
{
    id<DListNode> node = next;
    
    if (node == self) {
        return nil;
    }
    [self remove:node];
    detachNode(node);
    return node;
}

- (id<DListNode>)popTail
{
    id<DListNode> node = prev;
    
    if (node == self) {
        return nil;
    }
    [self remove:node];
    detachNode(node);
    return node;
}

- (id<DListNode>)remove:(id<DListNode>)node
{
    removeNode([node prev], [node next]);
    detachNode(node);
    return node;
}

- (NSEnumerator *)nodeEnumerator
{
    return [[DListEnumerator alloc] initWithDList:self reverse:NO];
}

- (NSEnumerator *)reverseNodeEnumerator
{
    return [[DListEnumerator alloc] initWithDList:self reverse:YES];
}

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state
                                  objects:(__unsafe_unretained id [])buffer
                                    count:(NSUInteger)len
{
    NSUInteger res = 0;
    __unsafe_unretained id<DListNode> node = nil;
    
    len--;
    if (state->state == 0) {
        state->state        = 1;
        state->itemsPtr     = buffer;
        state->mutationsPtr = &state->extra[0];
        node = next;
    } else {
        assert (state->state == 1);
        assert (state->itemsPtr == buffer);
        node = buffer[len];
    }
    
    assert (len > 0);
    while (res < len && node != self) {
        buffer[res++] = node;
        node = [node next];
    }
    buffer[len] = node;
    return res;
}
@end
