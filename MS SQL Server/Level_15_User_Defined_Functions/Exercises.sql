/* ============================================================
   LEVEL 15 - USER DEFINED FUNCTIONS  |  Exercises.sql
   ------------------------------------------------------------
   Try each question in the "YOUR ANSWERS" area FIRST.
   Then scroll down to SOLUTIONS and compare.
   Name every function dbo.fn_L15_Ex_<Name>; the SOLUTIONS section
   drops them all at the end.
   ============================================================ */

USE SQLPractice;
GO
DROP FUNCTION IF EXISTS dbo.fn_L15_Ex_WithGST, dbo.fn_L15_Ex_DeptName, dbo.fn_L15_Ex_OrderCount,
                        dbo.fn_L15_Ex_ProductsByCategory, dbo.fn_L15_Ex_OrdersBetween,
                        dbo.fn_L15_Ex_TopProducts, dbo.fn_L15_Ex_LastOrderByEmployee,
                        dbo.fn_L15_Ex_SalaryBands, dbo.fn_L15_Ex_WithGST_T;
GO

/* ------------------------------------------------------------
   QUESTIONS
   ------------------------------------------------------------
   Q1.  Scalar function dbo.fn_L15_Ex_WithGST(@Amount DECIMAL(12,2), @Rate DECIMAL(5,2))
        that returns the amount including GST (18 -> +18%). Show every product
        with Price and PriceWithGST (18%).

   Q2.  Scalar function dbo.fn_L15_Ex_DeptName(@EmployeeID INT) that returns the
        employee's department name, or 'No Department' when the employee has none.
        List all employees with it. (Which employee shows 'No Department'?)

   Q3.  Scalar function dbo.fn_L15_Ex_OrderCount(@CustomerID INT) returning the
        number of orders. Show all 8 customers with their count (0 for Hina Khan).

   Q4.  Inline TVF dbo.fn_L15_Ex_ProductsByCategory(@Category VARCHAR(100)) returning
        ProductID, ProductName, Price, Stock. Call it for 'Furniture'. Then use it
        again with an extra WHERE Stock < 10.

   Q5.  Inline TVF dbo.fn_L15_Ex_OrdersBetween(@From DATE, @To DATE) returning the
        orders in that date range. How many orders and how much total in Jan-Mar 2025?

   Q6.  Inline TVF dbo.fn_L15_Ex_TopProducts(@Category VARCHAR(100), @N INT) that returns
        the N most expensive products of a category. With CROSS APPLY show the single
        most expensive product of EACH category (3 rows).

   Q7.  Inline TVF dbo.fn_L15_Ex_LastOrderByEmployee(@EmployeeID INT) returning the most
        recent order (OrderID, OrderDate) of a salesperson. With OUTER APPLY list all
        12 employees and their last order (NULL when they never sold anything).

   Q8.  Multi-statement TVF dbo.fn_L15_Ex_SalaryBands(@DeptID INT) that ALWAYS returns
        3 rows: 'Below 60k', '60k to 79k', '80k and above' with the employee count of
        that department in each band (0 allowed). Test with department 2 and 6.

   Q9.  Run  SELECT fn_L15_Ex_WithGST(100, 18)  inside TRY/CATCH (via sp_executesql).
        Why does it fail? Write the correct call.

   Q10. Try to create a function that UPDATEs dbo.Products.Price (inside TRY/CATCH
        via EXEC). What is the error? What object should you use instead?

   Q11. List every dbo.fn_L15_Ex_% function with type_desc, number of parameters
        (without the return value) and is_inlineable.

   Q12. (interview) Rewrite Q1 WITHOUT a scalar UDF: create an inline TVF
        dbo.fn_L15_Ex_WithGST_T(@Amount, @Rate) RETURNS TABLE with one column
        PriceWithGST and use it with CROSS APPLY. Why is this version preferred?
   ------------------------------------------------------------ */

-- YOUR ANSWERS HERE (write below, run, compare)










/* ============================================================
   SOLUTIONS
   ============================================================ */

-- Q1
CREATE FUNCTION dbo.fn_L15_Ex_WithGST (@Amount DECIMAL(12,2), @Rate DECIMAL(5,2))
RETURNS DECIMAL(12,2)
AS
BEGIN
    RETURN @Amount * (1 + @Rate / 100);
END
GO
SELECT ProductID, ProductName, Price, dbo.fn_L15_Ex_WithGST(Price, 18) AS PriceWithGST
FROM dbo.Products
ORDER BY ProductID;
-- expect 11 rows: Laptop 75000 -> 88500.00, Mouse 1000 -> 1180.00, Pen 10 -> 11.80
GO

-- Q2
CREATE FUNCTION dbo.fn_L15_Ex_DeptName (@EmployeeID INT)
RETURNS VARCHAR(100)
AS
BEGIN
    DECLARE @Name VARCHAR(100);

    SELECT @Name = d.DepartmentName
    FROM dbo.Employees e
    JOIN dbo.Departments d ON d.DepartmentID = e.DepartmentID
    WHERE e.EmployeeID = @EmployeeID;

    RETURN ISNULL(@Name, 'No Department');
END
GO
SELECT EmployeeID, EmployeeName, dbo.fn_L15_Ex_DeptName(EmployeeID) AS Department
FROM dbo.Employees
ORDER BY EmployeeID;
-- expect 12 rows; Anjali (110) -> No Department
GO

-- Q3
CREATE FUNCTION dbo.fn_L15_Ex_OrderCount (@CustomerID INT)
RETURNS INT
AS
BEGIN
    RETURN (SELECT COUNT(*) FROM dbo.Orders o WHERE o.CustomerID = @CustomerID);
END
GO
SELECT CustomerID, CustomerName, dbo.fn_L15_Ex_OrderCount(CustomerID) AS Orders
FROM dbo.Customers
ORDER BY CustomerID;
-- expect 4, 4, 3, 2, 2, 2, 2, 0 (Hina Khan)
GO

-- Q4
CREATE FUNCTION dbo.fn_L15_Ex_ProductsByCategory (@Category VARCHAR(100))
RETURNS TABLE
AS
RETURN
(
    SELECT p.ProductID, p.ProductName, p.Price, p.Stock
    FROM dbo.Products p
    WHERE p.Category = @Category
);
GO
SELECT * FROM dbo.fn_L15_Ex_ProductsByCategory('Furniture') ORDER BY ProductID;
-- expect 3 rows: Chair, Desk, Bookshelf
SELECT * FROM dbo.fn_L15_Ex_ProductsByCategory('Furniture') WHERE Stock < 10;
-- expect 1 row: Bookshelf (stock 5)
GO

-- Q5
CREATE FUNCTION dbo.fn_L15_Ex_OrdersBetween (@From DATE, @To DATE)
RETURNS TABLE
AS
RETURN
(
    SELECT o.OrderID, o.CustomerID, o.OrderDate, o.TotalAmount, o.Status
    FROM dbo.Orders o
    WHERE o.OrderDate >= @From AND o.OrderDate <= @To
);
GO
SELECT COUNT(*) AS Orders, SUM(TotalAmount) AS Total
FROM dbo.fn_L15_Ex_OrdersBetween('2025-01-01', '2025-03-31');
-- expect 8 orders (1001-1008), 267500.00
GO

-- Q6
CREATE FUNCTION dbo.fn_L15_Ex_TopProducts (@Category VARCHAR(100), @N INT)
RETURNS TABLE
AS
RETURN
(
    SELECT TOP (@N) p.ProductID, p.ProductName, p.Price
    FROM dbo.Products p
    WHERE p.Category = @Category
    ORDER BY p.Price DESC, p.ProductID
);
GO
SELECT cat.Category, t.ProductName, t.Price
FROM (SELECT DISTINCT Category FROM dbo.Products) AS cat
CROSS APPLY dbo.fn_L15_Ex_TopProducts(cat.Category, 1) t
ORDER BY cat.Category;
-- expect 3 rows: Electronics Laptop 75000, Furniture Desk 15000, Stationery Notebook 50
GO

-- Q7
CREATE FUNCTION dbo.fn_L15_Ex_LastOrderByEmployee (@EmployeeID INT)
RETURNS TABLE
AS
RETURN
(
    SELECT TOP (1) o.OrderID, o.OrderDate
    FROM dbo.Orders o
    WHERE o.EmployeeID = @EmployeeID
    ORDER BY o.OrderDate DESC, o.OrderID DESC
);
GO
SELECT e.EmployeeID, e.EmployeeName, lo.OrderID AS LastOrder, lo.OrderDate
FROM dbo.Employees e
OUTER APPLY dbo.fn_L15_Ex_LastOrderByEmployee(e.EmployeeID) lo
ORDER BY e.EmployeeID;
-- expect 12 rows; only Priya (1018, 2025-08-30), Neha (1016, 2025-07-25),
-- Vikram (1017, 2025-08-09) have an order, the other 9 show NULL
GO

-- Q8
CREATE FUNCTION dbo.fn_L15_Ex_SalaryBands (@DeptID INT)
RETURNS @Bands TABLE (Band VARCHAR(20) NOT NULL, EmpCount INT NOT NULL)
AS
BEGIN
    -- step 1: the fixed list of bands (so 0-count bands still appear)
    INSERT INTO @Bands (Band, EmpCount)
    VALUES ('Below 60k', 0), ('60k to 79k', 0), ('80k and above', 0);

    -- step 2: fill in the counts
    UPDATE b
    SET EmpCount = (SELECT COUNT(*)
                    FROM dbo.Employees e
                    WHERE e.DepartmentID = @DeptID
                      AND CASE WHEN e.Salary < 60000 THEN 'Below 60k'
                               WHEN e.Salary < 80000 THEN '60k to 79k'
                               ELSE '80k and above' END = b.Band)
    FROM @Bands b;

    RETURN;
END
GO
SELECT * FROM dbo.fn_L15_Ex_SalaryBands(2);   -- Sales: Below 60k 1 (Neha), 60k to 79k 2, 80k and above 0
SELECT * FROM dbo.fn_L15_Ex_SalaryBands(6);   -- Legal: 0, 0, 0 (still 3 rows)
GO

-- Q9
BEGIN TRY
    EXEC sp_executesql N'SELECT fn_L15_Ex_WithGST(100, 18) AS X';
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
-- Reason: without a schema SQL Server only looks for BUILT-IN functions.
SELECT dbo.fn_L15_Ex_WithGST(100, 18) AS Fixed;     -- 118.00
GO

-- Q10
BEGIN TRY
    EXEC('CREATE FUNCTION dbo.fn_L15_Ex_RaisePrices() RETURNS INT AS
          BEGIN UPDATE dbo.Products SET Price = Price * 1.1; RETURN 1; END');
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
-- Functions must not have side effects. Use a STORED PROCEDURE for data changes.
GO

-- Q11
SELECT o.name, o.type_desc,
       (SELECT COUNT(*) FROM sys.parameters p WHERE p.object_id = o.object_id AND p.parameter_id > 0) AS Params,
       m.is_inlineable
FROM sys.objects o
JOIN sys.sql_modules m ON m.object_id = o.object_id
WHERE o.name LIKE 'fn[_]L15[_]Ex[_]%'
ORDER BY o.type_desc, o.name;
-- expect 8 rows: 3 SQL_SCALAR_FUNCTION, 4 SQL_INLINE_TABLE_VALUED_FUNCTION, 1 SQL_TABLE_VALUED_FUNCTION
GO

-- Q12
CREATE FUNCTION dbo.fn_L15_Ex_WithGST_T (@Amount DECIMAL(12,2), @Rate DECIMAL(5,2))
RETURNS TABLE
AS
RETURN (SELECT CAST(@Amount * (1 + @Rate / 100) AS DECIMAL(12,2)) AS PriceWithGST);
GO
SELECT p.ProductID, p.ProductName, p.Price, g.PriceWithGST
FROM dbo.Products p
CROSS APPLY dbo.fn_L15_Ex_WithGST_T(p.Price, 18) g
ORDER BY p.ProductID;
-- expect the same 11 rows as Q1.
-- Why preferred: an inline TVF is expanded into the query on EVERY version of SQL
-- Server (no per-row call, parallel plans allowed), while a scalar UDF is only
-- inlined on 2019+ and only when it is simple enough.
GO

/* ---------------- cleanup ---------------- */
DROP FUNCTION IF EXISTS dbo.fn_L15_Ex_WithGST, dbo.fn_L15_Ex_DeptName, dbo.fn_L15_Ex_OrderCount,
                        dbo.fn_L15_Ex_ProductsByCategory, dbo.fn_L15_Ex_OrdersBetween,
                        dbo.fn_L15_Ex_TopProducts, dbo.fn_L15_Ex_LastOrderByEmployee,
                        dbo.fn_L15_Ex_SalaryBands, dbo.fn_L15_Ex_WithGST_T;
GO
