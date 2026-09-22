/* ============================================================
   LEVEL 08 - JOINS  |  02_Practice_Join_Traps.sql
   ------------------------------------------------------------
   Topics : ON vs WHERE trap on outer joins, anti-join
            (LEFT JOIN ... IS NULL), semi-join preview (EXISTS),
            join on multiple conditions / non-equi join
            (dbo.L08_SalaryBands), NULL keys never match,
            duplicate rows from one-to-many joins (and the fix),
            old-style comma joins, join order (INNER vs OUTER),
            USING is not supported in T-SQL.
   HOW TO PRACTICE: run block by block, predict the output first.
   Creates dbo.L08_SalaryBands; drops it at the end.
   ============================================================ */

USE SQLPractice;
GO
DROP TABLE IF EXISTS dbo.L08_SalaryBands;
GO


/* ==== 1. THE ON vs WHERE TRAP  (a WHERE on the right table turns LEFT JOIN into INNER JOIN) ==== */

-- 1a. Goal: every customer and their COMPLETED orders. Attempt 1: filter in WHERE.
--     Hina's row has o.Status = NULL; NULL = 'Completed' is not true -> WHERE removes her. LEFT JOIN wasted.
SELECT c.CustomerName, o.OrderID, o.Status
FROM dbo.Customers c
LEFT JOIN dbo.Orders o ON o.CustomerID = c.CustomerID
WHERE o.Status = 'Completed'
ORDER BY c.CustomerID, o.OrderID;   -- 16 rows, NO Hina (behaves exactly like INNER JOIN)
GO

-- 1b. Correct: put the right-table filter in the ON clause. Unmatched customers survive with NULLs.
SELECT c.CustomerName, o.OrderID, o.Status
FROM dbo.Customers c
LEFT JOIN dbo.Orders o ON o.CustomerID = c.CustomerID AND o.Status = 'Completed'
ORDER BY c.CustomerID, o.OrderID;   -- 17 rows = 16 completed + Hina (NULL, NULL)
GO

-- 1c. Why it matters: counting. "Completed orders per customer, everyone listed."
SELECT c.CustomerName, COUNT(o.OrderID) AS CompletedOrders
FROM dbo.Customers c
LEFT JOIN dbo.Orders o ON o.CustomerID = c.CustomerID AND o.Status = 'Completed'
GROUP BY c.CustomerName
ORDER BY c.CustomerName;   -- 8 rows; Esha 1 (her other order is Cancelled), Hina 0
GO

-- 1d. A WHERE on the LEFT table is fine - it does not touch the outer-join logic
SELECT c.CustomerName, o.OrderID
FROM dbo.Customers c
LEFT JOIN dbo.Orders o ON o.CustomerID = c.CustomerID
WHERE c.City = 'Delhi'
ORDER BY c.CustomerID, o.OrderID;   -- 8 rows: Aarav x4, Chirag x3, Hina NULL
GO
-- RULE: for INNER JOIN, ON and WHERE give the same result. For OUTER joins they do NOT.


/* ==== 2. ANTI-JOIN  (rows in A that have NO match in B) ==== */

-- 2a. Pattern: LEFT JOIN, then keep only rows where the right side's KEY is NULL.
--     Test a NOT NULL column of the right table (its PK), never a nullable one.
SELECT p.ProductID, p.ProductName
FROM dbo.Products p
LEFT JOIN dbo.OrderDetails od ON od.ProductID = p.ProductID
WHERE od.OrderDetailID IS NULL;   -- Webcam (never ordered)
GO

-- 2b. Employees who never handled an order (9 of 12)
SELECT e.EmployeeName
FROM dbo.Employees e
LEFT JOIN dbo.Orders o ON o.EmployeeID = e.EmployeeID
WHERE o.OrderID IS NULL
ORDER BY e.EmployeeName;   -- everyone except Neha, Priya, Vikram -> 9 rows
GO

-- 2c. Same question with NOT EXISTS (usually clearer, same plan, no duplicate risk)
SELECT p.ProductName
FROM dbo.Products p
WHERE NOT EXISTS (SELECT 1 FROM dbo.OrderDetails od WHERE od.ProductID = p.ProductID);   -- Webcam
GO


/* ==== 3. SEMI-JOIN PREVIEW  (rows in A that HAVE a match in B - without duplicates) ==== */

-- 3a. "Customers who placed at least one order". A JOIN repeats Aarav 4 times ...
SELECT c.CustomerName
FROM dbo.Customers c
JOIN dbo.Orders o ON o.CustomerID = c.CustomerID
ORDER BY c.CustomerName;   -- 19 rows (names repeated)
GO

-- 3b. ... DISTINCT fixes the output, but EXISTS says what you MEAN and stops at the first match.
SELECT c.CustomerName
FROM dbo.Customers c
WHERE EXISTS (SELECT 1 FROM dbo.Orders o WHERE o.CustomerID = c.CustomerID)
ORDER BY c.CustomerName;   -- 7 rows, each once (Level 09 covers EXISTS fully)
GO


/* ==== 4. JOIN ON MULTIPLE CONDITIONS / NON-EQUI JOIN ==== */

-- 4a. Helper: salary bands as RANGES. No key to match on - the join condition is BETWEEN.
CREATE TABLE dbo.L08_SalaryBands
(
    BandName  VARCHAR(10)   NOT NULL,
    MinSalary DECIMAL(12,2) NOT NULL,
    MaxSalary DECIMAL(12,2) NOT NULL
);
INSERT INTO dbo.L08_SalaryBands VALUES ('Junior', 0, 59999.99), ('Mid', 60000, 74999.99), ('Senior', 75000, 9999999);
GO

-- 4b. Non-equi join: each employee lands in the band whose range contains the salary
SELECT b.BandName, e.EmployeeName, e.Salary
FROM dbo.Employees e
JOIN dbo.L08_SalaryBands b ON e.Salary BETWEEN b.MinSalary AND b.MaxSalary
ORDER BY e.Salary DESC;   -- Senior: Sneha, Rahul, Priya | Mid: Deepak, Karan, Amit, Pooja, Vikram, Ravi | Junior: Meera, Neha, Anjali
GO
SELECT b.BandName, COUNT(e.EmployeeID) AS Employees
FROM dbo.L08_SalaryBands b
LEFT JOIN dbo.Employees e ON e.Salary BETWEEN b.MinSalary AND b.MaxSalary
GROUP BY b.BandName
ORDER BY MIN(b.MinSalary);   -- Junior 3, Mid 6, Senior 3
GO

-- 4c. Several conditions with AND: order lines whose UnitPrice differs from the current list price
SELECT od.OrderID, p.ProductName, od.UnitPrice, p.Price
FROM dbo.OrderDetails od
JOIN dbo.Products p ON p.ProductID = od.ProductID AND od.UnitPrice <> p.Price;   -- 0 rows (no price changed yet)
GO

-- 4d. Self non-equi join: PAIRS of orders by the same customer (each pair once thanks to <)
SELECT o1.CustomerID, o1.OrderID AS FirstOrder, o2.OrderID AS LaterOrder, DATEDIFF(day, o1.OrderDate, o2.OrderDate) AS DaysBetween
FROM dbo.Orders o1
JOIN dbo.Orders o2 ON o2.CustomerID = o1.CustomerID AND o2.OrderID > o1.OrderID
ORDER BY o1.CustomerID, o1.OrderID, o2.OrderID;   -- 19 pairs (customer 1: 6 pairs, 2: 6, 3: 3, 4: 1, 5: 1, 6: 1, 7: 1)
GO


/* ==== 5. NULL KEYS NEVER MATCH ==== */

-- 5a. NULL is not equal to anything, not even NULL. So a NULL foreign key can never join.
SELECT CASE WHEN NULL = NULL THEN 'match' ELSE 'no match' END AS NullEqualsNull;   -- no match
GO

-- 5b. Orders -> Employees: order 1019 has EmployeeID NULL -> INNER JOIN drops it, LEFT JOIN keeps it with NULLs.
SELECT COUNT(*) AS InnerRows FROM dbo.Orders o JOIN      dbo.Employees e ON e.EmployeeID = o.EmployeeID;   -- 18
SELECT COUNT(*) AS LeftRows  FROM dbo.Orders o LEFT JOIN dbo.Employees e ON e.EmployeeID = o.EmployeeID;   -- 19
GO

-- 5c. Even a FULL JOIN will not pair two NULLs: Anjali (dept NULL) shows as unmatched, not matched to "some NULL department".
SELECT e.EmployeeName, d.DepartmentName
FROM dbo.Employees e
FULL JOIN dbo.Departments d ON d.DepartmentID = e.DepartmentID
WHERE e.DepartmentID IS NULL AND e.EmployeeID IS NOT NULL;   -- Anjali NULL
GO
-- If you really need NULL = NULL to match: ON a.col IS NOT DISTINCT FROM b.col (2022+), or LEFT JOIN + ISNULL logic.


/* ==== 6. DUPLICATE ROWS FROM ONE-TO-MANY JOINS  (the row-explosion trap) ==== */

-- 6a. One customer -> many orders. Joining repeats the customer once PER ORDER.
SELECT COUNT(*) AS Rows, COUNT(DISTINCT c.CustomerID) AS Customers
FROM dbo.Customers c
JOIN dbo.Orders o ON o.CustomerID = c.CustomerID;   -- 19, 7   (not 8: Hina dropped; not 7 rows: each order repeats its customer)
GO

-- 6b. "How many customers in Delhi have ordered?"  COUNT(*) explodes; COUNT(DISTINCT) is right.
SELECT COUNT(*) AS WrongCount, COUNT(DISTINCT c.CustomerID) AS RightCount
FROM dbo.Customers c
JOIN dbo.Orders o ON o.CustomerID = c.CustomerID
WHERE c.City = 'Delhi';   -- 7 (Aarav 4 + Chirag 3), 2
GO

-- 6c. Worse: SUMMING a parent column after joining to the child. Order 1008 has 3 lines -> its 78500 is added 3 times.
SELECT SUM(o.TotalAmount) AS WrongRevenue, COUNT(*) AS Lines, COUNT(DISTINCT o.OrderID) AS Orders
FROM dbo.Orders o
JOIN dbo.OrderDetails od ON od.OrderID = o.OrderID;   -- 824000 (!), 26, 19
GO

-- 6d. Fix 1: sum the CHILD level (line amounts), which is what the join produces
SELECT SUM(od.Quantity * od.UnitPrice) AS RightRevenue
FROM dbo.Orders o
JOIN dbo.OrderDetails od ON od.OrderID = o.OrderID;   -- 618000
GO

-- 6e. Fix 2: aggregate the child FIRST in a derived table, then join one row per order (Level 09 preview)
SELECT SUM(o.TotalAmount) AS RightRevenue, SUM(x.LineTotal) AS CheckLines
FROM dbo.Orders o
JOIN (SELECT OrderID, SUM(Quantity * UnitPrice) AS LineTotal FROM dbo.OrderDetails GROUP BY OrderID) AS x
     ON x.OrderID = o.OrderID;   -- 618000, 618000
GO

-- 6f. Fix 3 (when you only need "is there a match"): EXISTS instead of JOIN (see section 3)
--     Rule of thumb: after every join ask "did my row count change? should it have?"


/* ==== 7. OLD-STYLE COMMA JOINS  (know them, do not write them) ==== */

-- 7a. ANSI-89 syntax: tables separated by commas, the join condition hidden in WHERE. Works, same 11 rows.
SELECT e.EmployeeName, d.DepartmentName
FROM dbo.Employees e, dbo.Departments d
WHERE e.DepartmentID = d.DepartmentID
ORDER BY e.EmployeeID;   -- 11 rows (same as INNER JOIN)
GO

-- 7b. Forget the WHERE and you silently get a cross product (12 x 6 = 72 rows). With JOIN ... ON the parser stops you.
SELECT COUNT(*) AS SilentCrossProduct
FROM dbo.Employees e, dbo.Departments d;   -- 72
GO
-- 7c. The old outer-join operators *= and =* were REMOVED (SQL Server 2012+) - there is no comma-style LEFT JOIN.
--     Use explicit INNER / LEFT / RIGHT / FULL / CROSS JOIN ... ON. Mixing the two styles is a bug magnet.


/* ==== 8. JOIN ORDER: DOES NOT MATTER FOR INNER, MATTERS FOR OUTER ==== */

-- 8a. INNER JOIN is symmetric: A JOIN B = B JOIN A (the optimiser picks the physical order anyway)
SELECT COUNT(*) AS A_B FROM dbo.Employees e JOIN dbo.Departments d ON d.DepartmentID = e.DepartmentID;   -- 11
SELECT COUNT(*) AS B_A FROM dbo.Departments d JOIN dbo.Employees e ON d.DepartmentID = e.DepartmentID;   -- 11
GO

-- 8b. LEFT JOIN is NOT symmetric: which table is on the LEFT decides whose rows are kept
SELECT COUNT(*) AS CustomersLeft FROM dbo.Customers c LEFT JOIN dbo.Orders o ON o.CustomerID = c.CustomerID;   -- 20 (Hina kept)
SELECT COUNT(*) AS OrdersLeft    FROM dbo.Orders o LEFT JOIN dbo.Customers c ON c.CustomerID = o.CustomerID;   -- 19 (every order has a customer)
GO

-- 8c. Chained joins: an INNER JOIN AFTER a LEFT JOIN can undo it.
--     Customers LEFT JOIN Orders keeps Hina; then INNER JOIN Employees needs o.EmployeeID = e.EmployeeID.
--     Hina's o.EmployeeID is NULL (no match) and order 1019's EmployeeID is NULL too -> both vanish.
SELECT COUNT(*) AS Rows, COUNT(DISTINCT c.CustomerID) AS Customers
FROM dbo.Customers c
LEFT JOIN dbo.Orders    o ON o.CustomerID = c.CustomerID
JOIN      dbo.Employees e ON e.EmployeeID = o.EmployeeID;   -- 18, 7   (Hina AND order 1019 gone)
GO
-- Fix: once you go LEFT, stay LEFT for the tables that hang off the optional side
SELECT COUNT(*) AS Rows, COUNT(DISTINCT c.CustomerID) AS Customers
FROM dbo.Customers c
LEFT JOIN dbo.Orders    o ON o.CustomerID = c.CustomerID
LEFT JOIN dbo.Employees e ON e.EmployeeID = o.EmployeeID;   -- 20, 8
GO


/* ==== 9. USING IS NOT SUPPORTED IN T-SQL ==== */

-- Other databases allow JOIN ... USING (DepartmentID) or NATURAL JOIN. SQL Server does not: always write ON.
-- (Syntax errors happen at compile time, so this runs through sp_executesql to make TRY/CATCH able to catch it.)
BEGIN TRY
    EXEC sp_executesql N'SELECT e.EmployeeName, d.DepartmentName FROM dbo.Employees e JOIN dbo.Departments d USING (DepartmentID);';
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO
-- The T-SQL way:
SELECT COUNT(*) AS Rows FROM dbo.Employees e JOIN dbo.Departments d ON d.DepartmentID = e.DepartmentID;   -- 11
GO


/* ==== 10. CLEANUP ==== */
DROP TABLE IF EXISTS dbo.L08_SalaryBands;
GO
/* DONE. Next: Exercises.sql */
