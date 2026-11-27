# ``RevanieKit``

Purchases, entitlements and offerings for Apple apps, backed by Revanie.

## Overview

Configure once at launch, then ask whether a customer has an entitlement, show the current offering and buy its
packages. RevanieKit sends StoreKit 2's signed transactions to Revanie and trusts only answers Revanie has signed.

```swift
Revanie.configure(apiKey: "rv_pk_…")
let pro = try await Revanie.shared.customerInfo().isActive("pro")
```

## Topics

### Essentials
- ``Revanie``
- ``CustomerInfo``
- ``EntitlementInfo``

### Paywalls
- ``Offerings``
- ``Offering``
- ``Package``
- ``PurchaseResult``

### Errors
- ``RevanieError``
