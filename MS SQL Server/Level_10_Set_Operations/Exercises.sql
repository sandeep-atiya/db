/* ============================================================
   LEVEL 10 - SET OPERATIONS  |  Exercises.sql
   ------------------------------------------------------------
   Try each question FIRST in the "YOUR ANSWERS" area, then compare
   with SOLUTIONS below. Q10 creates a copy table and drops it.
   ============================================================ */

USE SQLPractice;
GO

/* ------------------------------------------------------------
   QUESTIONS
   ------------------------------------------------------------
   Q1.  One sorted list of all DISTINCT cities from Customers.City and
        Departments.Location.

   Q2.  Same list but KEEP duplicates. How many rows?

   Q3.  Cities that have BOTH customers and a department.

   Q4.  Cities that have customers but NO department.

   Q5.  One list of all people: employees and customers, with columns
        Name and Type ('Employee' / 'Customer'), sorted by Name.

   Q6.  ProductIDs ordered in January 2025 AND ALSO in February 2025.

   Q7.  ProductIDs ordered in January 2025 but NOT in February 2025.

   Q8.  EmployeeIDs of employees who never appear as a salesperson in
        Orders. Use EXCEPT.

   Q9.  Predict the result BEFORE running (write your guess as a comment):
          SELECT 1 UNION SELECT 2 UNION SELECT 3 INTERSECT SELECT 3 EXCEPT SELECT 1;
        Then rewrite it with parentheses so it reads the way it runs.

   Q10. Copy Employees to dbo.L10_Ex_Employees. In the copy: give Amit a
        salary of 70000, delete Anjali, insert employee 113 'Zara'
        (DepartmentID 3, salary 50000, hired 2025-01-01, no manager).
        Show the rows that differ, both ways, then drop the copy.

   Q11. For each month of 2025 show the number of ORDERS placed and the
        number of CUSTOMERS created (Customers.CreatedDate). Months with
        0 on one side must still appear. Use UNION ALL + GROUP BY.

   Q12. The 2 highest salaries and the 2 most expensive products in one
        list (Name, Amount, Kind). Remember: TOP needs a derived table.
   ------------------------------------------------------------ */

-- YOUR ANSWERS HERE (write below, run, compare)










/* ============================================================
   SOLUTIONS
   ============================================================ */

-- Q1
SELECT City FROM dbo.Customers
UNION
SELECT Location FROM dbo.Departments;
GO
-- 5 rows: Bangalore, Chennai, Delhi, Mumbai, Pune

-- Q2
SELECT City FROM dbo.Customers
UNION ALL
SELECT Location FROM dbo.Departments;
GO
-- 14 rows

-- Q3
SELECT City FROM dbo.Customers
INTERSECT
SELECT Location FROM dbo.Departments;
GO
-- 4 rows: Bangalore, Delhi, Mumbai, Pune

-- Q4
SELECT City FROM dbo.Customers
EXCEPT
SELECT Location FROM dbo.Departments;
GO
-- 1 row: Chennai

-- Q5
SELECT EmployeeName AS Name, 'Employee' AS Type FROM dbo.Employees
UNION ALL
SELECT CustomerName, 'Customer' FROM dbo.Customers
ORDER BY Name;
GO
-- 20 rows, Aarav Sharma first

-- Q6
SELECT od.ProductID
FROM dbo.OrderDetails od
JOIN dbo.Orders o ON o.OrderID = od.OrderID
WHERE o.OrderDate >= '20250101' AND o.OrderDate < '20250201'
INTERSECT
SELECT od.ProductID
FROM dbo.OrderDetails od
JOIN dbo.Orders o ON o.OrderID = od.OrderID
WHERE o.OrderDate >= '20250201' AND o.OrderDate < '20250301';
GO
-- 2 rows: 4 (Chair), 6 (Monitor).  Jan = {1,2,4,6}, Feb = {4,5,6}

-- Q7
SELECT od.ProductID
FROM dbo.OrderDetails od
JOIN dbo.Orders o ON o.OrderID = od.OrderID
WHERE o.OrderDate >= '20250101' AND o.OrderDate < '20250201'
EXCEPT
SELECT od.ProductID
FROM dbo.OrderDetails od
JOIN dbo.Orders o ON o.OrderID = od.OrderID
WHERE o.OrderDate >= '20250201' AND o.OrderDate < '20250301';
GO
-- 2 rows: 1 (Laptop), 2 (Mouse)

-- Q8
SELECT EmployeeID FROM dbo.Employees
EXCEPT
SELECT EmployeeID FROM dbo.Orders;
GO
-- 9 rows: everyone except 103, 104, 109. (The NULL EmployeeID in Orders is harmless here:
-- EXCEPT only removes values that match, and no employee has a NULL id.)

-- Q9
-- Prediction: INTERSECT runs first: (3 INTERSECT 3) = 3.
-- Then left to right: ((1 UNION 2) UNION 3) EXCEPT 1  ->  2, 3
SELECT 1 AS v UNION SELECT 2 UNION SELECT 3 INTERSECT SELECT 3 EXCEPT SELECT 1;
GO
-- 2 rows: 2, 3
((SELECT 1 AS v UNION SELECT 2) UNION (SELECT 3 INTERSECT SELECT 3)) EXCEPT SELECT 1;
GO
-- same 2 rows

-- Q10
DROP TABLE IF EXISTS dbo.L10_Ex_Employees;
SELECT * INTO dbo.L10_Ex_Employees FROM dbo.Employees;
UPDATE dbo.L10_Ex_Employees SET Salary = 70000 WHERE EmployeeID = 102;
DELETE FROM dbo.L10_Ex_Employees WHERE EmployeeID = 110;
INSERT INTO dbo.L10_Ex_Employees VALUES (113, 'Zara', 'zara@example.com', 3, 50000, '2025-01-01', NULL);
GO
SELECT 'Only in original' AS Side, d.*
FROM (SELECT * FROM dbo.Employees EXCEPT SELECT * FROM dbo.L10_Ex_Employees) AS d
UNION ALL
SELECT 'Only in copy', d.*
FROM (SELECT * FROM dbo.L10_Ex_Employees EXCEPT SELECT * FROM dbo.Employees) AS d
ORDER BY Side, EmployeeID;
GO
-- 4 rows: original -> Amit 65000, Anjali;  copy -> Amit 70000, Zara
DROP TABLE IF EXISTS dbo.L10_Ex_Employees;
GO

-- Q11
SELECT Mth, SUM(Orders) AS Orders, SUM(NewCustomers) AS NewCustomers
FROM (SELECT MONTH(OrderDate) AS Mth, 1 AS Orders, 0 AS NewCustomers
      FROM dbo.Orders
      WHERE YEAR(OrderDate) = 2025
      UNION ALL
      SELECT MONTH(CreatedDate), 0, 1
      FROM dbo.Customers
      WHERE YEAR(CreatedDate) = 2025) AS u
GROUP BY Mth
ORDER BY Mth;
GO
-- 9 rows: 1: 3/2, 2: 3/1, 3: 2/1, 4: 2/1, 5: 2/0, 6: 2/1, 7: 2/0, 8: 2/0, 9: 1/0

-- Q12
SELECT * FROM (SELECT TOP (2) EmployeeName AS Name, Salary AS Amount, 'Employee' AS Kind
               FROM dbo.Employees ORDER BY Salary DESC) AS e
UNION ALL
SELECT * FROM (SELECT TOP (2) ProductName AS Name, Price AS Amount, 'Product' AS Kind
               FROM dbo.Products ORDER BY Price DESC) AS p;
GO
-- 4 rows: Sneha 90000, Rahul 85000, Laptop 75000, Monitor 25000
-- (every column of a derived table needs a name - a bare literal like 'Product' has none)
