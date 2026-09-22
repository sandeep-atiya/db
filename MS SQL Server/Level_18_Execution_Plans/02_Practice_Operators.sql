/* ============================================================
   LEVEL 18 - EXECUTION PLANS  |  02_Practice_Operators.sql
   ------------------------------------------------------------
   Topics : every common plan operator, one by one, with a query that
            produces it and a proc that proves it from the cached plan:
            Table Scan, Clustered Index Scan, Index Scan, Index Seek,
            Key Lookup, RID Lookup, Sort, Hash Match (aggregate + join),
            Stream Aggregate, Nested Loops, Merge Join, Compute Scalar,
            Filter, Top, Parallelism (Gather Streams, cost threshold,
            MAXDOP), Table Spool (lazy + eager), join hints.

   HOW TO PRACTICE: run block by block, predict the operator first,
   then run the EXEC dbo.usp_L18_PlanOps line to check. In SSMS you
   can also press Ctrl+M before each query and look at the picture.
   ============================================================ */

USE SQLPractice;
GO
SET QUOTED_IDENTIFIER ON;      -- needed for the XML methods in the helper proc (sqlcmd default is OFF)
SET NOCOUNT ON;
GO


/* ============================================================
   0. SETUP - helper tables (same as file 01) + a HEAP copy + helper proc
   ============================================================ */
DROP TABLE IF EXISTS dbo.L18_OrdersHeap;
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
-- A HEAP = table without a clustered index (SELECT INTO creates one). Same 200,000 rows.
SELECT * INTO dbo.L18_OrdersHeap FROM dbo.L18_Orders;
GO
-- Helper from file 01 (explained there): lists the operators of the cached plan that contains @Tag.
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
    SELECT @Tag AS Tag, CASE WHEN @pointer IS NULL THEN 'direct' ELSE 'auto-parameterised' END AS PlanSource,
           r.value('@NodeId', 'int') AS NodeId,
           r.value('@PhysicalOp', 'varchar(60)') AS PhysicalOp, r.value('@LogicalOp', 'varchar(60)') AS LogicalOp,
           r.value('@EstimateRows', 'float') AS EstRows, r.value('@EstimatedTotalSubtreeCost', 'float') AS SubtreeCost,
           r.value('@Parallel', 'bit') AS IsParallel, r.value('(IndexScan/Object/@Index)[1]', 'sysname') AS IndexName
    FROM @plan.nodes('//RelOp') AS n(r) ORDER BY NodeId;
END
GO


/* ============================================================
   1. TABLE SCAN  (heap)  - reads every page of a table that has no clustered index
   ============================================================ */
-- EmployeeID has no index -> the only option is to read everything.
SELECT COUNT(*) AS Cnt FROM dbo.L18_OrdersHeap WHERE EmployeeID = 105 /* L18b:tablescan */;   -- 16667
GO
EXEC dbo.usp_L18_PlanOps 'L18b:tablescan';    -- expect: Table Scan (EstRows about 16700) -> Stream Aggregate -> Compute Scalar
GO


/* ============================================================
   2. CLUSTERED INDEX SCAN - same thing on a table WITH a clustered index (= the table itself)
   ============================================================ */
SELECT COUNT(*) AS Cnt FROM dbo.L18_Orders WHERE EmployeeID = 105 /* L18b:ciscan */;      -- 16667
GO
EXEC dbo.usp_L18_PlanOps 'L18b:ciscan';        -- expect: Clustered Index Scan on PK_L18_Orders (EstRows about 16700)
GO
-- Good or bad? A scan is BAD when you wanted a few rows (missing index). It is FINE when you
-- need most of the table anyway (reports, aggregates over everything).


/* ============================================================
   3. INDEX SCAN - reads a whole NONCLUSTERED index (narrower than the table = fewer pages)
   ============================================================ */
-- COUNT(*) needs no columns, so SQL Server scans the SMALLEST index it can find (about 350 pages
-- instead of about 3650 for the clustered index).
SELECT COUNT(*) AS Cnt FROM dbo.L18_Orders /* L18b:ixscan */;                                -- 200000
GO
EXEC dbo.usp_L18_PlanOps 'L18b:ixscan';        -- expect: Index Scan on IX_L18_Orders_CustomerID (EstRows 200000)
GO


/* ============================================================
   4. INDEX SEEK - jumps straight to the matching range using the B-tree
   ============================================================ */
-- The index on CustomerID contains CustomerID + OrderID (clustering key is always carried),
-- so this query is fully "covered": seek only, no lookup.
SELECT OrderID, CustomerID FROM dbo.L18_Orders WHERE CustomerID = 42 /* L18b:seek */;       -- 200 rows
GO
EXEC dbo.usp_L18_PlanOps 'L18b:seek';          -- expect: exactly ONE operator, Index Seek on IX_L18_Orders_CustomerID (EstRows 200)
GO
-- (PlanSource says auto-parameterised: a one-table, one-index query gets a "trivial plan".)


/* ============================================================
   5. KEY LOOKUP - the seek found the rows, but a column is missing from the index
   ============================================================ */
-- Amount is not in IX_L18_Orders_CustomerID, so for EACH of the 200 rows SQL Server jumps to the
-- clustered index to fetch it. 200 extra seeks = 200 x 3 page reads.
SET STATISTICS IO ON;
SELECT OrderID, CustomerID, Amount FROM dbo.L18_Orders WHERE CustomerID = 42 /* L18b:lookup */;
SET STATISTICS IO OFF;
GO
-- expect: logical reads about 623 (2 for the seek + about 3 per lookup x 200)
EXEC dbo.usp_L18_PlanOps 'L18b:lookup';
-- expect: Nested Loops -> Index Seek (200) + Clustered Index Seek (LogicalOp Clustered Index Seek, EstRows 1 = per execution)
--         In SSMS the second one is drawn as "Key Lookup (Clustered)".
GO
-- FIX: make the index COVERING with INCLUDE. Same query -> seek only, 3 reads instead of 623.
CREATE INDEX IX_L18_Orders_CustomerID_Covering ON dbo.L18_Orders (CustomerID) INCLUDE (Amount);
GO
SET STATISTICS IO ON;
SELECT OrderID, CustomerID, Amount FROM dbo.L18_Orders WHERE CustomerID = 42 /* L18b:covered */;
SET STATISTICS IO OFF;
GO
EXEC dbo.usp_L18_PlanOps 'L18b:covered';       -- expect: one Index Seek on IX_L18_Orders_CustomerID_Covering; reads 3 (root + 1 level + leaf)
GO
DROP INDEX IX_L18_Orders_CustomerID_Covering ON dbo.L18_Orders;   -- remove again so later demos behave the same
GO
-- Rule of thumb: a Key Lookup for a FEW rows is fine. Thousands of lookups per query = add INCLUDE columns.


/* ============================================================
   6. RID LOOKUP - the same problem on a HEAP (no clustered key -> uses the Row ID)
   ============================================================ */
CREATE INDEX IX_L18_OrdersHeap_CustomerID ON dbo.L18_OrdersHeap (CustomerID);
GO
SELECT OrderID, CustomerID, Amount FROM dbo.L18_OrdersHeap WHERE CustomerID = 42 /* L18b:rid */;   -- 200 rows
GO
EXEC dbo.usp_L18_PlanOps 'L18b:rid';           -- expect: Nested Loops -> Index Seek + RID Lookup
GO
DROP INDEX IX_L18_OrdersHeap_CustomerID ON dbo.L18_OrdersHeap;   -- back to a bare heap for section 11
GO


/* ============================================================
   7. SORT - ORDER BY (or DISTINCT / merge join input) with no index in that order
   ============================================================ */
SELECT OrderID, Amount FROM dbo.L18_Orders WHERE CustomerID = 42 ORDER BY Amount /* L18b:sort */;  -- 200 rows, cheapest first
GO
EXEC dbo.usp_L18_PlanOps 'L18b:sort';          -- expect: Sort on top of the seek + lookup
GO
-- Sorts need memory (a memory grant). Big sorts with a wrong estimate SPILL to tempdb (file 03).


/* ============================================================
   8. HASH MATCH (Aggregate) vs STREAM AGGREGATE
   ============================================================ */
-- 8a. GROUP BY on a column WITHOUT an index: rows arrive in random order -> build a hash table
--     keyed by EmployeeID and count into it. Needs memory, output order is random.
SELECT EmployeeID, COUNT(*) AS Orders FROM dbo.L18_Orders GROUP BY EmployeeID /* L18b:hashagg */;   -- 12 rows
GO
EXEC dbo.usp_L18_PlanOps 'L18b:hashagg';       -- expect: Clustered Index Scan -> Hash Match (LogicalOp Aggregate)
GO
-- 8b. GROUP BY on an INDEXED column: the index delivers rows already sorted by Status, so the
--     engine just counts each run of equal values (Stream Aggregate). No memory, no hashing.
SELECT Status, COUNT(*) AS Orders FROM dbo.L18_Orders GROUP BY Status /* L18b:streamagg */;        -- 3 rows
GO
EXEC dbo.usp_L18_PlanOps 'L18b:streamagg';     -- expect: Index Scan on IX_L18_Orders_Status -> Stream Aggregate
GO


/* ============================================================
   9. NESTED LOOPS - for each row of the OUTER (top) input, seek the INNER (bottom) input
   ============================================================ */
-- Best when the outer side is SMALL and the inner side has an index on the join column.
SELECT c.CustomerName, COUNT(*) AS Orders
FROM dbo.L18_Customers c
JOIN dbo.L18_Orders o ON o.CustomerID = c.CustomerID
WHERE c.CustomerID = 7
GROUP BY c.CustomerName /* L18b:loops */;                                                       -- Customer 7, 200
GO
EXEC dbo.usp_L18_PlanOps 'L18b:loops';         -- expect: Nested Loops with Clustered Index Seek (customers, 1 row) and Index Seek (orders, 200)
GO


/* ============================================================
   10. MERGE JOIN - both inputs SORTED on the join key, read them side by side like a zip
   ============================================================ */
-- Customers are sorted by CustomerID (clustered PK); orders are sorted by CustomerID (index).
-- The optimizer first counts orders per customer with a Stream Aggregate, then zips the two
-- sorted streams. Cheap and no memory - but only when both inputs are already ordered.
SELECT c.City, SUM(x.Orders) AS Orders
FROM dbo.L18_Customers c
JOIN (SELECT CustomerID, COUNT(*) AS Orders FROM dbo.L18_Orders GROUP BY CustomerID) x ON x.CustomerID = c.CustomerID
GROUP BY c.City /* L18b:merge */;                                                                -- 5 cities, 40000 each
GO
EXEC dbo.usp_L18_PlanOps 'L18b:merge';         -- expect: Merge Join (Inner Join) between Stream Aggregate/Index Scan and Clustered Index Scan
GO


/* ============================================================
   11. HASH MATCH (Join) - build a hash table from the SMALLER input, probe with the bigger one
   ============================================================ */
-- 200 Pune customers (no index on City) meet about 2,900 orders filtered on EmployeeID and Amount
-- (no index on either). Nothing to seek, nothing sorted on CustomerID -> hash: build a hash table
-- on the small input (customers), probe it with the big one (orders). Needs memory for the build.
SELECT c.CustomerName, o.OrderID, o.Amount
FROM dbo.L18_Customers c
JOIN dbo.L18_Orders o ON o.CustomerID = c.CustomerID
WHERE c.City = 'Pune' AND o.EmployeeID = 105 AND o.Amount > 95000 /* L18b:hashjoin */;     -- about 170 rows
GO
EXEC dbo.usp_L18_PlanOps 'L18b:hashjoin';      -- expect: Hash Match (Inner Join): Clustered Index Scan customers (EstRows 200, build side)
GO                                             --         + Clustered Index Scan orders (EstRows about 2900, probe side)
/* WHEN DOES THE OPTIMIZER PICK WHICH JOIN?
   Nested Loops : small outer input + index on the inner join column (OLTP lookups, "give me this customer's orders")
   Merge Join   : both inputs already sorted on the join key (or cheap to sort), medium/large inputs
   Hash Match   : large unsorted inputs, no useful index (reports, data warehouse joins)          */


/* ============================================================
   12. JOIN HINTS - force each physical join (FOR LEARNING ONLY, never in production code)
   ============================================================ */
-- Same query three times. Compare the SubtreeCost of the root operator: the hint you force
-- is almost always more expensive than the optimizer's own choice.
SELECT COUNT(*) AS PuneOrders FROM dbo.L18_Customers c JOIN dbo.L18_Orders o ON o.CustomerID = c.CustomerID
WHERE c.City = 'Pune' OPTION (HASH JOIN)  /* L18b:hint_hash */;     -- 40000
GO
SELECT COUNT(*) AS PuneOrders FROM dbo.L18_Customers c JOIN dbo.L18_Orders o ON o.CustomerID = c.CustomerID
WHERE c.City = 'Pune' OPTION (LOOP JOIN)  /* L18b:hint_loop */;     -- 40000
GO
SELECT COUNT(*) AS PuneOrders FROM dbo.L18_Customers c JOIN dbo.L18_Orders o ON o.CustomerID = c.CustomerID
WHERE c.City = 'Pune' OPTION (MERGE JOIN) /* L18b:hint_merge */;    -- 40000
GO
SELECT COUNT(*) AS PuneOrders FROM dbo.L18_Customers c JOIN dbo.L18_Orders o ON o.CustomerID = c.CustomerID
WHERE c.City = 'Pune' /* L18b:hint_none */;                         -- 40000, optimizer's own choice
GO
EXEC dbo.usp_L18_PlanOps 'L18b:hint_hash';     -- expect: Hash Match (Inner Join), root cost about 0.632
EXEC dbo.usp_L18_PlanOps 'L18b:hint_loop';     -- expect: Nested Loops (Inner Join), root cost about 0.748 (200 seeks x 200 rows)
EXEC dbo.usp_L18_PlanOps 'L18b:hint_merge';    -- expect: Merge Join (Inner Join), root cost about 0.616
EXEC dbo.usp_L18_PlanOps 'L18b:hint_none';     -- expect: the optimizer picked Merge Join by itself (same 0.616 - the cheapest)
GO


/* ============================================================
   13. COMPUTE SCALAR and FILTER
   ============================================================ */
-- 13a. Compute Scalar = calculates an expression per row (Amount * 1.18). Usually near-zero cost.
SELECT OrderID, Amount, Amount * 1.18 AS AmountWithGst FROM dbo.L18_Orders WHERE OrderID <= 5 /* L18b:compute */;  -- 5 rows
GO
EXEC dbo.usp_L18_PlanOps 'L18b:compute';       -- expect: Clustered Index Seek -> Compute Scalar
GO
-- 13b. Filter = a WHERE that could not be pushed into the scan/seek, typically HAVING (after the aggregate).
SELECT EmployeeID, COUNT(*) AS Orders FROM dbo.L18_Orders GROUP BY EmployeeID HAVING COUNT(*) > 16666 /* L18b:filter */;  -- 8 rows (the employees with 16667)
GO
EXEC dbo.usp_L18_PlanOps 'L18b:filter';        -- expect: ... -> Hash Match (Aggregate) -> Filter
GO


/* ============================================================
   14. TOP  (and TOP N Sort)
   ============================================================ */
-- 14a. TOP without ORDER BY: a Top operator simply stops the scan after 10 rows (any 10!).
SELECT TOP (10) OrderID, Amount FROM dbo.L18_Orders /* L18b:top */;
GO
EXEC dbo.usp_L18_PlanOps 'L18b:top';           -- expect: Index Scan -> Top (EstRows 10)
GO
-- 14b. TOP with ORDER BY on a non-indexed column: Sort with LogicalOp "TopN Sort" (keeps only 5 in memory).
SELECT TOP (5) OrderID, Amount FROM dbo.L18_Orders WHERE CustomerID = 42 ORDER BY Amount DESC /* L18b:topn */;
GO
EXEC dbo.usp_L18_PlanOps 'L18b:topn';          -- expect: PhysicalOp Sort, LogicalOp TopN Sort
GO


/* ============================================================
   15. PARALLELISM - Gather Streams, cost threshold, MAXDOP
   ============================================================ */
-- A plan goes parallel when its estimated cost is above 'cost threshold for parallelism'
-- (default 5 - most DBAs raise it to 25-50) and 'max degree of parallelism' allows > 1 thread.
SELECT name, value_in_use FROM sys.configurations
WHERE name IN ('cost threshold for parallelism', 'max degree of parallelism');
GO
-- Sorting 200,000 wide rows is expensive enough (cost about 5.5) to cross the default threshold of 5.
SELECT TOP (5) OrderID FROM dbo.L18_Orders ORDER BY Filler, Amount /* L18b:parallel */;
GO
EXEC dbo.usp_L18_PlanOps 'L18b:parallel';
-- expect (threshold 5): Top -> Parallelism (Gather Streams) -> Sort (TopN, IsParallel 1) -> Clustered Index Scan (IsParallel 1)
-- If your server uses a higher threshold you will see no Parallelism operator - that is the threshold working.
GO
-- MAXDOP 1 forces a serial plan for this query only (useful when parallelism itself is the problem: CXPACKET waits).
SELECT TOP (5) OrderID FROM dbo.L18_Orders ORDER BY Filler, Amount OPTION (MAXDOP 1) /* L18b:serial */;
GO
EXEC dbo.usp_L18_PlanOps 'L18b:serial';        -- expect: no Parallelism operator, IsParallel 0 everywhere
GO


/* ============================================================
   16. TABLE SPOOL - a temporary copy of rows in tempdb that the plan reads more than once
   ============================================================ */
-- 16a. LAZY spool: a window aggregate without ORDER BY. Rows of one CustomerID are stored once,
--      read once to compute SUM, and read again to attach the SUM to every row.
SELECT OrderID, Amount, SUM(Amount) OVER (PARTITION BY CustomerID) AS CustomerTotal
FROM dbo.L18_Orders WHERE CustomerID = 1 /* L18b:lazyspool */;                                   -- 200 rows, same total on each
GO
EXEC dbo.usp_L18_PlanOps 'L18b:lazyspool';     -- expect: Segment -> Table Spool (Lazy Spool) read by two branches of a Nested Loops
GO
-- 16b. EAGER spool ("Halloween protection"): we UPDATE the very column the seek uses. SQL Server
--      first copies all matching rows (eager = all at once), then updates, so a moved row is not seen twice.
BEGIN TRAN;
UPDATE dbo.L18_Orders SET CustomerID = CustomerID + 1 WHERE CustomerID = 5 /* L18b:eagerspool */;   -- 200 rows
ROLLBACK;                                                                                           -- data unchanged
GO
EXEC dbo.usp_L18_PlanOps 'L18b:eagerspool';    -- expect: Index Seek -> Table Spool (Eager Spool) -> ... -> Clustered Index Update
GO
-- Spools are usually a sign that the optimizer had to protect itself or reuse rows; many
-- spools with huge row counts = look for a better index or rewrite.


/* ============================================================
   17. CLEANUP
   ============================================================ */
DROP PROCEDURE IF EXISTS dbo.usp_L18_PlanOps;
DROP TABLE IF EXISTS dbo.L18_OrdersHeap;
DROP TABLE IF EXISTS dbo.L18_Orders;
DROP TABLE IF EXISTS dbo.L18_Customers;
GO
/* DONE. Next: 03_Practice_Cardinality_Cache_QueryStore.sql */
