/* ============================================================
   LEVEL 17 - INDEXES  |  02_Practice_Seek_Scan_Lookup.sql
   ------------------------------------------------------------
   Topics : SET STATISTICS IO and "logical reads", seeing the plan
            in T-SQL (SHOWPLAN_TEXT, STATISTICS XML) and in SSMS,
            Table Scan -> Clustered Index Scan -> Index Seek ->
            Key Lookup -> covered by INCLUDE (all MEASURED),
            seek vs scan on the same index (tipping point), the
            "secretly bad" Index Seek, non-SARGable predicates
            (YEAR(), LIKE '%x', implicit conversion, ISNULL),
            missing index DMVs, TOP / ORDER BY using an index
            to avoid a Sort.
   HOW TO PRACTICE: run block by block. Watch the PRINT label, then
   the "logical reads" number under it. Predict up or down first.
   Rebuilds dbo.L17_Orders (200,000 rows) as a HEAP; dropped at the end.
   ============================================================ */

USE SQLPractice;
GO
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
GO
DROP TABLE IF EXISTS dbo.L17_Orders;
GO
SELECT ISNULL(CAST(s.value AS INT), 0)                                    AS OrderID,
       s.value % 1000 + 1                                                  AS CustomerID,
       CASE WHEN s.value % 100 = 0 THEN NULL ELSE 101 + s.value % 12 END    AS EmployeeID,
       CAST(DATEADD(DAY, s.value % 1096, '2023-01-01') AS DATE)            AS OrderDate,
       CAST((s.value * 37) % 100000 + 100 AS DECIMAL(12,2))                AS Amount,
       CASE s.value % 20 WHEN 0 THEN 'Pending' WHEN 1 THEN 'Cancelled' ELSE 'Completed' END AS Status,
       CAST(s.value % 1000 + 1 AS VARCHAR(10))                             AS CustomerCode   -- CustomerID as text
INTO dbo.L17_Orders
FROM GENERATE_SERIES(1, 200000) AS s;
SELECT COUNT(*) AS Rows FROM dbo.L17_Orders;     -- 200000, and it is a HEAP (no index yet)
GO


/* ============================================================
   1. SET STATISTICS IO ON - the number that matters: LOGICAL READS
   ============================================================
   After each statement SQL Server prints one line per table:
     Table 'X'. Scan count 1, logical reads 1391, physical reads 0, read-ahead reads 0 ...
   logical reads  = 8 KB pages read from memory (buffer cache). STABLE and
                    comparable between runs -> THE tuning metric.
   physical reads = pages that had to come from disk first (depends on cache).
   Scan count     = how many times the object was accessed (seeks in a loop).
   Fewer logical reads = less CPU, less memory, less I/O, fewer locks.
   ============================================================ */
SET STATISTICS IO ON;
GO
PRINT '=== 1a. HEAP, no index: Table Scan reads every page ===';
SELECT COUNT(*) AS Orders, SUM(Amount) AS Total FROM dbo.L17_Orders WHERE CustomerID = 5;
-- expect ~1,260 logical reads (the whole table) to find 200 rows
GO
SET STATISTICS IO OFF;
GO


/* ============================================================
   2. SEEING THE PLAN
   ============================================================
   In SSMS : Ctrl+M  = Include ACTUAL execution plan (runs the query, shows real row counts)
             Ctrl+L  = Display ESTIMATED plan (does not run it)
             Read right-to-left, top-to-bottom. Look for: Table Scan, Clustered Index Scan,
             Index Seek, Key Lookup, Sort, Hash Match; hover for Estimated vs Actual rows;
             yellow triangle = warning (implicit conversion, spills); green text = missing index.
   In T-SQL: SET SHOWPLAN_TEXT ON  -> must be ALONE in its batch; the queries after it are
             NOT executed, only their plan text is returned, until SET SHOWPLAN_TEXT OFF.
             SET SHOWPLAN_ALL ON    -> same, more columns (EstimateRows, TotalSubtreeCost).
             SET STATISTICS XML ON  -> executes AND returns the actual plan as XML (one row per query).
   ============================================================ */

-- 2a. SHOWPLAN_TEXT: plan only, no execution
SET SHOWPLAN_TEXT ON;
GO
SELECT COUNT(*) AS Orders FROM dbo.L17_Orders WHERE CustomerID = 5;
-- expect the operator tree: Compute Scalar <- Stream Aggregate <- Table Scan(... WHERE CustomerID = 5)
GO
SET SHOWPLAN_TEXT OFF;
GO

-- 2b. STATISTICS XML: executes and adds the actual plan as an XML column (open it in SSMS = graphical plan)
SET STATISTICS XML ON;
GO
SELECT COUNT(*) AS Departments FROM dbo.Departments;     -- tiny table = short XML
GO
SET STATISTICS XML OFF;
GO


/* ============================================================
   3. THE PROGRESSION, MEASURED:
      Table Scan -> Clustered Index Scan -> Index Seek + Key Lookup -> covered
   ============================================================ */
SET STATISTICS IO ON;
GO
PRINT '=== 3a. HEAP: Table Scan ===';
SELECT COUNT(*) AS Orders, SUM(Amount) AS Total FROM dbo.L17_Orders WHERE CustomerID = 5;
-- expect ~1,260 reads
GO
SET STATISTICS IO OFF;
GO
ALTER TABLE dbo.L17_Orders ADD CONSTRAINT PK_L17_Orders PRIMARY KEY CLUSTERED (OrderID);
GO
SET STATISTICS IO ON;
GO
PRINT '=== 3b. clustered index on OrderID: Clustered Index Scan (the key does not help a CustomerID filter) ===';
SELECT COUNT(*) AS Orders, SUM(Amount) AS Total FROM dbo.L17_Orders WHERE CustomerID = 5;
-- expect the same ~1,260 reads - a scan is a scan, clustered or not
GO
SET STATISTICS IO OFF;
GO
CREATE NONCLUSTERED INDEX IX_L17_Orders_CustomerID ON dbo.L17_Orders (CustomerID);
GO
SET STATISTICS IO ON;
GO
PRINT '=== 3c. index on CustomerID: Index Seek (200 rows) + 200 Key Lookups for Amount ===';
SELECT COUNT(*) AS Orders, SUM(Amount) AS Total FROM dbo.L17_Orders WHERE CustomerID = 5;
-- expect ~620 reads: 2-3 for the seek, then ~3 per row to fetch Amount from the clustered index
GO
PRINT '=== 3d. same filter, but only columns the index has -> Index Seek alone ===';
SELECT COUNT(*) AS Orders, MAX(OrderID) AS LastOrderID FROM dbo.L17_Orders WHERE CustomerID = 5;
-- expect 2-3 reads (root -> leaf). OrderID is the clustered key, so it is in every NC index.
GO
SET STATISTICS IO OFF;
GO
CREATE NONCLUSTERED INDEX IX_L17_Orders_CustomerID_Amount ON dbo.L17_Orders (CustomerID) INCLUDE (Amount);
GO
SET STATISTICS IO ON;
GO
PRINT '=== 3e. covering index (INCLUDE Amount): no lookups ===';
SELECT COUNT(*) AS Orders, SUM(Amount) AS Total FROM dbo.L17_Orders WHERE CustomerID = 5;
-- expect 3 reads: from 1,260 to 3 for the same answer
GO
SET STATISTICS IO OFF;
GO
-- Proof of the operators (plan text only)
SET SHOWPLAN_TEXT ON;
GO
SELECT COUNT(*), SUM(Amount) FROM dbo.L17_Orders WITH (INDEX(IX_L17_Orders_CustomerID)) WHERE CustomerID = 5;
-- expect Nested Loops <- Index Seek(IX_L17_Orders_CustomerID) + Clustered Index Seek(PK_L17_Orders) = the Key Lookup
SELECT COUNT(*), SUM(Amount) FROM dbo.L17_Orders WHERE CustomerID = 5;
-- expect a single Index Seek(IX_L17_Orders_CustomerID_Amount)
GO
SET SHOWPLAN_TEXT OFF;
GO
DROP INDEX IX_L17_Orders_CustomerID_Amount ON dbo.L17_Orders;     -- keep only the non-covering one for section 4
GO


/* ============================================================
   4. SEEK vs SCAN ON THE SAME INDEX: selectivity and the TIPPING POINT
   ============================================================
   With the NON-covering index every matching row costs ~3 extra
   reads (Key Lookup). At some number of rows a full Clustered Index
   Scan (~1,390 reads) becomes cheaper, and the optimizer switches
   to it - even though the index "fits" the WHERE. Typically that
   happens somewhere between 0.1 % and 1 % of the table.
   ============================================================ */
SET STATISTICS IO ON;
GO
PRINT '=== 4a. CustomerID <= 1  (200 rows, 0.1%) : seek + lookups ===';
SELECT COUNT(*) AS Orders, SUM(Amount) AS Total FROM dbo.L17_Orders WHERE CustomerID <= 1;
-- expect ~620 reads
GO
PRINT '=== 4b. CustomerID <= 2  (400 rows, 0.2%) : still seek + lookups ===';
SELECT COUNT(*) AS Orders, SUM(Amount) AS Total FROM dbo.L17_Orders WHERE CustomerID <= 2;
-- expect ~1,240 reads (400 x 3): almost the cost of a full scan already
GO
PRINT '=== 4c. CustomerID <= 3  (600 rows, 0.3%) : the optimizer gives up on the index ===';
SELECT COUNT(*) AS Orders, SUM(Amount) AS Total FROM dbo.L17_Orders WHERE CustomerID <= 3;
-- expect ~1,260 reads (Clustered Index Scan) instead of ~1,850 for 600 lookups
GO
PRINT '=== 4d. CustomerID <= 500 (100,000 rows, 50%) : scan, obviously ===';
SELECT COUNT(*) AS Orders, SUM(Amount) AS Total FROM dbo.L17_Orders WHERE CustomerID <= 500;
-- expect ~1,260 reads again
GO
PRINT '=== 4e. THE SECRETLY BAD INDEX SEEK: force the index for the 50% query ===';
SELECT COUNT(*) AS Orders, SUM(Amount) AS Total
FROM dbo.L17_Orders WITH (INDEX(IX_L17_Orders_CustomerID))
WHERE CustomerID <= 500;
-- expect ~300,000 reads: an "Index Seek" in the plan, but 100,000 Key Lookups behind it.
-- Lesson: "Index Seek" is not automatically good - check the ROW COUNT flowing out of it.
GO
SET STATISTICS IO OFF;
GO


/* ============================================================
   5. NON-SARGABLE PREDICATES  (SARG = Search ARGument)
   ============================================================
   A predicate is SARGable when the COLUMN stands alone on one side:
   Col = x, Col > x, Col BETWEEN, Col LIKE 'abc%', Col IS NULL.
   Wrapping the column in a function / expression hides it from the
   index -> scan. Fix: move the function to the OTHER side.
   ============================================================ */
CREATE NONCLUSTERED INDEX IX_L17_Orders_OrderDate    ON dbo.L17_Orders (OrderDate);
CREATE NONCLUSTERED INDEX IX_L17_Orders_CustomerCode ON dbo.L17_Orders (CustomerCode);
CREATE NONCLUSTERED INDEX IX_L17_Orders_EmployeeID   ON dbo.L17_Orders (EmployeeID);
GO
SET STATISTICS IO ON;
GO
-- 5a. function on the column vs an open range
PRINT '=== 5a-1. YEAR(OrderDate) = 2024  -> index SCAN ===';
SELECT COUNT(*) AS Orders2024 FROM dbo.L17_Orders WHERE YEAR(OrderDate) = 2024;
-- expect ~320 reads (whole OrderDate index)
GO
PRINT '=== 5a-2. OrderDate >= 20240101 AND OrderDate < 20250101  -> index SEEK ===';
SELECT COUNT(*) AS Orders2024 FROM dbo.L17_Orders WHERE OrderDate >= '20240101' AND OrderDate < '20250101';
-- expect ~110 reads (only the 2024 part of the index), same 66,776 rows
GO

-- 5b. LIKE with a leading wildcard vs a prefix
PRINT '=== 5b-1. CustomerCode LIKE ''%5''  -> SCAN (every value must be inspected) ===';
SELECT COUNT(*) AS EndsWith5 FROM dbo.L17_Orders WHERE CustomerCode LIKE '%5';
-- expect ~420 reads (whole CustomerCode index) for 20,000 rows
GO
PRINT '=== 5b-2. CustomerCode LIKE ''5%''   -> SEEK on the range 5..6 ===';
SELECT COUNT(*) AS StartsWith5 FROM dbo.L17_Orders WHERE CustomerCode LIKE '5%';
-- expect ~50 reads for 22,200 rows (5, 50-59, 500-599)
GO

-- 5c. Implicit conversion: VARCHAR column compared with an INT literal.
--     INT has higher precedence, so the COLUMN is converted for every row -> scan
--     (plan shows CONVERT_IMPLICIT and a warning in SSMS).
PRINT '=== 5c-1. CustomerCode = 5  (varchar column, int literal) -> SCAN + convert ===';
SELECT COUNT(*) AS Orders FROM dbo.L17_Orders WHERE CustomerCode = 5;
-- expect ~420 reads
GO
PRINT '=== 5c-2. CustomerCode = ''5''  (same types) -> SEEK ===';
SELECT COUNT(*) AS Orders FROM dbo.L17_Orders WHERE CustomerCode = '5';
-- expect ~4 reads
GO
PRINT '=== 5c-3. the other way round is harmless: INT column = ''5'' converts the LITERAL only ===';
SELECT COUNT(*) AS Orders FROM dbo.L17_Orders WHERE CustomerID = '5';
-- expect 2-3 reads (seek). Still: match the types in your parameters (NVARCHAR params vs VARCHAR columns is the classic ORM bug).
GO

-- 5d. ISNULL / COALESCE around the column
PRINT '=== 5d-1. ISNULL(EmployeeID, 0) = 0  -> SCAN ===';
SELECT COUNT(*) AS OnlineOrders FROM dbo.L17_Orders WHERE ISNULL(EmployeeID, 0) = 0;
-- expect ~350 reads (whole EmployeeID index)
GO
PRINT '=== 5d-2. EmployeeID IS NULL  -> SEEK ===';
SELECT COUNT(*) AS OnlineOrders FROM dbo.L17_Orders WHERE EmployeeID IS NULL;
-- expect ~6 reads for the same 2,000 rows
GO
SET STATISTICS IO OFF;
GO
-- Other classics:  DATEDIFF(DAY, OrderDate, GETDATE()) < 30   -> OrderDate > DATEADD(DAY, -30, GETDATE())
--                  LEFT(Code, 2) = 'AB'                       -> Code LIKE 'AB%'
--                  Amount * 1.18 > 1000                       -> Amount > 1000 / 1.18
--                  UPPER(Name) = 'RAHUL'                      -> Name = 'Rahul' (case-insensitive collation)
--                  WHERE Col = @p OR @p IS NULL               -> OPTION (RECOMPILE) or dynamic SQL


/* ============================================================
   6. MISSING INDEX DMVs  (what SSMS shows in green, queryable)
   ============================================================
   When the optimizer wanted an index that does not exist it records
   the wish: sys.dm_db_missing_index_details (columns), _groups,
   _group_stats (how often, how much it would help). Cleared on restart.
   ============================================================ */
-- 6a. Run a query with no useful index (Status and Amount are not indexed)
SELECT COUNT(*) AS BigCancelled FROM dbo.L17_Orders WHERE Status = 'Cancelled' AND Amount > 90000;
GO
-- 6b. Read the wish list for this table
SELECT d.equality_columns, d.inequality_columns, d.included_columns,
       s.user_seeks AS TimesWanted, s.avg_user_impact AS PctImprovement,
       'CREATE INDEX IX_missing ON ' + d.statement + ' (' + ISNULL(d.equality_columns, '')
       + CASE WHEN d.inequality_columns IS NOT NULL THEN ', ' + d.inequality_columns ELSE '' END + ')'
       + ISNULL(' INCLUDE (' + d.included_columns + ')', '') AS SuggestedDDL
FROM sys.dm_db_missing_index_details d
JOIN sys.dm_db_missing_index_groups g ON g.index_handle = d.index_handle
JOIN sys.dm_db_missing_index_group_stats s ON s.group_handle = g.index_group_handle
WHERE d.database_id = DB_ID() AND d.object_id = OBJECT_ID('dbo.L17_Orders')
ORDER BY s.avg_user_impact DESC;
-- expect at least 1 row: equality [Status], inequality [Amount]
-- Treat it as a HINT: merge overlapping suggestions, do not create 20 indexes with huge INCLUDE lists.
GO


/* ============================================================
   7. TOP / ORDER BY: an index avoids the Sort
   ============================================================ */
SET STATISTICS IO ON;
GO
PRINT '=== 7a. TOP 10 newest orders, index on OrderDate exists: scan the index BACKWARD, stop after 10 ===';
SELECT TOP (10) OrderID, OrderDate FROM dbo.L17_Orders ORDER BY OrderDate DESC;
-- expect 2-3 reads, no Sort operator (10 rows dated 2025-12-31)
GO
PRINT '=== 7b. TOP 10 biggest amounts, NO index on Amount: full scan + Top N Sort of 200,000 rows ===';
SELECT TOP (10) OrderID, Amount FROM dbo.L17_Orders ORDER BY Amount DESC;
-- expect ~1,300 reads (Scan count > 1 = a parallel scan) plus CPU for the sort
GO
SET STATISTICS IO OFF;
GO
SET SHOWPLAN_TEXT ON;
GO
SELECT TOP (10) OrderID, OrderDate FROM dbo.L17_Orders ORDER BY OrderDate DESC;   -- Top <- Index Scan ORDERED BACKWARD
SELECT TOP (10) OrderID, Amount    FROM dbo.L17_Orders ORDER BY Amount DESC;      -- Top <- (Parallelism) <- Sort(TOP 10) <- Clustered Index Scan
GO
SET SHOWPLAN_TEXT OFF;
GO
CREATE NONCLUSTERED INDEX IX_L17_Orders_Amount ON dbo.L17_Orders (Amount);
GO
SET STATISTICS IO ON;
GO
PRINT '=== 7c. after CREATE INDEX on Amount ===';
SELECT TOP (10) OrderID, Amount FROM dbo.L17_Orders ORDER BY Amount DESC;
-- expect ~3 reads, no Sort
GO
SET STATISTICS IO OFF;
GO
-- Same idea: an index on (CustomerID, OrderDate) serves
--   WHERE CustomerID = 5 ORDER BY OrderDate   with no Sort at all.


/* ============================================================
   8. CLEANUP
   ============================================================ */
SET STATISTICS IO OFF;
SET STATISTICS XML OFF;
DROP TABLE IF EXISTS dbo.L17_Orders;
GO
SELECT name FROM sys.objects WHERE name LIKE '%L17%';   -- 0 rows
GO
/* DONE. Next: Exercises.sql */
