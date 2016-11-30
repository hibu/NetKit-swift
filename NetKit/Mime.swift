//
//  Mime.swift
//  NetKit2
//
//  Created by Marc Palluat de Besset on 02/11/2016.
//  Copyright © 2016 hibu. All rights reserved.
//

import UIKit

public protocol MimeConverter {
    static var mimeTypes: Set<String> { get }
    static func convert(data: Data) throws -> Any
    
    var mimeType: String { get }
    var headers: [String:String] { get set }
    func convert() throws -> Data
}

public typealias JSONString = String
public typealias JSONDictionary = [String:Any]
public typealias JSONArray = [Any]

private protocol Converter {
    func convert() throws -> Data
}

private struct JSONConverter<T>: Converter {
    let json: T
    
    init(json: T) {
        self.json = json
    }
    
    func convert() throws -> Data {
        return try JSONSerialization.data(withJSONObject: json, options: [])
    }
}

private class Holder {
    var data: Data?
}

public enum JSONMimeConverterError: Error {
    case noJSON
}

public struct JSONMimeConverter: MimeConverter {
    
    public var mimeType = "application/json;charset=UTF-8"
    public var headers: [String:String] = [:]
    private var provider: () -> Converter?
    private let holder = Holder()
    
    public static var mimeTypes: Set<String> {
        get {
            return ["application/json", "application/x-javascript", "text/javascript",
                    "text/x-javascript", "text/x-json"]
        }
    }
    
    public static func convert(data: Data) throws -> Any {
        return try JSONSerialization.jsonObject(with: data, options: [.allowFragments])
    }
    
    public func convert() throws -> Data {
        if let data = holder.data {
            return data
        } else if let converter = provider() {
            let data = try converter.convert()
            holder.data = data
            return data
        }
        throw JSONMimeConverterError.noJSON
    }
    
    public init(json: JSONString) {
        provider = {
            return JSONConverter(json: json)
        }
    }
    
    public init(json: JSONDictionary) {
        provider = {
            return JSONConverter(json: json)
        }
    }
    
    public init(json: JSONArray) {
        provider = {
            return JSONConverter(json: json)
        }
    }
    
    public init(json: @escaping () -> JSONDictionary?) {
        provider = {
            if let json = json() {
                return JSONConverter(json: json)
            }
            return nil
        }
    }
    
    public init(json: @escaping () -> JSONArray?) {
        provider = {
            if let json = json() {
                return JSONConverter(json: json)
            }
            return nil
        }
    }
    
    public init(json: @escaping () -> JSONString?) {
        provider = {
            if let json = json() {
                return JSONConverter(json: json)
            }
            return nil
        }
    }
}

public enum ImageMimeConverterError: Error {
    case invalidData
    case couldNotConvertToPNGRepresentation
}

public struct ImageMimeConverter: MimeConverter {
    
    public var headers: [String:String] = [:]
    public let image: UIImage
    private let holder = Holder()
    
    public static var mimeTypes: Set<String> {
        get {
            return ["image/png", "image/jpg", "image/jpeg", "image/gif",
                    "image/tiff", "image/tif", "image/*"]
        }
    }
    
    public var mimeType: String {
        get {
            return "image/png"
        }
    }
    
    init(image: UIImage) {
        self.image = image
    }
    
    public static func convert(data: Data) throws -> Any {
        if let image = UIImage(data: data, scale:0) {
            return image
        } else {
            throw ImageMimeConverterError.invalidData
        }
    }
    
    public func convert() throws -> Data {
        if let data = holder.data {
            return data
        } else if let data = UIImagePNGRepresentation(self.image) {
            holder.data = data
            return data
        } else {
            throw ImageMimeConverterError.couldNotConvertToPNGRepresentation
        }
    }
    
}

public enum MultipartMimeType : String {
    case mixed = "multipart/mixed"
    case alternative = "multipart/alternative"
    case digest = "multipart/digest"
    case parallel = "multipart/parallel"
    
    static let allValues = [mixed, alternative, digest, parallel]
}

public struct MultipartMimeConverter: MimeConverter {
    
    public let type: MultipartMimeType
    public let parts: [MimeConverter]
    public let boundary: String
    public var headers: [String : String] = [:]
    private let holder = Holder()
    
    public static var mimeTypes: Set<String> {
        get {
            return Set(MultipartMimeType.allValues.map { $0.rawValue })
        }
    }
    
    public var mimeType: String {
        get {
            return "\(type.rawValue); boundary=\(boundary)"
        }
    }
    
    public init?(mimeType: MultipartMimeType, parts: [MimeConverter]) {
        if parts.count == 0 {
            return nil
        }
        boundary = MultipartMimeConverter.randomBoundary()
        self.parts = parts
        self.type = mimeType
    }
    
    public static func convert(data: Data) throws -> Any {
        // not implemented yet
        return ""
    }
    
    public func convert() throws -> Data {
        
        if let data = holder.data {
            return data
        } else {
            let content = NSMutableData()
            content.append("--\(boundary)\r\n".data(using: String.Encoding.utf8)!)
            
            for (index, part) in parts.enumerated() {
                for (key, value) in part.headers {
                    content.append("\(key): \(value)\r\n".data(using: String.Encoding.utf8)!)
                }
                
                content.append("Content-Type: \(part.mimeType)\r\n\r\n".data(using: String.Encoding.utf8)!)
                
                if let data = try? part.convert() {
                    content.append(data)
                } else {
                    DLog("*** unable to get data from part \(part) ***")
                }
                
                content.append("\r\n--\(boundary)\(index == self.parts.count - 1 ? "--" : "")\r\n".data(using: String.Encoding.utf8)!)
            }
            
            holder.data = content as Data
            return content as Data
        }
    }
    
    private static func randomBoundary() -> String {
        return String(format: "NETKit.boundary.%08x%08x", arc4random(), arc4random())
    }
}

public let converters: [MimeConverter.Type] = [JSONMimeConverter.self, ImageMimeConverter.self]



