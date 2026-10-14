# Changelog

## 0.1.0

- Exact single-asset accounts with separate accounting classification.
- Immutable positive debit/credit postings and drafts.
- Explicit opaque Draft → Validated → Posted lifecycle, plus atomic `post`.
- Per-asset and precision-aware balance validation; no cross-asset netting.
- Debit-minus-credit account balances using arbitrary-size integer atoms.
- Entry-ID and source-scoped external-event idempotency with conflict rejection.
- Linked compensating reversals and immutable audit history.
- March 0.5.0 toolchain pin, property tests, and compile-time lifecycle checks.

This release is an in-memory library. Storage, concurrency coordination,
serialization, and chain-specific workflows are outside its scope.
