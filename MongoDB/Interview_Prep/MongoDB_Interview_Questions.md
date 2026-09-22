# MongoDB Interview Questions — Crisp Answers

> Read this in 40–50 minutes before an interview. Each answer is what you should *say*; details and runnable proofs live in the level READMEs.
> Practice the queries in [Top_Query_Patterns.js](Top_Query_Patterns.js) — interviewers will ask you to write at least 3 of them — and keep the [SQL → MongoDB cheat-sheet](SQL_to_MongoDB_Cheatsheet.md) in mind when they compare with SQL Server.

---

## A. Basics & Data Model (Levels 01–02)

**1. What is MongoDB? How does it differ from a relational database?**
A document database: data is stored as BSON documents in collections instead of rows in tables. Documents can nest arrays and sub-documents and need not share a schema; relationships are modelled by embedding or references (`$lookup`), not foreign keys and JOINs. It scales horizontally (replica sets for HA, sharding for capacity) and is designed around the application's access patterns.

**2. Database / collection / document / field — map them to SQL.**
Database = database, collection = table, document = row, field = column, `_id` = primary key, index = index, embedded document / array = no direct equivalent (JSON columns at best), `$lookup` = LEFT OUTER JOIN, aggregation pipeline = GROUP BY / window functions / CTE-style processing.

**3. What is BSON and why not JSON?**
Binary JSON: compact, fast to traverse, with extra types JSON lacks (Date, ObjectId, Int32/Int64, Decimal128, Binary, Regex). Documents are stored, indexed and transmitted as BSON.

**4. What is `_id` / ObjectId?**
`_id` is the mandatory, unique, immutable, automatically indexed primary key of every document. Without one the driver creates an ObjectId: 12 bytes = 4-byte timestamp + 5-byte random + 3-byte counter — globally unique without coordination and roughly time-ordered (`getTimestamp()`).

**5. Is MongoDB schemaless?**
The server does not enforce a schema by default (flexible schema); the application (or Mongoose) owns it, and `$jsonSchema` validation can enforce rules server-side. "Schemaless" does not mean "no design".

**6. Maximum document size? What about bigger data?**
16 MB. Redesign (bucket / subset pattern, child collection) or GridFS for files (255 KB chunks).

**7. Which numeric types exist and which do you get from `mongosh` / Node.js?**
int (32-bit), long (64-bit), double, decimal (Decimal128). A whole JS number that fits 32 bits becomes **int**, other numbers **double** (the legacy `mongo` shell stored everything as double). Money → `NumberDecimal`; 64-bit ids → `NumberLong("...")` as a string.

**8. How are dates stored? Time zones?**
As 64-bit milliseconds since the epoch, always UTC; no zone is stored. Convert on output (`$dateToString` with `timezone`) or in the app. Never store dates as strings.

**9. `null` vs missing field?**
Different: `{ f: null }` (query) matches both, `{ f: { $exists: false } }` only missing, `{ f: { $type: "null" } }` only explicit null. In aggregation expressions a missing field is *not* `$eq` to null — use `$ifNull`.

**10. What happens with `insertMany` when one document fails?**
Ordered (default): stops at the first error, earlier documents stay. Unordered: attempts all, reports every error. Not atomic — use a transaction for all-or-nothing.

## B. Querying (Levels 03–07)

**11. How do you write `WHERE a = 1 AND (b = 2 OR c = 3)`?**
`{ a: 1, $or: [ { b: 2 }, { c: 3 } ] }` — top-level fields are ANDed; `$or` takes an array. Use `$and` only when the same field/operator repeats.

**12. `$in` vs `$or`?**
`$in`: one field, list of values, one index scan with several bounds. `$or`: different conditions, each branch may use its own index; if one branch has no index the whole query scans.

**13. What do `$ne`, `$nin`, `$not` do with missing fields?**
They match documents where the field is missing. Add `$exists: true` when needed. They are also non-selective for indexes.

**14. How do you query nested documents and arrays?**
Dot notation: `{ "address.city": "Delhi" }`, `{ "items.productId": 2 }` (any element). Whole sub-document equality is exact and order-sensitive. `$elemMatch` when several conditions must hit the **same** array element; `$all`, `$size`, positional `"skills.0"`.

**15. How is `LIKE` done and does it use an index?**
`$regex`. An anchored, case-sensitive prefix `/^abc/` uses index bounds like `LIKE 'abc%'`; `/abc/` or `/^abc/i` scan the index. Full-text: text index or Atlas Search.

**16. What is `$expr` for?**
Aggregation expressions inside a query — compare two fields of the same document or compute (`{ $expr: { $gt: ["$spent", "$budget"] } }`). Functions on the field prevent index use.

**17. Projection rules?**
Inclusion `{ a: 1 }` or exclusion `{ a: 0 }`, never mixed except `_id: 0`. Array projection: `$slice`, `$elemMatch`, `$`. Computed fields with expressions (4.4+). Projection is not a filter.

**18. How do you paginate? What is wrong with `skip`?**
`sort + skip + limit` for shallow pages (deterministic sort with `_id` tiebreaker); `skip` still reads and discards the skipped documents, so deep pages are slow. Keyset pagination: `{ _id: { $gt: last } }.limit(n)` on an indexed sort key.

**19. `countDocuments` vs `estimatedDocumentCount` vs `count`?**
`countDocuments(filter)` is exact (runs a query); `estimatedDocumentCount()` uses metadata (instant, no filter, may be inexact); `count()` is deprecated.

**20. updateOne vs updateMany vs replaceOne? What does `upsert` do?**
Update the first match / all matches with operators; `replaceOne` swaps the whole document (no operators, `_id` kept). `upsert: true` inserts when nothing matches, building the document from the filter's equality fields + the update; `$setOnInsert` for insert-only fields; needs a unique index to be race-free.

**21. How do you update a field from another field of the same document?**
Pipeline update: `updateMany({}, [ { $set: { total: { $multiply: ["$qty", "$price"] } } } ])` — with `$cond`, `$$NOW`, etc.

**22. Explain `$`, `$[]` and `$[id]`.**
Positional `$` = first array element matched by the query; `$[]` = every element; `$[id]` with `arrayFilters` = the elements matching a condition (nested arrays possible).

**23. `$push` vs `$addToSet`; how do you cap an array?**
`$push` appends (duplicates allowed; `$each`, `$position`, `$slice`, `$sort`); `$addToSet` appends only if absent. Cap: `$push: { events: { $each: [e], $slice: -10 } }`.

**24. What is `findOneAndUpdate` for?**
Atomic update-and-return (before/after) — counters/sequences (`$inc` + `upsert`), job queues (claim a pending item), `findOneAndDelete` to pop.

**25. deleteMany({}) vs drop()?**
`deleteMany` removes documents one by one (oplog entry each, keeps indexes/options, slow at scale). `drop` removes the collection with its indexes instantly (≈ TRUNCATE/DROP). No cascading deletes exist — the application handles children (transaction or embedding).

**26. What is `bulkWrite`?**
Many mixed writes (insert/update/replace/delete) in one round trip; ordered stops at the first error, unordered runs everything and reports all errors. Not a transaction.

**27. What are retryable writes?**
The driver retries a single-document write exactly once after a transient network error/failover, using a transaction id so it is applied at most once. On by default; `updateMany`/`deleteMany` are not retryable.

## C. Aggregation (Levels 08–10)

**28. What is the aggregation pipeline?**
A sequence of stages (`$match`, `$project`/`$set`, `$group`, `$sort`, `$limit`, `$unwind`, `$lookup`, `$facet`, `$setWindowFields`, `$out`/`$merge` …) executed server-side in order; MongoDB's reporting and transformation engine, equivalent to GROUP BY / joins / window functions / CTEs.

**29. Where should `$match` go and why? What is `HAVING`?**
As early as possible so it uses indexes and shrinks the data. A `$match` after `$group` is `HAVING`. The optimiser also moves `$match`/`$sort` before `$project` when possible.

**30. How do you do COUNT(DISTINCT), conditional counts, top-N per group?**
`$group` by the field then `$count` (or `$addToSet` + `$size`); `$sum: { $cond: [...] }`; `$sort` + `$group` with `$first`/`$firstN`/`$topN`, or `$setWindowFields` with `$rank`.

**31. `$first`/`$last`, `$push`, `$$ROOT`?**
`$first`/`$last` take the first/last document in pipeline order (need a `$sort` before). `$push` collects values (or `$$ROOT` for whole documents). `$group` drops every field not in `_id` or an accumulator.

**32. Explain `$lookup`. LEFT JOIN, INNER JOIN, anti-join?**
`$lookup` joins another collection (equality on local/foreign fields or a correlated pipeline with `let`), producing an array (LEFT JOIN). `$unwind` without `preserveNullAndEmptyArrays` = INNER JOIN; `$match: { arr: [] }` = anti-join. Index the foreign field.

**33. What does `$unwind` do?**
One output document per array element (missing/empty arrays drop the document unless `preserveNullAndEmptyArrays`). Needed before grouping by array elements.

**34. RANK / DENSE_RANK / ROW_NUMBER / running totals / LAG?**
`$setWindowFields` with `$rank`, `$denseRank`, `$documentNumber`, `$sum` over `documents: ["unbounded", "current"]`, `$shift`. Rank operators need a single-field `sortBy`.

**35. `$facet`, `$bucket`, `$graphLookup`?**
`$facet`: several sub-pipelines on the same input in one pass (paginated results + total count). `$bucket`/`$bucketAuto`: histograms. `$graphLookup`: recursive traversal (org charts, categories) = recursive CTE.

**36. `$out` vs `$merge`; what is a view?**
`$out` replaces a collection; `$merge` upserts/merges into an existing one (incremental materialised views, must be last). A view is a saved read-only pipeline evaluated on every read.

**37. Memory limits in aggregation?**
100 MB per blocking stage (`$group`, `$sort`, `$facet`…); `allowDiskUse: true` spills to disk; prefer indexes for `$sort` and early `$match`.

**38. `CASE WHEN` / `COALESCE` / `TRY_CAST` equivalents?**
`$cond` / `$switch`; `$ifNull` (multi-arg); `$convert` with `onError`/`onNull` (`$toInt` etc. throw on bad input).

**39. How do you group by month with time zones?**
`$group: { _id: { $dateTrunc: { date: "$d", unit: "month", timezone: "Asia/Kolkata" } } }` (or `$year`/`$month` with `timezone`). `$dateDiff` counts boundaries crossed; `$dateToString` formats.

**40. Why does `$concat` return null?**
Any null/missing operand nulls the result — wrap optional fields in `$ifNull`.

## D. Indexes & Performance (Levels 11–12)

**41. What index types exist?**
Single field, compound, multikey (arrays), unique, partial, sparse, TTL, text, hashed, wildcard, geospatial; every collection has the `_id` index; clustered collections store data in `_id` order.

**42. Prefix rule / sort direction in compound indexes?**
`{ a, b, c }` serves `a`, `a+b`, `a+b+c` — never `b` alone. Sort directions must match the index (or its exact inverse).

**43. What is the ESR rule?**
Compound index field order: Equality fields, then Sort fields, then Range fields → tight bounds and an index-delivered sort with no in-memory `SORT`.

**44. What is a covered query?**
All filter, sort and projected fields are in one index (`_id` excluded or indexed); no `FETCH`, `totalDocsExamined: 0` (`PROJECTION_COVERED`). Multikey indexes cannot cover.

**45. How do you read `explain`?**
Stages from the inside out (`COLLSCAN`/`IXSCAN` → `FETCH` → `SORT` → `PROJECTION` → `LIMIT`); compare `nReturned` with `totalKeysExamined` and `totalDocsExamined` (ideal ≈ 1:1:1); look for in-memory `SORT`, `FETCH` with a filter, `SHARD_MERGE`. Verbosities: queryPlanner, executionStats, allPlansExecution.

**46. Unique index and missing fields?**
A missing field counts as `null` once — a second document without the field fails. Partial unique index on `{ f: { $type: "string" } }` fixes it.

**47. Multikey index limitations?**
One key per array element; a compound index may contain only one array field per document; cannot cover queries; no hashed shard keys on arrays.

**48. TTL index?**
`expireAfterSeconds` on a Date field; a background thread deletes expired documents every 60 s. Sessions, logs, tokens.

**49. Which predicates cannot use an index well?**
`$ne`, `$nin`, `$not`, `$exists: false`, unanchored or case-insensitive regex, `$where`, `$expr` on computed values, `$mod`, `$size`, and low-selectivity values (90 % of the collection) — even with an index, a scan may be cheaper.

**50. A query is slow — what do you do?**
1) `explain("executionStats")`: COLLSCAN, keys/docs vs returned, SORT, FETCH filter. 2) Is the predicate selective/indexable? 3) Design the index with ESR, cover if cheap, verify. 4) Profiler / `currentOp` / logs: frequency, locks, long runners; `maxTimeMS`. 5) Plan cache (clear a bad plan). 6) Aggregation: `$match` first, `$sort`+`$limit`, index the `$lookup` foreign field. 7) Server: working set vs cache, disk, replication lag, connections. 8) Schema: embed vs reference, bucket, computed fields.

**51. How does MongoDB choose a plan? What is the plan cache?**
Candidate plans race for a short trial; the winner is cached per query shape (filter shape + sort + projection + collation), reused for other values, re-planned if it degrades or indexes change. Shape-based caching is MongoDB's "parameter sniffing".

**52. How do you find slow queries and unused indexes?**
Profiler (`setProfilingLevel(1, { slowms })` → `system.profile`), slow-query log lines, `currentOp`, Atlas Performance Advisor; `$indexStats` for usage; `hideIndex` before dropping.

**53. What is the working set and WiredTiger cache?**
Working set = hot documents + indexes; it must fit in the WiredTiger cache (≈ 50 % RAM − 1 GB) or reads hit disk. Watch cache usage, "bytes read into cache", evictions by application threads.

## E. Schema Design & Validation (Level 13)

**54. Embed or reference — how do you decide?**
Read/written together, bounded, owned by the parent → embed (one read, atomic). Shared, unbounded, independently updated/queried, large → reference (+ index) and `$lookup` or extended references (copy a few hot fields, accept controlled staleness).

**55. Model one-to-many / many-to-many.**
1:few → embed an array; 1:many → child holds parent id (indexed); 1:squillions → same, never an array on the parent; M:N → arrays of ids on the queried side(s), or a link collection when the relation has attributes.

**56. Name the design patterns you know.**
Attribute, bucket, computed, extended reference, subset, outlier, polymorphic, schema versioning, tree (parent ref / ancestors array / materialised path), approximation, pre-allocation; time series collections implement bucketing natively.

**57. Anti-patterns?**
Unbounded arrays, "one collection per SQL table + `$lookup` everywhere", bloated documents, massive numbers of collections, unnecessary indexes, case-insensitive queries without a collation index, separating data read together.

**58. How does schema validation work?**
`validator` (`$jsonSchema` and/or query operators) on the collection; `validationLevel` strict/moderate (moderate skips already-invalid documents on update), `validationAction` error/warn; `collMod` to change; `bypassDocumentValidation` for privileged loads; `$jsonSchema` also works as a query to find violators.

**59. How do you evolve a schema without downtime?**
Schema versioning: add `schemaVersion`, write new documents in the new shape, read both, migrate lazily or in a background job.

## F. Transactions (Level 14)

**60. Does MongoDB have ACID transactions?**
Single-document writes have always been atomic; multi-document transactions since 4.0 (replica sets) / 4.2 (sharded) with snapshot isolation and majority write concern on commit.

**61. When do you need them / not need them?**
Need: atomic changes across documents/collections that cannot be one document (transfers, order + stock, both sides of M:N). Not: single-document changes (embed!), counters (`$inc`), idempotent retries.

**62. Core API vs `withTransaction`?**
Core: `startTransaction / commit / abort`, you write retries. `withTransaction`: runs the callback, commits, retries `TransientTransactionError` and `UnknownTransactionCommitResult` — callback must be idempotent, every operation must use the session.

**63. What is a write conflict?**
Two transactions (or a transaction and a plain write) modify the same document: the second transaction aborts immediately with `WriteConflict` (transient → retry); a plain write waits for the transaction to finish.

**64. Limits?**
60-second lifetime, 5 ms lock wait, primary reads only, no DDL/`$out`/`$merge`/`count`, one open transaction per session, an error aborts the transaction (start a new one).

**65. Compare with SQL Server isolation.**
Transactions ≈ SNAPSHOT isolation (no dirty/non-repeatable/phantom reads); no deadlocks between transactions (conflict → abort → retry); no savepoints; plain operations ≈ autocommit with READ COMMITTED-like behaviour on single documents.

## G. Security (Level 15)

**66. Authentication vs authorization; how do users and roles work?**
Authentication (SCRAM, x.509, LDAP/Kerberos) proves identity; authorization is RBAC: users (created in an authentication database, stored in `admin.system.users`) hold roles; roles bundle privileges (resource + actions). Built-in roles: read, readWrite, dbAdmin, userAdmin, dbOwner, *AnyDatabase, cluster*, backup/restore, root.

**67. How do you enable access control?**
Create an admin user via the localhost exception, set `security.authorization: enabled` (+ keyFile / x.509 for replica-set members), restart, create least-privilege app users; connect with `authSource`.

**68. Can MongoDB be injected?**
Operator injection when user JSON is used as a query (`{ "$ne": "" }`) and JS injection via `$where`. Validate/cast input, strip `$` keys, avoid server-side JS.

**69. What is the production security checklist?**
Auth + least privilege, TLS, private network/firewall, encryption at rest, auditing, secrets management, patching, backups, no `$where`, client-side field level / queryable encryption for sensitive fields.

## H. Backup & Restore (Level 16)

**70. How do you back up MongoDB?**
`mongodump` (BSON + indexes, `--oplog` for point-in-time on a replica set, `--gzip`, `--archive`) for small/medium data; filesystem/volume snapshots of a consistent `dbPath` for big data; Atlas/Ops Manager continuous backups with PIT restore. Test restores regularly.

**71. `mongodump` vs `mongoexport`?**
`mongodump` = full-fidelity BSON backup with index metadata. `mongoexport` = JSON/CSV data exchange; CSV loses types, no indexes — not a backup.

**72. How do you restore one collection / rename a database / point in time?**
`mongorestore --db X --collection Y --drop file.bson`; `--nsFrom/--nsTo`; dump with `--oplog`, restore with `--oplogReplay`.

**73. RPO / RTO?**
Acceptable data loss (frequency, oplog-based continuous backup) and acceptable downtime (snapshot restores are fast, dump restores rebuild indexes; rehearse).

## I. Replication (Level 17)

**74. How does replication work?**
A replica set: one primary takes writes and logs them idempotently in the oplog; secondaries tail and apply it; heartbeats every 2 s; on primary loss a majority elects a new primary (electionTimeout 10 s, priority, term); drivers reconnect automatically.

**75. Write concern / read concern / read preference?**
Write concern = acknowledgement level (w:1, majority, n, j). Read concern = visibility guarantee (local, majority, linearizable, snapshot). Read preference = which member serves reads (primary, secondaryPreferred, nearest, tags, maxStaleness). Secondary reads can be stale.

**76. Can data be lost in a failover?**
`w:1` writes not yet replicated when the primary fails are rolled back when it rejoins; `w: "majority"` prevents that.

**77. Why odd members? Arbiter?**
Majority voting: 3 and 4 both tolerate one failure. An arbiter votes without data — saves cost but weakens majority writes/reads when a data node is down (avoid PSA).

**78. What is the oplog window? Replication lag?**
Oplog size determines how long a member can be down and catch up without initial sync (and how far change streams can resume). Lag = delay applying the oplog; monitor with `rs.printSecondaryReplicationInfo()`; flow control throttles the primary.

**79. What are change streams?**
A resumable, filtered event API over the oplog (`watch()` on collection/db/deployment; insert/update/replace/delete/DDL events; `fullDocument`, pre-images; resume tokens; `invalidate` on drop). For cache invalidation, search sync, notifications, event sourcing, Kafka connector.

**80. Rolling maintenance / upgrade?**
Upgrade secondaries one by one, `rs.stepDown()` the primary, upgrade it; raise `featureCompatibilityVersion` afterwards.

## J. Sharding (Level 18)

**81. What is sharding and when do you need it?**
Partitioning a collection across replica sets by a shard key, routed by `mongos`, metadata on config servers. Needed when data, working set or write throughput exceed one replica set, or for locality. Replica sets = HA, sharding = scale.

**82. What makes a good shard key?**
High cardinality, even frequency, non-monotonic (or hashed), used by most queries (targeting), keeps related documents together; compound keys often best.

**83. Hashed vs ranged?**
Hashed: even writes for monotonic keys, equality targeted, ranges broadcast, no zones by value. Ranged: range queries targeted, zones, but hot shards for monotonic keys and jumbo chunks for skewed values.

**84. Chunks and the balancer?**
Chunks = key ranges (≤ 128 MB) on shards; the balancer (config server primary) migrates ranges to even data size; can be windowed/stopped; pre-split before bulk loads.

**85. Targeted vs scatter-gather?**
With the shard key in the filter `mongos` routes to one/few shards (`SINGLE_SHARD`); otherwise all shards (`SHARD_MERGE`) — works but does not scale.

**86. Unique indexes, `_id`, transactions, changing the key?**
Unique indexes must be prefixed by the shard key; `_id` is unique per shard only; cross-shard transactions use two-phase commit (keep related data on one shard); `reshardCollection` (5.0+) changes the key online.

## K. Application Development (Level 19)

**87. How do you manage connections from Node.js?**
One `MongoClient` per process (pool, `maxPoolSize`), created at startup, reused, closed on shutdown; never per request. `appName` in the URI for observability.

**88. Driver vs Mongoose?**
Driver: official, fast, shell-like, no schema. Mongoose: schemas/validation/middleware/virtuals/populate at the cost of overhead and its own semantics (`lean()`, `runValidators`, `unique` is an index). Choose by team and use case.

**89. `populate` vs `$lookup`; what is `lean()`?**
`populate` runs extra queries client-side and stitches documents; `$lookup` joins server-side in one aggregation with filtering. `lean()` returns plain objects (much faster) without document features.

**90. How do you handle errors and ObjectIds in an API?**
Validate ids (`ObjectId.isValid`), cast inputs, whitelist fields; map 11000 → 409, validation/cast → 400, no document → 404, transient → retry/503, else 500; serialise ObjectId/Decimal128/Date consciously.

## L. Operations (Level 20)

**91. How do you monitor MongoDB and what do you alert on?**
`serverStatus` (connections, opcounters, queues, cache), `mongostat`/`mongotop`, profiler/slow logs, `rs.status`, `sh.status`; Atlas/Ops Manager/Prometheus exporter + Grafana. Alerts: replication lag, connections near limit, queued ops, cache eviction/page faults, disk %, elections, slow query rate.

**92. Docker for MongoDB — dev vs prod?**
Dev: official image, named volume, root user via env (enables auth), init scripts, compose for labs. Prod: pinned versions, replica set across hosts, explicit cache size below the memory limit, no public ports, TLS/auth, backups, monitoring — typically Kubernetes operator or Atlas.

**93. What is `featureCompatibilityVersion`?**
A switch that keeps new on-disk features off after a binary upgrade so you can still downgrade; raise it once stable to enable the new version's features.

**94. How much RAM / how many connections?**
Working set (hot data + indexes) must fit the cache (≈ 50 % RAM − 1 GB); each connection ≈ 1 MB server RAM → size pools (`maxPoolSize` × instances) and use `maxIdleTimeMS`.

**95. Atlas or self-managed?**
Atlas: managed HA, backups with PIT, scaling, monitoring, security defaults, Search/Vector; less control, per-cluster cost. Self-managed: full control, potentially cheaper at scale, but you own security, backups, upgrades, on-call.

---

## Rapid-fire one-liners

- Field names and collection names are **case-sensitive**; a typo in a collection name returns nothing, not an error.
- `find()` returns a **cursor**; `cursor.map()` is still a cursor — `toArray()` for a real array.
- `sort → skip → limit` is applied in that order in `find` regardless of call order; in aggregation stage order matters.
- Whole-number JS values are stored as **int**, fractions/big values as **double**; the old `mongo` shell used double for everything.
- `"$field"` reads the field in expressions; `"field"` is a literal string.
- `$group` with `_id: null` = grand total; `$sum: 1` = COUNT(*); `$avg` ignores missing values.
- `$lookup` returns an **array** — `$unwind` or `$first` it; index the foreign field.
- Rank window operators need a **single** `sortBy` field.
- Text index: **one per collection**, `$text` at top level; regex `/^abc/` uses index bounds, `/abc/` and `/i` do not.
- Unique index counts a missing field as **null once**; partial unique index fixes it.
- Compound index: **one** array field maximum; multikey indexes cannot cover.
- `$where` = JavaScript per document: never in production (200k documents took 30 s vs 25 ms).
- Sorting without an index: **100 MB** limit → error or `allowDiskUse`.
- Transactions: **60 s** lifetime, `WriteConflict` = retry, errors abort the transaction, every op needs the session.
- `w: "majority"` prevents rollback on failover; secondary reads may be stale.
- Elections take ~10–12 s by default; odd number of voters; avoid arbiters.
- Oplog is **idempotent** (`$inc 5` is stored as `set qty to 6`); change streams ride on it and resume with tokens.
- `mongodump` = backup (BSON + indexes), `mongoexport` = data exchange (CSV loses types).
- Shard key = the most important decision; queries without it scatter-gather; `_id` unique per shard only.
- `docker` image: `MONGO_INITDB_*` and init scripts run **once** on an empty volume; a temporary `mongod` runs the init scripts first.
- One `MongoClient` per process; `appName` in the URI; never put `req.body` into a filter.
