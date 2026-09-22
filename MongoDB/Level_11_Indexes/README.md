# Level 11 — Indexes

**Goal:** know every index type and when to use it, create / inspect / drop / hide indexes, read the numbers that show whether an index is used (`totalKeysExamined`, `totalDocsExamined`), and know what an index costs.

**Time:** ~3 hr · **Files:** `01_Practice_Single_Compound_Unique_Multikey.js` → `02_Practice_Special_Indexes_Management.js` → `Exercises.js`

---

## 1. Concepts in plain words

An index is a **B-tree** of `key → document location`, kept sorted. Finding one key costs a handful of page reads instead of scanning every document. Collections of 19 documents never show this — the practice files build a **200 000-document `bench_orders`** collection (kept for Level 12; `00_Reset_All.js` removes it).

| Type | Create | Use it for | Notes |
|------|--------|-----------|-------|
| **`_id`** | automatic | primary key lookups | unique, cannot be dropped |
| **Single field** | `{ customerId: 1 }` | equality / range / sort on one field | direction (1/-1) irrelevant for a single field |
| **Compound** | `{ status: 1, orderDate: -1 }` | several fields; **prefix rule**: usable for `status` alone or `status + orderDate`, **not** `orderDate` alone | field order and sort directions matter (ESR rule, Level 12) |
| **Unique** | `{ email: 1 }, { unique: true }` | constraints (SQL `UNIQUE`) | a **missing** field counts as `null` → only one document without the field; combine with **partial** to allow many |
| **Multikey** | any index on an **array** field | `tags`, `items.productId` | one entry per element; a compound index may contain **at most one** array field per document |
| **Partial** | `{ status: 1 }, { partialFilterExpression: { status: "Pending" } }` | small hot subsets, "unique except null" | used only when the query filter **implies** the expression |
| **Sparse** | `{ email: 1 }, { sparse: true }` | legacy: skip documents without the field | prefer partial (`{ f: { $exists: true } }`) |
| **TTL** | `{ createdAt: 1 }, { expireAfterSeconds: 3600 }` | sessions, logs, tokens | background thread deletes expired documents every 60 s; field must be a Date |
| **Text** | `{ title: "text", body: "text" }` | word search with stemming, `$text: { $search }` | **one per collection**; for real search use Atlas Search |
| **Hashed** | `{ customerId: "hashed" }` | hashed **sharding** keys, equality only | no range queries, no sort |
| **Wildcard** | `{ "meta.$**": 1 }` | unknown / dynamic field names | one entry per path per document; not for sorting |
| **Collation** | `{ city: 1 }, { collation: { locale: "en", strength: 2 } }` | case-insensitive queries / sorts | query must use the **same** collation to hit it |
| 2dsphere / 2d | `{ loc: "2dsphere" }` | geo queries | not in this course |
| **Clustered collection** | `createCollection(..., { clusteredIndex: … })` | the collection **is** stored ordered by `_id` (like SQL clustered index) | 5.3+, for time-series / append-only ids |

### Reading `explain("executionStats")`

| Field | Meaning |
|-------|---------|
| `winningPlan` stages: `COLLSCAN` / `IXSCAN` / `FETCH` / `SORT` / `PROJECTION_*` / `LIMIT` / `EXPRESS_IXSCAN` (8.0 fast path) | how the query ran, read **inner → outer** |
| `nReturned` | documents returned |
| `totalKeysExamined` | index entries read (0 = no index used) |
| `totalDocsExamined` | documents read from the collection (the expensive part) |
| ideal | `nReturned ≈ totalKeysExamined ≈ totalDocsExamined` (or `totalDocsExamined = 0` for a **covered** query) |

## 2. Syntax cheat-sheet

```js
db.c.createIndex({ customerId: 1 })
db.c.createIndex({ status: 1, orderDate: -1 }, { name: "ix_status_date" })
db.c.createIndex({ email: 1 }, { unique: true })
db.c.createIndex({ email: 1 }, { unique: true, partialFilterExpression: { email: { $type: "string" } } })
db.c.createIndex({ status: 1 }, { partialFilterExpression: { status: "Pending" } })
db.c.createIndex({ createdAt: 1 }, { expireAfterSeconds: 3600 })
db.c.createIndex({ name: "text", description: "text" }, { weights: { name: 10 }, default_language: "english" })
db.c.createIndex({ customerId: "hashed" })
db.c.createIndex({ "meta.$**": 1 })
db.c.createIndex({ city: 1 }, { collation: { locale: "en", strength: 2 } })
db.c.createIndexes([ { a: 1 }, { b: 1 } ])                             // shell helper: key patterns (options apply to all)
db.runCommand({ createIndexes: "c", indexes: [ { key: { a: 1 }, name: "ix_a" } ] })   // command form: full specs

db.c.getIndexes()                 db.c.dropIndex("ix_status_date")     db.c.dropIndex({ customerId: 1 })
db.c.dropIndexes()                (all except _id)
db.c.hideIndex("ix_name")         db.c.unhideIndex("ix_name")           // test a drop without dropping
db.c.aggregate([ { $indexStats: {} } ])                                  // usage counters since restart
db.c.stats().indexSizes           db.c.totalIndexSize()
db.c.find({ status: "Pending" }).explain("executionStats")
db.c.find({ status: "Pending" }).hint({ status: 1 })                    // force an index (demos / last resort)
db.c.find({ $text: { $search: "laptop -mouse" } }, { score: { $meta: "textScore" } }).sort({ score: { $meta: "textScore" } })
db.c.find({ city: "delhi" }).collation({ locale: "en", strength: 2 })
```

## 3. Gotchas

- **Prefix rule:** `{ a: 1, b: 1 }` serves `a` and `a + b`, never `b` alone. `{ a: 1, b: 1 }` makes `{ a: 1 }` redundant.
- **Sort direction matters in compound indexes**: `{ a: 1, b: -1 }` can sort `{ a: 1, b: -1 }` or `{ a: -1, b: 1 }` (inverse), not `{ a: 1, b: 1 }`.
- **Unique + missing field**: the missing value is indexed as `null` once. Two documents without `email` → `E11000`. Fix: partial unique index on `{ email: { $type: "string" } }`.
- **Compound multikey limit**: at most one array field per document in a compound index; creating / inserting a second array fails.
- **Partial index is used only when the query guarantees the filter** — `{ status: "Pending" }` yes, `{ status: { $in: ["Pending", "X"] } }` no, `{ status: { $ne: "Completed" } }` no.
- **TTL deletes at most every 60 s** and only documents whose field is a Date; the expiry field in an array uses the earliest date; TTL index on `_id` is not possible.
- **Text index**: one per collection, `$text` must be the top-level filter, no `$text` inside `$or` with non-indexed fields, language stemming ("running" matches "run"), case-insensitive. Sorting by relevance needs `$meta: "textScore"`.
- **Hashed index**: equality only, cannot be unique, cannot be a compound prefix with ranges (compound hashed since 4.4 but still no range on the hashed field), floats are truncated before hashing (`2.3` = `2`).
- **Index builds** (4.2+) use an optimised build that holds only brief locks; on a replica set they build on all members simultaneously. Still, building on a huge collection costs CPU / IO — do it off-peak or with rolling builds.
- **Every index costs writes and RAM**: each insert / update touches every index containing the field; indexes should fit in RAM (WiredTiger cache) with the working set.
- **Limits**: 64 indexes per collection, key size 1024 bytes (older) / index key limit removed in 4.2 with FCV, index name ≤ 127 bytes (removed in 4.2).
- **`hint()` bypasses the planner** — only for experiments; a wrong hint is worse than no index.
- **Indexes on low-cardinality fields (`status`, booleans)** rarely help alone — use them as the *first* field of a compound / partial index for the rare value.

## 4. Interview questions

**Q: What index types does MongoDB have?**
Single field, compound, multikey (arrays), unique, partial, sparse, TTL, text, hashed, wildcard, geospatial (2d / 2dsphere), plus clustered collections. Every collection has the `_id` index.

**Q: What is the prefix rule of a compound index?**
A compound index supports queries on any *leading* subset of its fields, in order: `{ a, b, c }` supports `a`, `a+b`, `a+b+c` (and sorts on those prefixes) but not `b` or `c` alone.

**Q: What is a multikey index and what is its limitation?**
An index on an array field: one key per element. A compound index can have at most one array-valued field per document, and multikey indexes cannot be used as shard keys or for covered queries on the array.

**Q: How do you enforce uniqueness while allowing many documents without the field?**
A partial unique index: `{ email: 1 }, { unique: true, partialFilterExpression: { email: { $type: "string" } } }`.

**Q: What is a TTL index?**
An index on a Date field with `expireAfterSeconds`; a background thread removes documents once `field + seconds < now`, checking every 60 s. Used for sessions, caches, logs.

**Q: How do you find out whether a query uses an index?**
`explain("executionStats")`: look for `IXSCAN` (vs `COLLSCAN`), compare `totalKeysExamined` / `totalDocsExamined` to `nReturned`, check for an in-memory `SORT` stage.

**Q: How do you find unused indexes?**
`db.coll.aggregate([{ $indexStats: {} }])` → `accesses.ops` since the last restart (check every replica-set member). Hide the index first (`hideIndex`) to be safe, then drop it.

**Q: Does an index help `$regex` / `$ne` / `$exists: false`?**
A **case-sensitive anchored** regex (`/^abc/`) uses an index as a range; `/abc/` and `/^abc/i` scan the whole index. `$ne`, `$nin`, `$not`, `$exists: false` are not selective and generally scan.

**Q: When would you *not* create an index?**
Write-heavy collections with rare reads, low-cardinality fields queried alone, tiny collections, columns already covered by a compound prefix, or when RAM cannot hold the index.

**Q: What is a covered query?**
A query answered entirely from the index: all filter, sort and projected fields are in the index and `_id` is excluded (or indexed). `totalDocsExamined: 0`, no `FETCH` stage (Level 12).

## 5. Checklist

- [ ] I can create single, compound, unique, partial, TTL, text, hashed, wildcard and collation indexes
- [ ] I can explain the prefix rule, the multikey limitation and the unique-vs-missing behaviour
- [ ] I can read `COLLSCAN` / `IXSCAN` / `FETCH` and the keys / docs examined counters
- [ ] I can list, drop, hide and measure the usage and size of indexes
- [ ] I can explain what an index costs on writes and memory
