//
//  Request.swift
//  NetKit2
//
//  Created by Marc Palluat de Besset on 22/09/2016.
//  Copyright © 2016 hibu. All rights reserved.
//

import UIKit

let NetKitVersionNumber: Double = 2.0
let NetKitVersionString = "2.0".cString(using: String.Encoding.utf8)


private typealias Queue = DispatchQueue
public typealias Plist = [String:Any]

public let RequestDidStartNotification = NSNotification.Name("NetKitRequestDidStartNotification")
public let RequestDidEndNotification = NSNotification.Name("NetKitRequestDidEndNotification")

public enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case head = "HEAD"
    case connect = "CONNECT"
    case options = "OPTIONS"
}

public protocol ViewControllerSession: class {
    var session: URLSession? { get set }
}

public protocol MockManaging {
    var folderKey: String { get set }
    var mockEnabled: Bool { get set }
    func loadData(forKey key: String, completion: (Data?, HTTPURLResponse?, Error?) -> Void)
}

public protocol MockRecording: MockManaging {
    var mockRecordingEnabled: Bool { get set }
    func store(data: Data, response: HTTPURLResponse, forKey key: String)
}

public protocol Endpoint: class {}

public protocol EndpointSession: Endpoint {
    func session(forRequest request: Request?, viewController: ViewControllerSession?, flags: Plist?) -> URLSession
}

public protocol EndpointMockManager: Endpoint {
    func mockManager(forRequest request: Request, flags: Plist?) -> MockManaging?
}

public protocol EndpointConfiguration: Endpoint {
    func configure(request: Request, flags: Plist?) throws
}

public protocol EndpointControl: Endpoint {
    func control(request: Request, flags: Plist?, completion: (Bool, (() -> Void)?) -> Void)
}

public protocol EndpointURLRequestConfiguration: Endpoint {
    func configure(request: Request, urlRequest: URLRequest, flags: Plist?) throws -> URLRequest
}

public protocol EndpointResponseParsing: Endpoint {
    func parse(object: inout Any?, data: inout Data?, httpResponse: inout HTTPURLResponse?, error: inout Error?, completion: (Any?, HTTPURLResponse?, Error?) -> Void) -> Bool
}

public protocol BackgroundURLSession {
    // make your app delegate conform to this protocol to get the implementation
    // of the application(handleEventsForBackgroundURLSession:) method (defined below)
}

public extension BackgroundURLSession {
    
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        
        // recreate or get the session used for the background transfer
        if let endpoint = backgroundTransferEndpoints[identifier] {
            let _ = endpoint.session(forRequest: nil, viewController: nil, flags: nil)
        }
        
        // give time for the UI to update itself
        Queue.main.async {
            completionHandler()
        }
    }
}

fileprivate var backgroundTransferEndpoints: [String:EndpointSession] = [:]

public func register(backgroundTransferEndpoint endpoint: EndpointSession, urlSessionIdentifier identifier: String) {
    backgroundTransferEndpoints[identifier] = endpoint
}

open class Request {
    private static var gUID = 1
    fileprivate static let lock = Queue(label: "com.hibu.NetKit.Request.lock")
    
    public let method: HTTPMethod
    public let uid: Int
    public var flags: [String:Any]?
    public var quiet: Bool = true
    public var urlBuilder = URLComponents()
    public var headers: [String : Any] = [:]
    public var body: MimeConverter?
    public var timeout: TimeInterval?
    public var logRawResponseData: Bool = false
    public var notify = false
    public weak var viewController: ViewControllerSession?
    public var mockManager: MockManaging?
    public var mockEnabled = false
    public var apiMockKey: String?
    
    public fileprivate(set) var endpoint: Endpoint?
    public fileprivate(set) var session: URLSession
    public fileprivate(set) var executing = false
    public fileprivate(set) var cancelled = false
    
    fileprivate var upload: Bool = false
    fileprivate var dataTask: URLSessionDataTask?
    fileprivate var completionQueue: DispatchQueue = Queue.main
    fileprivate var taskGroup: DispatchGroup
    
    
    class func generateUid() -> Int {
        var uid = 0
        Request.lock.sync {
            uid = Request.gUID
            Request.gUID += 1
        }
        return uid
    }
    
    public init(endpoint: Endpoint? = nil, session: URLSession = URLSession.shared, method: HTTPMethod = .get, flags: [String:Any]? = nil) {
        
        self.session = session
        self.method = method
        self.uid = Request.generateUid()
        self.taskGroup = DispatchGroup()
        
        self.flags = flags
        
        self.urlBuilder.scheme = "https"
        self.urlBuilder.port = 443
    }
    
    deinit {
        if !quiet {
            DLog("\(self.description) - deinit")
        }
    }
    
    public var urlString: String? {
        get {
            return urlBuilder.url?.absoluteString
        }
        set(string) {
            if let string = string, let url = URL(string: string) {
                if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                    urlBuilder = components
                }
            }
        }
    }
    
    public var url: URL? {
        get {
            return urlBuilder.url
        }
        set(url) {
            if let url = url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                urlBuilder = components
            }
        }
    }
    
    public func addHeaders(newHeaders: [String:Any]) {
        newHeaders.forEach { self.headers[$0] = $1 }
    }
    
    fileprivate func urlRequest() -> URLRequest? {
        guard let url = self.url else { return nil }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = self.method.rawValue
        
        if let timeout = timeout {
            urlRequest.timeoutInterval = timeout
        }
        
        if let body = body {
            if let data = try? body.convert() {
                urlRequest.httpBody = data
                let length: String = String(format: "%ld", data.count)
                let type: String = body.mimeType
                self.addHeaders(newHeaders: ["content-length" : length, "content-type" : type])
            }
        }
        
        for (header, value) in self.headers {
            urlRequest.setValue("\(value)", forHTTPHeaderField:header)
        }
        
        return urlRequest
    }
    
}

extension Request {
    
    public func start<T>(queue: DispatchQueue = Queue.main, completion: @escaping (T?, HTTPURLResponse?, Error?) -> Void) {
        if executing {
            fatalError("start called on a request already started")
        }
        
        #if !DEBUG
            quiet = true
        #endif
        
        completionQueue = queue
        
        if mockManager == nil, let endpoint = self.endpoint as? EndpointMockManager {
            mockManager = endpoint.mockManager(forRequest: self, flags: flags)
        }
        
        if let manager = mockManager, let key = apiMockKey, manager.mockEnabled || mockEnabled {
            manager.loadData(forKey: key) { (data, response, error) in
                self.logRequest(mock: true)
                self.parse(data: data, urlResponse: response, error: error, mock: true, completion: completion)
            }
            return
        }
        
        taskGroup.enter()
        
        if let endpoint = self.endpoint as? EndpointControl {
            endpoint.control(request: self, flags: flags, completion: prepare(completion: completion))
        } else {
            prepare(completion: completion)(true, nil)
        }
    }
    
    public func startUpload(task: @escaping (URLSessionUploadTask) -> Void) {
        if executing {
            fatalError("start called on a request already started")
        }
        
        taskGroup.enter()
        upload = true
        
        let completion: (String?, HTTPURLResponse?, Error?) -> Void = { (str, response, error) in
            // do nothing, will probably never be called
        }
        
        prepare(completion: completion)(true, nil)
        
        taskGroup.notify(queue: Queue.main) {
            if let uploadTask = self.dataTask as? URLSessionUploadTask {
                task(uploadTask)
            }
        }
    }
    
    
    public func cancel() {
        cancelled = true
        dataTask?.cancel()
    }
    
    private func prepare<T>(completion: @escaping (T?, HTTPURLResponse?, Error?) -> Void) -> (_ proceed: Bool, _ throttledQueueCompletion: (() -> Void)?) -> Void {
        return { (proceed: Bool, throttledQueueCompletion: (() -> Void)?) in
            Queue.global().async {
                
                if self.cancelled {
                    throttledQueueCompletion?()
                    let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled, userInfo: nil)
                    self.complete(error: error, completion: completion)
                    return
                }
                
                self.executing = true
                
                if let sessionEndpoint = self.endpoint as? EndpointSession, self.session == URLSession.shared {
                    self.session = sessionEndpoint.session(forRequest: self, viewController: self.viewController, flags: self.flags)
                }
                
                if let endpoint = self.endpoint as? EndpointConfiguration {
                    do {
                        try endpoint.configure(request: self, flags: self.flags)
                    } catch let error as NSError {
                        self.executing = false
                        throttledQueueCompletion?()
                        self.complete(error: error, completion: completion)
                        return
                    }
                }
                
                if let urlRequest = self.urlRequest() {
                    self.executeDataTask(with: urlRequest, completion: completion, throttledQueueCompletion: throttledQueueCompletion)
                } else {
                    self.executing = false
                    throttledQueueCompletion?()
                    let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorBadURL, userInfo: nil)
                    self.complete(error: error, completion: completion)
                    return
                }
            }
        }
    }
    
    private func executeDataTask<T>(with urlRequest: URLRequest, completion: @escaping (T?, HTTPURLResponse?, Error?) -> Void, throttledQueueCompletion: (() -> Void)?) {
        
        var finalURLRequest = urlRequest
        
        if let endpoint = self.endpoint as? EndpointURLRequestConfiguration {
            do {
                finalURLRequest = try endpoint.configure(request: self, urlRequest: urlRequest, flags: flags)
            } catch let error as NSError {
                self.executing = false
                throttledQueueCompletion?()
                self.complete(error: error, completion: completion)
                return
            }
        }
        
        let result = tryCatch({
            
            if self.upload {
                let url = NSURL.fileURL(withPath: NSTemporaryDirectory() + NSUUID().uuidString)
                
                if let data = finalURLRequest.httpBody {
                    try! data.write(to: url, options: [.atomic])
                    finalURLRequest.httpBody = nil
                }
                
                // this call will raise an obj-c exception if the session is invalid
                self.dataTask = self.session.uploadTask(with: finalURLRequest, fromFile: url)
                self.taskGroup.leave()
            } else {
                // this call will raise an obj-c exception if the session is invalid
                self.dataTask = self.session.dataTask(with: finalURLRequest) { (data, response, error) in
                    Queue.global(qos: .default).async {
                        self.parse(data: data, urlResponse: response, error: error, completion: completion)
                        throttledQueueCompletion?()
                    }
                }
                self.taskGroup.leave()
            }
            
        }, { (exception: NSException) in
            // session is invalid, cannot create a data task.
            self.dataTask = nil
        })
        
        if self.dataTask == nil || result {
            self.executing = false
            throttledQueueCompletion?()
            let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled, userInfo: nil)
            self.complete(error: error, completion: completion)
            return
        }
        
        if !quiet {
            self.logRequest()
        }
        
        self.dataTask?.resume()
        post(notificationNamed: RequestDidStartNotification)
    }
    
    private func parse<T>(data: Data?, urlResponse: URLResponse?, error: Error?, mock: Bool = false, completion: @escaping (T?, HTTPURLResponse?, Error?) -> Void) {
        
        post(notificationNamed: RequestDidEndNotification)
        
        if let httpResponse = urlResponse as? HTTPURLResponse {
            
            if self.cancelled || self.dataTask?.state == .canceling {
                let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled, userInfo: nil)
                self.complete(error: error, completion: completion)
                return
            }
            
            let headers = httpResponse.allHeaderFields as! [String:String]
            var object: Any?
            
            if error == nil {
                var type = ""
                
                if let aType = headers.filter({ return $0.key.lowercased() == "content-type" }).map({ $1 }).first {
                    type = aType
                }
                
                if let data = data {
                    object = self.convert(data: data, contentType: type)
                    
                    if let manager = self.mockManager as? MockRecording, let key = self.apiMockKey, manager.mockRecordingEnabled {
                        manager.store(data: data, response: httpResponse, forKey: key)
                    }
                }
            }
            
            if !self.quiet {
                self.logResponse(object: object, data: data, httpResponse: httpResponse, error: error, mock: mock)
            }
            
            self.executing = false
            self.dataTask = nil
            
            
            self.complete(object: object, data: data, httpResponse: httpResponse, error: error, completion: completion)
        } else if let error = error {
            if !self.quiet {
                self.logResponse(object: nil, data: nil, httpResponse: nil, error: error)
            }
            
            self.complete(error: error, completion: completion)
        }
    }
    
    
    private func complete<T>(object: Any? = nil, data: Data? = nil, httpResponse: HTTPURLResponse? = nil, error: Error? = nil, completion:@escaping (T?, HTTPURLResponse?, Error?) -> Void) {
        
        var theObject = object
        var theData = data
        var theHttpResponse = httpResponse
        var theError = error
        
        if let endpoint = endpoint as? EndpointResponseParsing {
            
            let complete = { (object: Any?, httpResponse: HTTPURLResponse?, error: Error?) in
                completion(object as? T, httpResponse, error)
            }
            
            let proceed = endpoint.parse(object: &theObject, data: &theData, httpResponse: &theHttpResponse, error: &theError, completion: complete)
            
            if !proceed {
                return
            }
        }
        
        completionQueue.async {
            completion(theObject != nil ? theObject as? T : theData as? T, theHttpResponse, theError)
        }
    }
    
}

extension Request {
    
    fileprivate func post(notificationNamed name: Notification.Name) {
        if notify {
            Queue.main.async {
                NotificationCenter.default.post(name: name, object:self)
            }
        }
    }
    
    fileprivate func convert(data: Data, contentType: String) -> Any? {
        
        let components = contentType.components(separatedBy: ";")
        if let type = components.first?.lowercased(),
            let couple = components.last?.components(separatedBy: "=") {
            
            let charset = couple.first == "charset" ? couple.last : nil
            var encoding = String.Encoding.utf8
            
            if let charset = charset {
                let coding = CFStringConvertIANACharSetNameToEncoding(charset as CFString!)
                encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(coding))
            }
            
            if type == "text/html" {
                return String(data: data, encoding: encoding)
            }
            
            for converter in converters {
                if converter.mimeTypes.contains(type) {
                    return try? converter.convert(data: data)
                }
            }
        }
        
        return data
    }
    
}

extension Request {
    
    open func sessionDescription() -> String {
        if let description = self.session.sessionDescription {
            return description;
        }
        
        if self.session == URLSession.shared {
            return "shared session"
        }
        
        return ""
    }
    
    open func logRequest(mock: Bool = false) {
        #if DEBUG
            let desc = sessionDescription()
            
            Queue.main.async {
                DLog("\n")
                DLog("****** \(mock ? "[MOCKED] " : "")\(self.method.rawValue.uppercased()) REQUEST #\(self.uid) \(desc) ******")
                DLog(NSString(format:"URL = %@", self.urlString == nil ? "" : self.urlString!))
                DLog("Headers = \(self.headers)")
                
                if let converter = self.body {
                    if let data = try? converter.convert() as NSData {
                        DLog("Body = \(data.subdata(with: NSRange(location: 0, length: min(data.length, 20))))")
                    }
                }
                
                DLog("****** \\REQUEST #\(self.uid) ******")
                DLog("\n")
            }
        #endif
    }
    
    open func logResponse(object: Any?, data: Data?, httpResponse: HTTPURLResponse?, error: Error?, mock: Bool = false) {
        
        #if DEBUG
            Queue.main.async {
                var logRaw = false
                let headers = httpResponse?.allHeaderFields as? [String:String]
                var statusStr = ""
                if let statusCode = httpResponse?.statusCode {
                    statusStr = "\(statusCode)"
                }
                
                DLog("\n")
                DLog("****** \(mock ? "[MOCKED] " : "")RESPONSE #\(self.uid) status: \(statusStr) ******")
                DLog(NSString(format:"URL = %@", self.urlString == nil ? "" : self.urlString!))
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
                        DLog(String(format:"Body (raw, \(sizeString)) = %@", dataStr))
                    } else {
                        DLog("Body (raw, \(sizeString)) = \(data)")
                    }
                }
                DLog("****** \\RESPONSE #\(self.uid) ******")
                DLog("\n")
            }
        #endif
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

private let formatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "d/M/yyyy H:m:ss.SSS"
    return f
}()

public func DLog<T>(_ message: T, file: String = #file, function: String = #function, line: Int = #line, showFile: Bool = false, showFunction: Bool = false, showLine: Bool = false) {
    #if DEBUG
        if let text = message as? String {
            
            var prefix = formatter.string(from: Date())
            
            if showFile {
                let file: NSString = file as NSString
                prefix = prefix + " " + file.lastPathComponent
            }
            
            if showFunction {
                prefix = prefix + " " + function
            }
            
            if showLine {
                prefix = prefix + " \(line)"
            }
            
            Queue.main.async {
                print("\(prefix): " + text, terminator: "\n")
            }
        }
    #endif
}

public extension URLComponents {
    public mutating func add(_ items: [URLQueryItem]) {
        if let qItems = queryItems {
            queryItems = qItems + items
        } else {
            queryItems = items
        }
    }
}



