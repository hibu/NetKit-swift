//
//  Request.swift
//  NetKit2
//
//  Created by Marc Palluat de Besset on 22/09/2016.
//  Copyright © 2016 hibu. All rights reserved.
//

import UIKit

private typealias Queue = DispatchQueue
public typealias Plist = [String:Any]

public let RequestDidStartNotification = NSNotification.Name("NetKitRequestDidStartNotification")
public let RequestDidEndNotification = NSNotification.Name("NetKitRequestDidEndNotification")

public struct ErrorString: Error, ExpressibleByStringLiteral {

    public typealias UnicodeScalarLiteralType = StringLiteralType
    public typealias ExtendedGraphemeClusterLiteralType = StringLiteralType
    
    public let description: String
    
    public init(extendedGraphemeClusterLiteral value: ExtendedGraphemeClusterLiteralType) {
        description = value
    }
    
    public init(unicodeScalarLiteral value: UnicodeScalarLiteralType) {
        description = "\(value)"
    }

    public init(stringLiteral value: StringLiteralType) {
        description = value
    }
    
    public init(_ value: String) {
        description = value
    }
}

public enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case head = "HEAD"
    case connect = "CONNECT"
    case options = "OPTIONS"
}

public protocol SessionDescriptor {}

fileprivate class Session: SessionDescriptor {
    let identifier: String
    let session: URLSession
    
    init(identifier: String, session: URLSession) {
        self.identifier = identifier
        self.session = session
    }
    
    deinit {
        session.invalidateAndCancel()
    }
}

public protocol ViewControllerSession: class {
    var sessions: [String:SessionDescriptor]? { get set }
}

public protocol MockManaging {
    var folderKey: String { get set }
    var mockEnabled: Bool { get set }
    func loadData(forKey key: String, url: URL, completion: (Data?, HTTPURLResponse?, Error?) -> Void)
}

public protocol MockRecording: MockManaging {
    var mockRecordingEnabled: Bool { get set }
    func store(data: Data, response: HTTPURLResponse, forKey key: String)
}

public protocol Endpoint: class {
    var identifier: String { get }
}

public protocol EndpointSession: Endpoint {
    func session(forRequest request: Request?, flags: Plist?) -> URLSession
}

public protocol EndpointMockManager: Endpoint {
    func mockManager(forRequest request: Request, flags: Plist?) -> MockManaging?
}

public protocol EndpointConfiguration: Endpoint {
    func configure(request: Request, flags: Plist?) throws
}

public protocol EndpointControl: Endpoint {
    func control(request: Request, flags: Plist?, completion: @escaping (Bool, (() -> Void)?) -> Void)
}

public protocol EndpointURLRequestConfiguration: Endpoint {
    func configure(request: Request, urlRequest: URLRequest, flags: Plist?) throws -> URLRequest
}

public protocol EndpointResponseParsing: Endpoint {
    func parse(object: inout Any?, data: inout Data?, request: Request, response: inout HTTPURLResponse?, error: inout Error?, flags: Plist?, completion: @escaping (Any?, HTTPURLResponse?, Error?) -> Void) -> Bool
}

public protocol EndpointErrorReasonStringExtracting: Endpoint {
    func extract(json: [AnyHashable:Any?]) -> String?
}

@objc public protocol BackgroundURLSession {}

public extension BackgroundURLSession {
    
    func handleEventsForBackgroundURLSession(identifier: String, completionHandler: @escaping () -> Void) {
        
        // recreate or get the session used for the background transfer
        if let endpoint = backgroundTransferEndpoints[identifier] {
            let _ = endpoint.session(forRequest: nil, flags: nil)
        }
        
        // give time for the UI to update itself
        Queue.main.async {
            completionHandler()
        }
    }
}

fileprivate var backgroundTransferEndpoints: [String:EndpointSession] = [:]

public func register(backgroundTransferEndpoint endpoint: EndpointSession) {
    backgroundTransferEndpoints[endpoint.identifier] = endpoint
}


public enum Result<T> {
    case success(T)
    case issue(HTTPURLResponse)
    case failure(Error)
    
    public init(value: T) {
        self = .success(value)
    }
    
    public init(error: Error) {
        self = .failure(error)
    }
    
    public init(error: ErrorString) {
        self = .failure(error)
    }
    
    public init(response: HTTPURLResponse) {
        self = .issue(response)
    }
    
    public init?(response: HTTPURLResponse?, error: Error?) {
        if let response = response, error == nil {
            self = .issue(response)
        } else if let error = error, response == nil {
            self = .failure(error)
        }
        return nil
    }

    public init(_ f: @autoclosure () throws -> T) {
        self.init(attempt: f)
    }
    
    public init(attempt f: () throws -> T) {
        do {
            self = .success(try f())
        } catch {
            self = .failure(error)
        }
    }
    
    public func map<U>(_ transform: (T) -> Result<U>) -> Result<U> {
        switch self {
        case .success(let value): return transform(value)
        case .issue(let response): return .issue(response)
        case .failure(let error): return .failure(error)
        }
    }
    
    public func flatMap<U>(_ transform: (T) -> U?) -> Result<U> {
        switch self {
        case .success(let value):
            if let newValue = transform(value) {
                return .success(newValue)
            }
            return Result<U>(error: "Couldn't transform value")
        case .issue(let response):
            return .issue(response)
        case .failure(let error):
            return .failure(error)
        }
    }

    
    @discardableResult public func withSuccess(closure: (T) -> Void) -> Result<T> {
        switch self {
        case .success(let value): closure(value)
        default:()
        }
        return self
    }
    
    @discardableResult public func withIssue(closure: (HTTPURLResponse) -> Void) -> Result<T> {
        switch self {
        case .issue(let response): closure(response)
        default:()
        }
        return self
    }
    
    @discardableResult public func withFailure(closure: (Error) -> Void) -> Result<T> {
        switch self {
        case .failure(let error): closure(error)
        default:()
        }
        return self
    }
}

open class Request {
    private static var gUID = 1
    fileprivate static let lock = Queue(label: "com.hibu.NetKit.Request.lock")
    
    public static var userAgent: String?
    
    public let method: HTTPMethod
    public let uid: Int
    public var flags: [String:Any]?
    public var quiet: Bool = false
    public var urlBuilder = URLComponents()
    public var headers: [String : Any] = [:]
    public var body: MimeConverter?
    public var timeout: TimeInterval?
    public var logRawResponseData: Bool = false
    public static var notify = false
    public weak var viewController: ViewControllerSession?
    public var mockManager: MockManaging?
    public var mockEnabled = false
    public var apiMockKey: String?
    public var successRange = 200..<300
    
    public fileprivate(set) var endpoint: Endpoint?
    public fileprivate(set) var session: URLSession
    public fileprivate(set) var executing = false
    public fileprivate(set) var cancelled = false
    
    fileprivate var upload: Bool = false
    fileprivate var dataTask: URLSessionDataTask?
    fileprivate var completionQueue: DispatchQueue = Queue.main
    fileprivate var taskGroup: DispatchGroup
    fileprivate static var sessions: [String:URLSession] = [:]
    
    
    class func generateUid() -> Int {
        var uid = 0
        Request.lock.sync {
            uid = Request.gUID
            Request.gUID += 1
        }
        return uid
    }
    
    public class func session(for endpoint: Endpoint) -> URLSession? {
        if let session = sessions[endpoint.identifier] {
            return session
        } else {
            if let endpoint = endpoint as? EndpointSession {
                let session = endpoint.session(forRequest: nil, flags: nil)
                sessions[endpoint.identifier] = session
                return session
            }
        }
        return nil
    }
    
    public init(endpoint: Endpoint? = nil, session: URLSession = URLSession.shared, method: HTTPMethod = .get, flags: [String:Any]? = nil) {
        
        self.endpoint = endpoint
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
    
    public func add(headers: [String:Any]) {
        headers.forEach { self.headers[$0] = $1 }
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
                self.add(headers: ["content-length" : length, "content-type" : type])
            }
        }
        
        for (header, value) in self.headers {
            urlRequest.setValue("\(value)", forHTTPHeaderField:header)
        }
        
        if let userAgent = Request.userAgent {
            urlRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }
        
        return urlRequest
    }
    
}

extension Request {
    
    public func begin<T>(queue: DispatchQueue = Queue.main, result: @escaping (Result<T>) -> Void) {
        self.start(queue: queue) { (value: T?, response, error) in
            if let value = value, let response = response, self.successRange ~= response.statusCode {
                result(Result(value: value))
            } else if let value = value, let response = response,
                let endpoint = self.endpoint as? EndpointErrorReasonStringExtracting,
                type(of: value) == JSONDictionary.self {
                
                let json = value as! JSONDictionary
                var headers = response.allHeaderFields
                
                if let reason = endpoint.extract(json: json) {
                    headers["reason"] = reason
                }
                
                let newResponse = HTTPURLResponse(url: response.url!, statusCode: response.statusCode, httpVersion: "HTTP/1.1", headerFields: headers as? [String : String])!
                result(Result(response: newResponse))
            } else if let response = response {
                result(Result(response: response))
            } else if let error = error {
                result(Result(error: error))
            } else {
                assert(false, "no error and no HTTPURLResponse")
            }
        }
    }
    
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
            if let configurator = endpoint as? EndpointConfiguration {
                try? configurator.configure(request: self, flags: flags)
            }
        }
        
        if let manager = mockManager, let key = apiMockKey, let url = urlBuilder.url, manager.mockEnabled || mockEnabled {
            manager.loadData(forKey: key, url: url) { (data, response, error) in
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
                
                if self.session == URLSession.shared {
                    if let viewController = self.viewController, let endpoint = self.endpoint {
                        if let sessions = viewController.sessions {
                            if let descriptor = sessions[endpoint.identifier], let sessionDesc = descriptor as? Session {
                                self.session = sessionDesc.session
                            }
                        } else {
                            viewController.sessions = [:]
                        }
                        
                        if self.session == URLSession.shared {
                            if let sessionEndpoint = self.endpoint as? EndpointSession {
                                self.session = sessionEndpoint.session(forRequest: self, flags: self.flags)
                                viewController.sessions?[endpoint.identifier] = Session(identifier: endpoint.identifier, session: self.session)
                            }
                        }
                    } else {
                        if let endpoint = self.endpoint {
                            if let session = type(of:self).sessions[endpoint.identifier] {
                                self.session = session
                            } else {
                                if let sessionEndpoint = self.endpoint as? EndpointSession {
                                    self.session = sessionEndpoint.session(forRequest: self, flags: self.flags)
                                    type(of:self).sessions[endpoint.identifier] = self.session
                                }
                            }
                        }
                    }
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
            } else {
                // this call will raise an obj-c exception if the session is invalid
                self.dataTask = self.session.dataTask(with: finalURLRequest) { (data, response, error) in
                    Queue.global(qos: .default).async {
                        self.parse(data: data, urlResponse: response, error: error, completion: completion)
                        throttledQueueCompletion?()
                    }
                }
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
        
        if self.upload {
            self.taskGroup.leave()
            post(notificationNamed: RequestDidEndNotification)
        }
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
            
            
            self.complete(object: object, data: data, response: httpResponse, error: error, completion: completion)
        } else if let error = error {
            if !self.quiet {
                self.logResponse(object: nil, data: nil, httpResponse: nil, error: error)
            }
            
            self.complete(error: error, completion: completion)
        }
    }
    
    
    private func complete<T>(object: Any? = nil, data: Data? = nil, response: HTTPURLResponse? = nil, error: Error? = nil, completion:@escaping (T?, HTTPURLResponse?, Error?) -> Void) {
        
        var theObject = object
        var theData = data
        var theResponse = response
        var theError = error
        
        if let endpoint = endpoint as? EndpointResponseParsing {
            
            let complete = { (object: Any?, httpResponse: HTTPURLResponse?, error: Error?) in
                completion(object as? T, httpResponse, error)
            }
            
            let proceed = endpoint.parse(object: &theObject, data: &theData, request: self, response: &theResponse, error: &theError, flags: flags, completion: complete)
            
            if !proceed {
                return
            }
        }
        
        completionQueue.async {
            completion(theObject != nil ? theObject as? T : theData as? T, theResponse, theError)
        }
    }
    
}

extension Request {
    
    fileprivate func post(notificationNamed name: Notification.Name) {
        if Request.notify {
            Queue.main.async {
                NotificationCenter.default.post(name: name, object:self, userInfo: ["url": self.urlString ?? "unknown"])
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
            
            if true {
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
            if true {
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
        return "\(type(of: self)) #\(uid) (\(Unmanaged.passUnretained(self).toOpaque())) - \(String(describing: url))"
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
            
            if Thread.isMainThread {
                print("\(prefix): " + text)
            } else {
                Queue.main.sync { print("\(prefix): " + text) }
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

public extension HTTPURLResponse {
    var reason: String? {
        if let reason = allHeaderFields["reason"] as? String {
            return reason.uppercased()
        }
        return nil
    }
}



