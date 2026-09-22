# Level 05 — Update Operations

**Goal:** change documents safely with `updateOne` / `updateMany` / `replaceOne`, master every update operator, use upserts and `findOneAndUpdate`, and write updates that reference other fields with an aggregation pipeline.

**Time:** ~2 hr · **Files:** `01_Practice_Update_Operators.js` → `02_Practice_Upsert_FindAndModify_Pipeline.js` → `Exercises.js`

---

## 1. Concepts in plain words

| Method | What it does | Returns |
|--------|--------------|---------|
| `updateOne(filter, update, options)` | modifies the **first** matching document | `{ acknowledged, matchedCount, modifiedCount, upsertedCount, insertedId }` (the Node driver names the upserted `_id` `upsertedId`) |
| `updateMany(filter, update, options)` | modifies **all** matching documents | same |
| `replaceOne(filter, doc, options)` | replaces the whole document (keeps `_id`); `doc` has **no operators** | same |
| `findOneAndUpdate(filter, update, options)` | update + return the document (`returnDocument: "before" \| "after"`) atomically | the document |
| `findOneAndReplace` / `findOneAndDelete` | same idea | the document |
| `bulkWrite([...])` | many mixed writes in one call (Level 07) | bulk result |
| `update()` / `findAndModify()` | legacy | avoid |

- **`update` must use operators** (`{ $set: {...} }`). A plain document in `updateOne` is an error — that is `replaceOne`'s job.
- **Atomic per document**: one document is updated all-or-nothing, and concurrent updates to the same document are serialised. `updateMany` over many documents is **not** atomic as a whole (Level 14 for transactions).
- **`matchedCount` vs `modifiedCount`**: setting a field to the value it already has → matched 1, modified 0.
- **Upsert** (`{ upsert: true }`): if nothing matches, insert a new document built from the **equality fields of the filter + the update**. `$setOnInsert` sets fields only in that insert case.
- **Pipeline update** (4.2+): `updateOne(filter, [ { $set: { … } }, { $unset: … } ])` — expressions can read **other fields of the same document** (`$multiply: ["$salary", 1.1]`), use `$cond`, `$$NOW`. Only `$addFields`/`$set`, `$project`/`$unset`, `$replaceRoot`/`$replaceWith` stages are allowed.

### Update operators (field)

| Operator | Meaning | Notes |
|----------|---------|-------|
| `$set` | set field(s), creating them (and nested paths) if missing | `{ $set: { "address.city": "Pune", active: true } }` |
| `$unset` | remove field(s) | value is ignored: `{ $unset: { temp: "" } }` |
| `$inc` | add a number (negative to subtract) | creates the field if missing; error on non-number |
| `$mul` | multiply | `{ $mul: { salary: 1.1 } }`; missing field → 0 |
| `$rename` | rename a field | `{ $rename: { "adr": "address" } }`; nested ok, not inside arrays |
| `$min` / `$max` | set only if the new value is smaller / larger | great for "lowest price seen", "last login" |
| `$currentDate` | set to now | `true` → Date; `{ $type: "timestamp" }` → Timestamp |
| `$setOnInsert` | set only when an upsert inserts | audit `createdAt` |
| Array operators | `$push $pop $pull $pullAll $addToSet $each $position $slice $sort $ $[] $[id]` | Level 06 |

### SQL → MongoDB

| SQL | MongoDB |
|-----|---------|
| `UPDATE e SET salary = 80000 WHERE id = 101` | `db.e.updateOne({ _id: 101 }, { $set: { salary: 80000 } })` |
| `UPDATE e SET salary = salary + 5000 WHERE dept = 1` | `db.e.updateMany({ departmentId: 1 }, { $inc: { salary: 5000 } })` |
| `UPDATE e SET salary = salary * 1.1` | `db.e.updateMany({}, { $mul: { salary: 1.1 } })` |
| `UPDATE e SET annual = salary * 12` (column from column) | `db.e.updateMany({}, [ { $set: { annual: { $multiply: ["$salary", 12] } } } ])` |
| `UPDATE e SET band = CASE WHEN salary > 70000 THEN 'A' ELSE 'B' END` | `[ { $set: { band: { $cond: [ { $gt: ["$salary", 70000] }, "A", "B" ] } } } ]` |
| `ALTER TABLE DROP COLUMN x` | `db.e.updateMany({}, { $unset: { x: "" } })` |
| `sp_rename` column | `db.e.updateMany({}, { $rename: { old: "new" } })` |
| `MERGE` / upsert | `updateOne(filter, update, { upsert: true })` |
| `UPDATE … OUTPUT inserted.*` | `findOneAndUpdate(..., { returnDocument: "after" })` |
| `UPDATE TOP (1) … ORDER BY` | `updateOne(filter, update, { sort: { … } })` (8.0+) or `findOneAndUpdate` with `sort` |

## 2. Syntax cheat-sheet

```js
db.e.updateOne({ _id: 101 }, { $set: { salary: 88000, "address.city": "Gurgaon" } })
db.e.updateMany({ departmentId: 1 }, { $inc: { salary: 5000 }, $currentDate: { updatedAt: true } })
db.e.updateOne({ _id: 101 }, { $unset: { tempFlag: "" } })
db.e.updateOne({ _id: 101 }, { $rename: { "phone": "mobile" } })
db.e.updateOne({ _id: 101 }, { $min: { lowestSalary: 60000 }, $max: { highestSalary: 90000 } })
db.e.updateOne({ _id: 999 }, { $set: { name: "New" }, $setOnInsert: { createdAt: new Date() } }, { upsert: true })
db.e.replaceOne({ _id: 101 }, { name: "Rahul", salary: 85000 })          // everything else is gone
db.e.findOneAndUpdate({ _id: 101 }, { $inc: { logins: 1 } }, { returnDocument: "after", projection: { logins: 1 } })
db.counters.findOneAndUpdate({ _id: "orderId" }, { $inc: { seq: 1 } }, { upsert: true, returnDocument: "after" })   // sequence
db.e.updateMany({}, [ { $set: { annual: { $multiply: ["$salary", 12] }, updatedAt: "$$NOW" } } ])              // pipeline
db.e.updateMany({}, [ { $unset: ["annual", "tmp"] } ])
db.e.updateOne({ status: "Pending" }, { $set: { status: "Processing" } }, { sort: { orderDate: 1 } })          // 8.0+: oldest first
```

## 3. Gotchas

- **`updateOne({...}, { name: "x" })` (no operator) → error** `Update document requires atomic operators`. Use `$set` or `replaceOne`.
- **`replaceOne` drops every field you do not include.** It is a full overwrite (except `_id`).
- **The same field in two operators → error** (`Updating the path 'salary' would create a conflict`). Combine differently or use a pipeline.
- **`_id` cannot be modified.** `$set: { _id: … }` fails; delete + insert instead.
- **Upsert builds the new document from the filter's equality conditions.** `{ salary: { $gt: 5 } }` contributes nothing; `{ _id: 5 }` contributes `_id: 5`. Race condition: two concurrent upserts with the same filter can both insert unless a **unique index** exists on the filter field.
- **`$inc` on a non-numeric field fails**; on a missing field it creates it. `$mul` on a missing field sets 0.
- **`$rename` fails inside arrays** (`items.$.qty` → use `$set` + `$unset`).
- **Dot notation in `$set` creates intermediate objects** (`"a.b.c": 1` creates `a` and `b`), but setting `"skills.5"` on a 3-element array pads it with `null`s.
- **`modifiedCount: 0` is not an error** — the value was already there. Check `matchedCount` to know whether the filter found anything.
- **Pipeline updates cannot use `$push`/`$inc` etc.** — those are update operators, not aggregation stages. Use `$concatArrays`, `$add`.
- **`updateMany({}, …)` touches every document** — read the filter twice before pressing Enter.
- **Document growth**: updates that enlarge a document may move it (WiredTiger rewrites it) — many small `$push`es on huge documents are slow; design accordingly (Level 13).

## 4. Interview questions

**Q: updateOne vs updateMany vs replaceOne?**
`updateOne` modifies the first match with operators; `updateMany` modifies all matches; `replaceOne` swaps the whole document for the given one (no operators, `_id` kept). All return matched/modified counts.

**Q: What is an upsert? How is the inserted document built?**
`upsert: true` inserts when the filter matches nothing. The new document = equality fields of the filter + `$set`/`$inc`… values + `$setOnInsert` values. Needs a unique index on the filter field to be safe under concurrency.

**Q: How do you update a field based on another field of the same document?**
With a pipeline update: `updateMany({}, [ { $set: { total: { $multiply: ["$qty", "$price"] } } } ])`. Classic update operators cannot reference other fields.

**Q: `$set` vs `$setOnInsert`?**
`$set` applies to updates and inserts; `$setOnInsert` only when an upsert inserts — e.g. `createdAt` set once, `updatedAt` every time.

**Q: How do you implement an auto-increment id?**
A `counters` collection and `findOneAndUpdate({ _id: "orders" }, { $inc: { seq: 1 } }, { upsert: true, returnDocument: "after" })` — atomic per document. Or use ObjectId and avoid sequences (sharding-friendly).

**Q: Are updates atomic?**
Yes, per document — including all operators in one call and array modifications. Across several documents they are not; use a transaction.

**Q: findOneAndUpdate vs updateOne?**
`findOneAndUpdate` returns the document (before or after) atomically — for counters, queues (`findOneAndDelete`), claiming a job (`status: "pending"` → `"running"` and get it back). `updateOne` only returns counts.

**Q: What does `$min` do? Use case?**
Sets the field only if the new value is lower than the current one (`$max` the opposite). Used for "cheapest price seen", "first/last seen" timestamps without a read-modify-write.

**Q: How do you rename a field in every document?**
`db.c.updateMany({}, { $rename: { old: "new" } })` — it is a real rewrite of every document (plan for size and time; do it in batches on large collections).

## 5. Checklist

- [ ] I know the difference between updateOne / updateMany / replaceOne and can read the result object
- [ ] I can use `$set $unset $inc $mul $rename $min $max $currentDate` and nested dot paths
- [ ] I can do an upsert with `$setOnInsert` and explain how the new document is built
- [ ] I can use `findOneAndUpdate` for counters and job queues
- [ ] I can write a pipeline update that reads other fields and uses `$cond` / `$$NOW`
- [ ] I know the errors: missing operator, conflicting paths, immutable `_id`, `$inc` on strings
