/* ============================================================
   LEVEL 19 - PERFORMANCE TUNING  |  Exercises.sql
   ------------------------------------------------------------
   Try each question in the "YOUR ANSWERS" area FIRST, then compare
   with SOLUTIONS. All questions run on the small SQLPractice tables;
   the point is the TECHNIQUE (the numbers only get big at scale).
   ============================================================ */

USE SQLPractice;
GO
SET NOCOUNT ON;
GO

/* ------------------------------------------------------------
   QUESTIONS
   ------------------------------------------------------------
   Q1.  Rewrite SARGably:  SELECT OrderID FROM dbo.Orders WHERE YEAR(OrderDate) = 2025 AND MONTH(OrderDate) = 3
   Q2.  Rewrite SARGably:  SELECT OrderID, TotalAmount FROM dbo.Orders WHERE TotalAmount * 1.18 > 50000
   Q3.  Rewrite SARGably:  SELECT OrderID FROM dbo.Orders WHERE ISNULL(EmployeeID, 0) = 0
   Q4.  Rewrite SARGably:  SELECT OrderID FROM dbo.Orders WHERE CAST(OrderDate AS DATE) BETWEEN '2025-01-01' AND '2025-01-31'
   Q5.  Create an index on dbo.Orders (OrderDate) INCLUDE (TotalAmount). Show with SHOWPLAN_TEXT
        that the Q4 query changes from a Clustered Index Scan to an Index Seek. Drop the index.
   Q6.  Show the statistics header and histogram of PK_Orders, and list every statistics object of
        dbo.Orders with rows and modification_counter.
   Q7.  Write dbo.usp_L19x_OrdersByStatus(@Status) that returns the orders of one status and is
        immune to parameter sniffing. Run it for 'Completed' and 'Pending'. Write in a comment when
        you would NOT use that technique.
   Q8.  Write a "catch-all" proc dbo.usp_L19x_OrderSearch(@CustomerID INT = NULL, @Status VARCHAR(20) = NULL)
        (NULL = ignore the filter) that still gets a good plan for every combination. Test 3 combinations.
   Q9.  Show the top 5 wait types of this server without the benign background waits.
   Q10. Write the "who is blocking whom" query (session, blocker, wait, text). It returns 0 rows now - fine.
   Q11. Show the 5 statements with the highest total CPU from the plan cache, with their text.
   Q12. List the nonclustered indexes of SQLPractice that have never been read since the last restart,
        and the missing-index suggestions the optimizer recorded for dbo.Orders.
   ------------------------------------------------------------ */

-- YOUR ANSWERS HERE (write below, run, compare)










/* ============================================================
   SOLUTIONS
   ============================================================ */

-- Q1  (a closed-open range on the column; safe date literals)
SELECT OrderID FROM dbo.Orders WHERE OrderDate >= '20250301' AND OrderDate < '20250401';     -- 1007, 1008
GO

-- Q2  (move the arithmetic to the constant side)
SELECT OrderID, TotalAmount FROM dbo.Orders WHERE TotalAmount > 50000 / 1.18;               -- 5 rows: 1001, 1005, 1008, 1014, 1018
GO

-- Q3  (ISNULL(col,0) = 0  <=>  col = 0 OR col IS NULL; there is no EmployeeID 0, so IS NULL is enough)
SELECT OrderID FROM dbo.Orders WHERE EmployeeID IS NULL;                                     -- 1019
GO

-- Q4  (OrderDate is already DATE; the CAST only hides the column)
SELECT OrderID FROM dbo.Orders WHERE OrderDate >= '20250101' AND OrderDate < '20250201';     -- 1001, 1002, 1003
GO

-- Q5
SET SHOWPLAN_TEXT ON;
GO
SELECT OrderID FROM dbo.Orders WHERE OrderDate >= '20250101' AND OrderDate < '20250201';     -- Clustered Index Scan (no index on OrderDate)
GO
SET SHOWPLAN_TEXT OFF;
GO
CREATE INDEX IX_L19x_Orders_OrderDate ON dbo.Orders (OrderDate) INCLUDE (TotalAmount);
GO
SET SHOWPLAN_TEXT ON;
GO
SELECT OrderID FROM dbo.Orders WHERE OrderDate >= '20250101' AND OrderDate < '20250201';     -- Index Seek on IX_L19x_Orders_OrderDate
GO
SET SHOWPLAN_TEXT OFF;
GO
DROP INDEX IX_L19x_Orders_OrderDate ON dbo.Orders;
GO

-- Q6
DBCC SHOW_STATISTICS ('dbo.Orders', PK_Orders) WITH STAT_HEADER;      -- Rows 19, Steps 10
DBCC SHOW_STATISTICS ('dbo.Orders', PK_Orders) WITH HISTOGRAM;        -- 10 steps: every second OrderID, RANGE_ROWS 1 in between
SELECT s.name, s.auto_created, sp.rows, sp.rows_sampled, sp.modification_counter, sp.last_updated
FROM sys.stats s CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) sp
WHERE s.object_id = OBJECT_ID('dbo.Orders');
GO

-- Q7  (OPTION (RECOMPILE): a fresh plan per call. Do NOT use it for a proc called hundreds of times
--      per second - the compile CPU would cost more than the bad plan.)
CREATE OR ALTER PROCEDURE dbo.usp_L19x_OrdersByStatus @Status VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT OrderID, CustomerID, OrderDate, TotalAmount
    FROM dbo.Orders
    WHERE Status = @Status
    OPTION (RECOMPILE);
END
GO
EXEC dbo.usp_L19x_OrdersByStatus @Status = 'Completed';   -- 16 rows
EXEC dbo.usp_L19x_OrdersByStatus @Status = 'Pending';     -- 2 rows
GO

-- Q8  (catch-all: OPTION (RECOMPILE) lets the optimizer drop the NULL branches for the actual values.
--      The other classic answer is dynamic SQL that only adds the filters that are not NULL.)
CREATE OR ALTER PROCEDURE dbo.usp_L19x_OrderSearch @CustomerID INT = NULL, @Status VARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT OrderID, CustomerID, Status, TotalAmount
    FROM dbo.Orders
    WHERE (@CustomerID IS NULL OR CustomerID = @CustomerID)
      AND (@Status     IS NULL OR Status     = @Status)
    OPTION (RECOMPILE);
END
GO
EXEC dbo.usp_L19x_OrderSearch;                                       -- 19 rows (no filter)
EXEC dbo.usp_L19x_OrderSearch @CustomerID = 1;                       -- 4 rows
EXEC dbo.usp_L19x_OrderSearch @CustomerID = 1, @Status = 'Pending';  -- 1 row (1015)
GO

-- Q9
SELECT TOP (5) wait_type, waiting_tasks_count, wait_time_ms / 1000 AS WaitSec
FROM sys.dm_os_wait_stats
WHERE wait_type NOT IN ('CLR_SEMAPHORE','LAZYWRITER_SLEEP','RESOURCE_QUEUE','SLEEP_TASK','SLEEP_SYSTEMTASK','SQLTRACE_BUFFER_FLUSH',
      'WAITFOR','LOGMGR_QUEUE','CHECKPOINT_QUEUE','REQUEST_FOR_DEADLOCK_SEARCH','XE_TIMER_EVENT','BROKER_TO_FLUSH','BROKER_TASK_STOP',
      'CLR_MANUAL_EVENT','CLR_AUTO_EVENT','DISPATCHER_QUEUE_SEMAPHORE','FT_IFTS_SCHEDULER_IDLE_WAIT','XE_DISPATCHER_WAIT',
      'XE_DISPATCHER_JOIN','SQLTRACE_INCREMENTAL_FLUSH_SLEEP','ONDEMAND_TASK_QUEUE','BROKER_EVENTHANDLER','SLEEP_BPOOL_FLUSH',
      'DIRTY_PAGE_POLL','HADR_FILESTREAM_IOMGR_IOCOMPLETION','SP_SERVER_DIAGNOSTICS_SLEEP','QDS_PERSIST_TASK_MAIN_LOOP_SLEEP',
      'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP','QDS_ASYNC_QUEUE','QDS_SHUTDOWN_QUEUE','BROKER_RECEIVE_WAITFOR',
      'SOS_WORK_DISPATCHER','VDI_CLIENT_OTHER','PWAIT_ALL_COMPONENTS_INITIALIZED','PWAIT_DIRECTLOGCONSUMER_GETNEXT',
      'XE_LIVE_TARGET_TVF','MEMORY_ALLOCATION_EXT','WAIT_FOR_RESULTS','PVS_PREALLOCATE','STARTUP_DEPENDENCY_MANAGER',
      'HADR_WORK_QUEUE','HADR_TIMER_TASK','HADR_CLUSAPI_CALL','HADR_LOGCAPTURE_WAIT','HADR_NOTIFICATION_DEQUEUE',
      'HADR_FILESTREAM_IOMGR','KSOURCE_WAKEUP','LOGMGR_RESERVE_APPEND','SQLTRACE_WAIT_ENTRIES','SERVER_IDLE_CHECK',
      'SP_PREEMPTIVE_SERVER_DIAGNOSTICS_SLEEP','SOS_SCHEDULER_YIELD_IDLE')
  AND wait_type NOT LIKE 'PREEMPTIVE_%' AND wait_type NOT LIKE 'SLEEP_%' AND wait_type NOT LIKE 'PARALLEL_REDO_%'
ORDER BY wait_time_ms DESC;
GO

-- Q10
SELECT r.session_id AS Blocked, r.blocking_session_id AS Blocker, r.wait_type, r.wait_time AS WaitMs,
       s.login_name, s.program_name, t.text AS BlockedSql
FROM sys.dm_exec_requests r
JOIN sys.dm_exec_sessions s ON s.session_id = r.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.blocking_session_id <> 0;                          -- 0 rows: nobody is blocked right now
GO

-- Q11
SELECT TOP (5) qs.execution_count, qs.total_worker_time / 1000 AS TotalCpuMs, qs.total_logical_reads,
       SUBSTRING(st.text, qs.statement_start_offset / 2 + 1,
                 (CASE qs.statement_end_offset WHEN -1 THEN DATALENGTH(st.text) ELSE qs.statement_end_offset END
                  - qs.statement_start_offset) / 2 + 1) AS StatementText
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
ORDER BY qs.total_worker_time DESC;
GO

-- Q12
SELECT OBJECT_NAME(i.object_id) AS TableName, i.name AS IndexName, ISNULL(us.user_updates, 0) AS Writes
FROM sys.indexes i
LEFT JOIN sys.dm_db_index_usage_stats us ON us.object_id = i.object_id AND us.index_id = i.index_id AND us.database_id = DB_ID()
WHERE i.type_desc = 'NONCLUSTERED' AND OBJECTPROPERTY(i.object_id, 'IsUserTable') = 1
  AND ISNULL(us.user_seeks, 0) + ISNULL(us.user_scans, 0) + ISNULL(us.user_lookups, 0) = 0
ORDER BY TableName, IndexName;                             -- often 0 rows on a practice box (every index was read once); long list on a real server
GO
SELECT OrderID FROM dbo.Orders WHERE Status = 'Pending';   -- 2 rows; no index on Status -> the optimizer notes a suggestion
GO
SELECT mid.equality_columns, mid.inequality_columns, mid.included_columns, migs.user_seeks, migs.avg_user_impact
FROM sys.dm_db_missing_index_details mid
JOIN sys.dm_db_missing_index_groups mig       ON mig.index_handle = mid.index_handle
JOIN sys.dm_db_missing_index_group_stats migs ON migs.group_handle = mig.index_group_handle
WHERE mid.database_id = DB_ID() AND mid.object_id = OBJECT_ID('dbo.Orders');   -- may be 0 rows: on a 19-row table a scan is already cheap
GO

/* ---------- CLEANUP ---------- */
DROP PROCEDURE IF EXISTS dbo.usp_L19x_OrdersByStatus, dbo.usp_L19x_OrderSearch;
DROP INDEX IF EXISTS IX_L19x_Orders_OrderDate ON dbo.Orders;
GO
