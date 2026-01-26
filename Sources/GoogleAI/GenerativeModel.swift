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
import CommonLog
import WrkstrmNetworking

/// A type that represents a remote multimodal model (like Gemini), with the ability to generate
/// content based on various input types.
@available(iOS 15.0, macOS 11.0, macCatalyst 15.0, *)
public final class GenerativeModel: @unchecked Sendable {
  // The prefix for a model resource in the Gemini API.
  private static let modelResourcePrefix = "models/"

  /// The resource name of the model in the backend; has the format "models/model-name".
  let modelResourceName: String

  /// The backing service responsible for sending and receiving model requests to the backend.
  var generativeAIService: GenerativeAIService

  /// Configuration parameters used for the MultiModalModel.
  let generationConfig: GenerationConfig?

  /// The safety settings to be used for prompts.
  let safetySettings: [SafetySetting]?

  /// A list of tools the model may use to generate the next response.
  let tools: [Tool]?

  /// Tool configuration for any `Tool` specified in the request.
  let toolConfig: ToolConfig?

  /// Instructions that direct the model to behave a certain way.
  /// NOTE: This is not optional in the latest releases.
  /// TODO: Remove optional system instructions.
  var systemInstruction: ModelContent = try! ModelContent(role: "system", "Have a nice chat.")

  /// Configuration parameters for sending requests to the backend.
  let requestOptions: HTTP.Request.Options

  /// Initializes a new remote model with the given parameters.
  ///
  /// - Parameters:
  ///   - name: The name of the model to use, e.g., `"gemini-1.5-pro-latest"`; see
  ///     [Gemini models](https://ai.google.dev/models/gemini) for a list of supported model names.
  ///   - apiKey: The API key for your project.
  ///   - generationConfig: The content generation parameters your model should use.
  ///   - safetySettings: A value describing what types of harmful content your model should allow.
  ///   - tools: A list of ``Tool`` objects  that the model may use to generate the next response.
  ///   - systemInstruction: Instructions that direct the model to behave a certain way; currently
  ///     only text content is supported, e.g., "You are a cat. Your name is Neko."
  ///   - toolConfig: Tool configuration for any `Tool` specified in the request.
  ///   - requestOptions Configuration parameters for sending requests to the backend.
  public convenience init(
    name: String,
    apiKey: String,
    generationConfig: GenerationConfig? = nil,
    safetySettings: [SafetySetting]? = nil,
    tools: [Tool]? = nil,
    toolConfig: ToolConfig? = nil,
    systemInstruction: String...,
    requestOptions: HTTP.Request.Options = HTTP.Request.Options(),
  ) {
    self.init(
      name: name,
      apiKey: apiKey,
      generationConfig: generationConfig,
      safetySettings: safetySettings,
      tools: tools,
      toolConfig: toolConfig,
      systemInstruction: ModelContent(
        role: "system",
        parts: systemInstruction.map { ModelContent.Part.text($0) },
      ),
      requestOptions: requestOptions,
    )
  }

  /// The designated initializer for this class.
  /// Initializes a new remote model with the given parameters.
  ///
  /// - Parameters:
  ///   - name: The name of the model to use, for example `"gemini-1.5-pro-latest"`; see
  ///     [Gemini models](https://ai.google.dev/models/gemini) for a list of supported model names.
  ///   - apiKey: The API key for your project.
  ///   - generationConfig: The content generation parameters your model should use.
  ///   - safetySettings: A value describing what types of harmful content your model should allow.
  ///   - tools: A list of ``Tool`` objects  that the model may use to generate the next response.
  ///   - systemInstruction: Instructions that direct the model to behave a certain way; currently
  ///     only text content is supported, for example
  ///     `ModelContent(role: "system", parts: "You are a cat. Your name is Neko.")`.
  ///   - toolConfig: Tool configuration for any `Tool` specified in the request.
  ///   - requestOptions Configuration parameters for sending requests to the backend.
  public init(
    name: String,
    apiKey: String,
    generationConfig: GenerationConfig? = nil,
    safetySettings: [SafetySetting]? = nil,
    tools: [Tool]? = nil,
    toolConfig: ToolConfig? = nil,
    systemInstruction: ModelContent,
    requestOptions: HTTP.Request.Options = HTTP.Request.Options(),
  ) {
    modelResourceName = GenerativeModel.modelResourceName(name: name)
    generativeAIService = GenerativeAIService(environment: .betaEnv(with: apiKey))
    self.generationConfig = generationConfig
    self.safetySettings = safetySettings
    self.tools = tools
    self.toolConfig = toolConfig
    self.systemInstruction = systemInstruction
    self.requestOptions = requestOptions
    Log.verbose(
      """
      [GoogleGenerativeAI] Model \(name) initialized.
      To enable additional logging, add \
      `\(Logging.enableArgumentKey)` as a launch argument in Xcode.
      """,
    )
  }

  /// Convenience initializer allowing a custom URLSession backend (e.g., with URLProtocol).
  public convenience init(
    name: String,
    apiKey: String,
    generationConfig: GenerationConfig? = nil,
    safetySettings: [SafetySetting]? = nil,
    tools: [Tool]? = nil,
    toolConfig: ToolConfig? = nil,
    systemInstruction: String...,
    requestOptions: HTTP.Request.Options = HTTP.Request.Options(),
    urlSession: URLSession,
  ) {
    self.init(
      name: name,
      apiKey: apiKey,
      generationConfig: generationConfig,
      safetySettings: safetySettings,
      tools: tools,
      toolConfig: toolConfig,
      systemInstruction: ModelContent(
        role: "system",
        parts: systemInstruction.map { ModelContent.Part.text($0) },
      ),
      requestOptions: requestOptions,
    )
    // Replace service with one configured to use the provided session
    let env = AI.GoogleGenAI.Environment.betaEnv(with: apiKey)
    let transport = HTTP.URLSessionTransport(session: urlSession)
    let client = HTTP.CodableClient(
      environment: env,
      json: (.commonDateFormatting, .commonDateParsing),
      transport: transport,
    )
    generativeAIService = GenerativeAIService(environment: env, client: client)
  }

  /// Generates content from String and/or image inputs, given to the model as a prompt, that are
  /// representable as one or more ``ModelContent/Part``s.
  ///
  /// Since ``ModelContent/Part``s do not specify a role, this method is intended for generating
  /// content from
  /// [zero-shot](
  /// https://developers.google.com/machine-learning/glossary/generative#zero-shot-prompting
  /// )
  /// or "direct" prompts. For
  /// [few-shot](
  /// https://developers.google.com/machine-learning/glossary/generative#few-shot-prompting
  /// )
  /// prompts, see `generateContent(_ content: @autoclosure () throws -> [ModelContent])`.
  ///
  /// - Parameter content: The input(s) given to the model as a prompt (see
  /// ``ThrowingPartsRepresentable``
  /// for conforming types).
  /// - Returns: The content generated by the model.
  /// - Throws: A ``GenerateContentError`` if the request failed.
  public func generateContent(_ parts: any ThrowingPartsRepresentable...)
    async throws -> GenerateContentResponse
  {
    try await generateContent([ModelContent(parts: parts)])
  }

  /// Generates new content from input content given to the model as a prompt.
  ///
  /// - Parameter content: The input(s) given to the model as a prompt.
  /// - Returns: The generated content response from the model.
  /// - Throws: A ``GenerateContentError`` if the request failed.
  @MainActor
  public func generateContent(
    _ content: @autoclosure () throws -> [ModelContent],
  ) async throws
    -> GenerateContentResponse
  {
    let response: GenerateContentResponse
    do {
      let generateContentRequest = try GenerateContent.Request(
        isStreaming: false,
        options: requestOptions,
        body: .init(
          model: modelResourceName,
          contents: content(),
          generationConfig: generationConfig,
          safetySettings: safetySettings,
          tools: tools,
          toolConfig: toolConfig,
          systemInstruction: systemInstruction,
        ),
      )
      Log.genAI.trace("generateContent request: \(generateContentRequest)")
      response = try await generativeAIService.loadRequest(
        request: generateContentRequest,
      )
      Log.genAI.trace(
        "generateContent response: \(String(describing: response.candidates.first?.content))",
      )
    } catch {
      if let imageError = error as? ImageConversionError {
        throw GenerateContentError.promptImageContentError(
          underlying: imageError,
        )
      }
      throw GenerativeModel.generateContentError(from: error)
    }

    // Check the prompt feedback to see if the prompt was blocked.
    if response.promptFeedback?.blockReason != nil {
      throw GenerateContentError.promptBlocked(response: response)
    }

    // Check to see if an error should be thrown for stop reason.
    if let reason = response.candidates.first?.finishReason, reason != .stop {
      throw GenerateContentError.responseStoppedEarly(
        reason: reason,
        response: response,
      )
    }

    return response
  }

  /// Generates content from String and/or image inputs, given to the model as a prompt, that are
  /// representable as one or more ``ModelContent/Part``s.
  ///
  /// Since ``ModelContent/Part``s do not specify a role, this method is intended for generating
  /// content from
  /// [zero-shot](
  /// https://developers.google.com/machine-learning/glossary/generative#zero-shot-prompting
  /// )
  /// or "direct" prompts. For
  /// [few-shot](
  /// https://developers.google.com/machine-learning/glossary/generative#few-shot-prompting
  /// )
  /// prompts, see `generateContent(_ content: @autoclosure () throws -> [ModelContent])`.
  ///
  /// - Parameter content: The input(s) given to the model as a prompt (see
  /// ``ThrowingPartsRepresentable``
  /// for conforming types).
  /// - Returns: A stream wrapping content generated by the model or a ``GenerateContentError``
  ///     error if an error occurred.
  #if canImport(Darwin)
  @available(macOS 12.0, *)
  public func generateContentStream(_ parts: any ThrowingPartsRepresentable...)
    -> AsyncThrowingStream<GenerateContentResponse, Error>
  {
    try generateContentStream([ModelContent(parts: parts)])
  }

  /// Generates new content from input content given to the model as a prompt.
  ///
  /// - Parameter content: The input(s) given to the model as a prompt.
  /// - Returns: A stream wrapping content generated by the model or a ``GenerateContentError``
  ///     error if an error occurred.
  @available(macOS 12.0, *)
  public func generateContentStream(
    _ content: @autoclosure () throws -> [ModelContent],
  )
    -> AsyncThrowingStream<GenerateContentResponse, Error>
  {
    let evaluatedContent: [ModelContent]
    do {
      evaluatedContent = try content()
    } catch let underlying {
      return AsyncThrowingStream { continuation in
        let error: Error =
          if let contentError = underlying as? ImageConversionError {
            GenerateContentError.promptImageContentError(
              underlying: contentError,
            )
          } else {
            GenerateContentError.internalError(underlying: underlying)
          }
        continuation.finish(throwing: error)
      }
    }

    let generateContentRequest = GenerateContent.Request(
      isStreaming: true,
      options: requestOptions,
      body: .init(
        model: modelResourceName, contents: evaluatedContent, generationConfig: generationConfig,
        safetySettings: safetySettings, tools: tools, toolConfig: toolConfig,
        systemInstruction: systemInstruction,
      ),
    )

    var responseIterator = generativeAIService.loadRequestStream(
      request: generateContentRequest,
    )
    .makeAsyncIterator()
    Log.genAI.trace("generateContentStream request: \(generateContentRequest)")
    return AsyncThrowingStream {
      let response: GenerateContentResponse?
      do {
        response = try await responseIterator.next()
      } catch {
        Log.genAI.error("generateContentStream error: \(error.localizedDescription)")
        throw GenerativeModel.generateContentError(from: error)
      }

      // The responseIterator will return `nil` when it's done.
      guard let response else {
        // This is the end of the stream! Signal it by sending `nil`.
        return nil
      }

      Log.genAI.trace(
        "generateContentStream chunk: \(String(describing: response.candidates.first?.content))",
      )
      // Check the prompt feedback to see if the prompt was blocked.
      if response.promptFeedback?.blockReason != nil {
        throw GenerateContentError.promptBlocked(response: response)
      }

      // If the stream ended early unexpectedly, throw an error.
      guard let finishReason = response.candidates.first?.finishReason,
        finishReason != .stop
      else {
        // Response was valid content, pass it along and continue.
        return response
      }
      throw GenerateContentError.responseStoppedEarly(
        reason: finishReason,
        response: response,
      )
    }
  }
  #endif

  /// Creates a new chat conversation using this model with the provided history.
  @MainActor public func startChat(history: [ModelContent] = []) -> Chat {
    Chat(model: self, history: history)
  }

  /// Runs the model's tokenizer on String and/or image inputs that are representable as one or more
  /// ``ModelContent/Part``s.
  ///
  /// Since ``ModelContent/Part``s do not specify a role, this method is intended for tokenizing
  /// [zero-shot](
  /// https://developers.google.com/machine-learning/glossary/generative#zero-shot-prompting
  /// )
  /// or "direct" prompts. For
  /// [few-shot](
  /// https://developers.google.com/machine-learning/glossary/generative#few-shot-prompting
  /// )
  /// input, see `countTokens(_ content: @autoclosure () throws -> [ModelContent])`.
  ///
  /// - Parameter content: The input(s) given to the model as a prompt (see
  /// ``ThrowingPartsRepresentable``
  /// for conforming types).
  /// - Returns: The results of running the model's tokenizer on the input; contains
  /// ``CountTokensResponse/totalTokens``.
  /// - Throws: A ``CountTokensError`` if the tokenization request failed.
  public func countTokens(_ parts: any ThrowingPartsRepresentable...)
    async throws
    -> CountTokens.Response
  {
    try await countTokens([ModelContent(parts: parts)])
  }

  /// Runs the model's tokenizer on the input content and returns the token count.
  ///
  /// - Parameter content: The input given to the model as a prompt.
  /// - Returns: The results of running the model's tokenizer on the input; contains
  /// ``CountTokensResponse/totalTokens``.
  /// - Throws: A ``CountTokensError`` if the tokenization request failed or the input content was
  /// invalid.
  public func countTokens(_ content: @autoclosure () throws -> [ModelContent])
    async throws
    -> CountTokens.Response
  {
    do {
      let generateContentRequest: GenerateContent.Request = try .init(
        isStreaming: true,
        options: requestOptions,
        body: .init(
          model: modelResourceName,
          contents: content(),
          generationConfig: generationConfig,
          safetySettings: safetySettings,
          tools: tools,
          toolConfig: toolConfig,
          systemInstruction: systemInstruction,
        ),
      )
      let countTokensRequest = CountTokens.Request(
        options: requestOptions,
        model: modelResourceName,
        body: .init(generateContentRequest.body!),
      )
      return try await generativeAIService.loadRequest(
        request: countTokensRequest,
      )
    } catch {
      throw CountTokensError.internalError(underlying: error)
    }
  }

  /// Returns a model resource name of the form "models/model-name" based on `name`.
  private static func modelResourceName(name: String) -> String {
    if name.contains("/") {
      name
    } else {
      modelResourcePrefix + name
    }
  }

  /// Returns a `GenerateContentError` (for public consumption) from an internal error.
  ///
  /// If `error` is already a `GenerateContentError` the error is returned unchanged.
  private static func generateContentError(from error: Error)
    -> GenerateContentError
  {
    if let error = error as? GenerateContentError {
      return error
    } else if let error = error as? RPCError, error.isInvalidAPIKeyError() {
      return GenerateContentError.invalidAPIKey(message: error.message)
    } else if let error = error as? RPCError,
      error.isUnsupportedUserLocationError()
    {
      return GenerateContentError.unsupportedUserLocation
    } else if let clientError = error as? HTTP.ClientError {
      switch clientError {
      case .networkError(let underlying):
        // If the underlying error carries a JSON payload in its description, attempt to decode it
        if let data = underlying.localizedDescription.data(using: .utf8),
          let rpc = try? JSONDecoder().decode(RPCError.self, from: data)
        {
          if rpc.isInvalidAPIKeyError() {
            return .invalidAPIKey(message: rpc.message)
          }
          if rpc.isUnsupportedUserLocationError() {
            return .unsupportedUserLocation
          }
        }
        return .internalError(underlying: underlying)

      default:
        return .internalError(underlying: clientError)
      }
    }
    return GenerateContentError.internalError(underlying: error)
  }
}

/// An error thrown in `GenerativeModel.countTokens(_:)`.
@available(iOS 15.0, macOS 11.0, macCatalyst 15.0, *)
public enum CountTokensError: Error {
  case internalError(underlying: Error)
}
