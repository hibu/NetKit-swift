//
//  Intent.swift
//  NetKit
//
//  Created by Marc Palluat de Besset on 14/12/2015.
//  Copyright © 2015 hibu. All rights reserved.
//

import Foundation

// MARK: - protocols -

public protocol IntentProvider {
    func sessionCreatedForIntentNamed(_ name: String) -> URLSession
}

public protocol IntentConfigureRequest : IntentProvider {
    func configureRequest(_ request: Request, intent: Intent, flags: [String:Any]?) throws
}

public protocol IntentConfigureURLRequest : IntentProvider {
    func configureURLRequest(_ urlRequest: NSMutableURLRequest, request: Request, intent: Intent, flags: [String:Any]?, completion: Response) throws
}

public protocol IntentControlPoint : IntentProvider {
    func controlPoint(_ intent: Intent, toBeExecuted: (() -> Void) -> Void)
}

public protocol IntentReceivedData : IntentProvider {
    func receivedData(_ intent: Intent, request:IntentRequest, data: Data?, object: inout Any?, httpResponse: inout HTTPURLResponse?, error: inout NSError?, completion: Response, flags: [String:Any]?) -> Bool
}

public protocol IntentRequest: AnyObject {
    var retries: Int { get set }
    var url: URL? { get }
    func start(_ completion: Response)
}

// MARK: - class Intent -

/*
 class Intent
 
 Intents are used to implement endpoints (ex: google geocoding)
 They provide optional points to construct / modify Request objects.
 
 Typical use:
 
 let intent = ...
 
 let request = Request.requestWithIntent(intent)
 request.buildUrl { (builder) -> Void in
    builder.path = "products"
 }
 
 request.start { (object, httpResponse, error) -> Void in
    if json = object as JSONDictionary {
        ...
    }
 }

 */

public class Intent {
    public let name: String
    public let uid: UInt
    public let session: URLSession
    public let provider: IntentProvider
    private var detached_uid: UInt = 0
    public var finishTasksAndInvalidateSessionOnDeinit: Bool = false
    
    public var fullName: String {
        return "\(name) - \(uid)"
    }
    
// MARK: - init / deinit -
    public init(name: String, provider: IntentProvider, uid: UInt = 0) {
        self.name = name
        self.uid = uid
        self.provider = provider
        self.session = provider.sessionCreatedForIntentNamed(name)
    }
    
    deinit {
        if self.finishTasksAndInvalidateSessionOnDeinit {
            session.finishTasksAndInvalidate()
        } else {
            session.invalidateAndCancel()
        }
        
        DLog("NETIntent \(fullName) - deinit");
    }
    
// MARK: - API -
    public func detach() -> Intent {
        if uid != 0 {
            NSException(name: "IntentDetachException" as NSExceptionName, reason: "Can't detach from a detached Intent", userInfo: nil).raise()
        }
        
        var newUid: UInt = 0
        
        lockQueue.sync {
            self.detached_uid += 1
            newUid = self.detached_uid
        }
        
        return Intent(name: name, provider: provider, uid: newUid)
    }
}

// MARK: - class IRequest -
internal class IRequest : Request, IntentRequest {
    weak var intent: Intent?
    var retries: Int = 1
    
// MARK: - init -
    init(intent: Intent, session: URLSession? = nil, httpMethod: HTTPMethod = .get, flags: [String:Any]? = nil) {
        self.intent = intent
        super.init(session: session ?? intent.session, httpMethod: httpMethod, flags: flags)
    }
    
// MARK: - overrides -
    internal override func executeControlPointClosure(_ work: ControlPoint) {
        if let intent = intent, let provider = intent.provider as? IntentControlPoint {
            provider.controlPoint(intent, toBeExecuted: work)
        } else {
            super.executeControlPointClosure(work)
        }
    }
    
    internal override func configureRequest() throws {
        if let intent = intent, let provider = intent.provider as? IntentConfigureRequest {
            try provider.configureRequest(self, intent: intent, flags: flags)
        }
    }
    
    internal override func configureURLRequest(_ urlRequest: NSMutableURLRequest, completion: Response) throws {
        if let intent = intent, let provider = intent.provider as? IntentConfigureURLRequest {
            try provider.configureURLRequest(urlRequest, request: self, intent: intent, flags: flags, completion: completion)
        }
    }

    
    internal override func didReceiveData(_ data: Data?, object: inout Any?, httpResponse: inout HTTPURLResponse?, error: inout NSError?, completion: Response) -> Bool {
        if let intent = intent, let provider = intent.provider as? IntentReceivedData {
            return provider.receivedData(intent, request: self, data: data, object: &object, httpResponse: &httpResponse, error: &error, completion: completion, flags: self.flags)
        }
        return true
    }
    
    internal override func sessionDescription() -> String {
        if let intent = intent {
            return intent.fullName
        } else {
            return super.sessionDescription()
        }
    }
    
}

// MARK: - Request extension -

public extension Request {
    public class func requestWithIntent(_ intent: Intent?, session: URLSession? = nil, httpMethod: HTTPMethod = .get, flags: [String:Any]? = nil) -> Request {
        if let intent = intent {
            return IRequest(intent: intent, session: session, httpMethod: httpMethod, flags: flags)
        } else {
            return Request(session: session ?? URLSession.shared, httpMethod: httpMethod, flags: flags)
        }
    }
}

