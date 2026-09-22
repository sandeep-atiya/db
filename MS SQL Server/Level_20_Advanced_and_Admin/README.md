# Level 20 — Advanced T-SQL and Administration

**Goal:** round off the developer toolbox (dynamic SQL, modern functions, temporal tables, triggers, cursors, sequences, JSON/XML) and know the admin basics every SQL Server developer is asked about: security (login/user/role, GRANT/DENY/REVOKE), backup and restore, SQL Agent, linked servers and maintenance.

**Time:** ~5 hrs · **Files:** `01_Practice_Advanced_TSQL.sql` → `02_Practice_Triggers_Cursors_Sequences.sql` → `03_Practice_JSON_XML.sql` → `04_Practice_Security.sql` → `05_Practice_Backup_Restore_Agent.sql` → `Exercises.sql`

> Files 04 and 05 create server-level objects (a login, backup files, an Agent job, a linked server, a restored database). Each file removes everything it created in its CLEANUP section. Full-text search runs only if the feature is installed (the script checks and otherwise prints the syntax).

---

## 1. Concepts in plain words

| Term | Meaning |
|------|---------|
| **sp_executesql** | Runs dynamic SQL **with parameters**: one cached plan, no injection through values. Identifiers still need `QUOTENAME`. |
| **Temporal table** | Table with two system period columns + a history table; the engine keeps every old row version. Query the past with `FOR SYSTEM_TIME AS OF`. |
| **Computed column** | A formula column; `PERSISTED` stores the value and allows an index on it. **Sparse** column: NULLs cost no space (for mostly-NULL columns). |
| **Trigger** | Code that runs automatically on INSERT/UPDATE/DELETE (DML, `AFTER` or `INSTEAD OF`) or on DDL events. Fires **once per statement**; `inserted` / `deleted` hold the rows. |
| **Cursor** | Row-by-row loop over a result set (`DECLARE … CURSOR`, `OPEN`, `FETCH`, `@@FETCH_STATUS`, `CLOSE`, `DEALLOCATE`). Slow; use only when a set-based statement is impossible. |
| **Sequence** | Stand-alone number generator (`NEXT VALUE FOR`), sharable across tables, can be fetched before the insert; gaps are normal. `IDENTITY` is tied to one column. |
| **JSON / XML** | Document formats. SQL Server has `FOR JSON`/`OPENJSON`/`JSON_VALUE` … and `FOR XML`/`.nodes()`/`.value()` …; XML has a real data type and indexes, JSON gets a native type in SQL 2025. |
| **Login vs user** | Login = server principal (can connect to the instance). User = database principal mapped to a login by SID (can enter one database). **Orphaned user** = user whose login SID no longer exists. |
| **Role** | Container of permissions: fixed server roles (`sysadmin` …), fixed database roles (`db_owner`, `db_datareader` …) and custom roles (`CREATE ROLE`). |
| **GRANT / DENY / REVOKE** | Give / explicitly forbid / remove an entry. **DENY always wins** over any GRANT, at any level of role membership. |
| **Ownership chaining** | When a proc/view and the tables it uses have the same owner, only the proc/view permission is checked – users can run reports without table rights (DENY on the table is also skipped!). |
| **Recovery model** | `SIMPLE` (log truncates itself, no log backups), `FULL` (log kept until log backup → point-in-time restore), `BULK_LOGGED` (FULL with minimally logged bulk operations). |
| **Full / differential / log backup** | Full = everything; differential = extents changed since the last **full**; log = log records since the last log backup. `COPY_ONLY` = a full backup that does not disturb the chain. |
| **NORECOVERY / RECOVERY** | `NORECOVERY` = "more files follow" (database stays *Restoring*); `RECOVERY` = finish and open. `STOPAT = time` on the log restore = point-in-time. |
| **SQL Server Agent** | The built-in scheduler service: jobs (steps + schedules + target server) stored in `msdb`; history in `sysjobhistory`. |
| **Linked server** | A registered remote data source queried with four-part names (`server.db.schema.table`) or `OPENQUERY` (pass-through). |

### Recovery models

| Model | Log backups | Point-in-time restore | Typical use |
|-------|-------------|-----------------------|-------------|
| SIMPLE | not possible | no (last full/diff only) | dev/test, reload-able warehouses |
| FULL | required (or the log grows forever) | yes | production OLTP |
| BULK_LOGGED | required | yes, except across a log backup containing bulk operations | temporarily during bulk loads / index rebuilds |

### JSON functions

| Function | Purpose | Example |
|----------|---------|---------|
| `FOR JSON AUTO / PATH` | rows → JSON (`ROOT`, `INCLUDE_NULL_VALUES`, `WITHOUT_ARRAY_WRAPPER`) | `SELECT … FOR JSON PATH, ROOT('orders')` |
| `ISJSON(x)` | 1 if valid JSON | `CHECK (ISJSON(Payload) = 1)` |
| `JSON_VALUE(x, path)` | one **scalar** | `JSON_VALUE(@j, '$.customer.name')` |
| `JSON_QUERY(x, path)` | an **object / array** | `JSON_QUERY(@j, '$.lines')` |
| `JSON_MODIFY(x, path, v)` | change / add / `append` / delete (NULL) | `JSON_MODIFY(@j, 'append $.tags', 'x')` |
| `OPENJSON(x) [WITH (…)]` | JSON → rows (`AS JSON` for nested arrays + `CROSS APPLY`) | `OPENJSON(@j, '$.lines') WITH (qty INT)` |
| `JSON_OBJECT / JSON_ARRAY` (2022+) | build JSON in an expression | `JSON_OBJECT('id': ProductID)` |
| `json` type (2025) | native binary JSON column/variable | `DECLARE @d JSON` |

## 2. Syntax cheat-sheet

```sql
-- dynamic SQL
EXEC sp_executesql N'SELECT … WHERE Col = @p', N'@p INT, @out INT OUTPUT', @p = 1, @out = @v OUTPUT;
SELECT STRING_AGG(QUOTENAME(name), ', ') WITHIN GROUP (ORDER BY column_id) FROM sys.columns WHERE object_id = OBJECT_ID('dbo.T');
-- lists / pivot / dates / 2022 functions
STRING_SPLIT(@csv, ',' [, 1])   STRING_AGG(col, ', ') WITHIN GROUP (ORDER BY col)
SELECT … FROM (…) src PIVOT (COUNT(x) FOR Status IN ([A],[B])) p;     UNPIVOT (Value FOR Attr IN (c1, c2)) u
GENERATE_SERIES(1, 12)   DATETRUNC(QUARTER, d)   DATE_BUCKET(WEEK, 2, d)   a IS [NOT] DISTINCT FROM b   GREATEST(a,b)  LEAST(a,b)
TRIM(LEADING '0' FROM s)   APPROX_COUNT_DISTINCT(col)
-- temporal
CREATE TABLE T (…, ValidFrom DATETIME2 GENERATED ALWAYS AS ROW START, ValidTo DATETIME2 GENERATED ALWAYS AS ROW END,
                PERIOD FOR SYSTEM_TIME (ValidFrom, ValidTo)) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = dbo.T_History));
SELECT * FROM T FOR SYSTEM_TIME AS OF '2025-01-01';      ALTER TABLE T SET (SYSTEM_VERSIONING = OFF);  -- before DROP
-- triggers / cursors / sequences
CREATE TRIGGER trg ON dbo.T AFTER INSERT, UPDATE, DELETE AS … inserted / deleted … IF UPDATE(Col) … COLUMNS_UPDATED()
CREATE TRIGGER trg ON dbo.V INSTEAD OF DELETE AS …          CREATE TRIGGER trg ON DATABASE FOR DROP_TABLE AS … ROLLBACK;
DISABLE TRIGGER trg ON dbo.T;  ENABLE TRIGGER trg ON dbo.T;  SELECT * FROM sys.triggers;
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT …; OPEN c; FETCH NEXT FROM c INTO @v; WHILE @@FETCH_STATUS = 0 BEGIN … FETCH NEXT … END; CLOSE c; DEALLOCATE c;
CREATE SEQUENCE dbo.s AS INT START WITH 1 INCREMENT BY 1 CACHE 10;  NEXT VALUE FOR dbo.s;  ALTER SEQUENCE dbo.s RESTART WITH 100;
EXEC sp_sequence_get_range @sequence_name = 'dbo.s', @range_size = 5, @range_first_value = @f OUTPUT;
SCOPE_IDENTITY()  @@IDENTITY  IDENT_CURRENT('dbo.T')  DBCC CHECKIDENT ('dbo.T', RESEED, 100);
-- XML
SELECT … FOR XML RAW | AUTO | PATH('row'), ROOT('root'), ELEMENTS;
STUFF((SELECT ', ' + Name FROM … FOR XML PATH(''), TYPE).value('.', 'VARCHAR(MAX)'), 1, 2, '')   -- pre-2017 STRING_AGG
@x.value('(/a/b)[1]', 'INT')  @x.query('/a')  @x.exist('/a[@id=1]')  FROM @x.nodes('/a/b') AS t(n)
-- security
CREATE LOGIN L WITH PASSWORD = '…';  CREATE USER U FOR LOGIN L;  CREATE ROLE R;  ALTER ROLE R ADD MEMBER U;
GRANT SELECT ON SCHEMA::dbo TO R;  DENY SELECT ON dbo.T (Salary) TO U;  REVOKE SELECT ON dbo.T FROM U;
EXECUTE AS USER = 'U'; … REVERT;   fn_my_permissions('dbo.T', 'OBJECT')   HAS_PERMS_BY_NAME('dbo.T', 'OBJECT', 'SELECT')
ALTER USER U WITH LOGIN = L;       -- fix an orphaned user  (report: sp_change_users_login 'Report')
-- backup / restore
ALTER DATABASE db SET RECOVERY FULL;
BACKUP DATABASE db TO DISK = 'path\db_Full.bak' WITH INIT, COMPRESSION, CHECKSUM, STATS = 25;
BACKUP DATABASE db TO DISK = '…_Diff.bak' WITH DIFFERENTIAL;   BACKUP LOG db TO DISK = '…_Log.trn';   … WITH COPY_ONLY
RESTORE VERIFYONLY | HEADERONLY | FILELISTONLY FROM DISK = '…';
RESTORE DATABASE db2 FROM DISK = '…_Full.bak' WITH NORECOVERY, MOVE 'logical' TO 'D:\…\db2.mdf', MOVE 'logical_log' TO '…ldf';
RESTORE DATABASE db2 FROM DISK = '…_Diff.bak' WITH NORECOVERY;
RESTORE LOG db2 FROM DISK = '…_Log.trn' WITH STOPAT = '2025-09-22 12:00:00', RECOVERY;
SELECT * FROM msdb.dbo.backupset bs JOIN msdb.dbo.backupmediafamily f ON f.media_set_id = bs.media_set_id;
-- agent / linked server / maintenance
EXEC msdb.dbo.sp_add_job …; sp_add_jobstep …; sp_add_jobschedule …; sp_add_jobserver …; sp_start_job …; sp_delete_job …;
EXEC sp_addlinkedserver @server = 'X', @srvproduct = '', @provider = 'MSOLEDBSQL', @datasrc = 'host'; EXEC sp_addlinkedsrvlogin 'X', 'TRUE';
SELECT * FROM X.db.dbo.T;   SELECT * FROM OPENQUERY(X, 'SELECT …');   EXEC sp_dropserver 'X', 'droplogins';
DBCC CHECKDB WITH NO_INFOMSGS;   ALTER INDEX ALL ON dbo.T REORGANIZE | REBUILD;   EXEC sp_updatestats;
```

## 3. Gotchas

- **Never concatenate user input into SQL text** – `'x'' OR 1=1 --'` returned all customers in the demo. Values → parameters, identifiers → `QUOTENAME`.
- **Triggers fire once per statement**: `SELECT @id = OrderID FROM inserted` silently handles only one row. Always join `inserted`/`deleted` as sets.
- **`UPDATE(col)` is true when the column is in the SET list even if the value did not change**; compare `inserted` with `deleted` to detect real changes.
- **An INSTEAD OF trigger's own DML fires other AFTER triggers** (nested triggers, default ON) – a "rule" trigger can roll back your soft delete.
- **DDL triggers block everything they match, including your cleanup** – drop them first.
- `NEXT VALUE FOR` twice in the **same row** returns the same number; sequences and identities both have **gaps** (rollback, cache loss) – never use them as row counters.
- **`JSON_VALUE` returns NULL for objects/arrays** – use `JSON_QUERY`; Query Store / `FOR JSON` dates come out as ISO strings.
- **`SET QUOTED_IDENTIFIER ON`** is required for XML methods and for indexes on computed columns; sqlcmd defaults to OFF, SSMS to ON.
- **DENY beats GRANT**, and a DENY on one column removes table-level `SELECT` (`SELECT *` fails). But **ownership chaining skips the DENY** when a dbo view selects the column.
- **`DROP LOGIN` does not drop the database users** → orphans; after restoring a database on another server, remap with `ALTER USER … WITH LOGIN`.
- **FULL model without log backups = a log file that grows until the disk is full.** Switching to SIMPLE and back breaks the chain – take a new full backup afterwards.
- **A differential is based on the last FULL** – a stray full backup (without `COPY_ONLY`) resets the base and breaks the DBA's restore plan.
- Restores with `NORECOVERY` leave the database in *Restoring*; finish with `RESTORE DATABASE db WITH RECOVERY`.
- `sp_start_job` fails when the Agent **service** is stopped; jobs run asynchronously (check `sysjobhistory`).
- Linked-server joins pull data across the network row by row in the worst case; use `OPENQUERY` for remote filtering and ETL tools for volume.

## 4. Interview questions

**Q: Triggers vs constraints – when do you use which?**
Constraints (PK, FK, UNIQUE, CHECK, DEFAULT) are declarative, checked by the engine before the write, cheap and impossible to bypass. Use a trigger only for what a constraint cannot express: auditing (old/new values), cross-table rules, soft deletes via INSTEAD OF, DDL auditing. Triggers are hidden, run inside the caller's transaction and break easily on multi-row statements.

**Q: Cursor vs set-based?**
A cursor processes one row at a time (plan lookup, locks, log per iteration); a set-based statement does one pass. Measured: 20,000 cursor updates ≈ seconds, one `UPDATE` ≈ 10 ms. Use cursors only for per-row procedural calls (e.g. backup each database) or admin scripts.

**Q: Sequence vs IDENTITY?**
IDENTITY belongs to one column of one table and gives the value only after the insert (`SCOPE_IDENTITY()`). A sequence is an independent object usable by many tables, can be asked for the next value or a range before inserting, can restart or cycle. Both can have gaps.

**Q: Explain the main JSON functions.**
`FOR JSON` produces JSON from rows; `OPENJSON` turns JSON into rows (`WITH` for typed columns, `AS JSON` for nested arrays); `JSON_VALUE` extracts a scalar, `JSON_QUERY` an object/array, `JSON_MODIFY` changes it, `ISJSON` validates. Store JSON in `NVARCHAR(MAX)` with `CHECK (ISJSON(col) = 1)` and index hot keys through computed columns (SQL 2025 adds a native `json` type).

**Q: What is the FOR XML PATH trick?**
Before `STRING_AGG` (2017) the way to build a comma-separated list per group: a correlated subquery `SELECT ', ' + Name … FOR XML PATH(''), TYPE` produces one string, `.value('.', 'VARCHAR(MAX)')` un-escapes it and `STUFF(…, 1, 2, '')` removes the leading separator.

**Q: Login vs user? What is an orphaned user?**
A login lives in `master` and allows connecting to the instance; a user lives in a database and is mapped to the login by SID. When the login is missing or has a different SID (typical after restoring a database on another server), the user is orphaned: find with a SID join to `sys.server_principals` (or `sp_change_users_login 'Report'`), fix with `ALTER USER u WITH LOGIN = l`.

**Q: GRANT vs DENY vs REVOKE?**
GRANT gives a permission, DENY explicitly forbids it and wins over any GRANT inherited through roles, REVOKE removes a GRANT or a DENY entry (it is not itself a "no"). Permissions can target a table, a schema (`ON SCHEMA::dbo`, covers future objects) or columns.

**Q: What is ownership chaining?**
If a view/proc and the tables it uses have the same owner, SQL Server checks only the permission on the view/proc. That is how you give report users EXECUTE on a proc without SELECT on the tables. The chain also skips DENYs on the underlying tables, so secure the outer objects.

**Q: Explain SIMPLE, FULL and BULK_LOGGED recovery models.**
SIMPLE: log space is reused at checkpoints, no log backups, restore only to the last full/differential. FULL: log records are kept until backed up, enabling point-in-time restore; requires regular log backups. BULK_LOGGED: like FULL but bulk operations are minimally logged (faster loads, no point-in-time inside that log backup).

**Q: Full vs differential vs log backup, and a typical restore sequence?**
Full = the whole database; differential = all changes since the last full (independent of other diffs); log = log records since the last log backup (only in FULL/BULK_LOGGED). Restore: last full `WITH NORECOVERY` → last differential `WITH NORECOVERY` → every log backup after it in order `WITH NORECOVERY` → last one `WITH RECOVERY` (optionally `STOPAT` for point-in-time). Use `MOVE` to relocate files when restoring under a new name.

**Q: What is SQL Server Agent?**
The scheduling service of SQL Server: jobs made of steps (T-SQL, PowerShell, SSIS, CmdExec) with schedules, alerts and operators, stored in `msdb`. Used for backups, integrity checks, index/statistics maintenance, ETL. Managed with `sp_add_job`, `sp_add_jobstep`, `sp_add_jobschedule`, `sp_add_jobserver`, `sp_start_job`; history in `sysjobhistory`.

**Q: What is a linked server?**
A definition of a remote OLE DB data source (another SQL Server, Oracle, Excel …) that you query with four-part names or `OPENQUERY`. Security is mapped with `sp_addlinkedsrvlogin`. Good for occasional cross-server queries; for heavy data movement use ETL/replication.

**Q: What routine maintenance do you schedule?**
Integrity check (`DBCC CHECKDB`), index reorganize/rebuild by fragmentation, statistics update, full/differential/log backups, backup file and history cleanup, and regular restore tests – usually as Agent jobs (or Ola Hallengren's scripts).

## 5. Checklist

- [ ] I can write injection-safe dynamic SQL with `sp_executesql` and `QUOTENAME`
- [ ] I can use `STRING_SPLIT`, `STRING_AGG`, `PIVOT`/`UNPIVOT`, `GENERATE_SERIES`, `DATETRUNC`, `IS DISTINCT FROM`
- [ ] I can create a temporal table and query it `AS OF` a past time
- [ ] I can write a multi-row-safe audit trigger, an INSTEAD OF trigger and a DDL trigger, and explain why constraints come first
- [ ] I can write a cursor from memory and the set-based alternative
- [ ] I can create a sequence, share it across tables and explain gaps
- [ ] I can produce and shred JSON and XML, and do the FOR XML PATH aggregation trick
- [ ] I can create login → user → role, GRANT/DENY/REVOKE, test with `EXECUTE AS` and fix an orphaned user
- [ ] I can take full/diff/log backups, restore them to a new name with MOVE and do a STOPAT restore
- [ ] I can create and run an Agent job, define a linked server and describe the weekly maintenance plan
