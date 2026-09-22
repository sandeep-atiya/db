/* ============================================================
   LEVEL 18 - EXECUTION PLANS  |  03_Practice_Cardinality_Warnings.sql
   ------------------------------------------------------------
   Topics : cardinality estimation (estimated vs actual rows, stale
            statistics, table variables 1-row estimate vs deferred
            compilation), why wrong estimates matter (memory grants and
            spills to tempdb), plan warnings (implicit conversion, no join
            predicate, missing index, spills).

   HOW TO PRACTICE: run block by block, predict the output first.
   Database settings changed here (LAST_QUERY_PLAN_STATS, Query Store
   capture mode) are put back in the CLEANUP section.
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
-- Remember the current settings so CLEANUP can restore them exactly (temp table survives GO).
DROP TABLE IF EXISTS #L18_Settings;
SELECT (SELECT CAST(value AS INT) FROM sys.database_scoped_configurations WHERE name = 'LAST_QUERY_PLAN_STATS') AS LastPlanStats,
       (SELECT actual_state_desc       FROM sys.database_query_store_options) AS QsState,
       (SELECT query_capture_mode_desc FROM sys.database_query_store_options) AS QsCaptureMode
INTO #L18_Settings;
SELECT * FROM #L18_Settings;
GO
-- Keep the last ACTUAL plan of every cached query (2019+). Changing a scoped configuration flushes this
-- database's plan cache, so it is done here, before any query we want to look at.
ALTER DATABASE SCOPED CONFIGURATION SET LAST_QUERY_PLAN_STATS = ON;
GO
-- Query Store is used in 1c (it keeps plans the cache does not). Capture mode ALL records even one-off queries.
ALTER DATABASE SQLPractice SET QUERY_STORE = ON (OPERATION_MODE = READ_WRITE, QUERY_CAPTURE_MODE = ALL);
GO
-- Helpers from file 01 (explained there): operators of a cached plan / estimated vs actual rows of its last run
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
CREATE OR ALTER PROCEDURE dbo.usp_L18_EstVsActual @Tag NVARCHAR(100)
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
    IF @pointer IS NOT NULL SET @handle = CONVERT(VARBINARY(64), @pointer, 1);
    SELECT @plan = query_plan FROM sys.dm_exec_query_plan_stats(@handle);
    WITH XMLNAMESPACES (DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan')
    SELECT @Tag AS Tag, r.value('@NodeId', 'int') AS NodeId, r.value('@PhysicalOp', 'varchar(60)') AS PhysicalOp,
           r.value('@EstimateRows', 'float') AS EstRowsPerExecution,
           r.value('sum(RunTimeInformation/RunTimeCountersPerThread/@ActualRows)', 'float') AS ActualRowsTotal,
           r.value('sum(RunTimeInformation/RunTimeCountersPerThread/@ActualExecutions)', 'float') AS ActualExecutions,
           r.value('(IndexScan/Object/@Index)[1]', 'sysname') AS IndexName
    FROM @plan.nodes('//RelOp') AS n(r) ORDER BY NodeId;
END
GO
-- NEW helper: dbo.usp_L18_PlanWarnings @Tag - the query-level <Warnings> and <MissingIndex> elements of a cached plan
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
           @plan.value('(//Warnings/@NoJoinPredicate)[1]', 'varchar(5)') AS NoJoinPredicate,
           @plan.value('(//Warnings/PlanAffectingConvert/@ConvertIssue)[1]', 'varchar(50)') AS ConvertIssue,
           @plan.value('(//Warnings/PlanAffectingConvert/@Expression)[1]', 'varchar(200)') AS ConvertExpression,
           @plan.value('(//MissingIndexGroup/@Impact)[1]', 'float') AS MissingIndexImpact,
           @plan.value('(//MissingIndex/ColumnGroup[@Usage="EQUALITY"]/Column/@Name)[1]', 'sysname') AS MissingEqualityCol,
           @plan.value('(//MissingIndex/ColumnGroup[@Usage="INEQUALITY"]/Column/@Name)[1]', 'sysname') AS MissingInequalityCol,
           @plan.value('(//MissingIndex/ColumnGroup[@Usage="INCLUDE"]/Column/@Name)[1]', 'sysname') AS MissingIncludeCol;
END
GO


/* ============================================================
   1. CARDINALITY ESTIMATION - "how many rows will come out of this operator?"
   ============================================================
   The optimizer never reads the data while compiling. It uses STATISTICS (a histogram per
   index/column, Level 19) to GUESS the row count of every operator. Every decision - seek or
   scan, loops or hash, how much memory to reserve, serial or parallel - depends on that guess.
   A wrong estimate = a wrong plan, even though the query is "correct".
   ============================================================ */
-- 1a. A good estimate: statistics know there are 200 orders per customer.
SELECT /* L18c:good */ OrderID, Amount FROM dbo.L18_Orders WHERE CustomerID = 42 AND Amount > 90000;   -- 23 rows
GO
EXEC dbo.usp_L18_EstVsActual 'L18c:good';
-- expect: Index Seek Est 200 / Actual 200; Clustered Index Seek (lookup) Est 0.3 per execution, 200 executions, Actual 23 total
GO

-- 1b. STALE STATISTICS: insert 10,000 rows for a brand-new customer 1001. The histogram was built
--     before, so it has never heard of 1001. Auto-update only fires after about sqrt(1000 * rows)
--     = 14,142 changes on a 200,000-row table (SQL 2016+ rule), so 10,000 is NOT enough.
INSERT INTO dbo.L18_Orders (OrderID, CustomerID, EmployeeID, OrderDate, Amount, Status)
SELECT 200000 + value, 1001, 101, '2025-12-31', 500, 'Completed' FROM GENERATE_SERIES(1, 10000);
GO
SELECT sp.rows, sp.rows_sampled, sp.modification_counter, sp.last_updated
FROM sys.stats s CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) sp
WHERE s.object_id = OBJECT_ID('dbo.L18_Orders') AND s.name = 'IX_L18_Orders_CustomerID';
-- expect: rows 200000 (old!), modification_counter 10000
GO
SELECT /* L18c:stale */ COUNT(*) AS Cnt, SUM(Amount) AS Total FROM dbo.L18_Orders WHERE CustomerID = 1001;  -- 10000, 5000000.00
GO
EXEC dbo.usp_L18_EstVsActual 'L18c:stale';
-- expect: Index Seek Est 10 / Actual 10000 -> 1000x wrong! The optimizer chose seek + 10,000 Key Lookups
--         (fine for 10 rows, terrible for 10,000).
GO
-- FIX: refresh the statistics, then the same query gets a new estimate AND a different plan.
UPDATE STATISTICS dbo.L18_Orders IX_L18_Orders_CustomerID WITH FULLSCAN;
GO
SELECT /* L18c:fresh */ COUNT(*) AS Cnt, SUM(Amount) AS Total FROM dbo.L18_Orders WHERE CustomerID = 1001;  -- same result
GO
EXEC dbo.usp_L18_EstVsActual 'L18c:fresh';
-- expect: Index Seek Est 10000 / Actual 10000, and no per-row lookups: the plan now joins the
--         two nonclustered indexes with a Hash Match instead of 10,000 Key Lookups.
GO
DELETE FROM dbo.L18_Orders WHERE OrderID > 200000;            -- put the table back
UPDATE STATISTICS dbo.L18_Orders WITH FULLSCAN;
GO

-- 1c. TABLE VARIABLES: before SQL 2019 the optimizer always assumed a table variable has 1 ROW
--     (no statistics). SQL 2019+ (compat 150+) compiles the statement when the variable is already
--     filled ("deferred compilation") and sees the real count. The hint below shows the old behaviour.
DECLARE @Ids TABLE (CustomerID INT PRIMARY KEY);
INSERT INTO @Ids SELECT value FROM GENERATE_SERIES(1, 500);
SELECT /* L18c:tv_new */ COUNT(*) AS Cnt FROM @Ids t JOIN dbo.L18_Orders o ON o.CustomerID = t.CustomerID;   -- 100000
GO
-- A deferred-compiled batch is not kept in the plan cache on this build, so read its plan from
-- QUERY STORE instead (it records every statement's plan; more in file 04). Same XML, same RelOp nodes.
WITH XMLNAMESPACES (DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan')
SELECT r.value('@NodeId', 'int') AS NodeId, r.value('@PhysicalOp', 'varchar(60)') AS PhysicalOp,
       r.value('@EstimateRows', 'float') AS EstRows, r.value('(IndexScan/Object/@Table)[1]', 'sysname') AS TableName
FROM sys.query_store_query_text qt
JOIN sys.query_store_query q ON q.query_text_id = qt.query_text_id
JOIN sys.query_store_plan p  ON p.query_id = q.query_id
CROSS APPLY (SELECT CAST(p.query_plan AS XML) AS x) px
CROSS APPLY px.x.nodes('//RelOp') n(r)
WHERE qt.query_sql_text LIKE '%L18c:tv_new */%' AND qt.query_sql_text NOT LIKE '%query_store%'
ORDER BY NodeId;
-- expect: Merge Join <- Stream Aggregate <- Index Scan [L18_Orders] (200000) and Clustered Index Scan [@Ids] EstRows 500 (correct!)
GO
DECLARE @Ids TABLE (CustomerID INT PRIMARY KEY);
INSERT INTO @Ids SELECT value FROM GENERATE_SERIES(1, 500);
SELECT /* L18c:tv_old */ COUNT(*) AS Cnt FROM @Ids t JOIN dbo.L18_Orders o ON o.CustomerID = t.CustomerID
OPTION (USE HINT ('DISABLE_DEFERRED_COMPILATION_TV'));                                                     -- 100000
GO
EXEC dbo.usp_L18_PlanOps 'L18c:tv_old';        -- expect: table variable EstRows 1 -> Nested Loops (a plan built for 1 row, run for 500)
GO
-- Lesson: for big row sets prefer a #temp table (has statistics) over a table variable.

-- 1d. WHY IT MATTERS (2): memory grants. A Sort/Hash asks for memory based on the ESTIMATED rows.
--     Too small a grant -> the operator SPILLS to tempdb (slow disk). Simulate with MAX_GRANT_PERCENT.
SELECT /* L18c:spill */ TOP (1) OrderID
FROM (SELECT OrderID, ROW_NUMBER() OVER (ORDER BY Filler, Amount) AS rn FROM dbo.L18_Orders) x
WHERE rn = 1 OPTION (MAX_GRANT_PERCENT = 0.001, MAXDOP 1);
GO
SELECT qs.last_spills AS SpilledPages, qs.last_grant_kb, qs.last_used_grant_kb, qs.last_ideal_grant_kb
FROM sys.dm_exec_query_stats qs CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
WHERE st.text LIKE '%L18c:spill */%' AND st.text NOT LIKE '%dm_exec_query_stats%';
-- expect: about 11000 spilled pages, grant 512 KB while the ideal grant is about 44000 KB.
-- In an ACTUAL plan in SSMS the Sort shows a yellow warning "Operator used tempdb to spill data".
GO


/* ============================================================
   2. PLAN WARNINGS - the yellow triangles
   ============================================================ */
-- 2a. IMPLICIT CONVERSION: Status is VARCHAR, the variable is NVARCHAR. NVARCHAR wins the precedence
--     rule, so every Status value is converted -> the index cannot be SEEKED (scan) and the plan
--     carries a PlanAffectingConvert warning "Seek Plan".
DECLARE @s NVARCHAR(20) = N'Cancelled';
SELECT /* L18c:convert */ COUNT(*) AS Cnt FROM dbo.L18_Orders WHERE Status = @s;   -- 20000
GO
EXEC dbo.usp_L18_PlanWarnings 'L18c:convert';  -- expect: ConvertIssue 'Seek Plan', expression CONVERT_IMPLICIT(nvarchar(20),...Status...)
EXEC dbo.usp_L18_PlanOps 'L18c:convert';       -- expect: Index SCAN on IX_L18_Orders_Status (not a seek)
GO
DECLARE @s VARCHAR(20) = 'Cancelled';          -- FIX: match the column type
SELECT /* L18c:noconvert */ COUNT(*) AS Cnt FROM dbo.L18_Orders WHERE Status = @s;   -- 20000
GO
EXEC dbo.usp_L18_PlanWarnings 'L18c:noconvert';   -- expect: HasWarnings 0
EXEC dbo.usp_L18_PlanOps 'L18c:noconvert';        -- expect: Index SEEK on IX_L18_Orders_Status
GO

-- 2b. NO JOIN PREDICATE: a forgotten ON condition = cartesian product. The warning sits on the join operator.
SELECT c.CustomerName, o.OrderID
FROM dbo.L18_Customers c CROSS JOIN dbo.L18_Orders o
WHERE o.OrderID <= 2 AND c.CustomerID <= 3 /* L18c:nojoin */;                       -- 6 rows (3 x 2)
GO
EXEC dbo.usp_L18_PlanWarnings 'L18c:nojoin';   -- expect: NoJoinPredicate true
GO

-- 2c. MISSING INDEX: no index on Amount -> full scan, and the optimizer records a suggestion (read it in file 04).
SELECT /* L18c:missing */ OrderID, Amount FROM dbo.L18_Orders WHERE Amount = 555;   -- 2 rows
GO
EXEC dbo.usp_L18_PlanWarnings 'L18c:missing';  -- expect: MissingIndexImpact about 99, MissingEqualityCol Amount
GO
-- 2d. SPILL warnings exist only in ACTUAL plans (see 1d): "Sort/Hash warnings: operator used tempdb".


/* ============================================================
   3. CLEANUP - drop objects and restore the settings snapshot
   ============================================================ */
DECLARE @qsState NVARCHAR(30) = (SELECT QsState FROM #L18_Settings),
        @qsMode  NVARCHAR(30) = (SELECT QsCaptureMode FROM #L18_Settings),
        @lqps    INT          = (SELECT LastPlanStats FROM #L18_Settings);
IF @qsState = 'OFF'
    ALTER DATABASE SQLPractice SET QUERY_STORE = OFF;
ELSE IF @qsMode <> 'ALL'
    EXEC ('ALTER DATABASE SQLPractice SET QUERY_STORE = ON (QUERY_CAPTURE_MODE = ' + @qsMode + ');');
IF @lqps = 0  ALTER DATABASE SCOPED CONFIGURATION SET LAST_QUERY_PLAN_STATS = OFF;  -- default is OFF
GO
SELECT actual_state_desc, query_capture_mode_desc FROM sys.database_query_store_options;
SELECT name, value FROM sys.database_scoped_configurations WHERE name = 'LAST_QUERY_PLAN_STATS';
GO
DROP PROCEDURE IF EXISTS dbo.usp_L18_PlanOps;
DROP PROCEDURE IF EXISTS dbo.usp_L18_EstVsActual;
DROP PROCEDURE IF EXISTS dbo.usp_L18_PlanWarnings;
DROP TABLE IF EXISTS dbo.L18_Orders;
DROP TABLE IF EXISTS dbo.L18_Customers;
DROP TABLE IF EXISTS #L18_Settings;
GO
/* DONE. Next: 04_Practice_PlanCache_QueryStore.sql */
