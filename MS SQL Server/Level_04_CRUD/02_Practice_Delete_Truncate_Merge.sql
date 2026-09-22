/* ============================================================
   LEVEL 04 - CRUD  |  02_Practice_Delete_Truncate_Merge.sql
   ------------------------------------------------------------
   Topics : DELETE (WHERE, DELETE ... FROM JOIN, subquery, OUTPUT
            deleted.*), DELETE vs TRUNCATE vs DROP (identity reset,
            logging, WHERE, FK restriction), MERGE (upsert with
            WHEN MATCHED / NOT MATCHED BY TARGET / BY SOURCE, OUTPUT
            $action), TOP in INSERT / UPDATE / DELETE (batch deletes)

   HOW TO PRACTICE: run block by block, predict the output first.
   ALL changes happen on COPIES (dbo.L04_Products, dbo.L04_Customers,
   dbo.L04_Orders) made with SELECT ... INTO. Base tables are only read.
   ============================================================ */

USE SQLPractice;
GO

/* ---------- Clean start: drop every L04 object (children first) ---------- */
DROP TABLE IF EXISTS dbo.L04_Orders_Archive;
DROP TABLE IF EXISTS dbo.L04_TopProducts;
DROP TABLE IF EXISTS dbo.L04_Log;
DROP TABLE IF EXISTS dbo.L04_BigLog;
DROP TABLE IF EXISTS dbo.L04_ProductFeed;
DROP TABLE IF EXISTS dbo.L04_Orders;
DROP TABLE IF EXISTS dbo.L04_Customers;
DROP TABLE IF EXISTS dbo.L04_Products;
GO

/* ---------- Fresh copies (SELECT INTO copies rows, NOT constraints) + keys ---------- */
SELECT * INTO dbo.L04_Products  FROM dbo.Products;     -- 11 rows
SELECT * INTO dbo.L04_Customers FROM dbo.Customers;    -- 8 rows
SELECT * INTO dbo.L04_Orders    FROM dbo.Orders;       -- 19 rows
SELECT * INTO dbo.L04_Orders_Archive FROM dbo.Orders WHERE 1 = 0;   -- empty, same shape
GO
ALTER TABLE dbo.L04_Products  ADD CONSTRAINT PK_L04_Products  PRIMARY KEY (ProductID);
ALTER TABLE dbo.L04_Customers ADD CONSTRAINT PK_L04_Customers PRIMARY KEY (CustomerID);
ALTER TABLE dbo.L04_Orders    ADD CONSTRAINT PK_L04_Orders    PRIMARY KEY (OrderID);
ALTER TABLE dbo.L04_Orders    ADD CONSTRAINT FK_L04_Orders_Customers
    FOREIGN KEY (CustomerID) REFERENCES dbo.L04_Customers (CustomerID);   -- needed for the TRUNCATE demo
GO


/* ============================================================
   1. DELETE
   ============================================================ */

-- 1a. DELETE with WHERE (FROM is optional: "DELETE dbo.L04_Orders WHERE ..." also works)
SELECT COUNT(*) AS OrdersBefore FROM dbo.L04_Orders;                        -- 19
DELETE FROM dbo.L04_Orders WHERE Status = 'Cancelled';                       -- 1 row (1006)
SELECT COUNT(*) AS OrdersAfter FROM dbo.L04_Orders;                         -- 18
GO

-- 1b. DELETE ... FROM with JOIN: delete rows of one table based on another (orders of Chennai customers)
SELECT o.OrderID, c.CustomerName, c.City
FROM dbo.L04_Orders o
JOIN dbo.L04_Customers c ON c.CustomerID = o.CustomerID
WHERE c.City = 'Chennai';                                                    -- 1011, 1018 (Gaurav)
DELETE o
FROM dbo.L04_Orders o
JOIN dbo.L04_Customers c ON c.CustomerID = o.CustomerID
WHERE c.City = 'Chennai';                                                    -- 2 rows
SELECT COUNT(*) AS OrdersAfter FROM dbo.L04_Orders;                         -- 16
GO

-- 1c. DELETE with a subquery: customers who have no order left
SELECT CustomerID, CustomerName FROM dbo.L04_Customers
WHERE CustomerID NOT IN (SELECT CustomerID FROM dbo.L04_Orders);             -- 7 Gaurav (orders just deleted), 8 Hina
DELETE FROM dbo.L04_Customers
WHERE CustomerID NOT IN (SELECT CustomerID FROM dbo.L04_Orders);             -- 2 rows
SELECT COUNT(*) AS CustomersAfter FROM dbo.L04_Customers;                   -- 6
GO
-- (NOT IN is safe here because Orders.CustomerID is NOT NULL. With NULLs in the subquery NOT IN
--  returns nothing - the famous trap, Level 09. NOT EXISTS is the safer habit.)

-- 1d. OUTPUT deleted.*: see what you removed ...
DELETE FROM dbo.L04_Orders
OUTPUT deleted.OrderID, deleted.TotalAmount
WHERE TotalAmount < 5000;                                                    -- 1010 1500, 1017 4000, 1019 2500
SELECT COUNT(*) AS OrdersAfter FROM dbo.L04_Orders;                         -- 13
GO
-- ... or archive it in the same statement (OUTPUT ... INTO): the "soft delete to history" pattern
DELETE FROM dbo.L04_Orders
OUTPUT deleted.* INTO dbo.L04_Orders_Archive
WHERE OrderDate < '2025-02-01';                                              -- 3 rows: 1001, 1002, 1003
SELECT OrderID, OrderDate, TotalAmount FROM dbo.L04_Orders_Archive;         -- the 3 January orders
SELECT COUNT(*) AS OrdersAfter FROM dbo.L04_Orders;                         -- 10
GO

-- 1e. DELETE without WHERE = every row. Test inside a transaction, then ROLLBACK.
BEGIN TRAN;
    DELETE FROM dbo.L04_Orders;
    SELECT COUNT(*) AS InsideTran FROM dbo.L04_Orders;                      -- 0
ROLLBACK;
SELECT COUNT(*) AS AfterRollback FROM dbo.L04_Orders;                       -- 10
GO

-- 1f. A parent row with children cannot be deleted (FK, NO ACTION): Aarav (1) still has orders
BEGIN TRY
    DELETE FROM dbo.L04_Customers WHERE CustomerID = 1;
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO


/* ============================================================
   2. DELETE vs TRUNCATE vs DROP
   ============================================================ */
--            DELETE                      TRUNCATE                       DROP
-- removes    rows (WHERE possible)       ALL rows                       the whole table (structure too)
-- logging    every row logged            page de-allocations only       metadata
-- identity   keeps counting              resets to the seed             gone
-- triggers   DELETE triggers fire        no triggers                    no
-- FK         blocked per row             refused if ANY FK points here  refused if an FK points here
-- rollback   yes                         yes (inside a transaction)     yes (DDL is transactional in SQL Server)
-- speed      slow on big tables          very fast                      fast

-- 2a. Identity: DELETE keeps counting, TRUNCATE restarts at the seed
CREATE TABLE dbo.L04_Log
(
    LogID INT         NOT NULL IDENTITY(1,1) CONSTRAINT PK_L04_Log PRIMARY KEY,
    Note  VARCHAR(50) NOT NULL
);
INSERT INTO dbo.L04_Log (Note) VALUES ('a'), ('b'), ('c');
SELECT * FROM dbo.L04_Log;                                                   -- 1 a, 2 b, 3 c
DELETE FROM dbo.L04_Log;
INSERT INTO dbo.L04_Log (Note) VALUES ('after delete');
SELECT * FROM dbo.L04_Log;                                                   -- 4 after delete
TRUNCATE TABLE dbo.L04_Log;
INSERT INTO dbo.L04_Log (Note) VALUES ('after truncate');
SELECT * FROM dbo.L04_Log;                                                   -- 1 after truncate
GO

-- 2b. TRUNCATE has no WHERE (syntax error -> compile-time -> EXEC so CATCH can show it)
BEGIN TRY
    EXEC ('TRUNCATE TABLE dbo.L04_Log WHERE LogID = 1;');
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO

-- 2c. TRUNCATE is refused when ANY foreign key points at the table - even if no child row exists
BEGIN TRY
    TRUNCATE TABLE dbo.L04_Customers;          -- FK_L04_Orders_Customers references it
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO
-- DELETE FROM dbo.L04_Customers would also fail here, but row by row - and it would work for rows without children.

-- 2d. Myth: "TRUNCATE cannot be rolled back". In SQL Server it can, inside a transaction.
BEGIN TRAN;
    TRUNCATE TABLE dbo.L04_Log;
    SELECT COUNT(*) AS InsideTran FROM dbo.L04_Log;                         -- 0
ROLLBACK;
SELECT COUNT(*) AS AfterRollback FROM dbo.L04_Log;                          -- 1
GO

-- 2e. DROP removes the table itself
DROP TABLE dbo.L04_Log;
SELECT OBJECT_ID('dbo.L04_Log') AS ObjectIdAfterDrop;                        -- NULL = gone
DROP TABLE IF EXISTS dbo.L04_Log;                                            -- IF EXISTS: no error when already gone
GO


/* ============================================================
   3. MERGE  (upsert: INSERT + UPDATE + DELETE in one statement)
   ============================================================ */
-- MERGE target USING source ON (match) WHEN MATCHED ... WHEN NOT MATCHED BY TARGET ... WHEN NOT MATCHED BY SOURCE ...;
-- Typical use: a daily product feed (source) is applied to the product table (target).

-- 3a. The feed: 2 products we already have (changed prices), 2 new products
SELECT * INTO dbo.L04_ProductFeed FROM dbo.L04_Products WHERE 1 = 0;
INSERT INTO dbo.L04_ProductFeed (ProductID, ProductName, Category, Price, Stock) VALUES
(2,  'Mouse',     'Electronics', 1200, 150),   -- exists: price 1000 -> 1200
(11, 'Webcam',    'Electronics', 4500,  30),   -- exists: unchanged values
(12, 'USB Cable', 'Electronics',  300, 200),   -- new
(13, 'Stapler',   'Stationery',   150,  80);   -- new
SELECT ProductID, ProductName, Price, Stock FROM dbo.L04_Products WHERE ProductID IN (2, 7, 8, 11) ORDER BY ProductID;
-- before: Mouse 1000/100, Notebook 50/500, Pen 10/1000, Webcam 4500/30
GO

-- Full MERGE. NOT MATCHED BY SOURCE deletes target rows missing from the feed - restricted to Stationery
-- here on purpose (without the AND it would wipe every product not in the feed!). Note the final ';'.
MERGE dbo.L04_Products AS t
USING dbo.L04_ProductFeed AS s
      ON t.ProductID = s.ProductID
WHEN MATCHED THEN
    UPDATE SET t.Price = s.Price, t.Stock = s.Stock
WHEN NOT MATCHED BY TARGET THEN
    INSERT (ProductID, ProductName, Category, Price, Stock)
    VALUES (s.ProductID, s.ProductName, s.Category, s.Price, s.Stock)
WHEN NOT MATCHED BY SOURCE AND t.Category = 'Stationery' THEN
    DELETE
OUTPUT $action AS MergeAction, inserted.ProductID AS NewId, inserted.ProductName AS NewName,
       deleted.ProductID AS OldId, deleted.Price AS OldPrice;
-- 6 rows: UPDATE 2 (Mouse, Webcam), INSERT 2 (USB Cable, Stapler), DELETE 2 (Notebook, Pen)
GO
SELECT ProductID, ProductName, Price, Stock FROM dbo.L04_Products ORDER BY ProductID;   -- 11 rows: 7 and 8 gone, 12 and 13 new
GO

-- 3b. Upsert only (no DELETE) and "update only when something changed" - the everyday shape.
--     Running it again with the same feed changes nothing = idempotent.
MERGE dbo.L04_Products AS t
USING dbo.L04_ProductFeed AS s
      ON t.ProductID = s.ProductID
WHEN MATCHED AND (t.Price <> s.Price OR t.Stock <> s.Stock) THEN
    UPDATE SET t.Price = s.Price, t.Stock = s.Stock
WHEN NOT MATCHED BY TARGET THEN
    INSERT (ProductID, ProductName, Category, Price, Stock)
    VALUES (s.ProductID, s.ProductName, s.Category, s.Price, s.Stock)
OUTPUT $action AS MergeAction, inserted.ProductID;                          -- 0 rows
GO
UPDATE dbo.L04_ProductFeed SET Price = 1300 WHERE ProductID = 2;             -- the feed changes one price
MERGE dbo.L04_Products AS t
USING dbo.L04_ProductFeed AS s
      ON t.ProductID = s.ProductID
WHEN MATCHED AND (t.Price <> s.Price OR t.Stock <> s.Stock) THEN
    UPDATE SET t.Price = s.Price, t.Stock = s.Stock
WHEN NOT MATCHED BY TARGET THEN
    INSERT (ProductID, ProductName, Category, Price, Stock)
    VALUES (s.ProductID, s.ProductName, s.Category, s.Price, s.Stock)
OUTPUT $action AS MergeAction, inserted.ProductID, deleted.Price AS OldPrice, inserted.Price AS NewPrice;
-- 1 row: UPDATE 2, 1200.00 -> 1300.00
GO

-- 3c. GOTCHA: the source must match each target row at most ONCE, or MERGE fails (Msg 8672)
INSERT INTO dbo.L04_ProductFeed (ProductID, ProductName, Category, Price, Stock)
VALUES (2, 'Mouse', 'Electronics', 1400, 1);                                 -- ProductID 2 now twice in the feed
GO
BEGIN TRY
    MERGE dbo.L04_Products AS t
    USING dbo.L04_ProductFeed AS s ON t.ProductID = s.ProductID
    WHEN MATCHED THEN UPDATE SET t.Price = s.Price;
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO
DELETE FROM dbo.L04_ProductFeed WHERE ProductID = 2 AND Price = 1400;        -- remove the duplicate
GO

-- 3d. The same upsert WITHOUT MERGE (two plain statements - many teams prefer this)
UPDATE t
SET t.Price = s.Price, t.Stock = s.Stock
FROM dbo.L04_Products t
JOIN dbo.L04_ProductFeed s ON s.ProductID = t.ProductID
WHERE t.Price <> s.Price OR t.Stock <> s.Stock;                              -- 0 rows (already in sync)
INSERT INTO dbo.L04_Products (ProductID, ProductName, Category, Price, Stock)
SELECT s.ProductID, s.ProductName, s.Category, s.Price, s.Stock
FROM dbo.L04_ProductFeed s
WHERE NOT EXISTS (SELECT 1 FROM dbo.L04_Products t WHERE t.ProductID = s.ProductID);   -- 0 rows
GO


/* ============================================================
   4. TOP IN INSERT / UPDATE / DELETE
   ============================================================ */

-- 4a. UPDATE TOP (n) picks ARBITRARY rows (no ORDER BY allowed). To control WHICH rows: TOP + ORDER BY in a CTE.
;WITH TwoMostExpensive AS
(
    SELECT TOP (2) ProductID, ProductName, Stock
    FROM dbo.L04_Products
    ORDER BY Price DESC
)
UPDATE TwoMostExpensive
SET Stock = Stock + 1
OUTPUT inserted.ProductID, inserted.ProductName, deleted.Stock AS OldStock, inserted.Stock AS NewStock;
-- 2 rows: Laptop 10 -> 11, Monitor 25 -> 26
GO

-- 4b. INSERT TOP: put TOP (with ORDER BY) in the SELECT, not on the INSERT (INSERT TOP ignores the order)
SELECT COUNT(*) AS ArchiveBefore FROM dbo.L04_Orders_Archive;               -- 3
INSERT INTO dbo.L04_Orders_Archive (OrderID, CustomerID, EmployeeID, OrderDate, TotalAmount, Status)
SELECT TOP (2) OrderID, CustomerID, EmployeeID, OrderDate, TotalAmount, Status
FROM dbo.L04_Orders
ORDER BY OrderDate;                                                          -- the 2 oldest remaining: 1004, 1005
SELECT OrderID, OrderDate FROM dbo.L04_Orders_Archive ORDER BY OrderDate;   -- 5 rows: 1001, 1002, 1003, 1004, 1005
GO

-- 4c. DELETE TOP (n) in a loop = batching. One giant DELETE holds locks and grows the log for a long time;
--     small batches let other users work in between. (GENERATE_SERIES = SQL Server 2022+)
CREATE TABLE dbo.L04_BigLog (Id INT NOT NULL CONSTRAINT PK_L04_BigLog PRIMARY KEY, Payload CHAR(10) NOT NULL);
INSERT INTO dbo.L04_BigLog (Id, Payload)
SELECT value, 'x' FROM GENERATE_SERIES(1, 1000);
SELECT COUNT(*) AS RowsBefore FROM dbo.L04_BigLog;                           -- 1000
GO
DECLARE @batch INT = 300, @deleted INT = 1, @loops INT = 0;
WHILE @deleted > 0
BEGIN
    DELETE TOP (@batch) FROM dbo.L04_BigLog WHERE Id <= 1000;                -- the WHERE is the "old rows" rule
    SET @deleted = @@ROWCOUNT;                                               -- read it IMMEDIATELY after the DELETE
    IF @deleted > 0
    BEGIN
        SET @loops += 1;
        PRINT 'Batch ' + CAST(@loops AS VARCHAR(5)) + ' deleted ' + CAST(@deleted AS VARCHAR(5)) + ' rows';
    END
END
-- prints: 300, 300, 300, 100
SELECT COUNT(*) AS RowsAfter FROM dbo.L04_BigLog;                            -- 0
GO


/* ============================================================
   5. CLEANUP
   ============================================================ */
DROP TABLE IF EXISTS dbo.L04_Orders_Archive;
DROP TABLE IF EXISTS dbo.L04_TopProducts;
DROP TABLE IF EXISTS dbo.L04_Log;
DROP TABLE IF EXISTS dbo.L04_BigLog;
DROP TABLE IF EXISTS dbo.L04_ProductFeed;
DROP TABLE IF EXISTS dbo.L04_Orders;
DROP TABLE IF EXISTS dbo.L04_Customers;
DROP TABLE IF EXISTS dbo.L04_Products;
GO
/* DONE. Next: Exercises.sql */
