# Level 02 — Data Types

**Goal:** pick the right type for every column, understand storage size and precision, and convert safely between types.

**Time:** ~1 hr · **Files:** `01_Practice.sql` → `Exercises.sql`

---

## 1. The families

| Family | Types | Bytes | Notes |
|--------|-------|-------|-------|
| **Exact integer** | `TINYINT` 0–255 · `SMALLINT` ±32 K · `INT` ±2.1 billion · `BIGINT` ±9.2 quintillion | 1 / 2 / 4 / 8 | Integer ÷ integer = **integer** (7/2 = 3) |
| **Exact decimal** | `DECIMAL(p,s)` = `NUMERIC(p,s)` · `MONEY` · `SMALLMONEY` | 5–17 | `p` = total digits, `s` = digits after the point. `DECIMAL(10,2)` → max 99,999,999.99. Use for **money**. |
| **Approximate** | `FLOAT(53)` (8 B) · `REAL` = `FLOAT(24)` (4 B) | 4 / 8 | Binary floating point → `0.1 + 0.2 <> 0.3`. Use for scientific data, **never for money**. |
| **Character (1 byte/char)** | `CHAR(n)` fixed, padded · `VARCHAR(n)` variable · `VARCHAR(MAX)` up to 2 GB | n / actual+2 | Collation decides language rules. |
| **Unicode (2 bytes/char)** | `NCHAR(n)` · `NVARCHAR(n)` · `NVARCHAR(MAX)` | 2n / 2·actual+2 | Needs the **`N'…'` prefix** on literals, or non-Latin text becomes `?`. |
| **Date / time** | `DATE` (3 B) · `TIME(0-7)` (3–5 B) · `SMALLDATETIME` (4 B, minute) · `DATETIME` (8 B, **3.33 ms**) · `DATETIME2(0-7)` (6–8 B, 100 ns) · `DATETIMEOFFSET` (+ time-zone) | | Prefer `DATE` / `DATETIME2` in new work; `DATETIME` is legacy. |
| **Other** | `BIT` (0/1/NULL) · `UNIQUEIDENTIFIER` (GUID, 16 B) · `VARBINARY(MAX)` (files) · `XML` · `SQL_VARIANT` · `HIERARCHYID` · `GEOGRAPHY` | | 8 `BIT` columns share 1 byte. |

## 2. Conversion

```sql
CAST(expr AS type)                  -- ANSI standard
CONVERT(type, expr [, style])       -- SQL Server; style = date/number format (103 = dd/mm/yyyy, 112 = yyyymmdd, 120 = yyyy-mm-dd hh:mi:ss)
TRY_CAST / TRY_CONVERT              -- return NULL instead of error
PARSE / TRY_PARSE                   -- culture-aware, slow (uses .NET)
FORMAT(value, 'dd-MMM-yyyy')        -- pretty, .NET format string, SLOW on big sets
```

**Implicit conversion** happens when types differ: `1 + '1' = 2` (string → int, because INT has higher *precedence* than VARCHAR). Rule: the lower-precedence type is converted to the higher one. Implicit conversion on an **indexed column** in a `WHERE` kills index seeks (Level 19).

**Precedence (high → low, short list):** `DATETIME2` > `DATETIME` > `DATE` > `FLOAT` > `DECIMAL` > `MONEY` > `BIGINT` > `INT` > `SMALLINT` > `TINYINT` > `BIT` > `NVARCHAR` > `VARCHAR`.

## 3. Gotchas

- **`7 / 2 = 3`**. Make one side decimal: `7 / 2.0`, or `CAST(7 AS DECIMAL(5,2)) / 2`.
- **`DECIMAL` insert overflow:** `DECIMAL(5,2)` cannot hold `1000.00` (needs 6 digits) → *Arithmetic overflow*.
- **`CAST(123.456 AS INT)` truncates → 123; `CAST(123.456 AS DECIMAL(6,2))` rounds → 123.46.**
- **`CHAR(10)` always stores 10 bytes** ('abc' + 7 spaces); `LEN()` ignores trailing spaces, `DATALENGTH()` does not.
- **`VARCHAR` without a length** defaults to **1** in `CAST` / `DECLARE` and **30** in `CONVERT`. Always write the length.
- **`DATETIME` rounds to .000 / .003 / .007** → `'23:59:59.999'` becomes **next day 00:00:00.000**. Use `DATETIME2` or `< next-day` comparisons.
- **Date literals:** `'yyyymmdd'` and `'yyyy-mm-ddThh:mi:ss'` are safe in every language/DATEFORMAT. `'dd/mm/yyyy'` depends on `SET DATEFORMAT` / login language. Even `'yyyy-mm-dd'` is unsafe for **`DATETIME`** (not for `DATE`/`DATETIME2`).
- **`N` prefix:** `'नमस्ते'` → `??????`, `N'नमस्ते'` → correct.
- **`NVARCHAR(MAX)` / `VARCHAR(MAX)`** cannot be an index key and are slower; use only when > 8000 bytes really needed.
- **`FLOAT` equality comparisons are unreliable** – compare with a tolerance or use `DECIMAL`.
- **`UNIQUEIDENTIFIER` as clustered key** = random inserts → fragmentation. Prefer `INT IDENTITY` or `NEWSEQUENTIALID()`.

## 4. Interview questions

**Q: `CHAR` vs `VARCHAR` vs `NVARCHAR`?**
`CHAR(n)` fixed length, padded with spaces, fast for short fixed codes (country code, gender). `VARCHAR(n)` variable length, 1 byte per char + 2 bytes overhead. `NVARCHAR(n)` Unicode, 2 bytes per char, needed for multi-language text (Hindi, Chinese, emoji).

**Q: `DECIMAL` vs `FLOAT`? Which one for salary?**
`DECIMAL` is exact (stores base-10 digits), `FLOAT` is approximate (binary). Money/salary → `DECIMAL(p,s)`. `FLOAT` only for scientific measurements.

**Q: `DATETIME` vs `DATETIME2`?**
`DATETIME2` has larger range (0001–9999), configurable precision up to 100 ns, uses 6–8 bytes, and is ANSI-compliant. `DATETIME` is 8 bytes, 1753–9999, 3.33 ms accuracy. Use `DATETIME2` for new tables.

**Q: What does `NUMERIC(10,2)` mean?**
10 significant digits in total, 2 after the decimal point → range ±99,999,999.99. `NUMERIC` and `DECIMAL` are identical in SQL Server.

**Q: `CAST` vs `CONVERT`?**
Same job. `CAST` is ANSI (portable). `CONVERT` is SQL Server specific and has the *style* argument for formatting dates and numbers.

**Q: What is implicit conversion and why does it matter for performance?**
SQL Server silently converts one side of a comparison to the higher-precedence type. If the *column* side gets converted (e.g. `WHERE VarcharCol = 123`), the index on that column cannot be seeked → scan.

**Q: What is `SQL_VARIANT`?**
A column that can hold values of different base types. Rarely used; cannot be used in some operations and hurts performance.

**Q: What does the `N` prefix do?**
Marks a literal as Unicode (`NVARCHAR`). Without it the literal is `VARCHAR` and non-ASCII characters are converted using the database collation's code page (usually lost as `?`).

## 5. Checklist

- [ ] I can list the numeric / string / date families with their byte sizes
- [ ] I know why `7/2 = 3` and how to fix it
- [ ] I know when to use `DECIMAL` vs `FLOAT`
- [ ] I know why `N'...'` is required
- [ ] I can use `CAST`, `CONVERT` (with a style), `TRY_CAST`
- [ ] I know the `DATETIME` .999 rounding trap and the safe date literal formats
