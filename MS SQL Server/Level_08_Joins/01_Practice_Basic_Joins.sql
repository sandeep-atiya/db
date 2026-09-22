/* ============================================================
   LEVEL 08 - JOINS  |  01_Practice_Basic_Joins.sql
   ------------------------------------------------------------
   Topics : why joins (normalisation), INNER JOIN, LEFT JOIN,
            RIGHT JOIN, FULL OUTER JOIN, CROSS JOIN (helper tables
            dbo.L08_Sizes / dbo.L08_Colors + a useful cross join),
            SELF JOIN (employee-manager), joining 3-5 tables with a
            diagram, join + WHERE + GROUP BY (revenue per category,
            per city).
   HOW TO PRACTICE: run block by block, predict the output first.
   Creates dbo.L08_Sizes and dbo.L08_Colors; drops them at the end.
   ============================================================ */

USE SQLPractice;
GO
DROP TABLE IF EXISTS dbo.L08_Sizes;
DROP TABLE IF EXISTS dbo.L08_Colors;
GO


/* ==== 1. WHY JOINS?  (normalisation) ==== */
-- Employees stores only DepartmentID (a number). The department NAME lives once, in Departments.
-- That is normalisation: store each fact once, link with keys. A JOIN puts the pieces back together.
SELECT EmployeeID, EmployeeName, DepartmentID FROM dbo.Employees WHERE EmployeeID IN (101, 110);   -- 1, NULL - meaningless alone
SELECT DepartmentID, DepartmentName, Location FROM dbo.Departments;                                 -- the lookup
GO


/* ==== 2. INNER JOIN  (only rows that match on BOTH sides) ==== */

-- 2a. Employees with their department name. Anjali (DepartmentID NULL) has no match -> she is NOT in the result.
SELECT e.EmployeeID, e.EmployeeName, d.DepartmentName, d.Location
FROM dbo.Employees e
INNER JOIN dbo.Departments d ON d.DepartmentID = e.DepartmentID
ORDER BY e.EmployeeID;   -- 11 rows (12 employees - Anjali). Legal never appears either (no employees).
GO

-- 2b. "JOIN" alone means INNER JOIN. Orders with customer name: every order has a customer -> all 19 rows.
SELECT o.OrderID, o.OrderDate, c.CustomerName, c.City, o.TotalAmount
FROM dbo.Orders o
JOIN dbo.Customers c ON c.CustomerID = o.CustomerID
ORDER BY o.OrderID;   -- 19 rows; Hina (no orders) is absent
GO

-- 2c. Always use aliases and prefix every column: which table does "Email" come from?
SELECT e.EmployeeName, e.Email AS EmployeeEmail, d.DepartmentName
FROM dbo.Employees e
JOIN dbo.Departments d ON d.DepartmentID = e.DepartmentID
WHERE d.DepartmentName = 'IT';   -- Rahul, Amit, Pooja (3 rows)
GO


/* ==== 3. LEFT JOIN  (ALL rows from the left table + matches from the right, NULL where no match) ==== */

-- 3a. All employees, department name if any. Anjali appears with NULL department.
SELECT e.EmployeeName, e.DepartmentID, d.DepartmentName
FROM dbo.Employees e
LEFT JOIN dbo.Departments d ON d.DepartmentID = e.DepartmentID
ORDER BY e.EmployeeID;   -- 12 rows, last one: Anjali NULL NULL
GO

-- 3b. All customers, with their orders if any. Hina appears once with NULL order columns.
SELECT c.CustomerName, o.OrderID, o.TotalAmount
FROM dbo.Customers c
LEFT JOIN dbo.Orders o ON o.CustomerID = c.CustomerID
ORDER BY c.CustomerID, o.OrderID;   -- 20 rows = 19 orders + 1 row for Hina (NULL, NULL)
GO

-- 3c. Only the unmatched ones = "customers with no orders" (anti-join, more in file 02)
SELECT c.CustomerName
FROM dbo.Customers c
LEFT JOIN dbo.Orders o ON o.CustomerID = c.CustomerID
WHERE o.OrderID IS NULL;   -- Hina Khan
GO

-- 3d. LEFT JOIN + ISNULL to give the NULL a friendly label
SELECT e.EmployeeName, ISNULL(d.DepartmentName, '(contractor)') AS Department
FROM dbo.Employees e
LEFT JOIN dbo.Departments d ON d.DepartmentID = e.DepartmentID
WHERE e.EmployeeID IN (101, 110);   -- Rahul IT, Anjali (contractor)
GO


/* ==== 4. RIGHT JOIN  (ALL rows from the RIGHT table) ==== */

-- 4a. Every department, with its employees if any. Legal appears with NULL employee.
SELECT d.DepartmentName, e.EmployeeName
FROM dbo.Employees e
RIGHT JOIN dbo.Departments d ON d.DepartmentID = e.DepartmentID
ORDER BY d.DepartmentID, e.EmployeeName;   -- 12 rows = 11 matches + Legal NULL. Anjali is NOT here (right join keeps departments, not employees).
GO

-- 4b. Same result written as a LEFT JOIN by swapping the tables. Most teams write LEFT only - easier to read.
SELECT d.DepartmentName, e.EmployeeName
FROM dbo.Departments d
LEFT JOIN dbo.Employees e ON e.DepartmentID = d.DepartmentID
ORDER BY d.DepartmentID, e.EmployeeName;   -- identical 12 rows
GO

-- 4c. Departments with no employees
SELECT d.DepartmentName
FROM dbo.Departments d
LEFT JOIN dbo.Employees e ON e.DepartmentID = d.DepartmentID
WHERE e.EmployeeID IS NULL;   -- Legal
GO


/* ==== 5. FULL OUTER JOIN  (everything from BOTH sides) ==== */

-- Matches + unmatched employees (Anjali) + unmatched departments (Legal).
SELECT e.EmployeeName, d.DepartmentName
FROM dbo.Employees e
FULL OUTER JOIN dbo.Departments d ON d.DepartmentID = e.DepartmentID
ORDER BY d.DepartmentID, e.EmployeeName;   -- 13 rows = 11 + Anjali (NULL dept) + Legal (NULL employee)
GO

-- Only the orphans on either side (classic data-quality check)
SELECT e.EmployeeName, d.DepartmentName
FROM dbo.Employees e
FULL OUTER JOIN dbo.Departments d ON d.DepartmentID = e.DepartmentID
WHERE e.EmployeeID IS NULL OR d.DepartmentID IS NULL;   -- Anjali NULL ; NULL Legal  (2 rows)
GO


/* ==== 6. CROSS JOIN  (every row of A with every row of B = n x m) ==== */

-- 6a. Helper tables
CREATE TABLE dbo.L08_Sizes  (SizeName  VARCHAR(10) NOT NULL);
CREATE TABLE dbo.L08_Colors (ColorName VARCHAR(10) NOT NULL);
INSERT INTO dbo.L08_Sizes  VALUES ('Small'), ('Medium'), ('Large');
INSERT INTO dbo.L08_Colors VALUES ('Red'), ('Blue');
GO

-- 6b. No ON clause: 3 sizes x 2 colours = 6 combinations (product variants)
SELECT s.SizeName, c.ColorName, CONCAT(s.SizeName, '-', c.ColorName) AS Variant
FROM dbo.L08_Sizes s
CROSS JOIN dbo.L08_Colors c
ORDER BY s.SizeName, c.ColorName;   -- 6 rows
GO

-- 6c. USEFUL cross join: a complete grid of all months x all departments (9 x 6 = 54 rows),
--     so a report can show 0 instead of missing rows. GENERATE_SERIES is 2022+.
SELECT COUNT(*) AS GridRows
FROM GENERATE_SERIES(1, 9) AS m
CROSS JOIN dbo.Departments d;   -- 54
GO

-- 6d. Grid + LEFT JOIN to the facts = zero-filled matrix: orders per month per status (9 x 3 = 27 rows)
SELECT m.value AS Mth, s.Status, COUNT(o.OrderID) AS Orders
FROM GENERATE_SERIES(1, 9) AS m
CROSS JOIN (VALUES ('Pending'), ('Completed'), ('Cancelled')) AS s(Status)
LEFT JOIN dbo.Orders o ON MONTH(o.OrderDate) = m.value AND o.Status = s.Status
GROUP BY m.value, s.Status
ORDER BY m.value, s.Status;   -- 27 rows; e.g. 2 Cancelled 1, 2 Completed 2, 2 Pending 0
GO

-- 6e. Accidental cross join = forgetting the ON condition in old-style syntax (see file 02). 12 x 6 = 72 rows:
SELECT COUNT(*) AS Oops FROM dbo.Employees e CROSS JOIN dbo.Departments d;   -- 72
GO


/* ==== 7. SELF JOIN  (a table joined to itself - needs two aliases) ==== */

-- 7a. Employee -> manager name. ManagerID points to another EmployeeID in the SAME table.
--     LEFT JOIN so heads (ManagerID NULL) stay in the list.
SELECT e.EmployeeName AS Employee, e.ManagerID, m.EmployeeName AS Manager
FROM dbo.Employees e
LEFT JOIN dbo.Employees m ON m.EmployeeID = e.ManagerID
ORDER BY e.EmployeeID;   -- 12 rows: Amit -> Rahul, Neha -> Priya, Pooja -> Rahul, Vikram -> Priya, Deepak -> Sneha, Meera -> Karan, rest NULL
GO

-- 7b. Direct reports per manager (INNER: only employees who HAVE a manager)
SELECT m.EmployeeName AS Manager, COUNT(*) AS Reports, STRING_AGG(e.EmployeeName, ', ') AS Team
FROM dbo.Employees e
JOIN dbo.Employees m ON m.EmployeeID = e.ManagerID
GROUP BY m.EmployeeName
ORDER BY Reports DESC, Manager;   -- Priya 2 (Neha, Vikram), Rahul 2 (Amit, Pooja), Karan 1, Sneha 1
GO

-- 7c. Employees earning MORE than their manager: none in this company -> 0 rows (the query is still right!)
SELECT e.EmployeeName, e.Salary, m.EmployeeName AS Manager, m.Salary AS ManagerSalary
FROM dbo.Employees e
JOIN dbo.Employees m ON m.EmployeeID = e.ManagerID
WHERE e.Salary > m.Salary;   -- 0 rows
GO

-- 7d. Employees earning at least 80% of their manager's salary
SELECT e.EmployeeName, e.Salary, m.EmployeeName AS Manager, m.Salary AS ManagerSalary,
       CAST(e.Salary * 100.0 / m.Salary AS DECIMAL(5,1)) AS PctOfManager
FROM dbo.Employees e
JOIN dbo.Employees m ON m.EmployeeID = e.ManagerID
WHERE e.Salary >= m.Salary * 0.8
ORDER BY PctOfManager DESC;   -- Meera 82.9, Vikram 82.7, Deepak 80.0
GO


/* ==== 8. JOINING 3-5 TABLES ==== */
/*
   Follow the foreign keys. Each JOIN adds one table; each ON links it to a table already in the query.

        Departments                  Products
             ^ DepartmentID               ^ ProductID
             |                            |
        Employees  <---- EmployeeID ---- Orders ----> OrderID ----> OrderDetails
                                           |
                                           v CustomerID
                                       Customers

   Orders.EmployeeID can be NULL (online order) -> that link must be a LEFT JOIN
   or order 1019 silently disappears.
*/

-- 8a. 3 tables: order -> customer -> salesperson  (LEFT for the salesperson!)
SELECT o.OrderID, c.CustomerName, ISNULL(e.EmployeeName, 'Online') AS Salesperson, o.TotalAmount
FROM dbo.Orders o
JOIN      dbo.Customers c ON c.CustomerID = o.CustomerID
LEFT JOIN dbo.Employees e ON e.EmployeeID = o.EmployeeID
ORDER BY o.OrderID;   -- 19 rows; 1019 Bhavna Mehta Online 2500
GO

-- 8b. 5 tables: one row per ORDER LINE with everything a report needs. Order 1008 only (3 lines).
SELECT o.OrderID, o.OrderDate, c.CustomerName, c.City,
       e.EmployeeName AS Salesperson, d.DepartmentName,
       p.ProductName, od.Quantity, od.UnitPrice, od.Quantity * od.UnitPrice AS LineTotal
FROM dbo.Orders o
JOIN      dbo.Customers    c  ON c.CustomerID   = o.CustomerID
LEFT JOIN dbo.Employees    e  ON e.EmployeeID   = o.EmployeeID
LEFT JOIN dbo.Departments  d  ON d.DepartmentID = e.DepartmentID
JOIN      dbo.OrderDetails od ON od.OrderID     = o.OrderID
JOIN      dbo.Products     p  ON p.ProductID    = od.ProductID
WHERE o.OrderID = 1008
ORDER BY od.OrderDetailID;   -- Farhan Ali, Mumbai, Vikram, Sales: Laptop 1 75000 | Mouse 1 1000 | Keyboard 1 2500
GO

-- 8c. Same 5-table join over ALL orders: 26 rows (one per line), total 618000
SELECT COUNT(*) AS Lines, SUM(od.Quantity * od.UnitPrice) AS Revenue
FROM dbo.Orders o
JOIN      dbo.Customers    c  ON c.CustomerID   = o.CustomerID
LEFT JOIN dbo.Employees    e  ON e.EmployeeID   = o.EmployeeID
LEFT JOIN dbo.Departments  d  ON d.DepartmentID = e.DepartmentID
JOIN      dbo.OrderDetails od ON od.OrderID     = o.OrderID
JOIN      dbo.Products     p  ON p.ProductID    = od.ProductID;   -- 26, 618000.00
GO


/* ==== 9. JOIN + WHERE + GROUP BY ==== */
-- Order of thinking: join the tables -> filter rows (WHERE) -> group -> aggregate -> sort.

-- 9a. Revenue per product CATEGORY, Completed orders only
SELECT p.Category, COUNT(*) AS Lines, SUM(od.Quantity) AS Units, SUM(od.Quantity * od.UnitPrice) AS Revenue
FROM dbo.OrderDetails od
JOIN dbo.Products p ON p.ProductID = od.ProductID
JOIN dbo.Orders   o ON o.OrderID   = od.OrderID
WHERE o.Status = 'Completed'
GROUP BY p.Category
ORDER BY Revenue DESC;   -- Electronics 16 32 507500 | Furniture 4 5 65000 | Stationery 2 70 1500   (sums to 574000)
GO

-- 9b. Revenue per customer CITY (all orders), with distinct customers and order count
SELECT c.City, COUNT(DISTINCT c.CustomerID) AS Customers, COUNT(o.OrderID) AS Orders, SUM(o.TotalAmount) AS Revenue
FROM dbo.Customers c
JOIN dbo.Orders o ON o.CustomerID = c.CustomerID
GROUP BY c.City
ORDER BY Revenue DESC;   -- Delhi 2 7 158500 | Bangalore 1 2 158000 | Mumbai 2 6 137000 | Chennai 1 2 87000 | Pune 1 2 77500
GO
-- (Delhi has 3 customers, but Hina never ordered -> INNER JOIN counts 2. Use LEFT JOIN to count her.)

-- 9c. Best-selling product per category is Level 11 (window functions); with plain GROUP BY you can do units per product:
SELECT p.Category, p.ProductName, SUM(od.Quantity) AS Units
FROM dbo.Products p
JOIN dbo.OrderDetails od ON od.ProductID = p.ProductID
GROUP BY p.Category, p.ProductName
HAVING SUM(od.Quantity) >= 5
ORDER BY p.Category, Units DESC;   -- Electronics: Mouse 14, Monitor 7, Keyboard 5 | Furniture: Chair 6 | Stationery: Pen 150, Notebook 20
GO


/* ==== 10. CLEANUP ==== */
DROP TABLE IF EXISTS dbo.L08_Sizes;
DROP TABLE IF EXISTS dbo.L08_Colors;
GO
/* DONE. Next: 02_Practice_Join_Traps.sql */
