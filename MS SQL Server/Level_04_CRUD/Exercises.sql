/* ============================================================
   LEVEL 04 - CRUD  |  Exercises.sql
   ------------------------------------------------------------
   Try each question in the "YOUR ANSWERS" area FIRST.
   Then scroll down to SOLUTIONS and compare.
   Run the SETUP block first: it builds the copies you may change
   (dbo.L04_Products, dbo.L04_Customers, dbo.L04_Orders).
   The base tables are never modified. The last block drops the copies.
   ============================================================ */

USE SQLPractice;
GO

/* ---------- SETUP (run first, and again any time you want fresh copies) ---------- */
DROP TABLE IF EXISTS dbo.L04_Ex_Numbers;
DROP TABLE IF EXISTS dbo.L04_Orders_2025Q1;
DROP TABLE IF EXISTS dbo.L04_ProductFeed;
DROP TABLE IF EXISTS dbo.L04_Orders;
DROP TABLE IF EXISTS dbo.L04_Customers;
DROP TABLE IF EXISTS dbo.L04_Products;
GO
SELECT * INTO dbo.L04_Products  FROM dbo.Products;
SELECT * INTO dbo.L04_Customers FROM dbo.Customers;
SELECT * INTO dbo.L04_Orders    FROM dbo.Orders;
ALTER TABLE dbo.L04_Products  ADD CONSTRAINT PK_L04_Products  PRIMARY KEY (ProductID);
ALTER TABLE dbo.L04_Customers ADD CONSTRAINT PK_L04_Customers PRIMARY KEY (CustomerID);
ALTER TABLE dbo.L04_Orders    ADD CONSTRAINT PK_L04_Orders    PRIMARY KEY (OrderID);
GO

/* ------------------------------------------------------------
   QUESTIONS
   ------------------------------------------------------------
   Q1.  Insert product 12 'USB Cable', Electronics, price 300, stock 200
        into dbo.L04_Products. Show the row.

   Q2.  Insert TWO customers with ONE statement into dbo.L04_Customers:
        (9, 'Isha Verma', 'isha@example.com', 'Delhi', today)
        (10, 'Jai Mehta', 'jai@example.com', 'Pune', today).
        Show the customer count.

   Q3.  Create dbo.L04_Orders_2025Q1 with SELECT ... INTO containing the
        orders from January to March 2025 (from dbo.L04_Orders). How many rows?
        Prove that the new table has no constraints.

   Q4.  Add the April 2025 orders to dbo.L04_Orders_2025Q1 with INSERT ... SELECT.
        How many rows now?

   Q5.  Raise the price of every Electronics product in dbo.L04_Products by 5 %
        and show old and new price with OUTPUT. How many rows?

   Q6.  UPDATE with JOIN: set Status = 'Completed' for every Pending order
        whose customer lives in Delhi (dbo.L04_Orders / dbo.L04_Customers).
        Which orders changed?

   Q7.  UPDATE with subquery: set Stock = 0 in dbo.L04_Products for every
        product that has never been ordered (use dbo.OrderDetails, read-only).
        Which products?

   Q8.  Delete the cancelled orders from dbo.L04_Orders and return the deleted
        OrderID and TotalAmount with OUTPUT.

   Q9.  DELETE with JOIN: delete every order of a customer who has no email.
        How many rows? How many orders remain?

   Q10. Add FK_L04_Orders_Customers (L04_Orders.CustomerID -> L04_Customers).
        Try TRUNCATE TABLE dbo.L04_Customers inside TRY/CATCH (why does it
        fail?). Then TRUNCATE dbo.L04_Orders_2025Q1 and show its count.

   Q11. MERGE: build dbo.L04_ProductFeed (same shape as L04_Products) with
        (2, 'Mouse', 'Electronics', 900, 120) and (13, 'Stapler', 'Stationery', 150, 80).
        Merge it into dbo.L04_Products: update price/stock when matched,
        insert when not matched. Show $action for each row.

   Q12. Batch delete: create dbo.L04_Ex_Numbers (N INT PK) with 500 rows,
        then delete everything in batches of 200 with DELETE TOP in a loop,
        printing the number of rows each batch removed.
   ------------------------------------------------------------ */

-- YOUR ANSWERS HERE (write below, run, compare)










/* ============================================================
   SOLUTIONS
   ============================================================ */

-- Q1
INSERT INTO dbo.L04_Products (ProductID, ProductName, Category, Price, Stock)
VALUES (12, 'USB Cable', 'Electronics', 300, 200);
SELECT * FROM dbo.L04_Products WHERE ProductID = 12;
GO

-- Q2
INSERT INTO dbo.L04_Customers (CustomerID, CustomerName, Email, City, CreatedDate)
VALUES (9,  'Isha Verma', 'isha@example.com', 'Delhi', CAST(GETDATE() AS DATE)),
       (10, 'Jai Mehta',  'jai@example.com',  'Pune',  CAST(GETDATE() AS DATE));
SELECT COUNT(*) AS CustomerCount FROM dbo.L04_Customers;                     -- 10
GO

-- Q3
SELECT * INTO dbo.L04_Orders_2025Q1
FROM dbo.L04_Orders
WHERE OrderDate >= '2025-01-01' AND OrderDate < '2025-04-01';
SELECT COUNT(*) AS Q1Orders FROM dbo.L04_Orders_2025Q1;                       -- 8 (1001 .. 1008)
SELECT COUNT(*) AS ConstraintCount
FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS WHERE TABLE_NAME = 'L04_Orders_2025Q1';   -- 0
GO

-- Q4
INSERT INTO dbo.L04_Orders_2025Q1 (OrderID, CustomerID, EmployeeID, OrderDate, TotalAmount, Status)
SELECT OrderID, CustomerID, EmployeeID, OrderDate, TotalAmount, Status
FROM dbo.L04_Orders
WHERE OrderDate >= '2025-04-01' AND OrderDate < '2025-05-01';                -- 1009, 1010
SELECT COUNT(*) AS RowsNow FROM dbo.L04_Orders_2025Q1;                        -- 10
GO

-- Q5
UPDATE dbo.L04_Products
SET Price = Price * 1.05
OUTPUT deleted.ProductName, deleted.Price AS OldPrice, inserted.Price AS NewPrice
WHERE Category = 'Electronics';
-- 7 rows: Laptop 78750, Mouse 1050, Keyboard 2625, Monitor 26250, Headphones 3150, Webcam 4725, USB Cable 315
GO

-- Q6
SELECT o.OrderID, c.CustomerName, o.Status
FROM dbo.L04_Orders o JOIN dbo.L04_Customers c ON c.CustomerID = o.CustomerID
WHERE o.Status = 'Pending' AND c.City = 'Delhi';                              -- 1015 Aarav, 1017 Chirag
UPDATE o
SET o.Status = 'Completed'
FROM dbo.L04_Orders o
JOIN dbo.L04_Customers c ON c.CustomerID = o.CustomerID
WHERE o.Status = 'Pending' AND c.City = 'Delhi';                              -- 2 rows
SELECT COUNT(*) AS StillPending FROM dbo.L04_Orders WHERE Status = 'Pending'; -- 0
GO

-- Q7
UPDATE dbo.L04_Products
SET Stock = 0
WHERE NOT EXISTS (SELECT 1 FROM dbo.OrderDetails od WHERE od.ProductID = dbo.L04_Products.ProductID);
SELECT ProductID, ProductName, Stock FROM dbo.L04_Products WHERE Stock = 0 ORDER BY ProductID;
-- 9 Headphones (was already 0), 11 Webcam, 12 USB Cable   -> 2 rows were changed
GO

-- Q8
DELETE FROM dbo.L04_Orders
OUTPUT deleted.OrderID, deleted.TotalAmount
WHERE Status = 'Cancelled';                                                   -- 1006  8000.00
GO

-- Q9
DELETE o
FROM dbo.L04_Orders o
JOIN dbo.L04_Customers c ON c.CustomerID = o.CustomerID
WHERE c.Email IS NULL;                                                        -- 2 rows (Farhan: 1008, 1016; Hina has none)
SELECT COUNT(*) AS OrdersLeft FROM dbo.L04_Orders;                            -- 16
GO

-- Q10
ALTER TABLE dbo.L04_Orders ADD CONSTRAINT FK_L04_Orders_Customers
    FOREIGN KEY (CustomerID) REFERENCES dbo.L04_Customers (CustomerID);
GO
BEGIN TRY
    TRUNCATE TABLE dbo.L04_Customers;    -- refused: a FOREIGN KEY references the table (even with zero child rows)
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO
TRUNCATE TABLE dbo.L04_Orders_2025Q1;    -- nothing references it -> fine
SELECT COUNT(*) AS Q1Rows FROM dbo.L04_Orders_2025Q1;                         -- 0
GO

-- Q11
SELECT * INTO dbo.L04_ProductFeed FROM dbo.L04_Products WHERE 1 = 0;
INSERT INTO dbo.L04_ProductFeed (ProductID, ProductName, Category, Price, Stock)
VALUES (2, 'Mouse', 'Electronics', 900, 120), (13, 'Stapler', 'Stationery', 150, 80);
MERGE dbo.L04_Products AS t
USING dbo.L04_ProductFeed AS s ON t.ProductID = s.ProductID
WHEN MATCHED THEN
    UPDATE SET t.Price = s.Price, t.Stock = s.Stock
WHEN NOT MATCHED BY TARGET THEN
    INSERT (ProductID, ProductName, Category, Price, Stock)
    VALUES (s.ProductID, s.ProductName, s.Category, s.Price, s.Stock)
OUTPUT $action AS MergeAction, inserted.ProductID, inserted.ProductName, inserted.Price;
-- 2 rows: UPDATE 2 Mouse 900.00, INSERT 13 Stapler 150.00
SELECT COUNT(*) AS ProductCount FROM dbo.L04_Products;                        -- 13
GO

-- Q12
CREATE TABLE dbo.L04_Ex_Numbers (N INT NOT NULL CONSTRAINT PK_L04_Ex_Numbers PRIMARY KEY);
INSERT INTO dbo.L04_Ex_Numbers (N) SELECT value FROM GENERATE_SERIES(1, 500);   -- 2022+ (or a WHILE loop)
GO
DECLARE @rows INT = 1;
WHILE @rows > 0
BEGIN
    DELETE TOP (200) FROM dbo.L04_Ex_Numbers;
    SET @rows = @@ROWCOUNT;
    IF @rows > 0 PRINT 'Deleted ' + CAST(@rows AS VARCHAR(5)) + ' rows';     -- 200, 200, 100
END
SELECT COUNT(*) AS RowsLeft FROM dbo.L04_Ex_Numbers;                          -- 0
GO

/* ---------- CLEANUP ---------- */
DROP TABLE IF EXISTS dbo.L04_Ex_Numbers;
DROP TABLE IF EXISTS dbo.L04_Orders_2025Q1;
DROP TABLE IF EXISTS dbo.L04_ProductFeed;
DROP TABLE IF EXISTS dbo.L04_Orders;
DROP TABLE IF EXISTS dbo.L04_Customers;
DROP TABLE IF EXISTS dbo.L04_Products;
GO
