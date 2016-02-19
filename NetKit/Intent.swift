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
    func sessionCreatedForIntentNamed(name: String) -> NSURLSession
}

public protocol IntentConfigureRequest : IntentProvider {
    func configureRequest(request: Request, intent: Intent, flags: [String:Any]?) throws
}

public protocol IntentConfigureURLRequest : IntentProvider {
    func configureURLRequest(urlRequest: NSMutableURLRequest, request: Request, intent: Intent, flags: [String:Any]?) throws
}

public protocol IntentControlPoint : IntentProvider {
    func controlPoint(intent: Intent, toBeExecuted: (() -> Void) -> Void)
}

public protocol IntentReceivedData : IntentProvider {
    func receivedData(intent: Intent, data: NSData?, inout object: Any?, inout httpResponse: NSHTTPURLResponse?, inout error: NSError?)
}

// MARK: - class Intent -

public class Intent {
    public let name: String
    public let uid: UInt
    public let session: NSURLSession
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
        
        NSLog("NETIntent \(fullName) - deinit");
    }
    
// MARK: - API -
    public func detach() -> Intent {
        if uid != 0 {
            NSException(name: "IntentDetachException", reason: "Can't detach from a detached Intent", userInfo: nil).raise()
        }
        
        var newUid: UInt = 0
        
        dispatch_sync(lockQueue) {
            self.detached_uid += 1
            newUid = self.detached_uid
        }
        
        return Intent(name: name, provider: provider, uid: newUid)
    }
}

// MARK: - class IRequest -
internal class IRequest : Request {
    weak var intent: Intent?
    
// MARK: - init -
    init(intent: Intent, session: NSURLSession? = nil, httpMethod: String = "GET", flags: [String:Any]? = nil) {
        self.intent = intent
        super.init(session: session ?? intent.session, httpMethod: httpMethod, flags: flags)
    }
    
// MARK: - overrides -
    internal override func executeControlPointClosure(work: ControlPoint) {
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
    
    internal override func configureURLRequest(urlRequest: NSMutableURLRequest) throws {
        if let intent = intent, let provider = intent.provider as? IntentConfigureURLRequest {
            try provider.configureURLRequest(urlRequest, request: self, intent: intent, flags: flags)
        }
    }

    
    internal override func didReceiveData(data: NSData?, inout object: Any?, inout httpResponse: NSHTTPURLResponse?, inout error: NSError?) {
        if let intent = intent, let provider = intent.provider as? IntentReceivedData {
            provider.receivedData(intent, data: data, object: &object, httpResponse: &httpResponse, error: &error)
        }
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
    public class func requestWithIntent(intent: Intent?, session: NSURLSession? = nil, httpMethod: String = "GET", flags: [String:Any]? = nil) -> Request {
        if let intent = intent {
            return IRequest(intent: intent, session: session, httpMethod: httpMethod, flags: flags)
        } else {
            return Request(session: session ?? NSURLSession.sharedSession(), httpMethod: httpMethod, flags: flags)
        }
    }
}

