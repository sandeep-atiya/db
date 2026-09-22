/* ============================================================
   LEVEL 15 - USER DEFINED FUNCTIONS  |  01_Practice_Scalar_and_TVF.sql
   ------------------------------------------------------------
   Topics : the 3 kinds of UDF, scalar functions, inline
            table-valued functions (iTVF), multi-statement TVF
            (MSTVF), calling TVFs in FROM / JOIN / CROSS APPLY /
            OUTER APPLY, CREATE OR ALTER / ALTER / DROP FUNCTION.
   HOW TO PRACTICE: run block by block, predict the output first.
   All objects are prefixed fn_L15_ and are dropped in CLEANUP.
   Next file: 02_Practice_Rules_and_Schemabinding.sql
   ============================================================ */

USE SQLPractice;
GO
DROP FUNCTION IF EXISTS dbo.fn_L15_FullContact, dbo.fn_L15_GetAge, dbo.fn_L15_OrderTotal,
                        dbo.fn_L15_OrdersByCustomer, dbo.fn_L15_EmployeesByDept,
                        dbo.fn_L15_CustomerOrderSummary, dbo.fn_L15_TopNOrders;
GO


/* ============================================================
   1. THE THREE KINDS OF USER DEFINED FUNCTION
   ============================================================
   A function = a saved piece of T-SQL that takes parameters and
   RETURNS a value. Unlike a stored procedure it can be used
   INSIDE a query (SELECT list, WHERE, JOIN, FROM).

   Kind                        Returns          Called as              Body
   --------------------------  ---------------  ---------------------  ----------------------------
   Scalar                      one value        dbo.fn(args)           BEGIN ... RETURN value END
   Inline table-valued (iTVF)  a table          FROM dbo.fn(args)      RETURN (one SELECT)   <- "parameterised view"
   Multi-statement TVF (MSTVF) a table          FROM dbo.fn(args)      BEGIN INSERT @t ... RETURN END

   sys.objects.type : FN = scalar, IF = inline TVF, TF = multi-statement TVF
   ============================================================ */


/* ============================================================
   2. SCALAR FUNCTION  (returns ONE value)
   ============================================================ */

-- 2a. Simplest scalar function: build a display string from name + email.
--     RETURNS <type>  ...  BEGIN  ...  RETURN <value>  END
CREATE FUNCTION dbo.fn_L15_FullContact
(
    @Name  VARCHAR(100),
    @Email VARCHAR(150)
)
RETURNS VARCHAR(260)
AS
BEGIN
    DECLARE @Result VARCHAR(260);

    IF @Email IS NULL
        SET @Result = @Name + ' (no email)';
    ELSE
        SET @Result = @Name + ' <' + @Email + '>';

    RETURN @Result;
END
GO

-- Call it in a SELECT list. The schema prefix dbo. is MANDATORY for scalar UDFs.
SELECT CustomerID, dbo.fn_L15_FullContact(CustomerName, Email) AS Contact
FROM dbo.Customers
ORDER BY CustomerID;
-- expect 8 rows; Farhan Ali and Hina Khan show "(no email)"
GO

-- 2b. Calling WITHOUT the schema prefix -> error 195 "not a recognized function name".
--     SQL Server thinks you mean a built-in function.
--     (wrapped in sp_executesql because it is a compile error - TRY/CATCH cannot
--      catch compile errors of its own batch, only of a nested batch)
BEGIN TRY
    EXEC sp_executesql N'SELECT fn_L15_FullContact(''Rahul'', NULL) AS Contact';
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO

-- 2c. A scalar function may use GETDATE() (allowed since SQL 2005).
--     Age in whole years, correct even before the birthday in the current year.
CREATE FUNCTION dbo.fn_L15_GetAge (@BirthDate DATE)
RETURNS INT
AS
BEGIN
    DECLARE @Today DATE = CAST(GETDATE() AS DATE);
    DECLARE @Years INT = DATEDIFF(YEAR, @BirthDate, @Today);

    -- DATEDIFF(YEAR) only subtracts the year numbers; fix if birthday not yet reached
    IF DATEADD(YEAR, @Years, @BirthDate) > @Today
        SET @Years = @Years - 1;

    RETURN @Years;
END
GO

-- Use it with a variable, a literal and a column (years of service of each employee)
DECLARE @dob DATE = '2000-01-01';
SELECT dbo.fn_L15_GetAge(@dob)          AS AgeOfVariable,
       dbo.fn_L15_GetAge('1995-06-15')  AS AgeOfLiteral;
-- expect 26 and 31 when run in Sep 2026 (result moves with today's date)

SELECT EmployeeName, HireDate, dbo.fn_L15_GetAge(HireDate) AS YearsOfService
FROM dbo.Employees
ORDER BY HireDate;
-- expect Sneha (2020-05-18) first with the most years, Anjali (2024-05-20) last
GO

-- 2d. A scalar function that READS a table: order total from the line items.
--     Classic interview example: "write a function that returns the total of an order".
CREATE FUNCTION dbo.fn_L15_OrderTotal (@OrderID INT)
RETURNS DECIMAL(12,2)
AS
BEGIN
    DECLARE @Total DECIMAL(12,2);

    SELECT @Total = SUM(od.Quantity * od.UnitPrice)
    FROM dbo.OrderDetails od
    WHERE od.OrderID = @OrderID;

    RETURN ISNULL(@Total, 0);      -- unknown order -> 0 instead of NULL
END
GO

SELECT dbo.fn_L15_OrderTotal(1002) AS Total1002,     -- 8000 + 2*1000 = 10000.00
       dbo.fn_L15_OrderTotal(1008) AS Total1008,     -- 75000 + 1000 + 2500 = 78500.00
       dbo.fn_L15_OrderTotal(9999) AS UnknownOrder;  -- 0.00 (sqlcmd prints it as .00)
GO

-- Use it in SELECT and in WHERE. Every row calls the function (see file 02 for the cost).
SELECT o.OrderID, o.TotalAmount, dbo.fn_L15_OrderTotal(o.OrderID) AS LineTotal
FROM dbo.Orders o
WHERE o.TotalAmount <> dbo.fn_L15_OrderTotal(o.OrderID);
-- expect 0 rows: every stored TotalAmount matches its line items
GO

-- Scalar functions also work inside variables, CASE, ORDER BY, computed columns ...
SELECT TOP (3) o.OrderID, dbo.fn_L15_OrderTotal(o.OrderID) AS LineTotal
FROM dbo.Orders o
ORDER BY dbo.fn_L15_OrderTotal(o.OrderID) DESC;
-- expect 1014 (150000), 1008 (78500), then 1001 / 1018 (75000 - tie, either may appear)
GO


/* ============================================================
   3. INLINE TABLE-VALUED FUNCTION  (iTVF = "parameterised view")
   ============================================================
   RETURNS TABLE  AS  RETURN ( one SELECT )   - no BEGIN/END, no variables.
   The optimizer EXPANDS it into the calling query exactly like a
   view, so it gets normal statistics, indexes and parallelism.
   ============================================================ */

-- 3a. All orders of one customer
CREATE FUNCTION dbo.fn_L15_OrdersByCustomer (@CustomerID INT)
RETURNS TABLE
AS
RETURN
(
    SELECT o.OrderID, o.OrderDate, o.TotalAmount, o.Status
    FROM dbo.Orders o
    WHERE o.CustomerID = @CustomerID
);
GO

-- Call it in FROM like a table. The schema prefix is required here too.
SELECT * FROM dbo.fn_L15_OrdersByCustomer(1) ORDER BY OrderDate;
-- expect 4 rows: 1001, 1004, 1009, 1015 (Aarav Sharma)

SELECT * FROM dbo.fn_L15_OrdersByCustomer(8);
-- expect 0 rows (Hina Khan never ordered)
GO

-- 3b. Because it is expanded like a view you can filter / aggregate on top of it
SELECT COUNT(*) AS Orders, SUM(TotalAmount) AS Total
FROM dbo.fn_L15_OrdersByCustomer(2)
WHERE Status = 'Completed';
-- expect 4 orders, 48500.00 (10000 + 6000 + 30000 + 2500)
GO

-- 3c. Employees of a department, joined with Departments for the name
CREATE FUNCTION dbo.fn_L15_EmployeesByDept (@DeptID INT)
RETURNS TABLE
AS
RETURN
(
    SELECT e.EmployeeID, e.EmployeeName, e.Salary, d.DepartmentName
    FROM dbo.Employees e
    JOIN dbo.Departments d ON d.DepartmentID = e.DepartmentID
    WHERE e.DepartmentID = @DeptID
);
GO

SELECT * FROM dbo.fn_L15_EmployeesByDept(1) ORDER BY EmployeeID;
-- expect 3 rows: Rahul, Amit, Pooja (IT)

SELECT * FROM dbo.fn_L15_EmployeesByDept(6);
-- expect 0 rows (Legal has no employees)
GO


/* ============================================================
   4. MULTI-STATEMENT TABLE-VALUED FUNCTION  (MSTVF)
   ============================================================
   RETURNS @t TABLE (...)  then  BEGIN  ... INSERT INTO @t ...  RETURN  END
   Use only when ONE SELECT is not enough (loops, several steps).
   The optimizer treats it as a black box (see file 02).
   ============================================================ */

-- 4a. Per-status summary for a customer PLUS a total row (two INSERTs = needs MSTVF)
CREATE FUNCTION dbo.fn_L15_CustomerOrderSummary (@CustomerID INT)
RETURNS @Summary TABLE
(
    Status     VARCHAR(20)   NOT NULL,
    OrderCount INT           NOT NULL,
    Total      DECIMAL(12,2) NOT NULL
)
AS
BEGIN
    -- step 1: one row per status
    INSERT INTO @Summary (Status, OrderCount, Total)
    SELECT o.Status, COUNT(*), SUM(o.TotalAmount)
    FROM dbo.Orders o
    WHERE o.CustomerID = @CustomerID
    GROUP BY o.Status;

    -- step 2: a grand-total row
    INSERT INTO @Summary (Status, OrderCount, Total)
    SELECT 'ALL', ISNULL(SUM(OrderCount), 0), ISNULL(SUM(Total), 0)
    FROM @Summary;

    RETURN;     -- in an MSTVF, RETURN has no value: it just ends the function
END
GO

SELECT * FROM dbo.fn_L15_CustomerOrderSummary(1);
-- expect 3 rows: Completed 3 / 96000.00, Pending 1 / 32000.00, ALL 4 / 128000.00

SELECT * FROM dbo.fn_L15_CustomerOrderSummary(8);
-- expect 1 row: ALL 0 / 0.00
GO


/* ============================================================
   5. CALLING TVFs: FROM, JOIN, CROSS APPLY, OUTER APPLY
   ============================================================ */

-- 5a. JOIN works when the argument is a constant or a variable ...
DECLARE @Dept INT = 2;
SELECT d.DepartmentName, f.EmployeeName, f.Salary
FROM dbo.fn_L15_EmployeesByDept(@Dept) f
JOIN dbo.Departments d ON d.DepartmentID = @Dept
ORDER BY f.Salary DESC;
-- expect 3 rows: Priya 75000, Vikram 62000, Neha 55000 (Sales)
GO

-- 5b. ... but a JOIN CANNOT pass a column of another table as the argument.
--     The function is evaluated once, BEFORE the join, so c.CustomerID does not exist yet.
BEGIN TRY
    EXEC sp_executesql N'
        SELECT c.CustomerName, f.OrderID
        FROM dbo.Customers c
        JOIN dbo.fn_L15_OrdersByCustomer(c.CustomerID) f ON 1 = 1';
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO

-- 5c. CROSS APPLY = "call the function once PER ROW of the left table" (like an inner join)
SELECT c.CustomerName, f.OrderID, f.TotalAmount
FROM dbo.Customers c
CROSS APPLY dbo.fn_L15_OrdersByCustomer(c.CustomerID) f
ORDER BY c.CustomerID, f.OrderID;
-- expect 19 rows (every order); Hina Khan (8) does not appear
GO

-- 5d. OUTER APPLY keeps left rows that get nothing back (like a left join)
SELECT c.CustomerName, f.OrderID, f.TotalAmount
FROM dbo.Customers c
OUTER APPLY dbo.fn_L15_OrdersByCustomer(c.CustomerID) f
WHERE f.OrderID IS NULL;
-- expect 1 row: Hina Khan, NULL, NULL
GO

-- 5e. THE CLASSIC USE: top N per group. A TVF with TOP + ORDER BY, applied per customer.
CREATE FUNCTION dbo.fn_L15_TopNOrders (@CustomerID INT, @N INT)
RETURNS TABLE
AS
RETURN
(
    SELECT TOP (@N) o.OrderID, o.OrderDate, o.TotalAmount
    FROM dbo.Orders o
    WHERE o.CustomerID = @CustomerID
    ORDER BY o.TotalAmount DESC, o.OrderID
);
GO

-- Top 2 orders (by amount) of every customer
SELECT c.CustomerID, c.CustomerName, t.OrderID, t.TotalAmount
FROM dbo.Customers c
CROSS APPLY dbo.fn_L15_TopNOrders(c.CustomerID, 2) t
ORDER BY c.CustomerID, t.TotalAmount DESC;
-- expect 14 rows (7 customers x 2). Customer 1 -> 1001 75000, 1015 32000;
-- customer 2 -> 1012 30000, 1002 10000; customer 5 -> 1014 150000, 1006 8000

-- Same with OUTER APPLY: customers without orders are kept
SELECT c.CustomerID, c.CustomerName, t.OrderID, t.TotalAmount
FROM dbo.Customers c
OUTER APPLY dbo.fn_L15_TopNOrders(c.CustomerID, 1) t
ORDER BY c.CustomerID;
-- expect 8 rows; the last one is Hina Khan with NULL OrderID
GO

-- 5f. APPLY also works with a scalar function result "as a table" via VALUES
--     (handy when you want to reuse a computed value in several columns)
SELECT o.OrderID, x.LineTotal, x.LineTotal * 0.18 AS GST
FROM dbo.Orders o
CROSS APPLY (VALUES (dbo.fn_L15_OrderTotal(o.OrderID))) AS x(LineTotal)
WHERE o.OrderID IN (1001, 1002);
-- expect 2 rows: 75000.00 / 13500.00 and 10000.00 / 1800.00
GO


/* ============================================================
   6. CREATE OR ALTER  /  ALTER FUNCTION  /  DROP FUNCTION IF EXISTS
   ============================================================ */

-- 6a. ALTER FUNCTION keeps permissions and the object_id; the body is replaced.
--     Here we change the format of FullContact.
ALTER FUNCTION dbo.fn_L15_FullContact
(
    @Name  VARCHAR(100),
    @Email VARCHAR(150)
)
RETURNS VARCHAR(260)
AS
BEGIN
    RETURN CONCAT_WS(' | ', @Name, @Email);      -- CONCAT_WS (2017+) skips NULLs
END
GO

SELECT dbo.fn_L15_FullContact('Farhan Ali', NULL)             AS NoEmail,     -- Farhan Ali
       dbo.fn_L15_FullContact('Aarav Sharma', 'aarav@example.com') AS WithEmail;  -- Aarav Sharma | aarav@example.com
GO

-- 6b. CREATE OR ALTER (2016 SP1+): creates if missing, alters if present. Re-runnable scripts!
CREATE OR ALTER FUNCTION dbo.fn_L15_OrdersByCustomer (@CustomerID INT)
RETURNS TABLE
AS
RETURN
(
    SELECT o.OrderID, o.OrderDate, o.TotalAmount, o.Status,
           dbo.fn_L15_OrderTotal(o.OrderID) AS LineTotal      -- a TVF may call a scalar UDF
    FROM dbo.Orders o
    WHERE o.CustomerID = @CustomerID
);
GO
SELECT OrderID, TotalAmount, LineTotal FROM dbo.fn_L15_OrdersByCustomer(4);
-- expect 2 rows: 1005 50000/50000, 1013 27500/27500
GO

-- 6c. You cannot change the KIND of a function with ALTER (scalar -> table etc.)
BEGIN TRY
    EXEC sp_executesql N'ALTER FUNCTION dbo.fn_L15_GetAge (@BirthDate DATE)
                         RETURNS TABLE AS RETURN (SELECT 1 AS x)';
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO

-- 6d. DROP FUNCTION IF EXISTS (2016+); several names in one statement are allowed
DROP FUNCTION IF EXISTS dbo.fn_L15_TopNOrders;
DROP FUNCTION IF EXISTS dbo.fn_L15_TopNOrders;   -- second time: no error
GO

-- 6e. Dropping a function that another object still uses is allowed (no check!) ...
--     ... unless that object is SCHEMABOUND (file 02). Here OrdersByCustomer uses OrderTotal:
SELECT referencing_schema_name, referencing_entity_name, referencing_class_desc
FROM sys.dm_sql_referencing_entities('dbo.fn_L15_OrderTotal', 'OBJECT');
-- expect 1 row: dbo | fn_L15_OrdersByCustomer | OBJECT_OR_COLUMN  (it uses fn_L15_OrderTotal)
GO


/* ============================================================
   7. CLEANUP
   ============================================================ */
DROP FUNCTION IF EXISTS dbo.fn_L15_OrdersByCustomer;    -- drop the caller first (good habit)
DROP FUNCTION IF EXISTS dbo.fn_L15_FullContact, dbo.fn_L15_GetAge, dbo.fn_L15_OrderTotal,
                        dbo.fn_L15_EmployeesByDept, dbo.fn_L15_CustomerOrderSummary,
                        dbo.fn_L15_TopNOrders;
GO
SELECT name FROM sys.objects WHERE name LIKE 'fn_L15%';   -- expect 0 rows
GO
/* DONE. Next: 02_Practice_Rules_and_Schemabinding.sql */
