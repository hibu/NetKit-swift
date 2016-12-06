//
//  Exceptions.m
//  NetKit2
//
//  Created by Marc Palluat de Besset on 22/09/2016.
//  Copyright © 2016 hibu. All rights reserved.
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

