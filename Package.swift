// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "codex-dictate-companion",
  platforms: [
    .macOS("26.0")
  ],
  products: [
    .executable(name: "codex-dictate-companion", targets: ["CodexDictateCompanion"])
  ],
  targets: [
    .executableTarget(
      name: "CodexDictateCompanion"
    ),
    .testTarget(
      name: "CodexDictateCompanionTests",
      dependencies: ["CodexDictateCompanion"]
    )
  ]
)
