//
//  Extensions.swift
//  NetKit
//
//  Created by Marc Palluat de Besset on 11/12/2015.
//  Copyright © 2015 hibu. All rights reserved.
//

import Foundation

internal func += <KeyType, ValueType> (inout left: Dictionary<KeyType, ValueType>, right: Dictionary<KeyType, ValueType>) {
    for (k, v) in right {
        left.updateValue(v, forKey: k)
    }
}

internal extension NSURLComponents {
    func addQueryItems(items: [NSURLQueryItem]) {
        if let qItems = queryItems {
            queryItems = qItems + items
        } else {
            queryItems = items
        }
    }
}
