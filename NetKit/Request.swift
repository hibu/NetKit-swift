//
//  Request.swift
//  NetKit
//
//  Created by Marc Palluat de Besset on 20/11/2015.
//  Copyright © 2015 hibu. All rights reserved.
//

import Foundation

public typealias Response = (_ object: Any?, _ httpResponse: HTTPURLResponse?, _ error: Error?) -> Void
public typealias Completion = () -> Void
public typealias ControlPoint = (Completion?) -> Void

public let NETRequestDidStartNotification = Notification.Name("NETRequestDidStartNotification")
public let NETRequestDidEndNotification = Notification.Name("NETRequestDidEndNotification")

private var gUID = 1
internal let lockQueue = DispatchQueue(label: "com.hibu.NetKit.Request.lock", qos: .default)

// MARK: - functions -

private func assignUID() -> Int {
    var uid = 0;
    lockQueue.sync {
        uid = gUID
        gUID += 1
    }
    return uid
}

public func executeOnMainThread( _ closure: @escaping () -> Void ) {
    if Thread.isMainThread {
        closure()
    } else {
        DispatchQueue.main.async(execute: closure)
    }
}

public enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

// MARK: - class Request -

/*
 class Request
 
 typical use:
 
 let request = Request()
 request.urlString = "http://apple.com"
 request.headers = ["Accept": "text/html"]
 request.start { (object, response, error) in
    if let html = object as String {
        print(html)
    }
 }
 
 */
public class Request {
    public let session: URLSession
    public let method: HTTPMethod
    public let uid: Int

    public var headers = Dictionary<String, Any>()
    public var urlComponents = URLComponents()
    public var body: MimePart?
    public var completesOnGlobalQueue = false
    public var quiet: Bool = false
    public var logRawResponseData: Bool = false
    public var timeout: TimeInterval?
    
    public var flags: [String:Any]?
    private var upload: Bool = false
    private var taskGroup = DispatchGroup()
    
    private (set) public var executing = false
    private (set) public var cancelled = false
    private var dataTask: URLSessionDataTask? { didSet { if dataTask != nil { taskGroup.leave() } } }
    private var _request: Request?
    
// MARK: - init / deinit -
    public init(session: URLSession = URLSession.shared, httpMethod: HTTPMethod = .get, flags: [String:Any]? = nil) {
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
    public func buildUrl(_ componentsBlock: (inout URLComponents) -> Void) {
        componentsBlock(&urlComponents)
    }
    
    public var urlString: String? {
        get {
            return urlComponents.url?.absoluteString
        }
        set(string) {
            if let string = string, let url = URL(string: string) {
                if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                    urlComponents = components
                }
            }
        }
    }
    
    public var url: URL? {
        get {
            return urlComponents.url
        }
        set(url) {
            if let url = url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                urlComponents = components
            }
        }
    }
    
    public func addHeaders(_ newHeaders: [String:Any]) {
        headers += newHeaders
    }
    
// MARK: - API -
    
    public func start(_ completion: @escaping Response) {
        if executing {
            fatalError("start called on a request already started")
        }
        
        taskGroup.enter()
        let work = controlPointClosure(completion)
        executeControlPointClosure(work)
        _request = self
        
    }
    
    public func startUpload(_ task: @escaping (URLSessionUploadTask) -> Void) {
        if executing {
            fatalError("start called on a request already started")
        }
        
        taskGroup.enter()
        upload = true
        let work = controlPointClosure({_,_,_ in })
        executeControlPointClosure(work)
        _request = self
        
        taskGroup.notify(queue: DispatchQueue.main) {
            if let uploadTask = self.dataTask as? URLSessionUploadTask {
                task(uploadTask)
            }
        }
    }

    
    public func cancel() {
        cancelled = true
        dataTask?.cancel()
    }
    
 // MARK: - overrides -
    
    public func executeControlPointClosure(_ work: ControlPoint) {
        work(nil)
    }
    
    public func didReceiveData(_ data: Data?, object: inout Any?, httpResponse: inout HTTPURLResponse?, error: inout Error?, completion: @escaping Response) -> Bool {
        return true
    }
    
    public func configureRequest() throws {
        
    }
    
    public func configureURLRequest(_ urlRequest: NSMutableURLRequest, completion: Response) throws {
        
    }
    
    public func sessionDescription() -> String {
        if let description = self.session.sessionDescription {
            return description;
        }
        
        if self.session == URLSession.shared {
            return "shared session"
        }
        
        return ""
    }

    public func logRequest() {
        let desc = sessionDescription()
        
        DispatchQueue.main.async { () -> Void in
            DLog("\n")
            DLog("****** \(self.method) REQUEST #\(self.uid) \(desc) ******")
            DLog(NSString(format:"URL = %@", self.url == nil ? "" : self.url!.absoluteString))
            DLog("Headers = \(self.headers)")
            self.body?.dataRepresentation { (data) -> Void in
                if let data = data {
                    DLog("Body = \(data.subdata(in: 0..<min(data.count, 20)))")
                }
            }
            DLog("****** \\REQUEST #\(self.uid) ******")
            DLog("\n")
        }
    }
    
    public func logResponse(_ object: Any?, data: Data?, httpResponse: HTTPURLResponse?, error: Error?) {
        DispatchQueue.main.async { () -> Void in
            var logRaw = false
            let headers = httpResponse?.allHeaderFields as? [String:String]
            var statusStr = ""
            if let statusCode = httpResponse?.statusCode {
                statusStr = "\(statusCode)"
            }
            
            DLog("\n")
            DLog("****** RESPONSE #\(self.uid) status: \(statusStr) ******")
            DLog(NSString(format:"URL = %@", self.url == nil ? "" : self.url!.absoluteString))
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

            if let data = data, size == 0 {
                size = data.count;
            }
            
            let formatter = ByteCountFormatter()
            var sizeString = formatter.string(fromByteCount: Int64(size))
            
            if let encoding = headers?["content-encoding"] {
                sizeString = "\(encoding) \(sizeString)"
            }
            
            if let object = object as? CustomStringConvertible {
                DLog("Body (\(sizeString)) = " + object.description)
            } else {
                logRaw = true
            }
            
            if let data = data, self.logRawResponseData || logRaw {
                if let dataStr = NSString(data: data, encoding: String.Encoding.utf8.rawValue) {
                    DLog(NSString(format:"Body (raw, \(sizeString)) = %@" as NSString, dataStr))
                } else {
                    DLog("Body (raw, \(sizeString)) = \(data)")
                }
            }
            DLog("****** \\RESPONSE #\(self.uid) ******")
            DLog("\n")
        }
    }
    
    
// MARK: - private methods -
    private func completeWithObject(_ object: Any?, data: Data?, httpResponse: HTTPURLResponse?, error: Error?, completion:@escaping Response) {
        
        var theObject = object
        var theHttpResponse = httpResponse
        var theError = error
        
        if didReceiveData(data, object:&theObject, httpResponse: &theHttpResponse, error: &theError, completion:completion) {
        
            let response = { () -> Void in
                completion(theObject, theHttpResponse, theError)
            }
            
            if completesOnGlobalQueue {
                let globalQueue = DispatchQueue.global( qos: .default)
                globalQueue.async( execute: response)
            } else {
                executeOnMainThread(response)
            }
        }
        
        _request = nil
    }
    
    private func urlRequest(_ completion: @escaping (NSMutableURLRequest?) -> Void) {
        guard let url = self.url else { completion(nil); return }
        
        let mRequest = NSMutableURLRequest(url: url)
        mRequest.httpMethod = self.method.rawValue
        
        if let timeout = timeout {
            mRequest.timeoutInterval = timeout
        }
        
        let group = DispatchGroup()
        
        if let body = body {
            group.enter();
            body.dataRepresentation { (data: Data?) -> Void in
                if let data = data {
                    mRequest.httpBody = data
                    let length: String = String(format: "%ld", data.count)
                    let type: String = body.mimeType
                    self.addHeaders(["content-length" : length, "content-type" : type])
                }
                group.leave()
            }
        }
        
        for (header, value) in self.headers {
            mRequest.setValue("\(value)", forHTTPHeaderField:header)
        }
        
        group.notify(queue: DispatchQueue.main) { () -> Void in
            completion(mRequest)
        }
    }
    
    private func controlPointClosure(_ responseCompletion: @escaping Response) -> ControlPoint {
        return { (workCompletion: Completion?) -> Void in
            
            let work = self.mainThreadClosure(responseCompletion, workCompletion: workCompletion)
            executeOnMainThread(work)
        }
    }
    
    private func mainThreadClosure(_ completion: @escaping Response, workCompletion: Completion?) -> Completion {
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
            } catch let error {
                self.completeWithObject(nil, data: nil, httpResponse: nil, error: error, completion: completion)
                self.executeCompletion(workCompletion)
                return
            }
            
            self.urlRequest { (urlRequest: NSMutableURLRequest?) -> Void in
                if let urlRequest = urlRequest {
                    let globalQueue = DispatchQueue.global( qos: .default)
                    globalQueue.async {
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

    private func executeDataTaskWithURLRequest(_ urlRequest: NSMutableURLRequest, completion: @escaping Response, workCompletion: Completion?) {
        do {
            try configureURLRequest(urlRequest, completion: completion)
        } catch let error {
            self.completeWithObject(nil, data:nil, httpResponse:nil, error:error, completion:completion)
            self.executeCompletion(workCompletion)
            return
        }
        
        let tryClosure = { () -> Void in
            if self.upload {
                let url = URL(fileURLWithPath: NSTemporaryDirectory() + UUID().uuidString)
                
                if let data = urlRequest.httpBody {
                    try! data.write(to: url, options: [.atomic])
                    urlRequest.httpBody = nil
                }
                
                self.dataTask = self.session.uploadTask(with: urlRequest as URLRequest, fromFile: url)
            } else {
            // this call will raise an exception if the session is invalid
                self.dataTask = self.session.dataTask(with: urlRequest as URLRequest) { (data, response, error) in
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
        
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: NETRequestDidStartNotification, object:self)
        }
        
        self.dataTask?.resume()
        
        if upload {
            _request = nil
        }
    }

    public func processResponseData(_ data: Data?, urlResponse: URLResponse?, error: Error?, completion: @escaping Response) {
        
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: NETRequestDidEndNotification, object:self)
        }
        
        if let httpResponse = urlResponse as? HTTPURLResponse {
            
            if self.cancelled || self.dataTask?.state == .canceling {
                let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled, userInfo: nil)
                self.completeWithObject(nil, data:nil, httpResponse:nil, error:error, completion:completion)
                return;
            }
            
            // We dispatch async to not block the networking serial queue
            let globalQueue = DispatchQueue.global( qos: .default)
            globalQueue.async {
                let headers = httpResponse.allHeaderFields as! [String:String]
                
                var object: Any?
                
                if error == nil {
                    
                    var type = ""
                    
                    if headers["content-type"] != nil {
                        type = headers["content-type"]!
                    } else if headers["Content-Type"] != nil {
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
    
    private func convertData(_ data: Data, contentType: String) -> Any? {
        
        let components = contentType.components(separatedBy: ";")
        let type = components.first?.lowercased()
        let couple = components.last?.components(separatedBy: "=")
        let charset = couple?.first == "charset" ? couple?.last : nil
        var encoding = String.Encoding.utf8
        
        if let charset = charset {
            let coding = CFStringConvertIANACharSetNameToEncoding(charset as CFString!)
            encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(coding))
        }
        
        if type == "text/html" {
            return NSString(data: data, encoding: encoding.rawValue) as? String
        }
        
        for (mimeType, closure) in MimePart.subclasses() {
            if mimeType == type {
                if let result = closure(data) {
                    return result.content
                }
            }
        }
        
        return data
    }

    
// MARK: - helpers -
    
    private func executeCompletion(_ completion: Completion?) {
        if let completion = completion {
            completion()
        }
    }

}

extension Request : CustomStringConvertible {
    public var description : String {
        return "\(type(of: self)) #\(uid)"
    }
}

extension Request : CustomDebugStringConvertible {
    public var debugDescription : String {
        return "\(type(of: self)) #\(uid) (\(Unmanaged.passUnretained(self).toOpaque())) - \(url)"
    }
}


