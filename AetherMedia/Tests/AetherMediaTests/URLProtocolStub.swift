import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Every production-network test supplies a private URLSession with this protocol.
final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    struct Reply {
        var status = 200
        var body: Data
        var headers: [String: String] = ["Content-Type": "application/json"]
        var delay: TimeInterval = 0
        init(_ json: Any, status: Int = 200, delay: TimeInterval = 0) {
            self.status = status
            self.body = (try? JSONSerialization.data(withJSONObject: json, options: [.fragmentsAllowed])) ?? Data()
            self.delay = delay
        }
    }
    private static let lock = NSLock()
    private static var handler: ((URLRequest) throws -> Reply)?
    private let stateLock = NSRecursiveLock()
    private var stopped = false
    static func configure(_ handler: @escaping (URLRequest) throws -> Reply) {
        lock.lock(); defer { lock.unlock() }; Self.handler = handler
    }
    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: config)
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); let handler = Self.handler; Self.lock.unlock()
        do {
            guard let handler else { throw URLError(.badServerResponse) }
            var request = self.request
            // URLSession may deliver POST bodies through a stream rather than httpBody.
            if request.httpBody == nil, let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    data.append(buffer, count: count)
                }
                request.httpBody = data
            }
            let reply = try handler(request)
            let responseURL = request.url
            DispatchQueue.global().asyncAfter(deadline: .now() + reply.delay) { [self] in
                stateLock.lock(); defer { stateLock.unlock() }
                guard !stopped, let url = responseURL,
                      let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: nil, headerFields: reply.headers) else { return }
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: reply.body)
                client?.urlProtocolDidFinishLoading(self)
            }
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { stateLock.lock(); stopped = true; stateLock.unlock() }
}

final class RequestCounts: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Int] = [:]
    @discardableResult func increment(_ key: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        values[key, default: 0] += 1
        return values[key]!
    }
    func get(_ key: String) -> Int { lock.lock(); defer { lock.unlock() }; return values[key, default: 0] }
}
