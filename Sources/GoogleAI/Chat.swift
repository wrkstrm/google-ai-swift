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

/// An object that represents a back-and-forth chat with a model, capturing the history and saving
/// the context in memory between each message sent.
@available(iOS 15.0, macOS 11.0, macCatalyst 15.0, *)
@MainActor
public class Chat {
  private let model: GenerativeModel

  /// Initializes a new chat representing a 1:1 conversation between model and user.
  init(model: GenerativeModel, history: [ModelContent]) {
    self.model = model
    self.history = history
  }

  /// The previous content from the chat that has been successfully sent and received from the
  /// model. This will be provided to the model for each message sent as context for the discussion.
  public var history: [ModelContent]

  /// Sends a message using the existing history of this chat as context. If successful, the message
  /// and response will be added to the history. If unsuccessful, history will remain unchanged.
  /// - Parameter parts: The new content to send as a single chat message.
  /// - Returns: The model's response if no error occurred.
  /// - Throws: A ``GenerateContentError`` if an error occurred.
  @MainActor public func sendMessage(_ parts: any ThrowingPartsRepresentable...) async throws
    -> GenerateContentResponse
  {
    try await sendMessage([ModelContent(parts: parts)])
  }

  /// Sends a message using the existing history of this chat as context. If successful, the message
  /// and response will be added to the history. If unsuccessful, history will remain unchanged.
  /// - Parameter content: The new content to send as a single chat message.
  /// - Returns: The model's response if no error occurred.
  /// - Throws: A ``GenerateContentError`` if an error occurred.
  @MainActor public func sendMessage(_ content: @autoclosure () throws -> [ModelContent])
    async throws
    -> GenerateContentResponse
  {
    let newContent: [ModelContent]
    let request: [ModelContent]
    do {
      newContent = try content().map(populateContentRole(_:))
      let currentHistory = history
      request = currentHistory + newContent
    } catch let underlying {
      guard let contentError = underlying as? ImageConversionError else {
        throw GenerateContentError.internalError(underlying: underlying)
      }
      throw GenerateContentError.promptImageContentError(underlying: contentError)
    }
    Log.genAI.trace("sendMessage request: \(newContent)")
    // Create local copies to avoid crossing actor boundaries with non-Sendable self.model
    let localModel = model
    let localRequest = request

    let result = try await localModel.generateContent(localRequest)
    Log.genAI.trace(
      "sendMessage response: \(String(describing: result.candidates.first?.content))",
    )

    guard let reply = result.candidates.first?.content else {
      let error = NSError(
        domain: "com.google.generative-ai",
        code: -1,
        userInfo: [
          NSLocalizedDescriptionKey: "No candidates with content available."
        ],
      )
      throw GenerateContentError.internalError(underlying: error)
    }

    // Make sure we inject the role into the content received.
    let toAdd = ModelContent(role: "model", parts: reply.parts)

    // Append the request and successful result to history, then return the value.
    await MainActor.run {
      self.history.append(contentsOf: newContent)
      self.history.append(toAdd)
    }
    return result
  }

  /// Sends a message using the existing history of this chat as context. If successful, the message
  /// and response will be added to the history. If unsuccessful, history will remain unchanged.
  /// - Parameter parts: The new content to send as a single chat message.
  /// - Returns: A stream containing the model's response or an error if an error occurred.
  #if canImport(Darwin)
  @available(macOS 12.0, *)
  @MainActor
  public func sendMessageStream(_ parts: any ThrowingPartsRepresentable...)
    -> AsyncThrowingStream<GenerateContentResponse, Error>
  {
    try! sendMessageStream([ModelContent(parts: parts)])
  }

  /// Sends a message using the existing history of this chat as context. If successful, the message
  /// and response will be added to the history. If unsuccessful, history will remain unchanged.
  /// - Parameter content: The new content to send as a single chat message.
  /// - Returns: A stream containing the model's response or an error if an error occurred.
  @available(macOS 12.0, *)
  @MainActor
  public func sendMessageStream(_ content: @autoclosure () throws -> [ModelContent])
    -> AsyncThrowingStream<GenerateContentResponse, Error>
  {
    let newContent: [ModelContent]
    let localRequest: [ModelContent]
    do {
      let resolvedContent = try content()
      newContent = resolvedContent.map(populateContentRole(_:))
      localRequest = history + newContent
    } catch let underlying {
      return AsyncThrowingStream { continuation in
        let error: Error =
          if let contentError = underlying as? ImageConversionError {
            GenerateContentError.promptImageContentError(underlying: contentError)
          } else {
            GenerateContentError.internalError(underlying: underlying)
          }
        continuation.finish(throwing: error)
      }
    }
    Log.genAI.trace("sendMessageStream request: \(newContent)")
    let localModel = model

    return AsyncThrowingStream { continuation in
      Task {
        var localAggregatedContent: [ModelContent] = []
        let stream = localModel.generateContentStream(localRequest)
        do {
          for try await chunk in stream {
            if let chunkContent = chunk.candidates.first?.content {
              localAggregatedContent.append(chunkContent)
              Log.genAI.trace("sendMessageStream chunk: \(chunkContent)")
            }
            // Yield on MainActor to avoid data race with non-Sendable type
            let safeChunk = chunk
            _ = await MainActor.run {
              continuation.yield(safeChunk)
            }
          }
        } catch {
          Log.genAI.trace("sendMessageStream error: \(error.localizedDescription)")
          continuation.finish(throwing: error)
          return
        }
        // Only now, after streaming completes, update the shared history.
        await MainActor.run {
          history.append(contentsOf: newContent)
          let aggregated = aggregatedChunks(localAggregatedContent)
          history.append(aggregated)
        }
        continuation.finish()
      }
    }
  }
  #endif

  private func aggregatedChunks(_ chunks: [ModelContent]) -> ModelContent {
    var parts: [ModelContent.Part] = []
    var combinedText = ""
    for aggregate in chunks {
      // Loop through all the parts, aggregating the text and adding the images.
      for part in aggregate.parts {
        switch part {
        case .text(let str):
          combinedText += str

        case .data, .fileData, .functionCall, .functionResponse, .executableCode,
          .codeExecutionResult:
          // Don't combine it, just add to the content. If there's any text pending, add that as
          // a part.
          if !combinedText.isEmpty {
            parts.append(.text(combinedText))
            combinedText = ""
          }

          parts.append(part)
        }
      }
    }

    if !combinedText.isEmpty {
      parts.append(.text(combinedText))
    }

    return ModelContent(role: "model", parts: parts)
  }

  /// Populates the `role` field with `user` if it doesn't exist. Required in chat sessions.
  private func populateContentRole(_ content: ModelContent) -> ModelContent {
    if content.role != nil {
      content
    } else {
      ModelContent(role: "user", parts: content.parts)
    }
  }
}
