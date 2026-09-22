# Level 09 — Subqueries

**Goal:** write a query inside a query with confidence — know the four places a subquery can sit, when it must return one value, how `IN / ANY / ALL / EXISTS` differ, why correlated subqueries "loop", and the `NOT IN + NULL` trap that every interviewer asks about.

**Time:** ~1.5 hr · **Files:** `01_Practice_Subquery_Basics.sql` → `02_Practice_Subquery_Advanced.sql` → `Exercises.sql`

---

## 1. Concepts in plain words

| Term | Meaning |
|------|---------|
| **Subquery** | A `SELECT` inside another statement, always in `( )`. The inner query produces a value, a list or a table that the outer query uses. |
| **Scalar subquery** | Returns exactly **1 row, 1 column**. Can be used anywhere a value can: `SELECT` list, `WHERE Salary > (…)`, `SET Price = (…)`. Returns `NULL` if it finds no row; **errors** if it finds more than one. |
| **Multi-row subquery** | Returns one column, many rows. Used with `IN`, `NOT IN`, `ANY / SOME`, `ALL`. |
| **Derived table** | A subquery in the `FROM` clause. It behaves like a table and **must have an alias**. |
| **Correlated subquery** | The inner query refers to a column of the outer query (`WHERE x.DepartmentID = e.DepartmentID`). Logically it runs **once per outer row** — think "loop". |
| **`EXISTS`** | `TRUE` as soon as the subquery finds one row. What you select inside is ignored (`SELECT 1` is the convention). `NOT EXISTS` is the safest **anti-join**. |
| **Nested subquery** | A subquery inside a subquery. Read from the inside out. Two levels is normal; more usually means a JOIN/CTE would be clearer. |
| **Semi-join / anti-join** | "Rows of A that have (semi) / do not have (anti) a match in B". `IN`, `EXISTS`, `NOT EXISTS` all express this; the optimizer turns them into the same plan shapes. |

**Where a subquery can appear**

| Place | Must return | Example |
|-------|-------------|---------|
| `SELECT` list | 1 value | `(SELECT AVG(Salary) FROM dbo.Employees) AS CompanyAvg` |
| `FROM` | a table (needs alias) | `FROM (SELECT DepartmentID, AVG(Salary) AS A FROM … GROUP BY …) AS da` |
| `WHERE` | 1 value or a list | `WHERE Salary > (…)`, `WHERE DepartmentID IN (…)`, `WHERE EXISTS (…)` |
| `HAVING` | 1 value or a list | `HAVING AVG(Salary) > (SELECT AVG(Salary) FROM …)` |
| `UPDATE … SET`, `DELETE … WHERE` | as above | `SET Price = (SELECT …)`, `WHERE ProductID NOT IN (SELECT …)` |

**How the engine runs them**

| Kind | Runs | Result reused? | Example |
|------|------|----------------|---------|
| Non-correlated (scalar or list) | once, before the outer query | yes, for every outer row | `WHERE Salary > (SELECT AVG(Salary) FROM dbo.Employees)` |
| Correlated | logically once **per outer row** (the optimizer may rewrite it as a join) | no | `WHERE x.DepartmentID = e.DepartmentID` |
| `EXISTS` | per outer row, but **stops at the first match** | no | `WHERE EXISTS (SELECT 1 FROM dbo.Orders o WHERE o.CustomerID = c.CustomerID)` |
| Derived table | once, as a table in `FROM` | joined like any table | `FROM (SELECT … GROUP BY …) AS t` |

Reading a nested subquery — from the **inside out**: *products in Furniture* → *orders containing them* → *customers who placed those orders* (4 customers on our data).

## 2. Syntax cheat-sheet

```sql
-- Scalar: above company average
SELECT EmployeeName, Salary FROM dbo.Employees
WHERE Salary > (SELECT AVG(Salary) FROM dbo.Employees);                  -- 5 rows

-- IN / NOT IN (one column list)
WHERE DepartmentID IN (SELECT DepartmentID FROM dbo.Departments WHERE Location = 'Delhi');
WHERE ProductID NOT IN (SELECT ProductID FROM dbo.OrderDetails);          -- only if the list has NO NULLs

-- ANY / SOME / ALL
WHERE Salary > ALL (SELECT Salary FROM dbo.Employees WHERE DepartmentID = 2);  -- > MAX of Sales -> Sneha, Rahul
WHERE Salary > ANY (SELECT Salary FROM dbo.Employees WHERE DepartmentID = 2);  -- > MIN of Sales
WHERE DepartmentID = ANY (SELECT …)          -- same as IN

-- Correlated: above OWN department average
SELECT e.EmployeeName FROM dbo.Employees e
WHERE e.Salary > (SELECT AVG(x.Salary) FROM dbo.Employees x WHERE x.DepartmentID = e.DepartmentID);

-- EXISTS / NOT EXISTS (always correlated)
SELECT c.CustomerName FROM dbo.Customers c
WHERE NOT EXISTS (SELECT 1 FROM dbo.Orders o WHERE o.CustomerID = c.CustomerID);   -- Hina Khan

-- Derived table with aggregate, then JOIN (keeps parents with 0)
SELECT c.CustomerName, ISNULL(t.Cnt, 0) AS Orders
FROM dbo.Customers c
LEFT JOIN (SELECT CustomerID, COUNT(*) AS Cnt FROM dbo.Orders GROUP BY CustomerID) AS t
       ON t.CustomerID = c.CustomerID;

-- Subquery in HAVING
SELECT DepartmentID, AVG(Salary) FROM dbo.Employees GROUP BY DepartmentID
HAVING AVG(Salary) > (SELECT AVG(Salary) FROM dbo.Employees);            -- IT, Finance

-- UPDATE / DELETE with subquery (on a copy!)
UPDATE dbo.L09_Products SET Price = Price * 1.1
WHERE ProductID NOT IN (SELECT ProductID FROM dbo.OrderDetails);
DELETE p FROM dbo.L09_Products p
WHERE NOT EXISTS (SELECT 1 FROM dbo.OrderDetails od WHERE od.ProductID = p.ProductID);

-- 2nd highest salary (classic)
SELECT MAX(Salary) FROM dbo.Employees
WHERE Salary < (SELECT MAX(Salary) FROM dbo.Employees);                  -- 85000
```

**Choosing the tool**

| You need… | Use |
|-----------|-----|
| One computed value to compare with | scalar subquery with an aggregate (`MAX`, `AVG`) |
| "is in this list" | `IN` (or `= ANY`) |
| "is NOT in this list" | `NOT EXISTS` (NULL-safe) — or `NOT IN` + `IS NOT NULL` |
| "bigger than every value" | `> ALL` or `> (SELECT MAX …)` |
| columns from both tables | `JOIN` (then `DISTINCT`/`GROUP BY` if 1-to-many) |
| a per-row lookup | correlated subquery — or a window function (Level 11) |

## 3. Gotchas (things that bite beginners)

- **`NOT IN` with a NULL in the list returns NOTHING.** `x NOT IN (1, NULL)` = `x <> 1 AND x <> NULL` = `UNKNOWN`. `Departments NOT IN (SELECT DepartmentID FROM Employees)` gives 0 rows because Anjali's DepartmentID is NULL. Fix: `WHERE DepartmentID IS NOT NULL` inside, or use `NOT EXISTS`.
- **"Subquery returned more than 1 value"** (Msg 512): a scalar position got 2+ rows. It only appears when the *data* has duplicates, so it can pass in dev and fail in prod. Use an aggregate, `IN`, or `ALL/ANY`.
- **A derived table must have an alias** — `FROM (SELECT …)` alone is a syntax error.
- **`> ALL` against an EMPTY list is TRUE for every row**; `> (SELECT MAX …)` of an empty set compares with NULL and returns nothing. Different results for the same intent (Legal has no employees).
- **Correlated subquery + NULL:** `x.DepartmentID = e.DepartmentID` never matches when `e.DepartmentID` is NULL, so Anjali gets a NULL average and drops out of `Salary > (…)`.
- **JOIN duplicates rows** when the child has many rows (Customers JOIN Orders = 19 rows, not 7). For "customers who have orders" use `EXISTS` or `IN`, not a JOIN.
- **A subquery in `IN` must return exactly ONE column.**
- **Every column of a derived table needs a name.** `FROM (SELECT TOP (2) ProductName, Price, 'Product' FROM …) AS p` fails with *No column name was specified for column 3* — write `'Product' AS Kind` or `AS p (Name, Amount, Kind)`.
- Correlated subqueries in the `SELECT` list run once per row — fine for small tables, slow on millions of rows. Prefer a derived table with `GROUP BY` + JOIN, or window functions.
- Always run the `SELECT` version of an `UPDATE/DELETE … WHERE (subquery)` first and check the row count.

## 4. Interview questions

**Q: What is a subquery? Where can it be used?**
A query nested inside another. In the `SELECT` list (scalar), `FROM` (derived table, needs alias), `WHERE` / `HAVING` (scalar, `IN`, `ANY/ALL`, `EXISTS`), and in `INSERT/UPDATE/DELETE`.

**Q: Correlated vs non-correlated subquery?**
Non-correlated runs once and its result is reused. Correlated references the outer row and logically runs once per outer row (e.g. "salary above own department average").

**Q: `IN` vs `EXISTS` — which is faster?**
Usually the same plan (semi join). `EXISTS` stops at the first match and is NULL-safe; `IN` is more readable for a plain value list. Use `NOT EXISTS` rather than `NOT IN` when the column can be NULL.

**Q: Why does `NOT IN` return no rows when the subquery contains a NULL?**
Because `NOT IN` expands to `<> v1 AND <> v2 … AND <> NULL`; the comparison with NULL is UNKNOWN, so no row is TRUE. Fix with `IS NOT NULL` or `NOT EXISTS`.

**Q: Difference between `ANY`, `SOME` and `ALL`?**
`ANY` = `SOME`: true if the comparison holds for at least one value (`> ANY` = `> MIN`). `ALL`: must hold for every value (`> ALL` = `> MAX`). `= ANY` is `IN`.

**Q: What error do you get when a scalar subquery returns more than one row, and how do you fix it?**
Msg 512 "Subquery returned more than 1 value". Fix by aggregating (`MAX/MIN`), or switching to `IN` / `ALL` / `ANY`.

**Q: What is a derived table? How is it different from a CTE?**
A subquery in `FROM` with an alias, used once, read inside-out. A CTE (Level 11) is the same thing with a name on top, read top-down, reusable in the same statement and can be recursive.

**Q: How do you find the 2nd (or Nth) highest salary with a subquery?**
`SELECT MAX(Salary) FROM Employees WHERE Salary < (SELECT MAX(Salary) FROM Employees)` → 85000. General N: `WHERE N-1 = (SELECT COUNT(DISTINCT Salary) FROM Employees x WHERE x.Salary > e.Salary)`. Modern: `DENSE_RANK()` / `OFFSET-FETCH`.

**Q: When would you use a JOIN instead of a subquery?**
When you need columns from both tables in the output, or you aggregate over the child rows. For pure filtering ("has at least one order") `EXISTS` / `IN` are clearer and avoid duplicate rows.

**Q: Can you use a subquery in `UPDATE` or `DELETE`?**
Yes: in `WHERE` (`IN`, `EXISTS`), and a correlated scalar subquery in `SET`. Test the condition as a `SELECT` first.

**Q: What are a semi-join and an anti-join?**
Semi-join: rows of A that have at least one match in B (`IN`, `EXISTS`) — each A row once, no B columns. Anti-join: rows of A with no match in B (`NOT EXISTS`, `NOT IN` when the list has no NULLs, or `LEFT JOIN … WHERE b.key IS NULL`).

**Q: Correlated subquery or window function for "salary above department average"?**
Both return Rahul, Priya, Sneha, Karan. The window version (`AVG(Salary) OVER (PARTITION BY DepartmentID)` in a CTE, Level 11) reads the table once and can show the average next to each row; the correlated version is shorter for a pure filter. They treat a NULL department differently (own partition vs. no match).

## 5. Checklist

- [ ] I can name the four places a subquery can appear and what each must return
- [ ] I can write a scalar subquery and explain the "more than 1 value" error
- [ ] I can use `IN`, `NOT IN`, `ANY`, `ALL` and say what each means in words
- [ ] I can write a correlated subquery and explain that it runs per outer row
- [ ] I can write `EXISTS` / `NOT EXISTS` for "has / has no related rows"
- [ ] I can explain the `NOT IN` + NULL trap and fix it two ways
- [ ] I can put a subquery in `HAVING`, `FROM` (with alias), `UPDATE` and `DELETE`
- [ ] I can find the Nth highest salary with a subquery
