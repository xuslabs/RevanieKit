# Changelog

All notable changes to RevanieKit. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
project uses [Semantic Versioning](https://semver.org).

## [0.1.1] — 2026-11-28

### Changed
- `customerInfo()` also falls back to the last signed answer when Revanie is busy (429) or down (5xx), not only offline.

### Added
- `Examples/RevanieKitDemo`: a paywall on RevanieKit with a StoreKit configuration, and end-to-end tests (purchase
  unlocks, refund locks) against a local Revanie server.
- Testing in Xcode: StoreKit-configuration purchases are accepted by Revanie once the app's StoreKit certificate is added.

## [0.1.0] — 2026-11-28

### Added
- `Revanie.configure(apiKey:appUserID:purchasesCompletedBy:)`, `Revanie.shared`.
- `customerInfo(fetchPolicy:)`, `customerInfoUpdates`, `CustomerInfo.isActive(_:)`.
- `offerings()` with StoreKit products loaded; `Offering`, `Package`.
- `purchase(_:)`, `purchase(product:)` with the customer's `appAccountToken`; `PurchaseResult`.
- `restorePurchases()`, `syncPurchases()`.
- `logIn(_:)`, `logOut()`, `setAttributes(_:)`.
- Transaction listener (`unfinished`, then `updates`), finish-after-server, observer mode.
- Signed responses (Ed25519 over nonce and body), offline cache of the last signed answer.
- Privacy manifest.
