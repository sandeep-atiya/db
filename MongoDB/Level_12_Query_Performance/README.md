# Level 12 — Query Performance

**Goal:** read an execution plan like a DBA, design indexes with the **ESR rule**, write **covered** queries, recognise non-selective / non-indexable predicates, use the profiler, `currentOp` and the plan cache, and understand how the aggregation optimiser rewrites pipelines — so you can answer "this query is slow, what do you do?" with confidence.

**Time:** ~3 hr · **Files:** `01_Practice_Explain_ESR_Covered.js` → `02_Practice_Profiler_PlanCache_Aggregation.js` → `Exercises.js`

---

## 1. Concepts in plain words

### explain()

| Verbosity | Runs the query? | Gives |
|-----------|-----------------|-------|
| `"queryPlanner"` (default) | no | `winningPlan`, `rejectedPlans`, index bounds |
| `"executionStats"` | yes (winning plan) | + `nReturned`, `totalKeysExamined`, `totalDocsExamined`, `executionTimeMillis`, per-stage `works` / `advanced` |
| `"allPlansExecution"` | yes (all candidates, briefly) | + stats of the rejected plans (why the planner chose) |

Read the stage tree **from the innermost `inputStage` outwards** (like SQL Server plans right-to-left).

| Stage | Meaning |
|-------|---------|
| `COLLSCAN` | every document read — fine for tiny collections or "return most rows", bad for selective filters |
| `IXSCAN` | B-tree range scan; look at `indexBounds` and `keysExamined` |
| `EXPRESS_IXSCAN` / `EXPRESS_CLUSTERED_IXSCAN` (8.0) | fast path for single-key equality (`_id`, unique keys) |
| `FETCH` | load the full document for each index entry (the "Key Lookup"); has a `filter` when the index could not cover the predicate |
| `SORT` | in-memory sort; `memLimit` 100 MB, `totalDataSizeSorted`; with `LIMIT` it is a cheap top-k |
| `PROJECTION_COVERED` / `_SIMPLE` / `_DEFAULT` | covered = no FETCH needed |
| `LIMIT` / `SKIP` | |
| `OR` / `SUBPLAN` | each `$or` branch planned separately |
| `AND_SORTED` / `AND_HASH` | index intersection (rare; a compound index is usually better) |
| `COUNT_SCAN` / `DISTINCT_SCAN` | count / distinct answered from the index only |
| `TEXT_MATCH` | text index |
| `SHARD_MERGE` / `SINGLE_SHARD` | sharded cluster (Level 18) |
| `$cursor` (aggregation) | the find-part of a pipeline; stages after it run in the aggregation engine |

**Health check:** `nReturned` ≈ `totalKeysExamined` ≈ `totalDocsExamined`. Ratios like 1 : 1000 : 1000 = wrong / missing index. `totalDocsExamined: 0` = covered.

### Designing the index: the ESR rule

For a query with **E**quality predicates, a **S**ort, and **R**ange predicates, order the compound index fields **Equality → Sort → Range**:
`find({ status: "Completed", totalAmount: { $gte: 1e5 } }).sort({ orderDate: -1 })` → `{ status: 1, orderDate: -1, totalAmount: 1 }`.
Equality first narrows to one index range; sort next lets the index deliver order (no `SORT`); the range last is applied while scanning. Putting the range before the sort forces an in-memory sort of every match.

### Other rules of thumb

- **Selectivity**: an index only pays off when the predicate returns a small fraction (< ~10 %) — otherwise scanning the index *and* fetching every document is slower than a `COLLSCAN`. The planner knows and may skip a low-selectivity index.
- **Non-selective / un-indexable predicates**: `$ne`, `$nin`, `$not`, `$exists: false`, `$where`, unanchored or case-insensitive `$regex`, `$expr` on computed values, `$mod`, `$size` — they scan.
- **Covered query**: filter + sort + projection all inside one index, `_id: 0` (unless `_id` is in the index), no array fields → `PROJECTION_COVERED`, `docsExamined 0`.
- **Sort limit**: `SORT` without an index may use 100 MB; above that → error unless `allowDiskUse` (find 6.0+ / aggregate). A supporting index is the real fix.
- **`hint()`**: forces an index (or `{ $natural: 1 }` for a scan). Experiments only.
- **Plan cache**: the planner races candidate plans for a *query shape* (filter shape + sort + projection + collation), caches the winner, and re-plans when it performs badly (replanning) or indexes change. `getPlanCache().list()`, `planCacheClear()`, `$planCacheStats`. Parameter values are not part of the shape → a plan good for a rare value can be reused for a common one (MongoDB's version of parameter sniffing).
- **Profiler**: `db.setProfilingLevel(1, { slowms: 100 })` writes slow ops to the capped `system.profile` collection (per database); level 2 = everything (dev only). Fields: `op`, `ns`, `millis`, `planSummary`, `keysExamined`, `docsExamined`, `nreturned`, `command`.
- **`currentOp` / `killOp`**: see running operations (`secs_running`, `waitingForLock`, `planSummary`) and kill one by `opid`. `maxTimeMS` on a query stops it server-side.
- **Aggregation optimiser**: `$match` and `$sort` are pushed before `$project`/`$set` when possible and into the `$cursor` stage (index use); `$sort` + `$limit` become a top-k sort; `$skip` + `$limit` merge; `$lookup` uses the index on `foreignField`; `$facet` / `$group` cannot use indexes after they start. Rule: `$match` first, `$project` only what is needed, `$sort`+`$limit` together, index the `$lookup` foreign key.
- **Memory**: WiredTiger cache ≈ 50 % of RAM − 1 GB; the **working set** (hot documents + indexes) should fit; `db.serverStatus().wiredTiger.cache`.

## 2. Syntax cheat-sheet

```js
db.c.find(q).explain()                          // queryPlanner
db.c.find(q).sort(s).explain("executionStats")
db.c.find(q).explain("allPlansExecution").queryPlanner.rejectedPlans
db.c.aggregate(pipeline).explain("executionStats")
db.c.find(q).hint({ status: 1, orderDate: -1 })      db.c.find(q).hint({ $natural: 1 })
db.c.find(q).maxTimeMS(500)                    db.c.find(q).sort(s).allowDiskUse()
db.c.find(q, { _id: 0, a: 1, b: 1 })            // covered if index { a, b }

db.c.getPlanCache().list()                     db.c.getPlanCache().clear()
db.c.aggregate([ { $planCacheStats: {} } ])
db.setProfilingLevel(1, { slowms: 50 })         db.getProfilingStatus()        db.setProfilingLevel(0)
db.system.profile.find().sort({ ts: -1 }).limit(5)
db.currentOp({ active: true, secs_running: { $gt: 5 } })      db.killOp(<opid>)
db.serverStatus().wiredTiger.cache["bytes currently in the cache"]
db.c.stats().wiredTiger["block-manager"]["file size in bytes"]
```

## 3. Gotchas

- **`executionStats` runs the query** — on production, prefer `queryPlanner` or run on a secondary.
- **A used index is not automatically a good index**: `IXSCAN` reading 180 000 keys for 20 results is still slow. Watch `keysExamined`, not just the stage name.
- **`FETCH` with a `filter`** means the index did not cover part of the predicate — add that field to the index (respecting ESR).
- **Multikey indexes cannot cover** a query (the projected array field must come from the document).
- **Index bounds on a range plus a later equality** (`{ range, eq }` order) become loose: the equality is applied as a filter, not as bounds. Equality fields first.
- **`$in` with a sort**: `{ status: { $in: [...] } }` + sort on the next field is handled as several ranges merged with a `SORT_MERGE` — still fine, but watch big `$in` lists.
- **`$regex` anchored and case-sensitive only** uses index bounds. `/^abc/i` scans the whole index.
- **Plan cache is per shape, not per value** — a plan chosen for `{ status: "Cancelled" }` (3 %) gets reused for `{ status: "Completed" }` (90 %). The replanning mechanism usually catches it; `planCacheClear` or a hint / different query shape can help.
- **The profiler adds overhead and its collection is capped (1 MB)** — use `slowms`, sample with `sampleRate`, and turn it off afterwards. Atlas / Ops Manager give the same data without the write cost.
- **`explain()` on a sharded cluster** shows per-shard plans under `shards`; targeted vs scatter-gather is visible there (Level 18).
- **Counting with a filter uses `COUNT_SCAN` only for indexed equality/range**; `countDocuments({})` still walks the `_id` index — `estimatedDocumentCount()` is metadata.

## 4. Interview questions

**Q: A query is slow — what do you do?**
1) `explain("executionStats")`: COLLSCAN? keys/docs examined vs returned? in-memory SORT? FETCH filter? 2) Check the predicate: selective? indexable (no `$ne`, unanchored regex, `$where`)? 3) Design / fix the index with ESR, consider covering; check `hint` experiments. 4) Check the profiler / `currentOp` for lock waits and long-running ops; `maxTimeMS`. 5) Check the plan cache (bad cached plan → clear). 6) Look at the server: working set vs cache, disk, replication lag, connection storms. 7) Rewrite (pagination with keyset, `$match` first in aggregation, avoid `$lookup` on unindexed fields, project less). 8) Schema: embed vs reference, bucket pattern.

**Q: What is the ESR rule?**
Compound index field order: Equality fields first, then the Sort fields (in the query's direction), then Range fields. It yields tight bounds and an index-delivered sort.

**Q: What is a covered query and how do you verify it?**
All fields in the filter, sort and projection are in one index (and `_id` is excluded or indexed) → answered from the index alone. `explain` shows `PROJECTION_COVERED`, no `FETCH`, `totalDocsExamined: 0`.

**Q: What does `totalKeysExamined` >> `nReturned` tell you?**
The index bounds are loose (wrong field order, range before equality/sort, `$in` blow-up, multikey) or the index is not selective for that value. Redesign the index or the predicate.

**Q: How does MongoDB pick a plan?**
The planner builds candidate plans from applicable indexes, runs them in a short trial ("works" budget), keeps the one that produces results fastest, and caches it per query shape. Re-planning happens when the cached plan's performance degrades or indexes change.

**Q: How do you find slow queries in production?**
Database profiler (`setProfilingLevel(1, { slowms })` → `system.profile`), the slow query log lines (`slowOpThresholdMs`), `currentOp` for what is running now, Atlas Performance Advisor / Ops Manager, `$indexStats` for unused indexes.

**Q: What is the difference between `hint()` and just having the index?**
`hint` forces the planner to use a specific index (or `$natural` scan) regardless of its own choice. Use it to diagnose; in code only as a last resort because it silently breaks when the index is dropped or the data changes.

**Q: How does the aggregation optimiser help?**
It moves `$match` / `$sort` earlier (before `$project`/`$set`, into the query cursor so indexes are used), merges `$sort`+`$limit` into a top-k sort and `$skip`+`$limit`, and removes unneeded stages. But it cannot help a `$match` placed after `$group`, or an unindexed `$lookup`.

**Q: What is the working set?**
The portion of data + indexes accessed regularly. If it exceeds the WiredTiger cache (~50 % RAM − 1 GB), reads hit disk and latency jumps — add RAM, reduce data / indexes, or shard.

## 5. Checklist

- [ ] I can read a plan tree and the four key numbers, and spot COLLSCAN / SORT / FETCH-with-filter problems
- [ ] I can design a compound index with ESR and prove the SORT stage disappeared
- [ ] I can write and verify a covered query
- [ ] I can list predicates that cannot use indexes and rewrite them
- [ ] I can use `hint`, `maxTimeMS`, `allowDiskUse` and know their risks
- [ ] I can enable the profiler, read `system.profile`, use `currentOp` / `killOp`
- [ ] I can inspect and clear the plan cache and explain query-shape caching
- [ ] I can explain the aggregation optimiser's rewrites and index the `$lookup` foreign field
