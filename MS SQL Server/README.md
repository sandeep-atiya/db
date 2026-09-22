# MS SQL Server — Step-by-Step Practice (Basic → Advanced)

A self-paced, hands-on course in **20 small levels**. Every level has the same three things:
a short **README** (concepts + interview Q&A), a runnable **Practice** script with explanations,
and an **Exercises** script (questions first, solutions below). One practice database is used everywhere.

> Server used to validate everything: SQL Server 2025 Developer (all scripts also run on 2019 / 2022; features that need 2022+ are marked in comments).

---

## 1. How to use (3 steps)

1. **Create the practice database once:** open `00_Setup/00_Reset_All.sql` in SSMS → **F5**.
   Re-run it any time you want fresh data (e.g. after Level 04 or 16).
2. **Go level by level.** In each `Level_NN_*` folder:
   1. read `README.md` (5–10 min),
   2. open `01_Practice*.sql`, run **block by block** (select the lines → F5), *predict the output before running*,
   3. solve `Exercises.sql` in the "YOUR ANSWERS" area, then compare with the solutions.
3. **Tick the checklist** at the bottom of each README and in the roadmap table below.

**Tips**
- Ctrl+R toggles the results pane, Ctrl+L shows the estimated plan, Ctrl+M includes the actual plan.
- Run scripts from the terminal with `sqlcmd -S localhost -E -C -i "file.sql"`.
- Everything that is *supposed* to fail is wrapped in `BEGIN TRY … END TRY BEGIN CATCH PRINT 'EXPECTED ERROR: …'` so a whole file runs clean.
- Files starting with `03_Two_Sessions_Demo` need two query windows and are commented tutorials.

## 2. Folder structure

```
MS SQL Server/
├── README.md                          <- you are here (roadmap + quick revision)
├── 00_Setup/                          <- practice DB: SQLPractice (6 tables) + ER diagram
├── Level_01_Database_Basics/          <- each level: README.md, 01_Practice*.sql, Exercises.sql
├── Level_02_Data_Types/
├── ...
├── Level_20_Advanced_and_Admin/
├── Interview_Prep/
│   ├── SQL_Interview_Questions.md     <- 75 questions with crisp answers
│   └── Top_Query_Patterns.sql         <- 30 must-know queries, runnable
└── _archive/                          <- your original Lavels.docx + SQLQuery1.sql
```

## 3. Practice database in one look

```
Departments 1──< Employees (self-join ManagerID) 1──< Orders >──1 Customers
                                                       │
                                                       1
                                                       └──< OrderDetails >──1 Products
```
6 departments · 12 employees · 8 customers · 11 products · 19 orders · 26 order lines, with built-in edge cases
(NULL department, department with no employees, duplicate salaries, customer with no orders, product never sold,
order with no salesperson, Pending/Cancelled statuses). Full details: [00_Setup/README.md](00_Setup/README.md).

## 4. Roadmap & progress

| # | Level | You will be able to… | Done |
|---|-------|----------------------|:----:|
| 01 | [Database Basics](Level_01_Database_Basics/README.md) | CREATE/ALTER/DROP database, schema, table · USE · GO · catalog views | ☐ |
| 02 | [Data Types](Level_02_Data_Types/README.md) | choose INT/DECIMAL/VARCHAR/NVARCHAR/DATE… · CAST/CONVERT/TRY_CAST · conversion traps | ☐ |
| 03 | [Constraints](Level_03_Constraints/README.md) | PK · FK (+cascade) · UNIQUE · NOT NULL · CHECK · DEFAULT · IDENTITY | ☐ |
| 04 | [CRUD](Level_04_CRUD/README.md) | INSERT (…SELECT, INTO, OUTPUT) · UPDATE…FROM · DELETE…FROM · TRUNCATE · MERGE | ☐ |
| 05 | [SELECT Mastery](Level_05_SELECT_Mastery/README.md) | WHERE · AND/OR/NOT · IN · BETWEEN · LIKE · IS NULL · ORDER BY · TOP · DISTINCT · OFFSET/FETCH | ☐ |
| 06 | [Functions](Level_06_Functions/README.md) | string · date · numeric · CASE/IIF/COALESCE/ISNULL/NULLIF | ☐ |
| 07 | [Aggregation](Level_07_Aggregation/README.md) | COUNT/SUM/AVG/MIN/MAX · GROUP BY · HAVING · conditional aggregation · ROLLUP | ☐ |
| 08 | [Joins](Level_08_Joins/README.md) | INNER · LEFT · RIGHT · FULL · CROSS · SELF · multi-table · anti-join · ON vs WHERE | ☐ |
| 09 | [Subqueries](Level_09_Subqueries/README.md) | scalar · multi-row · correlated · EXISTS / NOT EXISTS · NOT IN + NULL trap | ☐ |
| 10 | [Set Operations](Level_10_Set_Operations/README.md) | UNION · UNION ALL · INTERSECT · EXCEPT · compare two tables | ☐ |
| 11 | [CTE & Window Functions](Level_11_CTE_and_Window_Functions/README.md) | CTE · recursive CTE · ROW_NUMBER/RANK/DENSE_RANK/NTILE · LAG/LEAD · running totals · gaps & islands · top-N per group · PIVOT/UNPIVOT | ☐ |
| 12 | [Temporary Objects](Level_12_Temporary_Objects/README.md) | #temp · ##global · @table variable · CTE · tempdb · TVP | ☐ |
| 13 | [Views](Level_13_Views/README.md) | CREATE/ALTER/DROP VIEW · updatable views · CHECK OPTION · SCHEMABINDING · indexed views | ☐ |
| 14 | [Stored Procedures](Level_14_Stored_Procedures/README.md) | parameters · OUTPUT · RETURN · TRY/CATCH · THROW · transactions · dynamic SQL / sp_executesql | ☐ |
| 15 | [User-Defined Functions](Level_15_User_Defined_Functions/README.md) | scalar · inline TVF · multi-statement TVF · CROSS/OUTER APPLY · UDF performance | ☐ |
| 16 | [Transactions](Level_16_Transactions/README.md) | BEGIN/COMMIT/ROLLBACK · SAVE TRAN · ACID · isolation levels · locks · blocking · deadlocks | ☐ |
| 17 | [Indexes](Level_17_Indexes/README.md) | clustered · nonclustered · composite · unique · filtered · INCLUDE/covering · seek vs scan vs lookup | ☐ |
| 18 | [Execution Plans](Level_18_Execution_Plans/README.md) | read plans · operators (Scan/Seek/Lookup/Sort/Hash/Loops/Merge) · estimated vs actual · plan cache | ☐ |
| 19 | [Performance Tuning](Level_19_Performance_Tuning/README.md) | SARGability · statistics · parameter sniffing · waits · blocking · DMVs · tuning checklist | ☐ |
| 20 | [Advanced & Admin](Level_20_Advanced_and_Admin/README.md) | dynamic SQL · triggers · cursors · sequences · JSON · XML · security · backup/restore · Agent · linked servers | ☐ |
| ★ | [Interview Prep](Interview_Prep/SQL_Interview_Questions.md) | 75 Q&A + [30 query patterns](Interview_Prep/Top_Query_Patterns.sql) | ☐ |

Suggested pace: **one level per day** for 01–10 (they are short), two days each for 11, 16–20.

---

## 5. Quick revision before an interview (15 minutes)

### 5.1 Logical order of a query
```
FROM → ON/JOIN → WHERE → GROUP BY → HAVING → SELECT → DISTINCT → ORDER BY → TOP / OFFSET-FETCH
```
→ a SELECT alias works in ORDER BY but **not** in WHERE/GROUP BY/HAVING. WHERE runs before aggregation, HAVING after.

### 5.2 The comparison tables interviewers love

| Question | Answer in one line |
|----------|--------------------|
| **DELETE vs TRUNCATE vs DROP** | rows + WHERE + logged + keeps identity / all rows, minimal log, resets identity, no FK refs / removes table itself |
| **WHERE vs HAVING** | before grouping, rows / after grouping, aggregates |
| **UNION vs UNION ALL** | dedups (slower) / keeps duplicates (faster) |
| **PRIMARY KEY vs UNIQUE** | one, no NULL, clustered by default / many, one NULL, nonclustered by default |
| **CHAR vs VARCHAR vs NVARCHAR** | fixed padded / variable 1 B/char / Unicode 2 B/char, `N'…'` |
| **DECIMAL vs FLOAT** | exact (money) / approximate (science) |
| **DATETIME vs DATETIME2** | 3.33 ms, 8 B, legacy / 100 ns, 6–8 B, use this |
| **ISNULL vs COALESCE** | 2 args, T-SQL, type of 1st / N args, ANSI, highest-precedence type |
| **IN vs EXISTS** | list compare, NULL trap with NOT IN / stops at first match, NULL-safe |
| **JOIN vs subquery** | columns from both sides, may duplicate rows / filter or scalar value, no duplicates |
| **ROW_NUMBER vs RANK vs DENSE_RANK** | 1,2,3,4 / 1,2,2,4 / 1,2,2,3 |
| **ROWS vs RANGE** | physical rows / value peers (RANGE is the default frame → running-total trap) |
| **CTE vs temp table vs table variable** | one statement, not materialised / session, stats, indexes, rolled back / batch, no stats, **not rolled back** |
| **View vs indexed view** | saved SELECT, no data / materialised by unique clustered index, SCHEMABINDING + COUNT_BIG |
| **Stored procedure vs function** | side effects, transactions, TRY/CATCH, EXEC / returns value or table, usable in SELECT, no side effects |
| **Inline TVF vs multi-statement TVF** | single SELECT, optimizer sees through it, fast / table variable inside, poor estimates |
| **EXEC('…') vs sp_executesql** | string concat, injection, no plan reuse / parameters, safe, plan reuse |
| **THROW vs RAISERROR** | 2012+, re-throw, severity 16, ends batch / custom severity, formatting, WITH LOG |
| **Clustered vs nonclustered** | data sorted by key, one per table / separate B-tree + locator, up to 999, INCLUDE |
| **Seek vs Scan vs Key Lookup** | B-tree navigation (good) / reads all (bad if selective) / per-row fetch after seek (fix: INCLUDE) |
| **REBUILD vs REORGANIZE** | recreate, updates stats, >30 % / online defrag, <30 % |
| **Blocking vs deadlock** | waiting, resolves itself / circular wait, victim killed (1205) |
| **Optimistic vs pessimistic** | version/detect at write (SNAPSHOT, ROWVERSION) / lock on read |
| **Login vs user** | server principal (authentication) / database principal (authorization) |
| **GRANT vs DENY vs REVOKE** | allow / block (wins) / remove either |
| **Full vs differential vs log backup** | everything / since last full / since last log; restore full → diff → logs, last WITH RECOVERY |
| **SIMPLE vs FULL recovery** | log auto-truncates, no PIT restore / log backups needed, point-in-time restore |
| **Sequence vs IDENTITY** | standalone, shared, value before insert / per column, value after insert |
| **Trigger vs constraint** | procedural, audit/cross-table, slower / declarative, integrity, faster |

### 5.3 Isolation levels
| Level | Dirty read | Non-repeatable | Phantom | How |
|-------|:---:|:---:|:---:|-----|
| READ UNCOMMITTED (NOLOCK) | ✔ | ✔ | ✔ | no shared locks |
| READ COMMITTED (default) | ✘ | ✔ | ✔ | S lock released after read |
| REPEATABLE READ | ✘ | ✘ | ✔ | S locks held to end |
| SERIALIZABLE | ✘ | ✘ | ✘ | range locks |
| SNAPSHOT / RCSI | ✘ | ✘ (RCSI ✔) | ✘ (RCSI ✔) | row versions in tempdb, readers don't block writers |

### 5.4 Must-be-able-to-write queries (see `Interview_Prep/Top_Query_Patterns.sql`)
1. Nth highest salary (DENSE_RANK · OFFSET/FETCH · MAX < MAX)
2. Find & delete duplicates keeping one (ROW_NUMBER + CTE DELETE)
3. Top-N per group (ROW_NUMBER PARTITION BY · CROSS APPLY TOP)
4. Employees earning more than their manager (self join)
5. Customers with no orders (NOT EXISTS · LEFT JOIN…IS NULL) and the **NOT IN + NULL trap**
6. Count per group including zero (LEFT JOIN + COUNT(col))
7. Running total (SUM OVER … ROWS UNBOUNDED PRECEDING) · month-over-month growth (LAG)
8. Gaps (LEAD) and islands / streaks (ROW_NUMBER difference)
9. PIVOT and its CASE equivalent
10. String aggregation (STRING_AGG · FOR XML PATH)
11. Hierarchy with recursive CTE
12. Median (PERCENTILE_CONT), odd/even rows, swap values with CASE, compare two tables with EXCEPT
13. Pagination with OFFSET/FETCH

### 5.5 "A query is slow — what do you do?"
Actual plan + `SET STATISTICS IO, TIME ON` → scans on big tables? key lookups? estimated ≠ actual? warnings (implicit conversion, spills)? →
SARGable predicates? → indexes (missing / covering / column order) → statistics up to date? → rewrite (EXISTS, set-based, no scalar UDF, no DISTINCT/ORDER BY abuse) →
blocking / waits (`sys.dm_exec_requests`, `sys.dm_os_wait_stats`) → parameter sniffing (`OPTION (RECOMPILE)`, `OPTIMIZE FOR`).

### 5.6 Traps to mention (shows experience)
- `NOT IN` with a NULL in the list returns nothing → `NOT EXISTS`.
- Filtering the right table in `WHERE` turns a `LEFT JOIN` into an `INNER JOIN` → put it in `ON`.
- `DATETIME '23:59:59.999'` rounds to next day → use `>= start AND < next_day`.
- `7 / 2 = 3` (integer division) · `LAST_VALUE` needs `ROWS BETWEEN … UNBOUNDED FOLLOWING`.
- Table variables are **not** rolled back · `SELECT *` in a view freezes columns · scalar UDF in WHERE = row-by-row.
- `YEAR(OrderDate) = 2024`, `LIKE '%x'`, `ISNULL(col,0) = 0`, `VarcharCol = 123` → index scan, not seek.
- `sp_` prefix → master lookup · `NOLOCK` ≠ free · `MERGE` needs `HOLDLOCK` under concurrency.

---

## 6. Conventions used in every script

- First lines: `USE SQLPractice; GO`. Base tables are never permanently changed; data-changing demos use copies (`L04_Products`, …) or `ROLLBACK`.
- Level-specific objects are prefixed `L<NN>_` (tables), `vw_L13_`, `usp_L14_`, `fn_L15_`, `trg_L20_` and dropped in a final **CLEANUP** block.
- Expected results are written as trailing comments (`-- 3`, `-- expect Legal`), all verified against the data.
- Always `schema.table`, always table aliases in joins (`e`, `d`, `c`, `o`, `od`, `p`).
