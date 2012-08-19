//
//  Header.h
//  libnews
//
//  Created by Florent Bruneau on 19/08/12.
//  Copyright (c) 2012 Florent Bruneau. All rights reserved.
//

#ifndef libnews_utils_h
#define libnews_utils_h

#define likely(Expr)    __builtin_expect(!!(Expr), 1)
#define unlikely(Expr)  __builtin_expect(!!(Expr), 0)

#define RETHROW(Expr)  ({                                                    \
        typeof(Expr) __e = (Expr);                                           \
        if (unlikely(__e < 0)) {                                             \
            return __e;                                                      \
        }                                                                    \
        __e;                                                                 \
    })

#define IGNORE(Expr)  ((void)(Expr))

#endif
