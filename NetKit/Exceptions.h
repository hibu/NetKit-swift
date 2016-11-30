//
//  Exceptions.h
//  NetKit2
//
//  Created by Marc Palluat de Besset on 22/09/2016.
//  Copyright © 2016 hibu. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef void (^CatchBlock_t)( NSException  * _Nonnull );

BOOL tryCatch(dispatch_block_t _Nonnull tryBlock, CatchBlock_t _Nonnull catchBlock);

