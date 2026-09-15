import Foundation

/// 按顺序返回预设响应的 URLSession，记录请求过的路径。每个实例用独立的 token 区分，测试可以并行。
final class StubResponses: @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var registry: [String: StubResponses] = [:]

    private let token = UUID().uuidString
    private var queue: [(Int, String)]
    private(set) var requestedPaths: [String] = []
    let session: URLSession

    init(_ responses: [(Int, String)]) {
        queue = responses
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        config.httpAdditionalHeaders = ["x-stub-token": token]
        session = URLSession(configuration: config)
        Self.lock.withLock { Self.registry[token] = self }
    }

    fileprivate static func next(for request: URLRequest) -> (Int, Data)? {
        lock.withLock {
            guard let token = request.value(forHTTPHeaderField: "x-stub-token"),
                  let stub = registry[token], !stub.queue.isEmpty else { return nil }
            stub.requestedPaths.append(request.url?.lastPathComponent ?? "")
            let (status, body) = stub.queue.removeFirst()
            return (status, Data(body.utf8))
        }
    }
}

private final class StubProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let (status, body) = StubResponses.next(for: request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
