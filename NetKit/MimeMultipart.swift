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
    return String(format: "NETKit.boundary.%08x%08x", arc4random(), arc4random())
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
        return { (data: Data) -> MimePart? in
            return nil
        }
    }
    
    override class func mimeTypes() -> [String] {
        return MultipartMimeTypes.allValues.map { $0.rawValue }
    }
    
    override public func dataRepresentation( _ completion: (_ data: Data?) -> Void) {
        guard parts.count > 0 else {
            completion(nil)
            return
        }
        
        let content = NSMutableData()
        content.append("--\(boundary)\r\n".data(using: String.Encoding.utf8)!)
        
        for (index, part) in parts.enumerated() {
            for (key, value) in part.headers {
                content.append("\(key): \(value)\r\n".data(using: String.Encoding.utf8)!)
            }
            
            content.append("Content-Type: \(part.mimeType)\r\n\r\n".data(using: String.Encoding.utf8)!)
            part.dataRepresentation { (data: Data?) in
                if let data = data {
                    content.append(data)
                } else {
                    DLog("*** unable to get data from part \(part) ***")
                }
            }
            
            content.append("\r\n--\(boundary)\(index == self.parts.count - 1 ? "--" : "")\r\n".data(using: String.Encoding.utf8)!)


        }
        
        completion(content as Data)
    }
    
    override var mimeType: String {
        get {
            return "\(super.mimeType); boundary=\(boundary)"
        }
    }


}
