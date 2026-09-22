/* ============================================================
   LEVEL 16 - TRANSACTIONS  |  02_Practice_Isolation_Locks.sql
   ------------------------------------------------------------
   Topics : lock modes (S, X, U, IS/IX, Sch-S/Sch-M), granularity,
            lock escalation, sys.dm_tran_locks, the 3 read phenomena,
            isolation levels (READ UNCOMMITTED, READ COMMITTED,
            REPEATABLE READ, SERIALIZABLE, SNAPSHOT, RCSI), reading
            the current level, lock hints (NOLOCK, READPAST, UPDLOCK,
            HOLDLOCK, ROWLOCK, TABLOCKX), finding blocking,
            LOCK_TIMEOUT, deadlocks (1205, DEADLOCK_PRIORITY, retry
            pattern, deadlock graph, prevention).
   HOW TO PRACTICE: run block by block, predict the output first.
   Everything here is SINGLE session: we open a transaction, look
   at our own locks, roll back. Two-session effects: file 03.
   ============================================================ */

USE SQLPractice;
GO
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;    -- sqlcmd default is OFF; the XML .query() in section 7c needs it ON
GO
DROP PROCEDURE IF EXISTS dbo.usp_L16_UpdateWithRetry;
DROP TABLE IF EXISTS dbo.L16_Accounts, dbo.L16_Big;
GO
SELECT c.CustomerID AS AccountID, c.CustomerName AS Owner, CAST(10000 AS DECIMAL(12,2)) AS Balance
INTO dbo.L16_Accounts
FROM dbo.Customers c;
ALTER TABLE dbo.L16_Accounts ADD CONSTRAINT PK_L16_Accounts PRIMARY KEY (AccountID);

-- 20,000 rows for the lock escalation demo (GENERATE_SERIES = SQL 2022+)
SELECT ISNULL(CAST(s.value AS INT), 0) AS ID, CAST(0 AS INT) AS Val
INTO dbo.L16_Big
FROM GENERATE_SERIES(1, 20000) AS s;
ALTER TABLE dbo.L16_Big ADD CONSTRAINT PK_L16_Big PRIMARY KEY (ID);
GO


/* ============================================================
   1. LOCKS: modes and granularity
   ============================================================
   Mode    Name                  Taken by                        Blocks
   ------  --------------------  ------------------------------  ------------------------
   S       Shared                reading (SELECT)                X
   X       Exclusive             INSERT / UPDATE / DELETE        S, U, X (everything)
   U       Update                "read now, will write soon"     U, X  (not S)
                                 -> only ONE session may hold U on a row: avoids the classic
                                    "both read with S, both want X" deadlock
   IS/IX   Intent Shared/Excl.   put on PAGE and TABLE when a row  a table-level X / Sch-M
                                 lock is taken below: "someone holds locks inside me"
   SIX     Shared + Intent X     table scan that updates some rows
   Sch-S   Schema stability      every running query             Sch-M (DDL must wait)
   Sch-M   Schema modification   ALTER TABLE, index rebuild ...  everything on that table

   Granularity (small -> big):  RID (heap row) / KEY (index row)  <  PAGE (8 KB)  <  OBJECT (table)  <  DATABASE
   Lock escalation: when ONE statement holds ~5000 locks on one table, SQL Server
   tries to replace them with ONE table lock (cheaper memory, less concurrency).
   ============================================================ */


/* ============================================================
   2. VIEWING YOUR OWN LOCKS: sys.dm_tran_locks
   ============================================================ */

-- 2a. Locks held after ONE row update, while the transaction is still open
BEGIN TRAN;
    UPDATE dbo.L16_Accounts SET Balance = Balance WHERE AccountID = 1;

    SELECT resource_type, request_mode, request_status,
           CASE resource_type WHEN 'OBJECT' THEN OBJECT_NAME(resource_associated_entity_id) ELSE '' END AS ObjectName
    FROM sys.dm_tran_locks
    WHERE request_session_id = @@SPID
      AND resource_database_id = DB_ID()        -- ignore locks in tempdb / other databases
    ORDER BY resource_type;
    -- expect 4 rows: DATABASE S (every connection), KEY X (the row), OBJECT IX, PAGE IX (intent locks above it)
ROLLBACK;
GO

-- 2b. A plain SELECT (READ COMMITTED) releases its S lock as soon as the row is read:
BEGIN TRAN;
    SELECT Balance FROM dbo.L16_Accounts WHERE AccountID = 1;
    SELECT resource_type, request_mode FROM sys.dm_tran_locks WHERE request_session_id = @@SPID;
    -- expect 1 row: DATABASE S only
ROLLBACK;
GO

-- 2c. A friendlier lock query: names for KEY / PAGE resources via sys.partitions
BEGIN TRAN;
    UPDATE dbo.L16_Accounts SET Balance = Balance WHERE AccountID IN (1, 2);

    SELECT l.resource_type, l.request_mode, l.request_status,
           COALESCE(OBJECT_NAME(p.object_id), OBJECT_NAME(l.resource_associated_entity_id)) AS ObjectName,
           l.resource_description
    FROM sys.dm_tran_locks l
    LEFT JOIN sys.partitions p ON p.hobt_id = l.resource_associated_entity_id
                              AND l.resource_type IN ('KEY', 'PAGE', 'RID')
    WHERE l.request_session_id = @@SPID AND l.resource_type <> 'DATABASE'
    ORDER BY l.resource_type, l.request_mode;
    -- expect 2 KEY X + 1 PAGE IX + 1 OBJECT IX, all on L16_Accounts
ROLLBACK;
GO

-- 2d. Lock ESCALATION: 3,000 rows -> row locks; 20,000 rows -> ONE table lock
BEGIN TRAN;
    UPDATE dbo.L16_Big SET Val = 1 WHERE ID <= 3000;
    SELECT resource_type, request_mode, COUNT(*) AS Locks
    FROM sys.dm_tran_locks WHERE request_session_id = @@SPID
    GROUP BY resource_type, request_mode ORDER BY resource_type;
    -- expect KEY X = 3000, PAGE IX (a few), OBJECT IX = 1, DATABASE S = 1
ROLLBACK;
GO
BEGIN TRAN;
    UPDATE dbo.L16_Big SET Val = 1;                       -- all 20,000 rows
    SELECT resource_type, request_mode, COUNT(*) AS Locks
    FROM sys.dm_tran_locks WHERE request_session_id = @@SPID
    GROUP BY resource_type, request_mode ORDER BY resource_type;
    -- expect OBJECT X = 1 (escalated!) and NO KEY / PAGE locks at all: the thousands of
    -- row locks were converted into ONE table lock and released
ROLLBACK;
GO
-- Per-table control: ALTER TABLE dbo.L16_Big SET (LOCK_ESCALATION = AUTO | TABLE | DISABLE);
SELECT name, lock_escalation_desc FROM sys.tables WHERE name = 'L16_Big';   -- TABLE (default)
GO

-- 2e. Schema locks: DDL takes Sch-M. (DDL is TRANSACTIONAL in SQL Server - it can be rolled back!)
BEGIN TRAN;
    ALTER TABLE dbo.L16_Big ADD Note VARCHAR(10) NULL;
    SELECT resource_type, request_mode, OBJECT_NAME(resource_associated_entity_id) AS ObjectName
    FROM sys.dm_tran_locks
    WHERE request_session_id = @@SPID AND resource_type = 'OBJECT' AND resource_database_id = DB_ID()
    ORDER BY request_mode;
    -- expect OBJECT Sch-M on L16_Big, plus IX locks on system tables (sysschobjs, syscolpars ...)
    -- because the DDL writes to the catalog
ROLLBACK;
SELECT COUNT(*) AS ColumnsInL16_Big FROM sys.columns WHERE object_id = OBJECT_ID('dbo.L16_Big');   -- 2 (Note is gone)
GO


/* ============================================================
   3. ISOLATION LEVELS and the THREE READ PHENOMENA
   ============================================================
   Dirty read          : you read a row another session changed but NOT yet committed
                         (it may be rolled back -> you saw data that never existed)
   Non-repeatable read : you read a row twice in one transaction and get different values
                         (someone updated + committed in between)
   Phantom read        : you run the same WHERE twice and get extra/missing ROWS
                         (someone inserted / deleted + committed in between)

   Level               Dirty  Non-repeatable  Phantom   How
   ------------------  -----  --------------  -------   ---------------------------------------------
   READ UNCOMMITTED    yes    yes             yes       no S locks at all (= NOLOCK)
   READ COMMITTED *    no     yes             yes       S lock only while reading the row   (DEFAULT)
   REPEATABLE READ     no     no              yes       S locks held until COMMIT
   SERIALIZABLE        no     no              no        range locks (RangeS-S) held until COMMIT
   SNAPSHOT            no     no              no        row VERSIONS in tempdb: readers never block/are blocked
   RCSI (READ COMMITTED SNAPSHOT) no  yes     yes       versions, but per STATEMENT (still READ COMMITTED)
   Stronger level = fewer anomalies but more blocking (except the versioning ones).
   ============================================================ */


/* ============================================================
   4. SET TRANSACTION ISOLATION LEVEL  +  reading the current level
   ============================================================ */

-- 4a. Two ways to see the level of YOUR session
DBCC USEROPTIONS;      -- last row: "isolation level  read committed"
SELECT transaction_isolation_level,
       CASE transaction_isolation_level
            WHEN 0 THEN 'Unspecified' WHEN 1 THEN 'ReadUncommitted' WHEN 2 THEN 'ReadCommitted'
            WHEN 3 THEN 'RepeatableRead' WHEN 4 THEN 'Serializable' WHEN 5 THEN 'Snapshot' END AS LevelName
FROM sys.dm_exec_sessions WHERE session_id = @@SPID;     -- 2 ReadCommitted
GO

-- 4b. READ UNCOMMITTED: no shared locks are taken at all
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
BEGIN TRAN;
    SELECT Balance FROM dbo.L16_Accounts WHERE AccountID = 1;
    SELECT resource_type, request_mode FROM sys.dm_tran_locks WHERE request_session_id = @@SPID;   -- DATABASE S only
ROLLBACK;
GO

-- 4c. READ COMMITTED (default): S lock taken per row, released right after reading
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
BEGIN TRAN;
    SELECT Balance FROM dbo.L16_Accounts WHERE AccountID = 1;
    SELECT resource_type, request_mode FROM sys.dm_tran_locks WHERE request_session_id = @@SPID;   -- DATABASE S only
ROLLBACK;
GO

-- 4d. REPEATABLE READ: the S lock on the row is HELD until the end of the transaction
--     -> nobody can UPDATE that row meanwhile -> a second read returns the same value
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
BEGIN TRAN;
    SELECT Balance FROM dbo.L16_Accounts WHERE AccountID = 1;
    SELECT resource_type, request_mode FROM sys.dm_tran_locks WHERE request_session_id = @@SPID
    ORDER BY resource_type;
    -- expect DATABASE S, KEY S, OBJECT IS, PAGE IS
ROLLBACK;
GO

-- 4e. SERIALIZABLE: RANGE locks - nobody can INSERT a row into the range either (no phantoms)
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
BEGIN TRAN;
    SELECT Balance FROM dbo.L16_Accounts WHERE AccountID BETWEEN 1 AND 3;
    SELECT resource_type, request_mode, COUNT(*) AS Locks FROM sys.dm_tran_locks
    WHERE request_session_id = @@SPID GROUP BY resource_type, request_mode ORDER BY resource_type;
    -- expect KEY RangeS-S = 4 (3 rows + the next key, to close the range), PAGE IS, OBJECT IS, DATABASE S
ROLLBACK;
GO

-- 4f. SNAPSHOT: must be ALLOWED at database level first
SET TRANSACTION ISOLATION LEVEL SNAPSHOT;
BEGIN TRY
    BEGIN TRAN;
        SELECT Balance FROM dbo.L16_Accounts WHERE AccountID = 1;
    COMMIT;
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();       -- error 3952: snapshot isolation is not allowed
    IF @@TRANCOUNT > 0 ROLLBACK;
END CATCH
GO
ALTER DATABASE SQLPractice SET ALLOW_SNAPSHOT_ISOLATION ON;       -- reverted in CLEANUP
GO
SELECT name, snapshot_isolation_state_desc, is_read_committed_snapshot_on
FROM sys.databases WHERE name = DB_NAME();                       -- ON, 0
GO
SET TRANSACTION ISOLATION LEVEL SNAPSHOT;
BEGIN TRAN;
    SELECT Balance FROM dbo.L16_Accounts WHERE AccountID = 1;
    SELECT resource_type, request_mode FROM sys.dm_tran_locks WHERE request_session_id = @@SPID;   -- DATABASE S only
    SELECT transaction_sequence_num, elapsed_time_seconds
    FROM sys.dm_tran_active_snapshot_database_transactions;      -- 1 row: our snapshot transaction
    DBCC USEROPTIONS;                                            -- last row: isolation level snapshot
ROLLBACK;
GO
-- How it works: writers keep the OLD version of each changed row in tempdb (version store).
-- A snapshot transaction reads the version that was current when the TRANSACTION began:
-- readers never block writers, writers never block readers. Cost: tempdb space + 14 bytes/row.
-- If a snapshot transaction UPDATES a row that someone else changed after it started ->
-- error 3960 "Snapshot isolation transaction aborted due to update conflict" (see file 03).

-- 4g. READ COMMITTED SNAPSHOT (RCSI): same versioning, but per STATEMENT and it replaces
--     the DEFAULT level - no code change needed anywhere. Switching needs an exclusive lock
--     on the database (all other connections must be out), so it is NOT switched here:
--       ALTER DATABASE SQLPractice SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE;
SELECT name, is_read_committed_snapshot_on FROM sys.databases WHERE name = DB_NAME();   -- 0 (off)
--     SNAPSHOT  : session opts in with SET TRANSACTION ISOLATION LEVEL SNAPSHOT; consistent for the whole transaction.
--     RCSI      : database-wide, every READ COMMITTED statement sees a consistent snapshot as of the STATEMENT start.
GO

-- 4h. Back to the default (the level is a SESSION setting - it stays until you change it!)
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
GO


/* ============================================================
   5. LOCK HINTS  (per table, per statement - override the isolation level)
   ============================================================ */

-- 5a. NOLOCK = READ UNCOMMITTED for that table. Fast, no blocking, BUT: dirty reads,
--     rows counted twice or skipped during page splits, error 601 "could not continue scan".
--     OK for rough reporting counts; NEVER for money, invoices, "is it there?" checks.
SELECT COUNT(*) AS Accounts FROM dbo.L16_Accounts WITH (NOLOCK);    -- 8
GO
-- Not allowed on the table you modify:
BEGIN TRY
    EXEC sp_executesql N'UPDATE dbo.L16_Accounts WITH (NOLOCK) SET Balance = Balance WHERE AccountID = 1';
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO

-- 5b. READPAST: skip rows that are locked by others instead of waiting (queue tables).
--     Nothing is locked now, so all 8 rows come back.
SELECT COUNT(*) AS NotLockedRows FROM dbo.L16_Accounts WITH (READPAST);   -- 8
-- Queue pattern: DELETE TOP (1) FROM dbo.Queue WITH (READPAST, ROWLOCK) OUTPUT deleted.* ...
GO

-- 5c. UPDLOCK: read with an U lock, held until the end of the transaction.
--     "Read the balance, then update it" with two sessions using plain S locks = deadlock;
--     with UPDLOCK the second session waits instead.
BEGIN TRAN;
    SELECT Balance FROM dbo.L16_Accounts WITH (UPDLOCK) WHERE AccountID = 1;
    SELECT resource_type, request_mode FROM sys.dm_tran_locks WHERE request_session_id = @@SPID
    ORDER BY resource_type;
    -- expect KEY U, PAGE IU, OBJECT IX, DATABASE S
    UPDATE dbo.L16_Accounts SET Balance = Balance WHERE AccountID = 1;   -- U is converted to X
ROLLBACK;
GO

-- 5d. HOLDLOCK = SERIALIZABLE for that table: the S lock is kept until the end
BEGIN TRAN;
    SELECT Balance FROM dbo.L16_Accounts WITH (HOLDLOCK) WHERE AccountID = 1;
    SELECT resource_type, request_mode FROM sys.dm_tran_locks WHERE request_session_id = @@SPID
    ORDER BY resource_type;
    -- expect KEY S held (compare with 4c where nothing was left), PAGE IS, OBJECT IS, DATABASE S
ROLLBACK;
GO

-- 5e. Granularity hints: ROWLOCK / PAGLOCK / TABLOCK / TABLOCKX
BEGIN TRAN;
    UPDATE dbo.L16_Big WITH (ROWLOCK) SET Val = 2 WHERE ID <= 100;   -- "please keep row locks"
    SELECT resource_type, request_mode, COUNT(*) AS Locks FROM sys.dm_tran_locks
    WHERE request_session_id = @@SPID GROUP BY resource_type, request_mode ORDER BY resource_type;
    -- expect KEY X = 100
ROLLBACK;
GO
BEGIN TRAN;
    SELECT COUNT(*) AS Rows FROM dbo.L16_Accounts WITH (TABLOCKX);  -- exclusive TABLE lock, held to the end
    SELECT resource_type, request_mode FROM sys.dm_tran_locks
    WHERE request_session_id = @@SPID AND resource_type = 'OBJECT';  -- OBJECT X
ROLLBACK;
GO
-- TABLOCK (shared table lock) is what bulk loads use for minimal logging:
--   INSERT INTO dbo.T WITH (TABLOCK) SELECT ...


/* ============================================================
   6. BLOCKING: how to find it
   ============================================================
   Blocking = my request waits for a lock another session holds
   (wait_type LCK_M_S / LCK_M_U / LCK_M_X ...). It is normal for
   milliseconds; a problem for seconds. Usual cause: a session that
   opened a transaction and never committed (idle "sleeping" blocker).
   ============================================================ */

-- 6a. READY-TO-USE blocking query (returns 0 rows on a quiet server)
SELECT r.session_id            AS BlockedSpid,
       r.blocking_session_id   AS BlockerSpid,
       r.wait_type, r.wait_time AS WaitMs, r.wait_resource,
       DB_NAME(r.database_id)  AS DbName,
       s.login_name, s.host_name, s.program_name,
       SUBSTRING(t.text, r.statement_start_offset / 2 + 1,
                 (CASE r.statement_end_offset WHEN -1 THEN DATALENGTH(t.text)
                       ELSE r.statement_end_offset END - r.statement_start_offset) / 2 + 1) AS BlockedStatement,
       ib.event_info           AS BlockerLastStatement
FROM sys.dm_exec_requests r
JOIN sys.dm_exec_sessions s ON s.session_id = r.session_id
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
OUTER APPLY sys.dm_exec_input_buffer(r.blocking_session_id, NULL) ib
WHERE r.blocking_session_id <> 0;
GO

-- 6b. The old way: sp_who2 - look at the BlkBy column. ('active' = skip sleeping sessions)
EXEC sp_who2 'active';
GO

-- 6c. Waiting tasks (also shows the blocking chain for parallel queries)
SELECT session_id, blocking_session_id, wait_type, wait_duration_ms, resource_description
FROM sys.dm_os_waiting_tasks
WHERE blocking_session_id IS NOT NULL;     -- 0 rows now
GO

-- 6d. LOCK_TIMEOUT: how long a statement waits for a lock before failing (default -1 = forever)
SELECT @@LOCK_TIMEOUT AS DefaultMs;        -- -1
SET LOCK_TIMEOUT 3000;                     -- wait max 3 s, then error 1222 "Lock request time out period exceeded"
SELECT @@LOCK_TIMEOUT AS NowMs;            -- 3000
SET LOCK_TIMEOUT -1;                       -- back to the default
GO
-- 6e. Killing the blocker (from ANOTHER session, needs ALTER ANY CONNECTION):  KILL 57;
--     Its open transaction is rolled back. You cannot KILL your own session.


/* ============================================================
   7. DEADLOCKS
   ============================================================
   Deadlock = session A waits for a lock held by B, while B waits
   for a lock held by A. Nobody can ever continue, so every ~5 s the
   deadlock monitor picks a VICTIM, rolls its transaction back and
   sends it error 1205 ("... was deadlocked on lock resources with
   another process and has been chosen as the deadlock victim.
   Rerun the transaction."). The other session continues normally.
   Victim choice: the session with the LOWER DEADLOCK_PRIORITY; if
   equal, the one that is CHEAPEST to roll back (least log written).
   ============================================================ */

-- 7a. DEADLOCK_PRIORITY: LOW (-5) | NORMAL (0) | HIGH (5) | any integer -10..10
SET DEADLOCK_PRIORITY LOW;
SELECT deadlock_priority FROM sys.dm_exec_sessions WHERE session_id = @@SPID;   -- -5
SET DEADLOCK_PRIORITY NORMAL;
SELECT deadlock_priority FROM sys.dm_exec_sessions WHERE session_id = @@SPID;   -- 0
GO
-- Use LOW for reports / background jobs that can simply be re-run.

-- 7b. THE RETRY PATTERN: because 1205 rolls back the victim, the fix is to run it again.
CREATE PROCEDURE dbo.usp_L16_UpdateWithRetry
    @AccountID INT,
    @Delta     DECIMAL(12,2)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @Attempt INT = 1, @MaxAttempts INT = 3;

    WHILE @Attempt <= @MaxAttempts
    BEGIN
        BEGIN TRY
            BEGIN TRAN;
                UPDATE dbo.L16_Accounts SET Balance = Balance + @Delta WHERE AccountID = @AccountID;
            COMMIT;
            PRINT 'Done on attempt ' + CAST(@Attempt AS VARCHAR(5));
            RETURN 0;                                        -- success: leave the loop AND the proc
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK;
            IF ERROR_NUMBER() = 1205 AND @Attempt < @MaxAttempts   -- deadlock victim -> wait, retry
            BEGIN
                PRINT 'Deadlock on attempt ' + CAST(@Attempt AS VARCHAR(5)) + ', retrying...';
                WAITFOR DELAY '00:00:00.200';
                SET @Attempt += 1;
            END
            ELSE
                THROW;                                       -- any other error (or out of retries)
        END CATCH
    END
END
GO
EXEC dbo.usp_L16_UpdateWithRetry @AccountID = 1, @Delta = 50;     -- "Done on attempt 1" (no deadlock alone)
SELECT Balance FROM dbo.L16_Accounts WHERE AccountID = 1;          -- 10050.00
GO

-- 7c. Seeing deadlock graphs: the always-on system_health Extended Events session keeps them
SELECT xed.value('@timestamp', 'DATETIME2(0)')                 AS DeadlockTimeUtc,
       xed.query('data/value/deadlock')                        AS DeadlockGraphXml
FROM (SELECT CAST(st.target_data AS XML) AS TargetData
      FROM sys.dm_xe_session_targets st
      JOIN sys.dm_xe_sessions s ON s.address = st.event_session_address
      WHERE s.name = 'system_health' AND st.target_name = 'ring_buffer') AS d
CROSS APPLY d.TargetData.nodes('RingBufferTarget/event[@name="xml_deadlock_report"]') AS x(xed)
ORDER BY DeadlockTimeUtc DESC;
-- expect 0 rows unless a deadlock happened since the last service restart
-- (run file 03 scenario (e), then run this again). Save the XML as .xdl and open it in SSMS.
GO
-- Older options: DBCC TRACEON (1222, -1) writes deadlock info to the ERRORLOG;
-- SQL Profiler "Deadlock graph" event; the .xel files:
--   sys.fn_xe_file_target_read_file('system_health*.xel', NULL, NULL, NULL)

-- 7d. HOW TO PREVENT DEADLOCKS
--   1. Access tables/rows in the SAME ORDER in every procedure (A then B, never B then A).
--   2. Keep transactions SHORT: no user interaction, no slow calls inside BEGIN TRAN.
--   3. Proper INDEXES: fewer rows touched = fewer locks (a table scan locks everything).
--   4. Use UPDLOCK when you "read then update" the same row.
--   5. Consider SNAPSHOT / RCSI so readers stop fighting with writers.
--   6. Give background jobs SET DEADLOCK_PRIORITY LOW and a retry loop.


/* ============================================================
   8. CLEANUP  (revert every session and database setting we touched)
   ============================================================ */
IF @@TRANCOUNT > 0 ROLLBACK;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
SET LOCK_TIMEOUT -1;
SET DEADLOCK_PRIORITY NORMAL;
DROP PROCEDURE IF EXISTS dbo.usp_L16_UpdateWithRetry;
DROP TABLE IF EXISTS dbo.L16_Accounts, dbo.L16_Big;
GO
ALTER DATABASE SQLPractice SET ALLOW_SNAPSHOT_ISOLATION OFF;
GO
SELECT name, snapshot_isolation_state_desc FROM sys.databases WHERE name = DB_NAME();   -- OFF
SELECT name FROM sys.objects WHERE name LIKE '%L16%';                                    -- 0 rows
GO
/* DONE. Next: 03_Two_Sessions_Demo.sql (read + try in two SSMS windows), then Exercises.sql */
