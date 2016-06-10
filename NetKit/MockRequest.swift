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

/*
 class MockRequest
 
 Mock requests will ignore all configuration done to it and will instead fetch a file
 from the mockBaseURL.
 
 typical use:
 
 // when app starts :
 mockBaseURL = "https://dl.dropboxusercontent.com/u/28161289/" // a public dropbox
 
 let intent = ...
 let request = Request.mockRequestWithIntent("reputation.json", intent: intent)
 request.buildUrl  { (builder) in
    builder.path = "listing/\(natid)/reviews/histogram"
 }
 
 request.start { (object, httpResponse, error) -> Void in
    if let json = object as? JSONDictionary {
        ...
    }
 
 }
 
 fetches the file reputation.json from a dropbox.
 
 */

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
        request.headers = ["accept" : "application/json"]
        request.start { (object, httpResponse, error) -> Void in
            
            if let data = object as? NSData,
                json = try? NSJSONSerialization.JSONObjectWithData(data, options: .AllowFragments) {
                        completion(object: json, httpResponse: httpResponse, error: error)
            } else {
                completion(object: nil, httpResponse: httpResponse, error: error)
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
