//
//  Exceptions.m
//  NetKit
//
//  Created by Marc Palluat de Besset on 14/12/2015.
//  Copyright © 2015 hibu. All rights reserved.
//

#import "Exceptions.h"

BOOL tryCatch(dispatch_block_t tryBlock, CatchBlock_t catchBlock ) {
    BOOL raised = NO;
    @try {
        tryBlock();
    }
    @catch (NSException *exception) {
        catchBlock(exception);
        raised = YES;
    }
    return raised;
}

