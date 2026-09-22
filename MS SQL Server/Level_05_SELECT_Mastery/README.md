# Level 05 — SELECT Mastery

**Goal:** write any single-table `SELECT` with confidence — filter with every operator, sort, take the top N, remove duplicates, page through results, and shape the output with aliases, expressions and `CASE`.

**Time:** ~1.5 hr · **Files:** `01_Practice_Filtering.sql` → `02_Practice_Sorting_Top_Paging.sql` → `Exercises.sql`

> Everything in this level is **read-only** on the real tables (`Employees`, `Customers`, `Products`, `Orders`).

---

## 1. Concepts in plain words

### Logical order of query processing (learn this by heart)

| Step | Clause | What happens |
|------|--------|--------------|
| 1 | `FROM` | Pick the table(s) (joins happen here) |
| 2 | `WHERE` | Throw away rows that are not TRUE |
| 3 | `GROUP BY` | Fold rows into groups |
| 4 | `HAVING` | Throw away groups |
| 5 | `SELECT` | Compute the output columns — **aliases are born here** |
| 6 | `DISTINCT` | Remove duplicate output rows |
| 7 | `ORDER BY` | Sort (can use aliases) |
| 8 | `TOP` / `OFFSET ... FETCH` | Keep a slice |

So an alias **cannot** be used in `WHERE` (step 2 runs before step 5), but **can** be used in `ORDER BY`.

### Filtering operators

| Operator | Meaning | Remember |
|----------|---------|----------|
| `AND` / `OR` / `NOT` | Combine conditions | **AND binds before OR** → use parentheses whenever both appear |
| `IN (a, b, c)` | Equals any value in the list | `NOT IN` with a NULL in the list returns **nothing** |
| `BETWEEN a AND b` | `>= a AND <= b` (**inclusive**) | Reversed bounds match nothing; on DATETIME use `>= start AND < next` |
| `LIKE` | Pattern: `%` any string, `_` one char, `[abc]` set, `[a-f]` range, `[^x]` not | Case-insensitive by default; leading `%` prevents index seeks; literal `_`/`%` need `ESCAPE` or `[_]` |
| `IS NULL` / `IS NOT NULL` | Test for unknown | `= NULL` and `<> NULL` are always UNKNOWN → never TRUE |

**Three-valued logic:** every comparison gives TRUE, FALSE or UNKNOWN. `WHERE` keeps only TRUE. `NOT UNKNOWN` is still UNKNOWN — that is why `NOT DepartmentID = 1`, `NOT IN`, and `NOT LIKE` all silently drop NULL rows.

### Shaping the result

| Feature | Syntax | Notes |
|---------|--------|-------|
| `ORDER BY` | `ORDER BY a ASC, b DESC, expr, alias, 2` | NULL = smallest (first in ASC). Ordinal (`2`) works but is fragile. Not allowed inside subqueries/views unless `TOP`/`OFFSET` |
| `TOP` | `TOP (n)`, `TOP (n) PERCENT`, `TOP (n) WITH TIES` | PERCENT rounds **up**; WITH TIES needs ORDER BY; no ORDER BY = arbitrary rows |
| `DISTINCT` | `SELECT DISTINCT a, b` | Whole-row uniqueness; NULLs count as one value; `COUNT(DISTINCT col)` |
| `OFFSET/FETCH` | `ORDER BY k OFFSET s ROWS FETCH NEXT n ROWS ONLY` | ORDER BY mandatory; skip = `(page-1)*size`; sort key must be unique (add the PK) |
| Alias | `col AS x`, `col x`, `x = col`, `[Two Words]` | Table alias: `FROM dbo.Employees e` |
| Concatenation | `a + b` (NULL kills it), `CONCAT(a, b)` (NULL → ''), `CONCAT_WS(sep, ...)` (2017+, skips NULL) | `'x' + 5` is a conversion error; `CONCAT` converts |
| `CASE` | `CASE WHEN cond THEN v ... ELSE v END` / `CASE col WHEN val THEN v END` | Works in SELECT, ORDER BY, WHERE |

## 2. Syntax cheat-sheet

```sql
SELECT [DISTINCT] [TOP (n) [PERCENT] [WITH TIES]]
       col AS Alias, expr AS Calc, CASE WHEN ... THEN ... ELSE ... END AS Label
FROM   dbo.Table AS t
WHERE  (a = 1 OR a = 2) AND b > 10                    -- parentheses when mixing AND / OR
  AND  c IN (1, 2, 3)   AND d NOT IN ('x', 'y')       -- never a NULL in a NOT IN list
  AND  e BETWEEN 10 AND 20                            -- inclusive
  AND  dt >= '2025-02-01' AND dt < '2025-03-01'       -- safe date range (not BETWEEN)
  AND  name LIKE '[A-M]%' AND code LIKE '%\_%' ESCAPE '\'
  AND  email IS NOT NULL
ORDER BY b DESC, Alias ASC
OFFSET (@Page - 1) * @Size ROWS FETCH NEXT @Size ROWS ONLY;   -- paging (no TOP together with this)

-- NULLs last in ascending order
ORDER BY CASE WHEN col IS NULL THEN 1 ELSE 0 END, col;

-- Case-sensitive compare
WHERE Name COLLATE Latin1_General_CS_AS = 'rahul';

-- Departments with no employees (NULL-safe)
SELECT d.DepartmentName FROM dbo.Departments d
WHERE NOT EXISTS (SELECT 1 FROM dbo.Employees e WHERE e.DepartmentID = d.DepartmentID);
```

**Common WHERE patterns on the practice data**

| Question | Pattern |
|----------|---------|
| Orders of one month | `OrderDate >= '2025-03-01' AND OrderDate < '2025-04-01'` |
| Names starting with N–Z and ending in "a" | `EmployeeName LIKE '[N-Z]%a'` |
| Customers without email **or** in Delhi | `Email IS NULL OR City = 'Delhi'` |
| Dept 1 or 2 **and** salary > 70000 | `(DepartmentID = 1 OR DepartmentID = 2) AND Salary > 70000` |
| Departments with no employees | `NOT EXISTS (SELECT 1 FROM dbo.Employees e WHERE e.DepartmentID = d.DepartmentID)` |
| Page *n* of size *s* | `ORDER BY key OFFSET (n-1)*s ROWS FETCH NEXT s ROWS ONLY` |

## 3. Gotchas (things that bite beginners)

- **`WHERE a = 1 OR a = 2 AND b > 70000`** means `a = 1 OR (a = 2 AND b > 70000)`. Add parentheses.
- **`NOT IN (…NULL…)` returns zero rows.** Same when the subquery returns a NULL (`Employees.DepartmentID`). Filter `IS NOT NULL` or use `NOT EXISTS`.
- **`= NULL` never matches.** Only `IS NULL`. `NOT`, `NOT IN`, `NOT LIKE`, `<>` all drop NULL rows silently.
- **`BETWEEN` is inclusive**, and `BETWEEN '2025-02-01' AND '2025-02-28'` on a DATETIME column loses every row after midnight on the 28th. Use `>= start AND < next_start`.
- **String `BETWEEN 'A' AND 'C'`** excludes `'Chirag'` — it is alphabetically after `'C'`.
- **An alias cannot be used in WHERE** (or GROUP BY / HAVING); repeat the expression or use a subquery/CTE.
- **Without `ORDER BY` there is no order.** `TOP` without `ORDER BY` returns arbitrary rows; `OFFSET/FETCH` refuses to run.
- **`TOP (n) PERCENT` rounds up** (30 % of 11 = 4 rows). **`WITH TIES`** can return more than *n*.
- **`ORDER BY 2`** silently changes meaning when you add a column to the SELECT list.
- **`DISTINCT` + `ORDER BY` a column not in the SELECT** → error. DISTINCT applies to the whole row, not one column.
- **Paging needs a unique sort key** (`ORDER BY Salary DESC, EmployeeID`) or rows can repeat across pages.
- **`'text' + number` fails** (conversion). Use `CAST` or `CONCAT`. **`'text' + NULL` is NULL** — use `CONCAT` / `ISNULL`.
- **`LIKE '%abc'`** (leading wildcard) cannot use an index seek → full scan on big tables (Level 19).
- **`LIKE` is case-insensitive** on the default collation; use `COLLATE Latin1_General_CS_AS` when case matters.

## 4. Interview questions

**Q: What is the logical order of execution of a SELECT?**
`FROM → WHERE → GROUP BY → HAVING → SELECT → DISTINCT → ORDER BY → TOP/OFFSET-FETCH`. It explains why an alias works in ORDER BY but not in WHERE, and why WHERE cannot use aggregates (HAVING can).

**Q: Why can't I use a column alias in WHERE?**
Because WHERE is evaluated before SELECT, where the alias is defined. Repeat the expression, or put the query in a derived table / CTE and filter outside.

**Q: WHERE vs HAVING?**
WHERE filters rows before grouping and cannot use aggregates; HAVING filters groups after GROUP BY and can use aggregates (Level 07).

**Q: What does `NOT IN` do when the list contains NULL?**
Returns no rows: `x <> NULL` is UNKNOWN, and AND-ing UNKNOWN into the condition makes the whole predicate never TRUE. Use `NOT EXISTS` or exclude NULLs.

**Q: Why does `WHERE col = NULL` return nothing?**
NULL is unknown; any comparison to it is UNKNOWN, not TRUE. Use `IS NULL`.

**Q: Is BETWEEN inclusive? Any problem with dates?**
Yes, both ends included. With DATETIME columns the upper bound is midnight, so rows later that day are missed — use `>= start AND < next_day`.

**Q: `TOP` vs `OFFSET ... FETCH`?**
TOP takes the first n rows (no skipping, ORDER BY optional but recommended). OFFSET/FETCH (2012+) skips s rows and takes n, needs ORDER BY, and is the standard way to page. They cannot be combined.

**Q: What does `TOP WITH TIES` do?**
Includes extra rows that have the same ORDER BY value as the last row of the TOP n, so ties are not cut arbitrarily.

**Q: DISTINCT vs GROUP BY?**
Both remove duplicates. GROUP BY can also aggregate (COUNT, SUM …) and lets ORDER BY use non-selected columns; DISTINCT is just de-duplication of the selected row.

**Q: How do NULLs sort in ORDER BY?**
SQL Server treats NULL as the lowest value: first in ASC, last in DESC. Use `ORDER BY CASE WHEN col IS NULL THEN 1 ELSE 0 END, col` to move them last.

**Q: `+` vs `CONCAT` for strings?**
`+` returns NULL if any part is NULL and errors when mixing text with numbers; `CONCAT` treats NULL as '' and converts every argument to string. `CONCAT_WS` adds a separator and skips NULLs.

**Q: How do you write a case-sensitive search?**
Add a case-sensitive collation to the comparison: `WHERE Name COLLATE Latin1_General_CS_AS = 'rahul'` (or use `LIKE` with the same collation).

**Q: Does a query without ORDER BY return rows in primary-key order?**
No guarantee. It often looks that way on small tables, but the optimizer may use any index or parallel plan. If order matters, write `ORDER BY` — every time.

**Q: How do you search for a literal `%` or `_` with LIKE?**
Wrap it in brackets (`LIKE '%[%]%'`, `LIKE '%[_]%'`) or declare an escape character: `LIKE '%\_%' ESCAPE '\'`.

## 5. Checklist

- [ ] I can recite the logical processing order and explain the alias-in-WHERE error
- [ ] I always add parentheses when mixing AND and OR
- [ ] I know the `NOT IN` + NULL trap and the `= NULL` trap
- [ ] I use `>= start AND < next` for date ranges and know BETWEEN is inclusive
- [ ] I can use every LIKE wildcard (`% _ [] [^]`) and ESCAPE a literal `_` or `%`
- [ ] I can sort by several columns, expressions and aliases, and control NULL position
- [ ] I can use TOP, TOP PERCENT and WITH TIES, and page with OFFSET ... FETCH and a formula
- [ ] I can alias, calculate, concatenate safely (CONCAT) and label rows with CASE
