# Level 06 — Functions

**Goal:** use the built-in string, date, numeric and conditional functions confidently, know the traps in each family (`+` with NULL, `DATEDIFF` boundaries, integer division, `ISNULL` truncation), and write the small "recipes" interviewers ask for.

**Time:** ~2 hr · **Files:** `01_Practice_String.sql` → `02_Practice_Date.sql` → `03_Practice_Numeric_Conditional.sql` → `Exercises.sql`

---

## 1. Concepts in plain words

A **function** takes one or more values and returns one value **per row**. It runs inside `SELECT`, `WHERE`, `ORDER BY`, `GROUP BY` — anywhere an expression is allowed. (Aggregate functions that work across rows are Level 07.)

| Family | Mental model | Most-used members |
|--------|--------------|-------------------|
| **String** | Text is a 1-based sequence of characters. Positions come from `CHARINDEX` / `PATINDEX`; pieces come from `LEFT` / `RIGHT` / `SUBSTRING`. | `LEN`, `UPPER/LOWER`, `SUBSTRING`, `CHARINDEX`, `REPLACE`, `TRIM`, `CONCAT`, `STRING_AGG`, `STRING_SPLIT`, `FORMAT` |
| **Date** | A date is a point on a line. `DATEADD` moves along it, `DATEDIFF` counts **boundaries crossed** between two points, `DATEPART/DATENAME` read one component. | `GETDATE`, `DATEADD`, `DATEDIFF`, `DATEPART`, `DATENAME`, `EOMONTH`, `DATEFROMPARTS`, `DATETRUNC` |
| **Numeric** | Result type follows the input type: `INT / INT = INT`, `POWER(INT, x)` is `INT`, `ROUND(DECIMAL(6,3))` keeps scale 3. | `ROUND`, `CEILING`, `FLOOR`, `ABS`, `POWER`, `SQRT`, `%`, `SIGN`, `RAND` |
| **Conditional** | Return a different value depending on a test. `CASE` is the general tool; the others are shortcuts for common cases. | `CASE`, `IIF`, `COALESCE`, `ISNULL`, `NULLIF`, `CHOOSE`, `GREATEST/LEAST` |

**Version markers used in the files:** `TRIM`, `CONCAT_WS`, `STRING_AGG`, `TRANSLATE` = 2017+ · `DATETRUNC`, `GREATEST/LEAST`, `STRING_SPLIT` ordinal, `GENERATE_SERIES` = 2022+ · `IIF`, `CHOOSE`, `FORMAT`, `EOMONTH`, `DATEFROMPARTS` = 2012+.

## 2. Syntax cheat-sheet

```sql
-- STRING
LEN(s)  DATALENGTH(s)                    -- chars (trailing spaces ignored) / bytes
UPPER(s)  LOWER(s)  REVERSE(s)
LEFT(s,n)  RIGHT(s,n)  SUBSTRING(s,start,len)          -- 1-based
CHARINDEX(find, s [,start])  PATINDEX('%pattern%', s)   -- 0 = not found
REPLACE(s, find, with)  STUFF(s, start, delete_n, insert)
TRIM([chars FROM] s)  LTRIM(s)  RTRIM(s)
CONCAT(a,b,c)  CONCAT_WS(sep,a,b,c)      -- NULL-safe;   a + NULL = NULL
REPLICATE(s,n)  SPACE(n)  QUOTENAME(name)  FORMAT(v,'00000')
STRING_SPLIT('a,b', ',' [,1])            -- table function, ordinal column with 3rd arg (2022+)
STRING_AGG(col, ', ') WITHIN GROUP (ORDER BY col)

-- DATE
GETDATE()  SYSDATETIME()  SYSUTCDATETIME()             -- DATETIME / DATETIME2 / UTC
DATEADD(part, n, d)  DATEDIFF(part, start, end)  DATEDIFF_BIG(...)
DATEPART(part, d)  DATENAME(part, d)  YEAR(d) MONTH(d) DAY(d)
EOMONTH(d [,months])  DATEFROMPARTS(y,m,d)  DATETRUNC(part, d)  ISDATE(s)
FORMAT(d, 'dd-MMM-yyyy')  CONVERT(VARCHAR(10), d, 103)   -- display only
@@DATEFIRST   SET DATEFIRST 1                            -- Monday = 1

-- NUMERIC
ROUND(x, len [,1])   -- len < 0 rounds left of the point; 3rd arg 1 = truncate
CEILING(x)  FLOOR(x)  ABS(x)  POWER(x,y)  SQRT(x)  SQUARE(x)  SIGN(x)  x % y
RAND([seed])         -- evaluated once per query; per-row: ABS(CHECKSUM(NEWID())) % n

-- CONDITIONAL
CASE col WHEN v1 THEN r1 WHEN v2 THEN r2 ELSE r END          -- simple
CASE WHEN cond1 THEN r1 WHEN cond2 THEN r2 ELSE r END        -- searched (first true wins)
IIF(cond, a, b)   COALESCE(a, b, c, ...)   ISNULL(a, b)   NULLIF(a, b)
CHOOSE(i, v1, v2, ...)   GREATEST(a, b, c)   LEAST(a, b, c)
```

**Recipes (memorise):**

| Task | Query |
|------|-------|
| Email domain | `SUBSTRING(Email, CHARINDEX('@', Email) + 1, LEN(Email))` |
| First / last name | `LEFT(n, CHARINDEX(' ', n) - 1)` / `SUBSTRING(n, CHARINDEX(' ', n) + 1, LEN(n))` |
| Mask email | `LEFT(e,1) + REPLICATE('*', CHARINDEX('@',e)-2) + SUBSTRING(e, CHARINDEX('@',e), LEN(e))` |
| Pad to 5 digits | `RIGHT('00000' + CAST(id AS VARCHAR(5)), 5)` or `FORMAT(id, '00000')` |
| First day of month | `DATEFROMPARTS(YEAR(d), MONTH(d), 1)` or `DATETRUNC(month, d)` |
| Last day of month | `EOMONTH(d)` |
| Correct age | `DATEDIFF(year, dob, today) - CASE WHEN DATEADD(year, DATEDIFF(year, dob, today), dob) > today THEN 1 ELSE 0 END` |
| Month bucket | `CONVERT(CHAR(7), d, 120)` → `'2025-01'` |
| Safe division | `a / NULLIF(b, 0)` |
| Percentage | `x * 100.0 / total` (never `x / total * 100` with INTs) |

## 3. Gotchas

- **`'a' + NULL` is NULL.** One NULL kills the whole `+` chain. `CONCAT` / `CONCAT_WS` treat NULL as empty.
- **`LEN` ignores trailing spaces; `DATALENGTH` counts bytes** (`NVARCHAR` = 2 bytes per char).
- **`DATEDIFF` counts boundaries, not full units.** `DATEDIFF(month, '2025-01-31', '2025-02-01') = 1`. `DATEDIFF(year, dob, today)` overstates age by 1 before the birthday.
- **`DATEDIFF` returns INT** → seconds over 68 years / ms over 24 days overflow. Use `DATEDIFF_BIG`.
- **`DATEADD(month, 1, '2025-01-31')` = `2025-02-28`** (clamped), not an error and not March.
- **`DATEPART(weekday)` depends on `@@DATEFIRST`** (7 = Sunday-first under us_english). `DATENAME` depends on `SET LANGUAGE`. Production code: `(DATEPART(weekday, d) + @@DATEFIRST - 2) % 7 + 1` gives Monday = 1 always.
- **Functions on a column in `WHERE` are not SARGable** (`YEAR(OrderDate) = 2025` → scan). Write `OrderDate >= '20250101' AND OrderDate < '20260101'`.
- **`FORMAT` is slow** (.NET call per row). Fine for a report of 100 rows; avoid on millions. `CONVERT` with a style is the fast alternative.
- **`INT / INT = INT`**: `16 / 19 * 100 = 0`. Multiply by `100.0` or `CAST` first.
- **`ROUND` keeps the input scale**: `ROUND(123.456, 2)` prints `123.460`. `CAST(... AS DECIMAL(10,2))` for display.
- **`POWER` returns the type of its FIRST argument**: `POWER(2, 0.5) = 1`. Write `POWER(2.0, 0.5)`.
- **`RAND()` runs once per query** — every row gets the same value. Use `CHECKSUM(NEWID())` per row.
- **`ISNULL` returns the type of the first argument and can truncate**: `ISNULL(varchar3_null, 'Mumbai') = 'Mum'`. `COALESCE` picks the highest-precedence type. `COALESCE(NULL, NULL)` is a compile error.
- **`CASE` stops at the first true `WHEN`** — order overlapping conditions from most specific to least. No `ELSE` + no match = NULL.
- **`STRING_AGG` order is random** unless `WITHIN GROUP (ORDER BY ...)`; `STRING_SPLIT` order is random unless you use the ordinal (2022+).

## 4. Interview questions

**Q: `LEN` vs `DATALENGTH`?**
`LEN` = number of characters, trailing spaces ignored. `DATALENGTH` = bytes stored, spaces included; for `NVARCHAR` it is 2 × characters. `LEN(NULL)` is NULL, `LEN('')` is 0.

**Q: `CHARINDEX` vs `PATINDEX`?**
Both return a 1-based position (0 if not found). `CHARINDEX` finds a literal string and accepts a start position. `PATINDEX` accepts a `LIKE` pattern with `%`, `_`, `[ ]` and has no start position.

**Q: `ISNULL` vs `COALESCE`?**
`ISNULL`: 2 arguments, SQL Server only, result type = first argument's type (can truncate), result is NOT NULL-able. `COALESCE`: 2+ arguments, ANSI standard, returns the first non-NULL, result type = highest precedence of all arguments, expanded to a `CASE` internally.

**Q: `CASE` vs `IIF`?**
`IIF(cond, a, b)` is just shorthand for a two-branch searched `CASE` (2012+). `CASE` handles many branches and the simple form `CASE col WHEN ...`.

**Q: How do you avoid divide-by-zero?**
`a / NULLIF(b, 0)` — `NULLIF` turns 0 into NULL, and anything divided by NULL is NULL instead of an error. Wrap with `ISNULL(..., 0)` if you need a number.

**Q: How do you calculate age correctly?**
Not `DATEDIFF(year, dob, today)` — it counts year boundaries, so it is one too many before the birthday. Subtract 1 when `DATEADD(year, DATEDIFF(year, dob, today), dob) > today`.

**Q: `DATEDIFF(month, '2025-01-31', '2025-02-01')` returns what and why?**
1. `DATEDIFF` counts how many month boundaries lie between the two dates, not how many full months elapsed.

**Q: How do you get the first and last day of the current month?**
First: `DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1)` or `DATETRUNC(month, GETDATE())` (2022+). Last: `EOMONTH(GETDATE())`.

**Q: `GETDATE()` vs `SYSDATETIME()` vs `SYSUTCDATETIME()`?**
`GETDATE()` returns `DATETIME` (3.33 ms precision) in server local time. `SYSDATETIME()` returns `DATETIME2(7)` (100 ns). `SYSUTCDATETIME()` is the same in UTC.

**Q: What does SARGable mean and how does it apply to dates?**
Search-ARGument-able: the predicate can use an index seek. `WHERE YEAR(OrderDate) = 2025` cannot; `WHERE OrderDate >= '20250101' AND OrderDate < '20260101'` can. Keep the column bare, put arithmetic on the other side.

**Q: How do you split 'a,b,c' into rows and the reverse?**
`STRING_SPLIT('a,b,c', ',')` (table function; add `, 1` for an ordinal in 2022+). Reverse: `STRING_AGG(col, ',') WITHIN GROUP (ORDER BY col)` (2017+).

**Q: Why is `16 / 19 * 100` zero?**
Integer division: `16 / 19 = 0` first, then `0 * 100`. Use `16 * 100.0 / 19` (= 84.21) or cast one operand to `DECIMAL`.

## 5. Checklist

- [ ] I can extract a domain, split a name, mask an email and zero-pad an ID
- [ ] I know why `+` with NULL gives NULL and when to use `CONCAT` / `CONCAT_WS`
- [ ] I can use `STRING_SPLIT` and `STRING_AGG` (with ordering)
- [ ] I can explain the `DATEDIFF` boundary rule and compute age / years of service correctly
- [ ] I can get first/last day of month/year and group orders by month
- [ ] I write date filters the SARGable way (`>= start AND < next`)
- [ ] I know `ROUND` negative length / truncate, integer division, and how to compute a percentage
- [ ] I can write simple, searched and nested `CASE`, use it in `ORDER BY`, and explain `ISNULL` vs `COALESCE` vs `NULLIF`
