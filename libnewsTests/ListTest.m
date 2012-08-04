//
//  ListTest.m
//  libnews
//
//  Created by Florent Bruneau on 04/08/12.
//  Copyright (c) 2012 Florent Bruneau. All rights reserved.
//

#import "ListTest.h"
#import "List.h"

@interface DListNodeTest : NSObject <DListNode>
@property UInt32 data;
+ (DListNodeTest *)newWithData:(UInt32)d;
@end

@implementation  DListNodeTest
@synthesize prev;
@synthesize next;
@synthesize refs;
@synthesize data;

+ (DListNodeTest *)newWithData:(UInt32)d
{
    DListNodeTest *node = [DListNodeTest new];
    [node setData:d];
    return node;
}
@end

@implementation ListTest
- (void)testDList
{
    DList *list = [DList new];
    UInt32 pos = 0;
    

    STAssertTrue([list isEmpty], @"");
    STAssertFalse([list isSingular], @"");
    STAssertTrue([list isEmptyOrSingular], @"");
    STAssertNil([list head], @"");
    STAssertNil([list tail], @"");

    [list addHead:[DListNodeTest newWithData:0]];
    for (DListNodeTest *node in list) {
        STAssertEquals([node data], pos, @"");
        pos++;
    }
    STAssertEquals(pos, 1u, @"");

    STAssertFalse([list isEmpty], @"");
    STAssertTrue([list isSingular], @"");
    STAssertTrue([list isEmptyOrSingular], @"");
    STAssertNotNil([list head], @"");
    STAssertNotNil([list tail], @"");
    STAssertEquals([list head], [list tail], @"");
    STAssertEquals([(DListNodeTest *)[list head] data], 0u, @"");

    [list addTail:[DListNodeTest newWithData:1]];
    pos = 0;
    for (DListNodeTest *node in list) {
        STAssertEquals([node data], pos, @"");
        pos++;
    }
    STAssertEquals(pos, 2u, @"");

    STAssertFalse([list isEmpty], @"");
    STAssertFalse([list isSingular], @"");
    STAssertFalse([list isEmptyOrSingular], @"");
    STAssertNotNil([list head], @"");
    STAssertNotNil([list tail], @"");
    STAssertEquals([(DListNodeTest *)[list head] data], 0u, @"");
    STAssertEquals([(DListNodeTest *)[list tail] data], 1u, @"");
    
    [list addHead:[DListNodeTest newWithData:2]];
    pos = 0;
    for (DListNodeTest *node in list) {
        if (pos == 0) {
            STAssertEquals([node data], 2u, @"");
        } else if (pos == 1) {
            STAssertEquals([node data], 0u, @"");
        } else {
            STAssertEquals([node data], 1u, @"");
        }
        pos++;
    }
    STAssertEquals(pos, 3u, @"");
    
    STAssertFalse([list isEmpty], @"");
    STAssertFalse([list isSingular], @"");
    STAssertFalse([list isEmptyOrSingular], @"");
    STAssertNotNil([list head], @"");
    STAssertNotNil([list tail], @"");
    STAssertEquals([(DListNodeTest *)[list head] data], 2u, @"");
    STAssertEquals([(DListNodeTest *)[[list head] next] data], 0u, @"");
    STAssertEquals([(DListNodeTest *)[list tail] data], 1u, @"");
    STAssertEquals([(DListNodeTest *)[[list tail] prev] data], 0u, @"");
    
    [list remove:[[list head] next]];
    pos = 0;
    for (DListNodeTest *node in list) {
        STAssertEquals([node data], 2 - pos, @"");
        pos++;
    }
    STAssertEquals(pos, 2u, @"");
    STAssertEquals([(DListNodeTest *)[list popHead] data], 2u, @"");
    STAssertTrue([list isSingular], @"");
}
@end
