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
    node.next = next;
    if (next == nil || [next isKindOfClass:[DList class]]) {
        node.refs = nil;
    } else {
        node.refs = next;
    }
}

static void addNode(id<DListNode> node, id<DListNode> prev, id<DListNode> next)
{
    next.prev = node;
    setNextNode(node, next);
    node.prev = prev;
    setNextNode(prev, node);
}

static void removeNode(id<DListNode> prev, id<DListNode> next)
{
    setNextNode(prev, next);
    next.prev = prev;
}

static void detachNode(id<DListNode> node)
{
    node.prev = nil;
    setNextNode(node, nil);
}


/* Interfaces */

@interface DListEnumerator : NSEnumerator
@property (assign) DList *list;
@property (assign) id<DListNode> next;
@property (assign) BOOL reverse;

- (id)initWithDList:(DList *)dlist reverse:(BOOL)reverse;
@end

@interface DList () <DListNode>
@end


/* Implementations */

@implementation DListEnumerator
-(id)initWithDList:(DList *)list reverse:(BOOL)reverse
{
    self.list    = list;
    self.reverse = reverse;
    if (reverse) {
        self.next = list.prev;
    } else {
        self.next = list.next;
    }
    return self;
}

- (id)nextObject
{
    id<DListNode> current = self.next;

    if (current == self.list) {
        return nil;
    }
    if (self.reverse) {
        self.next = current.prev;
    } else {
        self.next = current.next;
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
    self.prev = self.next = self;
    return self;
}

- (BOOL)isEmpty
{
    return self.next == self;
}

- (BOOL)isSingular
{
    return self.next != self && self.prev == self.next;
}

- (BOOL)isEmptyOrSingular
{
    return self.prev == self.next;
}

- (id<DListNode>)head
{
    if ([self isEmpty]) {
        return nil;
    }
    return self.next;
}

- (id<DListNode>)tail
{
    if ([self isEmpty]) {
        return nil;
    }
    return self.prev;
}

- (BOOL)isHead:(id<DListNode>)node
{
    return node == self.next;
}

- (BOOL)isTail:(id<DListNode>)node
{
    return node == self.prev;
}

- (void)addHead:(id<DListNode>)node
{
    addNode(node, self, self.next);
}

- (void)addTail:(id<DListNode>)node
{
    addNode(node, self.prev, self);
}

- (void)add:(id<DListNode>)node before:(id<DListNode>)otherNode
{
    addNode(node, otherNode.prev, otherNode);
}

- (void)add:(id<DListNode>)node after:(id<DListNode>)otherNode
{
    addNode(node, otherNode, otherNode.next);
}

- (void)moveToHead:(id<DListNode>)node
{
    if (node == self.next) {
        return;
    }
    [self remove:node];
    [self addHead:node];
}

- (void)moveToTail:(id<DListNode>)node
{
    if (node == self.prev) {
        return;
    }
    [self remove:node];
    [self addTail:node];
}

- (id<DListNode>)popHead
{
    id<DListNode> node = self.next;
    
    if (node == self) {
        return nil;
    }
    [self remove:node];
    detachNode(node);
    return node;
}

- (id<DListNode>)popTail
{
    id<DListNode> node = self.prev;
    
    if (node == self) {
        return nil;
    }
    [self remove:node];
    detachNode(node);
    return node;
}

- (id<DListNode>)remove:(id<DListNode>)node
{
    removeNode(node.prev, node.next);
    detachNode(node);
    return node;
}

- (void)clear
{
    if ([self isEmpty]) {
        return;
    }

    id<DListNode> head = self.head;
    self.prev = self.next = self;
    self.refs = nil;

    /* Traversing the list is not strictly needed since we already removed the
     * reference to the head, but it ensures the prev/next pointers are not
     * fucked up
     */
    while (head != self) {
        id<DListNode> tmp = head.next;
        head.prev = head.next = head.refs = nil;
        head = tmp;
    }
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
        node = self.next;
    } else {
        assert (state->state == 1);
        assert (state->itemsPtr == buffer);
        node = buffer[len];
    }
    
    assert (len > 0);
    while (res < len && node != self) {
        buffer[res++] = node;
        node = node.next;
    }
    buffer[len] = node;
    return res;
}

- (NSString *)description
{
    NSMutableString *str = [NSMutableString string];
    id<DListNode> node = self.next;
    
    [str appendFormat:@"%p:[%p;%p] ", self, self.prev, self.next];
    while (node != self) {
        [str appendFormat:@"%p:[%p;%p] <-> ", node, node.prev, node.next];
        node = node.next;
    }
    return str;
}
@end
