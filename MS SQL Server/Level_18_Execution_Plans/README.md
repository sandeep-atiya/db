# Level 18 — Execution Plans

**Goal:** read an execution plan like a story (which operator did what, for how many rows, at what cost), recognise every common operator, spot the classic warning signs (Key Lookup storms, wrong estimates, spills, implicit conversion), and use the plan cache and Query Store to find and fix slow queries.

**Time:** ~3 hrs · **Files:** `01_Practice_Reading_Plans.sql` → `02_Practice_Operators.sql` → `03_Practice_Cardinality_Warnings.sql` → `04_Practice_PlanCache_QueryStore.sql` → `Exercises.sql`

> The practice files build a 200,000-row table `dbo.L18_Orders` (+ 1,000 `dbo.L18_Customers`) so plans look like production plans. Everything is dropped at the end of each file.

---

## 1. Concepts in plain words

| Term | Meaning |
|------|---------|
| **Execution plan** | The optimizer's step-by-step recipe for a query: which index to read, how to join, where to sort. Shown as a tree of **operators**. |
| **Estimated plan** | Compiled *without running* the query (SSMS **Ctrl+L**, `SET SHOWPLAN_TEXT/XML ON`). Row counts are guesses from statistics. |
| **Actual plan** | Same plan plus real runtime numbers – *Actual Number of Rows*, executions, spills, time (SSMS **Ctrl+M** then run, `SET STATISTICS XML ON`). |
| **Live Query Statistics** | SSMS option that animates the actual plan while a long query runs. |
| **Reading direction** | Data flows **right → left**; children of a join run **top → bottom** (top = outer/driving input). Arrow thickness = rows. |
| **Cost %** | Share of the *estimated* total cost. Unit-less. Useful to find the heavy operator, but it stays an estimate even in an actual plan. |
| **Cardinality estimate** | The optimizer's guess of how many rows an operator returns, made from **statistics** (histograms). Every plan choice (seek/scan, join type, memory) depends on it. |
| **Statistics IO / TIME** | `SET STATISTICS IO ON` → logical reads (8 KB pages) per table = the number you compare before/after a change. `TIME` → CPU vs elapsed ms. |
| **Plan cache** | Memory where compiled plans are kept for reuse. `sys.dm_exec_cached_plans` → `sys.dm_exec_sql_text` → `sys.dm_exec_query_plan`. |
| **Parameterisation** | *Simple* (default): only trivial plans get literals replaced by parameters. *Forced*: almost every literal → one plan per query shape (fights cache bloat, risks parameter sniffing). |
| **Query Store** | Per-database history of query texts, plans and runtime stats (2016+, ON by default since 2022). Lets you find regressed queries and **force** a known-good plan. |
| **Spill** | An operator (Sort / Hash) got less memory than it needed (because the estimate was too low) and wrote to tempdb. Yellow warning in the actual plan. |

### Operator cheat-sheet

| Operator | What it means | Good / bad sign |
|----------|---------------|-----------------|
| **Table Scan** | Reads every page of a heap (no clustered index). | Bad for selective queries; a heap with lots of rows usually needs a clustered index. |
| **Clustered Index Scan** | Reads the whole table (in clustered-key order). | Fine for "everything" queries/aggregates; bad when you wanted a few rows → missing index or non-SARGable predicate. |
| **Index Scan** | Reads a whole nonclustered index (narrower than the table). | OK for counts/aggregates; suspicious with a selective `WHERE` (check for implicit conversion / functions on the column). |
| **Index Seek / Clustered Index Seek** | B-tree navigation straight to the matching range. | Good. Check *Seek Predicate* (used for navigation) vs *Predicate* (residual filter after reading). |
| **Key Lookup** | For each row from a nonclustered index, fetch missing columns from the clustered index. | Fine for a handful of rows; thousands per query = add `INCLUDE` columns (covering index). |
| **RID Lookup** | Same as Key Lookup but on a heap (uses the row ID). | Same advice; also a hint that the table should get a clustered index. |
| **Nested Loops** | For each outer row, run the inner side (usually a seek). | Great for small outer + indexed inner (OLTP). Bad if the outer side is unexpectedly big (estimate was wrong). |
| **Merge Join** | Zips two inputs that are **sorted** on the join key. | Cheap when inputs are already ordered by an index; if a Sort was added to feed it, check the cost. |
| **Hash Match (Join)** | Builds a hash table on the smaller input, probes with the bigger one. | Normal for large unsorted inputs (reports). Needs memory; watch for spills and for a *build* side that is not the smaller one. |
| **Hash Match (Aggregate)** | `GROUP BY` / `DISTINCT` on unsorted input using a hash table. | Normal; on huge inputs check the memory grant. |
| **Stream Aggregate** | Aggregates rows that arrive already sorted (index order). | Cheap; if you see a Sort feeding it, an index in that order could remove the sort. |
| **Sort** | `ORDER BY`, `DISTINCT`, `TOP N`, merge join input. | Expensive on big inputs (memory grant, spills). An index in the right order removes it. |
| **Top / TopN Sort** | Stops after N rows / keeps only N rows while sorting. | Good. `TOP` without `ORDER BY` returns *any* N rows. |
| **Compute Scalar** | Calculates an expression per row. | Near-zero cost; a scalar UDF here is the exception (row-by-row, see Level 15). |
| **Filter** | A predicate that could not be pushed into the scan/seek (e.g. `HAVING`). | Normal for HAVING; on a base table it often means non-SARGable predicate. |
| **Parallelism (Gather / Repartition / Distribute Streams)** | Query runs on several threads. | Good for big reports; on an OLTP query it means the plan cost crossed *cost threshold for parallelism* (default 5 – usually raised to 25-50). |
| **Table Spool (Lazy / Eager)** | Temporary copy of rows in tempdb read more than once (window functions, Halloween protection for updates). | Small spools are normal; huge spools = rewrite or index. |
| **Constant Scan / Concatenation** | Generates constant rows / appends inputs (`UNION ALL`, `IN` lists). | Normal. |

## 2. Syntax cheat-sheet

```sql
-- Estimated plan (query NOT executed) - each SET must be alone in its batch
SET SHOWPLAN_TEXT ON;  GO  SELECT ...;  GO  SET SHOWPLAN_TEXT OFF;  GO     -- indented text tree
SET SHOWPLAN_ALL  ON;  GO  SELECT ...;  GO  SET SHOWPLAN_ALL  OFF;  GO     -- + EstimateRows, EstimateIO/CPU, TotalSubtreeCost, OutputList
SET SHOWPLAN_XML  ON;  GO  SELECT ...;  GO  SET SHOWPLAN_XML  OFF;  GO     -- XML (clickable in SSMS)

-- Actual plan and runtime numbers (query IS executed)
SET STATISTICS XML ON;       -- results + actual plan XML
SET STATISTICS IO, TIME ON;  -- logical reads per table, CPU / elapsed ms

-- Find a plan in the cache (tag the query with a comment first: SELECT /* mytag */ ...)
SELECT cp.objtype, cp.usecounts, st.text, qp.query_plan
FROM sys.dm_exec_cached_plans cp
CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle)  st
CROSS APPLY sys.dm_exec_query_plan(cp.plan_handle) qp
WHERE st.text LIKE '%mytag */%' AND st.text NOT LIKE '%dm_exec_cached_plans%';
-- search the XML:  CAST(qp.query_plan AS NVARCHAR(MAX)) LIKE '%PhysicalOp="Index Seek"%'
-- last ACTUAL plan of a cached query (2019+): ALTER DATABASE SCOPED CONFIGURATION SET LAST_QUERY_PLAN_STATS = ON;
--                                             sys.dm_exec_query_plan_stats(plan_handle)

-- Plan cache housekeeping
DBCC FREEPROCCACHE (plan_handle);                                  -- one plan (safe)
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;         -- this database only (2016+)
DBCC FREEPROCCACHE;                                                -- WHOLE server - never on production
ALTER DATABASE db SET PARAMETERIZATION FORCED | SIMPLE;

-- Query Store
ALTER DATABASE db SET QUERY_STORE = ON (OPERATION_MODE = READ_WRITE, QUERY_CAPTURE_MODE = ALL);
sys.query_store_query_text -> sys.query_store_query -> sys.query_store_plan -> sys.query_store_runtime_stats
EXEC sp_query_store_force_plan @query_id, @plan_id;   EXEC sp_query_store_unforce_plan @query_id, @plan_id;

-- Hints (learning / last resort only)
OPTION (HASH JOIN | LOOP JOIN | MERGE JOIN)   OPTION (MAXDOP 1)   OPTION (RECOMPILE)   OPTION (MAX_GRANT_PERCENT = 10)
```

## 3. Gotchas

- **Cost % is always an estimate**, even in an actual plan. Compare *Estimated* vs *Actual Number of Rows* first; a 10×+ gap is the real problem.
- **Estimated rows on the inner side of a Nested Loops are *per execution***. A Key Lookup showing "1 row" with 10,000 *executions* did 10,000 seeks.
- `SET SHOWPLAN_*` **does not run the query** – an `UPDATE` under SHOWPLAN changes nothing – and the statement must be alone in its batch.
- **Trivial plans are auto-parameterised**: the cache entry with your literal text is only a shell that points to a `Prepared` plan (`ParameterizedPlanHandle`). Comments after the statement are not part of Query Store's statement text – put tags at the start of the statement.
- **Changing any database scoped configuration flushes that database's plan cache**; `DBCC FREEPROCCACHE` without arguments flushes the whole server.
- **Statistics go stale silently**: auto-update fires only after about `sqrt(1000 × rows)` changes (SQL 2016+ rule), e.g. ~14,000 rows on a 200,000-row table. Until then estimates for new values are wrong.
- **Table variables**: old behaviour = 1-row estimate; SQL 2019+ deferred compilation fixes the first estimate only. For big row sets use `#temp` tables (they have statistics).
- **Implicit conversion on the column side** (`VARCHAR` column = `N'...'` literal, `VARCHAR` = `INT`) turns a seek into a scan and shows a *PlanAffectingConvert* warning.
- **A missing-index suggestion is per query and greedy** (includes every column touched). Never create it blindly – check `user_seeks`, existing indexes, write cost.
- **Join hints and MAXDOP hints are for learning**; in production fix the estimate (statistics, SARGable predicate, index) instead.

## 4. Interview questions

**Q: What is the difference between an estimated and an actual execution plan?**
The estimated plan is produced by the optimizer without executing the query; row counts come from statistics. The actual plan is the same plan captured after execution and adds real numbers – actual rows, executions, spills, time. The shape is identical; only the runtime information differs. You use the actual plan to find estimate/actual gaps.

**Q: A query is slow. How do you tune it?** (say it as an ordered checklist)
1. Reproduce and measure: `SET STATISTICS IO, TIME ON`, actual plan.
2. Check the plan for the big picture: which operator has the highest cost / thickest arrows / biggest estimate-vs-actual gap.
3. Look for scans where a seek was expected → missing index or non-SARGable predicate (function on column, implicit conversion, leading wildcard).
4. Look for Key/RID Lookups with many executions → covering index (`INCLUDE`).
5. Check warnings: implicit conversion, spills (memory grant), no join predicate, missing index hint.
6. Check statistics freshness (`sys.dm_db_stats_properties`, `UPDATE STATISTICS`) and parameter sniffing (Level 19).
7. Rewrite the query (fewer columns, no `SELECT *`, no unnecessary `DISTINCT`/`ORDER BY`, set-based instead of loops).
8. Only then consider hints, plan forcing (Query Store) or hardware.

**Q: What is a Key Lookup and how do you remove it?**
A Key Lookup happens when a nonclustered index satisfies the `WHERE` but not the `SELECT` list, so for each matching row SQL Server jumps to the clustered index to fetch the missing columns (a RID Lookup on a heap). Remove it by adding the missing columns as `INCLUDE` columns (a covering index), or by selecting fewer columns.

**Q: Nested Loops vs Hash Match vs Merge Join – when does the optimizer choose each?**
Nested Loops: small outer input and an index on the inner join column (OLTP lookups). Merge Join: both inputs already sorted on the join key (or cheap to sort), medium/large inputs. Hash Match: large unsorted inputs without a useful index (reporting joins); needs memory for the build side.

**Q: What does "cardinality estimate" mean and why does it matter?**
It is the optimizer's guess of how many rows each operator will produce, computed from statistics before the query runs. Everything – seek vs scan, join type, memory grant, parallelism – is chosen from that guess. A wrong estimate (stale statistics, table variable, complex predicate) gives a plan built for the wrong number of rows, which is why "estimated vs actual rows" is the first thing to compare.

**Q: What is a spill to tempdb?**
A Sort or Hash operator asked for memory based on the estimated rows; more rows arrived than fit, so it wrote the overflow to tempdb (disk) and continued there. The actual plan shows a yellow warning on the operator and `sys.dm_exec_query_stats.last_spills` counts the pages. Fix the estimate (statistics, rewrite) or the memory grant.

**Q: How do you read a graphical plan?**
Right to left (data flow), top to bottom for join inputs; arrow width = rows; hover an operator for estimated vs actual rows, executions, predicate vs seek predicate, output list and warnings; start at the highest-cost operator and at the widest estimate/actual gap.

**Q: What is the plan cache and what is parameter reuse?**
Compiled plans are stored in memory and reused for identical text (or identical parameterised text). Simple parameterisation only turns trivial queries into `Prepared` plans; forced parameterisation does it for almost everything. Applications should send parameters (`sp_executesql`) so one plan is reused instead of one plan per literal.

**Q: What is Query Store and when do you force a plan?**
A per-database flight recorder of query texts, plans and runtime statistics. When a query regresses because the optimizer switched to a worse plan (after a statistics or data change), you can force the previously good plan with `sp_query_store_force_plan` as a quick fix while you address the root cause.

**Q: Should you create every index the "missing index" hint suggests?**
No. The suggestion is per query and greedy (includes every referenced column). Check how often the query runs (`user_seeks`), whether an existing index can be widened instead, and the write cost of one more index.

## 5. Checklist

- [ ] I can get an estimated plan (Ctrl+L / SHOWPLAN_TEXT) and an actual plan (Ctrl+M / STATISTICS XML) and know the difference
- [ ] I can read logical reads from `SET STATISTICS IO ON` and compare before/after
- [ ] I can name each operator in the cheat-sheet and say whether it is a good or bad sign
- [ ] I can find a query's plan in the cache and search its XML for an operator or a warning
- [ ] I can explain estimated vs actual rows, per-execution estimates and why stale statistics break plans
- [ ] I can recognise a Key Lookup and remove it with a covering index
- [ ] I can explain simple vs forced parameterisation and the danger of `DBCC FREEPROCCACHE`
- [ ] I can turn on Query Store, find the top resource queries and force/unforce a plan
