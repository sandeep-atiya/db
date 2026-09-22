# Level 04 — CRUD (INSERT · UPDATE · DELETE · MERGE)

**Goal:** change data confidently — insert rows in every form, update and delete with joins and subqueries, see what changed with `OUTPUT`, choose between `DELETE` / `TRUNCATE` / `DROP`, and upsert with `MERGE`.

**Time:** ~1.5 hr · **Files:** `01_Practice_Insert_Update.sql` → `02_Practice_Delete_Truncate_Merge.sql` → `Exercises.sql`

> Every file works on **copies** (`dbo.L04_Products`, `dbo.L04_Customers`, `dbo.L04_Orders`) built with `SELECT ... INTO`. The 6 base tables are never changed. If you ever break the real data, run `00_Setup\00_Reset_All.sql`.

---

## 1. Concepts in plain words

| Statement | What it does | Rows affected by |
|-----------|--------------|------------------|
| `INSERT` | Adds rows: literal `VALUES` (1 or many), the result of a `SELECT`, or `DEFAULT VALUES` | – |
| `SELECT ... INTO` | Creates a **new** table from a query and fills it. Copies column types / NULL-ability / IDENTITY, **not** PK, FK, CHECK, DEFAULT, indexes | – |
| `UPDATE` | Changes column values of existing rows. `SET` expressions read the **old** row values | `WHERE` (no WHERE = every row) |
| `DELETE` | Removes rows, logged one by one, identity keeps counting | `WHERE` (no WHERE = every row) |
| `TRUNCATE TABLE` | Removes **all** rows, minimal logging, identity reset to seed, no `WHERE`, refused if any FK points at the table | – |
| `DROP TABLE` | Removes the table itself (data + structure + constraints + permissions) | – |
| `MERGE` | Compares a *source* with a *target* on a key and does INSERT / UPDATE / DELETE in one statement (upsert) | `WHEN MATCHED / NOT MATCHED BY TARGET / NOT MATCHED BY SOURCE` |
| `OUTPUT` | Returns (or stores into a table) the rows a DML statement touched: `inserted.*` = after image, `deleted.*` = before image, `$action` in MERGE | – |
| `TOP (n)` in DML | Limit an INSERT / UPDATE / DELETE to *n* arbitrary rows; used in loops to delete big tables in batches | – |

**Two virtual tables** exist during every DML statement:

| Statement | `inserted` | `deleted` |
|-----------|-----------|-----------|
| INSERT | new rows | – |
| UPDATE | rows **after** the change | rows **before** the change |
| DELETE | – | removed rows |
| MERGE | inserted / updated rows | deleted / updated rows (+ `$action` = INSERT, UPDATE or DELETE) |

**DELETE vs TRUNCATE vs DROP** (asked in almost every interview)

| | DELETE | TRUNCATE | DROP |
|--|--------|----------|------|
| Removes | some or all rows | all rows | the table |
| `WHERE` | yes | no | no |
| Logging | each row | page de-allocation only (fast) | metadata |
| Identity | keeps counting | resets to seed | gone |
| Triggers | DELETE triggers fire | none | none |
| FK pointing at table | blocked row by row (only rows with children) | refused entirely | refused |
| Rollback | yes | **yes** (inside a transaction) | yes |
| Type | DML | DDL | DDL |

## 2. Syntax cheat-sheet

```sql
-- INSERT
INSERT INTO dbo.T (Col1, Col2) VALUES (1, 'a');                       -- single row (always list the columns)
INSERT INTO dbo.T (Col1, Col2) VALUES (2, 'b'), (3, 'c');             -- multi-row (max 1000 per VALUES)
INSERT INTO dbo.T (Col1, Col2) SELECT Id, Name FROM dbo.Src WHERE ...; -- from a query
INSERT INTO dbo.T DEFAULT VALUES;                                     -- every column from DEFAULT / IDENTITY
INSERT INTO dbo.T (Col1) OUTPUT inserted.Id, inserted.Col1 VALUES (4);  -- see what was inserted
INSERT INTO dbo.T (Col1) OUTPUT inserted.Id INTO @Ids VALUES (5);     -- keep the ids
SELECT * INTO dbo.T_Copy FROM dbo.T;                                  -- new table + rows (no constraints!)
SELECT * INTO dbo.T_Empty FROM dbo.T WHERE 1 = 0;                     -- new table, structure only

-- UPDATE
UPDATE dbo.T SET Col1 = 10, Col2 = Col2 + 1 WHERE Id = 1;             -- many columns, ONE SET
UPDATE dbo.T SET Price = Price * 1.1 WHERE Category = 'X';            -- computed from the old value
UPDATE dbo.T SET A = B, B = A WHERE Id = 1;                           -- swap works (SET reads old values)
UPDATE t SET t.Col = s.Col FROM dbo.T t JOIN dbo.S s ON s.Id = t.Id WHERE ...;   -- UPDATE ... FROM JOIN
UPDATE dbo.T SET Col = (SELECT MAX(x) FROM dbo.S s WHERE s.Id = dbo.T.Id);       -- correlated subquery
UPDATE dbo.T SET Col = 0 WHERE Id IN (SELECT Id FROM dbo.S);          -- subquery in WHERE
UPDATE dbo.T SET Col = 1 OUTPUT deleted.Col AS OldVal, inserted.Col AS NewVal WHERE ...;

-- DELETE
DELETE FROM dbo.T WHERE Id = 1;                                       -- FROM is optional
DELETE t FROM dbo.T t JOIN dbo.S s ON s.Id = t.Id WHERE s.Flag = 1;    -- DELETE ... FROM JOIN
DELETE FROM dbo.T WHERE Id NOT IN (SELECT Id FROM dbo.S);             -- subquery (prefer NOT EXISTS)
DELETE FROM dbo.T OUTPUT deleted.* INTO dbo.T_History WHERE ...;      -- archive while deleting
TRUNCATE TABLE dbo.T;                                                 -- all rows, identity reset
DROP TABLE IF EXISTS dbo.T;

-- MERGE (upsert) - do not forget the final ;
MERGE dbo.Target AS t
USING dbo.Source AS s ON t.Id = s.Id
WHEN MATCHED AND (t.Price <> s.Price) THEN UPDATE SET t.Price = s.Price
WHEN NOT MATCHED BY TARGET THEN INSERT (Id, Price) VALUES (s.Id, s.Price)
WHEN NOT MATCHED BY SOURCE AND t.Category = 'X' THEN DELETE
OUTPUT $action, inserted.Id, deleted.Id;

-- TOP in DML
UPDATE TOP (10) dbo.T SET Flag = 1 WHERE Flag = 0;                    -- 10 ARBITRARY rows
;WITH c AS (SELECT TOP (10) * FROM dbo.T ORDER BY CreatedAt) UPDATE c SET Flag = 1;   -- controlled order
WHILE 1 = 1 BEGIN                                                     -- batch delete
    DELETE TOP (5000) FROM dbo.Log WHERE LogDate < '2024-01-01';
    IF @@ROWCOUNT = 0 BREAK;
END
```

## 3. Gotchas (things that bite beginners)

- **UPDATE / DELETE without WHERE touches every row.** Habit: `BEGIN TRAN` → run → check → `COMMIT` or `ROLLBACK`. Or write the `WHERE` first, then the `SET`.
- **`SELECT INTO` copies no constraints, defaults or indexes** (and no FKs). The copy accepts negative stock, duplicate ids, anything. Add keys afterwards with `ALTER TABLE`.
- **Always list the columns in INSERT.** `INSERT INTO T VALUES (...)` breaks the moment a column is added or reordered.
- **`INSERT ... SELECT` matches columns by position, not by name.**
- **`SET` reads the old row values**, which is why `SET A = B, B = A` swaps without a temp variable.
- **`@@ROWCOUNT` must be read immediately** after the statement — any other statement (even `SET`) resets it. Store it in a variable first.
- **`TRUNCATE` is refused when *any* FK references the table**, even if there are zero child rows. Drop / disable the FK or use `DELETE`.
- **`TRUNCATE` can be rolled back** in SQL Server (it is logged, just minimally). Common interview myth.
- **MERGE fails if one target row matches several source rows** (Msg 8672). De-duplicate the source or aggregate it.
- **`WHEN NOT MATCHED BY SOURCE THEN DELETE` deletes every target row absent from the source.** Restrict it with an `AND` or leave it out.
- **`NOT IN (subquery)` returns nothing if the subquery contains a NULL** — use `NOT EXISTS` (Level 09).
- **`UPDATE TOP (n)` / `DELETE TOP (n)` pick arbitrary rows** (no `ORDER BY` allowed). Wrap the ordered `TOP` in a CTE if the choice matters.
- **A failed statement inside `TRY/CATCH` is already rolled back** on its own; only an explicit transaction keeps earlier statements together (Level 16).

## 4. Interview questions

**Q: DELETE vs TRUNCATE vs DROP?**
DELETE removes rows (WHERE possible, row-by-row logging, identity kept, triggers fire). TRUNCATE removes all rows (minimal logging, identity reset, no WHERE, refused if an FK references the table, no triggers). DROP removes the table itself. All three can be rolled back inside a transaction.

**Q: Can TRUNCATE be rolled back?**
Yes, in SQL Server. It is minimally logged (page de-allocations), not un-logged. Inside `BEGIN TRAN ... ROLLBACK` the rows come back.

**Q: What is the OUTPUT clause?**
It returns the rows a DML statement affected: `inserted.*` (new image) and `deleted.*` (old image). Use it to get generated ids, audit changes, or archive deleted rows with `OUTPUT ... INTO`.

**Q: Difference between `inserted` and `deleted` tables in an UPDATE?**
`deleted` holds the rows as they were before the update, `inserted` as they are after. Both have the same columns as the table.

**Q: How do you copy a table?**
`SELECT * INTO NewTable FROM OldTable` (structure + data, no constraints / indexes), or `... WHERE 1 = 0` for structure only. Then add keys/indexes with `ALTER TABLE` / `CREATE INDEX`.

**Q: How do you update one table using values from another?**
`UPDATE t SET t.Col = s.Col FROM dbo.Target t JOIN dbo.Source s ON s.Id = t.Id;` (T-SQL `UPDATE ... FROM`) or a correlated subquery in `SET`.

**Q: What is MERGE / upsert?**
One statement that compares a source to a target on a key and applies `WHEN MATCHED` (update / delete), `WHEN NOT MATCHED BY TARGET` (insert), `WHEN NOT MATCHED BY SOURCE` (delete / update). `OUTPUT $action` shows what happened per row. Many teams prefer a plain UPDATE + INSERT ... WHERE NOT EXISTS pair for simplicity.

**Q: How do you delete millions of rows without blocking everyone?**
Loop `DELETE TOP (n) ... WHERE <condition>` until `@@ROWCOUNT = 0`, committing each batch; small batches keep the log small and release locks between iterations.

**Q: Does DELETE reset the identity value? Does a rollback?**
No and no. Only `TRUNCATE` or `DBCC CHECKIDENT (..., RESEED)` change the counter. Gaps are normal.

**Q: What does `INSERT ... DEFAULT VALUES` do?**
Inserts one row using the DEFAULT of every column (identity generated). Every column must be nullable, have a default, or be an identity column.

**Q: Why should you always write the column list in an INSERT?**
Without it the VALUES are matched to columns by position, so adding, dropping or reordering a column silently breaks the statement (or puts data in the wrong column). The list also lets you skip columns that have defaults.

**Q: What is `@@ROWCOUNT` and when do you read it?**
The number of rows affected by the last statement. Read it immediately (or `SET @n = @@ROWCOUNT` as the very next line) because any following statement resets it. It drives batch loops and "did my UPDATE hit anything?" checks.

## 5. Checklist

- [ ] I can insert with VALUES (one or many rows), INSERT ... SELECT, SELECT ... INTO and DEFAULT VALUES
- [ ] I know what SELECT ... INTO copies and what it does not
- [ ] I can update several columns, compute from old values, and use UPDATE ... FROM JOIN and subqueries
- [ ] I can delete with WHERE, with a JOIN, with a subquery, and archive rows with OUTPUT ... INTO
- [ ] I can explain DELETE vs TRUNCATE vs DROP (identity, logging, WHERE, FK, rollback)
- [ ] I can write a MERGE with all three WHEN branches and read `$action`
- [ ] I can delete a big table in batches with DELETE TOP in a loop
