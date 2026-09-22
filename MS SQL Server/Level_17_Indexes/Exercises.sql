/* ============================================================
   LEVEL 17 - INDEXES  |  Exercises.sql
   ------------------------------------------------------------
   Try each question in the "YOUR ANSWERS" area FIRST.
   Then scroll down to SOLUTIONS and compare.
   Works on dbo.L17_Ex_Orders (200,000 rows, built in Q1, dropped
   at the end). Measure everything with SET STATISTICS IO ON.
   ============================================================ */

USE SQLPractice;
GO
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
GO
DROP INDEX IF EXISTS IX_L17_Ex_OrderDetails_OrderID ON dbo.OrderDetails;
DROP TABLE IF EXISTS dbo.L17_Ex_Orders;
GO

/* ------------------------------------------------------------
   QUESTIONS
   ------------------------------------------------------------
   Q1.  Build dbo.L17_Ex_Orders with 200,000 rows (OrderID 1..200000, CustomerID 1..1000,
        EmployeeID 101..112 with 1% NULL, OrderDate over 2023-2025, Amount, Status) from
        GENERATE_SERIES, WITHOUT any index. Prove it is a heap with sys.indexes.

   Q2.  Turn on STATISTICS IO and measure the logical reads of
        SELECT COUNT(*) FROM dbo.L17_Ex_Orders WHERE CustomerID = 42;   (expect a Table Scan)

   Q3.  Add a clustered primary key on OrderID. Show sys.indexes. Measure Q2 again -
        does the clustered index help this query? Why not?

   Q4.  Create the index that turns Q2 into an Index Seek and measure again.

   Q5.  Measure  SELECT SUM(Amount) FROM dbo.L17_Ex_Orders WHERE CustomerID = 42;
        Explain the extra reads (Key Lookup). Create a covering index and measure again.

   Q6.  Create a composite index on (Status, OrderDate). Measure:
          (a) WHERE Status = 'Pending' AND OrderDate >= '20250101'
          (b) WHERE OrderDate >= '20250101'   (only the second column)
        Which one seeks? Why?

   Q7.  Create a filtered index on (OrderDate) WHERE Status = 'Cancelled'. Compare its
        row_count and used_page_count with the full (Status, OrderDate) index.

   Q8.  Both queries below scan although an index exists. Rewrite them SARGable and
        measure before/after:
          (a) WHERE YEAR(OrderDate) = 2025          (index IX on OrderDate needed)
          (b) WHERE ISNULL(EmployeeID, 0) = 0       (index IX on EmployeeID needed)

   Q9.  Show avg_fragmentation_in_percent and page_count of every index on the table.
        Write the maintenance statement you would run for an index above 30 %.

   Q10. Using sys.dm_db_index_usage_stats list the indexes of dbo.L17_Ex_Orders that
        have NEVER been used for a seek, scan or lookup since creation.

   Q11. Run  SELECT COUNT(*) FROM dbo.L17_Ex_Orders WHERE Amount BETWEEN 99000 AND 100000
        (no index on Amount), then show what the missing index DMVs suggest for this table.

   Q12. List the foreign keys of SQLPractice whose first column has no index. Create the
        missing index for dbo.OrderDetails(OrderID) as IX_L17_Ex_OrderDetails_OrderID,
        verify, then drop it again.
   ------------------------------------------------------------ */

-- YOUR ANSWERS HERE (write below, run, compare)










/* ============================================================
   SOLUTIONS
   ============================================================ */

-- Q1
SELECT ISNULL(CAST(s.value AS INT), 0)                                    AS OrderID,
       s.value % 1000 + 1                                                  AS CustomerID,
       CASE WHEN s.value % 100 = 0 THEN NULL ELSE 101 + s.value % 12 END    AS EmployeeID,
       CAST(DATEADD(DAY, s.value % 1096, '2023-01-01') AS DATE)            AS OrderDate,
       CAST((s.value * 37) % 100000 + 100 AS DECIMAL(12,2))                AS Amount,
       CASE s.value % 20 WHEN 0 THEN 'Pending' WHEN 1 THEN 'Cancelled' ELSE 'Completed' END AS Status
INTO dbo.L17_Ex_Orders
FROM GENERATE_SERIES(1, 200000) AS s;
SELECT index_id, name, type_desc FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.L17_Ex_Orders');
-- expect: index_id 0, NULL, HEAP
GO

-- Q2
SET STATISTICS IO ON;
GO
PRINT '=== Q2 heap ===';
SELECT COUNT(*) AS Orders FROM dbo.L17_Ex_Orders WHERE CustomerID = 42;
-- expect 200 rows, ~1,140 logical reads (Table Scan)
GO
SET STATISTICS IO OFF;
GO

-- Q3
ALTER TABLE dbo.L17_Ex_Orders ADD CONSTRAINT PK_L17_Ex_Orders PRIMARY KEY CLUSTERED (OrderID);
SELECT index_id, name, type_desc FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.L17_Ex_Orders');
-- expect: index_id 1, PK_L17_Ex_Orders, CLUSTERED
GO
SET STATISTICS IO ON;
GO
PRINT '=== Q3 clustered index scan ===';
SELECT COUNT(*) AS Orders FROM dbo.L17_Ex_Orders WHERE CustomerID = 42;
-- expect about the same reads: the table is sorted by OrderID, which says nothing about CustomerID
GO
SET STATISTICS IO OFF;
GO

-- Q4
CREATE NONCLUSTERED INDEX IX_L17_Ex_Orders_CustomerID ON dbo.L17_Ex_Orders (CustomerID);
GO
SET STATISTICS IO ON;
GO
PRINT '=== Q4 index seek ===';
SELECT COUNT(*) AS Orders FROM dbo.L17_Ex_Orders WHERE CustomerID = 42;
-- expect 2-3 logical reads
GO

-- Q5
PRINT '=== Q5 seek + key lookups ===';
SELECT SUM(Amount) AS Total FROM dbo.L17_Ex_Orders WHERE CustomerID = 42;
-- expect ~620 reads: Amount is not in the index -> 200 Key Lookups into the clustered index
GO
SET STATISTICS IO OFF;
GO
CREATE NONCLUSTERED INDEX IX_L17_Ex_Orders_CustomerID_Amount ON dbo.L17_Ex_Orders (CustomerID) INCLUDE (Amount);
GO
SET STATISTICS IO ON;
GO
PRINT '=== Q5 covered ===';
SELECT SUM(Amount) AS Total FROM dbo.L17_Ex_Orders WHERE CustomerID = 42;
-- expect 3 reads
GO
SET STATISTICS IO OFF;
GO

-- Q6
CREATE NONCLUSTERED INDEX IX_L17_Ex_Orders_Status_Date ON dbo.L17_Ex_Orders (Status, OrderDate);
GO
SET STATISTICS IO ON;
GO
PRINT '=== Q6a leftmost column present -> seek ===';
SELECT COUNT(*) AS Pending2025 FROM dbo.L17_Ex_Orders WHERE Status = 'Pending' AND OrderDate >= '20250101';
-- expect 3312 rows, ~14 reads
GO
PRINT '=== Q6b second column only -> scan of the index ===';
SELECT COUNT(*) AS Orders2025 FROM dbo.L17_Ex_Orders WHERE OrderDate >= '20250101';
-- expect ~650 reads: dates are sorted only INSIDE each Status value (leftmost prefix rule)
GO
SET STATISTICS IO OFF;
GO

-- Q7
CREATE NONCLUSTERED INDEX IX_L17_Ex_Orders_Cancelled_Date ON dbo.L17_Ex_Orders (OrderDate) WHERE Status = 'Cancelled';
GO
SELECT i.name, i.filter_definition, ps.row_count, ps.used_page_count
FROM sys.indexes i
JOIN sys.dm_db_partition_stats ps ON ps.object_id = i.object_id AND ps.index_id = i.index_id
WHERE i.object_id = OBJECT_ID('dbo.L17_Ex_Orders') AND i.name IN ('IX_L17_Ex_Orders_Status_Date', 'IX_L17_Ex_Orders_Cancelled_Date');
-- expect 200000 rows / ~650 pages vs 10000 rows / ~20 pages
GO

-- Q8
CREATE NONCLUSTERED INDEX IX_L17_Ex_Orders_OrderDate  ON dbo.L17_Ex_Orders (OrderDate);
CREATE NONCLUSTERED INDEX IX_L17_Ex_Orders_EmployeeID ON dbo.L17_Ex_Orders (EmployeeID);
GO
SET STATISTICS IO ON;
GO
PRINT '=== Q8a before: YEAR() ===';
SELECT COUNT(*) AS Orders2025 FROM dbo.L17_Ex_Orders WHERE YEAR(OrderDate) = 2025;             -- scan, ~320 reads
PRINT '=== Q8a after: range ===';
SELECT COUNT(*) AS Orders2025 FROM dbo.L17_Ex_Orders WHERE OrderDate >= '20250101' AND OrderDate < '20260101';  -- seek, ~110 reads
PRINT '=== Q8b before: ISNULL() ===';
SELECT COUNT(*) AS Online FROM dbo.L17_Ex_Orders WHERE ISNULL(EmployeeID, 0) = 0;                -- scan, ~350 reads
PRINT '=== Q8b after: IS NULL ===';
SELECT COUNT(*) AS Online FROM dbo.L17_Ex_Orders WHERE EmployeeID IS NULL;                        -- seek, ~6 reads
GO
SET STATISTICS IO OFF;
GO

-- Q9
SELECT i.name, ps.avg_fragmentation_in_percent, ps.page_count
FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID('dbo.L17_Ex_Orders'), NULL, NULL, 'LIMITED') ps
JOIN sys.indexes i ON i.object_id = ps.object_id AND i.index_id = ps.index_id
ORDER BY ps.avg_fragmentation_in_percent DESC;
-- expect all near 0 % (freshly built). Maintenance for > 30 % and > 1000 pages:
--   ALTER INDEX <name> ON dbo.L17_Ex_Orders REBUILD;        (5-30 %: ... REORGANIZE;)
GO

-- Q10
SELECT i.name, i.type_desc
FROM sys.indexes i
LEFT JOIN sys.dm_db_index_usage_stats us
       ON us.object_id = i.object_id AND us.index_id = i.index_id AND us.database_id = DB_ID()
WHERE i.object_id = OBJECT_ID('dbo.L17_Ex_Orders') AND i.index_id > 0
  AND ISNULL(us.user_seeks, 0) + ISNULL(us.user_scans, 0) + ISNULL(us.user_lookups, 0) = 0;
-- expect IX_L17_Ex_Orders_Cancelled_Date (never queried); the rest were used above
GO

-- Q11
SELECT COUNT(*) AS Expensive FROM dbo.L17_Ex_Orders WHERE Amount BETWEEN 99000 AND 100000;
GO
SELECT d.equality_columns, d.inequality_columns, d.included_columns, s.user_seeks, s.avg_user_impact
FROM sys.dm_db_missing_index_details d
JOIN sys.dm_db_missing_index_groups g ON g.index_handle = d.index_handle
JOIN sys.dm_db_missing_index_group_stats s ON s.group_handle = g.index_group_handle
WHERE d.database_id = DB_ID() AND d.object_id = OBJECT_ID('dbo.L17_Ex_Orders');
-- expect a row with inequality_columns = [Amount]
GO

-- Q12
SELECT OBJECT_NAME(fk.parent_object_id) AS ChildTable, fk.name AS ForeignKey, c.name AS ChildColumn
FROM sys.foreign_keys fk
JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
JOIN sys.columns c ON c.object_id = fkc.parent_object_id AND c.column_id = fkc.parent_column_id
WHERE NOT EXISTS (SELECT 1 FROM sys.index_columns ic
                  WHERE ic.object_id = fkc.parent_object_id AND ic.column_id = fkc.parent_column_id AND ic.key_ordinal = 1)
ORDER BY ChildTable, ForeignKey;
-- expect 6 rows (all FKs of SQLPractice)
CREATE NONCLUSTERED INDEX IX_L17_Ex_OrderDetails_OrderID ON dbo.OrderDetails (OrderID);
SELECT name FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.OrderDetails') AND index_id > 0;   -- PK + the new one
DROP INDEX IX_L17_Ex_OrderDetails_OrderID ON dbo.OrderDetails;
GO

/* ---------------- cleanup ---------------- */
SET STATISTICS IO OFF;
DROP INDEX IF EXISTS IX_L17_Ex_OrderDetails_OrderID ON dbo.OrderDetails;
DROP TABLE IF EXISTS dbo.L17_Ex_Orders;
GO
