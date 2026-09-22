# SQL Server Interview Questions — Crisp Answers

> Read this in 30–40 minutes before an interview. Each answer is what you should *say*; details live in the level READMEs.
> Practice the queries in [Top_Query_Patterns.sql](Top_Query_Patterns.sql) — interviewers will ask you to write at least 3 of them.

---

## A. Basics & DDL (Levels 01–03)

**1. What is the difference between DELETE, TRUNCATE and DROP?**
DELETE removes rows, supports WHERE, fully logged, keeps IDENTITY, fires triggers. TRUNCATE removes all rows, no WHERE, minimally logged (deallocates pages), resets IDENTITY, cannot run if a FK references the table, does not fire DELETE triggers. DROP removes the whole table including structure, indexes, constraints, permissions. All three can be rolled back inside a transaction (yes, TRUNCATE too).

**2. What is GO?**
A batch separator for SSMS / sqlcmd, not T-SQL. Variables do not survive it; `CREATE PROCEDURE / VIEW / SCHEMA` must be first in a batch.

**3. What are the system databases?**
master (config, logins), model (template), msdb (Agent jobs, backup history), tempdb (temp objects, sorts, versions — rebuilt on restart).

**4. Primary key vs Unique key?**
Both enforce uniqueness. PK: one per table, no NULLs, creates a clustered index by default. UNIQUE: many per table, allows one NULL, creates a nonclustered index by default.

**5. What is a foreign key? What do CASCADE options do?**
A column referencing a PK/UNIQUE of another (or the same) table to enforce referential integrity. `ON DELETE/UPDATE CASCADE` propagates, `SET NULL`, `SET DEFAULT`, `NO ACTION` (default, error).

**6. CHAR vs VARCHAR vs NVARCHAR?**
CHAR fixed length padded; VARCHAR variable, 1 byte/char; NVARCHAR Unicode, 2 bytes/char, needs `N'…'` literals. Use NVARCHAR for multi-language text.

**7. DECIMAL vs FLOAT? What for money?**
DECIMAL exact, FLOAT approximate (0.1+0.2 ≠ 0.3). Money/salary → DECIMAL(p,s).

**8. DATETIME vs DATETIME2?**
DATETIME2: wider range, up to 100 ns precision, 6–8 bytes, ANSI. DATETIME: 3.33 ms precision, 8 bytes. Prefer DATETIME2.

**9. What is IDENTITY? SCOPE_IDENTITY vs @@IDENTITY vs IDENT_CURRENT?**
Auto-number column. SCOPE_IDENTITY() = last identity in *your scope* (safe); @@IDENTITY = last identity in your session, any scope (trigger can change it); IDENT_CURRENT('t') = last for the table from any session.

**10. What is a schema?**
A namespace / security container inside a database (`Sales.Orders`). Default is `dbo`.

**11. Implicit vs explicit conversion? Why does it matter?**
Explicit = CAST/CONVERT. Implicit = SQL Server converts automatically by data-type precedence. Implicit conversion on an indexed column in WHERE prevents an index seek.

## B. Querying (Levels 04–10)

**12. Logical order of a SELECT?**
FROM → ON/JOIN → WHERE → GROUP BY → HAVING → SELECT → DISTINCT → ORDER BY → TOP/OFFSET. That is why a SELECT alias cannot be used in WHERE but can in ORDER BY.

**13. WHERE vs HAVING?**
WHERE filters rows before grouping (no aggregates). HAVING filters groups after aggregation.

**14. Types of joins?**
INNER (matching only), LEFT/RIGHT OUTER (all from one side + matches), FULL OUTER (all from both), CROSS (Cartesian, n×m), SELF (table joined with itself, e.g. employee–manager).

**15. Filter in ON vs WHERE for an outer join?**
In ON: applied while matching, unmatched rows stay (with NULLs). In WHERE: applied after, removes rows with NULLs → turns LEFT JOIN into INNER.

**16. UNION vs UNION ALL?**
UNION removes duplicates (sort/hash cost). UNION ALL keeps everything, faster. Use UNION ALL unless you need dedup.

**17. IN vs EXISTS vs JOIN?**
EXISTS stops at first match, NULL-safe, best for "is there any". IN fine for small lists; **NOT IN returns nothing if the subquery has a NULL** → use NOT EXISTS. JOIN returns columns from both sides but can duplicate rows.

**18. How do you find duplicates? Delete them keeping one?**
`GROUP BY cols HAVING COUNT(*) > 1`. Delete: CTE with `ROW_NUMBER() OVER (PARTITION BY cols ORDER BY id)` then `DELETE WHERE rn > 1`.

**19. Nth highest salary?**
`DENSE_RANK() OVER (ORDER BY Salary DESC)` in a subquery/CTE, filter `= N`. Alternatives: `OFFSET N-1 ROWS FETCH NEXT 1` on DISTINCT salaries; `MAX(Salary) WHERE Salary < (SELECT MAX…)` for the 2nd.

**20. ROW_NUMBER vs RANK vs DENSE_RANK?**
ROW_NUMBER: unique 1,2,3 even for ties. RANK: ties share a rank, then a gap (1,2,2,4). DENSE_RANK: ties share, no gap (1,2,2,3).

**21. What is a correlated subquery?**
An inner query that references the outer query's column; conceptually runs once per outer row (e.g. salary > department average).

**22. COUNT(*) vs COUNT(column) vs COUNT(DISTINCT column)?**
All rows / non-NULL values / distinct non-NULL values.

**23. What does NULL = NULL return? How do you test NULL?**
UNKNOWN (treated as false). Use `IS NULL` / `IS NOT NULL` (or `IS DISTINCT FROM` in 2022+).

**24. ISNULL vs COALESCE?**
ISNULL: 2 args, T-SQL only, result type of the first arg. COALESCE: N args, ANSI, result type = highest precedence, evaluated as a CASE.

**25. TOP vs OFFSET/FETCH?**
TOP takes first N (WITH TIES, PERCENT). OFFSET/FETCH skips then takes, for paging, requires ORDER BY.

**26. MERGE?**
One statement that does INSERT / UPDATE / DELETE based on a match between source and target (upsert). Use `WHEN MATCHED / NOT MATCHED BY TARGET / NOT MATCHED BY SOURCE`; be careful with concurrency (use HOLDLOCK).

**27. What is a CTE? CTE vs temp table?**
`WITH name AS (...)` – a named result set for one statement; readable, can be recursive; not materialised (re-evaluated when referenced twice). Temp table is materialised in tempdb, has statistics and indexes, lives for the session – better for large intermediate results reused many times.

**28. Recursive CTE use cases?**
Hierarchies (org chart, BOM, folders), number/date series, path building. Default MAXRECURSION 100.

**29. What are window functions? What does OVER do?**
Functions that compute across a set of rows related to the current row *without collapsing* them. `OVER (PARTITION BY … ORDER BY … ROWS/RANGE …)` defines the window. Ranking (ROW_NUMBER…), offset (LAG/LEAD), aggregate (SUM OVER), distribution (NTILE, PERCENT_RANK).

**30. ROWS vs RANGE in a window frame?**
ROWS counts physical rows; RANGE groups peers with the same ORDER BY value (default frame when ORDER BY is present is RANGE UNBOUNDED PRECEDING → duplicates get the same running total). Use ROWS for running totals.

**31. PIVOT?**
Turns row values into columns with an aggregate: `PIVOT (SUM(x) FOR col IN ([a],[b]))`. Portable alternative: `SUM(CASE WHEN col='a' THEN x END)`. Dynamic column lists need dynamic SQL.

## C. Programmability (Levels 12–15)

**32. Temp table vs table variable?**
`#temp`: tempdb, session scope, statistics, indexes, can ALTER, part of transactions (rolled back). `@table`: batch scope, no statistics (poor estimates), inline constraints only, **not affected by ROLLBACK**, fewer recompiles. Use temp tables for large sets, table variables for small ones.

**33. Local vs global temp table?**
`#t` visible to the creating session (and its nested procs); `##t` visible to all sessions until the creator disconnects and no one references it.

**34. What is a view? Can you update through it?**
A saved SELECT (virtual table). Updatable if it maps to one base table, no aggregates/DISTINCT/GROUP BY. `WITH CHECK OPTION` prevents updates that push rows out of the view.

**35. Indexed view?**
A view materialised by a unique clustered index. Needs SCHEMABINDING, COUNT_BIG, deterministic expressions, no outer joins. Speeds up aggregates on big tables; slows writes.

**36. Stored procedure vs function?**
Proc: can modify data, use transactions, TRY/CATCH, dynamic SQL, return multiple result sets and OUTPUT params, called with EXEC. Function: must return a value/table, no side effects, no TRY/CATCH, usable inside SELECT/WHERE/JOIN. Scalar UDFs are slow row-by-row (inlined in 2019+); prefer inline TVFs.

**37. Why SET NOCOUNT ON in procs?**
Suppresses "n rows affected" messages → less network traffic, avoids confusing client drivers.

**38. EXEC vs sp_executesql?**
sp_executesql accepts parameters → plan reuse and protection from SQL injection. EXEC('string') concatenates values → injection risk, no reuse.

**39. RAISERROR vs THROW?**
THROW (2012+): simpler, re-throws with `THROW;`, always severity 16, ends the batch. RAISERROR: custom severity/state, printf formatting, `WITH LOG`, does not end the batch unless severity ≥ 20.

**40. What is the OUTPUT clause?**
Returns rows affected by INSERT/UPDATE/DELETE/MERGE via `inserted` / `deleted` pseudo tables (e.g. get generated IDs).

**41. CROSS APPLY vs OUTER APPLY?**
Invoke a table expression per row of the left side. CROSS APPLY = inner (drops rows with no result), OUTER APPLY = left (keeps them). Typical use: top-N per group with a TVF or TOP subquery.

## D. Transactions & Concurrency (Level 16)

**42. ACID?**
Atomicity (all or nothing), Consistency (constraints hold), Isolation (concurrent transactions don't interfere), Durability (committed = on disk/log).

**43. Isolation levels and what they prevent?**
READ UNCOMMITTED (dirty reads allowed) → READ COMMITTED (default; no dirty) → REPEATABLE READ (no non-repeatable) → SERIALIZABLE (no phantoms). SNAPSHOT / RCSI use row versioning in tempdb: readers don't block writers.

**44. Dirty / non-repeatable / phantom read?**
Dirty: read uncommitted data. Non-repeatable: same row read twice gives different values. Phantom: same query twice returns new rows.

**45. What is NOLOCK? Is it safe?**
= READ UNCOMMITTED hint. Faster, no blocking, but dirty reads, double/missing rows during page splits. Never for financial data; prefer RCSI.

**46. What is a deadlock? How to avoid?**
Two sessions each hold a lock the other needs; SQL Server kills the cheaper one (error 1205). Avoid: access tables in the same order, keep transactions short, proper indexes, snapshot isolation, retry logic.

**47. Blocking vs deadlock?**
Blocking = waiting for a lock, resolves when the holder commits. Deadlock = circular wait, never resolves → SQL Server chooses a victim.

**48. @@TRANCOUNT? Nested transactions?**
Number of open BEGIN TRANs. Inner COMMIT only decrements; one ROLLBACK undoes everything and sets it to 0. SAVE TRAN gives partial rollback.

**49. SET XACT_ABORT ON?**
Any run-time error aborts and rolls back the whole transaction automatically. Use it in procs with transactions.

**50. Optimistic vs pessimistic concurrency?**
Pessimistic: lock rows (default locking). Optimistic: no locks on read, detect conflicts at write time (row versioning / ROWVERSION column).

## E. Indexes & Performance (Levels 17–19)

**51. Clustered vs nonclustered index?**
Clustered: sorts and stores the actual data rows by the key; one per table (PK by default). Nonclustered: separate B-tree of key + row locator (clustered key or RID); up to 999; can INCLUDE columns.

**52. What is a covering index?**
An index that contains every column a query needs (keys + INCLUDE) so no Key Lookup to the table is required.

**53. Index Seek vs Scan vs Key Lookup?**
Seek: navigates the B-tree to the needed rows (good, selective). Scan: reads the whole index/table (fine for big result sets, bad for selective filters). Key Lookup: after a nonclustered seek, fetch remaining columns from the clustered index per row — expensive when many rows → fix with INCLUDE.

**54. Composite index — does column order matter?**
Yes. The index is sorted by the first column, then second… A filter on only the second column cannot seek (leftmost-prefix rule). Put the most selective / most-filtered-by-equality column first.

**55. Filtered index?**
Nonclustered index with a WHERE (e.g. `WHERE Status = 'Pending'`): smaller, faster, cheaper to maintain for queries that use the same predicate.

**56. What is fragmentation? REBUILD vs REORGANIZE?**
Logical order ≠ physical order / half-empty pages after inserts/updates. REORGANIZE: online, light, < 30 %. REBUILD: recreates the index, updates stats, > 30 %.

**57. What is SARGable?**
Search ARGument-able: a predicate that can use an index seek. Avoid functions/arithmetic on the column, leading `%`, implicit conversions, `ISNULL(col)`, `OR` across columns. Write `OrderDate >= '20240101' AND OrderDate < '20250101'` not `YEAR(OrderDate) = 2024`.

**58. What are statistics?**
Histograms of column value distribution used by the optimizer to estimate row counts. Auto-created/updated; stale stats → bad plans. `UPDATE STATISTICS t WITH FULLSCAN`.

**59. Parameter sniffing?**
The plan for a proc is compiled for the first parameter values and reused; a plan good for a rare value can be terrible for a common one. Fixes: OPTION (RECOMPILE), OPTIMIZE FOR, local variables, Query Store plan forcing.

**60. Estimated vs actual execution plan?**
Estimated: compiled without running (Ctrl+L). Actual: after execution with real row counts and warnings (Ctrl+M). Compare estimated vs actual rows to spot stats problems.

**61. Hash Match vs Nested Loops vs Merge Join?**
Nested Loops: small outer, indexed inner. Merge: both inputs sorted on the join key, large sets. Hash: large unsorted sets, builds a hash table (memory, can spill to tempdb).

**62. A query is slow — what do you do?**
1) Get the actual plan + STATISTICS IO/TIME. 2) Look for scans on big tables, key lookups, high-cost operators, estimated vs actual mismatch, warnings. 3) Check SARGability and implicit conversions. 4) Check/add/fix indexes (missing index DMV, covering). 5) Update statistics. 6) Rewrite (EXISTS, set-based, remove DISTINCT/ORDER BY, avoid scalar UDFs). 7) Check blocking/waits (sys.dm_exec_requests, sys.dm_os_wait_stats). 8) Parameter sniffing.

**63. What DMVs do you use?**
`sys.dm_exec_requests`, `sys.dm_exec_sessions`, `sys.dm_exec_query_stats`, `sys.dm_exec_sql_text`, `sys.dm_exec_query_plan`, `sys.dm_os_wait_stats`, `sys.dm_db_index_usage_stats`, `sys.dm_db_missing_index_details`, `sys.dm_db_index_physical_stats`, `sys.dm_tran_locks`.

## F. Advanced & Admin (Level 20)

**64. Trigger types? Triggers vs constraints?**
AFTER (INSERT/UPDATE/DELETE), INSTEAD OF (views, soft delete), DDL (ON DATABASE/SERVER), Logon. Use `inserted`/`deleted`; always write set-based (multi-row). Prefer constraints for integrity; triggers for audit/cross-table rules.

**65. Cursor — when and why not?**
Row-by-row processing. Slow, locks, memory; almost always replaceable by set-based SQL or a WHILE loop over keys. Use only for per-row admin tasks (e.g. run a proc per database).

**66. Sequence vs IDENTITY?**
SEQUENCE: standalone object, shared across tables, value obtained before insert (`NEXT VALUE FOR`), can cycle/restart. IDENTITY: tied to one column, value only after insert.

**67. JSON in SQL Server?**
`FOR JSON AUTO/PATH` to produce, `OPENJSON` to shred, `JSON_VALUE` (scalar), `JSON_QUERY` (object/array), `JSON_MODIFY`, `ISJSON`. Stored as NVARCHAR(MAX) (native `json` type in 2025).

**68. FOR XML PATH('') trick?**
Pre-2017 string aggregation: `STUFF((SELECT ',' + col FROM t FOR XML PATH('')), 1, 1, '')`. Today use `STRING_AGG`.

**69. Login vs user?**
Login = server-level principal (authentication, in master). User = database-level principal mapped to a login (authorization). Orphaned user = user whose login is missing.

**70. GRANT / DENY / REVOKE?**
GRANT gives permission, DENY explicitly blocks (wins over GRANT, even via roles), REVOKE removes a previous GRANT or DENY.

**71. Recovery models?**
SIMPLE: log truncated automatically, no log backups, no point-in-time restore. FULL: log kept until backed up, point-in-time restore possible. BULK_LOGGED: like FULL but minimal logging for bulk ops.

**72. Backup types & a typical restore?**
Full (everything), Differential (changes since last full), Log (changes since last log backup). Restore: full WITH NORECOVERY → latest diff WITH NORECOVERY → each log in order → last one WITH RECOVERY (or STOPAT for point-in-time).

**73. What is SQL Server Agent?**
The job scheduler service (jobs, steps, schedules, alerts, operators) stored in msdb; used for backups, index maintenance, ETL.

**74. Linked server?**
A registered remote data source queried with four-part names `server.db.schema.table` or `OPENQUERY`. Watch out for performance (remote filtering) and security mappings.

**75. Temporal (system-versioned) tables?**
Tables with SysStart/SysEnd columns and a history table maintained automatically; query the past with `FOR SYSTEM_TIME AS OF`.

---

## Rapid-fire one-liners

- `LEN` ignores trailing spaces, `DATALENGTH` returns bytes.
- `SELECT *` in a view freezes the column list — use `sp_refreshview`.
- `TRUNCATE` cannot be used on a table referenced by a foreign key.
- `sp_` prefix for your procs = SQL Server checks master first → slower; use `usp_`.
- A table can have **one** clustered index and up to **999** nonclustered.
- `NEWID()` random GUID → fragmentation; `NEWSEQUENTIALID()` only as a DEFAULT.
- `@@ROWCOUNT` right after a statement gives rows affected; `@@ERROR` is legacy → use TRY/CATCH.
- `DISTINCT` applies to the whole row, not one column.
- `ORDER BY` in a view/subquery is not allowed unless `TOP`/`OFFSET`, and even then order is not guaranteed outside.
- Window functions are not allowed in `WHERE` — wrap in a CTE.
- `BETWEEN` is inclusive; for dates use `>= start AND < next_day`.
- `COALESCE(a, b)` returns the first non-NULL; `NULLIF(a, b)` returns NULL if `a = b` (divide-by-zero guard).
- Default isolation level: READ COMMITTED. Default lock escalation threshold ≈ 5,000 locks.
- Plan cache: `DBCC FREEPROCCACHE` clears it (never in production casually).
- `OPTION (RECOMPILE)` = fresh plan per run; `WITH RECOMPILE` on the proc = never cached.
- Query Store keeps plan history per query and can force a plan.
