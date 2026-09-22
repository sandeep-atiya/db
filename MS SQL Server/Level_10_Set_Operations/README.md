# Level 10 — Set Operations

**Goal:** stack the results of two queries with `UNION`, `UNION ALL`, `INTERSECT` and `EXCEPT`, know the rules and the NULL behaviour, and use them for real jobs: contact lists, "compare two tables", and lookup lists built on the fly.

**Time:** ~1 hr · **Files:** `01_Practice.sql` → `Exercises.sql`

---

## 1. Concepts in plain words

A **JOIN** puts tables side by side (more *columns*). A **set operator** puts query results one under the other (more *rows*). Both queries must produce the same "shape" of row.

| Operator | Result | Duplicates | Typical use |
|----------|--------|------------|-------------|
| `UNION` | rows of A **plus** rows of B | **removed** (needs a sort/hash → slower; output looks sorted) | distinct city list from two tables |
| `UNION ALL` | rows of A plus rows of B | **kept** | contact list, stacking partitions, lookup lists — **default choice** when you know there are no duplicates |
| `INTERSECT` | rows in **both** A and B | removed | cities that have customers *and* an office |
| `EXCEPT` | rows in A that are **not** in B | removed | cities with customers but no office; **compare two tables** |

Worked on the dataset — `Customers.City` = Delhi, Mumbai, Delhi, Pune, Bangalore, Mumbai, Chennai, Delhi (8) · `Departments.Location` = Delhi, Mumbai, Delhi, Bangalore, Pune, Delhi (6):

| Query | Rows | Result |
|-------|------|--------|
| `Customers UNION Departments` | 5 | Bangalore, Chennai, Delhi, Mumbai, Pune |
| `Customers UNION ALL Departments` | 14 | all 8 + all 6 (Delhi six times) |
| `Customers INTERSECT Departments` | 4 | Bangalore, Delhi, Mumbai, Pune |
| `Customers EXCEPT Departments` | 1 | Chennai |
| `Departments EXCEPT Customers` | 0 | — |

**Order matters for `EXCEPT`**: `A EXCEPT B` ≠ `B EXCEPT A`. `UNION` and `INTERSECT` are symmetric.

**Which tool for which job**

| Need | Tool |
|------|------|
| Same-shaped rows from two sources in one list | `UNION ALL` (+ a literal "source" column) |
| Rows of A enriched with columns of B | `JOIN` |
| Which rows differ between two tables | `EXCEPT` both ways |
| Counts per key from two sources, key may exist on one side only | `UNION ALL` + `GROUP BY` (or `FULL OUTER JOIN`) |
| A small fixed list to join against | `UNION ALL SELECT …` or `(VALUES …) AS t (cols)` |

## 2. Syntax cheat-sheet

```sql
SELECT City     FROM dbo.Customers
UNION [ALL] | INTERSECT | EXCEPT
SELECT Location FROM dbo.Departments
ORDER BY City;                       -- ORDER BY once, at the END, using FIRST-query column names

-- Add a "source" column with a literal per branch
SELECT 'Employee' AS ContactType, EmployeeName AS Name, Email FROM dbo.Employees
UNION ALL
SELECT 'Customer', CustomerName, Email FROM dbo.Customers
ORDER BY ContactType, Name;          -- 20 rows

-- TOP / OFFSET per branch -> wrap the branch in a derived table (or CTE)
SELECT * FROM (SELECT TOP (2) EmployeeName AS Name, Salary AS Amount FROM dbo.Employees ORDER BY Salary DESC) AS e
UNION ALL
SELECT * FROM (SELECT TOP (2) ProductName, Price FROM dbo.Products ORDER BY Price DESC) AS p;

-- Compare two tables (classic): rows that differ, both ways
SELECT 'Only in original' AS Side, d.* FROM (SELECT * FROM dbo.Products EXCEPT SELECT * FROM dbo.L10_Products_Copy) AS d
UNION ALL
SELECT 'Only in copy',     d.* FROM (SELECT * FROM dbo.L10_Products_Copy EXCEPT SELECT * FROM dbo.Products) AS d;

-- Lookup list on the fly
SELECT s.Status, COUNT(o.OrderID) AS Orders
FROM (SELECT 1 AS SortOrder, 'Pending' AS Status
      UNION ALL SELECT 2, 'Completed'
      UNION ALL SELECT 3, 'Cancelled') AS s          -- or: (VALUES (1,'Pending'),(2,'Completed'),(3,'Cancelled')) AS s (SortOrder, Status)
LEFT JOIN dbo.Orders o ON o.Status = s.Status
GROUP BY s.Status, s.SortOrder ORDER BY s.SortOrder;  -- Pending 2, Completed 16, Cancelled 1

-- UNION ALL + GROUP BY instead of FULL OUTER JOIN (counts per city from two sources)
SELECT City, SUM(Emp) AS Employees, SUM(Cust) AS Customers
FROM (SELECT d.Location, 1, 0 FROM dbo.Employees e JOIN dbo.Departments d ON d.DepartmentID = e.DepartmentID
      UNION ALL
      SELECT City, 0, 1 FROM dbo.Customers) AS u (City, Emp, Cust)
GROUP BY City;                                        -- Chennai 0 / 1 appears without any COALESCE
```

**The rules**

| Rule | Detail |
|------|--------|
| Same number of columns | otherwise Msg 205 *"…must have an equal number of expressions…"* |
| Compatible types, position by position | `INT` vs a name → conversion error; `CAST` yourself |
| Column names come from the **first** SELECT | aliases in later branches are ignored |
| `ORDER BY` only once, at the end | and only by first-query names / positions |
| No `ORDER BY` / `TOP` / `OFFSET` inside a branch | wrap the branch in a derived table or CTE |
| Precedence | `INTERSECT` binds tighter; `UNION` / `EXCEPT` are equal and go **left to right** — always add parentheses when mixing |

**Precedence examples** (verified in `01_Practice.sql`, section 4)

| Expression | Evaluated as | Result |
|------------|--------------|--------|
| `SELECT 1 UNION SELECT 2 INTERSECT SELECT 2` | `1 UNION (2 INTERSECT 2)` | 1, 2 |
| `(SELECT 1 UNION SELECT 2) INTERSECT SELECT 2` | as written | 2 |
| `SELECT 1 UNION SELECT 2 EXCEPT SELECT 2` | `(1 UNION 2) EXCEPT 2` | 1 |
| `SELECT 2 EXCEPT SELECT 2 UNION SELECT 2` | `(2 EXCEPT 2) UNION 2` | 2 |

## 3. Gotchas (things that bite beginners)

- **`UNION` silently removes duplicates** — including "real" duplicate rows you wanted to keep (two different customers with the same name and NULL email). Use `UNION ALL` unless you *want* distinct.
- **NULLs are treated as EQUAL** by all four operators (they use "is not distinct from" logic). `SELECT NULL INTERSECT SELECT NULL` returns a row; `WHERE NULL = NULL` does not. Emails `UNION` → 18 rows (three NULLs collapse into one), `UNION ALL` → 20.
- **`UNION` output looks sorted, but that is a side effect** of de-duplication, not a guarantee. Add `ORDER BY`.
- **`ORDER BY Cust`** where `Cust` is an alias from the *second* query → *Invalid column name*. Use the first query's name.
- **`SELECT TOP (2) … ORDER BY … UNION …`** → *Incorrect syntax near 'UNION'*. Wrap it.
- **Every column of that derived table needs a name.** `(SELECT TOP (2) ProductName, Price, 'Product' FROM …) AS p` → *No column name was specified for column 3 of 'p'*. Write `'Product' AS Kind` or `AS p (Name, Amount, Kind)`.
- **Mixing operators without parentheses**: `1 UNION 2 INTERSECT 2` = `{1, 2}` (INTERSECT first), not `{2}`.
- `EXCEPT` compares **all** selected columns; an `IDENTITY` or timestamp column that differs will make every row "different" — select only the business columns.
- `UNION ALL` of many branches is fine, but each branch is a separate scan; for very wide tables consider a single query with `CASE`.

## 4. Interview questions

**Q: `UNION` vs `UNION ALL`?**
Both stack results. `UNION` removes duplicate rows (extra sort/hash work); `UNION ALL` keeps everything and is faster. Use `UNION ALL` unless you need distinct rows.

**Q: What are the rules for using `UNION`?**
Same number of columns, compatible data types position by position, column names from the first query, one `ORDER BY` at the end, no `TOP/ORDER BY` inside a branch without a derived table.

**Q: `UNION` vs `JOIN`?**
`UNION` adds **rows** from queries of the same shape; `JOIN` adds **columns** by matching rows on a key.

**Q: What does `INTERSECT` do? And `EXCEPT`?**
`INTERSECT` returns distinct rows present in both results. `EXCEPT` returns distinct rows in the first result that are not in the second — order of the queries matters.

**Q: How do you find rows that differ between two tables with the same structure?**
`(A EXCEPT B) UNION ALL (B EXCEPT A)` — each side in a derived table, optionally with a label column. Empty result = identical.

**Q: How do set operators treat NULL?**
As equal to each other (unlike `=`). Two NULL rows are duplicates for `UNION`, match for `INTERSECT`, and cancel for `EXCEPT`.

**Q: Can you use `ORDER BY` inside each SELECT of a UNION?**
No. Only one `ORDER BY` at the end for the whole result. To sort/limit a branch, put it in a derived table or CTE with `TOP` / `OFFSET-FETCH`.

**Q: What is the precedence of set operators?**
`INTERSECT` is evaluated before `UNION` and `EXCEPT`; `UNION` and `EXCEPT` have equal precedence and run left to right. Use parentheses to be explicit.

**Q: How can `UNION ALL` replace a `FULL OUTER JOIN`?**
Stack both sources with a 0 in the "other" measure column, then `GROUP BY` the key and `SUM`. Keys present on only one side still appear, with no `COALESCE` needed.

**Q: When would you build a table with `UNION ALL SELECT 'x'` or `VALUES`?**
For small lookup/reference lists inside a query (status names with a sort order, month names, test rows) without creating a table.

**Q: `EXCEPT` vs `NOT IN` / `NOT EXISTS`?**
All three say "in A but not in B". `EXCEPT` compares **whole rows** (every selected column), removes duplicates and treats NULLs as equal. `NOT EXISTS` compares the columns you choose and keeps duplicates. `NOT IN` returns nothing if the list contains a NULL.

**Q: How do you show the top 2 rows of two different tables in one result?**
`TOP` + `ORDER BY` cannot sit directly in a UNION branch. Put each branch in a derived table or CTE: `SELECT * FROM (SELECT TOP (2) … ORDER BY …) AS a UNION ALL SELECT * FROM (SELECT TOP (2) … ORDER BY …) AS b`, and give every column a name.

## 5. Checklist

- [ ] I can explain `UNION`, `UNION ALL`, `INTERSECT`, `EXCEPT` in one sentence each
- [ ] I know the five rules (columns, types, names, `ORDER BY`, `TOP` per branch)
- [ ] I know that set operators treat NULLs as equal
- [ ] I know `INTERSECT` binds tighter and I write parentheses when mixing
- [ ] I can build a contact list with a `Type` column from two tables
- [ ] I can compare two tables with `EXCEPT` both ways
- [ ] I can build a lookup list with `UNION ALL` / `VALUES` and join to it
- [ ] I can replace a `FULL OUTER JOIN` with `UNION ALL + GROUP BY`
