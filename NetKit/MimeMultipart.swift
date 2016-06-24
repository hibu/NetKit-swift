//
//  MimeMultipart.swift
//  NetKit
//
//  Created by Marc Palluat de Besset on 15/12/2015.
//  Copyright © 2015 hibu. All rights reserved.
//

import Foundation

public enum MultipartMimeTypes : String {
    case mixed = "multipart/mixed"
    case alternative = "multipart/alternative"
    case digest = "multipart/digest"
    case parallel = "multipart/parallel"
    
    static let allValues = [mixed, alternative, digest, parallel]
}

private func randomBoundary() -> String {
    return String(format: "NETKit.boundary.%08x%08x", random(), random())
}



public class MimeMultipart : MimePart {
    
    let boundary: String
    let parts: [MimePart]
    
//    public init(multipartData: NSData) throws {
//        
//    }
    
    public init(mimeType: MultipartMimeTypes, parts: [MimePart]) {
        boundary = randomBoundary()
        self.parts = parts
        super.init(mimeType: mimeType.rawValue)
    }

    
    public override class func creationClosure() -> CreationClosure {
        return { (data: NSData) -> MimePart? in
            return nil
        }
    }
    
    override class func mimeTypes() -> [String] {
        return MultipartMimeTypes.allValues.map { $0.rawValue }
    }
    
    override public func dataRepresentation( completion: (data: NSData?) -> Void) {
        guard parts.count > 0 else {
            completion(data: nil)
            return
        }
        
        let content = NSMutableData()
        content.appendData("--\(boundary)\r\n".dataUsingEncoding(NSUTF8StringEncoding)!)
        
        for (index, part) in parts.enumerate() {
            for (key, value) in part.headers {
                content.appendData("\(key): \(value)\r\n".dataUsingEncoding(NSUTF8StringEncoding)!)
            }
            
            content.appendData("Content-Type: \(part.mimeType)\r\n\r\n".dataUsingEncoding(NSUTF8StringEncoding)!)
            part.dataRepresentation { (data: NSData?) in
                if let data = data {
                    content.appendData(data)
                } else {
                    DLog("*** unable to get data from part \(part) ***")
                }
            }
            
            content.appendData("\r\n--\(boundary)\(index == self.parts.count - 1 ? "--" : "")\r\n".dataUsingEncoding(NSUTF8StringEncoding)!)


        }
        
        completion(data: content)
    }
    
    override var mimeType: String {
        get {
            return "\(super.mimeType); boundary=\(boundary)"
        }
    }


}