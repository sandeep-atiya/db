# Level 03 — Constraints

**Goal:** make the database itself reject bad data — keys, references, rules, defaults and auto-numbers — and know how to find, add, drop, disable and re-enable every constraint.

**Time:** ~2 hr · **Files:** `01_Practice_Keys.sql` → `02_Practice_Rules.sql` → `03_Practice_Identity.sql` → `04_Practice_Manage_Constraints.sql` → `Exercises.sql`

---

## 1. Concepts in plain words

A **constraint** is a rule the table enforces on every `INSERT` / `UPDATE` / `DELETE`. If the rule is broken the statement fails and nothing changes. Rules in the database are better than rules only in application code: every app, script and import job gets the same protection.

| Constraint | Meaning | Per table | NULL allowed? | Index created |
|------------|---------|-----------|---------------|---------------|
| **PRIMARY KEY** | Identifies one row. Unique + NOT NULL. Can be **composite** (several columns). | **1** | No | **Clustered** by default (`PRIMARY KEY NONCLUSTERED` to change) |
| **UNIQUE** | No duplicates. | Many | **One** NULL only (SQL Server treats NULL as a value here) | Nonclustered by default |
| **FOREIGN KEY** | Value must exist in the parent's PK / UNIQUE column. Can point at the **same table** (self-referencing, `ManagerID → EmployeeID`). | Many | Yes (NULL is never checked) | None (create one yourself, Level 17) |
| **NOT NULL** | Column must have a value. A column property, not a named constraint. | – | No | – |
| **CHECK** | Boolean rule: column-level (`Salary > 0`) or table-level / multi-column (`ManagerID <> EmployeeID`). | Many | **NULL passes** (UNKNOWN is not FALSE) | – |
| **DEFAULT** | Value used when the INSERT does not mention the column. Constant or function (`GETDATE()`, `NEWID()`, `SUSER_SNAME()`). | 1 per column | – | – |
| **IDENTITY(seed, inc)** | Auto-number. Not really a constraint; a column property. | 1 | No | – |

**Referential actions** – what the child does when the parent row is deleted / its key updated (`ON DELETE ... ON UPDATE ...`):

| Action | Effect on child rows | Note |
|--------|---------------------|------|
| `NO ACTION` (default) | Statement fails if children exist | Same as `RESTRICT` in other DBs |
| `CASCADE` | Children deleted / key updated too | Not allowed on a self-referencing FK ("may cause cycles") |
| `SET NULL` | FK column set to NULL | Column must be nullable |
| `SET DEFAULT` | FK column set to its DEFAULT | Default value must exist in the parent |

**Identity functions**

| Function | Returns | Use it when |
|----------|---------|-------------|
| `SCOPE_IDENTITY()` | Last identity generated **in your scope** (batch / procedure) | **Always**, to get the id you just inserted |
| `@@IDENTITY` | Last identity in your **session, any scope** – a trigger's insert changes it | Almost never |
| `IDENT_CURRENT('table')` | Last identity for that **table, any session** | Reporting only; another user may have inserted |

## 2. Syntax cheat-sheet

```sql
-- In CREATE TABLE (always NAME them: PK_ / FK_ / UQ_ / CK_ / DF_)
CREATE TABLE dbo.Employees
(
    EmployeeID   INT           NOT NULL IDENTITY(1,1),
    Email        VARCHAR(150)  NULL,
    DepartmentID INT           NULL,
    Salary       DECIMAL(12,2) NULL,
    Status       VARCHAR(20)   NOT NULL CONSTRAINT DF_Employees_Status DEFAULT ('Active'),
    ManagerID    INT           NULL,
    CONSTRAINT PK_Employees             PRIMARY KEY (EmployeeID),                    -- or PRIMARY KEY (A, B) composite
    CONSTRAINT UQ_Employees_Email       UNIQUE (Email),
    CONSTRAINT CK_Employees_Salary      CHECK (Salary > 0),
    CONSTRAINT CK_Employees_NotOwnMgr   CHECK (ManagerID <> EmployeeID),             -- multi-column = table-level
    CONSTRAINT FK_Employees_Departments FOREIGN KEY (DepartmentID) REFERENCES dbo.Departments (DepartmentID)
        ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT FK_Employees_Manager     FOREIGN KEY (ManagerID) REFERENCES dbo.Employees (EmployeeID)  -- self-ref
);

-- Later, with ALTER TABLE
ALTER TABLE dbo.T ADD CONSTRAINT PK_T PRIMARY KEY (Id);
ALTER TABLE dbo.T ADD CONSTRAINT UQ_T_Code UNIQUE (Code);
ALTER TABLE dbo.T ADD CONSTRAINT FK_T_Parent FOREIGN KEY (ParentId) REFERENCES dbo.Parent (Id) ON DELETE CASCADE;
ALTER TABLE dbo.T ADD CONSTRAINT CK_T_Qty CHECK (Qty >= 0);
ALTER TABLE dbo.T ADD CONSTRAINT DF_T_Status DEFAULT ('New') FOR Status;          -- note FOR column
ALTER TABLE dbo.T ADD Notes VARCHAR(50) NULL CONSTRAINT DF_T_Notes DEFAULT ('-') WITH VALUES;  -- fill old rows too
ALTER TABLE dbo.T ALTER COLUMN Name VARCHAR(100) NOT NULL;                         -- NOT NULL is ALTER COLUMN
ALTER TABLE dbo.T DROP CONSTRAINT CK_T_Qty, DF_T_Status;                           -- one syntax for all kinds
-- there is no ALTER CONSTRAINT: DROP + ADD

-- Skip validation of existing rows / disable / enable (FK and CHECK only)
ALTER TABLE dbo.T WITH NOCHECK ADD CONSTRAINT CK_T_Max CHECK (Qty <= 1000);  -- untrusted
ALTER TABLE dbo.T NOCHECK CONSTRAINT FK_T_Parent;          -- disable (bulk load)
ALTER TABLE dbo.T CHECK CONSTRAINT FK_T_Parent;            -- enable, existing rows NOT checked -> untrusted
ALTER TABLE dbo.T WITH CHECK CHECK CONSTRAINT FK_T_Parent; -- enable AND validate -> trusted
ALTER TABLE dbo.T NOCHECK CONSTRAINT ALL;   /  ALTER TABLE dbo.T WITH CHECK CHECK CONSTRAINT ALL;

-- Identity
SELECT SCOPE_IDENTITY(), @@IDENTITY, IDENT_CURRENT('dbo.T'), IDENT_SEED('dbo.T'), IDENT_INCR('dbo.T');
SET IDENTITY_INSERT dbo.T ON;  INSERT INTO dbo.T (Id, Name) VALUES (5, 'x');  SET IDENTITY_INSERT dbo.T OFF;
DBCC CHECKIDENT ('dbo.T', NORESEED);          -- show current value
DBCC CHECKIDENT ('dbo.T', RESEED, 100);       -- next value = 101 (or 100 if the table never had rows)

-- Find them
SELECT * FROM sys.key_constraints;      -- PK + UNIQUE      (type PK / UQ)
SELECT * FROM sys.foreign_keys;         -- FK + actions + is_disabled + is_not_trusted (+ sys.foreign_key_columns)
SELECT * FROM sys.check_constraints;    -- definition, is_disabled, is_not_trusted
SELECT * FROM sys.default_constraints;  -- definition, parent_column_id
SELECT * FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS;   -- ANSI: PK / UNIQUE / FK / CHECK (no DEFAULT)
SELECT * FROM sys.identity_columns;     -- seed_value, increment_value, last_value
EXEC sp_helpconstraint 'dbo.T';
```

## 3. Gotchas (things that bite beginners)

- **`UNIQUE` allows only ONE NULL** in SQL Server (ANSI says any number). Need many NULLs? Use a filtered unique index: `CREATE UNIQUE INDEX UX ON dbo.T (Email) WHERE Email IS NOT NULL;`
- **`CHECK` lets NULL through.** `CHECK (Salary > 0)` accepts `Salary = NULL` because the result is UNKNOWN, not FALSE. Add `NOT NULL` if you mean it.
- **Explicit `NULL` beats a `DEFAULT`.** `INSERT ... VALUES (NULL)` stores NULL; the default is used only when the column is *omitted* (or you write the keyword `DEFAULT`).
- **Adding a nullable column with a DEFAULT leaves existing rows NULL** unless you add `WITH VALUES`. A `NOT NULL` column with a DEFAULT fills them automatically.
- **Identity values are never given back.** A ROLLBACK, a failed insert or a DELETE leaves a gap. Gaps are normal; do not "fix" them.
- **`@@IDENTITY` is wrong when a trigger inserts into another identity table.** Use `SCOPE_IDENTITY()`.
- **`RESEED` below the current MAX** = PK violation on the next insert. Reseed to `MAX(id)`. And on a *never-used* (or just truncated) table, `RESEED n` makes the next value `n`, not `n + 1`.
- **Self-referencing FK cannot CASCADE** (Msg 1785). Same for two cascade paths reaching one table.
- **`SET DEFAULT` needs a DEFAULT on the FK column** and the default value must exist in the parent.
- **Cannot drop a PK / UNIQUE that an FK references**, cannot drop a column that still has a DEFAULT / CHECK, cannot add a PK on a nullable column, cannot `ALTER COLUMN` a column that sits in a PK / UNIQUE / index.
- **`CHECK CONSTRAINT x` alone leaves the constraint untrusted** (`is_not_trusted = 1`). Write `WITH CHECK CHECK CONSTRAINT x` to validate the existing rows; only trusted constraints help the optimizer.
- **Unnamed constraints get random names** (`PK__Employee__7AD04FF1...`) which differ per server — scripts that drop them break. Always name.
- **Some DDL errors are compile-time** (second PK, PK on nullable column, update of an identity column): a `TRY/CATCH` in the same batch does not see them; the practice files run those through `EXEC('...')` so the CATCH block works.

## 4. Interview questions

**Q: Primary key vs unique key?**
Both enforce uniqueness. PK: one per table, no NULL, clustered index by default. UNIQUE: many per table, one NULL allowed, nonclustered index by default. A FK can reference either.

**Q: What is a composite key?**
A PK (or UNIQUE) made of two or more columns; the *combination* must be unique. Typical for link tables: `(EmployeeID, ProjectID)`.

**Q: What is a foreign key and what are the referential actions?**
A column whose values must exist in the parent's PK/UNIQUE column. On parent DELETE/UPDATE: `NO ACTION` (block, default), `CASCADE` (propagate), `SET NULL`, `SET DEFAULT`.

**Q: Can a foreign key column be NULL?**
Yes, unless you also declare NOT NULL. NULL is never checked against the parent (e.g. an employee with no department).

**Q: `SCOPE_IDENTITY()` vs `@@IDENTITY` vs `IDENT_CURRENT()`?**
`SCOPE_IDENTITY()` = last identity in the current scope (safe). `@@IDENTITY` = last in the session, any scope – a trigger's insert into another table changes it. `IDENT_CURRENT('t')` = last value for that table from any session.

**Q: How do you insert an explicit value into an identity column?**
`SET IDENTITY_INSERT dbo.T ON;` then an INSERT *with a column list*; then set it OFF. Only one table per session at a time.

**Q: Does a rollback reset the identity value?**
No. The value is consumed; the next insert skips it. Only `TRUNCATE TABLE` or `DBCC CHECKIDENT (..., RESEED, n)` change the counter.

**Q: What is the difference between column-level and table-level CHECK?**
Column-level checks one column (`Salary > 0`). Table-level can compare several columns of the same row (`EndDate >= StartDate`, `ManagerID <> EmployeeID`). Both are stored in `sys.check_constraints`.

**Q: Does a CHECK constraint reject NULL?**
No. `NULL > 0` is UNKNOWN, and CHECK only rejects FALSE. Use NOT NULL as well if NULL must be refused.

**Q: What does `WITH NOCHECK` do and why does it matter?**
Adds (or re-enables) a FK / CHECK without validating existing rows. The constraint becomes *untrusted*: new rows are still checked, but the optimizer cannot use the rule to simplify plans. `WITH CHECK CHECK CONSTRAINT` validates and makes it trusted again.

**Q: Can you disable a primary key?**
No. PK and UNIQUE are indexes; only FK and CHECK constraints can be disabled with `NOCHECK CONSTRAINT`.

**Q: Where do you see all constraints of a table?**
`sys.key_constraints`, `sys.foreign_keys`, `sys.check_constraints`, `sys.default_constraints`, `INFORMATION_SCHEMA.TABLE_CONSTRAINTS` (no defaults), or `EXEC sp_helpconstraint 'dbo.T'`.

## 5. Checklist

- [ ] I can create a table with named PK / FK / UNIQUE / CHECK / DEFAULT constraints
- [ ] I can explain PK vs UNIQUE (count per table, NULL, index type)
- [ ] I know all four referential actions and when CASCADE is refused
- [ ] I know why `CHECK` lets NULL through and why `UNIQUE` allows only one NULL
- [ ] I can get the new identity value safely and explain the three identity functions
- [ ] I can use `SET IDENTITY_INSERT` and `DBCC CHECKIDENT` and explain identity gaps
- [ ] I can add / drop / disable / enable constraints and tell trusted from untrusted
- [ ] I can list every constraint of `SQLPractice` with the catalog views
