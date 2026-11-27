# Changelog

All notable changes to RevanieKit. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
project uses [Semantic Versioning](https://semver.org).

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
