# Level 01 — Database Basics (DDL)

**Goal:** be comfortable creating, changing and dropping databases, schemas and tables, and know where SQL Server keeps information about them.

**Time:** ~45 min · **Files:** `01_Practice.sql` → `Exercises.sql`

---

## 1. Concepts in plain words

| Term | Meaning |
|------|---------|
| **Database** | A container of objects (tables, views, procedures…). Physically = one data file (`.mdf`) + one log file (`.ldf`). |
| **System databases** | `master` (server config, logins), `model` (template for new DBs), `msdb` (SQL Agent jobs, backups history), `tempdb` (temp tables, sorting; **rebuilt at every restart** → never store practice data there). |
| **`USE db`** | Switches the *current* database of your session. |
| **`GO`** | **Not a T-SQL statement.** It is a *batch separator* understood by SSMS / sqlcmd. Everything between two `GO`s is sent to the server as one batch. Variables (`DECLARE`) die at `GO`. Some statements (`CREATE PROCEDURE`, `CREATE VIEW`, `CREATE SCHEMA`) must be the **first statement in a batch**, which is why they need a `GO` before them. |
| **Schema** | A *namespace* inside a database (`Sales.Orders`, `HR.Employees`). Default schema is `dbo`. Used to organise objects and to grant permissions on a group of objects. |
| **DDL vs DML** | DDL = *Data Definition* (`CREATE / ALTER / DROP`). DML = *Data Manipulation* (`SELECT / INSERT / UPDATE / DELETE`). |
| **Catalog views** | `sys.databases`, `sys.schemas`, `sys.tables`, `sys.columns` – tables the server uses to describe itself. `INFORMATION_SCHEMA.*` is the ANSI-standard version. |

## 2. Syntax cheat-sheet

```sql
-- DATABASE
CREATE DATABASE MyDB;
ALTER  DATABASE MyDB SET READ_ONLY;          -- or READ_WRITE, SINGLE_USER, MULTI_USER
ALTER  DATABASE MyDB MODIFY NAME = MyDB2;    -- rename
DROP   DATABASE MyDB;                        -- you must NOT be inside it (USE master first)
DROP   DATABASE IF EXISTS MyDB;              -- SQL 2016+

-- SCHEMA
CREATE SCHEMA Sales;                         -- must be alone in its batch
DROP   SCHEMA Sales;                         -- schema must be EMPTY

-- TABLE
CREATE TABLE Sales.Customers (Id INT PRIMARY KEY, Name VARCHAR(50) NOT NULL);
ALTER  TABLE Sales.Customers ADD   Email VARCHAR(100);           -- add column
ALTER  TABLE Sales.Customers ALTER COLUMN Name VARCHAR(100);     -- change type / nullability
ALTER  TABLE Sales.Customers DROP  COLUMN Email;                 -- remove column
EXEC sp_rename 'Sales.Customers.Name', 'FullName', 'COLUMN';     -- rename column
DROP   TABLE IF EXISTS Sales.Customers;

-- LOOK AROUND
SELECT name FROM sys.databases;
SELECT DB_NAME();
SELECT * FROM sys.tables;                    -- or INFORMATION_SCHEMA.TABLES
SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'Employees';
EXEC sp_help 'dbo.Employees';
```

## 3. Gotchas (things that bite beginners)

- **Cannot drop a database you are connected to.** `USE master;` first. If other sessions are connected use `ALTER DATABASE x SET SINGLE_USER WITH ROLLBACK IMMEDIATE;`.
- **Cannot drop a schema that still contains objects.** Drop / move the objects first.
- `CREATE SCHEMA` **must be the only statement in the batch** → put `GO` before and after.
- `ALTER COLUMN` fails if the column is part of a PK / index / constraint, or if the new type cannot hold existing data.
- `DROP COLUMN` fails if a constraint (DEFAULT, CHECK, FK) still references the column – drop the constraint first.
- `GO` inside a stored procedure or an `IF` block breaks it, because `GO` ends the batch.
- Always write **`schema.table`** (`dbo.Employees`) – it is faster (no name resolution) and avoids ambiguity.

## 4. Interview questions

**Q: What is the difference between `DELETE`, `TRUNCATE` and `DROP`?**
`DELETE` removes rows (can have `WHERE`, logged row-by-row, keeps identity). `TRUNCATE` removes all rows (minimal logging, resets identity, cannot have `WHERE`, needs no FK pointing to the table). `DROP` removes the table itself (structure + data + indexes + permissions).

**Q: What is `GO`? Is it a T-SQL command?**
No. It is a batch separator interpreted by the client tool (SSMS / sqlcmd). The server never sees it.

**Q: What are the system databases and what does each hold?**
`master` – server-level config & logins; `model` – template for new databases; `msdb` – SQL Agent jobs, alerts, backup history; `tempdb` – temporary objects, sorts, versions; recreated on restart.

**Q: What is a schema and why use one?**
A logical namespace for objects. Benefits: organisation (`Sales.*`, `HR.*`), security (grant on schema), avoids name clashes, easier ownership changes.

**Q: What is the default schema?**
`dbo` (database owner). If you write `SELECT * FROM Employees` SQL Server looks in your user's default schema, then `dbo`.

**Q: Why should you not use `tempdb` for permanent data?**
It is recreated from `model` every time the SQL Server service restarts – everything in it is lost.

**Q: How do you see all tables / columns of a database?**
`sys.tables`, `sys.columns`, `INFORMATION_SCHEMA.TABLES / COLUMNS`, `sp_help 'table'`, or Object Explorer.

## 5. Checklist

- [ ] I can create, rename, set read-only and drop a database
- [ ] I know why `USE master` is needed before `DROP DATABASE`
- [ ] I know what `GO` really is
- [ ] I can create a schema and a table inside it
- [ ] I can add / alter / drop / rename a column
- [ ] I can list databases, tables and columns with catalog views
