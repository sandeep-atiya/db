/* ============================================================
   LEVEL 12 - TEMPORARY OBJECTS  |  Exercises.sql
   ------------------------------------------------------------
   Try each question in the "YOUR ANSWERS" area FIRST.
   Then scroll down to SOLUTIONS and compare.
   Everything runs in ONE window against SQLPractice.
   ============================================================ */

USE SQLPractice;
GO

/* ------------------------------------------------------------
   QUESTIONS
   ------------------------------------------------------------
   Q1.  Using SELECT ... INTO, create a local temp table #L12_HighPaid with
        EmployeeID, EmployeeName, Salary of employees earning MORE than 65000.
        How many rows does it have?

   Q2.  Add a PRIMARY KEY on EmployeeID to #L12_HighPaid (ALTER TABLE), then
        try to insert EmployeeID 101 again inside TRY / CATCH.

   Q3.  Show the real name of #L12_HighPaid inside tempdb.sys.tables and the
        length of that name.

   Q4.  Declare a table variable @Status (Status VARCHAR(20) PRIMARY KEY, Cnt INT),
        fill it from dbo.Orders grouped by Status, and select it.

   Q5.  PREDICT FIRST, then run: create #L12_A (n INT) and DECLARE @B TABLE (n INT).
        Inside ONE BEGIN TRAN insert 5 rows into each, ROLLBACK, then count both.

   Q6.  Create dbo.usp_L12_GetOrders (@CustomerID INT) that returns OrderID,
        OrderDate, TotalAmount, Status. Capture its output for customers 2 AND 3
        into ONE temp table with INSERT ... EXEC and show the row count and grand total.

   Q7.  Stage-then-join: put revenue per product (SUM(Quantity * UnitPrice) from
        dbo.OrderDetails) into #L12_ProductRevenue, add a PK on ProductID, then join
        to dbo.Products to show the TOP 3 products by revenue with their Category.

   Q8.  Global temp table: create ##L12_Cities holding the DISTINCT customer cities,
        prove in tempdb.sys.tables that its name is stored exactly (no padding),
        then drop it.

   Q9.  TVP: create a table type dbo.L12_ProductIdList (ProductID INT PRIMARY KEY)
        and a proc dbo.usp_L12_ProductsByIds that takes it READONLY and returns
        ProductName and Price for those IDs. Call it with 1, 6 and 11.

   Q10. Show how many tempdb pages YOUR session has allocated and deallocated for
        user objects (sys.dm_db_session_space_usage).

   Q11. (Interview) Inside a transaction, log 2 steps into a table variable @Log AND
        the same 2 steps into a temp table #L12_Log, then ROLLBACK. Which log
        survives? Write the query that proves it.

   Q12. (Interview - answer as a comment) Which object would you use for:
        a) a 5-row lookup list inside a small procedure
        b) 2 million staged rows that are joined 3 times in a report
        c) a recursive "who reports to whom" query
        d) a scratch result a colleague must read from ANOTHER query window
   ------------------------------------------------------------ */

-- YOUR ANSWERS HERE (write below, run, compare)










/* ============================================================
   SOLUTIONS
   ============================================================ */

-- Q1
DROP TABLE IF EXISTS #L12_HighPaid;
SELECT e.EmployeeID, e.EmployeeName, e.Salary
INTO #L12_HighPaid
FROM dbo.Employees e
WHERE e.Salary > 65000;
SELECT * FROM #L12_HighPaid;   -- 5 rows: Rahul 85000, Priya 75000, Sneha 90000, Karan 70000, Deepak 72000
GO

-- Q2
ALTER TABLE #L12_HighPaid ADD PRIMARY KEY (EmployeeID);   -- unnamed: safe for temp tables
BEGIN TRY
    INSERT INTO #L12_HighPaid (EmployeeID, EmployeeName, Salary) VALUES (101, 'Rahul again', 1);
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();   -- Violation of PRIMARY KEY constraint ...
END CATCH
GO

-- Q3
SELECT name, LEN(name) AS NameLength
FROM tempdb.sys.tables
WHERE name LIKE '#L12[_]HighPaid%';   -- #L12_HighPaid______..._____00000000xxxx , 128
GO

-- Q4
DECLARE @Status TABLE (Status VARCHAR(20) NOT NULL PRIMARY KEY, Cnt INT NOT NULL);
INSERT INTO @Status (Status, Cnt)
SELECT o.Status, COUNT(*) FROM dbo.Orders o GROUP BY o.Status;
SELECT * FROM @Status;   -- 3 rows: Cancelled 1, Completed 16, Pending 2
GO

-- Q5
DROP TABLE IF EXISTS #L12_A;
CREATE TABLE #L12_A (n INT);
DECLARE @B TABLE (n INT);
BEGIN TRAN;
    INSERT INTO #L12_A SELECT value FROM GENERATE_SERIES(1, 5);
    INSERT INTO @B     SELECT value FROM GENERATE_SERIES(1, 5);
ROLLBACK TRAN;
SELECT (SELECT COUNT(*) FROM #L12_A) AS TempTableRows,   -- 0
       (SELECT COUNT(*) FROM @B)     AS TableVarRows;    -- 5  (table variables are not rolled back)
GO

-- Q6
CREATE OR ALTER PROCEDURE dbo.usp_L12_GetOrders
    @CustomerID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT o.OrderID, o.OrderDate, o.TotalAmount, o.Status
    FROM dbo.Orders o
    WHERE o.CustomerID = @CustomerID;
END
GO
DROP TABLE IF EXISTS #L12_Captured;
CREATE TABLE #L12_Captured (OrderID INT, OrderDate DATE, TotalAmount DECIMAL(12,2), Status VARCHAR(20));
INSERT INTO #L12_Captured EXEC dbo.usp_L12_GetOrders @CustomerID = 2;
INSERT INTO #L12_Captured EXEC dbo.usp_L12_GetOrders @CustomerID = 3;
SELECT COUNT(*) AS Orders, SUM(TotalAmount) AS GrandTotal FROM #L12_Captured;   -- 7 , 79000.00
GO

-- Q7
DROP TABLE IF EXISTS #L12_ProductRevenue;
SELECT od.ProductID, SUM(od.Quantity * od.UnitPrice) AS Revenue
INTO #L12_ProductRevenue
FROM dbo.OrderDetails od
GROUP BY od.ProductID;
ALTER TABLE #L12_ProductRevenue ADD PRIMARY KEY (ProductID);

SELECT TOP (3) p.ProductName, p.Category, r.Revenue
FROM #L12_ProductRevenue r
JOIN dbo.Products p ON p.ProductID = r.ProductID
ORDER BY r.Revenue DESC;   -- Laptop Electronics 300000, Monitor Electronics 175000, Chair Furniture 48000
GO

-- Q8
DROP TABLE IF EXISTS ##L12_Cities;
SELECT DISTINCT c.City INTO ##L12_Cities FROM dbo.Customers c;
SELECT COUNT(*) AS Cities FROM ##L12_Cities;                             -- 5
SELECT name, LEN(name) AS NameLength FROM tempdb.sys.tables WHERE name = '##L12_Cities';   -- ##L12_Cities , 12
DROP TABLE ##L12_Cities;
GO

-- Q9
DROP PROCEDURE IF EXISTS dbo.usp_L12_ProductsByIds;
DROP TYPE IF EXISTS dbo.L12_ProductIdList;
GO
CREATE TYPE dbo.L12_ProductIdList AS TABLE (ProductID INT NOT NULL PRIMARY KEY);
GO
CREATE OR ALTER PROCEDURE dbo.usp_L12_ProductsByIds
    @Ids dbo.L12_ProductIdList READONLY
AS
BEGIN
    SET NOCOUNT ON;
    SELECT p.ProductName, p.Price
    FROM dbo.Products p
    JOIN @Ids i ON i.ProductID = p.ProductID
    ORDER BY p.ProductID;
END
GO
DECLARE @Ids dbo.L12_ProductIdList;
INSERT INTO @Ids (ProductID) VALUES (1), (6), (11);
EXEC dbo.usp_L12_ProductsByIds @Ids = @Ids;   -- Laptop 75000, Monitor 25000, Webcam 4500
GO

-- Q10
SELECT session_id, user_objects_alloc_page_count, user_objects_dealloc_page_count
FROM sys.dm_db_session_space_usage
WHERE session_id = @@SPID;   -- numbers depend on what you ran; alloc >= dealloc
GO

-- Q11
DROP TABLE IF EXISTS #L12_Log;
CREATE TABLE #L12_Log (Step VARCHAR(50));
DECLARE @Log TABLE (Step VARCHAR(50));
BEGIN TRAN;
    INSERT INTO @Log     VALUES ('step 1'), ('step 2');
    INSERT INTO #L12_Log VALUES ('step 1'), ('step 2');
ROLLBACK TRAN;
SELECT (SELECT COUNT(*) FROM @Log)     AS TableVarLogRows,    -- 2  -> survives, use it for error logging
       (SELECT COUNT(*) FROM #L12_Log) AS TempTableLogRows;   -- 0  -> rolled back
GO

-- Q12
/*
 a) @table variable  - tiny, batch-scoped, no statistics needed, no recompiles
 b) #temp table      - big set, needs statistics + indexes, reused 3 times (compute once)
 c) CTE              - recursive CTE is the only one of the four that can recurse
 d) ##global temp    - the only one visible from another session (or use a real table)
*/

-- CLEANUP
DROP TABLE IF EXISTS #L12_HighPaid, #L12_A, #L12_Captured, #L12_ProductRevenue, #L12_Log, ##L12_Cities;
DROP PROCEDURE IF EXISTS dbo.usp_L12_GetOrders, dbo.usp_L12_ProductsByIds;
DROP TYPE IF EXISTS dbo.L12_ProductIdList;
GO
