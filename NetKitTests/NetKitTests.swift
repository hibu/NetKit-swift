//
//  NetKitTests.swift
//  NetKitTests
//
//  Created by Marc Palluat de Besset on 17/12/2015.
//  Copyright © 2015 hibu. All rights reserved.
//

import XCTest
@testable import NetKit

class netkitTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testFetchAppleHomePage() {
        let request = Request()
        request.urlString = "http://apple.com"
        request.headers = ["accept":"text/html"]
        request.start { (html: String?, response, error) in
           XCTAssert(html!.contains("<html"))
        }
        
    }
    
    func testFetchImage() {
        let request = Request()
        request.urlString = "https://www-a.yellqatest.com/static/image/26bac63a-bc5a-4e7c-aec2-9c837d034f17_image_jpeg"
        request.headers = ["accept":"image/*"]
        request.urlBuilder.add([URLQueryItem(name: "t", value: "tr/w:238/h:178/q:70")])
        request.start { (image: UIImage?, httpResponse, error) -> Void in
            
            if let image = image {
                XCTAssert(image.size.width <= 238 && image.size.height == 178)
            }
        }
        
    }
    
    
    func testGeocoding() {
        
        class Provider : EndpointSession, EndpointConfiguration {
            
            var identifier = "test"
            
            func session(forRequest request: Request?, flags: Plist?) -> URLSession {
                let configuration = URLSessionConfiguration.default
                return URLSession(configuration: configuration)
            }
            
            func configure(request: Request, flags: Plist?) throws {
                if (request.headers["accept"] == nil) {
                    request.add(headers: ["accept":"application/json"])
                }
                
                request.urlBuilder.scheme = "https"
                request.urlBuilder.host = "maps.googleapis.com"
                let userPath = request.urlBuilder.path
                let prefix = userPath.hasPrefix("/") ? "" : "/"
                request.urlBuilder.path = "/maps/api\(prefix)\(userPath)/json"
            }
            
        }
        
        let provider = Provider()
        
        let request = Request(endpoint: provider)
        request.urlBuilder.path = "geocode"
        request.urlBuilder.add([
            URLQueryItem(name: "sensor", value: "true"),
            URLQueryItem(name: "latlng", value: "51.48,-0.13")
            ])
        request.start { (json: [String:Any]?, httpResponse, error) -> Void in
            
            XCTAssertNotNil(json)
            if let json = json {
                XCTAssertNotNil(json["results"])
            }
        }
        
    }
    
    
}
