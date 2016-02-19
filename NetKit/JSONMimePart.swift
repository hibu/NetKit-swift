//
//  JSONMimePart.swift
//  NetKit
//
//  Created by Marc Palluat de Besset on 15/12/2015.
//  Copyright © 2015 hibu. All rights reserved.
//

import Foundation

public typealias JSONString = String
public typealias JSONDictionary = [String:AnyObject]
public typealias JSONArray = [AnyObject]

public class JSONMimePart : MimePart {
    
    let jsonData: NSData
    
    override var content: Any {
        do {
            return try NSJSONSerialization.JSONObjectWithData(jsonData, options: .AllowFragments)
        } catch {
            return [:]
        }
    }
    
    public required init(jsonData: NSData) throws {
        self.jsonData = jsonData
        super.init(mimeType: "application/json")
    }
    
    public convenience init(jsonDictionary: NSDictionary) throws {
        let data = try NSJSONSerialization.dataWithJSONObject(jsonDictionary, options: .PrettyPrinted)
        try self.init(jsonData: data)
    }
    
    public convenience init(jsonString: JSONString) throws {
        if let data = jsonString.dataUsingEncoding(NSUTF8StringEncoding) {
            try self.init(jsonData: data)
        } else {
            throw NSCocoaError.FormattingError
        }
    }
    
    override func dataRepresentation( completion: (data: NSData?) -> Void) {
        completion(data: jsonData)
    }
    
    override class func mimeTypes() -> [String] {
        return ["application/json", "application/x-javascript", "text/javascript", "text/x-javascript", "text/x-json"]
    }
    
    override class func creationClosure() -> CreationClosure {
        return { (data: NSData) -> MimePart? in
            do {
            return try self.init(jsonData: data)
            } catch {
                return nil
            }
        }
    }
}