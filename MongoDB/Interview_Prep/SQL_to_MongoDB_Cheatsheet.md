# SQL Server → MongoDB Cheat-sheet

> You already know T-SQL. This is the translation table interviewers love ("how would you do X in MongoDB?").
> Both sides run on the same data: `SQLPractice` (MS SQL Server course) ↔ `companyDB` (this course).

## 1. Vocabulary

| SQL Server | MongoDB |
|-----------|---------|
| instance | `mongod` / replica set / sharded cluster |
| database | database |
| schema (`dbo`) | *(none — one namespace per database)* |
| table | collection |
| row | document |
| column | field (may be nested or an array) |
| primary key | `_id` |
| foreign key + JOIN | embed, or reference + `$lookup` |
| index | index (B-tree; types in Level 11) |
| view | view (`db.createView`) |
| stored procedure / function / trigger | *(none — application code; change streams for reactions)* |
| identity / sequence | ObjectId (default) or a counter document with `findOneAndUpdate` |
| `NULL` | `null` **or** missing field (different!) |
| `GO` / batch | *(none — JavaScript in mongosh)* |
| SSMS / sqlcmd | Compass / mongosh |
| Availability Group | replica set |
| partitioning / federation | sharding |
| CDC / triggers | change streams |
| `BACKUP DATABASE` | `mongodump` / snapshots / Atlas backups |
| login / user / role | user (in an auth database) / role (RBAC) |

## 2. DDL

| SQL Server | MongoDB |
|-----------|---------|
| `CREATE DATABASE db` | `use("db")` + first insert (lazy) |
| `CREATE TABLE t (...)` | `db.createCollection("t")` or first insert; optional `validator` |
| `ALTER TABLE t ADD col` | nothing — just set the field: `updateMany({}, { $set: { col: null } })` if you want it everywhere |
| `ALTER TABLE t DROP COLUMN col` | `updateMany({}, { $unset: { col: "" } })` |
| `sp_rename 'col'` | `updateMany({}, { $rename: { col: "new" } })` |
| `DROP TABLE t` | `db.t.drop()` |
| `TRUNCATE TABLE t` | `db.t.drop()` (+ recreate indexes) or `deleteMany({})` |
| `CREATE UNIQUE INDEX` | `createIndex({ f: 1 }, { unique: true })` (partial for "unique except missing") |
| `CHECK (Salary > 0)` | `$jsonSchema` validator `minimum: 1` |
| `DEFAULT GETDATE()` | application / Mongoose default / `$setOnInsert` |
| `CREATE VIEW v AS SELECT …` | `db.createView("v", "t", [pipeline])` |

## 3. Queries (`find`)

| SQL Server | MongoDB |
|-----------|---------|
| `SELECT * FROM e` | `db.e.find()` |
| `SELECT name, salary FROM e` | `db.e.find({}, { _id: 0, name: 1, salary: 1 })` |
| `WHERE salary > 70000` | `{ salary: { $gt: 70000 } }` |
| `WHERE a = 1 AND b = 2` | `{ a: 1, b: 2 }` |
| `WHERE a = 1 OR b = 2` | `{ $or: [ { a: 1 }, { b: 2 } ] }` |
| `WHERE x IN (1,2)` / `NOT IN` | `{ x: { $in: [1, 2] } }` / `{ x: { $nin: [1, 2] } }` |
| `WHERE x BETWEEN 1 AND 5` | `{ x: { $gte: 1, $lte: 5 } }` |
| `WHERE name LIKE 'Ra%'` | `{ name: /^Ra/ }` |
| `WHERE x IS NULL` / `IS NOT NULL` | `{ x: null }` (null or missing) / `{ x: { $ne: null } }` |
| `WHERE col1 > col2` | `{ $expr: { $gt: ["$col1", "$col2"] } }` |
| `WHERE YEAR(d) = 2025` | `{ d: { $gte: ISODate("2025-01-01"), $lt: ISODate("2026-01-01") } }` (SARGable both ways) |
| `ORDER BY a, b DESC` | `.sort({ a: 1, b: -1 })` |
| `SELECT TOP 5` | `.limit(5)` |
| `OFFSET 10 ROWS FETCH NEXT 5` | `.skip(10).limit(5)` (or keyset `{ _id: { $gt: last } }`) |
| `SELECT DISTINCT city` | `db.e.distinct("city")` / `$group` |
| `SELECT COUNT(*) WHERE …` | `db.e.countDocuments({ … })` |
| `JSON_VALUE(doc, '$.address.city')` | `{ "address.city": "Delhi" }` — native |
| `EXISTS (SELECT 1 …)` | `$lookup` + `$match: { arr: { $ne: [] } }`, or `$lookup` pipeline with `$limit: 1` |
| `COLLATE Latin1_General_CI_AS` | `.collation({ locale: "en", strength: 2 })` |

## 4. DML

| SQL Server | MongoDB |
|-----------|---------|
| `INSERT INTO t VALUES (…)` | `insertOne({ … })` / `insertMany([...])` |
| `INSERT … SELECT` | `aggregate([..., { $out: "t2" }])` / `$merge` |
| `UPDATE t SET a = 1 WHERE …` | `updateMany({ … }, { $set: { a: 1 } })` |
| `UPDATE t SET a = a + 1` | `{ $inc: { a: 1 } }` |
| `UPDATE t SET a = b * 2` | pipeline update `[ { $set: { a: { $multiply: ["$b", 2] } } } ]` |
| `UPDATE … FROM other` | aggregate `other` + `$merge` into `t` |
| `MERGE` (upsert) | `updateOne(filter, update, { upsert: true })` / `bulkWrite` with upserts / `$merge` |
| `DELETE FROM t WHERE …` | `deleteMany({ … })` |
| `OUTPUT inserted.*` | `findOneAndUpdate(..., { returnDocument: "after" })` / `insertedId` |
| `SCOPE_IDENTITY()` | `insertedId` from the result / ObjectId generated client-side |

## 5. Aggregation (GROUP BY and friends)

| SQL Server | MongoDB pipeline |
|-----------|------------------|
| `WHERE` | `{ $match }` (first) |
| `GROUP BY dept` | `{ $group: { _id: "$dept" } }` |
| `COUNT(*)`, `SUM`, `AVG`, `MIN`, `MAX` | `$sum: 1`, `$sum`, `$avg`, `$min`, `$max` |
| `COUNT(DISTINCT x)` | `$group` by x then `$count` / `$addToSet` + `$size` |
| `HAVING` | `{ $match }` after `$group` |
| `SELECT a, b*2 AS c` | `$project` / `$set` |
| `ORDER BY` / `TOP` / `OFFSET` | `$sort` / `$limit` / `$skip` (order of stages matters) |
| `CASE WHEN` | `$cond` / `$switch` |
| `ISNULL` / `COALESCE` | `$ifNull` |
| `CAST` / `TRY_CAST` | `$toInt`… / `$convert` with `onError` |
| `STRING_AGG` | `$push` + `$reduce` `$concat` |
| `PIVOT` | `$group` + `$push {k,v}` + `$arrayToObject`, or conditional `$sum` |
| `UNPIVOT` | `$objectToArray` + `$unwind` |
| `INNER JOIN` | `$lookup` + `$unwind` |
| `LEFT JOIN` | `$lookup` (+ `$unwind` with `preserveNullAndEmptyArrays`) |
| `LEFT JOIN … WHERE b.id IS NULL` (anti-join) | `$lookup` + `$match: { arr: [] }` |
| `JOIN … ON complex condition` / `CROSS APPLY` | `$lookup` with `let` + `pipeline` |
| `CROSS APPLY OPENJSON(items)` | `$unwind: "$items"` |
| `UNION ALL` | `$unionWith` |
| `EXCEPT` / compare tables | `$lookup` both ways + `$match` |
| recursive CTE | `$graphLookup` |
| `ROW_NUMBER / RANK / DENSE_RANK / NTILE` | `$setWindowFields` `$documentNumber / $rank / $denseRank` (+ math) |
| `SUM() OVER (ORDER BY … ROWS UNBOUNDED PRECEDING)` | `$setWindowFields` `$sum` with `documents: ["unbounded", "current"]` |
| `LAG / LEAD` | `$shift` |
| `PERCENTILE_CONT` | `$percentile` / `$median` (7.0+) |
| `GROUPING SETS` / several reports | `$facet` |
| `DATETRUNC(month, d)` / `DATEADD` / `DATEDIFF` / `FORMAT` | `$dateTrunc` / `$dateAdd` / `$dateDiff` / `$dateToString` |
| `SELECT INTO` / materialised view | `$out` / `$merge` |
| temp table / CTE | none needed — stages are the pipeline; `$out` to a temp collection if reused |

## 6. Transactions & concurrency

| SQL Server | MongoDB |
|-----------|---------|
| `BEGIN TRAN … COMMIT` | `session.startTransaction()` … `commitTransaction()` / `withTransaction()` |
| single statement autocommit | every single-document write is atomic on its own |
| READ COMMITTED / SNAPSHOT | outside transactions: latest/majority read concern; in transactions: snapshot isolation |
| deadlock (1205) + retry | `WriteConflict` (`TransientTransactionError`) + retry — no deadlocks |
| `NOLOCK` | `readConcern: "local"` / secondary reads (stale, never dirty) |
| lock escalation / long transactions | 60 s lifetime; keep transactions tiny |
| `ROWVERSION` optimistic concurrency | version field + conditional `updateOne({ _id, version })` |

## 7. Indexes & tuning

| SQL Server | MongoDB |
|-----------|---------|
| clustered index | clustered collection (5.3+) — otherwise `_id` index + separate storage |
| nonclustered index | index (single / compound) |
| `INCLUDE` columns / covering | covered query = every needed field in the index (`_id: 0`) |
| filtered index | partial index |
| full-text index | text index / Atlas Search |
| computed-column index | index on a stored field (pre-compute) |
| execution plan (Ctrl+M) | `explain("executionStats")` |
| Index Seek / Scan / Key Lookup | `IXSCAN` / `COLLSCAN` / `FETCH` |
| `SET STATISTICS IO` | `totalKeysExamined` / `totalDocsExamined` |
| missing index DMV | `$indexStats` (usage), Atlas Performance Advisor |
| statistics | none — plans are chosen by trial ("works"), cached per shape |
| parameter sniffing | plan cache per query shape (+ replanning) |
| SARGability | same idea: no functions on the field, anchored regex, ESR field order |
| `OPTION (RECOMPILE)` / plan guide | `planCacheClear()` / `hint()` |
| Query Store / Profiler | database profiler (`system.profile`), slow query log |

## 8. Operations

| SQL Server | MongoDB |
|-----------|---------|
| full / differential / log backup | `mongodump` (+ `--oplog`), snapshots, Atlas continuous backup |
| `RESTORE … STOPAT` | `mongorestore --oplogReplay` / Atlas point-in-time |
| Always On AG, listener | replica set, driver auto-discovery (`?replicaSet=`) |
| readable secondary | `readPreference: secondaryPreferred` |
| synchronous commit | `w: "majority"` |
| log shipping with delay | delayed member |
| SQL Agent job | cron / Atlas triggers / application scheduler |
| `sys.dm_exec_requests` / `sp_who2` | `db.currentOp()` / `$currentOp` |
| `KILL <spid>` | `db.killOp(opid)` |
| DMVs / perf counters | `db.serverStatus()`, `mongostat`, `mongotop` |
| logins / users / roles / GRANT | users in auth db / roles / `createRole` privileges |
| TDE | encryption at rest (Enterprise / Atlas) |

## 9. Things that do **not** translate

- **No JOIN planner**: `$lookup` is a nested loop using the foreign index; design to avoid it (embed).
- **No stored procedures / triggers**: logic lives in the application; use change streams or Atlas Triggers for reactions.
- **No schema by default**: types and required fields are your responsibility (`$jsonSchema` / Mongoose).
- **`NULL` vs missing** are different things; three-valued logic mostly does not apply (`$nin` with null is fine).
- **Integer division does not exist** (`$divide` returns a double); numeric types are chosen by the driver.
- **Order of keys in an embedded document matters** for equality; field names are case-sensitive.
- **Uniqueness across shards** only via the shard key; `_id` is unique per shard.
- **No savepoints, no long transactions**: single-document atomicity is the primary tool.
