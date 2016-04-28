//
//  Extensions.swift
//  NetKit
//
//  Created by Marc Palluat de Besset on 11/12/2015.
//  Copyright © 2015 hibu. All rights reserved.
//

import Foundation

private let formatter: NSDateFormatter = {
    let f = NSDateFormatter()
    f.dateFormat = "d/M/yyyy H:m:ss.SSS"
    return f
}()

public func DLog<T>(message:T, file:String = #file, function:String = #function, line:Int = #line, showFile: Bool = false, showFunction: Bool = false, showLine: Bool = false) {
    #if DEBUG
        if let text = message as? String {
            
            var prefix = formatter.stringFromDate(NSDate())
            
            if showFile {
                let file: NSString = file
                prefix = prefix + " " + file.lastPathComponent
            }
            
            if showFunction {
                prefix = prefix + " " + function
            }
            
            if showLine {
                prefix = prefix + " \(line)"
            }
            
            dispatch_async(dispatch_get_main_queue()) {
                print("\(prefix): " + text, terminator: "\n")
            }
        }
    #endif
}

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
