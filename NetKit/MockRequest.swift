//
//  MockRequest.swift
//  NetKit
//
//  Created by Marc Palluat de Besset on 19/12/2015.
//  Copyright © 2015 hibu. All rights reserved.
//

import Foundation

public var mockBaseURL : String = ""

class MockProvider: IntentProvider {
    func sessionCreatedForIntentNamed(name: String) -> NSURLSession {
        return NSURLSession.sharedSession()
    }
}

class MockRequest : IRequest {
    
    var responseURL: NSURL
    
    init(url: String, intent: Intent, session: NSURLSession = NSURLSession.sharedSession(), httpMethod: String = "GET", flags: [String:Any]? = nil) {
        responseURL = NSURL(string:mockBaseURL + url)!
        super.init(intent: intent, session: session, httpMethod: httpMethod, flags: flags)
    }
    
    convenience init(url: String, session: NSURLSession = NSURLSession.sharedSession(), httpMethod: String = "GET", flags: [String:Any]? = nil) {
        let provider = MockProvider()
        let intent = Intent(name: "mockRequest", provider: provider)
        self.init(url: url, intent: intent, session: session, httpMethod: httpMethod, flags: flags)
    }
    
    override func start(completion: Response) {
        
        let request = Request()
        request.url = responseURL
        request.headers = ["Accept" : "application/json"]
        request.start { (object, httpResponse, error) -> Void in
            if let data = object as? NSData {
                do {
                    if let json = try NSJSONSerialization.JSONObjectWithData(data, options: .AllowFragments) as? NSDictionary {
                        completion(object: json, httpResponse: httpResponse, error: error)
                    }
                } catch {
                    completion(object: nil, httpResponse: httpResponse, error: nil)
                }
            }
        }
    }
}


public extension Request {
    public class func mockRequestWithIntent(url: String, intent: Intent?, session: NSURLSession = NSURLSession.sharedSession(), httpMethod: String = "GET", flags: [String:Any]? = nil) -> Request {
        var myIntent: Intent
        
        if let intent = intent {
            myIntent = intent
        } else {
            let provider = MockProvider()
            myIntent = Intent(name: "mockRequest", provider: provider)
        }
        
        return MockRequest(url: url, intent: myIntent, session: session, httpMethod: httpMethod, flags: flags)
    }
    public class func mockRequest(url: String, session: NSURLSession = NSURLSession.sharedSession(), httpMethod: String = "GET", flags: [String:Any]? = nil) -> Request {
        return MockRequest(url: url, session: session, httpMethod: httpMethod, flags: flags)
    }
}
