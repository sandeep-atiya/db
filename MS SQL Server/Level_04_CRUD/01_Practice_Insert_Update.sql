/* ============================================================
   LEVEL 04 - CRUD  |  01_Practice_Insert_Update.sql
   ------------------------------------------------------------
   Topics : SELECT recap, INSERT (single row, multi-row VALUES,
            INSERT ... SELECT, SELECT ... INTO, DEFAULT VALUES,
            OUTPUT inserted.*), UPDATE (one / many columns, computed
            SET, UPDATE ... FROM JOIN, subquery, OUTPUT deleted/inserted)

   HOW TO PRACTICE: run block by block, predict the output first.
   ALL changes happen on COPIES (dbo.L04_Products, dbo.L04_Customers,
   dbo.L04_Orders) made with SELECT ... INTO. The 6 base tables are
   only read. Every change shows the rows BEFORE and AFTER.
   Next: 02_Practice_Delete_Truncate_Merge.sql
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

/* ---------- Make the working copies with SELECT ... INTO ---------- */
-- SELECT INTO creates a NEW table from a query result: column names, types and NULL-ability
-- are copied, the rows are copied, but NO constraints, indexes, defaults or foreign keys.
SELECT * INTO dbo.L04_Products  FROM dbo.Products;     -- 11 rows
SELECT * INTO dbo.L04_Customers FROM dbo.Customers;    -- 8 rows
SELECT * INTO dbo.L04_Orders    FROM dbo.Orders;       -- 19 rows
GO
SELECT COUNT(*) AS ConstraintsOnCopies
FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS
WHERE TABLE_NAME LIKE 'L04[_]%';                       -- 0  (nothing was copied)
GO
-- Give the copies a primary key so "update by id" behaves like the real tables (Level 03 revision)
ALTER TABLE dbo.L04_Products  ADD CONSTRAINT PK_L04_Products  PRIMARY KEY (ProductID);
ALTER TABLE dbo.L04_Customers ADD CONSTRAINT PK_L04_Customers PRIMARY KEY (CustomerID);
ALTER TABLE dbo.L04_Orders    ADD CONSTRAINT PK_L04_Orders    PRIMARY KEY (OrderID);
GO


/* ============================================================
   1. SELECT RECAP  (the R in CRUD - Level 05 goes deep)
   ============================================================ */
SELECT * FROM dbo.L04_Products;                                              -- 11 rows, all columns
SELECT ProductName, Price FROM dbo.L04_Products
WHERE Category = 'Furniture' ORDER BY Price DESC;                            -- Desk 15000, Bookshelf 12000, Chair 8000
SELECT TOP (3) ProductName, Stock FROM dbo.L04_Products ORDER BY Stock DESC; -- Pen 1000, Notebook 500, Mouse 100
GO


/* ============================================================
   2. INSERT
   ============================================================ */

-- 2a. Single row. ALWAYS write the column list: the statement keeps working if columns are added later.
SELECT COUNT(*) AS ProductsBefore FROM dbo.L04_Products;                     -- 11
INSERT INTO dbo.L04_Products (ProductID, ProductName, Category, Price, Stock)
VALUES (12, 'USB Cable', 'Electronics', 300, 200);
SELECT COUNT(*) AS ProductsAfter FROM dbo.L04_Products;                      -- 12
GO

-- 2b. Multi-row VALUES: one statement, many rows (max 1000 rows per VALUES list)
INSERT INTO dbo.L04_Products (ProductID, ProductName, Category, Price, Stock)
VALUES (13, 'Stapler', 'Stationery', 150, 80),
       (14, 'Lamp',    'Furniture', 1200, 12);
SELECT * FROM dbo.L04_Products WHERE ProductID >= 12;                        -- 3 rows: 12, 13, 14
GO

-- 2c. INSERT ... SELECT: copy rows from a query. First an empty archive table with the same shape
--     (SELECT INTO with WHERE 1 = 0 copies the structure only).
SELECT * INTO dbo.L04_Orders_Archive FROM dbo.L04_Orders WHERE 1 = 0;
SELECT COUNT(*) AS ArchiveBefore FROM dbo.L04_Orders_Archive;               -- 0
INSERT INTO dbo.L04_Orders_Archive (OrderID, CustomerID, EmployeeID, OrderDate, TotalAmount, Status)
SELECT OrderID, CustomerID, EmployeeID, OrderDate, TotalAmount, Status
FROM dbo.L04_Orders
WHERE OrderDate < '2025-02-01';                                              -- January orders
SELECT * FROM dbo.L04_Orders_Archive;                                        -- 3 rows: 1001, 1002, 1003
GO
-- The SELECT may contain expressions, joins, anything: here we clone the Delhi customers with new ids
SELECT COUNT(*) AS CustomersBefore FROM dbo.L04_Customers;                  -- 8
INSERT INTO dbo.L04_Customers (CustomerID, CustomerName, Email, City, CreatedDate)
SELECT CustomerID + 100, CustomerName + ' (copy)', NULL, City, CAST(GETDATE() AS DATE)
FROM dbo.Customers
WHERE City = 'Delhi';                                                        -- Aarav, Chirag, Hina
SELECT CustomerID, CustomerName, City FROM dbo.L04_Customers WHERE CustomerID > 100;   -- 101, 103, 108
GO

-- 2d. SELECT ... INTO new table: query result becomes a brand-new table (must NOT exist yet)
SELECT TOP (3) ProductID, ProductName, Price
INTO dbo.L04_TopProducts
FROM dbo.L04_Products
ORDER BY Price DESC;
SELECT * FROM dbo.L04_TopProducts;                                           -- Laptop 75000, Monitor 25000, Desk 15000
SELECT COUNT(*) AS ConstraintsOnNewTable
FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS WHERE TABLE_NAME = 'L04_TopProducts';   -- 0: SELECT INTO copies no constraints
GO

-- 2e. INSERT ... DEFAULT VALUES: a row made only of defaults / identity (every column must have one)
CREATE TABLE dbo.L04_Log
(
    LogID    INT          NOT NULL IDENTITY(1,1) CONSTRAINT PK_L04_Log PRIMARY KEY,
    LoggedAt DATETIME2(0) NOT NULL CONSTRAINT DF_L04_Log_LoggedAt DEFAULT (SYSDATETIME()),
    Note     VARCHAR(50)  NOT NULL CONSTRAINT DF_L04_Log_Note     DEFAULT ('ping')
);
INSERT INTO dbo.L04_Log DEFAULT VALUES;
INSERT INTO dbo.L04_Log DEFAULT VALUES;
SELECT * FROM dbo.L04_Log;                                                   -- 2 rows: LogID 1, 2, Note ping
GO

-- 2f. OUTPUT inserted.*: see (or capture) the rows you just inserted - handy for identity / default values
INSERT INTO dbo.L04_Products (ProductID, ProductName, Category, Price, Stock)
OUTPUT inserted.ProductID, inserted.ProductName, inserted.Price
VALUES (15, 'Router', 'Electronics', 3500, 40);                              -- shows 15 Router 3500.00
GO
-- OUTPUT ... INTO a table variable: keep the values for later use in the same batch
DECLARE @Added TABLE (ProductID INT, ProductName VARCHAR(100));
INSERT INTO dbo.L04_Products (ProductID, ProductName, Category, Price, Stock)
OUTPUT inserted.ProductID, inserted.ProductName INTO @Added
VALUES (16, 'Printer', 'Electronics', 9000, 8);
SELECT * FROM @Added;                                                        -- 16 Printer
SELECT COUNT(*) AS ProductsNow FROM dbo.L04_Products;                        -- 16
GO

-- 2g. Typical INSERT errors
-- (i) wrong number of values (compile-time error -> EXEC lets CATCH see it; real message Msg 213)
BEGIN TRY
    EXEC ('INSERT INTO dbo.L04_Products (ProductID, ProductName, Category, Price, Stock) VALUES (17, ''Scanner'', ''Electronics'', 6000);');
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO
-- (ii) duplicate primary key
BEGIN TRY
    INSERT INTO dbo.L04_Products (ProductID, ProductName, Category, Price, Stock)
    VALUES (12, 'USB Cable again', 'Electronics', 300, 200);
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO
-- (iii) value too long for the column (ProductName is VARCHAR(100))
BEGIN TRY
    INSERT INTO dbo.L04_Products (ProductID, ProductName, Category, Price, Stock)
    VALUES (17, REPLICATE('x', 101), 'Electronics', 6000, 1);
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO


/* ============================================================
   3. UPDATE
   ============================================================ */

-- 3a. One column, one row (filter on the primary key)
SELECT ProductID, ProductName, Price FROM dbo.L04_Products WHERE ProductID = 2;   -- Mouse 1000.00
UPDATE dbo.L04_Products SET Price = 1100 WHERE ProductID = 2;
SELECT ProductID, ProductName, Price FROM dbo.L04_Products WHERE ProductID = 2;   -- Mouse 1100.00
GO

-- 3b. Several columns in one statement (comma separated, ONE SET keyword)
SELECT ProductName, Price, Stock FROM dbo.L04_Products WHERE ProductID = 3;       -- Keyboard 2500 / 50
UPDATE dbo.L04_Products
SET Price = 2600,
    Stock = Stock - 5
WHERE ProductID = 3;
SELECT ProductName, Price, Stock FROM dbo.L04_Products WHERE ProductID = 3;       -- Keyboard 2600 / 45
GO

-- 3c. Computed SET: the new value is calculated from the OLD value of the row
SELECT ProductName, Price FROM dbo.L04_Products WHERE Category = 'Stationery';    -- Notebook 50, Pen 10, Stapler 150
UPDATE dbo.L04_Products SET Price = Price * 1.1 WHERE Category = 'Stationery';     -- +10 %
SELECT ProductName, Price FROM dbo.L04_Products WHERE Category = 'Stationery';    -- 55.00, 11.00, 165.00
GO
-- Every expression in SET reads the OLD row values, so a swap needs no temp variable:
UPDATE dbo.L04_Products SET Price = Stock, Stock = Price WHERE ProductID = 2;
SELECT ProductName, Price, Stock FROM dbo.L04_Products WHERE ProductID = 2;       -- Mouse 100.00 / 1100  (swapped!)
UPDATE dbo.L04_Products SET Price = Stock, Stock = Price WHERE ProductID = 2;      -- swap back
SELECT ProductName, Price, Stock FROM dbo.L04_Products WHERE ProductID = 2;       -- Mouse 1100.00 / 100
GO

-- 3d. UPDATE without WHERE changes EVERY row. Habit: test inside a transaction, then ROLLBACK.
BEGIN TRAN;
    UPDATE dbo.L04_Products SET Stock = 0;
    SELECT COUNT(*) AS ZeroStockInsideTran FROM dbo.L04_Products WHERE Stock = 0;  -- 16 (all rows)
ROLLBACK;
SELECT COUNT(*) AS ZeroStockAfterRollback FROM dbo.L04_Products WHERE Stock = 0;   -- 1 (only Headphones)
GO

-- 3e. UPDATE ... FROM with JOIN: change rows of one table using a condition on another table.
--     Give a 10 % discount on every order placed by a Mumbai customer (Bhavna 2, Farhan 6).
SELECT o.OrderID, c.CustomerName, o.TotalAmount
FROM dbo.L04_Orders o
JOIN dbo.L04_Customers c ON c.CustomerID = o.CustomerID
WHERE c.City = 'Mumbai' ORDER BY o.OrderID;    -- 6 rows: 1002 10000, 1007 6000, 1008 78500, 1012 30000, 1016 10000, 1019 2500
UPDATE o
SET o.TotalAmount = o.TotalAmount * 0.9
FROM dbo.L04_Orders o
JOIN dbo.L04_Customers c ON c.CustomerID = o.CustomerID
WHERE c.City = 'Mumbai';                        -- 6 rows affected
SELECT o.OrderID, c.CustomerName, o.TotalAmount
FROM dbo.L04_Orders o
JOIN dbo.L04_Customers c ON c.CustomerID = o.CustomerID
WHERE c.City = 'Mumbai' ORDER BY o.OrderID;    -- 9000, 5400, 70650, 27000, 9000, 2250
GO
-- Tip: write "UPDATE alias" (UPDATE o) so it is obvious which table changes.

-- 3f. UPDATE with a subquery
-- (i) correlated subquery in SET: put the ORIGINAL prices back on the stationery rows that exist in dbo.Products
UPDATE p
SET p.Price = (SELECT b.Price FROM dbo.Products b WHERE b.ProductID = p.ProductID)
FROM dbo.L04_Products p
WHERE p.Category = 'Stationery'
  AND p.ProductID IN (SELECT ProductID FROM dbo.Products);                   -- 2 rows (Notebook, Pen)
SELECT ProductName, Price FROM dbo.L04_Products WHERE Category = 'Stationery';   -- 50.00, 10.00, 165.00 (Stapler untouched)
GO
-- (ii) subquery in WHERE: +10 stock for every product that appears in order 1008 (Laptop, Mouse, Keyboard)
SELECT ProductID, ProductName, Stock FROM dbo.L04_Products WHERE ProductID IN (1, 2, 3);   -- 10 / 100 / 45
UPDATE dbo.L04_Products
SET Stock = Stock + 10
WHERE ProductID IN (SELECT ProductID FROM dbo.OrderDetails WHERE OrderID = 1008);
SELECT ProductID, ProductName, Stock FROM dbo.L04_Products WHERE ProductID IN (1, 2, 3);   -- 20 / 110 / 55
GO

-- 3g. OUTPUT deleted.* / inserted.* on UPDATE: "deleted" = the row BEFORE, "inserted" = the row AFTER
UPDATE dbo.L04_Products
SET Price = Price * 1.05
OUTPUT deleted.ProductID, deleted.ProductName, deleted.Price AS OldPrice, inserted.Price AS NewPrice
WHERE Category = 'Furniture';
-- 4 rows: Chair 8000 -> 8400.00, Desk 15000 -> 15750.00, Bookshelf 12000 -> 12600.00, Lamp 1200 -> 1260.00
GO

-- 3h. Remember: SELECT INTO copied NO constraints. The copy accepts what the real table refuses.
UPDATE dbo.L04_Products SET Stock = -5 WHERE ProductID = 9;                        -- works on the copy!
SELECT ProductName, Stock FROM dbo.L04_Products WHERE ProductID = 9;               -- Headphones -5
UPDATE dbo.L04_Products SET Stock = 0  WHERE ProductID = 9;                        -- repair
GO
BEGIN TRAN;   -- the real table has CK_Products_Stock; the statement fails and we roll back anyway
BEGIN TRY
    UPDATE dbo.Products SET Stock = -5 WHERE ProductID = 9;
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
ROLLBACK;
SELECT ProductName, Stock FROM dbo.Products WHERE ProductID = 9;                   -- Headphones 0 (unchanged)
GO


/* ============================================================
   4. CLEANUP
   ============================================================ */
DROP TABLE IF EXISTS dbo.L04_Orders_Archive;
DROP TABLE IF EXISTS dbo.L04_TopProducts;
DROP TABLE IF EXISTS dbo.L04_Log;
DROP TABLE IF EXISTS dbo.L04_Orders;
DROP TABLE IF EXISTS dbo.L04_Customers;
DROP TABLE IF EXISTS dbo.L04_Products;
GO
/* DONE. Next: 02_Practice_Delete_Truncate_Merge.sql */
