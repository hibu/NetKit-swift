//
//  Request.swift
//  NetKit
//
//  Created by Marc Palluat de Besset on 20/11/2015.
//  Copyright © 2015 hibu. All rights reserved.
//

import Foundation

public typealias Response = (object: Any?, httpResponse: NSHTTPURLResponse?, error: NSError?) -> Void
public typealias Completion = () -> Void
public typealias ControlPoint = (Completion?) -> Void

public let NETRequestDidStartNotification = "NETRequestDidStartNotification"
public let NETRequestDidEndNotification = "NETRequestDidEndNotification"

private var gUID = 1
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

public class Request {
    public let session: NSURLSession
    public let method: String
    public let uid: Int

    public var headers = Dictionary<String, Any>()
    public var urlComponents = NSURLComponents()
    public var body: MimePart?
    public var completesOnGlobalQueue = false
    public var quiet: Bool = false
    public var logRawResponseData: Bool = false
    public var timeout: NSTimeInterval?
    
    public var flags: [String:Any]?
    private var upload: Bool = false
    
    private (set) public var executing = false
    private (set) public var cancelled = false
    private var dataTask: NSURLSessionDataTask?
    private var _request: Request?
    
// MARK: - init / deinit -
    public init(session: NSURLSession = NSURLSession.sharedSession(), httpMethod: String = "GET", flags: [String:Any]? = nil) {
        self.session = session
        method = httpMethod
        uid = assignUID()
        self.flags = flags
        
#if DEBUG
        quiet = false
#else
        quiet = true
#endif
        
        buildUrl { components in
            components.scheme = "https"
            components.port = 443
        }
    }
    
    deinit {
        if !quiet {
            DLog("\(self.description) - deinit")
        }
    }

// MARK: - getters / setters -
    public func buildUrl(componentsBlock: NSURLComponents -> Void) {
        componentsBlock(urlComponents)
    }
    
    public var urlString: String? {
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
    
    public var url: NSURL? {
        get {
            return urlComponents.URL
        }
        set(url) {
            if let url = url, let components = NSURLComponents(URL: url, resolvingAgainstBaseURL: false) {
                urlComponents = components
            }
        }
    }
    
    public func addHeaders(newHeaders: [String:Any]) {
        headers += newHeaders
    }
    
// MARK: - API -
    
    public func start(completion: Response) {
        if executing {
            fatalError("start called on a request already started")
        }
        
        let work = controlPointClosure(completion)
        executeControlPointClosure(work)
        _request = self
    }
    
    public func startUpload() {
        if executing {
            fatalError("start called on a request already started")
        }
        
        upload = true
        let work = controlPointClosure({_,_,_ in })
        executeControlPointClosure(work)
        _request = self
    }

    
    public func cancel() {
        cancelled = true
        dataTask?.cancel()
    }
    
 // MARK: - overrides -
    
    public func executeControlPointClosure(work: ControlPoint) {
        work(nil)
    }
    
    public func didReceiveData(data: NSData?, inout object: Any?, inout httpResponse: NSHTTPURLResponse?, inout error: NSError?, completion: Response) -> Bool {
        return true
    }
    
    public func configureRequest() throws {
        
    }
    
    public func configureURLRequest(urlRequest: NSMutableURLRequest) throws {
        
    }
    
    public func sessionDescription() -> String {
        if let description = self.session.sessionDescription {
            return description;
        }
        
        if self.session == NSURLSession.sharedSession() {
            return "shared session"
        }
        
        return ""
    }

    public func logRequest() {
        let desc = sessionDescription()
        
        dispatch_async(dispatch_get_main_queue()) { () -> Void in
            DLog("\n")
            DLog("****** \(self.method) REQUEST #\(self.uid) \(desc) ******")
            DLog(NSString(format:"URL = %@", self.url == nil ? "" : self.url!))
            DLog("Headers = \(self.headers)")
            self.body?.dataRepresentation { (data) -> Void in
                if let data = data {
                    DLog("Body = \(data)")
                }
            }
            DLog("****** \\REQUEST #\(self.uid) ******")
            DLog("\n")
        }
    }
    
    public func logResponse(object: Any?, data: NSData?, httpResponse: NSHTTPURLResponse?, error: NSError?) {
        dispatch_async(dispatch_get_main_queue()) { () -> Void in
            var logRaw = false
            let headers = httpResponse?.allHeaderFields as? [String:String]
            var statusStr = ""
            if let statusCode = httpResponse?.statusCode {
                statusStr = "\(statusCode)"
            }
            
            DLog("\n")
            DLog("****** RESPONSE #\(self.uid) status: \(statusStr) ******")
            DLog(NSString(format:"URL = %@", self.url == nil ? "" : self.url!))
            if let headers = headers {
            DLog("Headers = \(headers)")
            }
            if let error = error {
                DLog("Error = \(error)")
            }
            
            var size = 0
            if let length = headers?["content-length"] {
                if let sizeInt = Int(length) {
                    size = sizeInt
                }
            }
            
            if let data = data where size == 0 {
                size = data.length;
            }
            
            let formatter = NSByteCountFormatter()
            var sizeString = formatter.stringFromByteCount(Int64(size))
            
            if let encoding = headers?["content-encoding"] {
                sizeString = "\(encoding) \(sizeString)"
            }
            
            if let object = object as? CustomStringConvertible {
                DLog("Body (\(sizeString)) = " + object.description)
            } else {
                logRaw = true
            }
            
            if let data = data where self.logRawResponseData || logRaw {
                if let dataStr = NSString(data: data, encoding: NSUTF8StringEncoding) {
                    DLog(NSString(format:"Body (raw, \(sizeString)) = %@", dataStr))
                } else {
                    DLog("Body (raw, \(sizeString)) = \(data)")
                }
            }
            DLog("****** \\RESPONSE #\(self.uid) ******")
            DLog("\n")
        }
    }
    
    
// MARK: - private methods -
    private func completeWithObject(object: Any?, data: NSData?, httpResponse: NSHTTPURLResponse?, error: NSError?, completion:Response) {
        
        var theObject = object
        var theHttpResponse = httpResponse
        var theError = error
        
        if didReceiveData(data, object:&theObject, httpResponse: &theHttpResponse, error: &theError, completion:completion) {
        
            let response = { () -> Void in
                completion(object: theObject, httpResponse: theHttpResponse, error: theError)
            }
            
            if completesOnGlobalQueue {
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), response)
            } else {
                executeOnMainThread(response)
            }
        }
        
        _request = nil
    }
    
    private func urlRequest(completion: NSMutableURLRequest? -> Void) {
        guard let url = self.url else { completion(nil); return }
        
        let mRequest = NSMutableURLRequest(URL: url)
        mRequest.HTTPMethod = self.method
        
        if let timeout = timeout {
            mRequest.timeoutInterval = timeout
        }
        
        let group = dispatch_group_create()
        
        if let body = body {
            dispatch_group_enter(group);
            body.dataRepresentation { (data: NSData?) -> Void in
                if let data = data {
                    mRequest.HTTPBody = data
                    let length: String = String(format: "%ld", data.length)
                    let type: String = body.mimeType
                    self.addHeaders(["content-length" : length, "content-type" : type])
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
    
    private func controlPointClosure(responseCompletion: Response) -> ControlPoint {
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
            if self.upload {
                let url = NSURL.fileURLWithPath(NSTemporaryDirectory() + NSUUID().UUIDString)
                
                if let data = urlRequest.HTTPBody {
                    try! data.writeToURL(url, options: [.DataWritingAtomic])
                    urlRequest.HTTPBody = nil
                }
                
                self.dataTask = self.session.uploadTaskWithRequest(urlRequest, fromFile: url)
            } else {
            // this call will raise an exception if the session is invalid
                self.dataTask = self.session.dataTaskWithRequest(urlRequest) { (data, response, error) in
                    self.processResponseData(data, urlResponse: response, error: error, completion: completion)
                    self.executeCompletion(workCompletion)
                }
            }
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
        
        if upload {
            _request = nil
        }
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
                
                if error == nil {
                    
                    var type = ""
                    
                    if (headers["content-type"] != nil) {
                        type = headers["content-type"]!
                    } else if (headers["Content-Type"] != nil) {
                        type = headers["Content-Type"]!
                    }
                    
                    if let data = data {
                        object = self.convertData(data, contentType: type)
                    }
                }
                
                if !self.quiet {
                    self.logResponse(object, data: data, httpResponse: httpResponse, error: error)
                }
                
                self.executing = false
                self.dataTask = nil
                
                self.completeWithObject(object, data:data, httpResponse:httpResponse, error:error, completion:completion)
            }
        } else if let error = error {
            if !self.quiet {
                self.logResponse(nil, data: nil, httpResponse: nil, error: error)
            }

            self.completeWithObject(nil, data:nil, httpResponse:nil, error:error, completion:completion)
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
            return NSString(data: data, encoding: encoding) as? String
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

}

extension Request : CustomStringConvertible {
    public var description : String {
        return "\(self.dynamicType) #\(uid)"
    }
}

extension Request : CustomDebugStringConvertible {
    public var debugDescription : String {
        return "\(self.dynamicType) #\(uid) (\(unsafeAddressOf(self))) - \(url)"
    }
}


