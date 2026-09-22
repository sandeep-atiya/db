/* ============================================================
   LEVEL 18 - EXECUTION PLANS  |  Exercises.sql
   ------------------------------------------------------------
   Try each question in the "YOUR ANSWERS" area FIRST, then compare
   with SOLUTIONS. Q1-Q4 use the small SQLPractice tables, Q5-Q12
   use the 200,000-row helper table dbo.L18_Orders built below
   (dropped again at the end).
   ============================================================ */

USE SQLPractice;
GO
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

/* ---------- SETUP (same helper table as the practice files) ---------- */
DROP TABLE IF EXISTS dbo.L18_Orders;
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
GO

/* ------------------------------------------------------------
   QUESTIONS
   ------------------------------------------------------------
   Q1.  Show the ESTIMATED plan (as text) of
        SELECT * FROM dbo.Employees WHERE DepartmentID = 1;
        Which operator reads the table, and why not a seek?

   Q2.  Measure the logical reads of  SELECT * FROM dbo.Orders  and of
        SELECT * FROM dbo.Orders WHERE OrderID = 1005. Explain the numbers.

   Q3.  Get the ACTUAL plan of  SELECT COUNT(*) FROM dbo.OrderDetails  with T-SQL
        (not SSMS). Which SET option did you use and what extra do you get?

   Q4.  Force the join between dbo.Orders and dbo.Customers to use a Hash Match,
        a Merge Join and Nested Loops (three queries). Use SHOWPLAN_ALL to compare
        the TotalSubtreeCost of the three root rows.

   Q5.  On dbo.L18_Orders write a query that produces an Index Seek followed by a
        Key Lookup. Prove it with SHOWPLAN_TEXT and with SET STATISTICS IO.

   Q6.  Remove the Key Lookup of Q5 with a covering index; show the reads before/after.
        Drop the index afterwards.

   Q7.  Which query in the plan cache has the highest total logical reads against
        dbo.L18_Orders? Show its text and execution count (sys.dm_exec_query_stats).

   Q8.  Insert 5,000 rows for a NEW CustomerID 5000, then compare the estimated and
        actual rows of  SELECT COUNT(*) FROM dbo.L18_Orders WHERE CustomerID = 5000
        (hint: sys.dm_exec_query_plan_stats needs LAST_QUERY_PLAN_STATS ON).
        Fix it with UPDATE STATISTICS and show the new estimate. Delete the rows.

   Q9.  Run a query that filters dbo.L18_Orders on Amount, then list the missing
        index suggestion from the DMVs (columns + avg_user_impact). Write in a
        comment two reasons why you would NOT create it immediately.

   Q10. Write a query that produces a Parallelism (Gather Streams) operator and
        confirm it from the cached plan XML with LIKE. Then remove it with MAXDOP 1.

   Q11. Run  SELECT COUNT(*) FROM dbo.L18_Orders WHERE CustomerID = 7  and then the
        same with 8. Show from sys.dm_exec_cached_plans that ONE Prepared plan was
        reused (simple parameterisation).

   Q12. Query Store: list the 3 queries with the highest total duration in the last
        hour (query_id, executions, total duration in ms, text).
   ------------------------------------------------------------ */

-- YOUR ANSWERS HERE (write below, run, compare)










/* ============================================================
   SOLUTIONS
   ============================================================ */

-- Q1  (Employees has no index on DepartmentID and only 12 rows -> Clustered Index Scan on PK_Employees)
SET SHOWPLAN_TEXT ON;
GO
SELECT * FROM dbo.Employees WHERE DepartmentID = 1;
GO
SET SHOWPLAN_TEXT OFF;
GO
-- expect: |--Clustered Index Scan(OBJECT:([..].[dbo].[Employees].[PK_Employees]), WHERE:([DepartmentID]=(1)))

-- Q2  (both tiny: 19 rows fit in one leaf page under one root page)
SET STATISTICS IO ON;
SELECT * FROM dbo.Orders;                          -- logical reads 2 (root + the single leaf page)
SELECT * FROM dbo.Orders WHERE OrderID = 1005;     -- logical reads 2 (the seek walks the same 2 pages)
SET STATISTICS IO OFF;
GO
-- Lesson: on tiny tables scan = seek; plans only matter with real row counts.

-- Q3  (SET STATISTICS XML ON runs the query and adds the actual plan XML with ActualRows per operator)
SET STATISTICS XML ON;
GO
SELECT COUNT(*) AS Lines FROM dbo.OrderDetails;    -- 26
GO
SET STATISTICS XML OFF;
GO

-- Q4
SET SHOWPLAN_ALL ON;
GO
SELECT c.CustomerName, o.OrderID FROM dbo.Orders o JOIN dbo.Customers c ON c.CustomerID = o.CustomerID OPTION (HASH JOIN);
SELECT c.CustomerName, o.OrderID FROM dbo.Orders o JOIN dbo.Customers c ON c.CustomerID = o.CustomerID OPTION (MERGE JOIN);
SELECT c.CustomerName, o.OrderID FROM dbo.Orders o JOIN dbo.Customers c ON c.CustomerID = o.CustomerID OPTION (LOOP JOIN);
GO
SET SHOWPLAN_ALL OFF;
GO
-- expect: three root rows; on 19 x 8 rows all costs are tiny (hash 0.025, merge 0.024, loops 0.010); loops is cheapest here.

-- Q5  (Amount is not in IX_L18_Orders_CustomerID -> seek + lookup)
SET SHOWPLAN_TEXT ON;
GO
SELECT OrderID, Amount FROM dbo.L18_Orders WHERE CustomerID = 300;
GO
SET SHOWPLAN_TEXT OFF;
GO
-- expect: Nested Loops -> Index Seek (IX_L18_Orders_CustomerID) + Clustered Index Seek ... LOOKUP
SET STATISTICS IO ON;
SELECT OrderID, Amount FROM dbo.L18_Orders WHERE CustomerID = 300;     -- logical reads about 623 (200 lookups)
SET STATISTICS IO OFF;
GO

-- Q6
CREATE INDEX IX_L18_Orders_Cust_Amount ON dbo.L18_Orders (CustomerID) INCLUDE (Amount);
GO
SET STATISTICS IO ON;
SELECT OrderID, Amount FROM dbo.L18_Orders WHERE CustomerID = 300;     -- logical reads 4 (no lookups)
SET STATISTICS IO OFF;
GO
DROP INDEX IX_L18_Orders_Cust_Amount ON dbo.L18_Orders;
GO

-- Q7
SELECT TOP (1) qs.execution_count, qs.total_logical_reads, qs.last_logical_reads,
       SUBSTRING(st.text, qs.statement_start_offset / 2 + 1,
                 (CASE qs.statement_end_offset WHEN -1 THEN DATALENGTH(st.text) ELSE qs.statement_end_offset END
                  - qs.statement_start_offset) / 2 + 1) AS StatementText
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
WHERE st.text LIKE '%L18_Orders%' AND st.text NOT LIKE '%dm_exec_query_stats%'
ORDER BY qs.total_logical_reads DESC;
GO
-- expect: the Q5 lookup query (about 665 reads). The setup INSERT is gone from the DMV because CREATE INDEX
--         on the table invalidated its plan - stats live only as long as the plan is cached.

-- Q8  (LAST_QUERY_PLAN_STATS keeps the last actual plan; changing it also flushes this database's plan cache)
ALTER DATABASE SCOPED CONFIGURATION SET LAST_QUERY_PLAN_STATS = ON;
GO
INSERT INTO dbo.L18_Orders (OrderID, CustomerID, EmployeeID, OrderDate, Amount, Status)
SELECT 200000 + value, 5000, 101, '2025-12-31', 100, 'Completed' FROM GENERATE_SERIES(1, 5000);
GO
-- (COUNT + SUM(Amount) on purpose: a plain COUNT(*) would get a trivial, auto-parameterised plan
--  whose cached text no longer contains our tag.)
SELECT /* L18x:q8 */ COUNT(*) AS Cnt, SUM(Amount) AS Total FROM dbo.L18_Orders WHERE CustomerID = 5000;    -- 5000, 500000.00
GO
WITH XMLNAMESPACES (DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan')
SELECT r.value('@PhysicalOp', 'varchar(50)') AS PhysicalOp,
       r.value('@EstimateRows', 'float') AS EstRows,
       r.value('sum(RunTimeInformation/RunTimeCountersPerThread/@ActualRows)', 'float') AS ActualRows
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
CROSS APPLY sys.dm_exec_query_plan_stats(qs.plan_handle) ps
CROSS APPLY ps.query_plan.nodes('//RelOp[@PhysicalOp="Index Seek"]') n(r)
WHERE st.text LIKE '%L18x:q8 */%';
-- expect: Index Seek EstRows 5, ActualRows 5000 (statistics do not know customer 5000 yet)
GO
UPDATE STATISTICS dbo.L18_Orders IX_L18_Orders_CustomerID WITH FULLSCAN;
GO
SELECT /* L18x:q8fresh */ COUNT(*) AS Cnt, SUM(Amount) AS Total FROM dbo.L18_Orders WHERE CustomerID = 5000;   -- same result
GO
WITH XMLNAMESPACES (DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan')
SELECT r.value('@PhysicalOp', 'varchar(50)') AS PhysicalOp,
       r.value('@EstimateRows', 'float') AS EstRows,
       r.value('sum(RunTimeInformation/RunTimeCountersPerThread/@ActualRows)', 'float') AS ActualRows
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
CROSS APPLY sys.dm_exec_query_plan_stats(qs.plan_handle) ps
CROSS APPLY ps.query_plan.nodes('//RelOp[@PhysicalOp="Index Seek"]') n(r)
WHERE st.text LIKE '%L18x:q8fresh */%';
-- expect: EstRows 5000, ActualRows 5000
GO
DELETE FROM dbo.L18_Orders WHERE OrderID > 200000;
UPDATE STATISTICS dbo.L18_Orders WITH FULLSCAN;
ALTER DATABASE SCOPED CONFIGURATION SET LAST_QUERY_PLAN_STATS = OFF;
GO

-- Q9
SELECT OrderID FROM dbo.L18_Orders WHERE Amount = 777;     -- no index on Amount -> scan + suggestion
GO
SELECT mid.equality_columns, mid.inequality_columns, mid.included_columns, migs.user_seeks, migs.avg_user_impact
FROM sys.dm_db_missing_index_details mid
JOIN sys.dm_db_missing_index_groups mig       ON mig.index_handle = mid.index_handle
JOIN sys.dm_db_missing_index_group_stats migs ON migs.group_handle = mig.index_group_handle
WHERE mid.database_id = DB_ID() AND mid.object_id = OBJECT_ID('dbo.L18_Orders');
-- expect: equality_columns [Amount], avg_user_impact about 99
/* Reasons not to create it blindly: (1) user_seeks = 1 - the query may never run again;
   (2) every extra index slows INSERT/UPDATE/DELETE and the suggestion may duplicate or be
   covered by widening an existing index; (3) impact is per query, not per workload.          */
GO

-- Q10
SELECT TOP (3) OrderID FROM dbo.L18_Orders ORDER BY Filler, Amount /* L18x:q10 */;
GO
SELECT CASE WHEN CAST(qp.query_plan AS NVARCHAR(MAX)) LIKE '%PhysicalOp="Parallelism"%' THEN 'parallel' ELSE 'serial' END AS PlanType
FROM sys.dm_exec_cached_plans cp
CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) st
CROSS APPLY sys.dm_exec_query_plan(cp.plan_handle) qp
WHERE st.text LIKE '%L18x:q10%' AND st.text NOT LIKE '%dm_exec_cached_plans%';   -- parallel (with cost threshold 5)
GO
SELECT TOP (3) OrderID FROM dbo.L18_Orders ORDER BY Filler, Amount OPTION (MAXDOP 1) /* L18x:q10b */;
GO
SELECT CASE WHEN CAST(qp.query_plan AS NVARCHAR(MAX)) LIKE '%PhysicalOp="Parallelism"%' THEN 'parallel' ELSE 'serial' END AS PlanType
FROM sys.dm_exec_cached_plans cp
CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) st
CROSS APPLY sys.dm_exec_query_plan(cp.plan_handle) qp
WHERE st.text LIKE '%L18x:q10b%' AND st.text NOT LIKE '%dm_exec_cached_plans%';  -- serial
GO

-- Q11  (COUNT(*) keeps the output short; the plan is still trivial, so it is still auto-parameterised)
SELECT COUNT(*) AS Cnt FROM dbo.L18_Orders WHERE CustomerID = 7 /* L18x:q11 */;    -- 200
GO
SELECT COUNT(*) AS Cnt FROM dbo.L18_Orders WHERE CustomerID = 8 /* L18x:q11 */;    -- 200
GO
SELECT cp.objtype, cp.usecounts, LEFT(st.text, 80) AS QueryText
FROM sys.dm_exec_cached_plans cp CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) st
WHERE (st.text LIKE '%L18x:q11 */%' OR st.text LIKE '(@1 %L18_Orders%CustomerID]=@1%')
  AND st.text NOT LIKE '%dm_exec_cached_plans%'
ORDER BY cp.objtype;
-- expect: 2 Adhoc shells (usecounts 1) + 1 Prepared "(@1 tinyint)SELECT COUNT(*) [Cnt] FROM ... WHERE [CustomerID]=@1" (usecounts 2)
GO

-- Q12  (works when Query Store is ON for the database; returns 0 rows otherwise)
SELECT TOP (3) q.query_id, SUM(rs.count_executions) AS Executions,
       CAST(SUM(rs.avg_duration * rs.count_executions) / 1000 AS DECIMAL(12,1)) AS TotalDurationMs,
       LEFT(qt.query_sql_text, 60) AS QueryText
FROM sys.query_store_query q
JOIN sys.query_store_query_text qt    ON qt.query_text_id = q.query_text_id
JOIN sys.query_store_plan p           ON p.query_id = q.query_id
JOIN sys.query_store_runtime_stats rs ON rs.plan_id = p.plan_id
JOIN sys.query_store_runtime_stats_interval i ON i.runtime_stats_interval_id = rs.runtime_stats_interval_id
WHERE i.start_time >= DATEADD(HOUR, -1, SYSDATETIMEOFFSET())
GROUP BY q.query_id, qt.query_sql_text
ORDER BY TotalDurationMs DESC;
GO

/* ---------- CLEANUP ---------- */
DROP TABLE IF EXISTS dbo.L18_Orders;
GO
