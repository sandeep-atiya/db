/* ============================================================
   LEVEL 13 - VIEWS  |  01_Practice_View_Basics.sql
   ------------------------------------------------------------
   Topics : what a view is and why, CREATE VIEW / ALTER VIEW /
            CREATE OR ALTER / DROP VIEW IF EXISTS, the rules
            (no ORDER BY without TOP/OFFSET, the TOP 100 PERCENT
            myth, no parameters -> inline TVF, every column needs
            a name), updatable views, WITH CHECK OPTION.
   HOW TO PRACTICE: run block by block, predict the output first.
   Data changes happen only on the copy table dbo.L13_Products
   or inside a transaction that is rolled back.
   ============================================================ */

USE SQLPractice;
GO
DROP VIEW IF EXISTS dbo.vw_L13_EmployeeDetails, dbo.vw_L13_TopSalaries, dbo.vw_L13_Top100Myth,
                    dbo.vw_L13_AnnualSalary, dbo.vw_L13_Electronics, dbo.vw_L13_StaffPerDept,
                    dbo.vw_L13_Sorted, dbo.vw_L13_ByDept, dbo.vw_L13_NoName;
DROP FUNCTION IF EXISTS dbo.fn_L13_EmployeesByDept;
DROP TABLE IF EXISTS dbo.L13_Products;
GO


/* ==== 1. WHAT IS A VIEW, AND WHY ==== */
-- A view is a SAVED SELECT with a name. It stores NO data (except indexed views, file 02):
-- every time you query it, SQL Server runs the stored SELECT against the base tables.
-- Mental model: a "virtual table" / a "named query".
-- WHY:  1) hide a complex join behind one simple name
--       2) security: expose only some columns / rows (GRANT SELECT on the view, not the table)
--       3) one place for business logic, so every report gets the same numbers

-- 1a. CREATE VIEW must be the FIRST statement in its batch (GO before it)
CREATE VIEW dbo.vw_L13_EmployeeDetails
AS
SELECT e.EmployeeID, e.EmployeeName, e.Email, e.Salary, e.HireDate,
       d.DepartmentName, d.Location
FROM dbo.Employees e
JOIN dbo.Departments d ON d.DepartmentID = e.DepartmentID;
GO

-- 1b. Use it like a table: WHERE, ORDER BY, GROUP BY, JOIN - all on the OUTER query
SELECT EmployeeName, DepartmentName, Salary
FROM dbo.vw_L13_EmployeeDetails
WHERE Location = 'Delhi'
ORDER BY Salary DESC;        -- 4 rows: Rahul 85000, Amit / Pooja 65000, Ravi 60000
GO
SELECT DepartmentName, COUNT(*) AS Staff, AVG(Salary) AS AvgSalary
FROM dbo.vw_L13_EmployeeDetails
GROUP BY DepartmentName
ORDER BY AvgSalary DESC;     -- Finance 81000, IT 71666.67, Marketing / Sales 64000, HR 60000 (Legal has no staff -> absent)
GO
-- 1c. Row count: the INNER JOIN hides Anjali (no department) -> 11, not 12
SELECT COUNT(*) AS RowsInView FROM dbo.vw_L13_EmployeeDetails;   -- 11
GO


/* ==== 2. ALTER VIEW / CREATE OR ALTER / DROP VIEW IF EXISTS ==== */
-- 2a. ALTER VIEW replaces the SELECT and KEEPS permissions. Fails if the view does not exist.
ALTER VIEW dbo.vw_L13_EmployeeDetails
AS
SELECT e.EmployeeID, e.EmployeeName, e.Email, e.Salary, e.HireDate,
       d.DepartmentName, d.Location
FROM dbo.Employees e
LEFT JOIN dbo.Departments d ON d.DepartmentID = e.DepartmentID;   -- LEFT: keep Anjali
GO
SELECT COUNT(*) AS RowsInView FROM dbo.vw_L13_EmployeeDetails;   -- 12
GO
-- 2b. CREATE OR ALTER (2016 SP1+): works whether or not the view exists. Use it in deploy scripts.
CREATE OR ALTER VIEW dbo.vw_L13_EmployeeDetails
AS
SELECT e.EmployeeID, e.EmployeeName, e.Email, e.Salary, e.Salary * 12 AS AnnualSalary,
       e.HireDate, d.DepartmentName, d.Location
FROM dbo.Employees e
LEFT JOIN dbo.Departments d ON d.DepartmentID = e.DepartmentID;
GO
SELECT EmployeeName, DepartmentName, AnnualSalary
FROM dbo.vw_L13_EmployeeDetails
WHERE DepartmentName IS NULL;   -- Anjali, NULL, 576000.00
GO
-- 2c. DROP VIEW IF EXISTS (2016+): silent when the view is already gone.
--     Dropping a view NEVER touches the base tables' data.
DROP VIEW IF EXISTS dbo.vw_L13_DoesNotExist;
GO


/* ==== 3. THE RULES ==== */
-- 3a. No ORDER BY inside a view (a view is a table; tables have no order).
--     CREATE VIEW must start a batch, so to SEE the error we run it as dynamic SQL in TRY/CATCH.
BEGIN TRY
    EXEC (N'CREATE VIEW dbo.vw_L13_Sorted AS SELECT e.EmployeeID, e.Salary FROM dbo.Employees e ORDER BY e.Salary DESC;');
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();   -- The ORDER BY clause is invalid in views ... unless TOP, OFFSET or FOR XML is also specified.
END CATCH
GO
-- 3b. Allowed WITH TOP / OFFSET-FETCH: then ORDER BY says WHICH rows to keep, not how to return them
CREATE OR ALTER VIEW dbo.vw_L13_TopSalaries
AS
SELECT TOP (3) e.EmployeeID, e.EmployeeName, e.Salary
FROM dbo.Employees e
ORDER BY e.Salary DESC;
GO
SELECT * FROM dbo.vw_L13_TopSalaries;                      -- 3 rows: Sneha 90000, Rahul 85000, Priya 75000 (order NOT guaranteed)
SELECT * FROM dbo.vw_L13_TopSalaries ORDER BY Salary ASC;  -- want an order? put ORDER BY on the OUTER query
GO
-- 3c. The "TOP 100 PERCENT ... ORDER BY" myth. It compiles, but TOP 100 PERCENT means
--     "all rows", so the optimizer simply throws the ORDER BY away. Order is NOT guaranteed.
CREATE OR ALTER VIEW dbo.vw_L13_Top100Myth
AS
SELECT TOP (100) PERCENT e.EmployeeID, e.EmployeeName, e.Salary
FROM dbo.Employees e
ORDER BY e.Salary DESC;
GO
SELECT * FROM dbo.vw_L13_Top100Myth;   -- comes back in EmployeeID order (101, 102, ...), NOT by Salary -> myth busted
GO
-- 3d. A view has NO parameters. Need one? Use an INLINE table-valued function (Level 15).
BEGIN TRY
    EXEC (N'CREATE VIEW dbo.vw_L13_ByDept @DeptID INT AS SELECT e.EmployeeID FROM dbo.Employees e WHERE e.DepartmentID = @DeptID;');
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();   -- Incorrect syntax near '@DeptID'.
END CATCH
GO
CREATE OR ALTER FUNCTION dbo.fn_L13_EmployeesByDept (@DepartmentID INT)
RETURNS TABLE
AS
RETURN
(
    SELECT e.EmployeeID, e.EmployeeName, e.Salary
    FROM dbo.Employees e
    WHERE e.DepartmentID = @DepartmentID
);
GO
SELECT * FROM dbo.fn_L13_EmployeesByDept(2);   -- 3 rows: Priya, Neha, Vikram  = "a view with a parameter"
GO
-- 3e. Every column needs a name: expressions must have an alias
BEGIN TRY
    EXEC (N'CREATE VIEW dbo.vw_L13_NoName AS SELECT e.EmployeeName, e.Salary * 12 FROM dbo.Employees e;');
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();   -- ... no column name was specified for column 2.
END CATCH
GO
-- Fix 1: alias in the SELECT (e.Salary * 12 AS AnnualSalary).  Fix 2: a column list after the view name:
CREATE OR ALTER VIEW dbo.vw_L13_AnnualSalary (EmployeeName, AnnualSalary)
AS
SELECT e.EmployeeName, e.Salary * 12
FROM dbo.Employees e;
GO
SELECT TOP (2) * FROM dbo.vw_L13_AnnualSalary ORDER BY AnnualSalary DESC;   -- Sneha 1080000, Rahul 1020000
GO
-- Other rules: no INTO, no temp tables, no variables, no OPTION clause, ONE SELECT (UNION inside is fine).


/* ==== 4. UPDATABLE VIEWS ==== */
-- You can INSERT / UPDATE / DELETE THROUGH a view when the statement touches ONE base
-- table and the affected columns are plain columns (no aggregates, DISTINCT, GROUP BY,
-- UNION, derived expressions). We practise on a COPY of Products.
SELECT * INTO dbo.L13_Products FROM dbo.Products;
ALTER TABLE dbo.L13_Products ADD CONSTRAINT PK_L13_Products PRIMARY KEY (ProductID);
GO
CREATE OR ALTER VIEW dbo.vw_L13_Electronics
AS
SELECT p.ProductID, p.ProductName, p.Category, p.Price, p.Stock
FROM dbo.L13_Products p
WHERE p.Category = 'Electronics';
GO
SELECT COUNT(*) AS ElectronicsRows FROM dbo.vw_L13_Electronics;   -- 6
GO
-- 4a. UPDATE through the view -> the base table changes
UPDATE dbo.vw_L13_Electronics SET Price = Price + 100 WHERE ProductID = 2;   -- Mouse 1000 -> 1100
SELECT ProductName, Price FROM dbo.L13_Products WHERE ProductID = 2;         -- Mouse 1100.00
GO
-- 4b. INSERT through the view -> lands in the base table
INSERT INTO dbo.vw_L13_Electronics (ProductID, ProductName, Category, Price, Stock)
VALUES (12, 'Speaker', 'Electronics', 1500, 20);
SELECT ProductID, ProductName FROM dbo.L13_Products WHERE ProductID = 12;   -- 12 Speaker
GO
-- 4c. TRAP: without CHECK OPTION you can insert a row the view itself cannot show
INSERT INTO dbo.vw_L13_Electronics (ProductID, ProductName, Category, Price, Stock)
VALUES (13, 'Lamp', 'Furniture', 900, 10);        -- succeeds!
SELECT COUNT(*) AS InView  FROM dbo.vw_L13_Electronics WHERE ProductID = 13;   -- 0  (invisible through the view)
SELECT COUNT(*) AS InTable FROM dbo.L13_Products     WHERE ProductID = 13;   -- 1  (but it IS in the table)
GO
-- 4d. DELETE through the view works the same way - and only sees what the view sees
DELETE FROM dbo.vw_L13_Electronics WHERE ProductID = 13;   -- 0 rows affected: the view cannot see the Lamp
DELETE FROM dbo.L13_Products WHERE ProductID = 13;         -- 1 row affected
GO
-- 4e. A statement that touches columns of TWO base tables fails. (It is a compile-time
--     error, so it is run as dynamic SQL to be catchable.) Wrapped in a transaction that
--     is rolled back, so the real Employees table is never changed.
BEGIN TRAN;
BEGIN TRY
    EXEC (N'UPDATE dbo.vw_L13_EmployeeDetails SET Salary = 1, Location = ''Goa'' WHERE EmployeeID = 101;');
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();   -- ... not updatable because the modification affects multiple base tables.
END CATCH
-- ... but ONE base table at a time works, even through a join view:
UPDATE dbo.vw_L13_EmployeeDetails SET Salary = Salary + 1000 WHERE EmployeeID = 101;
SELECT Salary AS InsideTran FROM dbo.Employees WHERE EmployeeID = 101;     -- 86000.00
ROLLBACK TRAN;
SELECT Salary AS AfterRollback FROM dbo.Employees WHERE EmployeeID = 101;  -- 85000.00 (untouched)
GO
-- 4f. Aggregated / grouped views are read-only
CREATE OR ALTER VIEW dbo.vw_L13_StaffPerDept
AS
SELECT d.DepartmentName, COUNT(e.EmployeeID) AS Staff
FROM dbo.Departments d
LEFT JOIN dbo.Employees e ON e.DepartmentID = d.DepartmentID
GROUP BY d.DepartmentName;
GO
SELECT * FROM dbo.vw_L13_StaffPerDept ORDER BY Staff DESC, DepartmentName;   -- IT 3, Sales 3, Finance 2, Marketing 2, HR 1, Legal 0
BEGIN TRY
    EXEC (N'UPDATE dbo.vw_L13_StaffPerDept SET DepartmentName = ''Law'' WHERE DepartmentName = ''Legal'';');
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();   -- ... contains aggregates, or a DISTINCT or GROUP BY clause ...
END CATCH
GO


/* ==== 5. WITH CHECK OPTION ==== */
-- Adds a rule: every INSERT / UPDATE through the view must produce rows the view can still see.
CREATE OR ALTER VIEW dbo.vw_L13_Electronics
AS
SELECT p.ProductID, p.ProductName, p.Category, p.Price, p.Stock
FROM dbo.L13_Products p
WHERE p.Category = 'Electronics'
WITH CHECK OPTION;
GO
-- 5a. Moving a row OUT of the view now fails
BEGIN TRY
    UPDATE dbo.vw_L13_Electronics SET Category = 'Furniture' WHERE ProductID = 12;   -- Speaker
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();   -- ... did not qualify under the CHECK OPTION constraint.
END CATCH
GO
-- 5b. Inserting an invisible row fails too (the Lamp trick from 4c is blocked)
BEGIN TRY
    INSERT INTO dbo.vw_L13_Electronics (ProductID, ProductName, Category, Price, Stock)
    VALUES (14, 'Table', 'Furniture', 7000, 5);
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO
-- 5c. Changes that keep the row inside the view are fine
UPDATE dbo.vw_L13_Electronics SET Stock = Stock - 1 WHERE ProductID = 12;
SELECT ProductName, Category, Stock FROM dbo.vw_L13_Electronics WHERE ProductID = 12;   -- Speaker, Electronics, 19
GO
-- Where to see it: sys.views.with_check_option
SELECT name, with_check_option FROM sys.views WHERE name = 'vw_L13_Electronics';   -- 1
GO


/* ==== 6. CLEANUP ==== */
DROP VIEW IF EXISTS dbo.vw_L13_EmployeeDetails, dbo.vw_L13_TopSalaries, dbo.vw_L13_Top100Myth,
                    dbo.vw_L13_AnnualSalary, dbo.vw_L13_Electronics, dbo.vw_L13_StaffPerDept,
                    dbo.vw_L13_Sorted, dbo.vw_L13_ByDept, dbo.vw_L13_NoName;
DROP FUNCTION IF EXISTS dbo.fn_L13_EmployeesByDept;
DROP TABLE IF EXISTS dbo.L13_Products;
GO
/* DONE. Next: 02_Practice_View_Options_Indexed.sql */
