import Foundation

class MockURLProtocol: URLProtocol {
    static nonisolated(unsafe) var requests: [URLRequest] = []
    static nonisolated(unsafe) var responseStatusCode = 200
    static nonisolated(unsafe) var responsesByURL: [String: Data] = [:]
    static nonisolated(unsafe) var statusCodesByURL: [String: Int] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // URLSession moves the body to httpBodyStream; reconstruct a copy with httpBody populated.
        var captured = request
        if captured.httpBody == nil, let stream = captured.httpBodyStream {
            stream.open()
            var bodyData = Data()
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4_096)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: 4_096)
                if read > 0 { bodyData.append(buffer, count: read) }
            }
            stream.close()
            captured.httpBody = bodyData
        }
        MockURLProtocol.requests.append(captured)

        let urlKey = request.url?.absoluteString ?? ""
        let statusCode = MockURLProtocol.statusCodesByURL[urlKey] ?? MockURLProtocol.responseStatusCode
        let responseData = MockURLProtocol.responsesByURL[urlKey] ?? Data()

        let response = HTTPURLResponse(
            url: request.url!,  // swiftlint:disable:this force_unwrapping
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!  // swiftlint:disable:this force_unwrapping
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
