# Level 19 — Performance Tuning

**Goal:** write predicates the index can use (SARGable), keep statistics fresh, recognise and fix parameter sniffing, and know the DMV queries that answer "why is the server slow?" (waits, blocking, expensive queries, index health).

**Time:** ~3 hrs · **Files:** `01_Practice_SARGability_Statistics.sql` → `02_Practice_Parameter_Sniffing_Waits.sql` → `Exercises.sql`

> The practice files build a 200,000-row `dbo.L19_Orders` where **CustomerID 1 owns 40 % of the rows** (the "whale") – skew is what makes parameter sniffing visible. Every claim is measured with `SET STATISTICS IO ON` (logical reads).

---

## 1. Concepts in plain words

| Term | Meaning |
|------|---------|
| **SARGable** | *Search ARGument able*: the column stands alone on one side of the comparison, so the B-tree can be **seeked**. `WHERE OrderDate >= '20240101'` is SARGable; `WHERE YEAR(OrderDate) = 2024` is not (every row must be evaluated → scan). |
| **Logical reads** | 8 KB pages read from the buffer pool. The single best number to compare two versions of a query. |
| **Statistics** | Per index/column: a **histogram** (≤ 200 steps of value ranges with row counts) + **density** (1 / distinct values). The optimizer estimates row counts from them. |
| **Stale statistics** | Data changed but the histogram was not rebuilt. Auto-update fires only after `SQRT(1000 × rows)` changes (2016+; old rule 20 % + 500) – new values are invisible until then. |
| **Parameter sniffing** | On first compile the optimizer looks at the actual parameter value and builds the best plan for *that* value. The plan is cached and reused for all later values – great when values are alike, terrible when one value is a whale. |
| **Wait statistics** | Cumulative time the server spent waiting, by reason (`sys.dm_os_wait_stats`). Tells you *what* is slow: disk, locks, CPU, memory, network. |
| **Blocking** | Session A holds a lock that session B needs; B waits (`LCK_M_*`). Found with `sys.dm_exec_requests.blocking_session_id`. |
| **Missing / unused index** | The optimizer records indexes it wished it had (`sys.dm_db_missing_index_*`); usage stats show indexes nobody reads (`sys.dm_db_index_usage_stats`). |
| **Memory grant** | Workspace memory reserved for sorts/hashes from the *estimated* rows. Too small → spill to tempdb; too many → `RESOURCE_SEMAPHORE` waits. |

### SARGability rules (measured in file 01)

| Anti-pattern | Reads | SARGable rewrite | Reads |
|--------------|-------|------------------|-------|
| `YEAR(OrderDate) = 2024` | 624 | `OrderDate >= '20240101' AND OrderDate < '20250101'` | 211 |
| `Amount * 1.1 > 109000` | 474 | `Amount > 109000 / 1.1` | 8 |
| `RefNo LIKE '%999'` | 485 | `RefNo LIKE '1999%'` (only a trailing wildcard can seek) | 4 |
| `Status = N'Pending'` (VARCHAR column) | 568 | `Status = 'Pending'` (match the column type) | 56 |
| `RefNo = 12345` (VARCHAR column) | 959 | `RefNo = '12345'` | 6 |
| `ISNULL(EmployeeID, 0) = 105` | 349 | `EmployeeID = 105` (add `OR col IS NULL` only if needed) | 26 |
| `(@p IS NULL OR CustomerID = @p)` catch-all | 349 | add `OPTION (RECOMPILE)` or build dynamic SQL | 2 |
| `CONVERT(VARCHAR(10), OrderDate, 120) = '2024-06-01'` | 624 | `OrderDate >= '20240601' AND OrderDate < '20240602'` | 4 |
| function you cannot remove | – | `PERSISTED` computed column + index (optimizer matches the expression) | 119 |

Honest notes: `OR` across two *indexed* columns already gets an index union (28 reads) – the `UNION ALL` rewrite was *worse* (380); `<>` on a 3-value column became two range seeks (117 ≈ `IN`); `CAST(datetimecol AS DATE) = x` is the one function the optimizer can seek (4 reads). Measure, don't assume.

## 2. Syntax cheat-sheet

```sql
SET STATISTICS IO, TIME ON;                              -- reads + CPU/elapsed per statement
-- statistics
SELECT * FROM sys.stats s CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) sp WHERE s.object_id = OBJECT_ID('dbo.T');
DBCC SHOW_STATISTICS ('dbo.T', IX_Name) WITH STAT_HEADER | DENSITY_VECTOR | HISTOGRAM;
UPDATE STATISTICS dbo.T IX_Name WITH FULLSCAN;           -- or SAMPLE 20 PERCENT;  UPDATE STATISTICS dbo.T; (all)
EXEC sp_updatestats;                                     -- every stale statistic in the database
SELECT is_auto_create_stats_on, is_auto_update_stats_on, is_auto_update_stats_async_on FROM sys.databases WHERE name = DB_NAME();
-- parameter sniffing fixes
... WHERE Col = @p OPTION (RECOMPILE);                   -- fresh plan per execution (statement)
CREATE PROCEDURE p @p INT WITH RECOMPILE AS ...          -- fresh plan per execution (proc, never cached)
... OPTION (OPTIMIZE FOR (@p = 1));                      -- plan for a chosen value
... OPTION (OPTIMIZE FOR UNKNOWN);                       -- plan for the average (density)
DECLARE @local INT = @p; ... WHERE Col = @local;         -- same effect as UNKNOWN (old trick)
EXEC sp_recompile 'dbo.p';                               -- throw the cached plan away once
-- DMVs
sys.dm_exec_procedure_stats                              -- reads/CPU per proc
sys.dm_os_wait_stats                                     -- waits since restart; DBCC SQLPERF('sys.dm_os_wait_stats', CLEAR) resets
sys.dm_exec_requests + sys.dm_exec_sessions + sys.dm_exec_sql_text   -- who is blocking whom (blocking_session_id <> 0)
sys.dm_os_waiting_tasks                                  -- tasks waiting right now
EXEC sp_who2;                                            -- classic; sp_WhoIsActive (free) is better
sys.fn_xe_file_target_read_file('system_health*.xel', NULL, NULL, NULL) WHERE object_name = 'xml_deadlock_report'
sys.dm_exec_query_stats + sys.dm_exec_sql_text           -- expensive statements (total_worker_time, total_logical_reads, execution_count)
sys.dm_db_missing_index_details / _groups / _group_stats -- missing index suggestions
sys.dm_db_index_usage_stats                              -- seeks/scans/lookups/updates per index (unused = writes but no reads)
sys.dm_exec_query_memory_grants, tempdb.sys.dm_db_file_space_usage
```

## 3. Gotchas

- **Implicit conversion is silent.** A .NET `string` parameter is `NVARCHAR`; against a `VARCHAR` column the *column* is converted → scan. Declare parameters with the column's type.
- **`OPTIMIZE FOR UNKNOWN` and the local-variable trick are not "fixes"** – they build the plan for the *average* value; the whale still gets the wrong plan (measured: 245,000 reads).
- **`OPTION (RECOMPILE)` costs compile CPU every call.** Fine for reports and search screens; not for a proc called 500 times/second.
- **`WITH RECOMPILE` procs never appear in `sys.dm_exec_procedure_stats`** – their plans are never cached.
- **Auto-update statistics happens at compile time, synchronously** (the query waits for it) unless `AUTO_UPDATE_STATISTICS_ASYNC` is on. A big insert below the threshold leaves the histogram stale → estimate 8 vs actual 8,000.
- **`sys.dm_os_wait_stats` is cumulative since restart** – read it twice with a gap, or clear it on a test box, to see what is happening *now*.
- **`sys.dm_db_index_usage_stats` and missing-index DMVs reset on restart** (and on index rebuild for usage) – judge "unused" only after a full business cycle.
- **`SELECT *` kills covering indexes** (573 vs 4 reads) and pulls columns the app never uses across the network (`ASYNC_NETWORK_IO`).
- **A loop is 20,000 statements**: 2–3 s vs 10 ms for one set-based `UPDATE` on 20,000 rows.
- `sp_updatestats` updates *all* stale statistics with default sampling – on huge tables prefer targeted `UPDATE STATISTICS ... WITH FULLSCAN` in a maintenance window.

## 4. Interview questions

**Q: A query is slow. What do you do?** (the performance tuning checklist)
1. *Confirm and measure*: actual plan, `SET STATISTICS IO, TIME ON`, wait type of the session (`sys.dm_exec_requests`) – is it CPU, I/O, blocking or network?
2. *Server-level first*: top waits (`sys.dm_os_wait_stats`), blocking chain, are we the victim of somebody else?
3. *Plan*: biggest cost operator, scans where seeks were expected, Key Lookups with many executions, estimated vs actual gap, warnings (implicit conversion, spills, missing index).
4. *Predicates*: make them SARGable (no functions/arithmetic/conversion on the column, no leading wildcard, no catch-all OR).
5. *Statistics*: fresh? (`modification_counter`) → `UPDATE STATISTICS`; parameter sniffing? → `RECOMPILE` / `OPTIMIZE FOR` / split procs.
6. *Indexes*: missing (covering with `INCLUDE`), duplicate, unused, fragmented (Level 17).
7. *Query shape*: only needed columns, no `DISTINCT` to hide join duplicates, set-based instead of cursors/loops, avoid scalar UDFs.
8. *Then* hints, plan forcing (Query Store), tempdb files, memory, hardware.

**Q: What does SARGable mean? Give three non-SARGable predicates.**
A predicate the optimizer can turn into an index seek: the column is alone on one side. Non-SARGable: `YEAR(col) = 2024`, `col * 1.1 > x`, `col LIKE '%abc'`, `ISNULL(col, 0) = x`, `VARCHAR col = N'x'`.

**Q: What is parameter sniffing and how do you fix it?**
On the first execution the optimizer uses the actual parameter value to build the plan; the plan is cached and reused. If values are skewed, a plan built for a rare value (seek + lookups) is disastrous for a frequent value (245,000 vs 765 reads in the demo). Fixes: `OPTION (RECOMPILE)`, `WITH RECOMPILE`, `OPTIMIZE FOR (@p = value)` / `UNKNOWN`, separate procs for known heavy values, covering index so both plans converge, Query Store plan forcing, `sp_recompile` as a one-off.

**Q: What are statistics and when are they updated automatically?**
Histogram + density per index/column used to estimate row counts. Auto-created for predicate columns (`AUTO_CREATE_STATISTICS`), auto-updated at the next compile when the modification counter passes `SQRT(1000 × rows)` (2016+, old rule 20 % + 500). Manually: `UPDATE STATISTICS ... WITH FULLSCAN`, `sp_updatestats`, maintenance jobs.

**Q: How do you read `DBCC SHOW_STATISTICS`?**
Header (rows, rows sampled, steps, last update), density vector (1/distinct values per column prefix), histogram (`RANGE_HI_KEY`, `EQ_ROWS` = rows equal to the key, `RANGE_ROWS` = rows between steps, `AVG_RANGE_ROWS` = estimate for a value inside a range).

**Q: Name common wait types and what they mean.**
`CXPACKET/CXCONSUMER` parallelism; `PAGEIOLATCH_*` reading pages from disk (memory/I/O); `LCK_M_*` blocked by locks; `WRITELOG` log write latency; `SOS_SCHEDULER_YIELD` CPU pressure; `ASYNC_NETWORK_IO` client not consuming rows; `RESOURCE_SEMAPHORE` waiting for a memory grant; `PAGELATCH_*` on tempdb = allocation contention.

**Q: How do you find who is blocking whom?**
`sys.dm_exec_requests` (`blocking_session_id <> 0`) joined to `sys.dm_exec_sessions` and `sys.dm_exec_sql_text`; `sys.dm_os_waiting_tasks`; `sp_who2` (BlkBy column); `sp_WhoIsActive`. Deadlocks: `xml_deadlock_report` in the system_health Extended Events session.

**Q: How do you find the most expensive queries?**
`sys.dm_exec_query_stats` ordered by `total_worker_time` (CPU), `total_logical_reads` (I/O) or `execution_count` (chatty), with the statement cut out of `sys.dm_exec_sql_text` using the offsets, and the plan from `sys.dm_exec_query_plan(plan_handle)`. Or Query Store's Top Resource Consuming Queries.

**Q: EXISTS vs IN vs JOIN – which is fastest?**
For a simple existence check the optimizer produces the same semi-join plan for all three (163 reads each in the demo). Differences are semantic: `JOIN` can multiply rows, `NOT IN` with NULLs returns nothing; choose for correctness and readability.

**Q: Why is a cursor/WHILE loop slow?**
Each iteration is a separate statement: plan lookup, locks, log records, 20,000 round trips through the engine. One set-based statement does one pass (2–3 s vs 10 ms measured).

## 5. Checklist

- [ ] I can rewrite the nine non-SARGable patterns and prove the difference with logical reads
- [ ] I can read a histogram and tell when statistics are stale and how to refresh them
- [ ] I can reproduce parameter sniffing on skewed data and choose the right fix for a given workload
- [ ] I can list the top waits and say what each common wait type means
- [ ] I can paste the "who is blocking whom" and "top expensive queries" DMV queries from memory
- [ ] I can find missing, unused and duplicate indexes with DMVs and know why not to act on them blindly
- [ ] I can recite the "a query is slow" checklist in order
