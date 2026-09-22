# Level 12 — Temporary Objects

**Goal:** know the four kinds of "scratch space" in SQL Server — `#temp` tables, `##global` temp tables, `@table` variables and CTEs — choose the right one, and explain the differences interviewers love (scope, statistics, transactions).

**Time:** ~1.5 hr · **Files:** `01_Practice_Temp_Tables.sql` → `02_Practice_Table_Variables_TVP.sql` → `03_Two_Sessions_Demo.sql` (read, needs 2 windows) → `Exercises.sql`

---

## 1. Concepts in plain words

### tempdb — the shared scratch database

| Fact | Why it matters |
|------|----------------|
| One `tempdb` per server, shared by **every** database and **every** user | A bad query in one app can slow everyone down |
| Rebuilt from `model` at **every restart** | Never keep real data there; `create_date` of tempdb = last restart time |
| Holds `#temp`, `##temp`, `@table` variables, sort/hash work tables, cursors, row versions | "Table variables are in memory" is a **myth** — they live in tempdb too |
| Watch it with `tempdb.sys.dm_db_file_space_usage` (whole DB) and `sys.dm_db_session_space_usage` (per session) | Find who is filling it |

### The four options

| | `#Temp` table | `##Global` temp | `@Table` variable | CTE |
|---|---|---|---|---|
| **Stored in** | tempdb | tempdb | tempdb | nowhere (part of one query) |
| **Visible to** | my session + procs it calls | **all** sessions | the batch / proc / function it is declared in | the **one** statement after it |
| **Dropped when** | session (or creating proc) ends, or `DROP` | creating session ends **and** nobody is using it | batch ends (`GO`) | statement ends |
| **Statistics** | yes (auto-created) | yes | **no** → optimizer guesses 1 row (2019+: real row count at compile, still no histogram) | n/a |
| **Indexes** | any, add any time | any | only inline in `DECLARE` (PK, UNIQUE, `INDEX`) | none |
| **`ALTER TABLE`** | yes | yes | **no** | n/a |
| **`ROLLBACK`** | undone | undone | **not undone** | n/a |
| **Name in tempdb** | padded with `_` + hex counter (128 chars) | exact | internal `#A1B2…` | – |
| **Best for** | big sets, multi-step work, joins that need good estimates | handing rows to another session (rare) | small sets (< ~100 rows), inside functions, logging in `CATCH` | readable multi-step logic, recursion, single use |

### Table-valued parameter (TVP)
A user-defined **table type** (`CREATE TYPE … AS TABLE`) lets you pass a whole table into a procedure as one parameter. The parameter must be `READONLY`. Clients (.NET `DataTable`, JDBC) send thousands of rows in one round trip — the clean replacement for comma-separated ID strings.

## 2. Syntax cheat-sheet

```sql
-- LOCAL TEMP TABLE
DROP TABLE IF EXISTS #T;
CREATE TABLE #T (Id INT NOT NULL PRIMARY KEY, Name VARCHAR(50));     -- leave constraints UNNAMED
SELECT col1, col2 INTO #T2 FROM dbo.Orders WHERE Status = 'Pending'; -- create + fill
CREATE INDEX IX_T_Name ON #T (Name);                                 -- indexes OK, any time
ALTER TABLE #T ADD PRIMARY KEY (Id);
SELECT OBJECT_ID('tempdb..#T');                                      -- NULL = does not exist
SELECT name FROM tempdb.sys.tables WHERE name LIKE '#T[_]%';         -- real padded name

-- GLOBAL TEMP TABLE
CREATE TABLE ##Shared (...);          -- visible to all sessions; exact name in tempdb.sys.tables

-- TABLE VARIABLE
DECLARE @T TABLE (Id INT PRIMARY KEY, Qty INT CHECK (Qty > 0), INDEX IX_Qty (Qty));
INSERT INTO @T VALUES (1, 5);         -- no ALTER, no statistics, batch scope, ignores ROLLBACK

-- INSERT ... EXEC  (land a proc's result set in a table)
INSERT INTO #T (col1, col2) EXEC dbo.usp_GetRows @Param = 1;         -- same column count + order
INSERT INTO #T (col1, col2) EXEC ('SELECT a, b FROM dbo.X');          -- dynamic SQL works too

-- TABLE-VALUED PARAMETER
CREATE TYPE dbo.IdList AS TABLE (Id INT NOT NULL PRIMARY KEY);
CREATE PROCEDURE dbo.usp_X @Ids dbo.IdList READONLY AS SELECT ... JOIN @Ids i ON ...;
DECLARE @Ids dbo.IdList; INSERT INTO @Ids VALUES (1), (5); EXEC dbo.usp_X @Ids;
DROP PROCEDURE dbo.usp_X; DROP TYPE dbo.IdList;                      -- proc first, then type

-- TEMPDB USAGE
SELECT SUM(user_object_reserved_page_count) * 8 / 1024.0 AS UserMB FROM tempdb.sys.dm_db_file_space_usage;
SELECT * FROM sys.dm_db_session_space_usage WHERE session_id = @@SPID;
```

## 3. Gotchas

- **Named constraints on temp tables clash across sessions.** The table name is uniquified, the constraint name is not → second session gets *"There is already an object named 'PK_X'"*. Leave constraints unnamed; naming **indexes** is fine.
- **`SELECT … INTO #T` copies no constraints or indexes** — add the PK afterwards if you join on it.
- **A temp table created inside a proc dies with the proc.** The caller cannot see it; the reverse (caller creates, proc reads) works.
- **`@T` after `GO` is gone**, and dynamic SQL (`EXEC(...)`) cannot see it either — it runs as its own batch.
- **`@T` is not rolled back.** Great for logging inside `CATCH`, dangerous if you assumed it was undone.
- **`@T` has no statistics** → estimated 1 row (2019+ compat 150: real row count at first compile). Big sets in `@T` produce nested-loop disasters. Use `#T`.
- **`INSERT … EXEC` cannot be nested**, needs an existing target table with the same number of columns in the same order.
- **Global temp tables are shared state** — two users running the same script overwrite each other. Prefer a real staging table with a session key.
- **Deferred name resolution**: a proc that reads `#T` compiles fine even if `#T` does not exist yet; the error comes at run time.
- **Recompiles**: creating/changing a `#T` inside a proc can trigger statement recompiles; `@T` does not. For tiny sets that can make `@T` faster.

## 4. Interview questions

**Q: Temp table vs table variable — the differences?**
Scope (session vs batch), statistics (yes vs no), indexes (any time vs inline only), `ALTER` (yes vs no), transactions (`#T` rolled back, `@T` not), recompiles (`#T` may cause, `@T` fewer). Both live in tempdb.

**Q: Are table variables stored in memory?**
No. They are tempdb objects like temp tables; small ones may stay in the buffer pool, so may small temp tables.

**Q: Which one survives a ROLLBACK?**
The table variable keeps its rows; the temp table's changes are undone. That is why `@T` is used to collect error info inside a transaction before rolling back.

**Q: Local vs global temp table?**
`#T`: private to the creating session (and procs it calls), name padded in tempdb, dropped when the session/proc ends. `##T`: visible to every session, exact name, dropped when the creator disconnects and no one is using it.

**Q: Can a stored procedure see a temp table created by the caller?**
Yes — temp tables flow *down* into nested procs. They do not flow *up*: a temp table created inside a proc is dropped when that proc ends.

**Q: When would you choose a temp table over a CTE?**
When the result is needed by more than one statement, is large, or benefits from an index/statistics. A CTE is re-evaluated every time it is referenced and lives for one statement only.

**Q: What is a TVP and why use it?**
A table-type parameter (`READONLY`) that passes many rows to a proc in one call. Replaces CSV strings / XML; the client sends a `DataTable` in a single round trip.

**Q: How do you check tempdb usage?**
`tempdb.sys.dm_db_file_space_usage` (user objects vs internal objects vs version store vs free) and `sys.dm_db_session_space_usage` / `sys.dm_db_task_space_usage` to find the session or query responsible.

**Q: Why is tempdb "rebuilt on restart" important?**
Anything in it is gone after a restart; its file size and file count settings matter because every user shares it; contention on allocation pages is a classic tuning topic (multiple equal data files).

**Q: What is `INSERT … EXEC` used for?**
Capturing a procedure's result set (or dynamic SQL) into a table so it can be joined/filtered. Limitation: cannot be nested.

## 5. Checklist

- [ ] I can explain what tempdb is, who shares it, and why it is rebuilt on restart
- [ ] I can create a `#temp` table two ways (`CREATE TABLE #`, `SELECT … INTO #`) and find its real name in `tempdb.sys.tables`
- [ ] I know the scope rules: `#T` = session + nested procs, `##T` = all sessions, `@T` = batch
- [ ] I can demonstrate that `@T` ignores `ROLLBACK` and `#T` does not
- [ ] I can list the statistics / index / ALTER differences between `#T` and `@T`
- [ ] I can capture a proc's output with `INSERT … EXEC` and use the "stage in #temp then join" pattern
- [ ] I can create a table type, use it as a `READONLY` parameter, and drop it in the right order
- [ ] I can query the two tempdb space DMVs
