//
//  List.h
//  libnews
//
//  Created by Florent Bruneau on 04/08/12.
//  Copyright (c) 2012 Florent Bruneau. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol DListNode <NSObject>
@property(assign) id<DListNode> prev;
@property(assign) id<DListNode> next;
@property(strong) id<DListNode> refs;
@end

@interface DList : NSObject <NSFastEnumeration>
- (BOOL)isEmpty;
- (BOOL)isSingular;
- (BOOL)isEmptyOrSingular;

- (id<DListNode>)head;
- (id<DListNode>)tail;
- (BOOL)isHead:(id<DListNode>)node;
- (BOOL)isTail:(id<DListNode>)node;

- (void)addHead:(id<DListNode>)node;
- (void)addTail:(id<DListNode>)node;
- (void)add:(id<DListNode>)node before:(id<DListNode>)otherNode;
- (void)add:(id<DListNode>)node after:(id<DListNode>)otherNode;
- (void)moveToHead:(id<DListNode>)node;
- (void)moveToTail:(id<DListNode>)node;

- (id<DListNode>)popHead;
- (id<DListNode>)popTail;
- (id<DListNode>)remove:(id<DListNode>)node;

- (NSEnumerator *)nodeEnumerator;
- (NSEnumerator *)reverseNodeEnumerator;
@end
