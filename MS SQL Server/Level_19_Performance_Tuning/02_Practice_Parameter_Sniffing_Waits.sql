/* ============================================================
   LEVEL 19 - PERFORMANCE TUNING  |  02_Practice_Parameter_Sniffing_Waits.sql
   ------------------------------------------------------------
   Topics : parameter sniffing (bad plan reuse measured in reads) and
            its fixes (OPTION RECOMPILE, WITH RECOMPILE, OPTIMIZE FOR,
            OPTIMIZE FOR UNKNOWN, local variable, separate procs,
            sp_recompile, Query Store plan forcing); plan cache inspection
            for procs; wait statistics; blocking / deadlock investigation
            queries; finding expensive queries; missing / unused / duplicate
            index queries; tempdb contention and memory grants (brief).

   HOW TO PRACTICE: run block by block, predict the output first.
   Uses the same skewed dbo.L19_Orders table (CustomerID 1 = 40% of rows).
   ============================================================ */

USE SQLPractice;
GO
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO


/* ============================================================
   0. SETUP - same table as file 01 (about 3 seconds)
   ============================================================ */
DROP TABLE IF EXISTS dbo.L19_Orders;
CREATE TABLE dbo.L19_Orders
(
    OrderID    INT           NOT NULL CONSTRAINT PK_L19_Orders PRIMARY KEY,
    CustomerID INT           NOT NULL,
    EmployeeID INT           NULL,
    OrderDate  DATETIME2(0)  NOT NULL,
    Amount     DECIMAL(12,2) NOT NULL,
    Status     VARCHAR(20)   NOT NULL,
    RefNo      VARCHAR(20)   NOT NULL,
    Filler     CHAR(100)     NOT NULL CONSTRAINT DF_L19_Orders_Filler DEFAULT ('x')
);
INSERT INTO dbo.L19_Orders (OrderID, CustomerID, EmployeeID, OrderDate, Amount, Status, RefNo)
SELECT value,
       CASE WHEN value % 5 < 2 THEN 1 ELSE 2 + (value % 999) END,
       CASE WHEN value % 20 = 0 THEN NULL ELSE 101 + value % 12 END,
       DATEADD(MINUTE, value % 1440, DATEADD(DAY, value % 1096, '2023-01-01')),
       100 + (value * 7919) % 99900,
       CASE value % 10 WHEN 0 THEN 'Cancelled' WHEN 1 THEN 'Pending' ELSE 'Completed' END,
       CAST(value AS VARCHAR(20))
FROM GENERATE_SERIES(1, 200000);
CREATE INDEX IX_L19_Orders_CustomerID ON dbo.L19_Orders (CustomerID);
CREATE INDEX IX_L19_Orders_OrderDate  ON dbo.L19_Orders (OrderDate) INCLUDE (Amount);
CREATE INDEX IX_L19_Orders_Status     ON dbo.L19_Orders (Status);
GO
SELECT CustomerID, COUNT(*) AS Orders FROM dbo.L19_Orders WHERE CustomerID IN (1, 500) GROUP BY CustomerID;   -- 1: 80000, 500: 120
GO


/* ============================================================
   1. PARAMETER SNIFFING - one plan, two very different parameter values
   ============================================================
   When a proc is compiled, the optimizer "sniffs" the parameter value of THAT first call and
   builds the best plan for it. The plan is cached and reused for every later value.
   Customer 500 (120 rows)   -> best plan = Index Seek + 120 Key Lookups (about 378 reads).
   Customer 1   (80,000 rows)-> best plan = read the CustomerID index and the covering OrderDate
                                index once each and Hash-join them (about 765 reads); 80,000
                                lookups would be madness.
   Whichever runs first decides the plan for everybody.
   ============================================================ */
CREATE OR ALTER PROCEDURE dbo.usp_L19_OrdersByCustomer @CustomerID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT @CustomerID AS CustomerID, COUNT(*) AS Orders, SUM(Amount) AS Total, MIN(OrderDate) AS FirstOrder
    FROM dbo.L19_Orders
    WHERE CustomerID = @CustomerID;
END
GO
SET STATISTICS IO ON;
GO
-- 1a. First call = the RARE customer -> seek plan compiled and cached
EXEC dbo.usp_L19_OrdersByCustomer @CustomerID = 500;      -- 120 orders; logical reads about 378 (seek + 120 lookups)
GO
-- 1b. Same proc, the WHALE: the cached seek plan is reused -> 80,000 Key Lookups
EXEC dbo.usp_L19_OrdersByCustomer @CustomerID = 1;        -- 80000 orders; logical reads about 245,000 (!)
GO
-- 1c. Throw the plan away (sp_recompile marks the proc; next call compiles fresh) and call the whale first
EXEC sp_recompile 'dbo.usp_L19_OrdersByCustomer';
GO
EXEC dbo.usp_L19_OrdersByCustomer @CustomerID = 1;        -- logical reads about 765 (hash join of two indexes, no lookups): 300x fewer reads
GO
EXEC dbo.usp_L19_OrdersByCustomer @CustomerID = 500;      -- now the rare customer pays for the whale's plan too (about 627 instead of 378)
GO
SET STATISTICS IO OFF;
GO
-- 1d. Prove which value the plan was compiled for: the cached plan XML stores ParameterCompiledValue.
WITH XMLNAMESPACES (DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan')
SELECT ps.execution_count, ps.total_logical_reads, ps.last_logical_reads,
       qp.query_plan.value('(//ParameterList/ColumnReference/@ParameterCompiledValue)[1]', 'varchar(20)') AS CompiledFor,
       qp.query_plan.exist('//RelOp[@PhysicalOp="Hash Match"]') AS UsesHashJoin
FROM sys.dm_exec_procedure_stats ps
CROSS APPLY sys.dm_exec_query_plan(ps.plan_handle) qp
WHERE ps.object_id = OBJECT_ID('dbo.usp_L19_OrdersByCustomer');
-- expect: execution_count 2 (stats restarted with the new plan), CompiledFor (1), UsesHashJoin 1
GO


/* ============================================================
   2. THE FIXES (each one measured: reads for customer 500, then customer 1)
   ============================================================ */
-- 2a. OPTION (RECOMPILE) on the statement: a fresh plan every call (compile CPU each time; fine for
--     procs that run a few times per second at most). Best plan for BOTH values.
CREATE OR ALTER PROCEDURE dbo.usp_L19_OrdersByCustomer_Recompile @CustomerID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT @CustomerID AS CustomerID, COUNT(*) AS Orders, SUM(Amount) AS Total
    FROM dbo.L19_Orders WHERE CustomerID = @CustomerID
    OPTION (RECOMPILE);
END
GO
-- 2b. WITH RECOMPILE on the proc: same idea for the whole proc, plan never cached.
CREATE OR ALTER PROCEDURE dbo.usp_L19_OrdersByCustomer_WithRecompile @CustomerID INT
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SELECT @CustomerID AS CustomerID, COUNT(*) AS Orders, SUM(Amount) AS Total
    FROM dbo.L19_Orders WHERE CustomerID = @CustomerID;
END
GO
-- 2c. OPTIMIZE FOR (@p = value): always build the plan for the value YOU choose (the whale) - the
--     whale's plan for everyone. Predictable; the rare customer pays a little more.
CREATE OR ALTER PROCEDURE dbo.usp_L19_OrdersByCustomer_OptFor @CustomerID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT @CustomerID AS CustomerID, COUNT(*) AS Orders, SUM(Amount) AS Total
    FROM dbo.L19_Orders WHERE CustomerID = @CustomerID
    OPTION (OPTIMIZE FOR (@CustomerID = 1));
END
GO
-- 2d. OPTIMIZE FOR UNKNOWN: ignore the sniffed value, use the AVERAGE density (200,000 / 1,000 = 200 rows)
--     -> seek plan. Good for "typical" values, still bad for the whale.
CREATE OR ALTER PROCEDURE dbo.usp_L19_OrdersByCustomer_OptUnknown @CustomerID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT @CustomerID AS CustomerID, COUNT(*) AS Orders, SUM(Amount) AS Total
    FROM dbo.L19_Orders WHERE CustomerID = @CustomerID
    OPTION (OPTIMIZE FOR UNKNOWN);
END
GO
-- 2e. The local-variable trick (old-school OPTIMIZE FOR UNKNOWN): the optimizer cannot sniff a
--     local variable, so it uses the density -> same result as 2d.
CREATE OR ALTER PROCEDURE dbo.usp_L19_OrdersByCustomer_LocalVar @CustomerID INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @c INT = @CustomerID;
    SELECT @CustomerID AS CustomerID, COUNT(*) AS Orders, SUM(Amount) AS Total
    FROM dbo.L19_Orders WHERE CustomerID = @c;
END
GO
-- 2f. SEPARATE PROCS: route known heavy values to their own proc; each proc keeps its own good plan.
CREATE OR ALTER PROCEDURE dbo.usp_L19_OrdersByCustomer_Heavy @CustomerID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT @CustomerID AS CustomerID, COUNT(*) AS Orders, SUM(Amount) AS Total FROM dbo.L19_Orders WHERE CustomerID = @CustomerID;
END
GO
CREATE OR ALTER PROCEDURE dbo.usp_L19_OrdersByCustomer_Light @CustomerID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT @CustomerID AS CustomerID, COUNT(*) AS Orders, SUM(Amount) AS Total FROM dbo.L19_Orders WHERE CustomerID = @CustomerID;
END
GO
CREATE OR ALTER PROCEDURE dbo.usp_L19_OrdersByCustomer_Router @CustomerID INT
AS
BEGIN
    SET NOCOUNT ON;
    IF @CustomerID = 1 EXEC dbo.usp_L19_OrdersByCustomer_Heavy @CustomerID;   -- known whale(s)
    ELSE               EXEC dbo.usp_L19_OrdersByCustomer_Light @CustomerID;
END
GO
SET STATISTICS IO ON;
GO
PRINT '--- 2a OPTION (RECOMPILE): expect about 378 then about 765 reads (best plan each time)';
EXEC dbo.usp_L19_OrdersByCustomer_Recompile @CustomerID = 500;
EXEC dbo.usp_L19_OrdersByCustomer_Recompile @CustomerID = 1;
GO
PRINT '--- 2b WITH RECOMPILE: expect about 378 then about 765 reads';
EXEC dbo.usp_L19_OrdersByCustomer_WithRecompile @CustomerID = 500;
EXEC dbo.usp_L19_OrdersByCustomer_WithRecompile @CustomerID = 1;
GO
PRINT '--- 2c OPTIMIZE FOR (@CustomerID = 1): expect about 627 then about 765 (the whale plan for everyone)';
EXEC dbo.usp_L19_OrdersByCustomer_OptFor @CustomerID = 500;
EXEC dbo.usp_L19_OrdersByCustomer_OptFor @CustomerID = 1;
GO
PRINT '--- 2d OPTIMIZE FOR UNKNOWN: expect about 378 then about 245000 (density says 200 rows -> seek plan)';
EXEC dbo.usp_L19_OrdersByCustomer_OptUnknown @CustomerID = 500;
EXEC dbo.usp_L19_OrdersByCustomer_OptUnknown @CustomerID = 1;
GO
PRINT '--- 2e local variable: same as 2d';
EXEC dbo.usp_L19_OrdersByCustomer_LocalVar @CustomerID = 500;
EXEC dbo.usp_L19_OrdersByCustomer_LocalVar @CustomerID = 1;
GO
PRINT '--- 2f separate procs: expect about 378 then about 765 (each proc has its own plan)';
EXEC dbo.usp_L19_OrdersByCustomer_Router @CustomerID = 500;
EXEC dbo.usp_L19_OrdersByCustomer_Router @CustomerID = 1;
GO
SET STATISTICS IO OFF;
GO
/* 2g. Other tools:
   - EXEC sp_recompile 'dbo.proc'  -> drops the plan once (also works for a table: all plans using it).
   - Query Store: Regressed Queries report -> Force Plan (Level 18) when one plan is right for 99% of calls.
   - DBCC FREEPROCCACHE (plan_handle) -> same as sp_recompile for an ad hoc plan.
   - ALTER DATABASE SCOPED CONFIGURATION SET PARAMETER_SNIFFING = OFF -> whole database behaves like
     OPTIMIZE FOR UNKNOWN (rarely a good idea).
   - SQL 2022+ "Parameter Sensitive Plan optimization" (compat 160+) can keep several plans per proc automatically. */


/* ============================================================
   3. PLAN CACHE INSPECTION FOR PROCS
   ============================================================ */
SELECT OBJECT_NAME(ps.object_id) AS ProcName, ps.execution_count,
       ps.total_logical_reads, ps.last_logical_reads, ps.total_worker_time / 1000 AS TotalCpuMs,
       ps.cached_time, ps.last_execution_time
FROM sys.dm_exec_procedure_stats ps
WHERE ps.database_id = DB_ID() AND OBJECT_NAME(ps.object_id) LIKE 'usp_L19%'
ORDER BY ps.total_logical_reads DESC;
-- expect: _OptUnknown, _LocalVar and the original proc at the top (about 245,000 reads each from the whale call);
--         _WithRecompile is missing: WITH RECOMPILE plans are never cached, so they never appear here.
GO


/* ============================================================
   4. WAIT STATISTICS - what is the server waiting for?
   ============================================================ */
-- Cumulative since restart (or since the last clear). Filter out the "benign" background waits.
SELECT TOP (10) wait_type, waiting_tasks_count,
       wait_time_ms / 1000 AS WaitSec, signal_wait_time_ms / 1000 AS SignalSec,
       CAST(100.0 * wait_time_ms / NULLIF(SUM(wait_time_ms) OVER (), 0) AS DECIMAL(5,1)) AS Pct
FROM sys.dm_os_wait_stats
WHERE wait_type NOT IN ('CLR_SEMAPHORE','LAZYWRITER_SLEEP','RESOURCE_QUEUE','SLEEP_TASK','SLEEP_SYSTEMTASK','SQLTRACE_BUFFER_FLUSH',
      'WAITFOR','LOGMGR_QUEUE','CHECKPOINT_QUEUE','REQUEST_FOR_DEADLOCK_SEARCH','XE_TIMER_EVENT','BROKER_TO_FLUSH','BROKER_TASK_STOP',
      'CLR_MANUAL_EVENT','CLR_AUTO_EVENT','DISPATCHER_QUEUE_SEMAPHORE','FT_IFTS_SCHEDULER_IDLE_WAIT','XE_DISPATCHER_WAIT',
      'XE_DISPATCHER_JOIN','SQLTRACE_INCREMENTAL_FLUSH_SLEEP','ONDEMAND_TASK_QUEUE','BROKER_EVENTHANDLER','SLEEP_BPOOL_FLUSH',
      'DIRTY_PAGE_POLL','HADR_FILESTREAM_IOMGR_IOCOMPLETION','SP_SERVER_DIAGNOSTICS_SLEEP','QDS_PERSIST_TASK_MAIN_LOOP_SLEEP',
      'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP','QDS_ASYNC_QUEUE','QDS_SHUTDOWN_QUEUE','BROKER_RECEIVE_WAITFOR',
      'WAIT_XTP_HOST_WAIT','WAIT_XTP_OFFLINE_CKPT_NEW_LOG','WAIT_XTP_CKPT_CLOSE','SOS_WORK_DISPATCHER','VDI_CLIENT_OTHER',
      'PWAIT_ALL_COMPONENTS_INITIALIZED','PWAIT_DIRECTLOGCONSUMER_GETNEXT','XE_LIVE_TARGET_TVF','MEMORY_ALLOCATION_EXT',
      'PARALLEL_REDO_WORKER_WAIT_WORK','PARALLEL_REDO_DRAIN_WORKER','PARALLEL_REDO_LOG_CACHE','PARALLEL_REDO_TRAN_LIST',
      'PARALLEL_REDO_WORKER_SYNC','PARALLEL_REDO_TRAN_TURN','WAIT_FOR_RESULTS','PVS_PREALLOCATE','STARTUP_DEPENDENCY_MANAGER',
      'HADR_WORK_QUEUE','HADR_TIMER_TASK','HADR_CLUSAPI_CALL','HADR_LOGCAPTURE_WAIT','HADR_NOTIFICATION_DEQUEUE','HADR_FILESTREAM_IOMGR',
      'KSOURCE_WAKEUP','LOGMGR_RESERVE_APPEND','SQLTRACE_WAIT_ENTRIES','SNI_HTTP_ACCEPT','SERVER_IDLE_CHECK','DBMIRROR_EVENTS_QUEUE',
      'DBMIRRORING_CMD','SP_PREEMPTIVE_SERVER_DIAGNOSTICS_SLEEP','SOS_SCHEDULER_YIELD_IDLE')
  AND wait_type NOT LIKE 'PREEMPTIVE_%' AND wait_type NOT LIKE 'SLEEP_%'
ORDER BY wait_time_ms DESC;
GO
/* WHAT THE COMMON WAITS MEAN
   CXPACKET / CXCONSUMER : parallel threads waiting for each other. Normal for big reports; on OLTP -> raise
                           'cost threshold for parallelism' (25-50), set MAXDOP, fix the big query.
   PAGEIOLATCH_SH / _EX  : waiting for data pages to come from DISK -> not enough memory / slow storage / scans.
   LCK_M_S / LCK_M_X / LCK_M_U : blocked by another session's lock -> long transactions, missing indexes (Level 16).
   WRITELOG              : waiting for the transaction log to be written -> slow log disk, too many tiny commits.
   SOS_SCHEDULER_YIELD   : a thread gave up its CPU turn -> CPU pressure (or a hot loop in a query).
   ASYNC_NETWORK_IO      : the CLIENT is not consuming rows fast enough -> app problem, not SQL (SELECT * of millions).
   RESOURCE_SEMAPHORE    : waiting for a MEMORY GRANT -> too many big sorts/hashes at once, bad estimates.
   PAGELATCH_UP / _EX on tempdb : tempdb allocation contention -> more tempdb files.
   RESET the counters to watch a time window (server-wide, do it only on a test box):
       DBCC SQLPERF ('sys.dm_os_wait_stats', CLEAR);                                                      */


/* ============================================================
   5. BLOCKING AND DEADLOCK INVESTIGATION (ready-to-paste queries)
   ============================================================ */
-- 5a. WHO IS BLOCKING WHOM (0 rows when nobody is blocked - open Level 16's two-session demo to see rows)
SELECT r.session_id            AS BlockedSession,
       r.blocking_session_id   AS BlockedBy,
       r.wait_type, r.wait_time AS WaitMs, r.wait_resource,
       s.login_name, s.host_name, s.program_name, DB_NAME(r.database_id) AS DbName,
       t.text                  AS BlockedSql,
       (SELECT t2.text FROM sys.dm_exec_connections c2 CROSS APPLY sys.dm_exec_sql_text(c2.most_recent_sql_handle) t2
        WHERE c2.session_id = r.blocking_session_id) AS BlockerLastSql
FROM sys.dm_exec_requests r
JOIN sys.dm_exec_sessions s ON s.session_id = r.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.blocking_session_id <> 0;
GO
-- 5b. Every task that waits on a lock right now (lighter view)
SELECT wt.session_id, wt.blocking_session_id, wt.wait_type, wt.wait_duration_ms, wt.resource_description
FROM sys.dm_os_waiting_tasks wt
WHERE wt.blocking_session_id IS NOT NULL;
GO
-- 5c. The classic: sp_who2 (BlkBy column = blocking session). Better: the free sp_WhoIsActive
--     (whoisactive.com) shows waits, blocking chains and the running statement in one row per session.
EXEC sp_who2;
GO
-- 5d. Deadlocks are written to the system_health Extended Events session automatically. Read them:
SELECT TOP (5)
       CAST(event_data AS XML).value('(event/@timestamp)[1]', 'datetime2(0)') AS DeadlockTimeUtc,
       CAST(event_data AS XML).query('event/data/value/deadlock')             AS DeadlockGraph   -- clickable XML
FROM sys.fn_xe_file_target_read_file('system_health*.xel', NULL, NULL, NULL)
WHERE object_name = 'xml_deadlock_report'
ORDER BY DeadlockTimeUtc DESC;                             -- 0 rows if no deadlock happened since the files rolled over
GO


/* ============================================================
   6. FINDING EXPENSIVE QUERIES (plan cache statistics)
   ============================================================ */
-- The statement text is cut out of the batch with the offsets; plan_handle links to the plan.
SELECT TOP (5)
       qs.execution_count,
       qs.total_worker_time / 1000  AS TotalCpuMs,
       qs.total_logical_reads       AS TotalReads,
       qs.total_elapsed_time / 1000 AS TotalElapsedMs,
       qs.total_logical_reads / qs.execution_count AS AvgReads,
       SUBSTRING(st.text, qs.statement_start_offset / 2 + 1,
                 (CASE qs.statement_end_offset WHEN -1 THEN DATALENGTH(st.text) ELSE qs.statement_end_offset END
                  - qs.statement_start_offset) / 2 + 1) AS StatementText,
       qs.plan_handle                                     -- feed to sys.dm_exec_query_plan(plan_handle) for the plan
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
WHERE st.text LIKE '%L19_Orders%' AND st.text NOT LIKE '%dm_exec_query_stats%'
ORDER BY qs.total_logical_reads DESC;                      -- change to total_worker_time DESC (CPU) or execution_count DESC (chatty)
GO


/* ============================================================
   7. INDEX HEALTH QUERIES: missing, unused, duplicate
   ============================================================ */
-- 7a. Missing index suggestions collected by the optimizer (since restart), most valuable first
SELECT TOP (10)
       OBJECT_NAME(mid.object_id) AS TableName,
       mid.equality_columns, mid.inequality_columns, mid.included_columns,
       migs.user_seeks, migs.avg_user_impact,
       CAST(migs.user_seeks * migs.avg_total_user_cost * migs.avg_user_impact / 100 AS DECIMAL(12,1)) AS Score
FROM sys.dm_db_missing_index_details mid
JOIN sys.dm_db_missing_index_groups mig       ON mig.index_handle = mid.index_handle
JOIN sys.dm_db_missing_index_group_stats migs ON migs.group_handle = mig.index_group_handle
WHERE mid.database_id = DB_ID()
ORDER BY Score DESC;
GO
-- 7b. Unused indexes: written to (user_updates) but never read since restart -> candidates to drop
SELECT OBJECT_NAME(i.object_id) AS TableName, i.name AS IndexName,
       ISNULL(us.user_seeks, 0) + ISNULL(us.user_scans, 0) + ISNULL(us.user_lookups, 0) AS Reads,
       ISNULL(us.user_updates, 0) AS Writes
FROM sys.indexes i
LEFT JOIN sys.dm_db_index_usage_stats us ON us.object_id = i.object_id AND us.index_id = i.index_id AND us.database_id = DB_ID()
WHERE i.object_id = OBJECT_ID('dbo.L19_Orders') AND i.type_desc = 'NONCLUSTERED'
ORDER BY Reads, Writes DESC;
-- expect: IX_L19_Orders_Status with 0 reads (nobody used it in this file), _CustomerID with the most
GO
-- 7c. Duplicate indexes: same key columns in the same order (each one costs writes and space)
CREATE INDEX IX_L19_Orders_CustomerID_Dup ON dbo.L19_Orders (CustomerID);   -- create one on purpose
GO
WITH K AS
(
    SELECT i.object_id, i.name,
           STRING_AGG(c.name, ',') WITHIN GROUP (ORDER BY ic.key_ordinal) AS KeyCols
    FROM sys.indexes i
    JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.is_included_column = 0
    JOIN sys.columns c        ON c.object_id = ic.object_id AND c.column_id = ic.column_id
    WHERE i.object_id = OBJECT_ID('dbo.L19_Orders')
    GROUP BY i.object_id, i.name
)
SELECT a.name AS Index1, b.name AS Index2, a.KeyCols
FROM K a JOIN K b ON b.object_id = a.object_id AND b.KeyCols = a.KeyCols AND b.name > a.name;
-- expect 1 row: IX_L19_Orders_CustomerID / IX_L19_Orders_CustomerID_Dup / CustomerID
GO
DROP INDEX IX_L19_Orders_CustomerID_Dup ON dbo.L19_Orders;
GO


/* ============================================================
   8. TEMPDB CONTENTION AND MEMORY GRANTS (brief)
   ============================================================ */
-- 8a. tempdb: every #temp table, sort spill, hash spill, version store lives here. Contention shows as
--     PAGELATCH_UP/EX waits on tempdb pages (2:1:1 PFS, 2:1:3 SGAM). Fix: several equally sized data
--     files (1 per core up to 8) - the installer does this since SQL 2016.
SELECT COUNT(*) AS TempdbDataFiles FROM tempdb.sys.database_files WHERE type_desc = 'ROWS';
SELECT SUM(user_object_reserved_page_count) * 8 / 1024     AS UserObjectsMB,     -- #temp tables, table variables
       SUM(internal_object_reserved_page_count) * 8 / 1024 AS InternalObjectsMB, -- sorts, hashes, spools
       SUM(version_store_reserved_page_count) * 8 / 1024   AS VersionStoreMB,    -- snapshot isolation rows
       SUM(unallocated_extent_page_count) * 8 / 1024       AS FreeMB
FROM tempdb.sys.dm_db_file_space_usage;
GO
-- 8b. Memory grants: each Sort/Hash reserves workspace memory based on the ESTIMATED rows. Too small ->
--     spill to tempdb; too big -> other queries wait (RESOURCE_SEMAPHORE). Live view:
SELECT session_id, requested_memory_kb, granted_memory_kb, used_memory_kb, max_used_memory_kb, wait_time_ms
FROM sys.dm_exec_query_memory_grants;                      -- usually 0 rows on an idle box
GO


/* ============================================================
   9. CLEANUP
   ============================================================ */
DROP PROCEDURE IF EXISTS dbo.usp_L19_OrdersByCustomer, dbo.usp_L19_OrdersByCustomer_Recompile,
     dbo.usp_L19_OrdersByCustomer_WithRecompile, dbo.usp_L19_OrdersByCustomer_OptFor,
     dbo.usp_L19_OrdersByCustomer_OptUnknown, dbo.usp_L19_OrdersByCustomer_LocalVar,
     dbo.usp_L19_OrdersByCustomer_Heavy, dbo.usp_L19_OrdersByCustomer_Light, dbo.usp_L19_OrdersByCustomer_Router;
DROP TABLE IF EXISTS dbo.L19_Orders;
GO
/* DONE. Next: Exercises.sql */
