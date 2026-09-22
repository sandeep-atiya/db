# Level 14 — Stored Procedures

**Goal:** write, call and debug stored procedures — parameters (in / out / default / optional), return codes, transactions with proper rollback, error handling with `TRY/CATCH` and `THROW`, and safe dynamic SQL — the way they are asked in interviews.

**Time:** ~2.5 hr · **Files:** `01_Practice_Basics.sql` → `02_Practice_Advanced.sql` → `Exercises.sql`

---

## 1. Concepts in plain words

A **stored procedure** is a named program stored in the database: a block of T-SQL you call by name with parameters.

| Benefit | Why |
|---------|-----|
| **Reuse** | Write the logic once; call from apps, jobs, other procs. |
| **Security** | `GRANT EXECUTE` on the proc; the caller never touches the base tables. |
| **Plan caching** | The execution plan is compiled once and reused → faster. |
| **Less network traffic** | The app sends `EXEC usp_X 5`, not a 200-line query. |
| **Maintainable** | Fix the logic in one place; every caller gets the fix. |

**Parameter kinds:** *input* (default direction), *input with DEFAULT* (optional — caller may omit), *OUTPUT* (a single scalar handed back), and the **RETURN** value (one integer, status only: `0` = success).

**Optional-filter pattern:** `WHERE (@x IS NULL OR col = @x)` — "if the caller didn't pass `@x`, don't filter on that column".

**Error handling:** `BEGIN TRY … END TRY BEGIN CATCH … END CATCH`. In the CATCH, `ERROR_NUMBER / _MESSAGE / _SEVERITY / _STATE / _LINE / _PROCEDURE` describe the error. Raise your own with `THROW`; re-raise the original with a bare `THROW;`.

**Transactions in a proc:** `SET XACT_ABORT ON`, `BEGIN TRAN` in TRY, `COMMIT` at the end of TRY, and in CATCH `IF XACT_STATE() <> 0 ROLLBACK` then `THROW`. `@@TRANCOUNT` = nesting depth; `XACT_STATE()` = 1 healthy / -1 doomed / 0 none.

**Dynamic SQL:** `EXEC(@sql)` runs a string (own scope, no parameters — injection-prone) vs `sp_executesql` (parameterised, safe, cacheable, supports OUTPUT). Sanitise **object names** with `QUOTENAME`.

### THROW vs RAISERROR

| | `THROW` (2012+, prefer) | `RAISERROR` (older) |
|---|---|---|
| Custom number | ≥ 50000 | 50000, or a `sys.messages` id |
| Message formatting (`%s`,`%d`) | no | yes |
| Severity | always 16 | you choose (0–25) |
| Re-raise original | `THROW;` (no args) | cannot; rebuild the text |
| Effect | stops the batch; needs `;` before it | execution continues |

### Proc vs Function vs View

| | Procedure | Function | View |
|---|---|---|---|
| Call with | `EXEC` | inside a `SELECT` | `SELECT FROM` |
| Returns | result sets + OUTPUT + return code | one scalar or one table | one virtual table |
| INSERT/UPDATE/DELETE | yes | no | through it (limited) |
| Usable inside a query | no | yes | yes |
| `TRY/CATCH`, transactions | yes | no | no |
| Use for | actions, workflows | reusable calculations | reusable SELECT, security |

## 2. Syntax cheat-sheet

```sql
CREATE OR ALTER PROCEDURE dbo.usp_L14_X          -- usp_ prefix, NEVER sp_
    @In  INT,                                    -- input
    @Opt VARCHAR(20) = NULL,                     -- optional (has a default)
    @Out INT OUTPUT                              -- output
AS
BEGIN
    SET NOCOUNT ON;                              -- first line of every proc
    ... 
    SELECT @Out = COUNT(*) FROM dbo.T WHERE (@Opt IS NULL OR Col = @Opt);
    RETURN 0;                                    -- status code (0 = success)
END
GO

-- CALL
EXEC dbo.usp_L14_X @In = 1, @Out = @v OUTPUT;    -- named (preferred)
EXEC dbo.usp_L14_X 1, DEFAULT, @v OUTPUT;        -- positional
DECLARE @rc INT; EXEC @rc = dbo.usp_L14_X 1, NULL, @v OUTPUT;   -- capture RETURN code

DROP PROCEDURE IF EXISTS dbo.usp_L14_X;

-- ERROR HANDLING + TRANSACTION TEMPLATE
SET XACT_ABORT ON;
BEGIN TRY
    BEGIN TRAN;
        ... work ...
    COMMIT TRAN;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRAN;
    -- ERROR_NUMBER(), ERROR_MESSAGE(), ERROR_LINE(), ERROR_PROCEDURE()
    THROW;                                        -- re-raise to caller
END CATCH

THROW 50001, 'Custom business error.', 1;         -- custom (number >= 50000)
RAISERROR ('Value %d bad for %s.', 16, 1, @n, @s); -- formatted message

-- DYNAMIC SQL (safe)
EXEC sp_executesql N'SELECT @c = COUNT(*) FROM dbo.Orders WHERE CustomerID = @id',
                   N'@id INT, @c INT OUTPUT', @id = 1, @c = @c OUTPUT;
DECLARE @sql NVARCHAR(200) = N'SELECT TOP (@n) * FROM ' + QUOTENAME(@TableName);

-- DEFINITIONS
EXEC sp_helptext 'dbo.usp_L14_X';   SELECT OBJECT_DEFINITION(OBJECT_ID('dbo.usp_L14_X'));
SELECT * FROM sys.procedures;       SELECT * FROM sys.parameters WHERE object_id = OBJECT_ID('dbo.usp_L14_X');
```

## 3. Gotchas

- **`CREATE PROCEDURE` must be the first statement in its batch** → `GO` before it. Same for `CREATE VIEW/FUNCTION/TRIGGER`.
- **`SET NOCOUNT ON` as the first line** of every proc — kills "(N rows affected)" noise; does not change `@@ROWCOUNT`.
- **`RETURN` is for status only** (one integer). Return data via OUTPUT params or a result set, never via `RETURN`.
- **Mark OUTPUT in both places** — the proc definition *and* the `EXEC` call. Forget it on the call and you get NULL back.
- **Never prefix a proc `sp_`** — SQL Server searches `master` first for `sp_` names (overhead, possible recompile, shadowing). Use `usp_`.
- **`TRY/CATCH` does not catch** compile errors, severity 20+ errors, or attention/timeouts — only run-time errors (severity 11–19).
- **A rolled-back transaction still needs the CATCH to roll it back.** Without `SET XACT_ABORT ON`, some errors leave the transaction open and `@@TRANCOUNT > 0`; always check `XACT_STATE()`.
- **`EXEC(@sql)` + string concatenation = SQL injection.** Use `sp_executesql` with parameters; use `QUOTENAME` for object names that can't be parameters.
- **A temp table created in a proc is gone when the proc ends**; it *is* visible to procs that proc calls (flows down, not up). A temp table created inside `EXEC('...')` is not visible to the calling proc at all.
- **`WITH RECOMPILE` procs don't appear in `sys.dm_exec_procedure_stats`** (no cached plan). Prefer statement-level `OPTION (RECOMPILE)`.
- **`sp_rename` does not update the stored definition text** and warns you — scripts referencing the old name break. Prefer `CREATE OR ALTER`.
- **`sys.parameters.has_default_value` is 0 for T-SQL defaults** (that column is for CLR). Read the definition to see `= NULL` defaults.
- **`sp_depends` is deprecated/unreliable** — use `sys.dm_sql_referencing_entities` / `sys.dm_sql_referenced_entities`.

## 4. Interview questions

**Q: What is a stored procedure and its benefits?**
A named, precompiled T-SQL program. Benefits: reuse, security (execute permission only), cached plans, less network traffic, one place to maintain logic.

**Q: Difference between a stored procedure and a function?**
A function returns one value/table, is used inside a query, cannot have side effects (no INSERT/UPDATE to base tables), no `TRY/CATCH`/transactions. A proc is called with `EXEC`, can return multiple result sets + OUTPUT + status, can modify data and manage transactions.

**Q: Input vs output parameters vs return value?**
Input feeds data in; OUTPUT hands one scalar back; `RETURN` gives one integer status code (0 = success). Capture the return with `EXEC @rc = usp_...`.

**Q: How do you handle errors in a procedure?**
`TRY/CATCH`; in CATCH read `ERROR_NUMBER/_MESSAGE/_LINE/_PROCEDURE`, roll back if `XACT_STATE() <> 0`, and `THROW` to re-raise.

**Q: THROW vs RAISERROR?**
See the table — THROW is newer, simpler, re-raises with `THROW;`, always severity 16, no formatting; RAISERROR formats messages and picks severity but can't re-raise as-is.

**Q: How do you write a transaction safely in a proc?**
`SET XACT_ABORT ON`, `BEGIN TRAN` in TRY, `COMMIT` at end of TRY; in CATCH `IF XACT_STATE() <> 0 ROLLBACK` then `THROW`.

**Q: What is SQL injection and how do you prevent it?**
Concatenating user input into a SQL string lets an attacker change the query. Prevent it with parameterised `sp_executesql`; wrap dynamic object names in `QUOTENAME`.

**Q: `EXEC` vs `sp_executesql`?**
`EXEC(@s)` just runs a string (no parameters, injection-prone, poor plan reuse). `sp_executesql` accepts typed parameters (safe, reusable plan) and supports OUTPUT.

**Q: Why prefix procedures with `usp_` and not `sp_`?**
`sp_` names are resolved in `master` first — overhead, recompiles, and possible shadowing by system procs.

**Q: What is `SET NOCOUNT ON` and why use it?**
Stops the "(N rows affected)" messages — less network chatter and avoids confusing some client drivers.

**Q: Can a procedure return more than one result set?**
Yes — run several SELECTs; the client reads them in order.

**Q: What is parameter sniffing (preview)?**
SQL Server caches the plan for the first parameter value; if that value is atypical, later calls may get a bad plan. Mitigate with `OPTION (RECOMPILE)` or `WITH RECOMPILE` (full detail in Level 19).

## 5. Checklist

- [ ] I can `CREATE OR ALTER` / `ALTER` / `DROP … IF EXISTS` a procedure and call it named and positionally
- [ ] I can use input, default/optional, and OUTPUT parameters and capture a `RETURN` code
- [ ] I always start a proc with `SET NOCOUNT ON` and know why
- [ ] I can handle errors with `TRY/CATCH` and the `ERROR_*` functions
- [ ] I can explain and use THROW vs RAISERROR, including re-throwing
- [ ] I can write the safe transaction template (`XACT_ABORT`, `XACT_STATE`, rollback in CATCH)
- [ ] I can show a SQL injection and fix it with `sp_executesql` + `QUOTENAME`
- [ ] I can compare procedures, functions and views and know why `usp_` beats `sp_`
