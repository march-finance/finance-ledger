# finance-ledger guide

Immutable, exact double-entry journals for March 0.5.0.
This guide covers ledger operations only, without crypto or serialization.

## Install

Merge these entries into your application's `forge.toml`:

```toml
[deps]
finance-core = "0.1.0"
finance-ledger = "0.1.0"
```

Run `forge deps` and commit your application's lockfile. The examples use core
types directly, so declare core explicitly. Pin `.march-version` to `v0.5.0`;
install with `forge toolchain install v0.5.0`.

## Quickstart: post, retry, reverse

Save the complete test below under `test/ledger_quickstart_test.march` and run
`forge test --seed=42`. It funds cash with 12.50 USD of equity, retries the same
draft without duplication, then reverses the original.

```march
mod LedgerQuickstart do
  needs IO.Clock, IO.Process

  fn example() : Result(String, LedgerError.Error) do
    let usd = Result.unwrap(FinanceAsset.fiat("USD", 2))
    let metadata = Result.unwrap(FinanceMetadata.make("manual", 100, 101, Some("funding-1")))
    let? cash = LedgerAccount.make("cash", LedgerAccount.AssetAccount, usd)
    let? equity = LedgerAccount.make("equity", LedgerAccount.EquityAccount, usd)
    let? journal = LedgerJournal.new([cash, equity])
    let quantity = FinanceAmount.from_atoms(usd, BigInt.from_int(1250))
    let? debit = LedgerEntry.posting("cash", LedgerEntry.Debit, quantity)
    let? credit = LedgerEntry.posting("equity", LedgerEntry.Credit, quantity)
    let? empty = LedgerEntry.draft("opening-1", metadata)
    let draft = LedgerEntry.add(LedgerEntry.add(empty, debit), credit)
    let? (posted_journal, original) = LedgerJournal.post(journal, draft)
    let? (retried, _) = LedgerJournal.post(posted_journal, draft)
    let undo_metadata = Result.unwrap(FinanceMetadata.make("manual", 102, 103, Some("undo-1")))
    let? (reversed, _) = LedgerJournal.reverse(retried, original, "reversal-1", undo_metadata)
    let? balance = LedgerJournal.balance(reversed, "cash")
    Ok(FinanceAmount.format(balance))
  end

  test "documented posting retry and reversal" do
    assert (match example() do
      Ok(value) -> value == "0.00"
      Err(_) -> false
    end)
  end
end
```

The fixed core literals use `Result.unwrap` for brevity. For external input,
handle `FinanceError.Error` before entering this ledger-only Result function,
or map it into an application error type. Ledger operations use `let?` to
propagate `LedgerError.Error`.

After posting, cash is +12.50 and equity is -12.50. Retry leaves one entry.
Reversal leaves two entries and both balances at zero. Each returned journal
is a new value; the original empty journal and posted history still exist.

## Accounts and chart design

`LedgerAccount.make(id, kind, asset)` declares one asset and precision per account.
Kinds are AssetAccount, LiabilityAccount, EquityAccount, IncomeAccount and
ExpenseAccount. Account classification is not currency identity or custody location.
Use separate accounts for different currencies and locations.

IDs must be nonempty and cannot contain ASCII whitespace/control bytes <= space.
`LedgerJournal.new(accounts)` requires globally unique account IDs.
The chart is fixed for that journal; version 0.1.0 has no add-account operation.

`balance(journal, id)` returns a Quantity using debit minus credit for EVERY kind.
Credit-normal equity, income and liability balances are therefore often negative.
Apply your own presentation conventions; negative balances are not rejected and
the library does not check available funds.

## Draft, validation and posting

`LedgerEntry.posting(accountId, direction, quantity)` accepts strictly positive
quantities. Use Debit or Credit for direction, not a negative amount.
`draft(id, metadata)` starts empty; `add(draft, posting)` returns a new draft
with that posting appended. Posting order is part of replay comparison.

`LedgerJournal.post(journal, draft)` validates and returns
`Result((Ledger, PostedEntry), LedgerError.Error)`. Validation requires at least
two postings, known accounts, matching asset/precision, and equal debit and credit
atoms separately for every asset. Two different currencies cannot offset each other.

For separate review and posting, call `LedgerJournal.validate(journal, draft)`
then `LedgerJournal.post_validated(journal, validated)`.
The opaque Validated value stores an immutable draft, not a reservation or
authorization. Posting rechecks the destination chart and current replay state.
Failure returns no replacement journal; keep the journal you already had.

Inspect history with `entries`, `count`, `entry_id`, `draft` and `reversal_of`.
Posted values cannot be appended by bypassing the journal's operations.

## Retry and correction policy

A retry can match by entry ID or by metadata's (source, external ID).
No external ID means entry ID alone protects replay. Preserve effective time,
recorded time, ordered postings and reference keys across retries. Recomputing
recorded time on every retry can cause ReplayConflict.

An exact retry returns the original posted entry without appending. A different
draft ID with the same external event may return the OLD posted ID; trust the
returned entry, not the request ID. Conflicting content or keys matching two
different existing entries fail.

`reverse(journal, originalPostedEntry, newId, metadata)` appends a linked entry
with opposite directions. The original must exist with matching content.
Retrying the same reversal ID/content is harmless; another reversal ID for the
same original fails with AlreadyReversed. A reversal can itself be reversed.
There is no edit/delete posted-entry operation.

## Error handling reference

| LedgerError | Meaning / response |
| --- | --- |
| InvalidId | Fix account or draft ID |
| DuplicateAccount | Deduplicate the chart before construction |
| UnknownAccount | Posting/balance references an absent account |
| AssetMismatch | Account and quantity identity or precision disagree |
| InvalidAmount | Posting quantity is zero or negative |
| EmptyEntry | Fewer than two postings |
| Unbalanced | Debit and credit totals differ for an asset |
| ReplayConflict | Inspect conflicting identity/content; do not blindly change keys |
| UnknownEntry | Reversal target is absent or does not match |
| AlreadyReversed | Original already has another reversal |

Do not treat ReplayConflict as a transient transport failure. Resolve it using
the stored entry and source event. Never silently overwrite history.

## Operating boundaries

This is a pure in-memory accounting kernel, not a database. Serialize writers
yourself, and atomically persist the returned journal and any related ingestion
state. Two callers starting from the same old journal can independently produce
different valid successors. Opaque values do not prevent that race.

There is no authorization, durable transaction, tamper evidence, overdraft check,
currency conversion, valuation, tax/compliance policy or high-volume indexing.
Lists are scanned for validation and balances. A balanced journal proves internal
accounting consistency, not that an external transaction actually occurred.

See the [module map and contract tests](../README.md) and
[tested quickstart](../test/docs_quickstart_test.march).
