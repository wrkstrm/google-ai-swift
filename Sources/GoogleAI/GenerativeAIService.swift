// Copyright 2023 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation
import WrkstrmFoundation
import CommonLog
import WrkstrmNetworking

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension Log {
  /// A non default logger used for network responses.
  static let network: Log = .init(
    system: Logging.subsystem,
    category: "NetworkResponse",
    maxExposureLevel: .trace,
  )
}

@available(iOS 15.0, macOS 11.0, macCatalyst 15.0, *)
struct GenerativeAIService {
  var codableClient: HTTP.CodableClient

  var environment: any WrkstrmNetworking.HTTP.Environment
  private let sseExecutor: HTTP.SSEExecutor

  init(environment: AI.GoogleGenAI.Environment) {
    self.environment = environment
    let configuration: URLSessionConfiguration = .default
    configuration.httpAdditionalHeaders = environment.headers
    codableClient = HTTP.CodableClient(
      environment: environment,
      json: (.commonDateFormatting, .commonDateParsing),
    )
    sseExecutor = HTTP.SSEExecutor(environment: environment, session: codableClient.session)
  }

  init(environment: AI.GoogleGenAI.Environment, client: HTTP.CodableClient) {
    self.environment = environment
    codableClient = client
    sseExecutor = HTTP.SSEExecutor(environment: environment, session: client.session)
  }

  func loadRequest<T: HTTP.CodableURLRequest>(request: T) async throws
    -> T.ResponseType
  {
    let urlRequest = try await request.asURLRequest(
      with: environment,
      encoder: codableClient.jsonCoding.requestEncoder,
    )

    Log.network.trace(
      "Sending request: \(urlRequest.httpMethod ?? "") \(urlRequest.url?.absoluteString ?? "")",
    )
    if let body = urlRequest.httpBody,
      let bodyString = String(data: body, encoding: .utf8)
    {
      Log.network.trace("Request body: \(bodyString)")
    }
    #if DEBUG
    CURL.printCURLCommand(from: urlRequest, in: environment)
    #endif

    let (data, response): (Data, URLResponse)
    do {
      (data, response) = try await codableClient.session.data(for: urlRequest)
    } catch {
      Log.network.error("Request failed: \(error.localizedDescription)")
      throw error
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      throw NSError(
        domain: "com.google.generative-ai",
        code: -1,
        userInfo: [NSLocalizedDescriptionKey: "Response was not an HTTP response."],
      )
    }

    guard httpResponse.statusCode.isHTTPOKStatusRange else {
      Log.network
        .error(
          "[GoogleGenerativeAI] The server responded with an error: \(httpResponse)",
        )
      throw parseError(responseData: data)
    }

    return try parseResponse(T.ResponseType.self, from: data)
  }

  #if canImport(Darwin)
  @available(macOS 12.0, *)
  func loadRequestStream<T: HTTP.CodableURLRequest>(request: T)
    -> AsyncThrowingStream<
      T.ResponseType, Error
    > where T.ResponseType: Sendable
  {
    AsyncThrowingStream { continuation in
      Task {
        let urlRequest: URLRequest
        do {
          urlRequest = try await request.asURLRequest(
            with: environment,
            encoder: codableClient.jsonCoding.requestEncoder,
          )
        } catch {
          continuation.finish(throwing: error)
          return
        }

        Log.network.trace(
          "Streaming request: \(urlRequest.httpMethod ?? "") \(urlRequest.url?.absoluteString ?? "")",
        )
        if let body = urlRequest.httpBody,
          let bodyString = String(data: body, encoding: .utf8)
        {
          Log.network.trace("Request body: \(bodyString)")
        }
        #if DEBUG
        CURL.printCURLCommand(from: urlRequest, in: environment)
        #endif

        // Use shared decoder preset for stream decoding
        let decoder: JSONDecoder = .commonDateParsing
        let stream: AsyncThrowingStream<T.ResponseType, Error> =
          sseExecutor.sseJSONStream(request: urlRequest, decoder: decoder)

        do {
          for try await item in stream {
            continuation.yield(item)
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
    }
  }
  #endif

  // MARK: - Private Helpers

  private func httpResponse(urlResponse: URLResponse) throws -> HTTPURLResponse {
    // Verify the status code is 200
    guard let response = urlResponse as? HTTPURLResponse else {
      Logging.default
        .error(
          "[GoogleGenerativeAI] Response wasn't an HTTP response, internal error \(urlResponse)",
        )
      throw NSError(
        domain: "com.google.generative-ai",
        code: -1,
        userInfo: [
          NSLocalizedDescriptionKey: "Response was not an HTTP response."
        ],
      )
    }

    return response
  }

  private func jsonData(jsonText: String) throws -> Data {
    guard let data = jsonText.data(using: .utf8) else {
      let error = NSError(
        domain: "com.google.generative-ai",
        code: -1,
        userInfo: [
          NSLocalizedDescriptionKey: "Could not parse response as UTF8."
        ],
      )
      throw error
    }

    return data
  }

  private func parseError(responseBody: String) -> Error {
    do {
      let data = try jsonData(jsonText: responseBody)
      return parseError(responseData: data)
    } catch {
      return error
    }
  }

  private func parseError(responseData: Data) -> Error {
    do {
      return try JSONDecoder.commonDateParsing.decode(RPCError.self, from: responseData)
    } catch {
      // TODO: Return an error about an unrecognized error payload with the response body
      return error
    }
  }

  private func parseResponse<T: Decodable>(_ type: T.Type, from data: Data)
    throws -> T
  {
    do {
      return try JSONDecoder.commonDateParsing.decode(type, from: data)
    } catch {
      if let json = String(data: data, encoding: .utf8) {
        Log.network.error("[GoogleGenerativeAI] JSON response: \(json)")
      }
      Log.shared.error(
        "[GoogleGenerativeAI] Error decoding server JSON: \(error)",
      )
      throw error
    }
  }
}
