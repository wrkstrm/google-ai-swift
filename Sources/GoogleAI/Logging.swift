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

#if canImport(OSLog)
import OSLog
#endif

@available(iOS 15.0, macOS 11.0, macCatalyst 15.0, *)
enum Logging {
  /// Subsystem that should be used for all Loggers.
  static let subsystem = "com.google.generative-ai"

  /// Default category used for most loggers, unless specialized.
  static let defaultCategory = ""

  /// The argument required to enable additional logging.
  static let enableArgumentKey = "-GoogleGenerativeAIDebugLogEnabled"

  #if canImport(OSLog)
  /// The default logger that is visible for all users. Note: we shouldn't be using anything lower
  /// than `.notice`.
  static let `default` = Logger(subsystem: subsystem, category: defaultCategory)

  /// Verbose logger enabled via launch argument.
  static let verbose: Logger =
    if ProcessInfo.processInfo.arguments.contains(enableArgumentKey) {
      .init(subsystem: subsystem, category: defaultCategory)
    } else {
      // Return a valid logger that's using `OSLog.disabled` as the logger, hiding everything.
      .init(.disabled)
    }
  #else
  /// Fallback logger used when OSLog isn't available (e.g. Linux).
  struct DummyLogger {
    func debug(_ message: String) {}
    func info(_ message: String) {}
    func error(_ message: String) {}
  }

  static let `default` = DummyLogger()
  static let verbose = DummyLogger()
  #endif
}

extension Log {
  /// Logger for core GoogleGenerativeAI operations.
  static let genAI = Log(
    system: Logging.subsystem,
    category: "GenerativeAI",
    maxExposureLevel: .trace,
  )
}
