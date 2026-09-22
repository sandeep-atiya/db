# Level 14 — Transactions

**Goal:** know exactly what MongoDB guarantees without a transaction (single-document atomicity), when you really need a multi-document transaction, how to write one correctly (sessions, `withTransaction`, retries, read/write concern), what can go wrong (write conflicts, 60-second limit, lock timeouts) and how this compares to SQL Server isolation levels.

**Time:** ~2 hr · **Files:** `01_Practice_Transactions.js` → `02_Two_Sessions_Demo.js` → `Exercises.js`

---

## 1. Concepts in plain words

| Term | Meaning |
|------|---------|
| **Single-document atomicity** | Every write to **one** document (all operators, all array changes, embedded documents) is atomic and isolated — no other client ever sees a half-updated document. This is why embedding (Level 13) removes the need for most transactions. |
| **Multi-document transaction** | Several reads/writes across documents, collections and databases that commit or abort **together** (4.0+ replica sets, 4.2+ sharded clusters). Needs a **replica set** (our compose file runs one). |
| **Session** | The context that carries a transaction: `const s = db.getMongo().startSession()`; collections used inside must come from `s.getDatabase("companyDB")`. |
| **Core API** | `s.startTransaction({ readConcern, writeConcern })` → operations → `s.commitTransaction()` / `s.abortTransaction()` → `s.endSession()`. You handle retries. |
| **Callback API** | `s.withTransaction(fn, options)` — runs `fn`, commits, and **retries automatically** on `TransientTransactionError` (write conflicts, failovers) and `UnknownTransactionCommitResult`. Use this in application code. |
| **Isolation** | **Snapshot**: the transaction reads from a consistent snapshot taken at its first operation; its own writes are visible inside it, invisible to others until commit (no dirty reads, no non-repeatable reads, no phantoms). |
| **Write conflict** | Two transactions (or a transaction and a normal write) modify the same document: the second transaction gets `WriteConflict` (code 112, label `TransientTransactionError`) immediately — retry the whole transaction. A normal (non-transactional) write waits for the transaction to finish. |
| **Read concern** | `local` (default in txn), `majority`, `snapshot` (majority-committed snapshot, needed for consistent cross-shard reads). `available`/`linearizable` are not allowed in transactions. |
| **Write concern** | Applies at **commit**: `{ w: "majority" }` recommended so the commit survives a failover. Default 5.0+: majority. |
| **Read preference** | Transactions must read from the **primary**. |
| **Limits** | `transactionLifetimeLimitSeconds` = **60 s** (then aborted by the server); lock wait `maxTransactionLockRequestTimeoutMillis` = 5 ms (→ `LockTimeout`); oplog entry per transaction ≤ 16 MB *per oplog entry* (4.2+ splits large transactions); no DDL (`createIndex`, `drop`) inside; `count()` not allowed (use `countDocuments`); no `$out`/`$merge`. |
| **Retryable writes** | Different thing: the driver retries a *single* write once after a network error (Level 07). Transactions retry via `withTransaction`. |
| **Causal consistency** | Sessions guarantee "read your own writes" and monotonic reads across operations even on secondaries — a session property, no transaction needed. |

### SQL Server ↔ MongoDB

| SQL Server | MongoDB |
|-----------|---------|
| `BEGIN TRAN … COMMIT / ROLLBACK` | `session.startTransaction()` … `commitTransaction()` / `abortTransaction()` |
| `TRY/CATCH` + retry on deadlock 1205 | `withTransaction` (auto-retry on transient errors) |
| READ COMMITTED (default) | reads outside a transaction (`local`), single-document guarantees |
| SNAPSHOT isolation | transaction default: snapshot isolation (readConcern `snapshot` = majority-committed snapshot) |
| Locks held until commit, blocking | document-level intent locks; conflicting **transactional** writers abort immediately (`WriteConflict`), non-transactional writers wait |
| Deadlock victim | no deadlocks between transactions (conflict → abort → retry) |
| Lock escalation / long transactions | 60 s lifetime, keep transactions short, no user interaction inside |
| `SAVE TRAN` | no savepoints |
| Autocommit | every non-transactional operation is its own atomic unit |

## 2. Syntax cheat-sheet

```js
// Core API (mongosh)
const session = db.getMongo().startSession();
session.startTransaction({ readConcern: { level: "snapshot" }, writeConcern: { w: "majority" } });
const orders = session.getDatabase("companyDB").orders;      // collections BOUND to the session
const products = session.getDatabase("companyDB").products;
try {
    orders.insertOne({ _id: 2001, customerId: 1, items: [ { productId: 1, qty: 1 } ] });
    const r = products.updateOne({ _id: 1, stock: { $gte: 1 } }, { $inc: { stock: -1 } });
    if (r.matchedCount === 0) throw new Error("out of stock");
    session.commitTransaction();
} catch (e) {
    session.abortTransaction();
    throw e;
} finally {
    session.endSession();
}

// Callback API (auto-retry) - mongosh and every driver
session.withTransaction(() => {
    orders.insertOne({ ... });
    products.updateOne({ ... });
}, { readConcern: { level: "snapshot" }, writeConcern: { w: "majority" } });

// Node.js driver
await session.withTransaction(async () => {
    await orders.insertOne(doc, { session });          // pass { session } to EVERY operation
    await products.updateOne(filter, update, { session });
});

// Inspect
db.serverStatus().transactions                          // currentActive, totalCommitted, totalAborted, ...
db.adminCommand({ getParameter: 1, transactionLifetimeLimitSeconds: 1 })
db.currentOp({ "transaction.parameters.txnNumber": { $exists: true } })   // running transactions (with lsid, timeOpen)
```

## 3. Gotchas

- **Forgetting the session**: `db.orders.insertOne()` inside a transaction block writes **outside** the transaction (and can even conflict with it). Always use the session-bound collection (`session.getDatabase(...)`) / pass `{ session }` in drivers.
- **A transaction is not a lock on the future**: reads inside see the snapshot; a document you read may be modified by others — if you then write it, you get a `WriteConflict` and must retry. Design for retries (idempotent callbacks, no side effects like sending emails inside).
- **Keep it short**: no user input, no network calls inside; the server aborts after 60 s and every transaction pins the snapshot (WiredTiger cache pressure).
- **Write conflicts are normal**, not bugs — `withTransaction` retries them. But a hot document (a global counter) updated by many transactions will thrash; redesign (per-shard counters, `$inc` outside transactions).
- **Non-transactional writes on the same document block** until the transaction ends (up to 60 s) — a long transaction can stall the whole application.
- **DDL is not allowed** inside (create/drop index, drop collection); implicit collection creation on insert is allowed since 4.4.
- **Errors inside `withTransaction` that are not transient** (business errors, validation) abort and are re-thrown — do not swallow them.
- **`commitTransaction` can fail with `UnknownTransactionCommitResult`** (network) — the commit may or may not have happened; `withTransaction` retries the commit safely (commit is idempotent within the session).
- **Standalone servers cannot run transactions** ("Transaction numbers are only allowed on a replica set member or mongos") — that is why the practice setup is a 1-node replica set.
- **Transactions are not a substitute for schema design.** If two documents must always change together and belong together, embed them.

## 4. Interview questions

**Q: Does MongoDB support ACID transactions?**
Yes. Every single-document write has always been atomic; since 4.0 multi-document transactions on replica sets (4.2 sharded clusters) are ACID with snapshot isolation, committed with a configurable write concern.

**Q: When do you need a multi-document transaction, and when not?**
Need: atomic changes across documents/collections that cannot be modelled as one document (transfer between two accounts, order + stock decrement, both sides of a many-to-many). Not needed: anything that lives in one document (embed), independent updates, counters (`$inc`), idempotent retries.

**Q: What isolation level do transactions use?**
Snapshot isolation: consistent snapshot at start, own writes visible inside, others' committed writes invisible until you start a new transaction; conflicting writes abort with `WriteConflict`.

**Q: Core API vs callback API?**
Core: explicit `startTransaction/commit/abort`, you write retry logic. Callback (`withTransaction`): runs your function, commits, and retries transient errors and unknown commit results automatically. Prefer the callback API.

**Q: What is a `TransientTransactionError`?**
An error label meaning "the whole transaction can safely be retried from the start": write conflicts, primary failover, network errors before commit. `UnknownTransactionCommitResult` means retry only the commit.

**Q: What limits apply?**
60-second lifetime by default, 5 ms lock acquisition timeout (retry), reads from primary only, no DDL / `$out` / `$merge` / `count`, one open transaction per session; large transactions hurt cache and replication.

**Q: How do transactions behave on sharded clusters?**
Supported since 4.2 (two-phase commit coordinated by the first shard, `readConcern: "snapshot"` for a cluster-wide consistent view); more expensive than on a replica set — avoid cross-shard transactions in hot paths by choosing a shard key that keeps related documents together.

**Q: Transactions vs retryable writes?**
Retryable writes: a single-document write retried once by the driver after a transient network error. Transactions: multi-document atomicity with explicit commit; retried by `withTransaction`.

**Q: How would you implement "place order and reduce stock" safely?**
Preferably one document (order with embedded reserved-stock event) or an idempotent two-step with compensation; if both collections must change atomically: `withTransaction` → conditional `updateOne({ _id, stock: { $gte: qty } }, { $inc: { stock: -qty } })` (matchedCount 0 → throw → abort) + `insertOne(order)`, write concern majority.

## 5. Checklist

- [ ] I can explain single-document atomicity and why embedding avoids transactions
- [ ] I can write a transaction with the core API and with `withTransaction`, using session-bound collections
- [ ] I can demonstrate snapshot isolation (outside readers see old data until commit) and abort
- [ ] I can provoke and handle a `WriteConflict` and explain `TransientTransactionError`
- [ ] I know the limits (60 s, primary only, no DDL) and the write/read concern settings
- [ ] I can map SQL Server isolation concepts to MongoDB behaviour
