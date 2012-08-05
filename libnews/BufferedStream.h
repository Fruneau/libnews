//
//  BufferedStream.h
//  libnews
//
//  Created by Florent Bruneau on 05/08/12.
//  Copyright (c) 2012 Florent Bruneau. All rights reserved.
//

#import <Foundation/Foundation.h>

/** Stream-Buffer interaction
 */

@interface NSInputStream (Buffered)
+ (NSInputStream *)fromStream:(NSInputStream *)source maxSize:(NSUInteger)max;
@end

@interface NSOutputStream (Buffered)
+ (NSOutputStream *)toStream:(NSOutputStream *)dest maxSize:(NSUInteger)max;
@end
