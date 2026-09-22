/* ============================================================
   LEVEL 14 - STORED PROCEDURES  |  01_Practice_Basics.sql
   ------------------------------------------------------------
   Topics : what a proc is + benefits, CREATE / CREATE OR ALTER /
            ALTER / DROP IF EXISTS, naming (usp_ not sp_), EXEC
            positional vs named + EXEC/EXECUTE/bare name, input
            params with types and DEFAULT + optional-parameter
            pattern, SET NOCOUNT ON, variables + IF/ELSE/WHILE/
            BEGIN..END + PRINT vs SELECT, OUTPUT parameters,
            RETURN status codes, result sets (one and many),
            calling a proc from a proc, an INSERT proc that
            returns the new id, viewing definitions.
   HOW TO PRACTICE: run block by block, predict the output first.
   All data changes happen on the copy table dbo.L14_Orders.
   ============================================================ */

USE SQLPractice;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
DROP PROCEDURE IF EXISTS dbo.usp_L14_HelloWorld, dbo.usp_L14_GetEmployees, dbo.usp_L14_GetByDept,
                         dbo.usp_L14_SearchOrders, dbo.usp_L14_Classify, dbo.usp_L14_SumTo,
                         dbo.usp_L14_CountByDept, dbo.usp_L14_NextTicket, dbo.usp_L14_DeptReport,
                         dbo.usp_L14_AddOrder, dbo.usp_L14_AuditThenAdd;
DROP TABLE IF EXISTS dbo.L14_Orders;
GO


/* ==== 1. WHAT IS A STORED PROCEDURE, AND WHY ==== */
-- A stored procedure is a NAMED program stored in the database: T-SQL statements you
-- call by name with parameters. Benefits:
--   * REUSE          - write the logic once, call it from apps, jobs, other procs
--   * SECURITY       - GRANT EXECUTE on the proc; the caller never touches the tables
--   * PLAN CACHING   - the execution plan is compiled once and reused (faster)
--   * LESS NETWORK   - the app sends "EXEC usp_X 5" instead of a 200-line query
--   * MAINTAINABLE   - fix the logic in one place, every caller gets the fix

-- 1a. The simplest proc. CREATE PROCEDURE must be the FIRST statement in its batch (GO before).
CREATE PROCEDURE dbo.usp_L14_HelloWorld
AS
BEGIN
    SET NOCOUNT ON;
    SELECT 'Hello from a stored procedure' AS Message;
END
GO
EXEC dbo.usp_L14_HelloWorld;   -- one row: Hello from a stored procedure
GO


/* ==== 2. CREATE / CREATE OR ALTER / ALTER / DROP, and NAMING ==== */
-- 2a. CREATE OR ALTER (2016 SP1+) is what you use in real scripts: works whether or not
--     the proc already exists, and (unlike DROP + CREATE) keeps permissions.
CREATE OR ALTER PROCEDURE dbo.usp_L14_GetEmployees
AS
BEGIN
    SET NOCOUNT ON;
    SELECT EmployeeID, EmployeeName, Salary FROM dbo.Employees ORDER BY EmployeeID;
END
GO
-- 2b. ALTER replaces the body; fails if the proc does not exist. DROP ... IF EXISTS is re-runnable.
ALTER PROCEDURE dbo.usp_L14_GetEmployees
AS
BEGIN
    SET NOCOUNT ON;
    SELECT EmployeeID, EmployeeName, Salary FROM dbo.Employees WHERE Salary >= 70000 ORDER BY Salary DESC;
END
GO
EXEC dbo.usp_L14_GetEmployees;   -- 5 rows: Sneha 90000, Rahul 85000, Priya 75000, Deepak 72000, Karan 70000
GO
-- 2c. NAMING: prefix your procs "usp_" (user stored procedure). NEVER prefix with "sp_".
--     Why sp_ is bad: SQL Server treats sp_ as a SYSTEM proc and searches the master
--     database FIRST, then your database. That means an extra lookup, a chance of a
--     recompile, and if Microsoft ever ships a real system proc with that name, yours is
--     silently shadowed. So: dbo.usp_L14_... = good, dbo.sp_MyProc = bad.


/* ==== 3. EXEC vs EXECUTE vs the bare name; positional vs named parameters ==== */
CREATE OR ALTER PROCEDURE dbo.usp_L14_GetByDept
    @DepartmentID INT,
    @MinSalary    DECIMAL(12,2)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT EmployeeID, EmployeeName, Salary
    FROM dbo.Employees
    WHERE DepartmentID = @DepartmentID AND Salary >= @MinSalary
    ORDER BY Salary DESC;
END
GO
-- 3a. NAMED parameters (order does not matter, self-documenting - PREFER THIS)
EXEC dbo.usp_L14_GetByDept @DepartmentID = 1, @MinSalary = 65000;   -- Rahul 85000, Amit 65000, Pooja 65000
-- 3b. POSITIONAL parameters (must be in declared order)
EXEC dbo.usp_L14_GetByDept 2, 60000;                                -- Priya 75000, Vikram 62000
-- 3c. EXEC and EXECUTE are the SAME keyword. And when the call is the FIRST statement of a
--     batch you may even drop the word entirely (do not rely on this - always write EXEC).
EXECUTE dbo.usp_L14_GetByDept @DepartmentID = 4, @MinSalary = 0;    -- Sneha 90000, Deepak 72000
GO
dbo.usp_L14_GetByDept 5, 60000;                                     -- Karan 70000 (bare name, first in batch)
GO


/* ==== 4. INPUT PARAMETERS with DEFAULT + the OPTIONAL-parameter pattern ==== */
-- A parameter with "= value" is optional: callers may omit it and get the default.
-- The classic optional-filter pattern: (@x IS NULL OR col = @x) means "if the caller did
-- not supply @x, do not filter on that column".
CREATE OR ALTER PROCEDURE dbo.usp_L14_SearchOrders
    @Status     VARCHAR(20) = NULL,      -- omit -> any status
    @CustomerID INT         = NULL       -- omit -> any customer
AS
BEGIN
    SET NOCOUNT ON;
    SELECT o.OrderID, o.CustomerID, o.Status, o.TotalAmount
    FROM dbo.Orders o
    WHERE (@Status     IS NULL OR o.Status     = @Status)
      AND (@CustomerID IS NULL OR o.CustomerID = @CustomerID)
    ORDER BY o.OrderID;
END
GO
EXEC dbo.usp_L14_SearchOrders;                                  -- all 19 orders
EXEC dbo.usp_L14_SearchOrders @Status = 'Pending';             -- 2: 1015, 1017
EXEC dbo.usp_L14_SearchOrders @CustomerID = 1;                 -- 4: 1001, 1004, 1009, 1015
EXEC dbo.usp_L14_SearchOrders @Status = 'Completed', @CustomerID = 2;   -- 4: 1002, 1007, 1012, 1019
GO


/* ==== 5. SET NOCOUNT ON ==== */
-- Every data statement normally sends a "(N rows affected)" message to the client. Inside
-- a proc that does many statements (or loops) those messages are pure noise and extra
-- network chatter, and some old drivers even mistake them for result sets. Put
-- SET NOCOUNT ON as the first line of EVERY proc. (It does NOT affect @@ROWCOUNT.)
CREATE OR ALTER PROCEDURE dbo.usp_L14_Classify
    @Salary DECIMAL(12,2)
AS
BEGIN
    SET NOCOUNT ON;
    -- 6. variables, IF / ELSE, BEGIN..END, PRINT vs SELECT (see next section header)
    DECLARE @Band VARCHAR(20);
    IF @Salary >= 80000
        SET @Band = 'High';
    ELSE IF @Salary >= 60000
        SET @Band = 'Medium';
    ELSE
        SET @Band = 'Low';
    SELECT @Salary AS Salary, @Band AS Band;
END
GO


/* ==== 6. VARIABLES, IF/ELSE, WHILE, BEGIN..END, PRINT vs SELECT ==== */
EXEC dbo.usp_L14_Classify @Salary = 90000;   -- High
EXEC dbo.usp_L14_Classify @Salary = 65000;   -- Medium
EXEC dbo.usp_L14_Classify @Salary = 48000;   -- Low
GO
-- 6a. WHILE loop with BEGIN..END. PRINT writes to the Messages tab (debug text, no result
--     set); SELECT returns a result set (data). Use PRINT for progress, SELECT for output.
CREATE OR ALTER PROCEDURE dbo.usp_L14_SumTo
    @N INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @i INT = 1, @sum INT = 0;
    WHILE @i <= @N
    BEGIN
        SET @sum += @i;
        PRINT 'added ' + CAST(@i AS VARCHAR(10)) + ' running total ' + CAST(@sum AS VARCHAR(10));  -- debug
        SET @i += 1;
    END
    SELECT @N AS N, @sum AS SumOneToN;   -- the actual output
END
GO
EXEC dbo.usp_L14_SumTo @N = 5;   -- SumOneToN = 15 (Messages tab shows the 5 PRINT lines)
GO


/* ==== 7. OUTPUT PARAMETERS: hand a value BACK to the caller ==== */
-- A result set is for rows; an OUTPUT parameter is for a single scalar you want in a
-- variable (a count, a new id, a status text). Mark it OUTPUT in BOTH the proc and the call.
CREATE OR ALTER PROCEDURE dbo.usp_L14_CountByDept
    @DepartmentID INT,
    @Count        INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT @Count = COUNT(*) FROM dbo.Employees WHERE DepartmentID = @DepartmentID;
END
GO
DECLARE @c INT;
EXEC dbo.usp_L14_CountByDept @DepartmentID = 1, @Count = @c OUTPUT;   -- OUTPUT keyword required here too
SELECT @c AS ITHeadcount;   -- 3
GO


/* ==== 8. RETURN VALUE: an integer STATUS code (0 = success) ==== */
-- RETURN sends back ONE integer, meant only for status (0 = ok, non-zero = which problem).
-- It is NOT for data - use OUTPUT params or a result set for that. Capture it with EXEC @rc = .
CREATE OR ALTER PROCEDURE dbo.usp_L14_NextTicket
    @Priority   VARCHAR(10),
    @TicketText VARCHAR(50) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    IF @Priority NOT IN ('Low', 'High')
    BEGIN
        SET @TicketText = NULL;
        RETURN 1;                 -- 1 = bad input
    END
    SET @TicketText = @Priority + '-' + CONVERT(VARCHAR(8), SYSDATETIME(), 108);
    RETURN 0;                     -- 0 = success
END
GO
DECLARE @rc INT, @txt VARCHAR(50);
EXEC @rc = dbo.usp_L14_NextTicket @Priority = 'High', @TicketText = @txt OUTPUT;
SELECT @rc AS ReturnCode, @txt AS Ticket;          -- 0, High-hh:mm:ss
EXEC @rc = dbo.usp_L14_NextTicket @Priority = 'Zzz', @TicketText = @txt OUTPUT;
SELECT @rc AS ReturnCode, @txt AS Ticket;          -- 1, NULL
GO


/* ==== 9. RESULT SETS: one, and many ==== */
-- A proc can return several result sets - it just runs several SELECTs. The app reads them
-- in order (ADO.NET NextResult(), JDBC getMoreResults()).
CREATE OR ALTER PROCEDURE dbo.usp_L14_DeptReport
    @DepartmentID INT
AS
BEGIN
    SET NOCOUNT ON;
    -- result set 1: the department
    SELECT DepartmentID, DepartmentName, Location FROM dbo.Departments WHERE DepartmentID = @DepartmentID;
    -- result set 2: its employees
    SELECT EmployeeID, EmployeeName, Salary FROM dbo.Employees WHERE DepartmentID = @DepartmentID ORDER BY Salary DESC;
    -- result set 3: one summary row
    SELECT COUNT(*) AS Headcount, SUM(Salary) AS TotalSalary FROM dbo.Employees WHERE DepartmentID = @DepartmentID;
END
GO
EXEC dbo.usp_L14_DeptReport @DepartmentID = 1;
-- set1: IT / Delhi   set2: Rahul 85000, Amit 65000, Pooja 65000   set3: 3 / 215000.00
GO


/* ==== 10 + 11. AN INSERT PROC THAT RETURNS THE NEW ID, called from another proc ==== */
-- Work on a COPY so the base tables are never changed. IDENTITY gives auto ids.
CREATE TABLE dbo.L14_Orders
(
    OrderID     INT IDENTITY(2001,1) PRIMARY KEY,
    CustomerID  INT           NOT NULL,
    TotalAmount DECIMAL(12,2)  NOT NULL,
    Status      VARCHAR(20)    NOT NULL CONSTRAINT DF_L14_Orders_Status DEFAULT ('Pending')
);
GO
-- 11a. The INSERT proc: returns the new id via an OUTPUT param AND a status via RETURN.
CREATE OR ALTER PROCEDURE dbo.usp_L14_AddOrder
    @CustomerID  INT,
    @TotalAmount DECIMAL(12,2),
    @NewOrderID  INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    IF @TotalAmount <= 0
    BEGIN
        SET @NewOrderID = 0;
        RETURN 1;                         -- 1 = invalid amount
    END
    INSERT INTO dbo.L14_Orders (CustomerID, TotalAmount) VALUES (@CustomerID, @TotalAmount);
    SET @NewOrderID = SCOPE_IDENTITY();   -- the id just generated, on THIS connection/scope
    RETURN 0;
END
GO
DECLARE @id INT, @rc INT;
EXEC @rc = dbo.usp_L14_AddOrder @CustomerID = 1, @TotalAmount = 999, @NewOrderID = @id OUTPUT;
SELECT @rc AS ReturnCode, @id AS NewOrderID;   -- 0, 2001
EXEC @rc = dbo.usp_L14_AddOrder @CustomerID = 2, @TotalAmount = -5, @NewOrderID = @id OUTPUT;
SELECT @rc AS ReturnCode, @id AS NewOrderID;   -- 1, 0 (rejected, nothing inserted)
SELECT * FROM dbo.L14_Orders;                  -- 1 row: 2001, 1, 999.00, Pending
GO
-- 11b. Calling a proc FROM a proc (nesting). The inner proc's OUTPUT flows back to the outer one.
CREATE OR ALTER PROCEDURE dbo.usp_L14_AuditThenAdd
    @CustomerID  INT,
    @TotalAmount DECIMAL(12,2)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @id INT, @rc INT;
    EXEC @rc = dbo.usp_L14_AddOrder @CustomerID = @CustomerID, @TotalAmount = @TotalAmount, @NewOrderID = @id OUTPUT;
    IF @rc = 0
        SELECT 'created' AS Result, @id AS NewOrderID, @@NESTLEVEL AS NestLevel;   -- outer proc runs at level 1
    ELSE
        SELECT 'rejected' AS Result, NULL AS NewOrderID, @@NESTLEVEL AS NestLevel;
END
GO
EXEC dbo.usp_L14_AuditThenAdd @CustomerID = 3, @TotalAmount = 4200;   -- created, 2002, 1
SELECT COUNT(*) AS OrdersNow FROM dbo.L14_Orders;                     -- 2
GO


/* ==== 12. VIEWING PROCEDURE DEFINITIONS AND PARAMETERS ==== */
-- 12a. The text, two ways
EXEC sp_helptext 'dbo.usp_L14_AddOrder';
SELECT OBJECT_DEFINITION(OBJECT_ID('dbo.usp_L14_AddOrder')) AS Definition;
GO
-- 12b. All my procs
SELECT name, create_date, modify_date
FROM sys.procedures
WHERE name LIKE 'usp[_]L14%'
ORDER BY name;   -- 11 rows
GO
-- 12c. Parameters of one proc. NOTE: has_default_value / default_value are populated only
--      for CLR procs, so a T-SQL "= NULL" default shows has_default_value = 0. To see T-SQL
--      defaults, read the definition (12a).
SELECT p.name AS ParameterName, TYPE_NAME(p.user_type_id) AS DataType,
       p.max_length, p.is_output, p.parameter_id
FROM sys.parameters p
WHERE p.object_id = OBJECT_ID('dbo.usp_L14_AddOrder')
ORDER BY p.parameter_id;   -- @CustomerID int, @TotalAmount decimal, @NewOrderID int (is_output = 1)
GO


/* ==== 13. CLEANUP ==== */
DROP PROCEDURE IF EXISTS dbo.usp_L14_HelloWorld, dbo.usp_L14_GetEmployees, dbo.usp_L14_GetByDept,
                         dbo.usp_L14_SearchOrders, dbo.usp_L14_Classify, dbo.usp_L14_SumTo,
                         dbo.usp_L14_CountByDept, dbo.usp_L14_NextTicket, dbo.usp_L14_DeptReport,
                         dbo.usp_L14_AddOrder, dbo.usp_L14_AuditThenAdd;
DROP TABLE IF EXISTS dbo.L14_Orders;
GO
/* DONE. Next: 02_Practice_Advanced.sql */
