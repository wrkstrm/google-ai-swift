# Generative AI (Swift) — Slimmed Model SDK

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fwrkstrm%2Fgoogle-ai-swift%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/wrkstrm/google-ai-swift)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fwrkstrm%2Fgoogle-ai-swift%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/wrkstrm/google-ai-swift)

This repository is a slimmed-down fork focused on model access only. UI layers have been removed and now live under our cross-app Gen UI package. This package exposes the Google Generative AI client (models) without UI, and bundled chat demos have been decommissioned to keep the surface area headless.

> [!CAUTION] **The Google AI SDK for Swift is recommended for prototyping only.** If you plan to
> enable billing, we strongly recommend that you use a backend SDK to access the Google AI Gemini
> API. You risk potentially exposing your API key to malicious actors if you embed your API key
> directly in your Swift app or fetch it remotely at runtime.

## Get started with the Gemini API

1. Go to [Google AI Studio](https://aistudio.google.com/).
2. Login with your Google account.
3. [Create an API key](https://aistudio.google.com/app/apikey). Note that in Europe the free tier is
   not available.
4. Check out this repository. \
   `git clone https://github.com/wrkstrm/google-ai-swift`
5. Open and build the sample app in the `Examples` folder of this repo.
6. Run the app once to ensure the build script generates an empty `GenerativeAI-Info.plist` file
7. Paste your API key into the `API_KEY` property in the `GenerativeAI-Info.plist` file.
8. Run the app
9. For detailed instructions, try the
   [Swift SDK tutorial](https://ai.google.dev/tutorials/swift_quickstart) on
   [ai.google.dev](https://ai.google.dev).

## Usage

```swift
import GoogleGenerativeAI

let model = GenerativeModel(name: "gemini-1.5-flash-latest", apiKey: "<API_KEY>")
let response = try await model.generateContent("Hello!")
print(response.text ?? "")
```

## Logging

To enable additional logging in the Xcode console, including a cURL command and raw stream response
for each model request, add `-GoogleGenerativeAIDebugLogEnabled` as `Arguments Passed On Launch` in
the Xcode scheme.

## Documentation

See the [Gemini API Cookbook](https://github.com/google-gemini/gemini-api-cookbook/) or
[ai.google.dev](https://ai.google.dev) for complete documentation.

## Testing

Tests use the Swift Testing library (`import Testing`) instead of XCTest. Run with `swift test` from
the package root.

## Scope

- Models and APIs only (GoogleGenerativeAI). No UI or provider-neutral layers here.

## Contributing

See [Contributing](https://github.com/wrkstrm/google-ai-swift/blob/main/docs/CONTRIBUTING.md) for
more information on contributing to the Google AI SDK for Swift.

## License

The contents of this repository are licensed under the
[Apache License, version 2.0](http://www.apache.org/licenses/LICENSE-2.0).
