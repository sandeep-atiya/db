/* ============================================================
   LEVEL 17 - INDEXES  |  01_Practice_Index_Types.sql
   ------------------------------------------------------------
   Topics : what an index is (B-tree), heap vs clustered index,
            nonclustered index, CREATE INDEX variants, composite
            index + column order (leftmost prefix), unique index vs
            UNIQUE constraint, filtered index, INCLUDE / covering
            index, index on an expression (computed column), indexes
            and NULLs, DROP INDEX, ALTER INDEX REBUILD / REORGANIZE /
            DISABLE, fill factor, fragmentation, usage and size DMVs,
            sp_helpindex, when NOT to index, DML cost, PK / UNIQUE /
            FK and indexes.
   HOW TO PRACTICE: run block by block, predict the output first.
   Builds a 200,000 row table dbo.L17_Orders (a 19-row table never
   shows index behaviour). Everything is dropped in CLEANUP.
   "logical reads" = 8 KB pages touched: the number to watch.
   ============================================================ */

USE SQLPractice;
GO
SET NOCOUNT ON;
-- sqlcmd connects with QUOTED_IDENTIFIER OFF; filtered indexes and indexes on
-- computed columns need it ON (SSMS already has it ON).
SET QUOTED_IDENTIFIER ON;
GO
DROP INDEX IF EXISTS IX_L17_Orders_CustomerID ON dbo.Orders;      -- base-table index from section 15
DROP TABLE IF EXISTS dbo.L17_Orders, dbo.L17_NullDemo;
GO

-- 200,000 orders: 1000 customers, 12 salespeople (1% online = NULL), 3 years, 5% Pending
SELECT ISNULL(CAST(s.value AS INT), 0)                                    AS OrderID,
       s.value % 1000 + 1                                                  AS CustomerID,
       CASE WHEN s.value % 100 = 0 THEN NULL ELSE 101 + s.value % 12 END    AS EmployeeID,
       CAST(DATEADD(DAY, s.value % 1096, '2023-01-01') AS DATE)            AS OrderDate,    -- 2023-01-01 .. 2025-12-31
       CAST((s.value * 37) % 100000 + 100 AS DECIMAL(12,2))                AS Amount,
       CASE s.value % 20 WHEN 0 THEN 'Pending' WHEN 1 THEN 'Cancelled' ELSE 'Completed' END AS Status,
       CAST(s.value % 1000 + 1 AS VARCHAR(10))                             AS CustomerCode  -- used in file 02
INTO dbo.L17_Orders
FROM GENERATE_SERIES(1, 200000) AS s;      -- SQL 2022+ (older: a numbers CTE with ROW_NUMBER)
SELECT COUNT(*) AS Rows, MIN(OrderDate) AS FirstDate, MAX(OrderDate) AS LastDate FROM dbo.L17_Orders;
-- expect 200000, 2023-01-01, 2025-12-31
GO


/* ============================================================
   1. WHAT IS AN INDEX?  HEAP vs CLUSTERED INDEX
   ============================================================
   An index is a B-TREE (balanced tree): one ROOT page -> a few
   INTERMEDIATE pages -> many LEAF pages, all sorted by the key.
   Finding a key = 3-4 page reads instead of reading the whole table.

   HEAP              = table WITHOUT a clustered index; rows lie in no order.
                       Row address = RID (file:page:slot).            index_id = 0
   CLUSTERED INDEX   = the table itself sorted by the key; the LEAF
                       level IS the data. Max ONE per table.          index_id = 1
                       PRIMARY KEY creates it by default.
   NONCLUSTERED      = separate B-tree; leaf holds key + "row locator"
                       (clustered key, or RID on a heap). Up to 999.  index_id >= 2
   ============================================================ */

-- 1a. Right now dbo.L17_Orders is a HEAP (SELECT INTO creates no index)
SELECT index_id, name, type_desc FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.L17_Orders');
-- expect 1 row: index_id 0, name NULL, HEAP

-- 1b. Add the PRIMARY KEY -> clustered index by default (the data is physically re-sorted by OrderID)
ALTER TABLE dbo.L17_Orders ADD CONSTRAINT PK_L17_Orders PRIMARY KEY (OrderID);
SELECT index_id, name, type_desc, is_primary_key, is_unique
FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.L17_Orders');
-- expect 1 row: index_id 1, PK_L17_Orders, CLUSTERED, 1, 1
GO
-- (PRIMARY KEY NONCLUSTERED (OrderID) would keep the heap and make a nonclustered PK.)

-- 1c. See the B-tree levels: index_level 0 = leaf (the data pages), higher = root/intermediate
SELECT index_level, page_count, record_count, avg_record_size_in_bytes
FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID('dbo.L17_Orders'), 1, NULL, 'DETAILED')
ORDER BY index_level DESC;
-- expect 3 rows: level 2 = ROOT (1 page), level 1 = intermediate (a few pages),
--                level 0 = LEAF (about 1,250 pages holding all 200,000 records)
GO

-- 1d. Only ONE clustered index per table
BEGIN TRY
    CREATE CLUSTERED INDEX CX_L17_Orders_Date ON dbo.L17_Orders (OrderDate);
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO


/* ============================================================
   2. NONCLUSTERED INDEX
   ============================================================ */
CREATE NONCLUSTERED INDEX IX_L17_Orders_CustomerID ON dbo.L17_Orders (CustomerID);
GO
SELECT i.index_id, i.name, i.type_desc, ps.index_depth, ps.page_count
FROM sys.indexes i
CROSS APPLY sys.dm_db_index_physical_stats(DB_ID(), i.object_id, i.index_id, NULL, 'LIMITED') ps
WHERE i.object_id = OBJECT_ID('dbo.L17_Orders')
ORDER BY i.index_id;
-- expect 2 rows: clustered (index_id 1, ~1,250 pages, depth 3) and IX_L17_Orders_CustomerID (index_id 2,
-- ~350 pages, depth 2: its leaf holds only CustomerID + the row locator OrderID)
GO


/* ============================================================
   3. CREATE INDEX - syntax variants (reference)
   ============================================================
   CREATE [UNIQUE] [CLUSTERED | NONCLUSTERED] INDEX IX_Name
       ON dbo.Table (Col1 [ASC|DESC], Col2, ...)      -- KEY columns: sorted, searchable, max 32 / 1700 bytes
       [INCLUDE (ColA, ColB)]                          -- leaf-only copies: covering, not sorted
       [WHERE <predicate>]                             -- filtered index (2008+)
       [WITH (FILLFACTOR = 90, ONLINE = ON,            -- ONLINE: Enterprise/Developer
              SORT_IN_TEMPDB = ON, DATA_COMPRESSION = PAGE, DROP_EXISTING = ON)]
       [ON [PRIMARY] | filegroup];
   Inline in CREATE TABLE (2014+):  CREATE TABLE t (..., INDEX IX_t_Col NONCLUSTERED (Col));
   ============================================================ */


/* ============================================================
   4. COMPOSITE INDEX and WHY COLUMN ORDER MATTERS (leftmost prefix)
   ============================================================
   Index on (CustomerID, OrderDate) is sorted by CustomerID FIRST,
   then by OrderDate inside each customer - like a phone book sorted
   by surname then first name. You can SEEK on (CustomerID) or on
   (CustomerID, OrderDate), but NOT on OrderDate alone: the dates
   are scattered across all customers -> SCAN.
   ============================================================ */
CREATE NONCLUSTERED INDEX IX_L17_Orders_Cust_Date ON dbo.L17_Orders (CustomerID, OrderDate);
GO
SET STATISTICS IO ON;
GO
PRINT '=== 4a. leftmost column used -> Index Seek (few reads) ===';
SELECT COUNT(*) AS Orders FROM dbo.L17_Orders WHERE CustomerID = 5 AND OrderDate >= '2025-01-01';
-- expect logical reads < 5 (seek straight to customer 5, then the date range inside it)
GO
PRINT '=== 4b. only the SECOND column -> the index must be scanned end to end ===';
SELECT COUNT(*) AS Orders FROM dbo.L17_Orders WHERE OrderDate = '2025-03-01';
-- expect hundreds of logical reads (whole index leaf level), same answer
GO
SET STATISTICS IO OFF;
GO
-- Proof of the operator (SHOWPLAN_TEXT shows the plan and does NOT run the query):
SET SHOWPLAN_TEXT ON;
GO
SELECT COUNT(*) FROM dbo.L17_Orders WHERE CustomerID = 5 AND OrderDate >= '2025-01-01';   -- Index Seek
SELECT COUNT(*) FROM dbo.L17_Orders WHERE OrderDate = '2025-03-01';                       -- Index Scan
GO
SET SHOWPLAN_TEXT OFF;
GO
-- Rule: put the column you filter with = most often FIRST; put range columns last.
-- An index on (A, B) makes an index on (A) alone redundant (but not (B) alone).


/* ============================================================
   5. UNIQUE INDEX vs UNIQUE CONSTRAINT
   ============================================================
   Both are enforced by a unique index. The CONSTRAINT is the logical
   rule (visible in INFORMATION_SCHEMA, can be referenced by an FK,
   dropped with ALTER TABLE DROP CONSTRAINT). The plain unique INDEX
   can additionally have INCLUDE, a WHERE filter and IGNORE_DUP_KEY.
   ============================================================ */
CREATE TABLE dbo.L17_NullDemo (ID INT NOT NULL, Email VARCHAR(50) NULL, Phone VARCHAR(20) NULL);
ALTER TABLE dbo.L17_NullDemo ADD CONSTRAINT UQ_L17_NullDemo_Email UNIQUE (Email);         -- constraint
CREATE UNIQUE INDEX UX_L17_NullDemo_Phone ON dbo.L17_NullDemo (Phone) WITH (IGNORE_DUP_KEY = ON);  -- index
GO
SELECT name, is_unique, is_unique_constraint, ignore_dup_key
FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.L17_NullDemo') AND index_id > 0;
-- expect: UQ_... 1/1/0   UX_... 1/0/1
GO
-- The constraint's index cannot be dropped with DROP INDEX (error 3723)
BEGIN TRY
    DROP INDEX UQ_L17_NullDemo_Email ON dbo.L17_NullDemo;
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO
-- IGNORE_DUP_KEY: duplicates are silently skipped with a warning instead of failing the whole INSERT
INSERT INTO dbo.L17_NullDemo (ID, Email, Phone) VALUES (1, 'a@x.com', '111'), (2, 'b@x.com', '111');
SELECT * FROM dbo.L17_NullDemo;      -- 1 row (the second '111' was ignored: "Duplicate key was ignored.")
GO


/* ============================================================
   6. FILTERED INDEX  (2008+)  - index only the rows you query
   ============================================================ */
-- Only 5% of orders are Pending. A full index on OrderDate has 200,000 entries; the
-- filtered one has 10,000 -> smaller, cheaper to maintain, more accurate statistics.
CREATE NONCLUSTERED INDEX IX_L17_Orders_OrderDate ON dbo.L17_Orders (OrderDate);
CREATE NONCLUSTERED INDEX IX_L17_Orders_Pending_Date ON dbo.L17_Orders (OrderDate) WHERE Status = 'Pending';
GO
SELECT i.name, i.has_filter, i.filter_definition, ps.row_count, ps.used_page_count
FROM sys.indexes i
JOIN sys.dm_db_partition_stats ps ON ps.object_id = i.object_id AND ps.index_id = i.index_id
WHERE i.object_id = OBJECT_ID('dbo.L17_Orders') AND i.name LIKE '%Date'
ORDER BY i.name;
-- expect IX_L17_Orders_OrderDate 200000 rows / ~320 pages, IX_L17_Orders_Pending_Date 10000 rows / ~20 pages
GO
SET STATISTICS IO ON;
GO
PRINT '=== 6a. query matching the filter uses the small index ===';
SELECT COUNT(*) AS PendingIn2025 FROM dbo.L17_Orders WHERE Status = 'Pending' AND OrderDate >= '2025-01-01';
-- expect 3312 rows counted with about 9 logical reads (only the pending rows of 2025 are read)
GO
SET STATISTICS IO OFF;
GO
-- Gotcha: WHERE Status = @p (a parameter/variable) cannot use it - the optimizer cannot
-- prove @p = 'Pending' at compile time (use OPTION (RECOMPILE) or a literal).


/* ============================================================
   7. INCLUDE COLUMNS and the COVERING INDEX (kill the Key Lookup)
   ============================================================
   A nonclustered index knows only its key + the clustered key. Any
   OTHER column in your SELECT must be fetched from the clustered
   index = one "Key Lookup" PER ROW (expensive: ~3 reads each).
   INCLUDE copies those columns into the leaf level -> the index
   "covers" the query -> no lookups.
   ============================================================ */
SET STATISTICS IO ON;
GO
PRINT '=== 7a. only key columns needed: seek, no lookup ===';
SELECT COUNT(*) AS Orders, MAX(OrderID) AS LastOrderID FROM dbo.L17_Orders WHERE CustomerID = 5;
-- expect 200 rows counted with 3-4 logical reads (OrderID = clustered key -> already in the index leaf)
GO
PRINT '=== 7b. Amount is needed too: 200 Key Lookups into the clustered index ===';
SELECT COUNT(*) AS Orders, SUM(Amount) AS Total FROM dbo.L17_Orders WHERE CustomerID = 5;
-- expect ~620 logical reads (200 rows x 3 pages per lookup + the seek)
GO
SET STATISTICS IO OFF;
GO
CREATE NONCLUSTERED INDEX IX_L17_Orders_CustomerID_Covering
    ON dbo.L17_Orders (CustomerID) INCLUDE (Amount, OrderDate);
GO
SET STATISTICS IO ON;
GO
PRINT '=== 7c. covering index: back to 3-4 reads ===';
SELECT COUNT(*) AS Orders, SUM(Amount) AS Total FROM dbo.L17_Orders WHERE CustomerID = 5;
-- expect 3-4 logical reads: from ~620 to 4 for the same answer
GO
SET STATISTICS IO OFF;
GO
-- INCLUDE columns: not sorted, not counted in the 32-column / 1700-byte key limit,
-- can be (N)VARCHAR(MAX). Do not "include everything" - every column costs write time and space.


/* ============================================================
   8. INDEX ON AN EXPRESSION - via a COMPUTED COLUMN
   ============================================================
   WHERE YEAR(OrderDate) = 2024 cannot seek on OrderDate (function on
   the column). Add a computed column with that expression, index it,
   and the optimizer matches the expression automatically.
   ============================================================ */
SET STATISTICS IO ON;
GO
PRINT '=== 8a. before: YEAR(OrderDate) = 2024 -> scan ===';
SELECT COUNT(*) AS Orders2024 FROM dbo.L17_Orders WHERE YEAR(OrderDate) = 2024;
-- expect ~320 logical reads (scans the narrowest index that has OrderDate)
GO
SET STATISTICS IO OFF;
GO
ALTER TABLE dbo.L17_Orders ADD OrderYear AS YEAR(OrderDate);            -- not even PERSISTED
CREATE NONCLUSTERED INDEX IX_L17_Orders_OrderYear ON dbo.L17_Orders (OrderYear);
GO
SET STATISTICS IO ON;
GO
PRINT '=== 8b. after: the same query uses IX_L17_Orders_OrderYear ===';
SELECT COUNT(*) AS Orders2024 FROM dbo.L17_Orders WHERE YEAR(OrderDate) = 2024;
-- expect ~120 logical reads (seek to 2024, read only that year's 66,776 entries)
GO
SET STATISTICS IO OFF;
GO
-- Needs: deterministic, precise expression and the SET options (QUOTED_IDENTIFIER etc.) ON.
-- Usually the better fix is a SARGable predicate (file 02): OrderDate >= '20240101' AND OrderDate < '20250101'.


/* ============================================================
   9. INDEXES AND NULLs
   ============================================================ */
-- 9a. NULLs ARE stored in indexes (as the lowest value): IS NULL can seek
CREATE NONCLUSTERED INDEX IX_L17_Orders_EmployeeID ON dbo.L17_Orders (EmployeeID);
GO
SET STATISTICS IO ON;
GO
PRINT '=== 9a. WHERE EmployeeID IS NULL -> Index Seek on the NULL entries ===';
SELECT COUNT(*) AS OnlineOrders FROM dbo.L17_Orders WHERE EmployeeID IS NULL;   -- 2000
-- expect < 10 logical reads
GO
SET STATISTICS IO OFF;
GO

-- 9b. A UNIQUE index/constraint treats NULL as a value -> only ONE NULL allowed
INSERT INTO dbo.L17_NullDemo (ID, Email, Phone) VALUES (3, NULL, '333');      -- first NULL email: ok
BEGIN TRY
    INSERT INTO dbo.L17_NullDemo (ID, Email, Phone) VALUES (4, NULL, '444');  -- second NULL: duplicate!
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO
-- 9c. Fix: a FILTERED unique index ignores the NULL rows
ALTER TABLE dbo.L17_NullDemo DROP CONSTRAINT UQ_L17_NullDemo_Email;
CREATE UNIQUE INDEX UX_L17_NullDemo_Email ON dbo.L17_NullDemo (Email) WHERE Email IS NOT NULL;
INSERT INTO dbo.L17_NullDemo (ID, Email, Phone) VALUES (4, NULL, '444');      -- now fine
SELECT ID, Email FROM dbo.L17_NullDemo ORDER BY ID;                            -- 3 rows: 1, 3, 4
GO


/* ============================================================
   10. DROP INDEX, ALTER INDEX REBUILD / REORGANIZE / DISABLE, FILL FACTOR
   ============================================================ */
DROP INDEX IF EXISTS IX_L17_Orders_OrderYear ON dbo.L17_Orders;
ALTER TABLE dbo.L17_Orders DROP COLUMN OrderYear;
GO
-- 10a. DISABLE: index stays in metadata but is empty and unusable; REBUILD brings it back.
--      (Disabling the CLUSTERED index makes the whole table unreadable - never do that.)
ALTER INDEX IX_L17_Orders_EmployeeID ON dbo.L17_Orders DISABLE;
SELECT name, is_disabled FROM sys.indexes WHERE name = 'IX_L17_Orders_EmployeeID';      -- 1
ALTER INDEX IX_L17_Orders_EmployeeID ON dbo.L17_Orders REBUILD;
SELECT name, is_disabled FROM sys.indexes WHERE name = 'IX_L17_Orders_EmployeeID';      -- 0
GO

-- 10b. FILL FACTOR: % of each leaf page filled at (re)build time. 100 = full pages (default),
--      70 = 30% free space per page for future inserts/updates -> fewer page splits, but
--      more pages to read. Only meaningful for indexes with random inserts (GUIDs, names).
SELECT name, fill_factor FROM sys.indexes WHERE name = 'IX_L17_Orders_OrderDate';       -- 0 (= 100)
SELECT page_count AS PagesAt100 FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID('dbo.L17_Orders'),
       INDEXPROPERTY(OBJECT_ID('dbo.L17_Orders'), 'IX_L17_Orders_OrderDate', 'IndexID'), NULL, 'LIMITED');
ALTER INDEX IX_L17_Orders_OrderDate ON dbo.L17_Orders REBUILD WITH (FILLFACTOR = 70);
SELECT name, fill_factor FROM sys.indexes WHERE name = 'IX_L17_Orders_OrderDate';       -- 70
SELECT page_count AS PagesAt70 FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID('dbo.L17_Orders'),
       INDEXPROPERTY(OBJECT_ID('dbo.L17_Orders'), 'IX_L17_Orders_OrderDate', 'IndexID'), NULL, 'LIMITED');
-- expect about 40% more pages at fill factor 70
GO


/* ============================================================
   11. FRAGMENTATION: sys.dm_db_index_physical_stats
   ============================================================
   Logical fragmentation = leaf pages are not in key order on disk
   (caused by page splits from inserts/updates in the middle).
   Guideline: > 1000 pages AND  5-30% -> REORGANIZE (online, light),
                                > 30% -> REBUILD (new copy, updates statistics).
   ============================================================ */
-- 11a. Freshly rebuilt index with FULL pages: 0 % fragmentation, ~100 % page fullness
ALTER INDEX IX_L17_Orders_OrderDate ON dbo.L17_Orders REBUILD WITH (FILLFACTOR = 100);
SELECT i.name, ps.avg_fragmentation_in_percent, ps.page_count, ps.avg_page_space_used_in_percent
FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID('dbo.L17_Orders'), NULL, NULL, 'SAMPLED') ps
JOIN sys.indexes i ON i.object_id = ps.object_id AND i.index_id = ps.index_id
WHERE i.name = 'IX_L17_Orders_OrderDate';
GO
-- 11b. Cause page splits: move 10% of the rows to scattered dates (full pages must split)
UPDATE dbo.L17_Orders SET OrderDate = DATEADD(DAY, (OrderID * 7919) % 1096, '2023-01-01') WHERE OrderID % 10 = 0;
SELECT i.name, ps.avg_fragmentation_in_percent, ps.page_count, ps.avg_page_space_used_in_percent
FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID('dbo.L17_Orders'), NULL, NULL, 'SAMPLED') ps
JOIN sys.indexes i ON i.object_id = ps.object_id AND i.index_id = ps.index_id
WHERE i.name = 'IX_L17_Orders_OrderDate';
-- expect ~99 % fragmentation, about twice the pages (322 -> ~640), pages only ~50 % full
-- (with the fill factor 70 of section 10b the free space would have absorbed the moves: 0 %)
GO
-- 11c. REORGANIZE (defrag the leaf level in place), then REBUILD (rewrite it)
ALTER INDEX IX_L17_Orders_OrderDate ON dbo.L17_Orders REORGANIZE;
SELECT 'after REORGANIZE' AS Step, ps.avg_fragmentation_in_percent, ps.page_count
FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID('dbo.L17_Orders'),
     INDEXPROPERTY(OBJECT_ID('dbo.L17_Orders'), 'IX_L17_Orders_OrderDate', 'IndexID'), NULL, 'SAMPLED') ps;
ALTER INDEX IX_L17_Orders_OrderDate ON dbo.L17_Orders REBUILD WITH (FILLFACTOR = 100);
SELECT 'after REBUILD' AS Step, ps.avg_fragmentation_in_percent, ps.page_count
FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID('dbo.L17_Orders'),
     INDEXPROPERTY(OBJECT_ID('dbo.L17_Orders'), 'IX_L17_Orders_OrderDate', 'IndexID'), NULL, 'SAMPLED') ps;
-- expect < 1 % after REORGANIZE (pages compacted back to ~322) and 0.0 % after REBUILD
GO
-- ALTER INDEX ALL ON dbo.L17_Orders REBUILD;   -- every index of the table


/* ============================================================
   12. INDEX USAGE: sys.dm_db_index_usage_stats  (reset at service restart)
   ============================================================ */
SELECT i.name, i.type_desc,
       us.user_seeks, us.user_scans, us.user_lookups, us.user_updates, us.last_user_seek
FROM sys.indexes i
LEFT JOIN sys.dm_db_index_usage_stats us
       ON us.object_id = i.object_id AND us.index_id = i.index_id AND us.database_id = DB_ID()
WHERE i.object_id = OBJECT_ID('dbo.L17_Orders')
ORDER BY i.index_id;
-- expect: IX_L17_Orders_Cust_Date has seeks (4a) AND a scan (4b); the clustered index has lookups (7b);
--         every index that CONTAINS OrderDate has user_updates from 11b (that is the WRITE cost),
--         IX_L17_Orders_CustomerID and _EmployeeID have none (OrderDate is not in them)
GO
-- Unused index finder (run on production after weeks of uptime):
--   ... WHERE ISNULL(us.user_seeks,0) + ISNULL(us.user_scans,0) + ISNULL(us.user_lookups,0) = 0
--         AND i.is_primary_key = 0 AND i.is_unique = 0   -> candidates to DROP


/* ============================================================
   13. INDEX SIZE: sys.dm_db_partition_stats, sp_helpindex
   ============================================================ */
SELECT i.index_id, i.name, ps.row_count, ps.used_page_count,
       CAST(ps.used_page_count * 8 / 1024.0 AS DECIMAL(10,2)) AS SizeMB
FROM sys.indexes i
JOIN sys.dm_db_partition_stats ps ON ps.object_id = i.object_id AND ps.index_id = i.index_id
WHERE i.object_id = OBJECT_ID('dbo.L17_Orders')
ORDER BY i.index_id;
-- expect the clustered index ~10 MB; the nonclustered ones 2.5-5 MB each; the filtered one ~0.3 MB
EXEC sp_helpindex 'dbo.L17_Orders';       -- name, description, key columns (not INCLUDE columns)
EXEC sp_spaceused 'dbo.L17_Orders';       -- data vs index_size
GO


/* ============================================================
   14. WHEN NOT TO INDEX - and what indexes cost on INSERT/UPDATE/DELETE
   ============================================================
   Skip the index when:
     - the table is tiny (Departments = 1 page: a scan IS the fastest plan),
     - the column has few distinct values (Status: 3 values, 90% 'Completed'),
     - the table is write-heavy (logging/staging) and rarely searched,
     - a wider existing index already starts with that column.
   Every index = one more B-tree to maintain on EVERY insert/update/delete.
   ============================================================ */
-- 14a. Low selectivity: the optimizer IGNORES the index for the 90% value
CREATE NONCLUSTERED INDEX IX_L17_Orders_Status ON dbo.L17_Orders (Status);
GO
SET STATISTICS IO ON;
GO
PRINT '=== 14a. Status = Completed (180,000 rows): index ignored, Key Lookups would cost more ===';
SELECT COUNT(*) AS Completed FROM dbo.L17_Orders WHERE Status = 'Completed';
-- fine for COUNT(*) (the index alone covers it), but:
SELECT MAX(Amount) AS MaxCompleted FROM dbo.L17_Orders WHERE Status = 'Completed';
-- expect ~1,260 reads = clustered index SCAN; the Status index is not used because
-- 180,000 lookups would cost ~540,000 reads
GO
SET STATISTICS IO OFF;
GO

-- 14b. DML cost: the same UPDATE with 8 indexes vs with only the clustered index
SET STATISTICS TIME ON;
GO
PRINT '=== 14b-1. UPDATE 20,000 OrderDate values with all nonclustered indexes in place ===';
UPDATE dbo.L17_Orders SET OrderDate = DATEADD(DAY, 1, OrderDate) WHERE OrderID % 10 = 0;
GO
SET STATISTICS TIME OFF;
GO
DROP INDEX IX_L17_Orders_CustomerID ON dbo.L17_Orders;
DROP INDEX IX_L17_Orders_Cust_Date ON dbo.L17_Orders;
DROP INDEX IX_L17_Orders_OrderDate ON dbo.L17_Orders;
DROP INDEX IX_L17_Orders_Pending_Date ON dbo.L17_Orders;
DROP INDEX IX_L17_Orders_CustomerID_Covering ON dbo.L17_Orders;
DROP INDEX IX_L17_Orders_EmployeeID ON dbo.L17_Orders;
DROP INDEX IX_L17_Orders_Status ON dbo.L17_Orders;
GO
SET STATISTICS TIME ON;
GO
PRINT '=== 14b-2. the same UPDATE with only the clustered index ===';
UPDATE dbo.L17_Orders SET OrderDate = DATEADD(DAY, -1, OrderDate) WHERE OrderID % 10 = 0;
GO
SET STATISTICS TIME OFF;
GO
-- expect the first UPDATE to take several times longer: 4 of the dropped indexes contain
-- OrderDate and each of them had to be modified for all 20,000 rows.


/* ============================================================
   15. PK / UNIQUE / FK and INDEXES
   ============================================================
   PRIMARY KEY  -> unique CLUSTERED index (default) or NONCLUSTERED if you say so
   UNIQUE       -> unique NONCLUSTERED index (default)
   FOREIGN KEY  -> NO index at all! You must create one yourself
                   (joins child->parent, and DELETE on the parent must check the child).
   ============================================================ */
-- 15a. Indexes on the base table dbo.Orders: only the PK
SELECT name, type_desc, is_primary_key, is_unique_constraint FROM sys.indexes
WHERE object_id = OBJECT_ID('dbo.Orders') AND index_id > 0;
-- expect 1 row: PK_Orders CLUSTERED

-- 15b. Foreign keys whose columns have NO supporting index (ready-to-use finder)
SELECT OBJECT_NAME(fk.parent_object_id) AS ChildTable, fk.name AS ForeignKey, c.name AS ChildColumn
FROM sys.foreign_keys fk
JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
JOIN sys.columns c ON c.object_id = fkc.parent_object_id AND c.column_id = fkc.parent_column_id
WHERE NOT EXISTS (SELECT 1 FROM sys.index_columns ic
                  WHERE ic.object_id = fkc.parent_object_id AND ic.column_id = fkc.parent_column_id
                    AND ic.key_ordinal = 1)
ORDER BY ChildTable, ForeignKey;
-- expect 6 rows: every FK in SQLPractice (Employees x2, OrderDetails x2, Orders x2) has no index
GO
-- 15c. Create the missing one on the base table (dropped again in CLEANUP)
CREATE NONCLUSTERED INDEX IX_L17_Orders_CustomerID ON dbo.Orders (CustomerID);
SELECT name, type_desc FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Orders') AND index_id > 0;
-- expect 2 rows now
GO


/* ============================================================
   16. CLEANUP
   ============================================================ */
SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
DROP INDEX IF EXISTS IX_L17_Orders_CustomerID ON dbo.Orders;
DROP TABLE IF EXISTS dbo.L17_Orders, dbo.L17_NullDemo;
GO
SELECT name FROM sys.objects WHERE name LIKE '%L17%';                                          -- 0 rows
SELECT name FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Orders') AND index_id > 0;      -- PK_Orders only
GO
/* DONE. Next: 02_Practice_Seek_Scan_Lookup.sql */
