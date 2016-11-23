//
//  Extensions.swift
//  NetKit
//
//  Created by Marc Palluat de Besset on 11/12/2015.
//  Copyright © 2015 hibu. All rights reserved.
//

import Foundation

private let formatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "d/M/yyyy H:m:ss.SSS"
    return f
}()

public func DLog<T>(_ message:T, file:String = #file, function:String = #function, line:Int = #line, showFile: Bool = false, showFunction: Bool = false, showLine: Bool = false) {
    #if DEBUG
        if let text = message as? String {
            
            var prefix = formatter.string(from: Date())
            
            if showFile {
                let file = file as NSString
                prefix = prefix + " " + file.lastPathComponent
            }
            
            if showFunction {
                prefix = prefix + " " + function
            }
            
            if showLine {
                prefix = prefix + " \(line)"
            }
            
            DispatchQueue.main.async {
                print("\(prefix): " + text, terminator: "\n")
            }
        }
    #endif
}

internal func += <KeyType, ValueType> (left: inout Dictionary<KeyType, ValueType>, right: Dictionary<KeyType, ValueType>) {
    for (k, v) in right {
        left.updateValue(v, forKey: k)
    }
}

internal extension URLComponents {
    mutating func addQueryItems(_ items: [URLQueryItem]) {
        if let qItems = queryItems {
            queryItems = qItems + items
        } else {
            queryItems = items
        }
    }
}
