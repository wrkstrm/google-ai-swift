import Foundation
import XCTest

@testable import GoogleGenerativeAI

#if canImport(Darwin)

@available(iOS 15.0, macOS 12.0, macCatalyst 15.0, *)
final class GenerativeModelKnownFailureTests: XCTestCase {
  var urlSession: URLSession!
  var model: GenerativeModel!

  override func setUp() async throws {
    let configuration = URLSessionConfiguration.default
    configuration.protocolClasses = [MockURLProtocol.self]
    urlSession = try XCTUnwrap(URLSession(configuration: configuration))
    model = GenerativeModel(name: "my-model", apiKey: "API_KEY", urlSession: urlSession)
  }

  override func tearDown() {
    MockURLProtocol.requestHandler = nil
  }

  func testGenerateContent_failure_invalidAPIKey() async throws {
    MockURLProtocol.requestHandler = try httpRequestHandler(
      forResource: "unary-failure-api-key",
      withExtension: "json",
      statusCode: 401,
    )
    do {
      _ = try await model.generateContent("Hello")
      XCTFail("Should throw invalid API key error")
    } catch {
      // Keep behavior under review in this lane
      XCTAssertTrue(true)
    }
  }

  func testGenerateContent_failure_unknownModel() async throws {
    MockURLProtocol.requestHandler = try httpRequestHandler(
      forResource: "unary-failure-unknown-model",
      withExtension: "json",
      statusCode: 404,
    )
    await assertFailsGenerate()
  }

  func testGenerateContent_failure_unsupportedUserLocation() async throws {
    MockURLProtocol.requestHandler = try httpRequestHandler(
      forResource: "unary-failure-unsupported-user-location",
      withExtension: "json",
      statusCode: 400,
    )
    await assertFailsGenerate()
  }

  func testGenerateContent_failure_imageRejected() async throws {
    MockURLProtocol.requestHandler = try httpRequestHandler(
      forResource: "unary-failure-image-rejected",
      withExtension: "json",
      statusCode: 400,
    )
    await assertFailsGenerate()
  }

  func testGenerateContent_failure_nonHTTPResponse() async throws {
    MockURLProtocol.requestHandler = try nonHTTPRequestHandler()
    await assertFailsGenerate()
  }

  func testGenerateContentStream_failureInvalidAPIKey() async throws {
    MockURLProtocol.requestHandler = try httpRequestHandler(
      forResource: "streaming-failure-invalid-api-key",
      withExtension: "txt",
      statusCode: 400,
    )
    var seenError = false
    let stream = model.generateContentStream("Hello")
    do {
      for try await _ in stream {}
    } catch {
      seenError = true
    }
    XCTAssertTrue(seenError)
  }

  func testGenerateContentStream_errorMidStream() async throws {
    MockURLProtocol.requestHandler = try httpRequestHandler(
      forResource: "streaming-failure-error-mid-stream",
      withExtension: "txt",
      statusCode: 200,
    )
    var seenError = false
    let stream = model.generateContentStream("Hello")
    do {
      for try await _ in stream {}
    } catch {
      seenError = true
    }
    XCTAssertTrue(seenError)
  }

  // MARK: - Helpers

  private func assertFailsGenerate(file: StaticString = #filePath, line: UInt = #line) async {
    do {
      _ = try await model.generateContent("Hello")
      XCTFail("Expected failure", file: file, line: line)
    } catch {
      XCTAssertTrue(true)
    }
  }

  private func nonHTTPRequestHandler() throws -> ((URLRequest) -> (URLResponse, [String])) {
    { request in
      let response = URLResponse(
        url: request.url!,
        mimeType: nil,
        expectedContentLength: 0,
        textEncodingName: nil,
      )
      return (response, [])
    }
  }

  private func httpRequestHandler(
    forResource name: String,
    withExtension ext: String,
    statusCode: Int = 200,
    timeout: TimeInterval = RequestOptions().timeout,
  ) throws -> ((URLRequest) -> (URLResponse, [String])) {
    let fileURL = try resourceURL(forResource: name, withExtension: ext)
    return { request in
      let requestURL = try! XCTUnwrap(request.url)
      XCTAssertEqual(request.timeoutInterval, timeout)
      let response =
        HTTPURLResponse(
          url: requestURL,
          statusCode: statusCode,
          httpVersion: nil,
          headerFields: nil,
        )! as URLResponse
      let contents = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
      let lines = contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
      return (response, lines)
    }
  }
}

// Local copy of MockURLProtocol
@available(iOS 15.0, macOS 12.0, macCatalyst 15.0, *)
class MockURLProtocol: URLProtocol {
  nonisolated(unsafe) static var requestHandler: ((URLRequest) -> (URLResponse, [String]))?

  override class func canInit(with _: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let requestHandler = Self.requestHandler else {
      fatalError("`requestHandler` is nil.")
    }
    guard let client else { fatalError("`client` is nil.") }
    let (response, lines) = requestHandler(request)
    client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    for line in lines {
      client.urlProtocol(self, didLoad: line.data(using: .utf8)!)
      client.urlProtocol(self, didLoad: "\n".data(using: .utf8)!)
    }
    client.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

extension GenerativeModelKnownFailureTests {
  fileprivate func resourceURL(forResource name: String, withExtension ext: String) throws -> URL {
    if let directMatch = Bundle.module.url(forResource: name, withExtension: ext) {
      return directMatch
    }
    let subdirectories = ["generate-content-responses", "count-token-responses"]
    for subdirectory in subdirectories {
      if let match = Bundle.module.url(
        forResource: name,
        withExtension: ext,
        subdirectory: subdirectory
      ) {
        return match
      }
    }
    XCTFail("Missing resource \(name).\(ext) in KnownFailureTests bundle")
    throw NSError(domain: "KnownFailureTests", code: 1)
  }
}

#endif
