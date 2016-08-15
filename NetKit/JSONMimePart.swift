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
    
    let jsonData: Data
    
    override var content: Any {
        do {
            return try JSONSerialization.jsonObject(with: jsonData, options: .allowFragments)
        } catch {
            return [:]
        }
    }
    
    public required init(jsonData: Data) throws {
        self.jsonData = jsonData
        super.init(mimeType: "application/json;charset=UTF-8")
    }
    
    public convenience init(jsonDictionary: NSDictionary) throws {
        let data = try JSONSerialization.data(withJSONObject: jsonDictionary, options: .prettyPrinted)
        try self.init(jsonData: data)
    }
    
    public convenience init(jsonString: JSONString) throws {
        if let data = jsonString.data(using: String.Encoding.utf8) {
            try self.init(jsonData: data)
        } else {
            throw CocoaError(.formattingError)
        }
    }
    
    override public func dataRepresentation( _ completion: (data: Data?) -> Void) {
        completion(data: jsonData)
    }
    
    override class func mimeTypes() -> [String] {
        return ["application/json", "application/x-javascript", "text/javascript", "text/x-javascript", "text/x-json"]
    }
    
    override class func creationClosure() -> CreationClosure {
        return { (data: Data) -> MimePart? in
            do {
            return try self.init(jsonData: data)
            } catch {
                return nil
            }
        }
    }
}
