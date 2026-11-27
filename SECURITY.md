# Security

RevanieKit decides whether your customers get what they paid for, so we take reports seriously.

**Please don't open a public issue for a vulnerability.** Email **support@revanie.app** with steps to reproduce. We
answer within two working days and credit reporters (if they wish) once a fix ships.

## What RevanieKit guarantees
- Only Apple-signed transactions (StoreKit's JWS) are sent; Revanie verifies the chain to Apple Root CA G3 and the bundle id.
- Every response is signed by Revanie (Ed25519, over a per-request nonce and the exact body) and checked on device;
  an unsigned, altered or replayed answer is ignored.
- The SDK key (`rv_pk_…`) is public by design: it identifies the app, it cannot read or change customer data on its own.
