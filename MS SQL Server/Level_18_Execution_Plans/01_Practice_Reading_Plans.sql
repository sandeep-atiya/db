/* ============================================================
   LEVEL 18 - EXECUTION PLANS  |  01_Practice_Reading_Plans.sql
   ------------------------------------------------------------
   Topics : estimated vs actual plan, how to get a plan in SSMS
            (Ctrl+L / Ctrl+M / Live Query Statistics) and in T-SQL
            (SHOWPLAN_TEXT, SHOWPLAN_XML, SHOWPLAN_ALL, STATISTICS XML,
            STATISTICS IO / TIME), how to read a plan (right-to-left,
            arrows, cost %, tooltip properties), finding a plan in the
            plan cache and searching its XML, helper procs used by
            files 02 and 03.

   HOW TO PRACTICE: run block by block, predict the output first.
   This level builds two helper tables (dbo.L18_Orders = 200,000 rows,
   dbo.L18_Customers = 1,000 rows) so that plans look like real life.
   Everything is dropped in the CLEANUP section.
   ============================================================ */

USE SQLPractice;
GO
-- sqlcmd starts with QUOTED_IDENTIFIER OFF; XML methods (.value/.nodes) need it ON.
-- SSMS already has it ON. Harmless to set it again.
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO


/* ============================================================
   0. SETUP - build the big helper tables (about 2 seconds)
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
SELECT value,
       'Customer ' + CAST(value AS VARCHAR(10)),
       CHOOSE(value % 5 + 1, 'Delhi', 'Mumbai', 'Pune', 'Bangalore', 'Chennai')
FROM GENERATE_SERIES(1, 1000);                          -- GENERATE_SERIES = SQL 2022+
GO
CREATE TABLE dbo.L18_Orders
(
    OrderID    INT           NOT NULL CONSTRAINT PK_L18_Orders PRIMARY KEY,   -- clustered index
    CustomerID INT           NOT NULL,
    EmployeeID INT           NOT NULL,
    OrderDate  DATE          NOT NULL,
    Amount     DECIMAL(12,2) NOT NULL,
    Status     VARCHAR(20)   NOT NULL,
    Filler     CHAR(100)     NOT NULL CONSTRAINT DF_L18_Orders_Filler DEFAULT ('x')  -- makes rows wide, like real tables
);
INSERT INTO dbo.L18_Orders (OrderID, CustomerID, EmployeeID, OrderDate, Amount, Status)
SELECT value,
       (value - 1) % 1000 + 1,                            -- exactly 200 orders per customer
       101 + value % 12,                                  -- 12 salespeople 101..112
       DATEADD(DAY, value % 1096, '2023-01-01'),          -- 3 years: 2023-01-01 .. 2025-12-31
       100 + (value * 7919) % 99900,                      -- pseudo-random 100 .. 99999
       CASE value % 10 WHEN 0 THEN 'Cancelled' WHEN 1 THEN 'Pending' ELSE 'Completed' END
FROM GENERATE_SERIES(1, 200000);
CREATE INDEX IX_L18_Orders_CustomerID ON dbo.L18_Orders (CustomerID);
CREATE INDEX IX_L18_Orders_OrderDate  ON dbo.L18_Orders (OrderDate) INCLUDE (Amount);
CREATE INDEX IX_L18_Orders_Status     ON dbo.L18_Orders (Status);
GO
-- Section 8 needs the database to remember the last ACTUAL plan of every cached query (SQL 2019+).
-- Set it here, at the start: changing ANY database scoped configuration flushes the plan cache
-- of this database, which would wipe the plans we want to look at later. CLEANUP turns it off.
ALTER DATABASE SCOPED CONFIGURATION SET LAST_QUERY_PLAN_STATS = ON;
GO
-- Sanity check: 200000 rows, 1000 customers, dates 2023-01-01 .. 2025-12-31, 3 statuses
SELECT COUNT(*) AS Rows_, COUNT(DISTINCT CustomerID) AS Customers,
       MIN(OrderDate) AS FirstDate, MAX(OrderDate) AS LastDate
FROM dbo.L18_Orders;                                        -- 200000, 1000, 2023-01-01, 2025-12-31
SELECT Status, COUNT(*) AS Cnt FROM dbo.L18_Orders GROUP BY Status ORDER BY Status;  -- Cancelled 20000, Completed 160000, Pending 20000
GO
-- How big is the table? (pages of 8 KB per index). index_id 1 = clustered index = the table itself.
SELECT i.name AS IndexName, i.index_id, SUM(ps.used_page_count) AS Pages
FROM sys.dm_db_partition_stats ps
JOIN sys.indexes i ON i.object_id = ps.object_id AND i.index_id = ps.index_id
WHERE ps.object_id = OBJECT_ID('dbo.L18_Orders')
GROUP BY i.name, i.index_id ORDER BY i.index_id;            -- clustered about 3650 pages, CustomerID about 350, OrderDate about 550, Status about 470
GO


/* ============================================================
   1. ESTIMATED vs ACTUAL PLAN - what is the difference?
   ============================================================
   ESTIMATED plan = what the optimizer PLANS to do. Produced by
     compiling the query WITHOUT running it. Row counts are guesses
     made from statistics ("Estimated Number of Rows").
   ACTUAL plan    = the same plan PLUS what really happened when the
     query ran ("Actual Number of Rows", actual executions, spills,
     time per operator). The shape is the same; the numbers are real.

   In SSMS:
     Ctrl+L            -> Display Estimated Execution Plan (does not run the query)
     Ctrl+M  then F5   -> Include Actual Execution Plan (runs the query, adds an "Execution plan" tab)
     Query menu -> Include Live Query Statistics -> watch operators fill up while a long query runs
   In T-SQL (what this file shows):
     SET SHOWPLAN_TEXT ON / SET SHOWPLAN_XML ON / SET SHOWPLAN_ALL ON  -> estimated, query NOT executed
     SET STATISTICS XML ON                                             -> actual plan XML + results
     SET STATISTICS IO ON / SET STATISTICS TIME ON                     -> reads and CPU time per query
   ============================================================ */


/* ============================================================
   2. SET SHOWPLAN_TEXT ON  (estimated plan as indented text)
   ============================================================ */
-- 2a. The SET SHOWPLAN statement must be ALONE in its batch (GO before and after).
--     Every batch that follows returns its plan instead of running. Read the tree
--     from the deepest indentation (leaf) upwards: Index Seek -> Nested Loops.
SET SHOWPLAN_TEXT ON;
GO
SELECT OrderID, CustomerID, Amount FROM dbo.L18_Orders WHERE CustomerID = 42;
GO
SET SHOWPLAN_TEXT OFF;
GO
-- expect 3 plan rows (StmtText): Nested Loops(Inner Join ...)
--                                   |--Index Seek(OBJECT:(...IX_L18_Orders_CustomerID), SEEK:(CustomerID=(42)))
--                                   |--Clustered Index Seek(OBJECT:(...PK_L18_Orders), SEEK:(OrderID=OrderID) LOOKUP)
-- "LOOKUP" on the clustered index seek = a Key Lookup (Amount is not in the nonclustered index).

-- 2b. Proof that SHOWPLAN does NOT execute: an UPDATE under SHOWPLAN changes nothing.
SET SHOWPLAN_TEXT ON;
GO
UPDATE dbo.L18_Customers SET City = 'Goa' WHERE CustomerID = 1;
GO
SET SHOWPLAN_TEXT OFF;
GO
SELECT City FROM dbo.L18_Customers WHERE CustomerID = 1;   -- still 'Mumbai' -> the UPDATE never ran
GO

-- 2c. Predicate vs Seek Predicate. SEEK:(...) = the index navigates straight to the rows.
--     WHERE:(...) = a "residual predicate": rows are read first, then filtered.
--     Here CustomerID is seeked, Amount > 90000 is checked on each looked-up row.
SET SHOWPLAN_TEXT ON;
GO
SELECT OrderID, CustomerID, Amount FROM dbo.L18_Orders WHERE CustomerID = 42 AND Amount > 90000;
GO
SET SHOWPLAN_TEXT OFF;
GO
-- expect: Index Seek ... SEEK:([CustomerID]=(42))  and  Clustered Index Seek ... WHERE:([Amount]>(90000.00)) LOOKUP


/* ============================================================
   3. SET SHOWPLAN_ALL ON  (estimated plan + the "tooltip" numbers)
   ============================================================ */
-- One row per operator with EstimateRows, EstimateIO, EstimateCPU, TotalSubtreeCost,
-- OutputList, Warnings, Parallel, EstimateExecutions. These are exactly the properties
-- SSMS shows when you hover an operator. Wide output - scroll right.
SET SHOWPLAN_ALL ON;
GO
SELECT OrderID, CustomerID, Amount FROM dbo.L18_Orders WHERE CustomerID = 42;
GO
SET SHOWPLAN_ALL OFF;
GO
-- expect: Index Seek EstimateRows 200 (statistics know 200 orders per customer),
--         Clustered Index Seek EstimateRows 1 with EstimateExecutions 200 (the lookup runs once per row),
--         TotalSubtreeCost of the root about 0.64 ("cost" = unit-less estimate, not seconds).


/* ============================================================
   4. SET SHOWPLAN_XML ON  and  SET STATISTICS XML ON
   ============================================================ */
-- 4a. Estimated plan as XML (in SSMS the cell is a clickable link that opens the graphical plan)
SET SHOWPLAN_XML ON;
GO
SELECT OrderID FROM dbo.L18_Orders WHERE CustomerID = 42;
GO
SET SHOWPLAN_XML OFF;
GO
-- expect 1 row: <ShowPlanXML xmlns=... ><BatchSequence><Batch><Statements><StmtSimple ...

-- 4b. ACTUAL plan: STATISTICS XML runs the query, returns the results AND a second result
--     set with the actual plan (RunTimeInformation / ActualRows inside the XML).
SET STATISTICS XML ON;
GO
SELECT COUNT(*) AS OrdersOfCustomer42 FROM dbo.L18_Orders WHERE CustomerID = 42;   -- 200
GO
SET STATISTICS XML OFF;
GO


/* ============================================================
   5. SET STATISTICS IO, TIME ON  (the numbers you tune by)
   ============================================================ */
-- logical reads  = 8 KB pages read from memory (the number to compare before/after a change)
-- physical reads = pages that had to come from disk (depends on cache, ignore for tuning)
-- read-ahead     = pages pre-fetched from disk
-- scan count     = how many times the object was accessed (loops)
-- CPU time vs elapsed time: elapsed includes waiting (locks, I/O, network); CPU is pure work.
SET STATISTICS IO, TIME ON;
GO
SELECT COUNT(*) AS OrdersOfEmp105 FROM dbo.L18_Orders WHERE EmployeeID = 105;  -- 16667 (no index on EmployeeID -> full scan)
GO
SELECT COUNT(*) AS PendingOrders FROM dbo.L18_Orders WHERE Status = 'Pending';  -- 20000 (index on Status -> seek)
GO
SET STATISTICS IO, TIME OFF;
GO
-- expect: first query 'L18_Orders' logical reads about 3652 (whole clustered index),
--         second query logical reads about 56 (one range of the Status index).


/* ============================================================
   6. HOW TO READ A GRAPHICAL PLAN (mental model)
   ============================================================
   * Data flows RIGHT to LEFT: the operator on the far right reads the table/index;
     the operator on the far left (SELECT) returns rows to you.
   * Execution order is TOP to BOTTOM for the children of a join: the top input of a
     Nested Loops is the OUTER (driving) input, the bottom input runs once per outer row.
   * ARROW THICKNESS = number of rows flowing. A thick arrow going into a thin result
     means a lot of work was thrown away (filter too late, missing index).
   * COST % per operator = share of the ESTIMATED total cost. Even in an "actual" plan
     these are estimates. Look at the biggest % first, but also at the estimate/actual gap.
   * TOOLTIP (hover) properties to always check:
       Estimated Number of Rows vs Actual Number of Rows  -> gap = cardinality problem
       Estimated Subtree Cost                             -> cost of this operator + everything to its right
       Predicate vs Seek Predicate                        -> seek = good, residual predicate = rows read then filtered
       Output List                                        -> columns carried; too many -> maybe Key Lookup / no covering index
       Warnings (yellow triangle)                         -> implicit conversion, missing index, spill, no join predicate
   * Number of Executions: an inner-side operator that says "1 estimated row" but
     "200 executions" did 200 seeks - that is the Key Lookup pattern.
   ============================================================ */


/* ============================================================
   7. FINDING A PLAN IN THE PLAN CACHE (after the query has run)
   ============================================================ */
-- Every batch that ran has a cached plan. Three DMVs joined together give you
-- text + plan: sys.dm_exec_cached_plans -> sys.dm_exec_sql_text -> sys.dm_exec_query_plan.
-- Trick used in this level: put a unique comment TAG such as /* L18a:demo */ into the query,
-- then search the cache for the text 'L18a:demo */'. The cached text is the WHOLE batch
-- (comments included), so the tagged query gets a batch of its own (note the GO right above it).
GO
SELECT /* L18a:demo */ OrderID, CustomerID, Amount FROM dbo.L18_Orders WHERE CustomerID = 42 AND Amount > 90000;   -- 23 rows
GO
SELECT cp.objtype, cp.usecounts, cp.size_in_bytes,
       LEFT(st.text, 80) AS QueryText,
       qp.query_plan                                    -- XML; clickable in SSMS
FROM sys.dm_exec_cached_plans cp
CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle)  st
CROSS APPLY sys.dm_exec_query_plan(cp.plan_handle) qp
WHERE st.text LIKE '%L18a:demo */%'
  AND st.text NOT LIKE '%dm_exec_cached_plans%';        -- exclude this search itself (its text also contains the tag)
GO
-- expect 1 row: objtype Adhoc, usecounts 1, QueryText starting with SELECT /* L18a:demo */

-- 7a. The simplest way to CONFIRM an operator: cast the XML to text and LIKE for the operator name
SELECT CASE WHEN CAST(qp.query_plan AS NVARCHAR(MAX)) LIKE '%PhysicalOp="Index Seek"%'   THEN 'yes' ELSE 'no' END AS HasIndexSeek,
       CASE WHEN CAST(qp.query_plan AS NVARCHAR(MAX)) LIKE '%Lookup="1"%'                THEN 'yes' ELSE 'no' END AS HasKeyLookup,
       CASE WHEN CAST(qp.query_plan AS NVARCHAR(MAX)) LIKE '%PhysicalOp="Hash Match"%'   THEN 'yes' ELSE 'no' END AS HasHashMatch
FROM sys.dm_exec_cached_plans cp
CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle)  st
CROSS APPLY sys.dm_exec_query_plan(cp.plan_handle) qp
WHERE st.text LIKE '%L18a:demo */%' AND st.text NOT LIKE '%dm_exec_cached_plans%';
GO
-- expect: yes, yes, no


/* ============================================================
   8. HELPER PROCS (reused by 02 and 03): one row per operator
   ============================================================ */
-- 8a. dbo.usp_L18_PlanOps @Tag : finds the cached plan whose text contains "@Tag */" and lists
--     its operators (RelOp nodes of the XML). Detail: a "trivial" plan (single table, one
--     obvious way) is auto-parameterised; the cache entry with our text is only a shell that
--     points to the real Prepared plan through ParameterizedPlanHandle, so we follow it.
CREATE OR ALTER PROCEDURE dbo.usp_L18_PlanOps @Tag NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @handle VARBINARY(64), @objtype NVARCHAR(20), @uses INT, @plan XML, @pointer VARCHAR(200);

    SELECT TOP (1) @handle = cp.plan_handle, @objtype = cp.objtype, @uses = cp.usecounts
    FROM sys.dm_exec_cached_plans cp
    CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) st
    WHERE st.text LIKE '%' + @Tag + ' */%'
      AND st.text NOT LIKE '%usp_L18_%' AND st.text NOT LIKE '%dm_exec_cached_plans%'   -- not our own tooling
    ORDER BY cp.usecounts DESC;

    IF @handle IS NULL BEGIN PRINT 'No cached plan found for tag ' + @Tag; RETURN; END;

    SELECT @plan = query_plan FROM sys.dm_exec_query_plan(@handle);
    WITH XMLNAMESPACES (DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan')
    SELECT @pointer = @plan.value('(//StmtSimple/@ParameterizedPlanHandle)[1]', 'varchar(200)');
    IF @pointer IS NOT NULL
        SELECT @plan = query_plan FROM sys.dm_exec_query_plan(CONVERT(VARBINARY(64), @pointer, 1));

    WITH XMLNAMESPACES (DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan')
    SELECT @Tag AS Tag, @objtype AS ObjType, @uses AS UseCounts,
           CASE WHEN @pointer IS NULL THEN 'direct' ELSE 'auto-parameterised' END AS PlanSource,
           r.value('@NodeId', 'int')                          AS NodeId,
           r.value('@PhysicalOp', 'varchar(60)')               AS PhysicalOp,
           r.value('@LogicalOp', 'varchar(60)')                AS LogicalOp,
           r.value('@EstimateRows', 'float')                   AS EstRows,
           r.value('@EstimatedTotalSubtreeCost', 'float')      AS SubtreeCost,
           r.value('@Parallel', 'bit')                         AS IsParallel,
           r.value('(IndexScan/Object/@Index)[1]', 'sysname')  AS IndexName
    FROM @plan.nodes('//RelOp') AS n(r)
    ORDER BY NodeId;
END
GO

-- 8b. dbo.usp_L18_EstVsActual @Tag : ESTIMATED vs ACTUAL rows per operator of the LAST execution.
--     Needs the database option LAST_QUERY_PLAN_STATS = ON (set in SETUP; SQL 2019+), which keeps
--     the last actual plan in the cache entry. sys.dm_exec_query_plan_stats returns it.
CREATE OR ALTER PROCEDURE dbo.usp_L18_EstVsActual @Tag NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @handle VARBINARY(64), @plan XML, @pointer VARCHAR(200);

    SELECT TOP (1) @handle = cp.plan_handle
    FROM sys.dm_exec_cached_plans cp
    CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) st
    WHERE st.text LIKE '%' + @Tag + ' */%'
      AND st.text NOT LIKE '%usp_L18_%' AND st.text NOT LIKE '%dm_exec_cached_plans%'   -- not our own tooling
    ORDER BY cp.usecounts DESC;

    IF @handle IS NULL BEGIN PRINT 'No cached plan found for tag ' + @Tag; RETURN; END;

    SELECT @plan = query_plan FROM sys.dm_exec_query_plan(@handle);
    WITH XMLNAMESPACES (DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan')
    SELECT @pointer = @plan.value('(//StmtSimple/@ParameterizedPlanHandle)[1]', 'varchar(200)');
    IF @pointer IS NOT NULL SET @handle = CONVERT(VARBINARY(64), @pointer, 1);

    SELECT @plan = query_plan FROM sys.dm_exec_query_plan_stats(@handle);   -- the LAST ACTUAL plan

    WITH XMLNAMESPACES (DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan')
    SELECT @Tag AS Tag,
           r.value('@NodeId', 'int')                                                        AS NodeId,
           r.value('@PhysicalOp', 'varchar(60)')                                             AS PhysicalOp,
           r.value('@EstimateRows', 'float')                                                 AS EstRowsPerExecution,
           r.value('sum(RunTimeInformation/RunTimeCountersPerThread/@ActualRows)', 'float')  AS ActualRowsTotal,
           r.value('sum(RunTimeInformation/RunTimeCountersPerThread/@ActualExecutions)', 'float') AS ActualExecutions,
           r.value('(IndexScan/Object/@Index)[1]', 'sysname')                                AS IndexName
    FROM @plan.nodes('//RelOp') AS n(r)
    ORDER BY NodeId;
END
GO

-- 8c. Use them on the tagged query from section 7 (a third helper for plan WARNINGS is added in file 03)
EXEC dbo.usp_L18_PlanOps 'L18a:demo';
-- expect 3 operators: Nested Loops (Inner Join, EstRows about 63), Index Seek on IX_L18_Orders_CustomerID (200),
--                     Clustered Index Seek on PK_L18_Orders (EstRows 0.3 = the residual Amount filter per lookup)
EXEC dbo.usp_L18_EstVsActual 'L18a:demo';
-- expect: Index Seek Est 200 / Actual 200 / Executions 1;
--         Clustered Index Seek Est 0.3 per execution / Actual 23 rows total / Executions 200 (one lookup per seek row)
--         Nested Loops Est 63 / Actual 23 -> the optimizer guessed 1 in 3 orders is above 90000; really 1 in 9.
GO


/* ============================================================
   9. CLEANUP
   ============================================================ */
ALTER DATABASE SCOPED CONFIGURATION SET LAST_QUERY_PLAN_STATS = OFF;   -- back to the default
GO
DROP PROCEDURE IF EXISTS dbo.usp_L18_PlanOps;
DROP PROCEDURE IF EXISTS dbo.usp_L18_EstVsActual;
DROP TABLE IF EXISTS dbo.L18_Orders;
DROP TABLE IF EXISTS dbo.L18_Customers;
GO
/* DONE. Next: 02_Practice_Operators.sql */
