# Level 07 — Delete & Bulk Write

**Goal:** remove documents safely (`deleteOne`, `deleteMany`, `findOneAndDelete`), know the difference between emptying and dropping a collection, delete large volumes without hurting the server, and batch mixed writes with `bulkWrite`.

**Time:** ~1 hr · **Files:** `01_Practice_Delete_Bulk.js` → `Exercises.js`

---

## 1. Concepts in plain words

| Method | What it does | Returns |
|--------|--------------|---------|
| `deleteOne(filter)` | deletes the **first** matching document (natural order — use a precise filter, usually `_id`) | `{ acknowledged, deletedCount }` |
| `deleteMany(filter)` | deletes **all** matching documents; `{}` = every document | same |
| `findOneAndDelete(filter, { sort, projection })` | deletes one and **returns it** (atomic pop from a queue) | the document or `null` |
| `drop()` | removes the collection **with its indexes** — instant, like `DROP TABLE` | `true` / `false` |
| `bulkWrite([ops], { ordered })` | many inserts / updates / replaces / deletes in one round trip | bulk result with counts |
| `remove()` | legacy | avoid |

- **No cascading deletes.** Deleting a customer does not touch their orders. Do it in the application (two statements, ideally in a transaction — Level 14) or embed the data so it dies with the parent.
- **Deletes are atomic per document** and cannot be rolled back outside a transaction. There is no undo — back up first (Level 16) or use a **soft delete** (`deletedAt` field + filters / partial index).
- **`deleteMany({})` vs `drop()`**: `deleteMany` removes documents one by one (logged in the oplog, keeps indexes and collection options, slow for millions). `drop` throws away the whole collection instantly, indexes included; recreate indexes afterwards. `TRUNCATE` in SQL is closest to `drop` + recreate.
- **Large deletes**: run in batches (`find` ids with `limit` → `deleteMany({ _id: { $in: ids } })`, loop) so replication lag and locking stay small; or use a **TTL index** (Level 11) to let the server expire documents automatically.
- **`bulkWrite`** operations: `insertOne`, `updateOne`, `updateMany`, `replaceOne`, `deleteOne`, `deleteMany` (with `upsert`, `arrayFilters`, `collation`, `hint` where relevant). `ordered: true` (default) stops at the first error; `ordered: false` runs everything and reports every error (and can run in parallel). Max 100 000 operations per call (the driver splits them into batches).
- **Write concern** (`{ w: 1 | "majority" | n, j: true|false, wtimeout }`) applies to deletes and bulk writes too. **Retryable writes** (default on) let the driver retry a single delete/update/insert once after a network error or failover without duplicating it.

### SQL → MongoDB

| SQL | MongoDB |
|-----|---------|
| `DELETE FROM t WHERE id = 5` | `db.t.deleteOne({ _id: 5 })` |
| `DELETE FROM t WHERE status = 'X'` | `db.t.deleteMany({ status: "X" })` |
| `DELETE TOP (1) … ORDER BY date` | `db.t.findOneAndDelete({ … }, { sort: { date: 1 } })` |
| `DELETE FROM t` (all rows, keep table) | `db.t.deleteMany({})` |
| `TRUNCATE TABLE t` | `db.t.drop()` then recreate indexes (fast) |
| `DROP TABLE t` | `db.t.drop()` |
| `ON DELETE CASCADE` | application code / transaction |
| `MERGE` (many rows) | `bulkWrite([{ updateOne: { filter, update, upsert: true } }, …])` |
| batch of INSERT/UPDATE/DELETE | `bulkWrite([...])` |

## 2. Syntax cheat-sheet

```js
db.orders.deleteOne({ _id: 1006 })
db.orders.deleteMany({ status: "Cancelled" })
db.orders.deleteMany({})                                   // everything - keep your hand off Enter
db.orders.findOneAndDelete({ status: "Pending" }, { sort: { orderDate: 1 }, projection: { _id: 1 } })
db.orders.drop()

db.products.bulkWrite([
    { insertOne:  { document: { _id: 12, name: "Dock", price: 6500, stock: 8 } } },
    { updateOne:  { filter: { _id: 9 }, update: { $set: { stock: 15 } } } },
    { updateOne:  { filter: { _id: 13 }, update: { $set: { name: "Hub" } }, upsert: true } },
    { updateMany: { filter: { category: "Stationery" }, update: { $mul: { price: 1.05 } } } },
    { replaceOne: { filter: { _id: 11 }, replacement: { name: "Webcam HD", price: 5000 } } },
    { deleteOne:  { filter: { _id: 8 } } },
    { deleteMany: { filter: { stock: 0 } } }
], { ordered: false })
// -> { insertedCount, matchedCount, modifiedCount, deletedCount, upsertedCount, upsertedIds, insertedIds }

// batched mass delete
let n;
do {
    const ids = db.logs.find({ createdAt: { $lt: cutoff } }, { _id: 1 }).limit(1000).toArray().map(d => d._id);
    n = ids.length ? db.logs.deleteMany({ _id: { $in: ids } }).deletedCount : 0;
} while (n > 0);

// soft delete
db.customers.updateOne({ _id: 8 }, { $set: { deletedAt: new Date() } })
db.customers.find({ deletedAt: { $exists: false } })
```

## 3. Gotchas

- **`deleteOne` with a broad filter deletes an arbitrary matching document.** There is no `sort` option on `deleteOne`; use `findOneAndDelete` with `sort`.
- **`deleteMany({})` on a big collection is slow and floods the oplog** (each document is an oplog entry) → batches, or `drop()` if you can afford to lose indexes for a moment.
- **`drop()` also removes the collection's options** (validator, collation, capped) and any views still exist but are broken.
- **`deletedCount: 0` is not an error.** Check it if the delete was expected to hit.
- **A `bulkWrite` is not a transaction.** Ordered stops at the first error, but the operations before it stay applied; unordered applies everything that can be applied.
- **Partial results on error:** catch the `MongoBulkWriteError` — `e.result` holds the counts, `e.writeErrors` the failed operations (index, code, message).
- **Deleting the document a cursor is iterating** is fine (cursors are snapshot-less; you may just not see it).
- **Deleting from a capped collection** is not allowed (only drop / TTL-like behaviour by size).

## 4. Interview questions

**Q: deleteOne vs deleteMany vs drop?**
`deleteOne` removes the first match, `deleteMany` all matches (documents only, indexes stay), `drop` removes the entire collection including indexes and options instantly.

**Q: How do you "truncate" a collection efficiently?**
`drop()` and recreate indexes — `deleteMany({})` writes an oplog entry per document and is much slower on large collections.

**Q: How do you delete millions of old documents without impacting production?**
In batches by `_id` (`find … limit → deleteMany $in`), during low traffic, watching replication lag; or design with a **TTL index** so expiry is automatic; or partition by time into collections and drop old ones.

**Q: Does MongoDB support cascading deletes / foreign keys?**
No. Referential integrity is the application's responsibility (delete children then parent in a transaction), or embed child data so it is removed with the parent.

**Q: What is `bulkWrite` and when do you use it?**
One call carrying many write operations of different types. Fewer round trips, one result; `ordered: false` lets the server execute in parallel and report all errors. Use it for imports, syncs (upsert per row), and mass corrections. It is not atomic across operations.

**Q: What is a soft delete and why use it?**
Marking a document deleted (`deletedAt`, `isDeleted`) instead of removing it — keeps history / audit, allows undo, but every query must filter it out (a partial index on `deletedAt: { $exists: false }` keeps that cheap).

**Q: What are retryable writes?**
The driver automatically retries `insertOne`, `updateOne`, `deleteOne`, `findOneAndX` and bulk single-document operations exactly once after a transient network error or primary failover, using a transaction id so the write is not applied twice. On by default (`retryWrites=true`). `updateMany` / `deleteMany` are **not** retryable.

## 5. Checklist

- [ ] I can delete one / many / and-return with a precise filter and read `deletedCount`
- [ ] I know when to use `deleteMany({})` and when `drop()`
- [ ] I can delete a parent and its children by hand and know why cascading does not exist
- [ ] I can implement a soft delete
- [ ] I can write a `bulkWrite` with mixed operations, ordered and unordered, and read its result and errors
- [ ] I can delete large volumes in batches
