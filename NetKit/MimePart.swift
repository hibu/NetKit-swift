//
//  MimePart.swift
//  NetKit
//
//  Created by Marc Palluat de Besset on 15/12/2015.
//  Copyright © 2015 hibu. All rights reserved.
//

import Foundation

public typealias CreationClosure = (data: NSData) -> MimePart?

// MARK: - abstract class MimePart -
public class MimePart {
    private let mType: String
    var headers = [String:String]()
    
    var mimeType: String {
        get {
            return mType
        }
    }
    
    var content: Any {
        return ""
    }
    
    class func subclasses() -> [String:CreationClosure] {
        
        var subclasses = [String:CreationClosure]()
        
        for mimeType in JSONMimePart.mimeTypes() {
            subclasses[mimeType] = JSONMimePart.creationClosure()
        }
        
        for mimeType in ImageMimePart.mimeTypes() {
            subclasses[mimeType] = ImageMimePart.creationClosure()
        }
        
        return subclasses
    }
    
    class func mimeTypes() -> [String] {
        return []
    }
    
    init(mimeType: String) {
        self.mType = mimeType.lowercaseString
    }
    
    // subclassers should implement :
    // init(jsonData: NSData, encoding: NSStringEncoding)
    
    public func dataRepresentation( completion: (data: NSData?) -> Void) {
        
    }
    
    class func creationClosure() -> CreationClosure {
        return { (data: NSData) -> MimePart? in
            return nil
        }
    }
}