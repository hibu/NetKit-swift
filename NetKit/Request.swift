//
//  Request.swift
//  NetKit
//
//  Created by Marc Palluat de Besset on 20/11/2015.
//  Copyright © 2015 hibu. All rights reserved.
//

import Foundation

typealias Response = (object: Any?, httpResponse: NSHTTPURLResponse?, error: NSError?) -> Void
typealias Completion = () -> Void
typealias Work = (Completion?) -> Void

public let NETRequestDidStartNotification = "NETRequestDidStartNotification"
public let NETRequestDidEndNotification = "NETRequestDidEndNotification"

private var gUID = 0
internal let lockQueue = dispatch_queue_create("com.hibu.NetKit.Request.lock", nil)

// MARK: - functions -

private func assignUID() -> Int {
    var uid = 0;
    dispatch_sync(lockQueue) {
        uid = gUID
        gUID += 1
    }
    return uid
}

public func executeOnMainThread( closure: () -> Void ) {
    if NSThread.isMainThread() {
        closure()
    } else {
        dispatch_async(dispatch_get_main_queue(), closure)
    }
}

// MARK: - class Request -

public class Request : CustomStringConvertible, CustomDebugStringConvertible {
    let session: NSURLSession
    let method: String
    let uid: Int

    var headers = Dictionary<String, Any>()
    var urlComponents = NSURLComponents()
    var body: MimePart?
    var completesOnBackgroundThread = false
    var quiet: Bool = false
    var logRawResponseData: Bool = false
    
    internal var flags: [String:Any]?
    
    private (set) public var executing = false
    private (set) public var cancelled = false
    private var dataTask: NSURLSessionDataTask?
    
// MARK: - init / deinit -
    init(aSession: NSURLSession = NSURLSession.sharedSession(), httpMethod: String = "GET", flags: [String:Any]? = nil) {
        session = aSession
        method = httpMethod
        uid = assignUID()
        self.flags = flags
        
        buildUrl { components in
            components.scheme = "https"
            components.port = 443
        }
    }
    
    deinit {
        if !quiet {
            NSLog("\(self) - dealloc")
        }
    }

// MARK: - getters / setters -
    func buildUrl(componentsBlock: NSURLComponents -> Void) {
        componentsBlock(urlComponents)
    }
    
    var urlString: String? {
        get {
            return urlComponents.URL?.absoluteString
        }
        set(string) {
            if let string = string, let url = NSURL(string: string) {
                if let components = NSURLComponents(URL: url, resolvingAgainstBaseURL: false) {
                    urlComponents = components
                }
            }
        }
    }
    
    var url: NSURL? {
        get {
            return urlComponents.URL
        }
        set(url) {
            if let url = url, let components = NSURLComponents(URL: url, resolvingAgainstBaseURL: false) {
                urlComponents = components
            }
        }
    }
    
    func addHeaders(newHeaders: [String:Any]) {
        headers += newHeaders
    }
    
// MARK: - API -
    
    func start(completion: Response) {
        if executing {
            fatalError("start called on a request already started")
        }
        
        let work = controlPointClosure(completion)
        executeControlPointClosure(work)
    }
    
    func cancel() {
        cancelled = true
        dataTask?.cancel()
    }
    
 // MARK: - overrides -
    
    internal func executeControlPointClosure(work: Work) {
        work(nil)
    }
    
    internal func didReceiveData(data: NSData?, inout object: Any?, inout httpResponse: NSHTTPURLResponse?, inout error: NSError?) {
        
    }
    
    internal func configureRequest() throws {
        
    }
    
    internal func configureURLRequest(urlRequest: NSMutableURLRequest) throws {
        
    }
    
    internal func sessionDescription() -> String {
        if let description = self.session.sessionDescription {
            return description;
        }
        
        if self.session == NSURLSession.sharedSession() {
            return "shared session"
        }
        
        return ""
    }

    internal func logRequest() {
        let desc = sessionDescription()
        
        dispatch_async(dispatch_get_main_queue()) { () -> Void in
            NSLog("\n")
            NSLog("****** \(self.method) REQUEST #\(self.uid) \(desc) ******")
            NSLog("URL = \(self.url)")
            NSLog("Headers = \(self.headers)")
            NSLog("****** \\REQUEST #\(self.uid) ******")
            NSLog("\n")
        }
    }
    
    internal func logResponse(object: Any?, data: NSData?, httpResponse: NSHTTPURLResponse?, error: NSError?) {
        dispatch_async(dispatch_get_main_queue()) { () -> Void in
            var logRaw = false
            let headers = httpResponse?.allHeaderFields as? [String:String]
            let statusCode = httpResponse?.statusCode
            
            NSLog("\n")
            NSLog("****** RESPONSE #\(self.uid) status: \(statusCode) ******")
            NSLog("URL = \(self.url)")
            NSLog("Headers = \(headers)")
            if let error = error {
                NSLog("Error = \(error)")
            }
            
            var size = 0
            let encoding = headers?["Content-Encoding"]
            if let length = headers?["Content-Length"] {
                if let sizeInt = Int(length) {
                    size = sizeInt
                }
            }
            
            if let data = data where size == 0 {
                size = data.length;
            }
            
            let formatter = NSByteCountFormatter()
            var sizeString = formatter.stringFromByteCount(Int64(size))
            
            if let encoding = encoding {
                sizeString = "\(encoding) \(sizeString)"
            }
            
            if let object = object {
                NSLog("Body (\(sizeString)) = \(object)")
            } else {
                logRaw = true
            }
            
            if let data = data where self.logRawResponseData || logRaw {
                if let dataStr = NSString(data: data, encoding: NSUTF8StringEncoding) {
                    NSLog("Body (raw, \(sizeString)) = \(dataStr)")
                } else {
                    NSLog("Body (raw, \(sizeString)) = \(data)")
                }
            }
            NSLog("****** \\RESPONSE #\(self.uid) ******")
            NSLog("\n")
        }
    }
    
    
// MARK: - private methods -
    private func completeWithObject(object: Any?, data: NSData?, httpResponse: NSHTTPURLResponse?, error: NSError?, completion:Response) {
        
        var theObject = object
        var theHttpResponse = httpResponse
        var theError = error
        
        didReceiveData(data, object:&theObject, httpResponse: &theHttpResponse, error: &theError)
        
        let response = { () -> Void in
            completion(object: theObject, httpResponse: theHttpResponse, error: theError)
        }
        
        if completesOnBackgroundThread {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), response)
        } else {
            executeOnMainThread(response)
        }
    }
    
    private func urlRequest(completion: NSMutableURLRequest? -> Void) {
        guard let url = self.url else { completion(nil); return }
        
        let mRequest = NSMutableURLRequest(URL: url)
        let group = dispatch_group_create()
        
        if let body = body {
            dispatch_group_enter(group);
            body.dataRepresentation { (data: NSData?) -> Void in
                if let data = data {
                    mRequest.HTTPBody = data
                    mRequest.setValue("\(data.length)", forHTTPHeaderField:"Content-Length")
                    mRequest.setValue(body.mimeType, forHTTPHeaderField:"Content-Type")
                }
                dispatch_group_leave(group)
            }
        }
        
        for (header, value) in self.headers {
            mRequest.setValue("\(value)", forHTTPHeaderField:header)
        }
        
        dispatch_group_notify(group, dispatch_get_main_queue()) { () -> Void in
            completion(mRequest)
        }
    }
    
    private func controlPointClosure(responseCompletion: Response) -> Work {
        return { (workCompletion: Completion?) -> Void in
            
            let work = self.mainThreadClosure(responseCompletion, workCompletion: workCompletion)
            executeOnMainThread(work)
        }
    }
    
    private func mainThreadClosure(completion: Response, workCompletion: Completion?) -> Completion {
        return { _ in
            
            if self.cancelled {
                let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled, userInfo: nil)
                self.completeWithObject(nil, data:nil, httpResponse:nil, error:error, completion:completion)
                self.executeCompletion(workCompletion)
                return
            }
            
            self.executing = true
            
            do {
                try self.configureRequest();
            } catch let error as NSError {
                self.completeWithObject(nil, data: nil, httpResponse: nil, error: error, completion: completion)
                self.executeCompletion(workCompletion)
                return
            }
            
            self.urlRequest { (urlRequest: NSMutableURLRequest?) -> Void in
                if let urlRequest = urlRequest {
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
                        self.executeDataTaskWithURLRequest(urlRequest, completion: completion, workCompletion: workCompletion)
                    }
                } else {
                    let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorBadURL, userInfo: nil)
                    self.completeWithObject(nil, data:nil, httpResponse:nil, error:error, completion:completion)
                    self.executeCompletion(workCompletion)
                    return
                }
            }
        }
    }

    private func executeDataTaskWithURLRequest(urlRequest: NSMutableURLRequest, completion: Response, workCompletion: Completion?) {
        do {
            try configureURLRequest(urlRequest)
        } catch let error as NSError {
            self.completeWithObject(nil, data:nil, httpResponse:nil, error:error, completion:completion)
            self.executeCompletion(workCompletion)
            return
        }
        
        let tryClosure = { () -> Void in
            // this call will raise an exception if the session is invalid
            self.dataTask = Optional(self.session.dataTaskWithRequest(urlRequest) { (data: NSData?, urlResponse: NSURLResponse?, error: NSError?) -> Void in
                self.processResponseData(data, urlResponse: urlResponse, error: error, completion: completion)
                self.executeCompletion(workCompletion)
                })
        }
        
        let catchClosure = { (exception: NSException) in
            // session is invalid, cannot create a data task.
            self.dataTask = nil;
        }
        
        if tryCatch(tryClosure, catchClosure) || self.dataTask == nil {
            let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled, userInfo: nil)
            self.completeWithObject(nil, data:nil, httpResponse:nil, error:error, completion:completion)
            self.executeCompletion(workCompletion)
            return
        }
        
        if !quiet {
            self.logRequest()
        }
        
        dispatch_async(dispatch_get_main_queue()) {
            NSNotificationCenter.defaultCenter().postNotificationName(NETRequestDidStartNotification, object:self)
        }
        
        self.dataTask?.resume()
    }

    private func processResponseData(data: NSData?, urlResponse: NSURLResponse?, error: NSError?, completion: Response) {
        
        dispatch_async(dispatch_get_main_queue()) {
            NSNotificationCenter.defaultCenter().postNotificationName(NETRequestDidEndNotification, object:self)
        }
        
        if let httpResponse = urlResponse as? NSHTTPURLResponse {
            
            if self.cancelled || self.dataTask?.state == .Canceling {
                let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled, userInfo: nil)
                self.completeWithObject(nil, data:nil, httpResponse:nil, error:error, completion:completion)
                return;
            }
            
            // We dispatch async to not block the networking serial queue
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
                
                let headers = httpResponse.allHeaderFields as! [String:String]
                
                var object: Any?
                
                if error == nil && httpResponse.statusCode >= 200 && httpResponse.statusCode <= 299 {
                    if let data = data {
                        object = self.convertData(data, contentType: headers["Content-Type"]!)
                    }
                }
                
                if !self.quiet {
                    self.logResponse(object, data: data, httpResponse: httpResponse, error: error)
                }
                
                self.executing = false
                self.dataTask = nil
                
                self.completeWithObject(object, data:data, httpResponse:httpResponse, error:error, completion:completion)
            }
        }
    }
    
    private func convertData(data: NSData, contentType: String) -> Any? {
        
        let components = contentType.componentsSeparatedByString(";")
        let type = components.first?.lowercaseString
        let couple = components.last?.componentsSeparatedByString("=")
        let charset = couple?.first == "charset" ? couple?.last : nil
        var encoding = NSUTF8StringEncoding
        
        if let charset = charset {
            let coding = CFStringConvertIANACharSetNameToEncoding(charset)
            encoding = CFStringConvertEncodingToNSStringEncoding(coding)
        }
        
        if type == "text/html" {
            return NSString(data: data, encoding: encoding)
        }
        
        for (mimeType, closure) in MimePart.subclasses() {
            if mimeType == type {
                if let result = closure(data: data) {
                    return result.content
                }
            }
        }
        
        return data
    }

    
// MARK: - helpers -
    
    private func executeCompletion(completion: Completion?) {
        if let completion = completion {
            completion()
        }
    }
    
    public var description : String {
        return "\(self.dynamicType) - \(url)"
    }
    
    public var debugDescription : String {
        return "\(self.dynamicType) #\(uid) (\(unsafeAddressOf(self))) - \(url)"
    }


}


