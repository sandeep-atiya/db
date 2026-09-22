# Level 08 — Joins

**Goal:** combine rows from two or more tables correctly — pick the right join type, keep the "optional" side with `LEFT JOIN`, avoid the ON-vs-WHERE and row-explosion traps, and join 5 tables without fear.

**Time:** ~2 hr · **Files:** `01_Practice_Basic_Joins.sql` → `02_Practice_Join_Traps.sql` → `Exercises.sql`

---

## 1. Concepts in plain words

**Why joins exist.** Normalisation stores each fact once: the department name lives in `Departments`, and `Employees` only keeps the `DepartmentID`. A `JOIN` re-assembles the pieces by matching key values. The `ON` clause says *how* rows match; the join *type* says *what to do with rows that do not match*.

### Join types (Venn diagram in words)

Picture two overlapping circles, **A** (left table) and **B** (right table). The overlap = rows whose keys match.

| Join | Keeps | In words | On our data (`Employees` A, `Departments` B) |
|------|-------|----------|---------------------------------------------|
| **INNER JOIN** | overlap only | Only rows with a partner on both sides | 11 rows — Anjali (no dept) and Legal (no staff) both missing |
| **LEFT JOIN** | all of A + overlap | Every A row; B columns NULL when no partner | 12 rows — Anjali appears with NULL department |
| **RIGHT JOIN** | all of B + overlap | Every B row; A columns NULL when no partner | 12 rows — Legal appears with NULL employee |
| **FULL OUTER JOIN** | all of A + all of B | Everything; NULLs on whichever side is missing | 13 rows — Anjali *and* Legal |
| **CROSS JOIN** | A × B | Every row of A with every row of B, no `ON` | 12 × 6 = 72 rows |
| **SELF JOIN** | (any type) | A table joined to itself with two aliases | employee → manager via `ManagerID` |
| **Anti-join** | A minus overlap | `LEFT JOIN … WHERE B.key IS NULL` | Webcam (never ordered), Hina (no orders), Legal |
| **Semi-join** | A ∩ overlap, no duplicates | `WHERE EXISTS (…)` | customers who ordered — each once |

`JOIN` alone means `INNER JOIN`. `LEFT JOIN` = `LEFT OUTER JOIN`. Most teams write only `INNER`, `LEFT`, `FULL`, `CROSS` — a `RIGHT JOIN` is a `LEFT JOIN` with the tables swapped.

### How many rows come back? (classic interview)

Tables **A** with *n* rows and **B** with *m* rows:

| Join | Minimum | Maximum | Typical (unique key on B, every A row matches) |
|------|---------|---------|-----------------------------------------------|
| INNER | 0 | n × m | n |
| LEFT | **n** (never fewer than the left table) | n × m | n |
| RIGHT | m | n × m | m |
| FULL | max(n, m) | n + m (nothing matches) … n × m (everything matches everything) | n |
| CROSS | n × m | n × m | n × m — always |

Trick question: **A** has values `1, 1, 1` and **B** has `1, 1`. `INNER JOIN` on the value returns **6** rows (3 × 2), `LEFT` 6, `CROSS` 6. Duplicates multiply.

## 2. Syntax cheat-sheet

```sql
-- always: alias every table, prefix every column, one ON per JOIN
SELECT e.EmployeeName, d.DepartmentName
FROM   dbo.Employees e
INNER JOIN dbo.Departments d ON d.DepartmentID = e.DepartmentID;

FROM dbo.Employees e LEFT  JOIN dbo.Departments d ON d.DepartmentID = e.DepartmentID   -- all employees
FROM dbo.Employees e RIGHT JOIN dbo.Departments d ON d.DepartmentID = e.DepartmentID   -- all departments
FROM dbo.Employees e FULL  JOIN dbo.Departments d ON d.DepartmentID = e.DepartmentID   -- both
FROM dbo.L08_Sizes s CROSS JOIN dbo.L08_Colors c                                     -- no ON

-- self join (two aliases of the same table)
FROM dbo.Employees e LEFT JOIN dbo.Employees m ON m.EmployeeID = e.ManagerID

-- 5 tables: follow the foreign keys, LEFT where the key can be NULL
FROM dbo.Orders o
JOIN      dbo.Customers    c  ON c.CustomerID   = o.CustomerID
LEFT JOIN dbo.Employees    e  ON e.EmployeeID   = o.EmployeeID      -- NULL for online orders
LEFT JOIN dbo.Departments  d  ON d.DepartmentID = e.DepartmentID
JOIN      dbo.OrderDetails od ON od.OrderID     = o.OrderID
JOIN      dbo.Products     p  ON p.ProductID    = od.ProductID

-- filter on the RIGHT table of an outer join goes in ON, not WHERE
LEFT JOIN dbo.Orders o ON o.CustomerID = c.CustomerID AND o.Status = 'Completed'

-- anti-join / semi-join
LEFT JOIN dbo.OrderDetails od ON od.ProductID = p.ProductID  WHERE od.OrderDetailID IS NULL
WHERE EXISTS (SELECT 1 FROM dbo.Orders o WHERE o.CustomerID = c.CustomerID)

-- non-equi join (ranges) and multiple conditions
JOIN dbo.L08_SalaryBands b ON e.Salary BETWEEN b.MinSalary AND b.MaxSalary
JOIN dbo.Orders o2 ON o2.CustomerID = o1.CustomerID AND o2.OrderID > o1.OrderID

-- join + WHERE + GROUP BY
SELECT p.Category, SUM(od.Quantity * od.UnitPrice) AS Revenue
FROM dbo.OrderDetails od JOIN dbo.Products p ON p.ProductID = od.ProductID
                         JOIN dbo.Orders   o ON o.OrderID   = od.OrderID
WHERE o.Status = 'Completed'
GROUP BY p.Category;
```

## 3. Gotchas

- **WHERE on the right table kills a LEFT JOIN.** `LEFT JOIN Orders o … WHERE o.Status = 'Completed'` drops Hina (her `o.Status` is NULL). Put that condition in `ON`. For `INNER JOIN` it makes no difference.
- **NULL keys never match**, not even NULL = NULL. Order 1019 (`EmployeeID NULL`) vanishes from `Orders JOIN Employees`; Anjali vanishes from `Employees JOIN Departments`. Use `LEFT JOIN` if those rows matter.
- **One-to-many joins multiply rows.** `Customers JOIN Orders` has 19 rows, not 8. `SUM(o.TotalAmount)` after joining `OrderDetails` gives 824 000 instead of 618 000. Fix: aggregate at the child level, aggregate the child first in a subquery, `COUNT(DISTINCT …)`, or use `EXISTS` when you only need "has a match".
- **`COUNT(*)` after a LEFT JOIN counts the unmatched row as 1.** Use `COUNT(right.key)`.
- **An INNER JOIN after a LEFT JOIN can undo the LEFT.** `Customers LEFT JOIN Orders JOIN Employees` drops Hina again (and order 1019). Once optional, stay `LEFT` down the chain.
- **Join order is irrelevant for INNER, decisive for OUTER.** `Customers LEFT JOIN Orders` = 20 rows; `Orders LEFT JOIN Customers` = 19.
- **Anti-join: test a NOT NULL column** of the right table (its PK), never a nullable one, or real rows leak into the "no match" result.
- **Old comma joins** (`FROM A, B WHERE A.k = B.k`) work but hide the condition; forgetting the `WHERE` gives a silent cross product (72 rows). `*=` / `=*` are gone since 2012. Write explicit `JOIN … ON`.
- **`USING (col)` and `NATURAL JOIN` do not exist in T-SQL** — "Incorrect syntax near 'USING'". Always `ON`.
- **Ambiguous column names** ("Email" exists in both `Employees` and `Customers`) → Msg 209. Prefix everything.
- **Self join needs two different aliases** (`e` and `m`); `ManagerID` of the head is NULL, so use `LEFT JOIN` to keep the heads.
- **CROSS JOIN is useful on purpose**: months × departments gives a complete grid so reports show 0 instead of a missing row.

## 4. Interview questions

**Q: Difference between INNER, LEFT, RIGHT and FULL join?**
INNER: only matching rows. LEFT: all rows of the left table plus matches (NULLs where none). RIGHT: same for the right table. FULL: all rows of both, NULL-padded on either side.

**Q: A LEFT JOIN returns fewer rows than the left table has. Why?**
It cannot — unless a filter on the right table sits in `WHERE`, which turns it into an INNER JOIN. Move that predicate into the `ON` clause.

**Q: Where should the condition go: ON or WHERE?**
INNER JOIN: no difference. OUTER JOIN: conditions on the *optional* (outer) table go in `ON`; conditions on the preserved table can go in `WHERE`.

**Q: How do you find rows in A with no match in B?**
`LEFT JOIN B ON … WHERE B.PK IS NULL` (anti-join) or `WHERE NOT EXISTS (SELECT 1 FROM B WHERE B.k = A.k)`. Avoid `NOT IN` when the subquery column can be NULL (Level 09).

**Q: What is a self join? Give an example.**
Joining a table to itself using two aliases, e.g. `Employees e LEFT JOIN Employees m ON m.EmployeeID = e.ManagerID` to list each employee with their manager's name.

**Q: What is a CROSS JOIN and when is it useful?**
Cartesian product: every row of A with every row of B (n × m), no `ON`. Useful for generating combinations (sizes × colours) or a full calendar/department grid to fill with zeros.

**Q: Tables A (n rows) and B (m rows): how many rows do INNER / LEFT / CROSS return?**
CROSS: exactly n × m. INNER: 0 to n × m depending on matches (n if B's key is unique and every A row matches). LEFT: at least n, at most n × m. With duplicate keys on both sides the counts multiply (3 × 2 = 6).

**Q: Why does my total double after adding a join?**
One-to-many: each parent row repeats once per child. Summing a parent column then over-counts. Sum the child column, pre-aggregate the child in a derived table/CTE, or use `EXISTS` if you only need existence.

**Q: Is `JOIN … USING` valid in SQL Server?**
No. T-SQL requires `ON`. `NATURAL JOIN` is not supported either.

**Q: What is a non-equi join?**
A join whose `ON` uses something other than `=`: `BETWEEN` (salary bands), `<`, `>`, `<>`. Example: `ON e.Salary BETWEEN b.MinSalary AND b.MaxSalary`.

**Q: Does the order of tables in a query matter?**
Not for INNER joins (the optimiser reorders them). For OUTER joins yes — the left/right position decides which rows are preserved, and an INNER join later in the chain can remove rows a LEFT join kept.

**Q: How do you join more than two tables?**
Add one `JOIN … ON` per table, each `ON` linking the new table to one already in the query, following the foreign keys (Orders → Customers, Orders → Employees → Departments, Orders → OrderDetails → Products).

## 5. Checklist

- [ ] I can explain INNER / LEFT / RIGHT / FULL / CROSS with the Venn picture and give the row counts for n and m rows
- [ ] I can write a LEFT JOIN that keeps Anjali / Hina / Legal and turn a RIGHT JOIN into a LEFT JOIN
- [ ] I can write a self join for employee → manager
- [ ] I can join 5 tables following the foreign keys and know which link must be LEFT
- [ ] I know why a WHERE on the right table breaks an outer join and where to put it instead
- [ ] I can write an anti-join (`IS NULL`) and a semi-join (`EXISTS`)
- [ ] I can spot row explosion from a one-to-many join and fix the count / sum
- [ ] I know that comma joins are legacy and `USING` does not exist in T-SQL
