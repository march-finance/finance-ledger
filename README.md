# finance-ledger

[![Tests](https://github.com/march-finance/finance-ledger/actions/workflows/ci.yml/badge.svg)](https://github.com/march-finance/finance-ledger/actions/workflows/ci.yml)

Licensed under the [MIT License](LICENSE).

## GitHub checkout and CI

finance-core is pinned to registry version 0.1.0; no sibling checkout is needed:

```sh
git clone https://github.com/march-finance/finance-ledger.git
cd finance-ledger
forge deps
forge test --seed=42
```

GitHub Actions runs on pushes, pull requests and manual dispatches. It installs
the pinned March 0.5.0 release, checks/builds this package, and runs debug/release
tests and properties. finance-core is installed from ForgePM using `forge.lock`.
Compile-time contract checks run with Z3.

Exact, immutable double-entry accounting for March, depending on the published
`finance-core` 0.1.0 package.

March 0.5.0 is pinned in `.march-version`. Install it with
`forge toolchain install v0.5.0`; confirm resolution with `forge toolchain which`.

| Module | Responsibility |
| --- | --- |
| LedgerError | Domain errors |
| LedgerAccount | Opaque accounts, classification, declared asset |
| LedgerEntry | Positive postings, debit/credit direction, opaque drafts |
| LedgerValidation | Accounting invariants and opaque validated entries |
| LedgerJournal | Validation, atomic posting, balances, replay, reversals |

## Posting operations

Construct accounts with `LedgerAccount.make(id, kind, asset)`, then create a
journal with `LedgerJournal.new(accounts)`. Account IDs are unique and cannot
contain ASCII whitespace. Each account holds exactly one asset and precision.

Build a draft using `LedgerEntry.draft(id, metadata)` and `LedgerEntry.add`.
Create each posting using `LedgerEntry.posting(accountId, Debit|Credit, quantity)`.
Amounts must be strictly positive; direction conveys sign. `post(journal, draft)`
returns `Result((newJournal, postedEntry), LedgerError.Error)`.

The explicit lifecycle is also available:

```march
let? validated = LedgerJournal.validate(journal, draft)
let? (next_journal, posted) = LedgerJournal.post_validated(journal, validated)
```

`validate` checks accounting invariants without appending an entry or reserving
an ID. Its result is an opaque `LedgerValidation.Validated` value. You can inspect
its immutable draft with `LedgerValidation.draft`. Editing that draft does not
change the validated value. `post_validated` checks the destination chart and
current replay keys again: validation is neither an authorization token nor a
promise that a later post cannot conflict. `post` remains the atomic convenience
operation for callers that do not need a separate validation step. Reversals use
the same validation before appending their linked compensating entries.

Posting requires at least two postings, known accounts, matching asset identities
and precision, and debit atoms equal to credit atoms **separately for every
asset**. Errors return no replacement journal. Constructors are hidden behind
opaque types. Journal count is refined to a nonnegative integer; asset precision
retains finance-core's refinements.

`balance(journal, accountId)` returns debit-minus-credit atoms, not classification-
adjusted presentation. Credit-normal liability, equity, and income accounts
typically report negative values.

## Replay and audit

Entry IDs are unique. External event keys are tuples `(source, externalId)` from
`FinanceMetadata`; sources have independent namespaces. An exact retry returns
the original posted entry and unchanged journal. Same-key requests with changed
effective time, recorded time, ordered postings, or reversal link fail with
`ReplayConflict`. A new draft ID on the same external event can resolve to the
original entry; the returned entry ID is authoritative. Collisions with two
existing records are rejected. With no external ID, only entry ID protects replay.

`reverse(journal, postedEntry, newId, metadata)` appends opposite-direction
postings and records `reversal_of`. The original is retained. An exact reversal
retry with the same reversal ID is harmless; a second different reversal ID
fails with `AlreadyReversed`, even with the same external event key. The original
must exist with matching content in the supplied journal. A reversal can itself
be reversed, representing a new compensating event.

## Crypto trades

A BTC debit and USD credit alone are **not** balanced. A trade needs four legs:

| Account | Direction | Amount |
| --- | --- | --- |
| BTC wallet | Debit | 0.01 BTC |
| BTC clearing | Credit | 0.01 BTC |
| USD cash | Credit | 600.00 USD |
| USD clearing | Debit | 600.00 USD |

Pricing, valuation, fees, realized gains, chain finality, and reorg policy belong
to applications. This kernel never equates atoms of different assets.

## Scope and verification

This is a pure in-memory kernel, not a durable accounting service. Callers must
serialize concurrent writers and persist returned journals transactionally.
Opaque data prevents unvalidated appends but does not provide access control,
cross-journal identity, database transactions, regulatory compliance, or audit
tamper resistance. Journals with identical histories accept the same posted
value. Account charts are fixed at construction. Validation uses list scans;
this first version emphasizes correctness rather than large-volume throughput.

```sh
forge check
forge build
forge test --seed=42
forge test --release --seed=20261014
sh scripts/check-contracts.sh
```

Tests cover exact balances, generated reversal conservation and replay,
unbalanced rejection, precision mismatch, duplicate accounts, unknown accounts,
negative amounts, reversal membership and duplicate reversal, and crypto clearing.
Additional lifecycle tests cover validation without posting, destination chart
changes, later replay conflicts, exact arbitrary-size balances, and generated
multi-entry conservation. Compile-time checks reject forged validated/posted/
journal/posting constructors and passing a draft to `post_validated`.
