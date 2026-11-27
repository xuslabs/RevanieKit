// swift-tools-version: 6.0
// RevanieKit — purchases, entitlements and offerings for Apple apps, backed by Revanie (api.revanie.app).
// StoreKit 2 only, no UI, no dependencies.
import PackageDescription

let package = Package(
    name: "RevanieKit",
    platforms: [.iOS(.v15), .macOS(.v12), .tvOS(.v15), .watchOS(.v8), .visionOS(.v1)],
    products: [.library(name: "RevanieKit", targets: ["RevanieKit"])],
    targets: [
        .target(name: "RevanieKit", resources: [.copy("PrivacyInfo.xcprivacy")]),
        .testTarget(name: "RevanieKitTests", dependencies: ["RevanieKit"]),
    ]
)
