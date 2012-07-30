//
//  NewsRCTest.m
//  libnews
//
//  Created by Florent Bruneau on 29/07/12.
//  Copyright (c) 2012 Florent Bruneau. All rights reserved.
//

#import "NewsRCTest.h"
#import "NewsRC.h"

@implementation NewsRCTest
- (void)testSubscription
{
    NewsRC *rc = [NewsRC new];
    
    STAssertFalse([rc isSubcribed:@"toto"], @"");
    STAssertFalse([rc isSubcribed:@"tata"], @"");
    STAssertFalse([rc isSubcribed:@"titi"], @"");

    [rc subscribe:@"tata"];
    STAssertFalse([rc isSubcribed:@"toto"], @"");
    STAssertTrue([rc isSubcribed:@"tata"], @"");
    STAssertFalse([rc isSubcribed:@"titi"], @"");
    [rc subscribe:@"toto"];
    STAssertTrue([rc isSubcribed:@"toto"], @"");
    STAssertTrue([rc isSubcribed:@"tata"], @"");
    STAssertFalse([rc isSubcribed:@"titi"], @"");
    [rc subscribe:@"toto"];
    STAssertTrue([rc isSubcribed:@"toto"], @"");
    STAssertTrue([rc isSubcribed:@"tata"], @"");
    STAssertFalse([rc isSubcribed:@"titi"], @"");

    [rc unsubscribe:@"tata"];
    STAssertTrue([rc isSubcribed:@"toto"], @"");
    STAssertFalse([rc isSubcribed:@"tata"], @"");
    STAssertFalse([rc isSubcribed:@"titi"], @"");
    [rc unsubscribe:@"tata"];
    STAssertTrue([rc isSubcribed:@"toto"], @"");
    STAssertFalse([rc isSubcribed:@"tata"], @"");
    STAssertFalse([rc isSubcribed:@"titi"], @"");
    [rc unsubscribe:@"toto"];
    STAssertFalse([rc isSubcribed:@"toto"], @"");
    STAssertFalse([rc isSubcribed:@"tata"], @"");
    STAssertFalse([rc isSubcribed:@"titi"], @"");
}

- (void)testMarkRead
{
    NewsRC *rc = [NewsRC new];
    
    for (int i = 0; i < 10; i++) {
        STAssertFalse([rc isMarkedAsRead:@"toto" article:i], @"");
    }
    [rc markAsRead:@"toto" article:1];
    for (int i = 0; i < 10; i++) {
        if (i == 1) {
            STAssertTrue([rc isMarkedAsRead:@"toto" article:i], @"");
        } else {
            STAssertFalse([rc isMarkedAsRead:@"toto" article:i], @"");            
        }
    }

    [rc markAsRead:@"toto" article:1];
    for (int i = 0; i < 10; i++) {
        if (i == 1) {
            STAssertTrue([rc isMarkedAsRead:@"toto" article:i], @"");
        } else {
            STAssertFalse([rc isMarkedAsRead:@"toto" article:i], @"");
        }
    }

    [rc markAsRead:@"toto" article:2];
    for (int i = 0; i < 10; i++) {
        if (i == 1 || i == 2) {
            STAssertTrue([rc isMarkedAsRead:@"toto" article:i], @"");
        } else {
            STAssertFalse([rc isMarkedAsRead:@"toto" article:i], @"");
        }
    }
    
    [rc markAsRead:@"toto" article:4];
    for (int i = 0; i < 10; i++) {
        if (i == 1 || i == 2 || i == 4) {
            STAssertTrue([rc isMarkedAsRead:@"toto" article:i], @"");
        } else {
            STAssertFalse([rc isMarkedAsRead:@"toto" article:i], @"");
        }
    }
    
    
    [rc markAsRead:@"toto" article:5];
    for (int i = 0; i < 10; i++) {
        if (i == 1 || i == 2 || i == 4 || i == 5) {
            STAssertTrue([rc isMarkedAsRead:@"toto" article:i], @"");
        } else {
            STAssertFalse([rc isMarkedAsRead:@"toto" article:i], @"");
        }
    }

    [rc markAsRead:@"toto" from:2 to:4];
    for (int i = 0; i < 10; i++) {
        if (i == 1 || i == 2 || i == 3 || i == 4 || i == 5)
        {
            STAssertTrue([rc isMarkedAsRead:@"toto" article:i], @"");
        } else {
            STAssertFalse([rc isMarkedAsRead:@"toto" article:i], @"");
        }
    }
    
    [rc markAsRead:@"toto" from:6 to:7];
    for (int i = 0; i < 10; i++) {
        if (i >= 1 && i <= 7) {
            STAssertTrue([rc isMarkedAsRead:@"toto" article:i], @"");
        } else {
            STAssertFalse([rc isMarkedAsRead:@"toto" article:i], @"");
        }
    }
    
    [rc markAsRead:@"toto" article:9];
    for (int i = 0; i < 10; i++) {
        if ((i >= 1 && i <= 7) || i == 9) {
            STAssertTrue([rc isMarkedAsRead:@"toto" article:i], @"");
        } else {
            STAssertFalse([rc isMarkedAsRead:@"toto" article:i], @"");
        }
    }

    [rc markAsRead:@"toto" from:0 to:8];
    for (int i = 0; i < 10; i++) {
        STAssertTrue([rc isMarkedAsRead:@"toto" article:i], @"");
    }
}

- (void)testMarkUnread
{
    NewsRC *rc = [NewsRC new];
    
    [rc markAsRead:@"toto" article:1];
    [rc markAsRead:@"toto" from:3 to:5];
    [rc markAsRead:@"toto" from:7 to:8];
    [rc markAsRead:@"toto" article:10];
    [rc markAsRead:@"toto" from:12 to:13];
    [rc markAsRead:@"toto" from:15 to:17];
    for (int i = 0; i < 20; i++) {
        if (i == 1 || i == 3 || i == 4 || i == 5 || i == 7 || i == 8
            || i == 10 || i == 12 || i == 13 || i == 15 || i == 16 || i == 17)
        {
            STAssertTrue([rc isMarkedAsRead:@"toto" article:i], @"");
        } else {
            STAssertFalse([rc isMarkedAsRead:@"toto" article:i], @"");
        }
    }
    
    [rc markAsUnread:@"toto" article:0];
    for (int i = 0; i < 20; i++) {
        if (i == 1 || i == 3 || i == 4 || i == 5 || i == 7 || i == 8
            || i == 10 || i == 12 || i == 13 || i == 15 || i == 16 || i == 17)
        {
            STAssertTrue([rc isMarkedAsRead:@"toto" article:i], @"");
        } else {
            STAssertFalse([rc isMarkedAsRead:@"toto" article:i], @"");
        }
    }
    
    [rc markAsUnread:@"toto" article:1];
    for (int i = 0; i < 20; i++) {
        if (i == 3 || i == 4 || i == 5 || i == 7 || i == 8
            || i == 10 || i == 12 || i == 13 || i == 15 || i == 16 || i == 17)
        {
            STAssertTrue([rc isMarkedAsRead:@"toto" article:i], @"");
        } else {
            STAssertFalse([rc isMarkedAsRead:@"toto" article:i], @"");
        }
    }
    
    [rc markAsUnread:@"toto" from:1 to:3];
    for (int i = 0; i < 20; i++) {
        if (i == 4 || i == 5 || i == 7 || i == 8
            || i == 10 || i == 12 || i == 13 || i == 15 || i == 16 || i == 17)
        {
            STAssertTrue([rc isMarkedAsRead:@"toto" article:i], @"");
        } else {
            STAssertFalse([rc isMarkedAsRead:@"toto" article:i], @"");
        }
    }
    
    [rc markAsUnread:@"toto" from:0 to:6];
    for (int i = 0; i < 20; i++) {
        if (i == 7 || i == 8 || i == 10 || i == 12 || i == 13
             || i == 15 || i == 16 || i == 17)
        {
            STAssertTrue([rc isMarkedAsRead:@"toto" article:i], @"");
        } else {
            STAssertFalse([rc isMarkedAsRead:@"toto" article:i], @"");
        }
    }
    
    [rc markAsUnread:@"toto" from:8 to:12];
    NSLog(@"%@", rc);
    for (int i = 0; i < 20; i++) {
        if (i == 7 || i == 13 || i == 15 || i == 16 || i == 17) {
            STAssertTrue([rc isMarkedAsRead:@"toto" article:i], @"");
        } else {
            STAssertFalse([rc isMarkedAsRead:@"toto" article:i], @"");
        }
    }
    
    
    [rc markAsUnread:@"toto" from:0 to:14];
    for (int i = 0; i < 20; i++) {
        if (i == 15 || i == 16 || i == 17) {
            STAssertTrue([rc isMarkedAsRead:@"toto" article:i], @"");
        } else {
            STAssertFalse([rc isMarkedAsRead:@"toto" article:i], @"");
        }
    }

    [rc markAsUnread:@"toto" article:16];
    for (int i = 0; i < 20; i++) {
        if (i == 15 || i == 17) {
            STAssertTrue([rc isMarkedAsRead:@"toto" article:i], @"");
        } else {
            STAssertFalse([rc isMarkedAsRead:@"toto" article:i], @"");
        }
    }

    [rc markAsUnread:@"toto" from:0 to:20];
    for (int i = 0; i < 20; i++) {
        STAssertFalse([rc isMarkedAsRead:@"toto" article:i], @"");
    }
}
@end
