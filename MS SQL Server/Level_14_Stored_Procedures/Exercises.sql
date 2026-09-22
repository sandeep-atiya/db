/* ============================================================
   LEVEL 14 - STORED PROCEDURES  |  Exercises.sql
   ------------------------------------------------------------
   Try each question in the "YOUR ANSWERS" area FIRST.
   Then scroll down to SOLUTIONS and compare.
   Data changes happen only on the copy table dbo.L14_Products.
   ============================================================ */

USE SQLPractice;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ------------------------------------------------------------
   QUESTIONS
   ------------------------------------------------------------
   Q1.  Create dbo.usp_L14_EmployeesByDept (@DepartmentID INT) that returns
        EmployeeID, EmployeeName, Salary for that department, highest salary
        first. Call it for department 2.

   Q2.  Make @DepartmentID optional (default NULL): when omitted, return ALL
        employees. Call it twice (with and without the argument) and count.

   Q3.  Create dbo.usp_L14_DeptStats (@DepartmentID INT, @Headcount INT OUTPUT,
        @AvgSalary DECIMAL(12,2) OUTPUT). Call it for department 1 and print
        both outputs.

   Q4.  Create dbo.usp_L14_CheckStock (@ProductID INT) that RETURNs 0 if the
        product has stock > 0, 1 if stock = 0, and 2 if the product does not
        exist. Capture the return code for products 1, 9 and 999.

   Q5.  Create dbo.usp_L14_OrderSummary (@OrderID INT) that returns TWO result
        sets: the order header (from dbo.Orders) and its lines (from
        dbo.OrderDetails joined to dbo.Products). Run it for order 1008.

   Q6.  On a copy table dbo.L14_Products (SELECT * INTO ... FROM dbo.Products),
        create dbo.usp_L14_RaisePrice (@Category VARCHAR(100), @Pct DECIMAL(5,2))
        that increases Price by @Pct percent for that category, inside a
        transaction with TRY/CATCH + ROLLBACK. Raise Electronics by 10%. Show the
        new Laptop price. (Base dbo.Products must stay unchanged.)

   Q7.  Add validation to Q6: if @Pct is negative or > 100, THROW error 50050
        'Percent out of range (0-100).' and do not change anything. Test with
        @Pct = 250 inside TRY/CATCH.

   Q8.  Write a safe dynamic-SQL proc dbo.usp_L14_CountRows (@TableName SYSNAME)
        that returns the row count of any table in dbo, using QUOTENAME and
        sp_executesql with an OUTPUT parameter. Run it for 'Orders' and
        'OrderDetails'.

   Q9.  Show the SQL injection problem: build a query with EXEC + string
        concatenation for City = ''' OR 1=1 --' and show it returns all 8
        customers; then show the parameterised sp_executesql version returns 0.

   Q10. List all procedures whose name starts with usp_L14_ together with their
        parameter count (join sys.procedures to sys.parameters).

   Q11. (Interview - answer as a comment) Difference between THROW and RAISERROR?
        And why prefix a proc usp_ and never sp_?
   ------------------------------------------------------------ */

-- YOUR ANSWERS HERE (write below, run, compare)










/* ============================================================
   SOLUTIONS
   ============================================================ */

-- Q1
CREATE OR ALTER PROCEDURE dbo.usp_L14_EmployeesByDept
    @DepartmentID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT EmployeeID, EmployeeName, Salary
    FROM dbo.Employees
    WHERE DepartmentID = @DepartmentID
    ORDER BY Salary DESC;
END
GO
EXEC dbo.usp_L14_EmployeesByDept @DepartmentID = 2;   -- Priya 75000, Vikram 62000, Neha 55000
GO

-- Q2
CREATE OR ALTER PROCEDURE dbo.usp_L14_EmployeesByDept
    @DepartmentID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT EmployeeID, EmployeeName, Salary
    FROM dbo.Employees
    WHERE (@DepartmentID IS NULL OR DepartmentID = @DepartmentID)
    ORDER BY Salary DESC;
END
GO
EXEC dbo.usp_L14_EmployeesByDept @DepartmentID = 2;   -- 3 rows
EXEC dbo.usp_L14_EmployeesByDept;                     -- 12 rows (all employees)
GO

-- Q3
CREATE OR ALTER PROCEDURE dbo.usp_L14_DeptStats
    @DepartmentID INT,
    @Headcount    INT OUTPUT,
    @AvgSalary    DECIMAL(12,2) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT @Headcount = COUNT(*), @AvgSalary = AVG(Salary)
    FROM dbo.Employees WHERE DepartmentID = @DepartmentID;
END
GO
DECLARE @h INT, @a DECIMAL(12,2);
EXEC dbo.usp_L14_DeptStats @DepartmentID = 1, @Headcount = @h OUTPUT, @AvgSalary = @a OUTPUT;
SELECT @h AS Headcount, @a AS AvgSalary;   -- 3 , 71666.67
GO

-- Q4
CREATE OR ALTER PROCEDURE dbo.usp_L14_CheckStock
    @ProductID INT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM dbo.Products WHERE ProductID = @ProductID)
        RETURN 2;                                                     -- not found
    IF (SELECT Stock FROM dbo.Products WHERE ProductID = @ProductID) = 0
        RETURN 1;                                                     -- out of stock
    RETURN 0;                                                         -- in stock
END
GO
DECLARE @r1 INT, @r2 INT, @r3 INT;
EXEC @r1 = dbo.usp_L14_CheckStock @ProductID = 1;     -- 0 (Laptop, stock 10)
EXEC @r2 = dbo.usp_L14_CheckStock @ProductID = 9;     -- 1 (Headphones, stock 0)
EXEC @r3 = dbo.usp_L14_CheckStock @ProductID = 999;   -- 2 (does not exist)
SELECT @r1 AS Laptop, @r2 AS Headphones, @r3 AS Missing;
GO

-- Q5
CREATE OR ALTER PROCEDURE dbo.usp_L14_OrderSummary
    @OrderID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT OrderID, CustomerID, EmployeeID, OrderDate, TotalAmount, Status
    FROM dbo.Orders WHERE OrderID = @OrderID;
    SELECT od.ProductID, p.ProductName, od.Quantity, od.UnitPrice,
           od.Quantity * od.UnitPrice AS LineTotal
    FROM dbo.OrderDetails od
    JOIN dbo.Products p ON p.ProductID = od.ProductID
    WHERE od.OrderID = @OrderID
    ORDER BY od.ProductID;
END
GO
EXEC dbo.usp_L14_OrderSummary @OrderID = 1008;
-- set1: 1008 / cust 6 / emp 109 / 78500.00 / Completed
-- set2: Laptop 1x75000, Mouse 1x1000, Keyboard 1x2500  (line totals 75000, 1000, 2500)
GO

-- Q6
DROP PROCEDURE IF EXISTS dbo.usp_L14_RaisePrice;
DROP TABLE IF EXISTS dbo.L14_Products;
SELECT * INTO dbo.L14_Products FROM dbo.Products;
ALTER TABLE dbo.L14_Products ADD CONSTRAINT PK_L14_Products PRIMARY KEY (ProductID);
GO
CREATE OR ALTER PROCEDURE dbo.usp_L14_RaisePrice
    @Category VARCHAR(100),
    @Pct      DECIMAL(5,2)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRAN;
            UPDATE dbo.L14_Products
            SET Price = Price * (1 + @Pct / 100.0)
            WHERE Category = @Category;
        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        THROW;
    END CATCH
END
GO
EXEC dbo.usp_L14_RaisePrice @Category = 'Electronics', @Pct = 10;
SELECT ProductName, Price FROM dbo.L14_Products WHERE ProductID = 1;   -- Laptop 82500.00
SELECT ProductName, Price FROM dbo.Products     WHERE ProductID = 1;   -- Laptop 75000.00 (base unchanged)
GO

-- Q7
CREATE OR ALTER PROCEDURE dbo.usp_L14_RaisePrice
    @Category VARCHAR(100),
    @Pct      DECIMAL(5,2)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @Pct < 0 OR @Pct > 100
        THROW 50050, 'Percent out of range (0-100).', 1;
    BEGIN TRY
        BEGIN TRAN;
            UPDATE dbo.L14_Products SET Price = Price * (1 + @Pct / 100.0) WHERE Category = @Category;
        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        THROW;
    END CATCH
END
GO
BEGIN TRY
    EXEC dbo.usp_L14_RaisePrice @Category = 'Electronics', @Pct = 250;
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR ' + CAST(ERROR_NUMBER() AS VARCHAR(10)) + ': ' + ERROR_MESSAGE();   -- 50050
END CATCH
SELECT ProductName, Price FROM dbo.L14_Products WHERE ProductID = 1;   -- still 82500.00 (nothing changed)
GO

-- Q8
CREATE OR ALTER PROCEDURE dbo.usp_L14_CountRows
    @TableName SYSNAME
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @sql NVARCHAR(300) = N'SELECT @c = COUNT(*) FROM dbo.' + QUOTENAME(@TableName);
    DECLARE @c INT;
    EXEC sp_executesql @sql, N'@c INT OUTPUT', @c = @c OUTPUT;
    SELECT @TableName AS TableName, @c AS RowCnt;
END
GO
EXEC dbo.usp_L14_CountRows @TableName = 'Orders';        -- 19
EXEC dbo.usp_L14_CountRows @TableName = 'OrderDetails';  -- 26
GO

-- Q9
DECLARE @City VARCHAR(100) = ''' OR 1=1 --';
DECLARE @sql NVARCHAR(400) = N'SELECT COUNT(*) AS Unsafe FROM dbo.Customers WHERE City = ''' + @City + '''';
EXEC (@sql);   -- 8 : injection returns every customer
EXEC sp_executesql
     N'SELECT COUNT(*) AS Safe FROM dbo.Customers WHERE City = @City',
     N'@City VARCHAR(100)', @City = @City;   -- 0 : parameterised, safe
GO

-- Q10
SELECT p.name AS ProcName, COUNT(pa.parameter_id) AS ParameterCount
FROM sys.procedures p
LEFT JOIN sys.parameters pa ON pa.object_id = p.object_id
WHERE p.name LIKE 'usp[_]L14[_]%'
GROUP BY p.name
ORDER BY p.name;
-- CheckStock 1, CountRows 1, DeptStats 3, EmployeesByDept 1, OrderSummary 1, RaisePrice 2
GO

-- Q11
/*
 THROW vs RAISERROR:
   THROW (2012+) - custom number must be >= 50000, no message formatting, severity always
   16, re-raises the original error with a bare "THROW;", ends the batch, needs a ';' before
   it. RAISERROR (older) - can FORMAT the message (%s, %d), lets you pick the severity,
   cannot re-raise as-is, execution continues. Prefer THROW for new code.

 usp_ not sp_:
   SQL Server treats an sp_-prefixed proc as a system proc and looks it up in master FIRST,
   which adds overhead, risks a recompile, and can be shadowed by a real Microsoft system
   proc of the same name. usp_ (user stored proc) avoids all of that and reads clearly.
*/

-- CLEANUP
DROP PROCEDURE IF EXISTS dbo.usp_L14_EmployeesByDept, dbo.usp_L14_DeptStats, dbo.usp_L14_CheckStock,
                         dbo.usp_L14_OrderSummary, dbo.usp_L14_RaisePrice, dbo.usp_L14_CountRows;
DROP TABLE IF EXISTS dbo.L14_Products;
GO
