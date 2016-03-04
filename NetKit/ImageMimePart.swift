//
//  ImageMimePart.swift
//  NetKit
//
//  Created by Marc Palluat de Besset on 15/12/2015.
//  Copyright © 2015 hibu. All rights reserved.
//

import UIKit

public class ImageMimePart : MimePart {
    
    let image: UIImage
    
    required public init(imageData: NSData) throws {
        if let image = UIImage(data: imageData, scale:0) {
            self.image = image
            super.init(mimeType: "image/png")
        } else {
            self.image = UIImage()
            super.init(mimeType: "image/png")
            throw NSCocoaError.init(rawValue: 999)
        }
    }
    
    public init(image: UIImage) {
        self.image = image
        super.init(mimeType: "image/png")
    }
    
    override class func creationClosure() -> CreationClosure {
        return { (data: NSData) -> MimePart? in
            var imagePart: MimePart?

            do {
                imagePart = try self.init(imageData: data)
            } catch {
                imagePart = nil
            }
            
            if let part = imagePart {
                return part
            }
            return nil
        }
    }
    
    override class func mimeTypes() -> [String] {
        return ["image/png", "image/jpg", "image/jpeg", "image/gif", "image/tiff", "image/tif", "image/*"]
    }
    
    override public func dataRepresentation( completion: (data: NSData?) -> Void) {
        completion(data: UIImagePNGRepresentation(self.image))
    }

    override var content: Any {
        return image
    }

//    + (NSString *)contentTypeForImageData:(NSData *)data {
//    uint8_t c;
//    [data getBytes:&c length:1];
//    
//    switch (c) {
//    case 0xFF:
//    return @"image/jpeg";
//    case 0x89:
//    return @"image/png";
//    case 0x47:
//    return @"image/gif";
//    case 0x49:
//    case 0x4D:
//    return @"image/tiff";
//    }
//    return nil;
//    }


}