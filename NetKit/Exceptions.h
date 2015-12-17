//
//  Exceptions.h
//  NetKit
//
//  Created by Marc Palluat de Besset on 14/12/2015.
//  Copyright © 2015 hibu. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef void (^CatchBlock_t)( NSException  * _Nonnull );

BOOL tryCatch(dispatch_block_t _Nonnull tryBlock, CatchBlock_t _Nonnull catchBlock);

