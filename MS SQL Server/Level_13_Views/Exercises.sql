/* ============================================================
   LEVEL 13 - VIEWS  |  Exercises.sql
   ------------------------------------------------------------
   Try each question in the "YOUR ANSWERS" area FIRST.
   Then scroll down to SOLUTIONS and compare.
   Data changes happen only on copy tables (dbo.L13_Employees).
   ============================================================ */

USE SQLPractice;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;   -- needed for Q6 / Q8 (schema-bound + indexed views)
GO

/* ------------------------------------------------------------
   QUESTIONS
   ------------------------------------------------------------
   Q1.  Create dbo.vw_L13_CustomerOrders: every customer (LEFT JOIN) with
        CustomerName, City, OrderID, OrderDate, TotalAmount, Status.
        How many rows does the view return? Why not 19?

   Q2.  Using the view, show Completed revenue per City, highest first.

   Q3.  With CREATE OR ALTER, add a column OrderYear = YEAR(OrderDate) to the
        view. Then count orders per OrderYear through the view.

   Q4.  Try to create a view with ORDER BY TotalAmount DESC (no TOP) and catch
        the error. Then write the correct way to get the 2 biggest orders
        from dbo.vw_L13_CustomerOrders.

   Q5.  Make a copy dbo.L13_Employees. Create dbo.vw_L13_ITStaff over it with
        EmployeeID, EmployeeName, DepartmentID WHERE DepartmentID = 1 and
        WITH CHECK OPTION. Insert (113, 'Test IT', 1) through the view, then
        try (114, 'Test Sales', 2) inside TRY/CATCH. Count the rows in the view.

   Q6.  Create dbo.vw_L13_EmpSalaries WITH SCHEMABINDING (EmployeeID, Salary)
        over dbo.L13_Employees. Try to DROP COLUMN Salary (TRY/CATCH).
        Then drop the view and drop the column successfully.

   Q7.  Create dbo.vw_L13_AllEmp AS SELECT * FROM dbo.L13_Employees. Add a
        column Phone VARCHAR(15) to the table. Show the view's column count
        before and after sp_refreshview.

   Q8.  Indexed view: dbo.vw_L13_SalesByEmployee over dbo.Orders grouped by
        EmployeeID with OrderCount (COUNT_BIG) and Revenue (SUM of TotalAmount,
        remember TotalAmount is nullable). Create the unique clustered index and
        query it WITH (NOEXPAND).

   Q9.  List every view whose name starts with vw_L13_ with: is it schema-bound,
        does it have CHECK OPTION, and the first 40 characters of its definition.

   Q10. Which tables and columns does dbo.vw_L13_CustomerOrders depend on?

   Q11. (Interview - answer as a comment) A report joins 5 tables and is run by
        20 people through 3 different tools. Views, a CTE, or a temp table? Why?
        And when would you make that view an indexed view?
   ------------------------------------------------------------ */

-- YOUR ANSWERS HERE (write below, run, compare)










/* ============================================================
   SOLUTIONS
   ============================================================ */

-- Q1
DROP VIEW IF EXISTS dbo.vw_L13_CustomerOrders;
GO
CREATE VIEW dbo.vw_L13_CustomerOrders
AS
SELECT c.CustomerID, c.CustomerName, c.City,
       o.OrderID, o.OrderDate, o.TotalAmount, o.Status
FROM dbo.Customers c
LEFT JOIN dbo.Orders o ON o.CustomerID = c.CustomerID;
GO
SELECT COUNT(*) AS RowsInView FROM dbo.vw_L13_CustomerOrders;   -- 20 = 19 orders + Hina Khan (no orders, NULL order columns)
GO

-- Q2
SELECT City, SUM(TotalAmount) AS CompletedRevenue
FROM dbo.vw_L13_CustomerOrders
WHERE Status = 'Completed'
GROUP BY City
ORDER BY CompletedRevenue DESC;   -- Bangalore 150000, Mumbai 137000, Delhi 122500, Chennai 87000, Pune 77500
GO

-- Q3
CREATE OR ALTER VIEW dbo.vw_L13_CustomerOrders
AS
SELECT c.CustomerID, c.CustomerName, c.City,
       o.OrderID, o.OrderDate, YEAR(o.OrderDate) AS OrderYear, o.TotalAmount, o.Status
FROM dbo.Customers c
LEFT JOIN dbo.Orders o ON o.CustomerID = c.CustomerID;
GO
SELECT OrderYear, COUNT(OrderID) AS Orders
FROM dbo.vw_L13_CustomerOrders
GROUP BY OrderYear;   -- NULL 0 (Hina), 2025 19
GO

-- Q4
BEGIN TRY
    EXEC (N'CREATE VIEW dbo.vw_L13_Biggest AS SELECT OrderID, TotalAmount FROM dbo.Orders ORDER BY TotalAmount DESC;');
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();   -- The ORDER BY clause is invalid in views ...
END CATCH
GO
-- Correct: sort the OUTER query (a view is a table; tables have no order)
SELECT TOP (2) CustomerName, OrderID, TotalAmount
FROM dbo.vw_L13_CustomerOrders
ORDER BY TotalAmount DESC;   -- Esha Kapoor 1014 150000, Farhan Ali 1008 78500
GO

-- Q5
DROP VIEW IF EXISTS dbo.vw_L13_ITStaff, dbo.vw_L13_EmpSalaries, dbo.vw_L13_AllEmp;
DROP TABLE IF EXISTS dbo.L13_Employees;
SELECT * INTO dbo.L13_Employees FROM dbo.Employees;
ALTER TABLE dbo.L13_Employees ADD CONSTRAINT PK_L13_Employees PRIMARY KEY (EmployeeID);
GO
CREATE VIEW dbo.vw_L13_ITStaff
AS
SELECT e.EmployeeID, e.EmployeeName, e.DepartmentID
FROM dbo.L13_Employees e
WHERE e.DepartmentID = 1
WITH CHECK OPTION;
GO
INSERT INTO dbo.vw_L13_ITStaff (EmployeeID, EmployeeName, DepartmentID) VALUES (113, 'Test IT', 1);   -- OK
BEGIN TRY
    INSERT INTO dbo.vw_L13_ITStaff (EmployeeID, EmployeeName, DepartmentID) VALUES (114, 'Test Sales', 2);
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();   -- ... did not qualify under the CHECK OPTION constraint.
END CATCH
SELECT COUNT(*) AS ITStaff FROM dbo.vw_L13_ITStaff;   -- 4: Rahul, Amit, Pooja, Test IT
GO

-- Q6
CREATE VIEW dbo.vw_L13_EmpSalaries
WITH SCHEMABINDING
AS
SELECT e.EmployeeID, e.Salary FROM dbo.L13_Employees e;
GO
BEGIN TRY
    ALTER TABLE dbo.L13_Employees DROP COLUMN Salary;
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();   -- ALTER TABLE DROP COLUMN Salary failed because one or more objects access this column.
END CATCH
GO
DROP VIEW dbo.vw_L13_EmpSalaries;
ALTER TABLE dbo.L13_Employees DROP COLUMN Salary;   -- now OK
SELECT COUNT(*) AS ColumnsLeft FROM sys.columns WHERE object_id = OBJECT_ID('dbo.L13_Employees');   -- 6
GO

-- Q7
CREATE VIEW dbo.vw_L13_AllEmp AS SELECT * FROM dbo.L13_Employees;
GO
SELECT COUNT(*) AS ViewColsBefore FROM sys.columns WHERE object_id = OBJECT_ID('dbo.vw_L13_AllEmp');   -- 6
ALTER TABLE dbo.L13_Employees ADD Phone VARCHAR(15) NULL;
SELECT COUNT(*) AS ViewColsAfterAdd FROM sys.columns WHERE object_id = OBJECT_ID('dbo.vw_L13_AllEmp');  -- still 6
EXEC sp_refreshview 'dbo.vw_L13_AllEmp';
SELECT COUNT(*) AS ViewColsAfterRefresh FROM sys.columns WHERE object_id = OBJECT_ID('dbo.vw_L13_AllEmp');   -- 7
GO

-- Q8
DROP VIEW IF EXISTS dbo.vw_L13_SalesByEmployee;
GO
CREATE VIEW dbo.vw_L13_SalesByEmployee
WITH SCHEMABINDING
AS
SELECT o.EmployeeID,
       COUNT_BIG(*)                    AS OrderCount,
       SUM(ISNULL(o.TotalAmount, 0))   AS Revenue      -- SUM needs a NOT NULL expression -> ISNULL
FROM dbo.Orders o
GROUP BY o.EmployeeID;
GO
CREATE UNIQUE CLUSTERED INDEX IX_vw_L13_SalesByEmployee ON dbo.vw_L13_SalesByEmployee (EmployeeID);
GO
SELECT EmployeeID, OrderCount, Revenue
FROM dbo.vw_L13_SalesByEmployee WITH (NOEXPAND)
ORDER BY Revenue DESC;   -- 103 7 293000, 109 5 250500, 104 6 72000, NULL 1 2500 (online order)
GO

-- Q9
SELECT v.name, m.is_schema_bound, v.with_check_option, LEFT(m.definition, 40) AS DefinitionStart
FROM sys.views v
JOIN sys.sql_modules m ON m.object_id = v.object_id
WHERE v.name LIKE 'vw[_]L13[_]%'
ORDER BY v.name;   -- 4 rows: AllEmp, CustomerOrders, ITStaff (check option 1), SalesByEmployee (schema-bound 1)
GO

-- Q10
SELECT referenced_entity_name AS TableName, referenced_minor_name AS ColumnName
FROM sys.dm_sql_referenced_entities('dbo.vw_L13_CustomerOrders', 'OBJECT')
WHERE referenced_minor_name IS NOT NULL
ORDER BY TableName, ColumnName;   -- Customers: City, CustomerID, CustomerName; Orders: CustomerID, OrderDate, OrderID, Status, TotalAmount
GO

-- Q11
/*
 A VIEW: 20 people x 3 tools must all get the same join logic and the same numbers, and
 a view is the only one of the three that is a permanent, shareable, securable object.
 A CTE lives inside one query (each tool would copy the SQL); a temp table lives in one
 session (nobody else can read it and it must be rebuilt every time).
 Make it an INDEXED view when the report aggregates a lot of rows, is read far more
 often than the base tables change, and the base tables are not hot OLTP tables
 (every write then has to maintain the index; SCHEMABINDING blocks schema changes).
*/

-- CLEANUP
DROP VIEW IF EXISTS dbo.vw_L13_SalesByEmployee, dbo.vw_L13_AllEmp, dbo.vw_L13_ITStaff,
                    dbo.vw_L13_EmpSalaries, dbo.vw_L13_CustomerOrders, dbo.vw_L13_Biggest;
DROP TABLE IF EXISTS dbo.L13_Employees;
GO
