/* ============================================================
   LEVEL 09 - SUBQUERIES  |  Exercises.sql
   ------------------------------------------------------------
   Try each question FIRST in the "YOUR ANSWERS" area, then compare
   with SOLUTIONS below. Q11 creates a copy table and drops it.
   ============================================================ */

USE SQLPractice;
GO

/* ------------------------------------------------------------
   QUESTIONS
   ------------------------------------------------------------
   Q1.  Employees (name, salary) earning more than the company average salary.

   Q2.  Employees who work in a department located in 'Delhi'. Use IN.

   Q3.  Products that have never been ordered. Use NOT EXISTS.

   Q4.  Customers who have never placed an order. Use NOT IN.
        Is NOT IN safe here? Why? (Hint: is Orders.CustomerID nullable?)

   Q5.  Employees whose salary is higher than EVERY employee of the
        Marketing department (DepartmentID 5). Use ALL.

   Q6.  Employees whose salary is above the average salary of their OWN
        department (correlated subquery). Show name, DepartmentID, salary.

   Q7.  Department names whose average salary is above the company
        average (subquery in HAVING).

   Q8.  Every customer with their number of orders and total amount,
        including customers with no orders (show 0). Use a derived table.

   Q9.  The THIRD highest salary, using only subqueries (no ranking functions).

   Q10. Departments with no employees written with NOT IN. It returns no
        rows - explain why in a comment, then fix it two ways.

   Q11. Copy Products into dbo.L09_Ex_Products. Delete every product whose
        total quantity sold is less than 5 (never-sold products included).
        Show what remains, then drop the copy.

   Q12. Orders whose TotalAmount is greater than the average order amount
        of THAT customer (correlated). Show CustomerID, OrderID, TotalAmount.
   ------------------------------------------------------------ */

-- YOUR ANSWERS HERE (write below, run, compare)










/* ============================================================
   SOLUTIONS
   ============================================================ */

-- Q1
SELECT EmployeeName, Salary
FROM dbo.Employees
WHERE Salary > (SELECT AVG(Salary) FROM dbo.Employees)
ORDER BY Salary DESC;
GO
-- 5 rows: Sneha, Rahul, Priya, Deepak, Karan  (avg = 67083.33)

-- Q2
SELECT EmployeeName, DepartmentID
FROM dbo.Employees
WHERE DepartmentID IN (SELECT DepartmentID FROM dbo.Departments WHERE Location = 'Delhi')
ORDER BY EmployeeName;
GO
-- 4 rows: Amit, Pooja, Rahul, Ravi

-- Q3
SELECT p.ProductID, p.ProductName
FROM dbo.Products p
WHERE NOT EXISTS (SELECT 1 FROM dbo.OrderDetails od WHERE od.ProductID = p.ProductID);
GO
-- 1 row: Webcam

-- Q4
SELECT CustomerID, CustomerName
FROM dbo.Customers
WHERE CustomerID NOT IN (SELECT CustomerID FROM dbo.Orders);
GO
-- 1 row: Hina Khan.  Safe because Orders.CustomerID is NOT NULL, so the list
-- can never contain a NULL. With a nullable column prefer NOT EXISTS.

-- Q5
SELECT EmployeeName, Salary
FROM dbo.Employees
WHERE Salary > ALL (SELECT Salary FROM dbo.Employees WHERE DepartmentID = 5)
ORDER BY Salary DESC;
GO
-- 4 rows: Sneha 90000, Rahul 85000, Priya 75000, Deepak 72000  (Marketing max = 70000)

-- Q6
SELECT e.EmployeeName, e.DepartmentID, e.Salary
FROM dbo.Employees e
WHERE e.Salary > (SELECT AVG(x.Salary) FROM dbo.Employees x WHERE x.DepartmentID = e.DepartmentID)
ORDER BY e.DepartmentID;
GO
-- 4 rows: Rahul, Priya, Sneha, Karan

-- Q7
SELECT d.DepartmentName, AVG(e.Salary) AS AvgSalary
FROM dbo.Employees e
JOIN dbo.Departments d ON d.DepartmentID = e.DepartmentID
GROUP BY d.DepartmentName
HAVING AVG(e.Salary) > (SELECT AVG(Salary) FROM dbo.Employees);
GO
-- 2 rows: IT 71666.67, Finance 81000

-- Q8
SELECT c.CustomerName, ISNULL(t.OrderCount, 0) AS OrderCount, ISNULL(t.Total, 0) AS TotalAmount
FROM dbo.Customers c
LEFT JOIN (SELECT CustomerID, COUNT(*) AS OrderCount, SUM(TotalAmount) AS Total
           FROM dbo.Orders
           GROUP BY CustomerID) AS t ON t.CustomerID = c.CustomerID
ORDER BY c.CustomerID;
GO
-- 8 rows; Hina Khan 0 / 0

-- Q9
SELECT MAX(Salary) AS ThirdHighest
FROM dbo.Employees
WHERE Salary < (SELECT MAX(Salary)
                FROM dbo.Employees
                WHERE Salary < (SELECT MAX(Salary) FROM dbo.Employees));
GO
-- 75000.00   (alternative: DISTINCT TOP 3 ... ORDER BY DESC, then TOP 1 ... ASC)

-- Q10
SELECT DepartmentName
FROM dbo.Departments
WHERE DepartmentID NOT IN (SELECT DepartmentID FROM dbo.Employees);
GO
-- 0 rows. Employees.DepartmentID has a NULL (Anjali). NOT IN becomes
-- "<> 1 AND <> 2 ... AND <> NULL"; "<> NULL" is UNKNOWN, so no row is TRUE.
SELECT DepartmentName
FROM dbo.Departments
WHERE DepartmentID NOT IN (SELECT DepartmentID FROM dbo.Employees WHERE DepartmentID IS NOT NULL);
GO
-- Fix 1 -> Legal
SELECT d.DepartmentName
FROM dbo.Departments d
WHERE NOT EXISTS (SELECT 1 FROM dbo.Employees e WHERE e.DepartmentID = d.DepartmentID);
GO
-- Fix 2 -> Legal (preferred: NULL-safe)

-- Q11
DROP TABLE IF EXISTS dbo.L09_Ex_Products;
SELECT * INTO dbo.L09_Ex_Products FROM dbo.Products;
GO
DELETE FROM dbo.L09_Ex_Products
WHERE ISNULL((SELECT SUM(od.Quantity)
              FROM dbo.OrderDetails od
              WHERE od.ProductID = dbo.L09_Ex_Products.ProductID), 0) < 5;
GO
-- (5 rows affected): Laptop 4, Desk 3, Headphones 3, Bookshelf 1, Webcam 0
SELECT ProductName FROM dbo.L09_Ex_Products ORDER BY ProductName;
GO
-- 6 rows: Chair, Keyboard, Monitor, Mouse, Notebook, Pen
DROP TABLE IF EXISTS dbo.L09_Ex_Products;
GO

-- Q12
SELECT o.CustomerID, o.OrderID, o.TotalAmount
FROM dbo.Orders o
WHERE o.TotalAmount > (SELECT AVG(x.TotalAmount)
                       FROM dbo.Orders x
                       WHERE x.CustomerID = o.CustomerID)
ORDER BY o.CustomerID;
GO
-- 7 rows: 1001, 1012, 1003, 1005, 1014, 1008, 1018 (the biggest order of each customer;
-- Aarav's 1015 = 32000 equals his average 32000, so "greater than" excludes it)
