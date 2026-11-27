<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset=".github/assets/banner-dark.png">
    <img alt="RevanieKit — purchases, entitlements and offerings for Apple apps" src=".github/assets/banner-light.png" width="840">
  </picture>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white" alt="Swift 6">
  <img src="https://img.shields.io/badge/platforms-iOS%2015%20%7C%20macOS%2012%20%7C%20tvOS%2015%20%7C%20watchOS%208%20%7C%20visionOS%201-15181E" alt="Platforms">
  <img src="https://img.shields.io/badge/SPM-compatible-E5781F" alt="Swift Package Manager">
  <img src="https://img.shields.io/badge/StoreKit-2-15181E" alt="StoreKit 2">
  <img src="https://img.shields.io/badge/license-MIT-6B6D74" alt="MIT">
</p>

**RevanieKit** is the client for [Revanie](https://revanie.app): in-app purchases, entitlements and remotely configured
offerings for Apple apps, with every customer visible in the Revanie app on your phone.

- **StoreKit 2 only, no dependencies, no UI.** A small, readable Swift 6 package.
- **Honest by construction.** Purchases go up as Apple-signed JWS; every answer comes back signed by Revanie and is checked
  on device. Nothing unsigned unlocks anything.
- **Never loses a sale.** A transaction is finished only after Revanie has it; offline, the last signed answer stands.
- **Starts without it.** Revanie works SDK-free from App Store Server Notifications; adding RevanieKit later keeps the
  same history — no migration.
- **No share of your revenue.** SDK mode is part of Revanie Studio.

## Requirements

| | Minimum |
|---|---|
| iOS / iPadOS | 15 |
| macOS | 12 |
| tvOS | 15 |
| watchOS | 8 |
| visionOS | 1 |
| Xcode | 16 (Swift 6) |

## Installation

**Xcode:** File › Add Package Dependencies… › `https://github.com/xuslabs/RevanieKit`

**Package.swift**
```swift
.package(url: "https://github.com/xuslabs/RevanieKit", from: "0.1.0")
```

## Setting up in Revanie

1. In the Revanie app, add your app and paste its notification URL into App Store Connect (the SDK-free setup).
2. Open the app's **SDK · full control** screen, create the SDK key (`rv_pk_…`) and define:
   - **Entitlements** — what unlocks (`pro`) and which products unlock it;
   - **Offerings** — what the paywall shows, as packages (`annual`, `monthly`); one is current.

## Quick start

```swift
import RevanieKit

@main
struct MyApp: App {
    init() { Revanie.configure(apiKey: "rv_pk_…") }          // as early as possible
    var body: some Scene { WindowGroup { ContentView() } }
}
```

```swift
// The paywall: what is current in Revanie, with StoreKit products loaded
let offerings = try await Revanie.shared.offerings()
let packages = offerings.current?.packages ?? []

// Buying
switch try await Revanie.shared.purchase(packages[0]) {
case .purchased(let info, _): unlocked = info.isActive("pro")
case .cancelled: break
case .pending: break   // Ask to Buy: the answer arrives through customerInfoUpdates
}

// Anywhere
let pro = try await Revanie.shared.customerInfo().isActive("pro")

// Live
Task {
    for await info in await Revanie.shared.customerInfoUpdates { unlocked = info.isActive("pro") }
}

// A "Restore purchases" button
_ = try await Revanie.shared.restorePurchases()
```

### Your own accounts

```swift
_ = try await Revanie.shared.logIn("user-123")   // what was bought anonymously on this device goes with the user
_ = try await Revanie.shared.logOut()            // back to a fresh anonymous user
try await Revanie.shared.setAttributes(["plan_source": "onboarding"])
```

### Next to other purchase code

```swift
Revanie.configure(apiKey: "rv_pk_…", purchasesCompletedBy: .myApp)
```
Revanie records every transaction and never finishes one, so your code (or another SDK) stays in charge while you compare.

## How it works

| Step | What happens |
|---|---|
| Launch | Unfinished transactions are sent first, then RevanieKit listens to `Transaction.updates` (renewals, Ask to Buy, refunds, offer codes). |
| Purchase | The customer's `appAccountToken` goes on the purchase, so Apple ties every later renewal and refund to them — even when the app is closed. |
| Verify | Revanie checks Apple's signature chain and your bundle id, stores the transaction, links it to the customer. |
| Answer | `CustomerInfo` comes back signed (Ed25519 over a fresh nonce and the body). RevanieKit checks it before trusting it. |
| Finish | Only then is the StoreKit transaction finished. If the network drops, StoreKit gives it back next launch. |

## Privacy

RevanieKit ships a privacy manifest (`PrivacyInfo.xcprivacy`): no tracking, no tracking domains. It sends Apple's signed
transactions, your app user id and any attributes you set — nothing else. No IDFA, no device fingerprinting.
Declare *Purchase History* and *User ID* (App Functionality, linked, not tracking) in your App Store privacy label.

## Documentation

DocC reference: build it in Xcode (Product › Build Documentation) or read it on the Swift Package Index.

## Security

Please report vulnerabilities privately — see [SECURITY.md](SECURITY.md).

## License

MIT © XUSLABS LTD. See [LICENSE](LICENSE).
