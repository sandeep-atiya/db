/* ============================================================
   LEVEL 18 - EXECUTION PLANS  |  04_Practice_PlanCache_QueryStore.sql
   ------------------------------------------------------------
   Topics : the plan cache (finding a plan, objtype / usecounts, freeing
            ONE plan, DBCC FREEPROCCACHE and why it is dangerous, per-database
            CLEAR PROCEDURE_CACHE), plan reuse and parameterisation (simple
            vs forced), Query Store (turn on, the views, top resource
            queries, forcing / unforcing a plan), reading the missing-index
            suggestion and why not to apply it blindly.

   HOW TO PRACTICE: run block by block, predict the output first.
   Database settings changed here (PARAMETERIZATION, Query Store capture
   mode) are put back in the CLEANUP section.
   ============================================================ */

USE SQLPractice;
GO
SET QUOTED_IDENTIFIER ON;      -- XML methods need it (sqlcmd default is OFF)
SET NOCOUNT ON;
GO


/* ============================================================
   0. SETUP - helper tables (same as file 01), settings snapshot, helper procs
   ============================================================ */
DROP TABLE IF EXISTS dbo.L18_Orders;
DROP TABLE IF EXISTS dbo.L18_Customers;
GO
CREATE TABLE dbo.L18_Customers
(
    CustomerID   INT         NOT NULL CONSTRAINT PK_L18_Customers PRIMARY KEY,
    CustomerName VARCHAR(50) NOT NULL,
    City         VARCHAR(30) NOT NULL
);
INSERT INTO dbo.L18_Customers (CustomerID, CustomerName, City)
SELECT value, 'Customer ' + CAST(value AS VARCHAR(10)),
       CHOOSE(value % 5 + 1, 'Delhi', 'Mumbai', 'Pune', 'Bangalore', 'Chennai')
FROM GENERATE_SERIES(1, 1000);
GO
CREATE TABLE dbo.L18_Orders
(
    OrderID    INT           NOT NULL CONSTRAINT PK_L18_Orders PRIMARY KEY,
    CustomerID INT           NOT NULL,
    EmployeeID INT           NOT NULL,
    OrderDate  DATE          NOT NULL,
    Amount     DECIMAL(12,2) NOT NULL,
    Status     VARCHAR(20)   NOT NULL,
    Filler     CHAR(100)     NOT NULL CONSTRAINT DF_L18_Orders_Filler DEFAULT ('x')
);
INSERT INTO dbo.L18_Orders (OrderID, CustomerID, EmployeeID, OrderDate, Amount, Status)
SELECT value, (value - 1) % 1000 + 1, 101 + value % 12,
       DATEADD(DAY, value % 1096, '2023-01-01'), 100 + (value * 7919) % 99900,
       CASE value % 10 WHEN 0 THEN 'Cancelled' WHEN 1 THEN 'Pending' ELSE 'Completed' END
FROM GENERATE_SERIES(1, 200000);
CREATE INDEX IX_L18_Orders_CustomerID ON dbo.L18_Orders (CustomerID);
CREATE INDEX IX_L18_Orders_OrderDate  ON dbo.L18_Orders (OrderDate) INCLUDE (Amount);
CREATE INDEX IX_L18_Orders_Status     ON dbo.L18_Orders (Status);
GO
-- Settings snapshot for CLEANUP (temp table survives GO)
DROP TABLE IF EXISTS #L18_Settings;
SELECT (SELECT is_parameterization_forced FROM sys.databases WHERE name = DB_NAME()) AS ParamForced,
       (SELECT actual_state_desc       FROM sys.database_query_store_options)         AS QsState,
       (SELECT query_capture_mode_desc FROM sys.database_query_store_options)         AS QsCaptureMode
INTO #L18_Settings;
SELECT * FROM #L18_Settings;
GO
-- Helpers from files 01 and 03 (explained there)
CREATE OR ALTER PROCEDURE dbo.usp_L18_PlanOps @Tag NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @handle VARBINARY(64), @objtype NVARCHAR(20), @uses INT, @plan XML, @pointer VARCHAR(200);
    SELECT TOP (1) @handle = cp.plan_handle, @objtype = cp.objtype, @uses = cp.usecounts
    FROM sys.dm_exec_cached_plans cp CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) st
    WHERE st.text LIKE '%' + @Tag + ' */%' AND st.text NOT LIKE '%usp_L18_%' AND st.text NOT LIKE '%dm_exec_cached_plans%'
    ORDER BY cp.usecounts DESC;
    IF @handle IS NULL BEGIN PRINT 'No cached plan found for tag ' + @Tag; RETURN; END;
    SELECT @plan = query_plan FROM sys.dm_exec_query_plan(@handle);
    WITH XMLNAMESPACES (DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan')
    SELECT @pointer = @plan.value('(//StmtSimple/@ParameterizedPlanHandle)[1]', 'varchar(200)');
    IF @pointer IS NOT NULL SELECT @plan = query_plan FROM sys.dm_exec_query_plan(CONVERT(VARBINARY(64), @pointer, 1));
    WITH XMLNAMESPACES (DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan')
    SELECT @Tag AS Tag, @objtype AS ObjType, @uses AS UseCounts,
           CASE WHEN @pointer IS NULL THEN 'direct' ELSE 'auto-parameterised' END AS PlanSource, r.value('@NodeId', 'int') AS NodeId,
           r.value('@PhysicalOp', 'varchar(60)') AS PhysicalOp, r.value('@LogicalOp', 'varchar(60)') AS LogicalOp,
           r.value('@EstimateRows', 'float') AS EstRows, r.value('@EstimatedTotalSubtreeCost', 'float') AS SubtreeCost,
           r.value('(IndexScan/Object/@Index)[1]', 'sysname') AS IndexName
    FROM @plan.nodes('//RelOp') AS n(r) ORDER BY NodeId;
END
GO
CREATE OR ALTER PROCEDURE dbo.usp_L18_PlanWarnings @Tag NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @handle VARBINARY(64), @plan XML, @pointer VARCHAR(200);
    SELECT TOP (1) @handle = cp.plan_handle
    FROM sys.dm_exec_cached_plans cp CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) st
    WHERE st.text LIKE '%' + @Tag + ' */%' AND st.text NOT LIKE '%usp_L18_%' AND st.text NOT LIKE '%dm_exec_cached_plans%'
    ORDER BY cp.usecounts DESC;
    IF @handle IS NULL BEGIN PRINT 'No cached plan found for tag ' + @Tag; RETURN; END;
    SELECT @plan = query_plan FROM sys.dm_exec_query_plan(@handle);
    WITH XMLNAMESPACES (DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan')
    SELECT @pointer = @plan.value('(//StmtSimple/@ParameterizedPlanHandle)[1]', 'varchar(200)');
    IF @pointer IS NOT NULL SELECT @plan = query_plan FROM sys.dm_exec_query_plan(CONVERT(VARBINARY(64), @pointer, 1));
    WITH XMLNAMESPACES (DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan')
    SELECT @Tag AS Tag, @plan.exist('//Warnings') AS HasWarnings,
           @plan.value('(//MissingIndexGroup/@Impact)[1]', 'float') AS MissingIndexImpact,
           @plan.value('(//MissingIndex/ColumnGroup[@Usage="EQUALITY"]/Column/@Name)[1]', 'sysname') AS MissingEqualityCol,
           @plan.value('(//MissingIndex/ColumnGroup[@Usage="INEQUALITY"]/Column/@Name)[1]', 'sysname') AS MissingInequalityCol,
           @plan.value('(//MissingIndex/ColumnGroup[@Usage="INCLUDE"]/Column/@Name)[1]', 'sysname') AS MissingIncludeCol;
END
GO


/* ============================================================
   1. THE PLAN CACHE
   ============================================================ */
-- 1a. Run two tagged queries, then look at their cache entries. objtype: Adhoc (plain batch),
--     Prepared (parameterised), Proc (stored procedure). usecounts = how often the plan was reused.
SELECT /* L18d:q1 */ OrderID, Amount FROM dbo.L18_Orders WHERE Amount = 555;                          -- 2 rows
GO
SELECT /* L18d:q2 */ COUNT(*) AS Cnt, SUM(Amount) AS Total FROM dbo.L18_Orders WHERE CustomerID = 77;  -- 200, about 9.8 million
GO
SELECT cp.objtype, cp.usecounts, cp.size_in_bytes / 1024 AS SizeKB, LEFT(st.text, 70) AS QueryText
FROM sys.dm_exec_cached_plans cp
CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) st
WHERE st.text LIKE '%L18d:q% */%' AND st.text NOT LIKE '%dm_exec_cached_plans%'
ORDER BY st.text;                                                                                      -- 2 Adhoc rows, usecounts 1
GO
-- 1b. Remove ONE plan: DBCC FREEPROCCACHE (plan_handle). Safe and precise.
DECLARE @h VARBINARY(64) = (SELECT TOP (1) cp.plan_handle FROM sys.dm_exec_cached_plans cp
                            CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) st
                            WHERE st.text LIKE '%L18d:q1 */%' AND st.text NOT LIKE '%dm_exec_cached_plans%');
DBCC FREEPROCCACHE (@h) WITH NO_INFOMSGS;
GO
EXEC dbo.usp_L18_PlanOps 'L18d:q1';            -- expect: 'No cached plan found for tag L18d:q1'
EXEC dbo.usp_L18_PlanOps 'L18d:q2';            -- expect: still there (Nested Loops, Index Seek, Clustered Index Seek)
GO
-- 1c. DBCC FREEPROCCACHE with NO argument empties the WHOLE server cache: every query on every
--     database recompiles -> CPU spike on a busy production server. Only for practice/test boxes.
--     Per-database alternative (2016+), used here because it touches only this database:
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
GO
SELECT COUNT(*) AS PlansLeftForThisFile
FROM sys.dm_exec_cached_plans cp CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) st
WHERE st.text LIKE '%L18d:q% */%' AND st.text NOT LIKE '%dm_exec_cached_plans%';                       -- 0
GO


/* ============================================================
   2. PLAN REUSE AND PARAMETERISATION
   ============================================================ */
-- 2a. SIMPLE parameterisation (default): for a TRIVIAL query the literal is replaced by a parameter,
--     so two different values share ONE Prepared plan (+ one Adhoc shell per text).
SELECT COUNT(*) AS Cnt FROM dbo.L18_Orders WHERE CustomerID = 44 /* L18d:simple */;   -- 200
GO
SELECT COUNT(*) AS Cnt FROM dbo.L18_Orders WHERE CustomerID = 45 /* L18d:simple */;   -- 200
GO
SELECT cp.objtype, cp.usecounts, LEFT(st.text, 90) AS QueryText
FROM sys.dm_exec_cached_plans cp CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) st
WHERE (st.text LIKE '%L18d:simple */%' OR st.text LIKE '(@1 %L18_Orders%CustomerID]=@1%')
  AND st.text NOT LIKE '%dm_exec_cached_plans%'
ORDER BY cp.objtype;
-- expect: 2 Adhoc shells (usecounts 1 each) + 1 Prepared "(@1 tinyint)SELECT COUNT(*) [Cnt] FROM ... WHERE [CustomerID]=@1" with usecounts 2
GO
-- 2b. A NON-trivial query (join) is NOT parameterised: two literals = two full plans = cache bloat.
SELECT c.CustomerName, o.OrderID FROM dbo.L18_Customers c JOIN dbo.L18_Orders o ON o.CustomerID = c.CustomerID
WHERE c.CustomerID = 11 AND o.Amount > 99000 /* L18d:join */;
GO
SELECT c.CustomerName, o.OrderID FROM dbo.L18_Customers c JOIN dbo.L18_Orders o ON o.CustomerID = c.CustomerID
WHERE c.CustomerID = 12 AND o.Amount > 99000 /* L18d:join */;
GO
SELECT cp.objtype, cp.usecounts, LEFT(st.text, 60) AS QueryText
FROM sys.dm_exec_cached_plans cp CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) st
WHERE st.text LIKE '%L18d:join */%' AND st.text NOT LIKE '%dm_exec_cached_plans%';      -- 2 Adhoc plans, no Prepared
GO
-- 2c. FORCED parameterisation: the database parameterises (almost) every literal. Fixes cache bloat
--     for apps that send literals, but one plan for all values = parameter-sniffing risk (Level 19).
ALTER DATABASE SQLPractice SET PARAMETERIZATION FORCED;
GO
SELECT c.CustomerName, o.OrderID FROM dbo.L18_Customers c JOIN dbo.L18_Orders o ON o.CustomerID = c.CustomerID
WHERE c.CustomerID = 13 AND o.Amount > 99000 /* L18d:forced */;
GO
SELECT c.CustomerName, o.OrderID FROM dbo.L18_Customers c JOIN dbo.L18_Orders o ON o.CustomerID = c.CustomerID
WHERE c.CustomerID = 14 AND o.Amount > 99000 /* L18d:forced */;
GO
SELECT cp.objtype, cp.usecounts, LEFT(st.text, 110) AS QueryText
FROM sys.dm_exec_cached_plans cp CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) st
WHERE cp.objtype = 'Prepared' AND st.text LIKE '%L18_Customers c join%' AND st.text NOT LIKE '%dm_exec_cached_plans%';
-- expect: 1 Prepared plan "(@0 int,@1 int)select c . CustomerName ..." with usecounts 2 (text is normalised by the server)
GO
ALTER DATABASE SQLPractice SET PARAMETERIZATION SIMPLE;   -- back to default (CLEANUP restores the snapshot value too)
GO
-- Best practice: applications should send PARAMETERS (sp_executesql, ORM parameters) - Level 14/20.


/* ============================================================
   3. QUERY STORE - the "flight recorder" for plans (2016+, ON by default for new DBs in 2022+)
   ============================================================ */
-- 3a. Turn it on with capture mode ALL so even cheap one-off queries are recorded (AUTO skips them).
ALTER DATABASE SQLPractice SET QUERY_STORE = ON (OPERATION_MODE = READ_WRITE, QUERY_CAPTURE_MODE = ALL);
GO
SELECT actual_state_desc, query_capture_mode_desc, max_storage_size_mb, stale_query_threshold_days
FROM sys.database_query_store_options;                                                -- READ_WRITE, ALL, ...
GO
-- 3b. Run a query 3 times (GO 3 repeats the batch). The tag is INSIDE the statement on purpose:
--     Query Store stores statement text, and a comment after the statement is not part of it.
SELECT /* L18d:qs */ COUNT(*) AS Cnt, SUM(Amount) AS Total FROM dbo.L18_Orders WHERE CustomerID = 79;
GO 3
-- 3c. The four views: query text -> query -> plan(s) -> runtime stats per interval
SELECT q.query_id, p.plan_id, p.is_forced_plan, rs.count_executions,
       rs.avg_logical_io_reads, rs.avg_duration AS AvgMicroseconds, LEFT(qt.query_sql_text, 60) AS QueryText
FROM sys.query_store_query_text qt
JOIN sys.query_store_query q          ON q.query_text_id = qt.query_text_id
JOIN sys.query_store_plan p           ON p.query_id = q.query_id
JOIN sys.query_store_runtime_stats rs ON rs.plan_id = p.plan_id
WHERE qt.query_sql_text LIKE '%L18d:qs */%' AND qt.query_sql_text NOT LIKE '%query_store%';
-- expect: 1 row, count_executions 3, avg_logical_io_reads about 666, is_forced_plan 0
GO
-- 3d. Top resource-consuming queries of this database (what the SSMS "Top Resource Consuming Queries" report shows)
SELECT TOP (5) q.query_id, SUM(rs.count_executions) AS Executions,
       CAST(SUM(rs.avg_cpu_time * rs.count_executions) / 1000 AS DECIMAL(12,1)) AS TotalCpuMs,
       CAST(SUM(rs.avg_logical_io_reads * rs.count_executions) AS BIGINT) AS TotalReads,
       LEFT(qt.query_sql_text, 60) AS QueryText
FROM sys.query_store_query q
JOIN sys.query_store_query_text qt    ON qt.query_text_id = q.query_text_id
JOIN sys.query_store_plan p           ON p.query_id = q.query_id
JOIN sys.query_store_runtime_stats rs ON rs.plan_id = p.plan_id
GROUP BY q.query_id, qt.query_sql_text
ORDER BY TotalCpuMs DESC;
GO
-- 3e. FORCE a plan (what you do when a good plan was replaced by a bad one after a stats change):
--     sp_query_store_force_plan @query_id, @plan_id. UNFORCE when the root cause is fixed.
DECLARE @q BIGINT, @p BIGINT;
SELECT TOP (1) @q = q.query_id, @p = p.plan_id
FROM sys.query_store_query_text qt
JOIN sys.query_store_query q ON q.query_text_id = qt.query_text_id
JOIN sys.query_store_plan p  ON p.query_id = q.query_id
WHERE qt.query_sql_text LIKE '%L18d:qs */%' AND qt.query_sql_text NOT LIKE '%query_store%';
IF @q IS NULL PRINT 'Query not captured yet - run 3b again'
ELSE
BEGIN
    EXEC sp_query_store_force_plan @q, @p;
    SELECT plan_id, is_forced_plan FROM sys.query_store_plan WHERE query_id = @q;    -- is_forced_plan 1
    EXEC sp_query_store_unforce_plan @q, @p;
    SELECT plan_id, is_forced_plan FROM sys.query_store_plan WHERE query_id = @q;    -- is_forced_plan 0
END
GO
-- In SSMS: Database -> Query Store -> "Regressed Queries" / "Top Resource Consuming Queries" -> Force Plan button.


/* ============================================================
   4. READING THE "MISSING INDEX" SUGGESTION - and why not to apply it blindly
   ============================================================ */
SELECT /* L18d:mi */ OrderID, Amount, Status FROM dbo.L18_Orders WHERE Amount BETWEEN 500 AND 505;   -- 12 rows
GO
EXEC dbo.usp_L18_PlanWarnings 'L18d:mi';
-- expect: MissingIndexImpact about 70, MissingInequalityCol Amount (BETWEEN = range), MissingIncludeCol Status
GO
-- The server also keeps every suggestion in DMVs (reset at restart):
SELECT mid.equality_columns, mid.inequality_columns, mid.included_columns,
       migs.user_seeks, migs.avg_user_impact, migs.avg_total_user_cost
FROM sys.dm_db_missing_index_details mid
JOIN sys.dm_db_missing_index_groups mig       ON mig.index_handle = mid.index_handle
JOIN sys.dm_db_missing_index_group_stats migs ON migs.group_handle = mig.index_group_handle
WHERE mid.database_id = DB_ID() AND mid.object_id = OBJECT_ID('dbo.L18_Orders');
GO
/* WHY NOT APPLY IT BLINDLY?
   1. Impact % is for THIS query only; user_seeks tells you if it runs often enough to matter.
   2. The suggestion is greedy: it INCLUDEs every column the query touched -> a wide duplicate index.
      Check existing indexes first: maybe adding ONE include column to an existing index is enough.
   3. Column order in the suggestion is not tuned (equality columns first, then inequality, most
      selective first is YOUR job).
   4. Every index costs writes (INSERT/UPDATE/DELETE maintain it) and space.
   5. It never suggests filtered indexes, columnstore, or a query rewrite - often the better fix.   */


/* ============================================================
   5. CLEANUP - drop objects and restore the settings snapshot
   ============================================================ */
DECLARE @qsState NVARCHAR(30) = (SELECT QsState FROM #L18_Settings),
        @qsMode  NVARCHAR(30) = (SELECT QsCaptureMode FROM #L18_Settings),
        @forced  BIT          = (SELECT ParamForced FROM #L18_Settings);
IF @qsState = 'OFF'
    ALTER DATABASE SQLPractice SET QUERY_STORE = OFF;
ELSE IF @qsMode <> 'ALL'
    EXEC ('ALTER DATABASE SQLPractice SET QUERY_STORE = ON (QUERY_CAPTURE_MODE = ' + @qsMode + ');');
IF @forced = 1 ALTER DATABASE SQLPractice SET PARAMETERIZATION FORCED;
GO
SELECT actual_state_desc, query_capture_mode_desc FROM sys.database_query_store_options;
SELECT is_parameterization_forced FROM sys.databases WHERE name = DB_NAME();
GO
DROP PROCEDURE IF EXISTS dbo.usp_L18_PlanOps;
DROP PROCEDURE IF EXISTS dbo.usp_L18_PlanWarnings;
DROP TABLE IF EXISTS dbo.L18_Orders;
DROP TABLE IF EXISTS dbo.L18_Customers;
DROP TABLE IF EXISTS #L18_Settings;
GO
/* DONE. Next: Exercises.sql */
