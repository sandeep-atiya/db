# Level 07 — Aggregation (GROUP BY / HAVING)

**Goal:** turn many rows into summary numbers correctly — know exactly how `COUNT`, `SUM`, `AVG` treat NULL, when to use `WHERE` vs `HAVING`, and how to get several filtered counts in one query with conditional aggregation.

**Time:** ~1.5 hr · **Files:** `01_Practice_Aggregates.sql` → `02_Practice_Advanced_Grouping.sql` → `Exercises.sql`

---

## 1. Concepts in plain words

| Term | Meaning |
|------|---------|
| **Aggregate function** | Looks at many rows, returns **one value**: `COUNT`, `SUM`, `AVG`, `MIN`, `MAX`, `STRING_AGG`. |
| **No `GROUP BY`** | The whole (filtered) table is **one group** → exactly one result row. |
| **`GROUP BY col`** | One result row **per distinct value** of `col`. NULL is its own group. Aggregates work *inside* each group. |
| **The golden rule** | Every column in `SELECT` must be **either** in `GROUP BY` **or** inside an aggregate. Otherwise Msg 8120. |
| **`WHERE`** | Filters **rows** *before* grouping. Cannot use aggregates. |
| **`HAVING`** | Filters **groups** *after* grouping. Can use aggregates. Works without `GROUP BY` too (whole table = one group). |
| **Conditional aggregation** | A `CASE` *inside* the aggregate: `SUM(CASE WHEN Status = 'Completed' THEN 1 ELSE 0 END)`. Several filtered counts in one pass. |
| **`ROLLUP` / `CUBE` / `GROUPING SETS`** | Extra subtotal rows in the same result. `GROUPING(col) = 1` marks the subtotal rows. |

**Logical processing order** (explains almost every error in this level):

```
FROM → JOIN → WHERE → GROUP BY → HAVING → SELECT (aliases born here) → ORDER BY → TOP/OFFSET
```

So: aliases work in `ORDER BY` but **not** in `WHERE` / `GROUP BY` / `HAVING`; aggregates work in `HAVING` / `SELECT` / `ORDER BY` but **not** in `WHERE`.

### NULL behaviour (learn this table by heart)

| Function | NULLs are… | Example on `Employees` (12 rows, 1 NULL dept) |
|----------|-----------|------------------------------------------------|
| `COUNT(*)` | **counted** (counts rows) | 12 |
| `COUNT(col)` | ignored | `COUNT(DepartmentID)` = 11 |
| `COUNT(DISTINCT col)` | ignored, duplicates removed | `COUNT(DISTINCT DepartmentID)` = 5 |
| `SUM / AVG / MIN / MAX` | ignored | `AVG` = `SUM(col) / COUNT(col)`, **not** `/ COUNT(*)` |
| Over **zero rows** | `COUNT` → 0, everything else → NULL | |

## 2. Syntax cheat-sheet

```sql
-- whole table
SELECT COUNT(*), COUNT(Email), COUNT(DISTINCT City), SUM(x), AVG(x), MIN(d), MAX(s) FROM dbo.T;

-- grouped
SELECT  col1, YEAR(d) AS Yr, COUNT(*) AS Cnt, SUM(amt) AS Total
FROM    dbo.T
WHERE   amt > 0                          -- rows, before grouping
GROUP BY col1, YEAR(d)                   -- same expression as in SELECT
HAVING  SUM(amt) > 1000                  -- groups, after grouping (repeat the expression, no alias)
ORDER BY Total DESC;                     -- alias OK here

-- integer AVG trap
AVG(IntCol)          -- truncated INT      AVG(IntCol * 1.0)   -- decimal

-- conditional aggregation
SUM(CASE WHEN Status = 'Completed' THEN 1 ELSE 0 END)        AS Completed,
COUNT(CASE WHEN Status = 'Cancelled' THEN 1 END)             AS Cancelled,   -- no ELSE -> NULL -> not counted
SUM(CASE WHEN Status = 'Completed' THEN TotalAmount ELSE 0 END) AS CompletedRevenue

-- ratio of sums (weighted), not AVG of ratios
SUM(Quantity * UnitPrice) / SUM(Quantity)

-- list per group
STRING_AGG(Name, ', ') WITHIN GROUP (ORDER BY Name)

-- subtotals (advanced)
GROUP BY ROLLUP(a, b)                    -- (a,b) (a) ()
GROUP BY CUBE(a, b)                      -- (a,b) (a) (b) ()
GROUP BY GROUPING SETS ((a), (b), ())    -- exactly the levels you list
CASE WHEN GROUPING(a) = 1 THEN 'ALL' ELSE a END

-- top-N groups
SELECT TOP (3) [WITH TIES] key, SUM(x) AS Total FROM ... GROUP BY key ORDER BY Total DESC;
```

## 3. Gotchas

- **`COUNT(*)` with `LEFT JOIN` counts the unmatched row as 1.** Hina has no orders but `COUNT(*)` says 1. Use `COUNT(o.OrderID)`.
- **`AVG` of an `INT` column is an `INT`**: `AVG(Stock)` = 159, not 159.55. Multiply by `1.0` or `CAST`.
- **`AVG` ignores NULL rows entirely.** If NULL should mean zero, write `AVG(ISNULL(col, 0))`.
- **Msg 8120** "column is invalid in the select list…": add the column to `GROUP BY`, or wrap it in an aggregate (`MIN`, `STRING_AGG`).
- **Alias in `HAVING` → Msg 207 "Invalid column name".** Repeat the aggregate expression.
- **Aggregate in `WHERE` → Msg 147.** Move it to `HAVING`.
- **`GROUP BY` an expression → the identical expression must be in `SELECT`.** `SELECT OrderDate ... GROUP BY YEAR(OrderDate)` fails.
- **`HAVING` without aggregate works but is wasteful** — a row filter belongs in `WHERE` (fewer rows to group).
- **Average of averages ≠ overall average.** `AVG(UnitPrice)` gives every line the same weight; `SUM(qty*price)/SUM(qty)` weighs by quantity. Interviewers love this one.
- **`STRING_AGG` order is random** without `WITHIN GROUP (ORDER BY …)`; it also skips NULL values.
- **`TOP (1)` hides ties.** Two customers have 4 orders — use `TOP (1) WITH TIES` or window functions (Level 11).
- **`ROLLUP` shows NULL for subtotal rows** — if the data itself has NULLs (e.g. `DepartmentID`), use `GROUPING()` to tell the two apart.
- **`DISTINCT` inside `SUM`/`AVG` exists but is rarely what you want** (`SUM(DISTINCT Salary)` would count Amit and Pooja's 65000 once).

## 4. Interview questions

**Q: `COUNT(*)` vs `COUNT(1)` vs `COUNT(column)`?**
`COUNT(*)` and `COUNT(1)` both count rows (identical performance — the optimiser treats them the same). `COUNT(column)` counts rows where the column is NOT NULL. `COUNT(DISTINCT column)` counts different non-NULL values.

**Q: `WHERE` vs `HAVING`?**
`WHERE` filters individual rows before grouping and cannot contain aggregates. `HAVING` filters groups after `GROUP BY` and is where aggregate conditions go. Both can be in one query. `HAVING` without `GROUP BY` treats the whole table as one group.

**Q: Why does `SELECT EmployeeName, MAX(Salary) FROM Employees` fail?**
`MAX` collapses 12 rows into one, but `EmployeeName` has 12 values — SQL cannot pick one. Every non-aggregated column must be in `GROUP BY` (Msg 8120). Use `TOP (1) … ORDER BY Salary DESC` or a subquery.

**Q: Can you use a column alias in `WHERE` / `GROUP BY` / `HAVING`?**
No — those clauses run before `SELECT` where the alias is defined. Only `ORDER BY` (which runs after `SELECT`) sees aliases.

**Q: How does `AVG` treat NULL? What is `AVG(10, 20, NULL)`?**
NULLs are ignored: 15 (= 30 / 2), not 10 (= 30 / 3). Use `AVG(ISNULL(col, 0))` if NULL means zero.

**Q: How do you count Completed and Cancelled orders per customer in one query?**
Conditional aggregation: `SUM(CASE WHEN Status = 'Completed' THEN 1 ELSE 0 END)` and the same for Cancelled, with `GROUP BY CustomerID`. One pass, no self-joins, no subqueries.

**Q: What is the difference between `ROLLUP` and `CUBE`?**
`ROLLUP(a, b)` gives hierarchical subtotals: `(a,b)`, `(a)`, grand total. `CUBE(a, b)` gives all combinations, adding `(b)` subtotals as well. `GROUPING SETS` lets you list exactly the levels you want. `GROUPING(col)` returns 1 on the subtotal rows.

**Q: How do you get the top 3 customers by revenue?**
`SELECT TOP (3) CustomerID, SUM(TotalAmount) AS Rev FROM Orders GROUP BY CustomerID ORDER BY Rev DESC`. Add `WITH TIES` to include equal values at the cut-off.

**Q: What is the logical order of a `SELECT` statement?**
`FROM → WHERE → GROUP BY → HAVING → SELECT → ORDER BY → TOP`. It explains why aliases fail in `WHERE`, why aggregates fail in `WHERE`, and why `HAVING` sees aggregates.

**Q: Average of a ratio vs ratio of sums — which is right?**
Depends on the question, but "average price per unit sold" means revenue / units = `SUM(qty*price) / SUM(qty)`. `AVG(price)` treats a 100-unit line and a 1-unit line equally and is usually wrong for business reporting.

## 5. Checklist

- [ ] I can explain the NULL behaviour of `COUNT(*)`, `COUNT(col)`, `COUNT(DISTINCT col)`, `SUM`, `AVG`
- [ ] I know the integer `AVG` trap and how to fix it
- [ ] I can group by one column, several columns and an expression like `YEAR(OrderDate)`
- [ ] I can explain Msg 8120 and fix it three ways
- [ ] I know the logical processing order and therefore where aliases and aggregates are allowed
- [ ] I can write `WHERE` and `HAVING` in the same query and say what each one filters
- [ ] I can write conditional aggregation (`SUM(CASE …)`) for side-by-side counts
- [ ] I can do a `ROLLUP` with a labelled total row and a top-N-groups query
