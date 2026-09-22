/* ============================================================
   INTERVIEW PREP  |  Top_Query_Patterns.sql
   ------------------------------------------------------------
   The 30 query patterns that come up again and again in SQL
   Server interviews, all runnable on SQLPractice.
   Practice: read the title, WRITE IT YOURSELF, then compare.
   Every pattern is independent - run any block alone.
   ============================================================ */

USE SQLPractice;
GO

/* ============================================================
   1. Nth HIGHEST SALARY  (3 ways)   -> 2nd highest = 85000 (Rahul)
   ============================================================ */
-- 1a. DENSE_RANK (best: handles ties, returns names)
DECLARE @N INT = 2;
SELECT EmployeeName, Salary
FROM (SELECT EmployeeName, Salary, DENSE_RANK() OVER (ORDER BY Salary DESC) AS rnk
      FROM dbo.Employees) t
WHERE rnk = @N;
GO
-- 1b. OFFSET / FETCH (no ties handling: DISTINCT salaries)
SELECT DISTINCT Salary FROM dbo.Employees ORDER BY Salary DESC OFFSET 1 ROWS FETCH NEXT 1 ROWS ONLY;
GO
-- 1c. Classic subquery (works on any DB, no window functions)
SELECT MAX(Salary) AS SecondHighest
FROM dbo.Employees
WHERE Salary < (SELECT MAX(Salary) FROM dbo.Employees);
GO
-- 1d. Generic Nth with correlated count: salary with exactly N-1 distinct salaries above it
SELECT DISTINCT e1.Salary
FROM dbo.Employees e1
WHERE 2 - 1 = (SELECT COUNT(DISTINCT e2.Salary) FROM dbo.Employees e2 WHERE e2.Salary > e1.Salary);
GO


/* ============================================================
   2. FIND DUPLICATES  /  DELETE DUPLICATES (keep one)
   ============================================================ */
-- Build a copy with duplicates
DROP TABLE IF EXISTS dbo.IP_Customers;
SELECT CustomerID, CustomerName, City INTO dbo.IP_Customers FROM dbo.Customers;
INSERT INTO dbo.IP_Customers VALUES (9, 'Aarav Sharma', 'Delhi'), (10, 'Aarav Sharma', 'Delhi'), (11, 'Divya Nair', 'Pune');
GO
-- 2a. Find duplicates by name+city
SELECT CustomerName, City, COUNT(*) AS Cnt
FROM dbo.IP_Customers
GROUP BY CustomerName, City
HAVING COUNT(*) > 1;                          -- Aarav Sharma (3), Divya Nair (2)
GO
-- 2b. Delete duplicates, keep the lowest CustomerID   (CTE + ROW_NUMBER: the interview answer)
WITH d AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY CustomerName, City ORDER BY CustomerID) AS rn
    FROM dbo.IP_Customers)
DELETE FROM d WHERE rn > 1;                   -- 3 rows deleted
SELECT * FROM dbo.IP_Customers ORDER BY CustomerID;   -- back to 8 rows
GO


/* ============================================================
   3. TOP-N PER GROUP  (highest paid employee in each department)
   ============================================================ */
SELECT DepartmentName, EmployeeName, Salary
FROM (SELECT d.DepartmentName, e.EmployeeName, e.Salary,
             ROW_NUMBER() OVER (PARTITION BY e.DepartmentID ORDER BY e.Salary DESC) AS rn
      FROM dbo.Employees e
      JOIN dbo.Departments d ON d.DepartmentID = e.DepartmentID) t
WHERE rn = 1
ORDER BY DepartmentName;
-- Use DENSE_RANK instead of ROW_NUMBER if ties should all be returned.
GO
-- 3b. Same with CROSS APPLY (top 2 orders per customer)
SELECT c.CustomerName, o.OrderID, o.OrderDate, o.TotalAmount
FROM dbo.Customers c
CROSS APPLY (SELECT TOP (2) OrderID, OrderDate, TotalAmount
             FROM dbo.Orders o WHERE o.CustomerID = c.CustomerID
             ORDER BY TotalAmount DESC) o
ORDER BY c.CustomerName, o.TotalAmount DESC;
GO


/* ============================================================
   4. EMPLOYEES EARNING MORE THAN THEIR MANAGER   (SELF JOIN)
   ============================================================ */
SELECT e.EmployeeName, e.Salary, m.EmployeeName AS Manager, m.Salary AS ManagerSalary
FROM dbo.Employees e
JOIN dbo.Employees m ON m.EmployeeID = e.ManagerID
WHERE e.Salary > m.Salary;                    -- 0 rows in this data (managers earn more)
GO
-- Employee + manager list, managers on top
SELECT e.EmployeeName, ISNULL(m.EmployeeName, '(none)') AS Manager
FROM dbo.Employees e
LEFT JOIN dbo.Employees m ON m.EmployeeID = e.ManagerID
ORDER BY CASE WHEN e.ManagerID IS NULL THEN 0 ELSE 1 END, e.EmployeeName;
GO


/* ============================================================
   5. DEPARTMENT-WISE MAX SALARY WITH EMPLOYEE NAME
   ============================================================ */
-- 5a. Join back to the aggregate (classic)
SELECT d.DepartmentName, e.EmployeeName, e.Salary
FROM dbo.Employees e
JOIN dbo.Departments d ON d.DepartmentID = e.DepartmentID
JOIN (SELECT DepartmentID, MAX(Salary) AS MaxSal FROM dbo.Employees GROUP BY DepartmentID) mx
     ON mx.DepartmentID = e.DepartmentID AND mx.MaxSal = e.Salary
ORDER BY d.DepartmentName;
GO
-- 5b. Correlated subquery
SELECT e.EmployeeName, e.DepartmentID, e.Salary
FROM dbo.Employees e
WHERE e.Salary = (SELECT MAX(Salary) FROM dbo.Employees x WHERE x.DepartmentID = e.DepartmentID);
GO


/* ============================================================
   6. CUSTOMERS WITH NO ORDERS  (3 ways)  -> Hina Khan
   ============================================================ */
SELECT c.CustomerName FROM dbo.Customers c
WHERE NOT EXISTS (SELECT 1 FROM dbo.Orders o WHERE o.CustomerID = c.CustomerID);   -- best

SELECT c.CustomerName FROM dbo.Customers c
LEFT JOIN dbo.Orders o ON o.CustomerID = c.CustomerID
WHERE o.OrderID IS NULL;                                                          -- anti-join

SELECT CustomerName FROM dbo.Customers
WHERE CustomerID NOT IN (SELECT CustomerID FROM dbo.Orders WHERE CustomerID IS NOT NULL);  -- NOT IN: guard against NULL!
GO


/* ============================================================
   7. COUNT PER GROUP INCLUDING ZERO  (departments with 0 employees)
   ============================================================ */
SELECT d.DepartmentName, COUNT(e.EmployeeID) AS Employees      -- COUNT(column) not COUNT(*)
FROM dbo.Departments d
LEFT JOIN dbo.Employees e ON e.DepartmentID = d.DepartmentID
GROUP BY d.DepartmentName
ORDER BY Employees DESC;                                       -- Legal = 0
GO


/* ============================================================
   8. RUNNING TOTAL  and  MONTH-OVER-MONTH GROWTH
   ============================================================ */
-- 8a. Running total of order amounts by date
SELECT OrderID, OrderDate, TotalAmount,
       SUM(TotalAmount) OVER (ORDER BY OrderDate, OrderID ROWS UNBOUNDED PRECEDING) AS RunningTotal
FROM dbo.Orders
WHERE Status = 'Completed';
GO
-- 8b. Monthly revenue + previous month + growth %
WITH m AS (
    SELECT FORMAT(OrderDate, 'yyyy-MM') AS YearMonth, SUM(TotalAmount) AS Revenue
    FROM dbo.Orders WHERE Status = 'Completed'
    GROUP BY FORMAT(OrderDate, 'yyyy-MM'))
SELECT YearMonth, Revenue,
       LAG(Revenue) OVER (ORDER BY YearMonth) AS PrevMonth,
       CAST(100.0 * (Revenue - LAG(Revenue) OVER (ORDER BY YearMonth))
            / NULLIF(LAG(Revenue) OVER (ORDER BY YearMonth), 0) AS DECIMAL(10,1)) AS GrowthPct
FROM m ORDER BY YearMonth;
GO


/* ============================================================
   9. RANK vs DENSE_RANK vs ROW_NUMBER  (Amit & Pooja tie at 65000)
   ============================================================ */
SELECT EmployeeName, Salary,
       ROW_NUMBER() OVER (ORDER BY Salary DESC) AS RowNum,     -- 1,2,3,4,5,6,7,8...
       RANK()       OVER (ORDER BY Salary DESC) AS Rnk,        -- 1,2,3,4,5,6,6,8...  (gap)
       DENSE_RANK() OVER (ORDER BY Salary DESC) AS DenseRnk    -- 1,2,3,4,5,6,6,7...  (no gap)
FROM dbo.Employees;
GO


/* ============================================================
   10. GAPS IN A SEQUENCE  (missing OrderIDs)  and  ISLANDS (streaks)
   ============================================================ */
-- 10a. Missing numbers between min and max OrderID (none in base data; delete one on a copy to test)
DROP TABLE IF EXISTS dbo.IP_Orders;
SELECT OrderID, CustomerID, OrderDate INTO dbo.IP_Orders FROM dbo.Orders;
DELETE FROM dbo.IP_Orders WHERE OrderID IN (1004, 1005, 1011);
GO
SELECT o.OrderID + 1 AS GapStart,
       (SELECT MIN(OrderID) FROM dbo.IP_Orders x WHERE x.OrderID > o.OrderID) - 1 AS GapEnd
FROM dbo.IP_Orders o
WHERE NOT EXISTS (SELECT 1 FROM dbo.IP_Orders y WHERE y.OrderID = o.OrderID + 1)
  AND o.OrderID < (SELECT MAX(OrderID) FROM dbo.IP_Orders);      -- 1004-1005, 1011-1011
GO
-- 10b. Same with LEAD
SELECT OrderID + 1 AS GapStart, NextID - 1 AS GapEnd
FROM (SELECT OrderID, LEAD(OrderID) OVER (ORDER BY OrderID) AS NextID FROM dbo.IP_Orders) t
WHERE NextID - OrderID > 1;
GO
-- 10c. Islands: consecutive-day login streaks (ROW_NUMBER difference trick)
DROP TABLE IF EXISTS dbo.IP_Logins;
CREATE TABLE dbo.IP_Logins (UserName VARCHAR(20), LoginDate DATE);
INSERT INTO dbo.IP_Logins VALUES
('amit','2025-03-01'),('amit','2025-03-02'),('amit','2025-03-03'),('amit','2025-03-06'),('amit','2025-03-07'),
('neha','2025-03-01'),('neha','2025-03-03'),('neha','2025-03-04'),('neha','2025-03-05');
GO
WITH g AS (
    SELECT UserName, LoginDate,
           DATEADD(DAY, -ROW_NUMBER() OVER (PARTITION BY UserName ORDER BY LoginDate), LoginDate) AS grp
    FROM dbo.IP_Logins)
SELECT UserName, MIN(LoginDate) AS StreakStart, MAX(LoginDate) AS StreakEnd, COUNT(*) AS Days
FROM g GROUP BY UserName, grp
ORDER BY UserName, StreakStart;                -- amit: 3 days + 2 days ; neha: 1 day + 3 days
GO


/* ============================================================
   11. PIVOT: order counts per status per customer  (PIVOT and CASE)
   ============================================================ */
SELECT CustomerID, ISNULL([Completed],0) AS Completed, ISNULL([Pending],0) AS Pending, ISNULL([Cancelled],0) AS Cancelled
FROM (SELECT CustomerID, Status FROM dbo.Orders) src
PIVOT (COUNT(Status) FOR Status IN ([Completed],[Pending],[Cancelled])) p
ORDER BY CustomerID;
GO
SELECT CustomerID,
       SUM(CASE WHEN Status = 'Completed' THEN 1 ELSE 0 END) AS Completed,
       SUM(CASE WHEN Status = 'Pending'   THEN 1 ELSE 0 END) AS Pending,
       SUM(CASE WHEN Status = 'Cancelled' THEN 1 ELSE 0 END) AS Cancelled
FROM dbo.Orders GROUP BY CustomerID ORDER BY CustomerID;      -- portable version
GO


/* ============================================================
   12. STRING AGGREGATION  (employees per department, comma separated)
   ============================================================ */
SELECT d.DepartmentName,
       STRING_AGG(e.EmployeeName, ', ') WITHIN GROUP (ORDER BY e.EmployeeName) AS Members
FROM dbo.Departments d
LEFT JOIN dbo.Employees e ON e.DepartmentID = d.DepartmentID
GROUP BY d.DepartmentName;
GO
-- Pre-2017 way (FOR XML PATH + STUFF) - still asked in interviews
SELECT d.DepartmentName,
       STUFF((SELECT ', ' + e.EmployeeName FROM dbo.Employees e
              WHERE e.DepartmentID = d.DepartmentID ORDER BY e.EmployeeName
              FOR XML PATH('')), 1, 2, '') AS Members
FROM dbo.Departments d;
GO


/* ============================================================
   13. HIERARCHY  (recursive CTE: org chart with level and path)
   ============================================================ */
WITH org AS (
    SELECT EmployeeID, EmployeeName, ManagerID, 1 AS Lvl, CAST(EmployeeName AS VARCHAR(500)) AS Path
    FROM dbo.Employees WHERE ManagerID IS NULL
    UNION ALL
    SELECT e.EmployeeID, e.EmployeeName, e.ManagerID, o.Lvl + 1, CAST(o.Path + ' > ' + e.EmployeeName AS VARCHAR(500))
    FROM dbo.Employees e JOIN org o ON o.EmployeeID = e.ManagerID)
SELECT REPLICATE('   ', Lvl - 1) + EmployeeName AS Tree, Lvl, Path
FROM org ORDER BY Path;
GO


/* ============================================================
   14. FIRST AND LAST ORDER PER CUSTOMER  (one row per customer)
   ============================================================ */
SELECT c.CustomerName,
       MIN(o.OrderDate) AS FirstOrder, MAX(o.OrderDate) AS LastOrder,
       COUNT(o.OrderID) AS Orders, SUM(o.TotalAmount) AS Revenue
FROM dbo.Customers c
LEFT JOIN dbo.Orders o ON o.CustomerID = c.CustomerID
GROUP BY c.CustomerName ORDER BY Revenue DESC;
GO
-- With the amount of the first order too (FIRST_VALUE)
SELECT DISTINCT CustomerID,
       FIRST_VALUE(OrderID)     OVER (PARTITION BY CustomerID ORDER BY OrderDate) AS FirstOrderID,
       FIRST_VALUE(TotalAmount) OVER (PARTITION BY CustomerID ORDER BY OrderDate) AS FirstAmount,
       LAST_VALUE(OrderID)      OVER (PARTITION BY CustomerID ORDER BY OrderDate
                                      ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS LastOrderID
FROM dbo.Orders ORDER BY CustomerID;
GO


/* ============================================================
   15. PERCENT OF TOTAL  (revenue share per category)
   ============================================================ */
SELECT p.Category,
       SUM(od.Quantity * od.UnitPrice) AS Revenue,
       CAST(100.0 * SUM(od.Quantity * od.UnitPrice) / SUM(SUM(od.Quantity * od.UnitPrice)) OVER () AS DECIMAL(5,2)) AS Pct
FROM dbo.OrderDetails od
JOIN dbo.Products p ON p.ProductID = od.ProductID
GROUP BY p.Category ORDER BY Revenue DESC;
GO


/* ============================================================
   16. BEST-SELLING PRODUCT / PRODUCTS NEVER SOLD
   ============================================================ */
SELECT TOP (1) WITH TIES p.ProductName, SUM(od.Quantity) AS UnitsSold
FROM dbo.OrderDetails od JOIN dbo.Products p ON p.ProductID = od.ProductID
GROUP BY p.ProductName ORDER BY UnitsSold DESC;                  -- Pen (150)

SELECT p.ProductName FROM dbo.Products p
WHERE NOT EXISTS (SELECT 1 FROM dbo.OrderDetails od WHERE od.ProductID = p.ProductID);   -- Webcam
GO


/* ============================================================
   17. MEDIAN SALARY
   ============================================================ */
SELECT DISTINCT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY Salary) OVER () AS MedianSalary
FROM dbo.Employees;                                              -- 65000
GO
-- Without PERCENTILE_CONT (two middle rows averaged)
SELECT AVG(Salary) AS MedianSalary
FROM (SELECT Salary, ROW_NUMBER() OVER (ORDER BY Salary) AS rn, COUNT(*) OVER () AS cnt
      FROM dbo.Employees) t
WHERE rn IN ((cnt + 1) / 2, (cnt + 2) / 2);
GO


/* ============================================================
   18. ODD / EVEN ROWS   and   EVERY Nth ROW
   ============================================================ */
SELECT * FROM (SELECT *, ROW_NUMBER() OVER (ORDER BY EmployeeID) AS rn FROM dbo.Employees) t WHERE rn % 2 = 1;  -- odd
SELECT * FROM (SELECT *, ROW_NUMBER() OVER (ORDER BY EmployeeID) AS rn FROM dbo.Employees) t WHERE rn % 2 = 0;  -- even
GO


/* ============================================================
   19. SWAP VALUES WITH ONE UPDATE  (classic "swap gender" question)
   ============================================================ */
DROP TABLE IF EXISTS dbo.IP_Swap;
CREATE TABLE dbo.IP_Swap (Id INT, Gender CHAR(1));
INSERT INTO dbo.IP_Swap VALUES (1,'M'),(2,'F'),(3,'M');
UPDATE dbo.IP_Swap SET Gender = CASE Gender WHEN 'M' THEN 'F' WHEN 'F' THEN 'M' END;
SELECT * FROM dbo.IP_Swap;                                       -- F, M, F
GO


/* ============================================================
   20. COMPARE TWO TABLES  (rows that differ)  -> EXCEPT both ways
   ============================================================ */
DROP TABLE IF EXISTS dbo.IP_Products2;
SELECT * INTO dbo.IP_Products2 FROM dbo.Products;
UPDATE dbo.IP_Products2 SET Price = 999 WHERE ProductID = 2;
DELETE FROM dbo.IP_Products2 WHERE ProductID = 11;
GO
SELECT 'Only in original' AS Which, * FROM (SELECT * FROM dbo.Products EXCEPT SELECT * FROM dbo.IP_Products2) a
UNION ALL
SELECT 'Only in copy', * FROM (SELECT * FROM dbo.IP_Products2 EXCEPT SELECT * FROM dbo.Products) b;
GO


/* ============================================================
   21. EMPLOYEES HIRED IN THE LAST N MONTHS / SAME MONTH AS SOMEONE
   ============================================================ */
SELECT EmployeeName, HireDate FROM dbo.Employees
WHERE HireDate >= DATEADD(MONTH, -30, CAST(GETDATE() AS DATE));   -- SARGable: no function on the column

SELECT a.EmployeeName, b.EmployeeName AS SameMonthAs, a.HireDate, b.HireDate
FROM dbo.Employees a JOIN dbo.Employees b
  ON YEAR(a.HireDate) = YEAR(b.HireDate) AND MONTH(a.HireDate) = MONTH(b.HireDate)
 AND a.EmployeeID < b.EmployeeID;                                   -- pairs, no self / duplicates
GO


/* ============================================================
   22. CONDITIONAL AGGREGATION  (completed vs cancelled per salesperson)
   ============================================================ */
SELECT ISNULL(e.EmployeeName, '(online)') AS SalesPerson,
       COUNT(*)                                                 AS AllOrders,
       SUM(CASE WHEN o.Status = 'Completed' THEN 1 ELSE 0 END)  AS Completed,
       SUM(CASE WHEN o.Status = 'Cancelled' THEN 1 ELSE 0 END)  AS Cancelled,
       SUM(CASE WHEN o.Status = 'Completed' THEN o.TotalAmount ELSE 0 END) AS CompletedRevenue
FROM dbo.Orders o
LEFT JOIN dbo.Employees e ON e.EmployeeID = o.EmployeeID
GROUP BY e.EmployeeName ORDER BY CompletedRevenue DESC;
GO


/* ============================================================
   23. COMMA LIST -> ROWS  (STRING_SPLIT) and use it in a filter
   ============================================================ */
DECLARE @ids VARCHAR(100) = '101,103,106';
SELECT e.EmployeeID, e.EmployeeName
FROM dbo.Employees e
JOIN STRING_SPLIT(@ids, ',') s ON s.value = e.EmployeeID;
GO


/* ============================================================
   24. THE NOT IN + NULL TRAP  (returns nothing!)
   ============================================================ */
SELECT DepartmentName FROM dbo.Departments
WHERE DepartmentID NOT IN (SELECT DepartmentID FROM dbo.Employees);        -- 0 rows because one DepartmentID is NULL
SELECT DepartmentName FROM dbo.Departments d
WHERE NOT EXISTS (SELECT 1 FROM dbo.Employees e WHERE e.DepartmentID = d.DepartmentID);   -- Legal (correct)
GO


/* ============================================================
   25. ON vs WHERE IN OUTER JOINS  (the trap)
   ============================================================ */
-- Wrong: WHERE turns the LEFT JOIN into an INNER JOIN (customers without Completed orders disappear)
SELECT c.CustomerName, COUNT(o.OrderID) AS CompletedOrders
FROM dbo.Customers c LEFT JOIN dbo.Orders o ON o.CustomerID = c.CustomerID
WHERE o.Status = 'Completed'
GROUP BY c.CustomerName;
-- Right: put the filter in ON so unmatched customers stay with 0
SELECT c.CustomerName, COUNT(o.OrderID) AS CompletedOrders
FROM dbo.Customers c LEFT JOIN dbo.Orders o ON o.CustomerID = c.CustomerID AND o.Status = 'Completed'
GROUP BY c.CustomerName;
GO


/* ============================================================
   26. CUMULATIVE DISTRIBUTION / TOP 25% EARNERS  (NTILE)
   ============================================================ */
SELECT EmployeeName, Salary, NTILE(4) OVER (ORDER BY Salary DESC) AS Quartile
FROM dbo.Employees;                                        -- Quartile 1 = top 25%
GO


/* ============================================================
   27. DATE SERIES + LEFT JOIN  (show months with zero orders)
   ============================================================ */
WITH months AS (
    SELECT CAST('2025-01-01' AS DATE) AS MonthStart
    UNION ALL SELECT DATEADD(MONTH, 1, MonthStart) FROM months WHERE MonthStart < '2025-12-01')
SELECT FORMAT(m.MonthStart, 'yyyy-MM') AS YearMonth, COUNT(o.OrderID) AS Orders, ISNULL(SUM(o.TotalAmount), 0) AS Revenue
FROM months m
LEFT JOIN dbo.Orders o ON o.OrderDate >= m.MonthStart AND o.OrderDate < DATEADD(MONTH, 1, m.MonthStart)
GROUP BY m.MonthStart ORDER BY m.MonthStart;               -- Oct-Dec show 0
GO


/* ============================================================
   28. UPDATE FROM ANOTHER TABLE  (set Orders.TotalAmount from line totals, on a copy)
   ============================================================ */
DROP TABLE IF EXISTS dbo.IP_Orders2;
SELECT OrderID, TotalAmount INTO dbo.IP_Orders2 FROM dbo.Orders;
UPDATE dbo.IP_Orders2 SET TotalAmount = 0;
GO
UPDATE o
SET o.TotalAmount = t.LineTotal
FROM dbo.IP_Orders2 o
JOIN (SELECT OrderID, SUM(Quantity * UnitPrice) AS LineTotal FROM dbo.OrderDetails GROUP BY OrderID) t
  ON t.OrderID = o.OrderID;
SELECT * FROM dbo.IP_Orders2 ORDER BY OrderID;             -- totals restored
GO


/* ============================================================
   29. CUSTOMERS WHO BOUGHT FROM EVERY CATEGORY  (relational division)
   ============================================================ */
SELECT c.CustomerName
FROM dbo.Customers c
JOIN dbo.Orders o ON o.CustomerID = c.CustomerID
JOIN dbo.OrderDetails od ON od.OrderID = o.OrderID
JOIN dbo.Products p ON p.ProductID = od.ProductID
GROUP BY c.CustomerID, c.CustomerName
HAVING COUNT(DISTINCT p.Category) = (SELECT COUNT(DISTINCT Category) FROM dbo.Products);   -- 0 rows: nobody bought all 3 categories
GO
-- Relaxed: customers who bought from at least 2 different categories
SELECT c.CustomerName, COUNT(DISTINCT p.Category) AS Categories
FROM dbo.Customers c
JOIN dbo.Orders o ON o.CustomerID = c.CustomerID
JOIN dbo.OrderDetails od ON od.OrderID = o.OrderID
JOIN dbo.Products p ON p.ProductID = od.ProductID
GROUP BY c.CustomerID, c.CustomerName
HAVING COUNT(DISTINCT p.Category) >= 2
ORDER BY c.CustomerName;                                    -- Aarav, Bhavna, Chirag, Esha, Gaurav
GO


/* ============================================================
   30. PAGINATION  (page 2, 5 rows per page)
   ============================================================ */
DECLARE @PageNo INT = 2, @PageSize INT = 5;
SELECT EmployeeID, EmployeeName, Salary
FROM dbo.Employees
ORDER BY EmployeeID
OFFSET (@PageNo - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
GO


/* ============================================================
   CLEANUP
   ============================================================ */
DROP TABLE IF EXISTS dbo.IP_Customers, dbo.IP_Orders, dbo.IP_Logins, dbo.IP_Swap, dbo.IP_Products2, dbo.IP_Orders2;
GO
