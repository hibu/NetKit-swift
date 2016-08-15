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
        request.start { (object, httpResponse, error) -> Void in
            
            if let html = object as? String {
                XCTAssert(html.contains("<html"))
            }
        }
        
    }
    
    func testFetchImage() {
        let request = Request()
        request.urlString = "https://www-a.yellqatest.com/static/image/26bac63a-bc5a-4e7c-aec2-9c837d034f17_image_jpeg"
        request.headers = ["accept":"image/*"]
        request.urlComponents.addQueryItems([URLQueryItem(name: "t", value: "tr/w:238/h:178/q:70")])
        request.start { (object, httpResponse, error) -> Void in
            
            if let image = object as? UIImage {
                XCTAssert(image.size.width <= 238 && image.size.height == 178)
            }
        }
        
    }
    
    
    func testGeocoding() {
        class Provider : IntentProvider, IntentConfigureRequest {
            
            func sessionCreatedForIntentNamed(_ name: String) -> URLSession {
                let configuration = URLSessionConfiguration.default
                return URLSession(configuration: configuration)
            }
            
            func configureRequest(_ request: Request, intent: Intent, flags: [String:Any]?) throws {
                if (request.headers["accept"] == nil) {
                    request.addHeaders(["accept":"application/json"])
                }
                
                request.buildUrl { (components: URLComponents) -> Void in
                    components.scheme = "https"
                    components.host = "maps.googleapis.com"
                    let userPath = components.path!
                    let prefix = userPath.hasPrefix("/") ? "" : "/"
                    components.path = "/maps/api\(prefix)\(userPath)/json"
                }
            }
            
        }
        
        let provider = Provider()
        let intent = Intent(name: "google", provider: provider)
        
        let request = Request.requestWithIntent(intent)
        request.urlComponents.path = "geocode"
        request.urlComponents.addQueryItems([
            URLQueryItem(name: "sensor", value: "true"),
            URLQueryItem(name: "latlng", value: "51.48,-0.13")
            ])
        request.start { (object, httpResponse, error) -> Void in
            
            XCTAssertNotNil(object)
            if let json = object as? NSDictionary {
                XCTAssertNotNil(json["results"])
            }
        }
        
    }
    
    
}
