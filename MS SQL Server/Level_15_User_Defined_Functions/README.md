# Level 15 — User Defined Functions (UDF)

**Goal:** write scalar, inline table-valued and multi-statement table-valued functions, call them correctly (schema prefix, FROM, CROSS/OUTER APPLY), know the rules they must obey, and know when a function will make a query slow.

**Time:** ~2 hr · **Files:** `01_Practice_Scalar_and_TVF.sql` → `02_Practice_Rules_and_Schemabinding.sql` → `03_Practice_Performance_and_Metadata.sql` → `Exercises.sql`

---

## 1. Concepts in plain words

A **function** is saved T-SQL that takes parameters and **returns a value** (one value or a table). Unlike a procedure it can be used *inside* a query. Every UDF lives in a schema, so you always call it as `dbo.fn_Name(...)`.

### The three kinds

| Kind | `sys.objects.type` | Returns | Body | Called as | Optimizer sees |
|------|-------------------|---------|------|-----------|----------------|
| **Scalar** | `FN` | one value | `BEGIN … RETURN value END` | `SELECT dbo.fn(x)` | a black box, run per row (unless *inlined*, 2019+) |
| **Inline TVF** (iTVF) | `IF` | a table | `RETURNS TABLE AS RETURN (one SELECT)` | `FROM dbo.fn(x)` | expanded like a view ("parameterised view") — best performance |
| **Multi-statement TVF** (MSTVF) | `TF` | a table | `RETURNS @t TABLE(…) BEGIN INSERT @t … RETURN END` | `FROM dbo.fn(x)` | a black box that fills a table variable, no statistics |

### Calling a TVF

| Way | Works? | Notes |
|-----|--------|-------|
| `FROM dbo.fn(5)` | yes | like a table; filter / aggregate on top of it |
| `JOIN dbo.fn(@var) f ON …` | yes | argument must be a constant or a variable |
| `JOIN dbo.fn(t.Col) f ON …` | **no** | `t.Col` "could not be bound" — the function is evaluated before the join |
| `CROSS APPLY dbo.fn(t.Col) f` | yes | called **once per row** of `t`; rows with no result disappear (inner) |
| `OUTER APPLY dbo.fn(t.Col) f` | yes | same, but rows with no result are kept with NULLs (outer) |

Classic APPLY use: **top N per group** — a TVF with `TOP (@N) … ORDER BY`, applied per customer.

### Rules — a function must have NO side effects

Inside a function you **cannot**: `INSERT/UPDATE/DELETE` a permanent table, use `TRY/CATCH`, `THROW`/`RAISERROR`, dynamic SQL, temp tables (`#t`), `NEWID()`, `RAND()`, or call a procedure (compiles, fails at run time with error 557). You **can**: read tables, use table variables, `GETDATE()` (since 2005), call other functions.

### Deterministic vs non-deterministic, SCHEMABINDING

*Deterministic* = same input → always same output. SQL Server only **trusts** a UDF as deterministic when it is created `WITH SCHEMABINDING` (then the body cannot silently change). Needed for persisted computed columns and indexed views; also removes the "may access data" assumption. Schemabinding requires two-part names inside the function and blocks `ALTER/DROP` of the referenced tables.

### Performance

- A **scalar UDF** in `SELECT`/`WHERE` was (before 2019) executed **once per row** and forced the whole plan **serial**. On 200 000 rows: ~30 ms as an expression vs ~700 ms as a UDF.
- **Scalar UDF inlining** (2019+, compat ≥ 150): simple UDFs are rewritten into the query. Check `sys.sql_modules.is_inlineable` / `inline_type`; control with `WITH INLINE = ON | OFF`, hint `DISABLE_TSQL_SCALAR_UDF_INLINING`, or database scoped configuration `TSQL_SCALAR_UDF_INLINING`. Not inlineable: uses `GETDATE()`, too complex, used in computed columns, etc.
- **iTVF vs MSTVF**: iTVF gets real statistics, indexes, predicate push-down and parallelism. MSTVF builds the whole result first (fixed estimate: 1 row < 2014, 100 rows 2014–2016, real count via *interleaved execution* 2017+), then filters. Prefer iTVF whenever the body can be one SELECT.

### Function vs stored procedure (interview classic)

| Feature | Function | Stored procedure |
|---------|----------|------------------|
| Must return a value | yes (scalar or table) | no (optional int `RETURN`, `OUTPUT` params) |
| Usable inside `SELECT` / `WHERE` / `JOIN` | yes | no (`EXEC` only; `INSERT … EXEC` to reuse rows) |
| Modify tables / transactions / TRY-CATCH | no | yes |
| Call a procedure / dynamic SQL / temp tables | no | yes |
| Result sets | exactly one | 0 … many |
| Can be called with `EXEC` | scalar: yes (rarely used) | yes |

## 2. Syntax cheat-sheet

```sql
-- SCALAR
CREATE FUNCTION dbo.fn_OrderTotal (@OrderID INT) RETURNS DECIMAL(12,2)
AS BEGIN
    DECLARE @t DECIMAL(12,2);
    SELECT @t = SUM(Quantity * UnitPrice) FROM dbo.OrderDetails WHERE OrderID = @OrderID;
    RETURN ISNULL(@t, 0);
END
SELECT dbo.fn_OrderTotal(1002);                    -- schema prefix is MANDATORY

-- INLINE TVF ("parameterised view")
CREATE FUNCTION dbo.fn_OrdersByCustomer (@CustomerID INT) RETURNS TABLE
AS RETURN (SELECT OrderID, OrderDate, TotalAmount FROM dbo.Orders WHERE CustomerID = @CustomerID);
SELECT * FROM dbo.fn_OrdersByCustomer(1);

-- MULTI-STATEMENT TVF
CREATE FUNCTION dbo.fn_Summary (@CustomerID INT)
RETURNS @t TABLE (Status VARCHAR(20), Cnt INT)
AS BEGIN
    INSERT INTO @t SELECT Status, COUNT(*) FROM dbo.Orders WHERE CustomerID = @CustomerID GROUP BY Status;
    INSERT INTO @t SELECT 'ALL', SUM(Cnt) FROM @t;
    RETURN;                                        -- no value here
END

-- TOP N PER GROUP with APPLY
SELECT c.CustomerName, t.OrderID, t.TotalAmount
FROM dbo.Customers c
CROSS APPLY dbo.fn_TopNOrders(c.CustomerID, 2) t;  -- OUTER APPLY keeps customers with no orders

-- CHANGE / REMOVE
CREATE OR ALTER FUNCTION dbo.fn_X ... ;           -- 2016 SP1+
ALTER FUNCTION dbo.fn_X ... ;                     -- same kind only (cannot turn scalar into TVF)
DROP FUNCTION IF EXISTS dbo.fn_X, dbo.fn_Y;       -- 2016+

-- OPTIONS
CREATE FUNCTION ... RETURNS INT WITH SCHEMABINDING AS ...      -- trusted deterministic, locks referenced tables
CREATE FUNCTION ... RETURNS INT WITH INLINE = ON | OFF AS ...  -- 2019+ scalar UDF inlining

-- METADATA
SELECT name, type, type_desc FROM sys.objects WHERE type IN ('FN','IF','TF');
SELECT is_schema_bound, is_inlineable, inline_type, definition FROM sys.sql_modules WHERE object_id = OBJECT_ID('dbo.fn_X');
SELECT OBJECTPROPERTY(OBJECT_ID('dbo.fn_X'), 'IsDeterministic');
EXEC sp_helptext 'dbo.fn_X';  SELECT * FROM sys.parameters WHERE object_id = OBJECT_ID('dbo.fn_X');
SELECT * FROM sys.dm_sql_referencing_entities('dbo.fn_X', 'OBJECT');   -- who uses it
```

## 3. Gotchas

- **`SELECT fn_X(1)` → error 195 "not a recognized function name".** Without a schema SQL Server looks only at built-in functions. Always `dbo.fn_X(1)`.
- **`JOIN dbo.fn(t.Col)` does not work** ("multi-part identifier could not be bound"). Use `CROSS APPLY` / `OUTER APPLY`.
- `RETURN` in an MSTVF has **no value**; in a scalar function the **last statement must be `RETURN value`**.
- **Comments in the same batch before `CREATE FUNCTION` are stored** in the definition. Put `GO` right before `CREATE` if you want it clean.
- **`sqlcmd` runs with `QUOTED_IDENTIFIER OFF`** — persisted computed columns / filtered indexes that use a function then fail. `SET QUOTED_IDENTIFIER ON;` first (SSMS does it for you).
- A scalar UDF in `WHERE` **kills index seeks** on that column and (pre-2019 / not inlineable) forces a **serial** plan.
- Dropping a function that a view / other function uses gives **no error** unless that object is schemabound — the caller breaks at run time.
- `ALTER FUNCTION` cannot change the **kind** (scalar ↔ table) — drop and create.
- A function that calls a procedure **compiles fine** but fails at run time (error 557).
- Need an error inside a function? Force one: `RETURN CAST('my message' AS INT);` — ugly, but the standard trick.

## 4. Interview questions

**Q: What are the types of user defined functions in SQL Server?**
Scalar (returns one value), inline table-valued (one `SELECT`, behaves like a parameterised view) and multi-statement table-valued (fills a declared `@table` with several statements). Types `FN`, `IF`, `TF` in `sys.objects`.

**Q: Difference between a function and a stored procedure?**
A function must return a value, can be used inside `SELECT`/`WHERE`/`JOIN`, and cannot change data, use transactions, TRY/CATCH, dynamic SQL, temp tables or call procedures. A procedure can do all of those, returns 0..n result sets and is called only with `EXEC`.

**Q: Can a function call a stored procedure? Can a procedure call a function?**
Function → procedure: no (runtime error 557). Procedure → function: yes.

**Q: Can we use `GETDATE()` inside a function? And `NEWID()`?**
`GETDATE()` yes (since 2005, the function becomes non-deterministic and not inlineable). `NEWID()`/`RAND()` no — "side-effecting operator". Workaround: pass the value as a parameter or read it from a view.

**Q: Inline TVF vs multi-statement TVF — which is faster and why?**
Inline. It is expanded into the calling query like a view, so it uses indexes, real statistics, predicate push-down and parallelism. An MSTVF materialises everything into a table variable (no statistics, fixed row estimate before 2017, serial), then filters.

**Q: Why are scalar UDFs slow? What changed in SQL Server 2019?**
They were executed once per row as a separate call and blocked parallel plans. SQL 2019 (compat 150+) can *inline* simple scalar UDFs into the query (`sys.sql_modules.is_inlineable`, `WITH INLINE = ON/OFF`).

**Q: What is `CROSS APPLY` and when do you use it?**
An operator that calls a table expression / TVF once per row of the left input using its columns (a `JOIN` cannot). `CROSS APPLY` = inner (drops rows with no result), `OUTER APPLY` = outer (keeps them with NULLs). Typical use: top N per group.

**Q: What does `WITH SCHEMABINDING` do on a function?**
Binds the function to the objects it references: they cannot be altered/dropped while it exists, names must be two-part, and SQL Server can now trust the function as deterministic (needed for persisted computed columns and indexed views).

**Q: What is a deterministic function? Give examples.**
Same input always gives the same output: `LEN`, `ABS`, `DATEADD`, a UDF that only uses its parameters. Non-deterministic: `GETDATE`, `NEWID`, `RAND`, anything reading tables.

**Q: Can a function return multiple values?**
Not as a scalar. Return a table (TVF) or several columns in one row of a TVF.

**Q: Where are function definitions stored?**
`sys.sql_modules.definition` (also `OBJECT_DEFINITION()`, `sp_helptext`); the object row in `sys.objects`; parameters in `sys.parameters`.

## 5. Checklist

- [ ] I can write a scalar function, an inline TVF and a multi-statement TVF and know their `sys.objects` types
- [ ] I always call UDFs with the schema prefix and know why `fn_X()` alone fails
- [ ] I can do top-N-per-group with `CROSS APPLY` and know when to use `OUTER APPLY`
- [ ] I can list what a function is not allowed to do and why (no side effects)
- [ ] I know what `WITH SCHEMABINDING` changes and what "deterministic" means
- [ ] I can explain why scalar UDFs are slow and what scalar UDF inlining is
- [ ] I prefer inline TVFs over multi-statement TVFs and can say why
- [ ] I can answer "function vs stored procedure" in 30 seconds
