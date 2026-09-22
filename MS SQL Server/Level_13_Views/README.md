# Level 13 — Views

**Goal:** create, change and drop views confidently, know the rules (ORDER BY, parameters, column names), update data *through* a view safely, and explain SCHEMABINDING, CHECK OPTION and indexed views in an interview.

**Time:** ~1.5 hr · **Files:** `01_Practice_View_Basics.sql` → `02_Practice_View_Options_Indexed.sql` → `Exercises.sql`

---

## 1. Concepts in plain words

| Term | Meaning |
|------|---------|
| **View** | A **saved SELECT with a name**. Stores no data (a "virtual table"); every query against it re-runs the stored SELECT on the base tables. |
| **Why views** | 1) hide a complex join behind one name, 2) **security** — expose some columns/rows and `GRANT SELECT` on the view only, 3) one place for business logic so every report gets the same numbers. |
| **Updatable view** | You may `INSERT / UPDATE / DELETE` *through* a view if the statement touches **one base table** and only plain columns (no aggregates, `DISTINCT`, `GROUP BY`, `UNION`, derived expressions). A join view is fine as long as one statement changes columns of one table. |
| **`WITH CHECK OPTION`** | Every insert/update through the view must produce rows the view can still see. Without it, you can insert a row that then "disappears". |
| **`WITH SCHEMABINDING`** | Locks the base tables: you cannot drop/alter a column the view uses, or drop the table. Requires two-part names and no `SELECT *`. Mandatory for indexed views. |
| **`WITH ENCRYPTION`** | Hides the definition (`sp_helptext`, `OBJECT_DEFINITION`, `sys.sql_modules` return nothing). Weak, rarely used. |
| **Indexed view** | A view with a **unique clustered index** → the result is stored on disk and maintained automatically on every base-table change. Reads become an index seek; writes get slower. |
| **Nested view** | A view that selects from another view. Allowed (32 levels), discouraged: hidden cost, hard to tune, fragile. |
| **Inline TVF** | "A view with parameters" (`CREATE FUNCTION … RETURNS TABLE AS RETURN (SELECT …)`). Level 15. |

### View vs CTE vs temp table vs table

| | View | CTE | #Temp table | Table |
|---|---|---|---|---|
| Stores data | no (indexed: yes) | no | yes (tempdb) | yes |
| Lifetime | permanent object | one statement | session | permanent |
| Reusable by | every query / user | next statement only | my session | everyone |
| Parameters | no (use inline TVF) | no | – | – |
| Indexes | only as indexed view | no | yes | yes |
| Security | `GRANT` on view | none | none | `GRANT` on table |
| Best for | reuse + security + hiding joins | readability, recursion | staging, multi-step work | real data |

## 2. Syntax cheat-sheet

```sql
CREATE VIEW dbo.vw_X AS SELECT ... ;              -- must be FIRST statement in the batch (GO before)
ALTER  VIEW dbo.vw_X AS SELECT ... ;              -- replace SELECT, keep permissions; fails if missing
CREATE OR ALTER VIEW dbo.vw_X AS SELECT ... ;     -- 2016 SP1+: create or replace
DROP VIEW IF EXISTS dbo.vw_X, dbo.vw_Y;           -- 2016+

CREATE VIEW dbo.vw_X (ColA, ColB) AS SELECT a, b * 12 FROM dbo.T;   -- column list = names for expressions
CREATE VIEW dbo.vw_X AS SELECT TOP (3) ... ORDER BY Salary DESC;    -- ORDER BY allowed only with TOP / OFFSET
CREATE VIEW dbo.vw_X AS SELECT ... WHERE Category = 'Electronics' WITH CHECK OPTION;
CREATE VIEW dbo.vw_X WITH SCHEMABINDING AS SELECT t.a, t.b FROM dbo.T t;   -- two-part names, no *
CREATE VIEW dbo.vw_X WITH ENCRYPTION   AS SELECT ... ;

-- INDEXED VIEW (SET options ON first: ANSI_NULLS, QUOTED_IDENTIFIER, ANSI_PADDING, ANSI_WARNINGS,
--               ARITHABORT, CONCAT_NULL_YIELDS_NULL; NUMERIC_ROUNDABORT OFF)
CREATE VIEW dbo.vw_Rev WITH SCHEMABINDING AS
SELECT p.Category, SUM(od.Quantity * od.UnitPrice) AS Revenue, COUNT_BIG(*) AS LineCount
FROM dbo.OrderDetails od JOIN dbo.Products p ON p.ProductID = od.ProductID
GROUP BY p.Category;
CREATE UNIQUE CLUSTERED INDEX IX_vw_Rev ON dbo.vw_Rev (Category);
SELECT * FROM dbo.vw_Rev WITH (NOEXPAND);         -- Standard edition needs NOEXPAND to use the index

-- METADATA
SELECT * FROM sys.views;                                       -- with_check_option
SELECT * FROM sys.sql_modules WHERE object_id = OBJECT_ID('dbo.vw_X');   -- definition, is_schema_bound
EXEC sp_helptext 'dbo.vw_X';    SELECT OBJECT_DEFINITION(OBJECT_ID('dbo.vw_X'));
SELECT * FROM INFORMATION_SCHEMA.VIEWS;                        -- ANSI; IS_UPDATABLE always 'NO'
SELECT * FROM sys.dm_sql_referenced_entities('dbo.vw_X', 'OBJECT');    -- what the view uses
SELECT * FROM sys.dm_sql_referencing_entities('dbo.T', 'OBJECT');      -- who uses the table
EXEC sp_refreshview 'dbo.vw_X';                                -- re-read base columns after ALTER TABLE
```

## 3. Gotchas

- **`ORDER BY` in a view is an error** unless `TOP` / `OFFSET` / `FOR XML` is present — and even then the *output order is not guaranteed*. `TOP 100 PERCENT … ORDER BY` is a myth: the optimizer removes it. Sort in the outer query.
- **`SELECT *` freezes the column list** at creation time. New table columns are invisible until `sp_refreshview`; dropping/re-adding columns can return wrong data under the old names. Always list columns.
- **Every expression needs an alias**, or `CREATE VIEW` fails ("no column name was specified for column N").
- **No parameters, no variables, no temp tables, no `INTO`, no `OPTION`** inside a view.
- **Updating through a join view** works only if one statement touches one base table; touching two gives *"modification affects multiple base tables"*. Aggregated views are read-only.
- **Without `CHECK OPTION`** an insert through a filtered view can succeed and be invisible through the same view.
- **`DELETE` through a filtered view only deletes rows the view can see** — a row outside the filter is untouched (0 rows affected).
- **`SCHEMABINDING`** blocks `ALTER TABLE ... DROP/ALTER COLUMN` and `DROP TABLE` on the base tables; you must drop the view first. `ADD COLUMN` still works.
- **Indexed views**: `COUNT_BIG(*)` is mandatory with `GROUP BY`; `SUM` only over non-nullable expressions (`SUM(ISNULL(col,0))`); no outer joins, subqueries, `DISTINCT`, `AVG/MIN/MAX`; the 7 SET options must be correct for the creator *and for every later writer* of the base tables (sqlcmd defaults `QUOTED_IDENTIFIER OFF`!).
- **Standard / Express edition** only use an indexed view with `WITH (NOEXPAND)`; Enterprise / Developer match it automatically.
- **`WITH ENCRYPTION`** is obfuscation, not security — and you lose the source if it is not in version control.
- **`INFORMATION_SCHEMA.VIEWS.IS_UPDATABLE`** is always `NO` in SQL Server; `VIEW_DEFINITION` is truncated at 4000 characters.
- **Nested views** compile fine and then surprise you: an `ALTER` of the bottom view breaks the top one at run time.

## 4. Interview questions

**Q: What is a view? Does it store data?**
A named, saved SELECT. No data is stored — except an *indexed* view, whose unique clustered index materialises the result on disk.

**Q: Why use views?**
Simplify complex joins, security (hide columns/rows, grant on the view), consistent business logic in one place, backward compatibility when tables change.

**Q: Can you INSERT / UPDATE through a view?**
Yes if the statement modifies one base table, the columns are real columns, and the view has no aggregates / `DISTINCT` / `GROUP BY` / `UNION`. `WITH CHECK OPTION` makes sure the changed rows still satisfy the view's `WHERE`.

**Q: What is `WITH CHECK OPTION`?**
A guard: any INSERT/UPDATE through the view must produce rows visible through the view; otherwise error 550.

**Q: What is `WITH SCHEMABINDING`?**
It binds the view to the base tables' schema: columns the view uses cannot be dropped or altered and the table cannot be dropped. Needs two-part names, no `SELECT *`. Required for indexed views.

**Q: Can a view have ORDER BY?**
Only together with `TOP` / `OFFSET-FETCH` / `FOR XML`, and it then defines which rows to return, not their order. `TOP 100 PERCENT ... ORDER BY` does not sort.

**Q: Can a view take parameters?**
No. Use an inline table-valued function, which behaves like a parameterised view.

**Q: What is an indexed (materialised) view? When would you use it?**
A schema-bound view with a unique clustered index; SQL Server stores and maintains the rows. Use for heavy aggregates read far more often than the base tables change. Avoid on write-heavy OLTP tables (every write maintains the index; strict SET options).

**Q: What are the requirements of an indexed view?**
`SCHEMABINDING`, deterministic expressions, `COUNT_BIG(*)` with `GROUP BY`, no outer joins / subqueries / `DISTINCT` / `TOP` / `UNION`, first index unique clustered, correct SET options.

**Q: View vs stored procedure?**
A view is a single SELECT you can query and join; a procedure is a program (parameters, logic, DML, multiple result sets) that you `EXEC` and cannot `SELECT FROM`.

**Q: How do you see a view's definition or dependencies?**
`sp_helptext`, `OBJECT_DEFINITION()`, `sys.sql_modules`, `INFORMATION_SCHEMA.VIEWS`; dependencies via `sys.dm_sql_referenced_entities` / `sys.dm_sql_referencing_entities`.

**Q: What happens to a view when a base table column is added?**
Nothing until refreshed: a `SELECT *` view keeps its old column list until `sp_refreshview`; an explicit column list is unaffected.

## 5. Checklist

- [ ] I can `CREATE`, `ALTER`, `CREATE OR ALTER` and `DROP … IF EXISTS` a view and query it like a table
- [ ] I know the three rules: ORDER BY only with TOP/OFFSET, no parameters, every column named
- [ ] I can update data through a view and explain when it fails (multi-table, aggregates)
- [ ] I can explain and demonstrate `WITH CHECK OPTION`
- [ ] I can explain `WITH SCHEMABINDING`, `WITH ENCRYPTION` and the `SELECT *` / `sp_refreshview` trap
- [ ] I can build an indexed view (requirements, unique clustered index, `NOEXPAND`) and say when it helps or hurts
- [ ] I can find views and their definitions/dependencies in the catalog views and DMVs
- [ ] I can compare view vs CTE vs temp table vs table in one sentence each
