# MongoDB — Step-by-Step Practice (Basic → Advanced)

A self-paced, hands-on course in **20 small levels**, built exactly like the MS SQL Server course next door. Every level has the same three things:
a short **README** (concepts + gotchas + interview Q&A + checklist), one or more runnable **Practice** scripts with explanations and expected results,
and an **Exercises** script (questions first, solutions below). One practice database is used everywhere — the **same Company / Sales data as `SQLPractice`**, reshaped the MongoDB way, so you can run the same question in T-SQL and in MongoDB and compare.

> Server used to validate everything: **MongoDB 8.x** in Docker (a 1-node replica set) with **mongosh 2.x**. Every script in this course was executed against it; expected results are written as trailing comments.

---

## 1. How to use (3 steps)

1. **Start the server once:** `cd 00_Setup` → `docker compose up -d` (MongoDB 8 + a web UI on <http://localhost:8081>). Then load the data: `mongosh --file 00_Reset_All.js`.
   Re-run the reset any time you want fresh data (e.g. after Level 05 or 14).
2. **Go level by level.** In each `Level_NN_*` folder:
   1. read `README.md` (10–15 min),
   2. open `01_Practice*.js`, run it **block by block** (paste into `mongosh`, or select the lines in a VS Code MongoDB Playground / Compass shell), *predict the output before running*,
   3. solve `Exercises.js` in the "YOUR ANSWERS" area, then compare with the solutions.
3. **Tick the checklist** at the bottom of each README and in the roadmap table below.

**Tips**
- Whole practice file with every result echoed: `Get-Content 01_Practice.js -Raw | mongosh --quiet` (PowerShell) or `mongosh --quiet < 01_Practice.js` (bash). `mongosh --file x.js` only shows `print()` output.
- `use("companyDB")` and `show("collections")` are the script-safe forms of `use companyDB` / `show collections`.
- Everything that is *supposed* to fail is wrapped in `try { … } catch (e) { print("EXPECTED ERROR: …") }` so a whole file runs clean.
- Levels 16 and 20 use **PowerShell** scripts (`.ps1`) because backups and Docker are command-line tools; Level 19 uses **Node.js**.
- Levels 15, 17 and 18 ship extra `docker-compose.*.yml` labs (auth-enabled server, 3-node replica set, sharded cluster) — start them only for that level, `down -v` afterwards.
- Never start a line with `.sort(...)` when pasting into mongosh — the shell reads a leading `.` as a REPL command.

## 2. Folder structure

```
MongoDB/
├── README.md                                   <- you are here (roadmap + quick revision)
├── 00_Setup/                                   <- docker-compose.yml, 00_Reset_All.js, data model, tricky cases
├── Level_01_MongoDB_Basics/                    <- each level: README.md, 01_Practice*.js, Exercises.js
├── Level_02_Insert_and_Data_Types/
├── ...
├── Level_20_Docker_and_Production/
├── Interview_Prep/
│   ├── MongoDB_Interview_Questions.md          <- 95 questions with crisp answers
│   ├── Top_Query_Patterns.js                   <- 30 must-know queries, runnable
│   └── SQL_to_MongoDB_Cheatsheet.md            <- T-SQL ↔ MongoDB translation table
└── _archive/                                   <- your original MongoDB.docx roadmap
```

## 3. Practice database in one look

```
departments 1──< employees (self-reference managerId) 1──< orders >──1 customers
                                                          │
                                                          └── items: [ { productId → products, qty, unitPrice } ]   (embedded order lines)
```
6 departments · 12 employees · 8 customers · 11 products · 19 orders (26 embedded lines), with built-in edge cases
(employee with `departmentId: null` **and** no email field, empty vs missing arrays, department with no employees, duplicate salaries,
customer with `email: null` vs missing email, customer with no orders, product never sold, product with 0 stock, order with no salesperson,
Pending/Cancelled statuses, 9 months of dates). Full details: [00_Setup/README.md](00_Setup/README.md).

## 4. Roadmap & progress

| # | Level | You will be able to… | Done |
|---|-------|----------------------|:----:|
| 01 | [MongoDB Basics](Level_01_MongoDB_Basics/README.md) | vocabulary, mongosh, databases/collections/documents, `_id`/ObjectId, BSON, create/rename/drop, SQL↔Mongo terms | ☐ |
| 02 | [Insert & Data Types](Level_02_Insert_and_Data_Types/README.md) | insertOne/Many (ordered), custom `_id`, every BSON type, int vs double vs Decimal128, dates (UTC), null vs missing, type order | ☐ |
| 03 | [Find & Query Operators](Level_03_Find_and_Query_Operators/README.md) | comparison · logical · element · `$regex` · `$expr` · dot notation · arrays basics · cursors | ☐ |
| 04 | [Projection, Sort, Limit, Skip](Level_04_Projection_Sort_Limit_Skip/README.md) | projection (`$slice`, `$elemMatch`, computed) · sort rules & collation · pagination (skip vs keyset) · count · distinct | ☐ |
| 05 | [Update Operations](Level_05_Update_Operations/README.md) | `$set $unset $inc $mul $rename $min $max $currentDate` · upsert · findOneAndUpdate · pipeline updates · replaceOne | ☐ |
| 06 | [Arrays & Nested Documents](Level_06_Arrays_and_Nested_Documents/README.md) | `$all $size $elemMatch` · `$push/$addToSet/$pop/$pull` · positional `$`, `$[]`, `$[id]` + arrayFilters · nested updates | ☐ |
| 07 | [Delete & Bulk Write](Level_07_Delete_and_Bulk_Write/README.md) | deleteOne/Many · findOneAndDelete · drop vs deleteMany · soft delete · batched deletes · bulkWrite (ordered/unordered) | ☐ |
| 08 | [Aggregation Basics](Level_08_Aggregation_Basics/README.md) | pipeline · `$match $project $set $group $sort $limit $skip $count $sortByCount` · accumulators · HAVING · conditional aggregation | ☐ |
| 09 | [Aggregation Advanced](Level_09_Aggregation_Advanced/README.md) | `$unwind` · `$lookup` (pipeline, self, anti-join) · `$graphLookup` · `$setWindowFields` (rank/running/LAG) · `$facet` · `$bucket` · array expressions · PIVOT · `$out/$merge` · views | ☐ |
| 10 | [Dates, Strings, Conditionals](Level_10_Dates_Strings_Conditionals/README.md) | date parts/format/timezone/add/diff/trunc · string operators & regex · `$cond/$switch/$ifNull` · `$convert` (TRY_CAST) · math | ☐ |
| 11 | [Indexes](Level_11_Indexes/README.md) | single · compound (prefix rule) · unique/partial · multikey · text · hashed · TTL · wildcard · collation · management · write cost (200k-doc benchmark) | ☐ |
| 12 | [Query Performance](Level_12_Query_Performance/README.md) | reading `explain` · ESR rule · covered queries · selectivity · non-indexable predicates · hint · profiler · currentOp/killOp · plan cache · aggregation optimiser | ☐ |
| 13 | [Schema Design & Validation](Level_13_Schema_Design_and_Validation/README.md) | embed vs reference · 1:1/1:N/M:N · patterns (bucket, computed, extended reference, subset, attribute, tree, versioning) · anti-patterns · `$jsonSchema` · time series | ☐ |
| 14 | [Transactions](Level_14_Transactions/README.md) | single-document atomicity · sessions · core & callback API · snapshot isolation · write conflicts & retries · limits · SQL isolation mapping | ☐ |
| 15 | [Users & Security](Level_15_Users_and_Security/README.md) | authentication vs authorization · users/roles/privileges · custom roles · enabling auth (Docker lab) · "not authorized" · injection · checklist | ☐ |
| 16 | [Backup & Restore](Level_16_Backup_and_Restore/README.md) | mongodump/mongorestore (rename, single collection, archive, oplog PIT) · mongoexport/mongoimport (typed CSV, upsert) · strategies, RPO/RTO | ☐ |
| 17 | [Replication & Change Streams](Level_17_Replication_and_Change_Streams/README.md) | replica set, oplog, elections, failover drill (3-node lab) · write/read concern, read preference · `rs.*` · change streams (pipelines, resume tokens, pre-images) | ☐ |
| 18 | [Sharding](Level_18_Sharding/README.md) | shards/config/mongos (Docker lab) · shard key (hashed vs ranged) · targeted vs scatter-gather · chunks, split/move, balancer, zones · rules | ☐ |
| 19 | [Node.js Driver & Mongoose](Level_19_NodeJS_Driver_and_Mongoose/README.md) | MongoClient & pool · CRUD/cursors/aggregation/bulk/errors · transactions & change streams in Node · Mongoose schemas/validation/populate/lean · Express REST API | ☐ |
| 20 | [Docker & Production](Level_20_Docker_and_Production/README.md) | docker run/volumes/env/init scripts/limits · monitoring (serverStatus, mongostat, logs, FCV) · production checklist · capacity, upgrades, Atlas vs self-managed | ☐ |
| ★ | [Interview Prep](Interview_Prep/MongoDB_Interview_Questions.md) | 95 Q&A + [30 query patterns](Interview_Prep/Top_Query_Patterns.js) + [SQL ↔ MongoDB cheat-sheet](Interview_Prep/SQL_to_MongoDB_Cheatsheet.md) | ☐ |

Suggested pace: **one level per day** for 01–08 (they are short), two days each for 09, 11–14, 17–19.

---

## 5. Quick revision before an interview (15 minutes)

### 5.1 The document model in one breath
Model for the **queries**: data read/written together lives together (**embed**: 1:1, 1:few, bounded, owned); shared / unbounded / independently updated data is **referenced** (child holds the parent id, indexed, `$lookup` when needed); copy a few hot fields (**extended reference**) and accept controlled staleness. Never grow an array forever (16 MB, rewrite cost) — bucket / subset / child collection.

### 5.2 The comparison tables interviewers love

| Question | Answer in one line |
|----------|--------------------|
| **SQL vs MongoDB** | tables/rows/joins, fixed schema, vertical scale / documents (nesting, arrays), flexible schema, embed-or-reference, horizontal scale (replica sets + sharding) |
| **Embed vs reference** | read together, bounded, atomic / shared, unbounded, independent, `$lookup` |
| **`null` vs missing** | `{f: null}` matches both · `$exists: false` missing only · `$type: "null"` null only · in expressions missing ≠ null (`$ifNull`) |
| **int vs double vs Decimal128** | whole JS numbers → int, others → double, money → `NumberDecimal` |
| **find vs aggregate** | filter/project/sort one collection / pipeline: group, join, window, reshape, write out |
| **`$match` early vs late** | filter rows (uses indexes) / after `$group` = HAVING |
| **`$lookup` vs embed** | join at read time (index the foreign field) / pre-joined, one read |
| **`$unwind` vs `$size`/`$map`/`$filter`** | one doc per element (for grouping by elements) / per-document array processing |
| **`$rank` / `$denseRank` / `$documentNumber`** | 1,2,2,4 / 1,2,2,3 / 1,2,3,4 (single-field `sortBy`) |
| **`$out` vs `$merge`** | replace whole collection / upsert into existing (incremental, must be last) |
| **updateOne vs replaceOne vs findOneAndUpdate** | operators on first match / whole document swap / update and return (counters, queues) |
| **upsert** | insert from filter equality + update when nothing matches; `$setOnInsert`; unique index for races |
| **`$` vs `$[]` vs `$[id]`** | first matched element / all elements / elements matching arrayFilters |
| **deleteMany({}) vs drop** | logged per document, keeps indexes / instant, drops indexes |
| **bulkWrite ordered vs unordered** | stop at first error / do all, report all — neither is a transaction |
| **countDocuments vs estimatedDocumentCount** | exact, filterable / metadata, instant |
| **skip/limit vs keyset** | simple, O(offset) / `{_id: {$gt: last}}`, O(page) |
| **single vs compound index** | one field / several, prefix rule, ESR order |
| **unique vs partial unique** | missing = null once / uniqueness only where the filter holds |
| **hashed vs ranged (index/shard key)** | equality only, even spread / ranges + sort, hot spots on monotonic keys |
| **COLLSCAN / IXSCAN / FETCH / SORT** | scan all / index range / per-key document read / in-memory sort (100 MB) |
| **covered query** | filter + sort + projection in the index, `_id: 0`, docsExamined 0 |
| **plan cache vs SQL parameter sniffing** | cached per query *shape*, replanned when it degrades |
| **profiler vs slow log** | `system.profile` capped collection per db / `Slow query` log lines above `slowms` |
| **single-document atomicity vs transaction** | always atomic, no session / multi-document, session, snapshot, 60 s, retry on WriteConflict |
| **core API vs withTransaction** | manual commit/abort/retry / callback with automatic retries |
| **write concern / read concern / read preference** | acknowledgement (w:1, majority) / visibility (local, majority, snapshot) / which member (primary, secondary…) |
| **replica set vs sharding** | HA + read scaling / write & data scaling via shard key |
| **primary / secondary / arbiter / hidden / delayed** | writes / copies / vote only / invisible to clients / applies oplog late |
| **election** | heartbeat 2 s, timeout 10 s, majority of votes, priority, term |
| **oplog** | idempotent capped log; window = catch-up time and change-stream resume horizon |
| **change stream vs tailing oplog** | supported, resumable, filtered events / unsupported internals |
| **mongodump vs mongoexport** | BSON + indexes = backup / JSON-CSV = data exchange (CSV loses types) |
| **targeted vs scatter-gather** | shard key in the filter → one shard / all shards, merged by mongos |
| **authentication vs authorization** | who (SCRAM/x.509/LDAP) / what (RBAC: users → roles → privileges) |
| **driver vs Mongoose** | official, fast, shell-like / schemas, validation, middleware, populate, overhead |
| **populate vs `$lookup`** | extra client queries / server-side join |
| **Atlas vs self-managed** | managed HA/backups/monitoring/security / full control, you own operations |

### 5.3 Must-be-able-to-write queries (see `Interview_Prep/Top_Query_Patterns.js`)
1. Nth highest salary (`$denseRank` · distinct+skip · max-below-max)
2. Find & delete duplicates keeping one (`$group` + `$push` ids)
3. Top-N per group (`$sort`+`$first` · `$topN` · `$rank`)
4. Employees earning more than their manager (self `$lookup`)
5. Customers with no orders (`$lookup` + `$match: []` · `$nin` distinct)
6. Count per group including zero (`$lookup` from the parent side)
7. Running total · month-over-month growth (`$setWindowFields`, `$shift`)
8. Gaps (`$shift`) and islands (document-number trick with `$dateSubtract`)
9. PIVOT (`$arrayToObject`) and its `$cond` version · UNPIVOT (`$objectToArray`)
10. String aggregation (`$push` + `$reduce`)
11. Hierarchy (`$graphLookup`)
12. Median (`$median`), odd/even rows, swap values (pipeline update), compare two collections
13. Pagination (skip/limit, keyset, `$facet` with total)

### 5.4 "A query is slow — what do you do?"
`explain("executionStats")` → COLLSCAN? keys/docs examined vs nReturned? in-memory SORT? FETCH with a filter? → predicate selective and indexable? (no `$ne`/`$nin`/`$exists:false`/`$where`/unanchored or `/i` regex/`$expr` on computed fields) →
index with **ESR**, cover if cheap, verify → profiler / `currentOp` / slow log for frequency and lock waits, `maxTimeMS` → plan cache (clear a bad plan) →
aggregation: `$match` first, `$sort`+`$limit`, index the `$lookup` foreign field, `allowDiskUse` → server: working set vs cache, disk, replication lag, connections → schema: embed vs reference, bucket, computed fields.

### 5.5 Traps to mention (shows experience)
- `$ne` / `$nin` / `$not` match **missing** fields; `{ a: 1, a: 2 }` keeps only the last key — use `$and`.
- Conditions on `"items.x"` and `"items.y"` may match **different** elements — `$elemMatch`.
- `{ address: { city: "Delhi" } }` needs the exact sub-document in the same order — dot notation.
- `cursor.map()` is still a cursor; `find().limit().sort()` still sorts first; aggregation stage order is literal.
- `$concat` with a null operand is null; missing ≠ null in expressions; `$size` on a missing array errors (`$ifNull`).
- `$rank`/`$documentNumber` need a single `sortBy` field; `$first`/`$last` need a `$sort`.
- Unique index: a missing field is `null` once → partial unique index. Compound index: one array field max.
- `/^abc/` uses index bounds, `/abc/` and `/^abc/i` scan; `$where` is JavaScript per document (30 s for 200k docs).
- An error inside a transaction aborts it — every later operation fails with `NoSuchTransaction`; use the session-bound collection or the write escapes the transaction.
- `w: 1` writes can be rolled back after failover; arbiters break majority; hostnames in `rs.conf()` must resolve for clients too.
- `mongoimport` CSV turns numbers and dates into strings (`--columnsHaveTypes`); `mongorestore` does not overwrite without `--drop`.
- `_id` is unique per shard only; unique indexes must start with the shard key; queries without the shard key scatter-gather.
- One `MongoClient` per process; never put `req.body` into a filter (operator injection); Mongoose `unique` is an index, `findOneAndUpdate` skips validators unless `runValidators`.

---

## 6. Conventions used in every script

- First line: `use("companyDB");`. Base collections are never permanently changed; data-changing demos use copies made with `$out` (`l05_employees`, …) and are dropped in a final **CLEANUP** block.
- Level-specific objects are prefixed `l<NN>_` (collections), `vw_l<NN>_` (views), `ip_` (interview patterns); Levels 11–12 share a 200k-document `bench_orders` collection that any of their scripts rebuilds on demand (`00_Reset_All.js` removes it).
- Expected results are written as trailing comments (`// 3`, `// Rahul, Sneha`), all verified against the data on MongoDB 8.3 / mongosh 2.8.
- Errors that are meant to happen are caught and printed as `EXPECTED ERROR: …`.
- Projections `{ _id: 0, name: 1 }` in practice files exist to keep output short; they are explained in Level 04.
