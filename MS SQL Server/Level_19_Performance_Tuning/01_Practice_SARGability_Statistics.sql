/* ============================================================
   LEVEL 19 - PERFORMANCE TUNING  |  01_Practice_SARGability_Statistics.sql
   ------------------------------------------------------------
   Topics : SARGability rules measured with logical reads (function on
            column, arithmetic, leading wildcard, implicit conversion,
            ISNULL/COALESCE, OR, NOT IN / <>, date truncation, computed
            persisted column as a fix); statistics (histogram, density,
            sys.stats, DBCC SHOW_STATISTICS, AUTO_CREATE/UPDATE, when they
            go stale, UPDATE STATISTICS, sp_updatestats, a bad estimate
            after a big insert); query-writing tips (SELECT *, EXISTS vs IN
            vs JOIN, DISTINCT abuse, ORDER BY, TOP without ORDER BY,
            unnecessary subqueries, set-based vs loop).

   HOW TO PRACTICE: run block by block, predict the output first.
   Every "before/after" pair prints logical reads (Messages tab in SSMS).
   Helper table dbo.L19_Orders (200,000 rows, SKEWED: CustomerID 1 owns
   40% of the rows) is created here and dropped in CLEANUP.
   ============================================================ */

USE SQLPractice;
GO
SET QUOTED_IDENTIFIER ON;      -- XML methods in section 11 need it (sqlcmd default is OFF)
SET NOCOUNT ON;
GO


/* ============================================================
   0. SETUP - a 200,000-row orders table with a "whale" customer
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
    RefNo      VARCHAR(20)   NOT NULL,       -- digits stored as text, e.g. '12345'
    Filler     CHAR(100)     NOT NULL CONSTRAINT DF_L19_Orders_Filler DEFAULT ('x')
);
INSERT INTO dbo.L19_Orders (OrderID, CustomerID, EmployeeID, OrderDate, Amount, Status, RefNo)
SELECT value,
       CASE WHEN value % 5 < 2 THEN 1 ELSE 2 + (value % 999) END,      -- 40% customer 1, rest spread over 2..1000 (about 120 each)
       CASE WHEN value % 20 = 0 THEN NULL ELSE 101 + value % 12 END,   -- 5% online orders without salesperson
       DATEADD(MINUTE, value % 1440, DATEADD(DAY, value % 1096, '2023-01-01')),   -- 2023..2025 with a time part
       100 + (value * 7919) % 99900,
       CASE value % 10 WHEN 0 THEN 'Cancelled' WHEN 1 THEN 'Pending' ELSE 'Completed' END,
       CAST(value AS VARCHAR(20))
FROM GENERATE_SERIES(1, 200000);                                        -- SQL 2022+
CREATE INDEX IX_L19_Orders_CustomerID ON dbo.L19_Orders (CustomerID);
CREATE INDEX IX_L19_Orders_OrderDate  ON dbo.L19_Orders (OrderDate) INCLUDE (Amount);
CREATE INDEX IX_L19_Orders_Amount     ON dbo.L19_Orders (Amount);
CREATE INDEX IX_L19_Orders_Status     ON dbo.L19_Orders (Status);
CREATE INDEX IX_L19_Orders_RefNo      ON dbo.L19_Orders (RefNo);
CREATE INDEX IX_L19_Orders_EmployeeID ON dbo.L19_Orders (EmployeeID);
GO
SELECT COUNT(*) AS Rows_, SUM(IIF(CustomerID = 1, 1, 0)) AS Customer1Rows, COUNT(DISTINCT CustomerID) AS Customers
FROM dbo.L19_Orders;                                                    -- 200000, 80000, 1000
GO


/* ============================================================
   1. SARGABLE = "Search ARGument able": the predicate can use an index SEEK
   ============================================================
   Rule: keep the COLUMN alone on one side of the operator. Anything wrapped around
   the column (function, arithmetic, conversion, ISNULL) hides its value from the
   index, so SQL Server must read every row and evaluate the expression = SCAN.
   We measure with logical reads: the index on OrderDate has about 624 pages,
   the clustered index about 3,900. Fewer reads = less work.
   ============================================================ */
SET STATISTICS IO ON;
GO

-- 2. FUNCTION ON THE COLUMN
SELECT COUNT(*) AS Orders2024, SUM(Amount) AS Total FROM dbo.L19_Orders WHERE YEAR(OrderDate) = 2024;             -- 66776, scan: about 624 reads
SELECT COUNT(*) AS Orders2024, SUM(Amount) AS Total FROM dbo.L19_Orders
WHERE OrderDate >= '2024-01-01' AND OrderDate < '2025-01-01';                                                    -- same numbers, seek: about 211 reads
GO

-- 3. ARITHMETIC ON THE COLUMN: move the maths to the other side
SELECT COUNT(*) AS BigOrders FROM dbo.L19_Orders WHERE Amount * 1.1 > 109000;      -- 1819, scan of the Amount index: about 474 reads
SELECT COUNT(*) AS BigOrders FROM dbo.L19_Orders WHERE Amount > 109000 / 1.1;      -- 1819, seek: 8 reads
GO

-- 4. LEADING WILDCARD: LIKE '%x' cannot use the B-tree (it is sorted by the FIRST characters)
SELECT COUNT(*) AS EndsWith999   FROM dbo.L19_Orders WHERE RefNo LIKE '%999';      -- 200, scan: about 485 reads
SELECT COUNT(*) AS StartsWith1999 FROM dbo.L19_Orders WHERE RefNo LIKE '1999%';     -- 111, seek: 4 reads
GO

-- 5. IMPLICIT CONVERSION on the column side (data type precedence: NVARCHAR > VARCHAR, INT > VARCHAR)
SELECT COUNT(*) AS Pending FROM dbo.L19_Orders WHERE Status = N'Pending';           -- 20000, column converted to NVARCHAR -> scan: about 568 reads
SELECT COUNT(*) AS Pending FROM dbo.L19_Orders WHERE Status = 'Pending';            -- 20000, seek: about 56 reads
GO
SELECT OrderID, Amount FROM dbo.L19_Orders WHERE RefNo = 12345;      -- INT literal: every RefNo converted to INT -> scan, about 959 reads (and a conversion error if any RefNo were not numeric!)
SELECT OrderID, Amount FROM dbo.L19_Orders WHERE RefNo = '12345';    -- seek: 6 reads
GO
-- Same trap from application code: a parameter declared NVARCHAR (default for .NET strings) against a VARCHAR column.

-- 6. ISNULL / COALESCE on the column: rewrite as a plain comparison (+ IS NULL only when needed)
SELECT COUNT(*) AS Emp105 FROM dbo.L19_Orders WHERE ISNULL(EmployeeID, 0) = 105;   -- 13334, scan: about 349 reads
SELECT COUNT(*) AS Emp105 FROM dbo.L19_Orders WHERE EmployeeID = 105;              -- 13334, seek: about 26 reads
-- ISNULL(col, 0) = 0  means  col = 0 OR col IS NULL  -> write exactly that.
GO

-- 7. OR ACROSS TWO COLUMNS
-- 7a. Both columns indexed: the optimizer can seek both and union the results ("index union") - fine here.
SELECT COUNT(*) AS Cnt FROM dbo.L19_Orders WHERE CustomerID = 500 OR EmployeeID = 105;                 -- 13454, 2 seeks: about 28 reads
GO
-- 7b. The real OR problem is the "catch-all" search screen: (@p IS NULL OR col = @p). One plan must
--     work for NULL (everything) and for a value -> SQL Server plays safe and SCANS.
DECLARE @c INT = 500;
SELECT COUNT(*) AS Cnt FROM dbo.L19_Orders WHERE (@c IS NULL OR CustomerID = @c);                       -- 120, scan: about 349 reads
SELECT COUNT(*) AS Cnt FROM dbo.L19_Orders WHERE (@c IS NULL OR CustomerID = @c) OPTION (RECOMPILE);    -- 120, seek: 2 reads (plan built for THIS value)
GO
-- 7c. Textbook rewrite OR -> UNION ALL. Measure it: here it is WORSE (about 380 reads) because the
--     second branch must exclude the first. Rewrite only when the plan shows a scan; always measure.
SELECT COUNT(*) AS Cnt FROM (SELECT OrderID FROM dbo.L19_Orders WHERE CustomerID = 500
                             UNION ALL
                             SELECT OrderID FROM dbo.L19_Orders WHERE EmployeeID = 105 AND CustomerID <> 500) x;   -- 13454
GO

-- 8. NOT IN / <>: the optimizer turns "<> 'Completed'" into two ranges (< and >) on this 3-value column,
--    so all three forms cost the same (about 117 reads). The cost of <> is usually that it RETURNS most of
--    the table; when it does, a scan is the right plan anyway. (NOT IN with NULLs = wrong results, Level 09.)
SELECT COUNT(*) AS NotCompleted FROM dbo.L19_Orders WHERE Status <> 'Completed';                 -- 40000
SELECT COUNT(*) AS NotCompleted FROM dbo.L19_Orders WHERE Status IN ('Pending', 'Cancelled');    -- 40000
SELECT COUNT(*) AS NotCompleted FROM dbo.L19_Orders WHERE Status NOT IN ('Completed');           -- 40000
GO

-- 9. DATE TRUNCATION: CAST(datetime AS DATE) = x is the ONE exception the optimizer can rewrite into a
--    range seek (4 reads). CONVERT to a string is not. The explicit range is always safe and clear.
SELECT COUNT(*) AS OnJune1 FROM dbo.L19_Orders WHERE CAST(OrderDate AS DATE) = '2024-06-01';               -- 183, 4 reads (special case)
SELECT COUNT(*) AS OnJune1 FROM dbo.L19_Orders WHERE OrderDate >= '2024-06-01' AND OrderDate < '2024-06-02'; -- 183, 4 reads
SELECT COUNT(*) AS OnJune1 FROM dbo.L19_Orders WHERE CONVERT(VARCHAR(10), OrderDate, 120) = '2024-06-01';    -- 183, scan: about 624 reads
GO

-- 10. FIX FOR A FUNCTION YOU CANNOT REMOVE: a PERSISTED computed column with an index.
--     The optimizer matches the expression YEAR(OrderDate) to the computed column automatically.
SET STATISTICS IO OFF;
ALTER TABLE dbo.L19_Orders ADD OrderYear AS YEAR(OrderDate) PERSISTED;
CREATE INDEX IX_L19_Orders_OrderYear ON dbo.L19_Orders (OrderYear);
SET STATISTICS IO ON;
GO
SELECT COUNT(*) AS Orders2024 FROM dbo.L19_Orders WHERE YEAR(OrderDate) = 2024;    -- 66788, now a seek on IX_L19_Orders_OrderYear: about 119 reads
SELECT COUNT(*) AS Orders2024 FROM dbo.L19_Orders WHERE OrderYear = 2024;          -- same
GO
SET STATISTICS IO OFF;
GO


/* ============================================================
   11. STATISTICS - the numbers behind every estimate
   ============================================================
   A statistics object = a HISTOGRAM (up to 200 steps: value ranges with row counts) + a
   DENSITY vector (1 / number of distinct values) for the leading column(s) of an index or
   for a column the optimizer needed (auto-created, name _WA_Sys_...).
   ============================================================ */
-- 11a. Which statistics exist and how fresh are they? (modification_counter = changes since last update)
SELECT s.name, s.auto_created, sp.rows, sp.rows_sampled, sp.steps, sp.modification_counter, sp.last_updated
FROM sys.stats s
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) sp
WHERE s.object_id = OBJECT_ID('dbo.L19_Orders')
ORDER BY s.stats_id;                                       -- one row per index, rows 200000, modification_counter 0
GO
-- 11b. Read one: header (rows, sampled, steps), density (1/1000 = 0.001 for CustomerID), histogram.
DBCC SHOW_STATISTICS ('dbo.L19_Orders', IX_L19_Orders_CustomerID) WITH STAT_HEADER;
DBCC SHOW_STATISTICS ('dbo.L19_Orders', IX_L19_Orders_CustomerID) WITH DENSITY_VECTOR;
DBCC SHOW_STATISTICS ('dbo.L19_Orders', IX_L19_Orders_CustomerID) WITH HISTOGRAM;
GO
/* HISTOGRAM columns:  RANGE_HI_KEY = upper value of the step, EQ_ROWS = rows equal to that value,
   RANGE_ROWS = rows strictly between this step and the previous one, DISTINCT_RANGE_ROWS,
   AVG_RANGE_ROWS = RANGE_ROWS / DISTINCT_RANGE_ROWS (used for values inside the range).
   Look for RANGE_HI_KEY 1: EQ_ROWS 80000 - the histogram KNOWS customer 1 is the whale.           */

-- 11c. Database settings: create missing stats automatically, update stale ones automatically (sync or async)
SELECT name, is_auto_create_stats_on, is_auto_update_stats_on, is_auto_update_stats_async_on
FROM sys.databases WHERE name = DB_NAME();                 -- 1, 1, 0 (defaults)
GO
/* WHEN DO STATISTICS GO STALE? Auto-update is triggered at the NEXT compile once the modification
   counter passes a threshold:  old rule (<= 2014 / TF 2371 off) = 20% of rows + 500;
   new rule (2016+, compat 130+) = SQRT(1000 * rows)  ->  200,000 rows: about 14,142 changes.
   Below the threshold the optimizer keeps using the old histogram -> new values are "unknown".          */

-- 11d. DEMO: insert 8,000 rows for a NEW customer 2000 (below the 14,142 threshold -> no auto update)
INSERT INTO dbo.L19_Orders (OrderID, CustomerID, EmployeeID, OrderDate, Amount, Status, RefNo)
SELECT 200000 + value, 2000, 101, '2025-12-31', 500, 'Completed', 'N' + CAST(value AS VARCHAR(10))
FROM GENERATE_SERIES(1, 8000);
GO
SELECT sp.rows, sp.modification_counter FROM sys.stats s CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) sp
WHERE s.object_id = OBJECT_ID('dbo.L19_Orders') AND s.name = 'IX_L19_Orders_CustomerID';     -- rows 200000 (stale), modification_counter 8000
GO
SELECT /* L19a:stale */ COUNT(*) AS Cnt, SUM(Amount) AS Total FROM dbo.L19_Orders WHERE CustomerID = 2000;   -- 8000, 4000000.00
GO
-- Estimated rows of the Index Seek in the cached plan (technique from Level 18):
WITH XMLNAMESPACES (DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan')
SELECT r.value('@PhysicalOp', 'varchar(50)') AS PhysicalOp, r.value('@EstimateRows', 'float') AS EstRows
FROM sys.dm_exec_cached_plans cp
CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) st
CROSS APPLY sys.dm_exec_query_plan(cp.plan_handle) qp
CROSS APPLY qp.query_plan.nodes('//RelOp[@PhysicalOp="Index Seek"]') n(r)
WHERE st.text LIKE '%L19a:stale */%' AND st.text NOT LIKE '%dm_exec_cached_plans%';
-- expect: EstRows 8 while the real count is 8000 -> the plan does 8000 Key Lookups one by one
GO
-- FIX 1: update this one statistic with a full scan (SAMPLE n PERCENT is the cheaper option for huge tables)
UPDATE STATISTICS dbo.L19_Orders IX_L19_Orders_CustomerID WITH FULLSCAN;
GO
SELECT /* L19a:fresh */ COUNT(*) AS Cnt, SUM(Amount) AS Total FROM dbo.L19_Orders WHERE CustomerID = 2000;   -- same result
GO
WITH XMLNAMESPACES (DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan')
SELECT r.value('@PhysicalOp', 'varchar(50)') AS PhysicalOp, r.value('@EstimateRows', 'float') AS EstRows
FROM sys.dm_exec_cached_plans cp
CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) st
CROSS APPLY sys.dm_exec_query_plan(cp.plan_handle) qp
CROSS APPLY qp.query_plan.nodes('//RelOp[@PhysicalOp="Index Seek"]') n(r)
WHERE st.text LIKE '%L19a:fresh */%' AND st.text NOT LIKE '%dm_exec_cached_plans%';
-- expect: EstRows 8000 (and the plan no longer does row-by-row lookups)
GO
-- FIX 2: refresh every statistic of the database that has changed (what maintenance jobs run at night)
EXEC sp_updatestats;                                       -- prints one line per table; "has been updated" only where needed
GO
-- FIX 3 (comment): UPDATE STATISTICS dbo.L19_Orders;  -> all statistics of one table, default sampling.
DELETE FROM dbo.L19_Orders WHERE OrderID > 200000;         -- put the table back
UPDATE STATISTICS dbo.L19_Orders WITH FULLSCAN;
GO


/* ============================================================
   12. QUERY-WRITING TIPS (measured where possible)
   ============================================================ */
SET STATISTICS IO ON;
GO
-- 12a. SELECT * vs only the columns you need: the covering index cannot be used for *.
SELECT *                 FROM dbo.L19_Orders WHERE OrderDate >= '2024-06-01' AND OrderDate < '2024-06-02';   -- 183 rows, about 573 reads (lookups)
SELECT OrderDate, Amount FROM dbo.L19_Orders WHERE OrderDate >= '2024-06-01' AND OrderDate < '2024-06-02';   -- 183 rows, 4 reads (covered)
GO
-- 12b. EXISTS vs IN vs JOIN for "orders whose customer exists": the optimizer builds the SAME plan
--      (semi join) for all three - about 163 reads each. Choose by readability, not by myth.
SELECT COUNT(*) AS Cnt FROM dbo.L19_Orders o WHERE EXISTS (SELECT 1 FROM dbo.Customers c WHERE c.CustomerID = o.CustomerID);   -- 80843
SELECT COUNT(*) AS Cnt FROM dbo.L19_Orders o WHERE o.CustomerID IN (SELECT c.CustomerID FROM dbo.Customers c);               -- 80843
SELECT COUNT(*) AS Cnt FROM dbo.L19_Orders o JOIN dbo.Customers c ON c.CustomerID = o.CustomerID;                            -- 80843 (JOIN can duplicate rows if c were not unique!)
GO
-- 12c. DISTINCT abuse: DISTINCT added to hide duplicates from a join = extra Sort/Hash over all rows.
--      Ask the real question ("customers who have orders") with EXISTS instead.
SELECT DISTINCT c.CustomerID, c.CustomerName FROM dbo.Customers c JOIN dbo.Orders o ON o.CustomerID = c.CustomerID;         -- 7 rows
SELECT c.CustomerID, c.CustomerName FROM dbo.Customers c WHERE EXISTS (SELECT 1 FROM dbo.Orders o WHERE o.CustomerID = c.CustomerID);   -- 7 rows, no DISTINCT needed
GO
-- 12d. ORDER BY costs a Sort operator (memory + CPU) unless an index already delivers that order.
--      Sort only when the user needs it, and sort as few rows as possible (filter first, TOP).
SELECT OrderID, Amount FROM dbo.L19_Orders WHERE CustomerID = 500 ORDER BY Amount;                   -- 120 rows sorted in memory
GO
-- 12e. TOP without ORDER BY = "any N rows"; the result can change with the plan or the data layout.
SELECT TOP (3) OrderID FROM dbo.L19_Orders WHERE CustomerID = 500;                          -- some 3 rows (index order today)
SELECT TOP (3) OrderID FROM dbo.L19_Orders WHERE CustomerID = 500 ORDER BY OrderDate DESC;   -- the 3 newest - deterministic
GO
-- 12f. Unnecessary subqueries: a scalar subquery in the SELECT list runs once per outer row.
SELECT c.CustomerName, (SELECT COUNT(*) FROM dbo.Orders o WHERE o.CustomerID = c.CustomerID) AS Orders FROM dbo.Customers c;   -- 8 rows
SELECT c.CustomerName, COUNT(o.OrderID) AS Orders FROM dbo.Customers c LEFT JOIN dbo.Orders o ON o.CustomerID = c.CustomerID
GROUP BY c.CustomerName;                                                                                                      -- same 8 rows, one pass
GO
SET STATISTICS IO OFF;
GO
-- 12g. SET-BASED vs ROW-BY-ROW: update 20,000 rows one at a time vs in one statement.
DROP TABLE IF EXISTS dbo.L19_OrdersCopy;
SELECT TOP (20000) OrderID, Amount INTO dbo.L19_OrdersCopy FROM dbo.L19_Orders ORDER BY OrderID;
CREATE UNIQUE CLUSTERED INDEX CX_L19_OrdersCopy ON dbo.L19_OrdersCopy (OrderID);
GO
-- (STATISTICS TIME stays OFF for the loop: it would print 20,000 timing messages. We time it with SYSDATETIME.)
DECLARE @t0 DATETIME2 = SYSDATETIME(), @i INT = 1;
WHILE @i <= 20000
BEGIN
    UPDATE dbo.L19_OrdersCopy SET Amount = Amount * 1.01 WHERE OrderID = @i;
    SET @i += 1;
END
SELECT 'WHILE loop, 20000 statements' AS Method, DATEDIFF(MILLISECOND, @t0, SYSDATETIME()) AS Ms;      -- about 2000-3000 ms
GO
SET STATISTICS TIME ON;      -- for ONE statement it is useful: CPU time vs elapsed time
GO
DECLARE @t0 DATETIME2 = SYSDATETIME();
UPDATE dbo.L19_OrdersCopy SET Amount = Amount * 1.01;
SELECT 'one UPDATE' AS Method, DATEDIFF(MILLISECOND, @t0, SYSDATETIME()) AS Ms;                          -- about 10-20 ms (100x+ faster)
GO
SET STATISTICS TIME OFF;
GO
-- SQL Server is a set engine: one statement = one plan, one pass, minimal logging overhead.
-- A loop = 20,000 plans looked up, 20,000 log records, 20,000 lock acquisitions.


/* ============================================================
   13. CLEANUP
   ============================================================ */
DROP TABLE IF EXISTS dbo.L19_OrdersCopy;
DROP TABLE IF EXISTS dbo.L19_Orders;
GO
/* DONE. Next: 02_Practice_Parameter_Sniffing_Waits.sql */
