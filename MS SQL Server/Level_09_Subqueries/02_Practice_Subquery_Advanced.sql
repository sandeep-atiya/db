/* ============================================================
   LEVEL 09 - SUBQUERIES  |  02_Practice_Subquery_Advanced.sql
   ------------------------------------------------------------
   Topics : subquery in HAVING, derived table with aggregate then
            JOIN, nested subqueries (2 levels), subquery vs JOIN
            vs EXISTS (when to use which), UPDATE / DELETE with a
            subquery (on a copy: dbo.L09_Products), Nth highest
            salary with a subquery (2nd highest - the classic).

   HOW TO PRACTICE: run block by block, predict the output first.
   Creates ONE copy table dbo.L09_Products and drops it at the end.
   Base tables are never modified.
   ============================================================ */

USE SQLPractice;
GO
DROP TABLE IF EXISTS dbo.L09_Products;
GO


/* ============================================================
   1. SUBQUERY IN HAVING  (filter GROUPS with a computed value)
   ============================================================ */

-- 1a. Departments whose average salary is above the company average.
--     WHERE cannot see AVG(), so the comparison must live in HAVING.
SELECT d.DepartmentName, AVG(e.Salary) AS AvgSalary
FROM dbo.Employees e
JOIN dbo.Departments d ON d.DepartmentID = e.DepartmentID
GROUP BY d.DepartmentName
HAVING AVG(e.Salary) > (SELECT AVG(Salary) FROM dbo.Employees)
ORDER BY AvgSalary DESC;
GO
-- expect 2 rows: Finance 81000, IT 71666.67   (company avg = 67083.33)

-- 1b. Customers who spent more than the AVERAGE customer.
--     The inner query is a derived table that computes per-customer totals first.
SELECT c.CustomerName, SUM(o.TotalAmount) AS TotalSpent
FROM dbo.Orders o
JOIN dbo.Customers c ON c.CustomerID = o.CustomerID
GROUP BY c.CustomerName
HAVING SUM(o.TotalAmount) > (SELECT AVG(t.Spent)
                             FROM (SELECT SUM(TotalAmount) AS Spent
                                   FROM dbo.Orders
                                   GROUP BY CustomerID) AS t)
ORDER BY TotalSpent DESC;
GO
-- expect 3 rows: Esha Kapoor 158000, Aarav Sharma 128000, Farhan Ali 88500
-- (average per customer = 618000 / 7 = 88285.71)

-- 1c. The salesperson with the MOST orders (ties would all show).
SELECT e.EmployeeName, COUNT(*) AS OrdersHandled
FROM dbo.Orders o
JOIN dbo.Employees e ON e.EmployeeID = o.EmployeeID
GROUP BY e.EmployeeName
HAVING COUNT(*) = (SELECT MAX(t.Cnt)
                   FROM (SELECT COUNT(*) AS Cnt
                         FROM dbo.Orders
                         WHERE EmployeeID IS NOT NULL
                         GROUP BY EmployeeID) AS t);
GO
-- expect 1 row: Priya 7


/* ============================================================
   2. DERIVED TABLE WITH AN AGGREGATE, THEN JOIN
   ============================================================
   Pattern: first shrink the detail table to one row per key
   (GROUP BY inside the derived table), THEN join it to the parent.
   This avoids double counting and lets you keep parents with 0.
   ============================================================ */

-- 2a. Every customer with order count and total, INCLUDING customers with no orders.
SELECT c.CustomerID, c.CustomerName,
       ISNULL(t.OrderCount, 0) AS OrderCount,
       ISNULL(t.TotalSpent, 0) AS TotalSpent
FROM dbo.Customers c
LEFT JOIN (SELECT CustomerID, COUNT(*) AS OrderCount, SUM(TotalAmount) AS TotalSpent
           FROM dbo.Orders
           GROUP BY CustomerID) AS t ON t.CustomerID = c.CustomerID
ORDER BY c.CustomerID;
GO
-- expect 8 rows; Hina Khan 0 / 0.00; Aarav 4 / 128000

-- 2b. Employee salary next to the department average (set-based version of the
--     correlated subquery from file 01, section 5a).
SELECT e.EmployeeName, e.Salary, da.AvgSalary,
       e.Salary - da.AvgSalary AS DiffFromDeptAvg
FROM dbo.Employees e
JOIN (SELECT DepartmentID, AVG(Salary) AS AvgSalary
      FROM dbo.Employees
      GROUP BY DepartmentID) AS da ON da.DepartmentID = e.DepartmentID
WHERE e.Salary > da.AvgSalary
ORDER BY e.EmployeeName;
GO
-- expect 4 rows: Karan, Priya, Rahul, Sneha (JOIN drops Anjali: NULL never joins)

-- 2c. Two derived tables joined: the best-selling product of EACH category.
SELECT pr.Category, pr.ProductName, pr.Revenue
FROM (SELECT p.Category, p.ProductName, SUM(od.Quantity * od.UnitPrice) AS Revenue
      FROM dbo.OrderDetails od
      JOIN dbo.Products p ON p.ProductID = od.ProductID
      GROUP BY p.Category, p.ProductName) AS pr
JOIN (SELECT p.Category, MAX(x.Revenue) AS MaxRevenue
      FROM (SELECT ProductID, SUM(Quantity * UnitPrice) AS Revenue
            FROM dbo.OrderDetails
            GROUP BY ProductID) AS x
      JOIN dbo.Products p ON p.ProductID = x.ProductID
      GROUP BY p.Category) AS mx ON mx.Category = pr.Category AND mx.MaxRevenue = pr.Revenue
ORDER BY pr.Category;
GO
-- expect 3 rows: Electronics Laptop 300000, Furniture Chair 48000, Stationery Pen 1500
-- (Level 11 does this in 3 lines with ROW_NUMBER - but interviewers still ask for this way)


/* ============================================================
   3. NESTED SUBQUERIES  (a subquery inside a subquery)
   ============================================================
   Read them from the INSIDE out. Two levels is normal; more than
   three usually means a JOIN or CTE would be clearer.
   ============================================================ */

-- 3a. Customers who bought at least one FURNITURE product.
--     inner-most: furniture product IDs -> middle: orders containing them -> outer: customers
SELECT CustomerID, CustomerName
FROM dbo.Customers
WHERE CustomerID IN (SELECT CustomerID
                     FROM dbo.Orders
                     WHERE OrderID IN (SELECT OrderID
                                       FROM dbo.OrderDetails
                                       WHERE ProductID IN (SELECT ProductID
                                                           FROM dbo.Products
                                                           WHERE Category = 'Furniture')))
ORDER BY CustomerID;
GO
-- expect 4 rows: 1 Aarav Sharma, 2 Bhavna Mehta, 5 Esha Kapoor, 7 Gaurav Singh

-- 3b. Everyone who works in the department of the highest-paid employee.
SELECT EmployeeName, DepartmentID, Salary
FROM dbo.Employees
WHERE DepartmentID = (SELECT DepartmentID
                      FROM dbo.Employees
                      WHERE Salary = (SELECT MAX(Salary) FROM dbo.Employees));
GO
-- expect 2 rows: Sneha 90000, Deepak 72000 (Finance, DepartmentID 4)
-- Note: the middle query is scalar only because ONE person has the max salary.
-- Safer: WHERE DepartmentID IN (...)  - it survives a tie for the top salary.


/* ============================================================
   4. SUBQUERY vs JOIN vs EXISTS - WHEN TO USE WHICH
   ============================================================ */

-- 4a. The same question 4 ways: "customers who placed an order".
--     JOIN without DISTINCT duplicates the customer once per order.
SELECT COUNT(*) AS JoinRows
FROM dbo.Customers c
JOIN dbo.Orders o ON o.CustomerID = c.CustomerID;
GO
-- expect 19  (one row per ORDER, not per customer!)

SELECT COUNT(DISTINCT c.CustomerID) AS JoinDistinct
FROM dbo.Customers c
JOIN dbo.Orders o ON o.CustomerID = c.CustomerID;
GO
-- expect 7

SELECT COUNT(*) AS InRows
FROM dbo.Customers
WHERE CustomerID IN (SELECT CustomerID FROM dbo.Orders);
GO
-- expect 7

SELECT COUNT(*) AS ExistsRows
FROM dbo.Customers c
WHERE EXISTS (SELECT 1 FROM dbo.Orders o WHERE o.CustomerID = c.CustomerID);
GO
-- expect 7

-- 4b. JOIN is the right tool when you need COLUMNS from both tables.
SELECT c.CustomerName, o.OrderID, o.OrderDate, o.TotalAmount
FROM dbo.Customers c
JOIN dbo.Orders o ON o.CustomerID = c.CustomerID
WHERE o.TotalAmount >= 75000
ORDER BY o.TotalAmount DESC;
GO
-- expect 4 rows: Esha 1014 150000, Farhan 1008 78500, Aarav 1001 75000, Gaurav 1018 75000

/* 4c. Guidance (say this in the interview):
   - JOIN      : you need columns from BOTH tables, or you will aggregate the child rows.
                 Watch out: 1-to-many joins multiply rows (use DISTINCT / GROUP BY).
   - IN        : short, readable "is in this list". Fine when the list has no NULLs.
   - EXISTS    : "at least one related row exists". Stops at first match, NULL-safe,
                 can test several conditions. NOT EXISTS is THE anti-join.
   - Scalar    : one computed value to compare against.
   - Correlated: per-row lookups; simple to write, can be slow on big tables
                 (think "loop"). Window functions (Level 11) often replace them.
   The optimizer usually turns IN / EXISTS / JOIN-for-filtering into the SAME
   plan (a semi join), so pick the one that reads clearest and is NULL-safe.   */


/* ============================================================
   5. UPDATE / DELETE WITH A SUBQUERY  (on the copy dbo.L09_Products)
   ============================================================ */

-- 5a. Work on a copy so the base table stays untouched.
SELECT * INTO dbo.L09_Products FROM dbo.Products;
SELECT COUNT(*) AS CopiedRows FROM dbo.L09_Products;
GO
-- expect 11

-- 5b. UPDATE with NOT IN: raise the price of products that were never sold by 10%.
UPDATE dbo.L09_Products
SET Price = Price * 1.10
WHERE ProductID NOT IN (SELECT ProductID FROM dbo.OrderDetails);
GO
-- expect (1 row affected)
SELECT ProductName, Price FROM dbo.L09_Products WHERE ProductID = 11;
GO
-- expect Webcam 4950.00

-- 5c. UPDATE with IN + HAVING: 10% discount on products that sold 10 or more units in total.
UPDATE dbo.L09_Products
SET Price = Price * 0.90
WHERE ProductID IN (SELECT ProductID
                    FROM dbo.OrderDetails
                    GROUP BY ProductID
                    HAVING SUM(Quantity) >= 10);
GO
-- expect (3 rows affected): Mouse (14 units), Notebook (20), Pen (150)
SELECT ProductName, Price FROM dbo.L09_Products WHERE ProductID IN (2, 7, 8);
GO
-- expect Mouse 900.00, Notebook 45.00, Pen 9.00

-- 5d. UPDATE with a CORRELATED subquery in SET: store total units sold per product.
ALTER TABLE dbo.L09_Products ADD TotalSold INT NULL;
GO
UPDATE dbo.L09_Products
SET TotalSold = ISNULL((SELECT SUM(od.Quantity)
                        FROM dbo.OrderDetails od
                        WHERE od.ProductID = dbo.L09_Products.ProductID), 0);
GO
-- expect (11 rows affected)
SELECT ProductName, TotalSold FROM dbo.L09_Products ORDER BY TotalSold DESC, ProductName;
GO
-- expect Pen 150, Notebook 20, Mouse 14, Monitor 7, Chair 6, Keyboard 5,
--        Laptop 4, Desk 3, Headphones 3, Bookshelf 1, Webcam 0

-- 5e. DELETE with NOT EXISTS: remove products that were never ordered.
DELETE p
FROM dbo.L09_Products p
WHERE NOT EXISTS (SELECT 1 FROM dbo.OrderDetails od WHERE od.ProductID = p.ProductID);
GO
-- expect (1 row affected)  -> Webcam gone
SELECT COUNT(*) AS Remaining FROM dbo.L09_Products;
GO
-- expect 10

-- 5f. DELETE with IN + HAVING: remove slow movers (fewer than 5 units sold in total).
DELETE FROM dbo.L09_Products
WHERE ProductID IN (SELECT ProductID
                    FROM dbo.OrderDetails
                    GROUP BY ProductID
                    HAVING SUM(Quantity) < 5);
GO
-- expect (4 rows affected): Laptop 4, Desk 3, Headphones 3, Bookshelf 1
SELECT ProductName FROM dbo.L09_Products ORDER BY ProductName;
GO
-- expect 6 rows: Chair, Keyboard, Monitor, Mouse, Notebook, Pen

-- TIP: before any UPDATE/DELETE with a subquery, run the SAME condition as a
--      SELECT first and check the row count. Then convert it.


/* ============================================================
   6. NTH HIGHEST SALARY WITH A SUBQUERY  (the classic)
   ============================================================
   Distinct salaries, highest first:
   90000, 85000, 75000, 72000, 70000, 65000, 62000, 60000, 58000, 55000, 48000
   ============================================================ */

-- 6a. 2nd highest = the biggest salary that is smaller than the biggest salary.
SELECT MAX(Salary) AS SecondHighest
FROM dbo.Employees
WHERE Salary < (SELECT MAX(Salary) FROM dbo.Employees);
GO
-- expect 85000.00

-- 6b. WHO earns the 2nd highest? Wrap it once more.
SELECT EmployeeName, Salary
FROM dbo.Employees
WHERE Salary = (SELECT MAX(Salary)
                FROM dbo.Employees
                WHERE Salary < (SELECT MAX(Salary) FROM dbo.Employees));
GO
-- expect 1 row: Rahul 85000

-- 6c. General N (correlated COUNT DISTINCT): "exactly N-1 distinct salaries are above mine".
DECLARE @N INT = 3;
SELECT DISTINCT e.Salary AS NthHighest
FROM dbo.Employees e
WHERE @N - 1 = (SELECT COUNT(DISTINCT x.Salary)
                FROM dbo.Employees x
                WHERE x.Salary > e.Salary);
GO
-- expect 75000.00 (3rd highest). Change @N to 2 -> 85000, to 6 -> 65000 (Amit & Pooja share it).

-- 6d. TOP-inside-TOP: take the top N distinct, then the smallest of those.
SELECT TOP (1) t.Salary AS SecondHighest
FROM (SELECT DISTINCT TOP (2) Salary
      FROM dbo.Employees
      ORDER BY Salary DESC) AS t
ORDER BY t.Salary ASC;
GO
-- expect 85000.00
-- Level 11 adds the two modern answers: DENSE_RANK() = N, and OFFSET N-1 ROWS FETCH NEXT 1 ROW ONLY.


/* ============================================================
   7. CLEANUP
   ============================================================ */
DROP TABLE IF EXISTS dbo.L09_Products;
GO
/* DONE. Next: Exercises.sql */
