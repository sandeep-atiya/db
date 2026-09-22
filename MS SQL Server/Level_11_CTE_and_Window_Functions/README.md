# Level 11 — CTE and Window Functions

**Goal:** write readable multi-step queries with `WITH`, walk hierarchies with recursive CTEs, and master `OVER()` — ranking, `LAG/LEAD`, running totals, frames — plus the interview patterns built on them (top-N per group, Nth highest, de-duplication, gaps and islands, PIVOT).

**Time:** ~4 hr (split over 2–3 sessions) · **Files:** `01_Practice_CTE.sql` → `02_Practice_Window_Functions.sql` → `03_Practice_Patterns.sql` → `04_Practice_Pivot_Unpivot.sql` → `Exercises.sql`

---

## 1. Concepts in plain words

| Term | Meaning |
|------|---------|
| **CTE** (`WITH name AS (…)`) | A named result set that exists **only for the next statement**. Like a derived table with the name on top, so you read top-down. Reusable inside that statement; the only way to write recursion. |
| **Not materialised** | A CTE is inlined like a view. Reference it 3 times = evaluated 3 times. For expensive, reused results use a temp table. |
| **Recursive CTE** | `anchor UNION ALL recursive-member`. The anchor gives starting rows; the recursive member joins back to the CTE and runs until it returns no rows. Default limit 100 rounds (`OPTION (MAXRECURSION n)`). |
| **Window function** | `func() OVER (PARTITION BY … ORDER BY … frame)`. Computes a value over a *window* of related rows **without collapsing the rows** (unlike `GROUP BY`). |
| **PARTITION BY** | "GROUP BY inside the window": restarts the calculation per group. NULL is its own partition. |
| **ORDER BY (in OVER)** | Gives the rows a sequence: required for ranking, `LAG/LEAD`, running totals. |
| **Frame** | Which rows around the current row the aggregate sees: `ROWS/RANGE BETWEEN … AND …`. Default with `ORDER BY` = `RANGE UNBOUNDED PRECEDING … CURRENT ROW`. |
| **PIVOT / UNPIVOT** | Turn row values into columns (and back). Three roles: grouping column, spreading column, aggregate. |

**Ranking functions** (Employees by Salary DESC; Amit and Pooja tie at 65000):

| Function | Ties | Gaps after a tie | Sneha, Rahul, Priya, Deepak, Karan, **Amit, Pooja**, Vikram … | Use for |
|----------|------|------------------|------|---------|
| `ROW_NUMBER()` | unique numbers (arbitrary order unless you add a tie-breaker) | — | 1 2 3 4 5 **6 7** 8 | de-duplication, pagination, top-1 per group |
| `RANK()` | same rank | **yes** (next = 8) | 1 2 3 4 5 **6 6** 8 | competition ranking |
| `DENSE_RANK()` | same rank | **no** (next = 7) | 1 2 3 4 5 **6 6** 7 | Nth highest value, top-N *values* |
| `NTILE(n)` | fills buckets in order | — | 12 rows / 4 → 1 1 1 2 2 2 3 3 3 4 4 4 | quartiles, salary bands |

**Frames cheat-sheet**

| Frame | Meaning |
|-------|---------|
| `ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW` | running total, row by row (**write this one**) |
| `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW` | the **default** when `ORDER BY` is present; rows with the same ORDER BY value are *peers* and get the same result |
| `ROWS BETWEEN 2 PRECEDING AND CURRENT ROW` | 3-row moving window (moving average) |
| `ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING` | centred 3-row window |
| `ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING` | whole partition — needed for `LAST_VALUE` |
| *(no ORDER BY)* | whole partition |

`ROWS` counts physical rows; `RANGE` groups by value (peers). `RANGE` only supports `UNBOUNDED` and `CURRENT ROW` in SQL Server.

## 2. Syntax cheat-sheet

```sql
-- CTE chain (each CTE can use the ones above it); previous statement MUST end with ;
WITH DeptAvg AS (SELECT DepartmentID, AVG(Salary) AS AvgSalary FROM dbo.Employees GROUP BY DepartmentID),
     AboveAvg AS (SELECT e.* FROM dbo.Employees e JOIN DeptAvg d ON d.DepartmentID = e.DepartmentID WHERE e.Salary > d.AvgSalary)
SELECT * FROM AboveAvg;                                              -- Rahul, Priya, Sneha, Karan

-- CTE in UPDATE / DELETE (single base table)
WITH Numbered AS (SELECT *, ROW_NUMBER() OVER (PARTITION BY CustomerName, Email ORDER BY Id) AS rn FROM dbo.L11_DupCustomers)
DELETE FROM Numbered WHERE rn > 1;                                   -- keep lowest Id

-- Recursive CTE: org chart with Level and Path
WITH Org AS
(   SELECT EmployeeID, EmployeeName, ManagerID, 1 AS Lvl, CAST(EmployeeName AS VARCHAR(500)) AS Path
    FROM dbo.Employees WHERE ManagerID IS NULL                       -- anchor
    UNION ALL
    SELECT e.EmployeeID, e.EmployeeName, e.ManagerID, o.Lvl + 1, CAST(o.Path + ' > ' + e.EmployeeName AS VARCHAR(500))
    FROM dbo.Employees e JOIN Org o ON o.EmployeeID = e.ManagerID     -- recursive member
)
SELECT * FROM Org ORDER BY Path OPTION (MAXRECURSION 50);
-- Up the chain: JOIN Up u ON u.ManagerID = m.EmployeeID  (anchor = the employee)
-- Numbers: SELECT 1 AS n UNION ALL SELECT n + 1 FROM Numbers WHERE n < 100   (2022+: GENERATE_SERIES(1,100))

-- Window functions
AVG(Salary)  OVER ()                                            -- whole table, on every row
AVG(Salary)  OVER (PARTITION BY DepartmentID)                   -- per department, on every row
ROW_NUMBER() OVER (PARTITION BY DepartmentID ORDER BY Salary DESC, EmployeeID)
LAG(OrderDate, 1, NULL) OVER (PARTITION BY CustomerID ORDER BY OrderDate)     -- previous row; LEAD = next
FIRST_VALUE(EmployeeName) OVER (PARTITION BY DepartmentID ORDER BY Salary DESC)
LAST_VALUE(EmployeeName)  OVER (PARTITION BY DepartmentID ORDER BY Salary DESC
                                ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
SUM(Revenue) OVER (ORDER BY Mth ROWS UNBOUNDED PRECEDING)                       -- running total
AVG(Revenue) OVER (ORDER BY Mth ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)       -- moving average
Salary * 100.0 / SUM(Salary) OVER ()                                            -- percent of total
SUM(SUM(Salary)) OVER ()                                        -- window on top of a GROUP BY aggregate
WINDOW w AS (PARTITION BY DepartmentID ORDER BY Salary DESC)    -- SQL 2022+: RANK() OVER w, SUM(x) OVER (w ROWS UNBOUNDED PRECEDING)

-- Filter on a window function: CTE first
WITH R AS (SELECT *, DENSE_RANK() OVER (ORDER BY Salary DESC) AS rk FROM dbo.Employees)
SELECT * FROM R WHERE rk = 2;                                   -- Rahul 85000

-- PIVOT (source = ONLY grouping + spreading + aggregate columns)
SELECT Category, [1] AS Jan, [2] AS Feb, [3] AS Mar
FROM (SELECT p.Category, MONTH(o.OrderDate) AS Mth, od.Quantity * od.UnitPrice AS Amount FROM … ) AS src
PIVOT (SUM(Amount) FOR Mth IN ([1], [2], [3])) AS pv;
-- Portable: SUM(CASE WHEN Mth = 1 THEN Amount ELSE 0 END) AS Jan, …
-- Dynamic: @cols = STRING_AGG(QUOTENAME(Category), ',')  ->  build @sql  ->  EXEC sp_executesql @sql
-- UNPIVOT (Revenue FOR MonthName IN (Jan, Feb, Mar)) AS up          -- drops NULL cells
-- CROSS APPLY (VALUES (1,'Jan',c.Jan), (2,'Feb',c.Feb)) AS v (MthNo, MonthName, Revenue)   -- modern unpivot
```

## 3. Gotchas (things that bite beginners)

- **"…the previous statement must be terminated with a semicolon"** — the statement before `WITH` needs a `;`. End every statement with `;` (the `;WITH` habit is a workaround).
- **A CTE lives for ONE statement.** The next `SELECT … FROM cte` fails with *Invalid object name*. Need it twice across statements → temp table.
- **Window functions cannot be used in `WHERE`/`HAVING`** (Msg 4108). Wrap in a CTE/derived table, filter outside.
- **`LAST_VALUE` looks broken** because the default frame ends at the current row. Add `ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING` (or use `FIRST_VALUE` with reversed `ORDER BY`).
- **Running totals with the default `RANGE` frame** give the same total to tied rows (Amit & Pooja both 413000). Write `ROWS UNBOUNDED PRECEDING` — correct and faster.
- **`ROW_NUMBER` with ties is non-deterministic** — add a unique tie-breaker (`EmployeeID`) to the `ORDER BY`.
- **`RANK = 7` can return nobody** (after a tie at 6 the next rank is 8). Use `DENSE_RANK` for "Nth highest".
- **Recursive CTE**: both members need the same column count and **types** (`CAST` the `Path` in both), `UNION ALL` not `UNION`, default 100 levels → Msg 530; a cycle in the data recurses forever — guard with a Path check or a level limit.
- **`PIVOT` explodes** into many rows if the source has extra columns — every extra column becomes a grouping column. Use a derived table with exactly three columns.
- **`UNPIVOT` drops NULL cells** and needs identical column types; `CROSS APPLY VALUES` keeps NULLs and is more flexible.
- **`STRING_AGG(DISTINCT …)` is not allowed** — `SELECT DISTINCT` in a derived table first.
- `PARTITION BY` treats NULL as a group of its own; a correlated subquery drops NULL keys. Same question, different NULL answer.

## 4. Interview questions

**Q: `RANK` vs `DENSE_RANK` vs `ROW_NUMBER`?**
All number rows by an `ORDER BY`. `ROW_NUMBER` is always unique (ties broken arbitrarily). `RANK` gives ties the same number and then **skips** (1, 2, 2, 4). `DENSE_RANK` gives ties the same number with **no gap** (1, 2, 2, 3). On our data Amit/Pooja: 6/7, 6/6, 6/6 and Vikram next: 8, 8, 7.

**Q: CTE vs temp table?**
CTE: one statement, not stored, re-evaluated per reference, can be recursive, no indexes. Temp table: physical in tempdb, lives for the session, usable by many statements, has statistics and can be indexed — better for large reused intermediate results.

**Q: CTE vs subquery / derived table?**
Same result; a CTE is named, read top-down, can be referenced several times in the statement and can be recursive. Performance is usually identical because both are inlined.

**Q: Where do you use a recursive CTE?**
Hierarchies (org chart, bill of materials, folder trees, category parent/child), walking up to all ancestors, generating number and date series, splitting or expanding rows. Needs anchor + `UNION ALL` + recursive member; control depth with `MAXRECURSION`.

**Q: How do you find the Nth highest salary?**
`WITH R AS (SELECT *, DENSE_RANK() OVER (ORDER BY Salary DESC) AS rk FROM Employees) SELECT * FROM R WHERE rk = N`. Alternatives: `SELECT DISTINCT Salary … ORDER BY Salary DESC OFFSET N-1 ROWS FETCH NEXT 1 ROWS ONLY`, or `MAX(Salary) WHERE Salary < (SELECT MAX(Salary) …)` for N = 2. Use `DENSE_RANK`, not `RANK`, because of ties.

**Q: How do you delete duplicate rows keeping one?**
`WITH N AS (SELECT ROW_NUMBER() OVER (PARTITION BY <dup columns> ORDER BY Id) AS rn FROM T) DELETE FROM N WHERE rn > 1;` — `PARTITION BY` defines what "duplicate" means, `ORDER BY` decides which copy survives.

**Q: What is "gaps and islands"?**
Finding runs of consecutive values (islands: login streaks) and the missing values between them (gaps). Islands: `date - ROW_NUMBER()` is constant within a run → `GROUP BY` that value. Gaps: `LEAD(value)` and keep rows where `next - current > 1`; list each missing value with a numbers table / `GENERATE_SERIES` + `NOT EXISTS`.

**Q: Top-N per group?**
`ROW_NUMBER() OVER (PARTITION BY group ORDER BY measure DESC)` in a CTE, then `WHERE rn <= N`. Use `DENSE_RANK` if ties should all be included.

**Q: What is the difference between `ROWS` and `RANGE`?**
`ROWS` frames by physical row count; `RANGE` frames by value, so rows with the same `ORDER BY` value are treated as one block. The default frame is `RANGE`, which is why running totals over tied values look "wrong" — use `ROWS`.

**Q: `LAG` / `LEAD` — what are they for?**
Read the previous / next row's value without a self-join: previous order date, days between orders, month-over-month growth (`(Revenue - LAG(Revenue)) / LAG(Revenue)`), "did the amount increase".

**Q: What does `PIVOT` need, and how do you do it without `PIVOT`?**
A source with exactly the grouping, spreading and aggregate columns, a static list of spreading values, and an aggregate. Without it: `SUM(CASE WHEN col = 'x' THEN val END) AS x` — portable and lets you add totals. Dynamic column lists: build the SQL with `STRING_AGG(QUOTENAME(...))` and `sp_executesql`.

**Q: Can a window function be used in `WHERE`?**
No — it is evaluated after `WHERE`/`GROUP BY`/`HAVING`. Compute it in a CTE or derived table and filter in the outer query.

## 5. Checklist

- [ ] I can write a chain of CTEs and explain the semicolon error
- [ ] I can explain CTE vs derived table vs temp table (scope, materialisation)
- [ ] I can write a recursive CTE for an org chart (down and up) and a number/date series, and set `MAXRECURSION`
- [ ] I can explain `ROW_NUMBER` vs `RANK` vs `DENSE_RANK` with the 65000 tie
- [ ] I can use `LAG/LEAD`, `FIRST_VALUE/LAST_VALUE` (with the right frame) and running totals with `ROWS`
- [ ] I can solve top-N per group, Nth highest salary, delete duplicates and gaps-and-islands from memory
- [ ] I can write a `PIVOT`, the same with `CASE`, a dynamic PIVOT and an `UNPIVOT` / `CROSS APPLY VALUES`
- [ ] I know why a window function cannot go in `WHERE` and how to fix it
