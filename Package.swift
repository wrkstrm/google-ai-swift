// swift-tools-version:6.1
import Foundation
import PackageDescription

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

ConfigurationService.local.dependencies = [
  .package(name: "WrkstrmLog", path: "../WrkstrmLog"),
  .package(name: "WrkstrmFoundation", path: "../WrkstrmFoundation"),
]

ConfigurationService.remote.dependencies = [
  .package(url: "https://github.com/wrkstrm/WrkstrmLog.git", from: "2.0.0"),
  .package(url: "https://github.com/wrkstrm/WrkstrmFoundation.git", from: "2.0.0"),
]

let package = Package(
  name: "google-ai-swift",
  platforms: [
    .iOS(.v17),
    .macOS(.v15),
    .macCatalyst(.v17),
  ],
  products: [
    .library(
      name: "GoogleGenerativeAI",
      targets: ["GoogleGenerativeAI"],
    )
  ],
  dependencies: ConfigurationService.inject.dependencies,
  targets: [
    .target(
      name: "GoogleGenerativeAI",
      dependencies: [
        .product(name: "WrkstrmFoundation", package: "WrkstrmFoundation"),
        .product(name: "WrkstrmNetworking", package: "WrkstrmFoundation"),
        .product(name: "WrkstrmLog", package: "WrkstrmLog"),
      ],
      path: "Sources/GoogleAI",
    ),
    .testTarget(
      name: "GoogleGenerativeAITests",
      dependencies: [
        "GoogleGenerativeAI",
        .product(name: "WrkstrmFoundation", package: "WrkstrmFoundation"),
        .product(name: "WrkstrmNetworking", package: "WrkstrmFoundation"),
        .product(name: "WrkstrmLog", package: "WrkstrmLog"),
      ],
      path: "Tests",
      resources: [
        .process("GoogleAITests/Resources/CountTokenResponses"),
        .process("GoogleAITests/Resources/GenerateContentResponses"),
      ],
      swiftSettings: [.define("DISABLE_KNOWN_FAILURE_TESTS")],
    ),
    .testTarget(
      name: "GoogleGenerativeAIKnownFailureTests",
      dependencies: [
        "GoogleGenerativeAI",
        .product(name: "WrkstrmFoundation", package: "WrkstrmFoundation"),
        .product(name: "WrkstrmNetworking", package: "WrkstrmFoundation"),
        .product(name: "WrkstrmLog", package: "WrkstrmLog"),
      ],
      path: "KnownFailureTests",
      resources: [
        .process("../Tests/GoogleAITests/Resources/CountTokenResponses"),
        .process("../Tests/GoogleAITests/Resources/GenerateContentResponses"),
      ],
    ),
    .testTarget(
      name: "LinuxDummyTests",
      dependencies: ["GoogleGenerativeAI"],
      path: "LinuxDummyTests",
    ),
  ],
)

// MARK: - Configuration Service

@MainActor
public struct ConfigurationService {
  public static let version = "1.0.0"

  public var swiftSettings: [SwiftSetting] = []
  var dependencies: [PackageDescription.Package.Dependency] = []

  public static let inject: ConfigurationService = ProcessInfo.useLocalDeps ? .local : .remote

  static var local: ConfigurationService = .init(swiftSettings: [.local])
  static var remote: ConfigurationService = .init()
}

// MARK: - PackageDescription extensions

extension SwiftSetting {
  public static let local: SwiftSetting = .unsafeFlags([
    "-Xfrontend",
    "-warn-long-expression-type-checking=10",
  ])
}

// MARK: - Foundation extensions

extension ProcessInfo {
  public static var useLocalDeps: Bool {
    ProcessInfo.processInfo.environment["SPM_USE_LOCAL_DEPS"] == "true"
  }
}

// CONFIG_SERVICE_END_V1
