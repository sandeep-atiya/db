/* ============================================================
   LEVEL 07 - AGGREGATION  |  02_Practice_Advanced_Grouping.sql
   ------------------------------------------------------------
   Topics : GROUP BY with JOIN (orders per customer name, revenue
            per department), conditional aggregation
            SUM(CASE ...) / COUNT(CASE ...), AVG of a ratio vs
            ratio of sums, STRING_AGG per group,
            GROUPING SETS / ROLLUP / CUBE with GROUPING() (advanced),
            top-N groups with TOP + ORDER BY aggregate.
   HOW TO PRACTICE: run block by block, predict the output first.
   Joins are explained fully in Level 08; here you only need
   "JOIN ... ON key = key" to bring a name next to a number.
   ============================================================ */

USE SQLPractice;
GO


/* ==== 1. GROUP BY WITH JOIN ==== */

-- 1a. Orders per CUSTOMER NAME (not ID). Join first, then group by the name.
--     INNER JOIN drops Hina (no orders).
SELECT c.CustomerName, COUNT(*) AS Orders, SUM(o.TotalAmount) AS Revenue
FROM dbo.Customers c
JOIN dbo.Orders o ON o.CustomerID = c.CustomerID
GROUP BY c.CustomerName
ORDER BY Revenue DESC;
-- Esha 2 158000 | Aarav 4 128000 | Farhan 2 88500 | Gaurav 2 87000 | Divya 2 77500 | Bhavna 4 48500 | Chirag 3 30500  (7 rows)
GO

-- 1b. Include customers with ZERO orders: LEFT JOIN + COUNT(o.OrderID), NOT COUNT(*).
--     COUNT(*) would count Hina's one all-NULL row as 1.
SELECT c.CustomerName, COUNT(*) AS CountStar, COUNT(o.OrderID) AS Orders, ISNULL(SUM(o.TotalAmount), 0) AS Revenue
FROM dbo.Customers c
LEFT JOIN dbo.Orders o ON o.CustomerID = c.CustomerID
GROUP BY c.CustomerName
ORDER BY Orders, c.CustomerName;   -- Hina Khan 1 0 0.00 first, then Divya 2 2 77500 ...   (8 rows)
GO

-- 1c. Group by TWO tables' columns: rule is still "every non-aggregated column goes in GROUP BY".
--     Headcount and payroll per department NAME (Anjali has no department -> dropped by INNER JOIN).
SELECT d.DepartmentName, d.Location, COUNT(e.EmployeeID) AS Headcount, SUM(e.Salary) AS Payroll
FROM dbo.Departments d
JOIN dbo.Employees e ON e.DepartmentID = d.DepartmentID
GROUP BY d.DepartmentName, d.Location
ORDER BY Payroll DESC;   -- IT Delhi 3 215000 | Sales Mumbai 3 192000 | Finance Bangalore 2 162000 | Marketing Pune 2 128000 | HR Delhi 1 60000
GO

-- 1d. Revenue per DEPARTMENT via the salesperson: Orders -> Employees -> Departments (3 tables).
--     All salespeople are in Sales; the online order (EmployeeID NULL) is dropped by the INNER JOIN.
SELECT d.DepartmentName, COUNT(o.OrderID) AS Orders, SUM(o.TotalAmount) AS Revenue
FROM dbo.Orders o
JOIN dbo.Employees   e ON e.EmployeeID   = o.EmployeeID
JOIN dbo.Departments d ON d.DepartmentID = e.DepartmentID
GROUP BY d.DepartmentName;   -- Sales 18 615500  (the 19th order, 2500, has no salesperson)
GO

-- 1e. Revenue per product CATEGORY: OrderDetails -> Products
SELECT p.Category, SUM(od.Quantity) AS Units, SUM(od.Quantity * od.UnitPrice) AS Revenue
FROM dbo.OrderDetails od
JOIN dbo.Products p ON p.ProductID = od.ProductID
GROUP BY p.Category
ORDER BY Revenue DESC;   -- Electronics 33 510500 | Furniture 10 105000 | Stationery 170 2500
GO


/* ==== 2. CONDITIONAL AGGREGATION  SUM(CASE ...) / COUNT(CASE ...) ==== */
-- The trick: put a CASE INSIDE the aggregate. Each row contributes 1 (or its amount) only when the condition holds.
-- This is how you get several "filtered counts" side by side in ONE pass over the table.

-- 2a. Completed / Pending / Cancelled orders per customer, plus revenue from Completed orders only
SELECT c.CustomerName,
       COUNT(o.OrderID)                                                  AS AllOrders,
       SUM(CASE WHEN o.Status = 'Completed' THEN 1 ELSE 0 END)           AS Completed,
       SUM(CASE WHEN o.Status = 'Pending'   THEN 1 ELSE 0 END)           AS Pending,
       COUNT(CASE WHEN o.Status = 'Cancelled' THEN 1 END)                AS Cancelled,   -- COUNT ignores the NULL from "no ELSE"
       SUM(CASE WHEN o.Status = 'Completed' THEN o.TotalAmount ELSE 0 END) AS CompletedRevenue
FROM dbo.Customers c
LEFT JOIN dbo.Orders o ON o.CustomerID = c.CustomerID
GROUP BY c.CustomerName
ORDER BY c.CustomerName;
-- Aarav 4 3 1 0 96000 | Bhavna 4 4 0 0 48500 | Chirag 3 2 1 0 26500 | Divya 2 2 0 0 77500
-- Esha 2 1 0 1 150000 | Farhan 2 2 0 0 88500 | Gaurav 2 2 0 0 87000 | Hina 0 0 0 0 0
GO

-- 2b. Same idea as a "pivot": orders per month in columns for each status
SELECT Status,
       SUM(CASE WHEN DATEPART(quarter, OrderDate) = 1 THEN 1 ELSE 0 END) AS Q1,
       SUM(CASE WHEN DATEPART(quarter, OrderDate) = 2 THEN 1 ELSE 0 END) AS Q2,
       SUM(CASE WHEN DATEPART(quarter, OrderDate) = 3 THEN 1 ELSE 0 END) AS Q3,
       COUNT(*) AS Total
FROM dbo.Orders
GROUP BY Status;   -- Cancelled 1 0 0 1 | Completed 7 6 3 16 | Pending 0 0 2 2
GO

-- 2c. Percentage with conditional aggregation: share of Completed orders per customer (note * 100.0)
SELECT c.CustomerName,
       COUNT(o.OrderID) AS Orders,
       CAST(SUM(CASE WHEN o.Status = 'Completed' THEN 1 ELSE 0 END) * 100.0 / COUNT(o.OrderID) AS DECIMAL(5,1)) AS CompletedPct
FROM dbo.Customers c
JOIN dbo.Orders o ON o.CustomerID = c.CustomerID
GROUP BY c.CustomerName
ORDER BY CompletedPct, c.CustomerName;   -- Esha 50.0, Chirag 66.7, Aarav 75.0, then 100.0 for the rest
GO

-- 2d. Real-world: employees hired per year, split into "with manager" / "top level"
SELECT YEAR(HireDate) AS HireYear, COUNT(*) AS Hired,
       SUM(CASE WHEN ManagerID IS NULL THEN 1 ELSE 0 END) AS Heads,
       SUM(CASE WHEN ManagerID IS NOT NULL THEN 1 ELSE 0 END) AS Reports
FROM dbo.Employees
GROUP BY YEAR(HireDate)
ORDER BY HireYear;   -- 2020 1 1 0 | 2021 2 1 1 | 2022 3 2 1 | 2023 3 1 2 | 2024 3 1 2
GO


/* ==== 3. AVG OF A RATIO vs RATIO OF SUMS  (interview classic) ==== */
-- "Average selling price per unit in each category?"
--   AVG(UnitPrice)                       = average of the LINE prices (a 100-pen line counts the same as a 1-laptop line)
--   SUM(Qty * UnitPrice) / SUM(Qty)      = revenue per unit actually sold (weighted) -> usually what the business means
SELECT p.Category,
       COUNT(*)                                             AS Lines,
       AVG(od.UnitPrice)                                    AS AvgOfLinePrices,          -- Electronics 20294.117647
       SUM(od.Quantity * od.UnitPrice) / SUM(od.Quantity)   AS WeightedPricePerUnit      -- Electronics 15469.696969
FROM dbo.OrderDetails od
JOIN dbo.Products p ON p.ProductID = od.ProductID
GROUP BY p.Category
ORDER BY p.Category;   -- Furniture 6 11000 vs 10500 | Stationery 3 23.33 vs 14.71 (rounded)
GO

-- Same trap with percentages (uses a derived table - Level 09 preview):
-- "average of per-customer average order value" is NOT the overall average order value.
SELECT AVG(x.AvgPerCustomer) AS AvgOfAverages,               -- 37113.095238 (each customer weighs the same)
       SUM(x.Total) / SUM(x.Orders) AS OverallAverage         -- 32526.315789 (= 618000 / 19, each ORDER weighs the same)
FROM (SELECT CustomerID, AVG(TotalAmount) AS AvgPerCustomer, SUM(TotalAmount) AS Total, COUNT(*) AS Orders
      FROM dbo.Orders GROUP BY CustomerID) AS x;
GO


/* ==== 4. STRING_AGG PER GROUP ==== */

-- 4a. Employees per department as one line (LEFT JOIN keeps Legal with 0 / NULL)
SELECT d.DepartmentName, COUNT(e.EmployeeID) AS Headcount,
       STRING_AGG(e.EmployeeName, ', ') WITHIN GROUP (ORDER BY e.EmployeeName) AS Members
FROM dbo.Departments d
LEFT JOIN dbo.Employees e ON e.DepartmentID = d.DepartmentID
GROUP BY d.DepartmentName
ORDER BY Headcount DESC, d.DepartmentName;
-- IT 3 Amit, Pooja, Rahul | Sales 3 Neha, Priya, Vikram | Finance 2 Deepak, Sneha | Marketing 2 Karan, Meera | HR 1 Ravi | Legal 0 NULL
GO

-- 4b. Products per category with price in the text (CONCAT to build each item first)
SELECT Category, COUNT(*) AS Products,
       STRING_AGG(CONCAT(ProductName, ' (', Price, ')'), ' | ') WITHIN GROUP (ORDER BY Price DESC) AS PriceList
FROM dbo.Products
GROUP BY Category;   -- Stationery 2 Notebook (50.00) | Pen (10.00)
GO


/* ==== 5. GROUPING SETS / ROLLUP / CUBE  (ADVANCED - reporting subtotals) ==== */
-- Normal GROUP BY gives one level of totals. These give SEVERAL levels in ONE query.
-- GROUPING(col) = 1 on the subtotal rows where that column is "all" (shown as NULL) - use it to label them.

-- 5a. ROLLUP(a, b) = totals for (a, b), then (a), then ()  -> hierarchy: quarter -> status -> grand total
SELECT DATEPART(quarter, OrderDate) AS Qtr, Status, COUNT(*) AS Orders, SUM(TotalAmount) AS Revenue,
       GROUPING(DATEPART(quarter, OrderDate)) AS IsAllQtr, GROUPING(Status) AS IsAllStatus
FROM dbo.Orders
GROUP BY ROLLUP(DATEPART(quarter, OrderDate), Status)
ORDER BY IsAllQtr, Qtr, IsAllStatus, Status;
-- 1 Cancelled 1 8000 | 1 Completed 7 259500 | 1 NULL 8 267500 (Q1 subtotal) | 2 Completed 6 227000 | 2 NULL 6 227000
-- 3 Completed 3 87500 | 3 Pending 2 36000 | 3 NULL 5 123500 | NULL NULL 19 618000 (grand total)     (9 rows)
GO

-- 5b. Label the subtotal rows with GROUPING() + CASE instead of showing NULL
SELECT CASE WHEN GROUPING(Status) = 1 THEN 'ALL' ELSE Status END AS Status,
       COUNT(*) AS Orders, SUM(TotalAmount) AS Revenue
FROM dbo.Orders
GROUP BY ROLLUP(Status);   -- Cancelled 1 8000 | Completed 16 574000 | Pending 2 36000 | ALL 19 618000
GO

-- 5c. CUBE(a, b) = ALL combinations: (a,b), (a), (b), ()  -> also gives per-status totals across quarters
SELECT DATEPART(quarter, OrderDate) AS Qtr, Status, COUNT(*) AS Orders,
       GROUPING(DATEPART(quarter, OrderDate)) AS IsAllQtr, GROUPING(Status) AS IsAllStatus
FROM dbo.Orders
GROUP BY CUBE(DATEPART(quarter, OrderDate), Status)
ORDER BY IsAllQtr, Qtr, IsAllStatus, Status;   -- 12 rows = 5 combos + 3 quarter subtotals + 3 status subtotals + 1 grand total
GO

-- 5d. GROUPING SETS = you choose exactly which subtotal levels you want (here: per quarter, per status, grand total; NO combos)
SELECT DATEPART(quarter, OrderDate) AS Qtr, Status, COUNT(*) AS Orders
FROM dbo.Orders
GROUP BY GROUPING SETS ( (DATEPART(quarter, OrderDate)), (Status), () )
ORDER BY GROUPING(DATEPART(quarter, OrderDate)), Qtr, Status;   -- 7 rows: 3 quarters, 3 statuses, 1 total
GO


/* ==== 6. TOP-N GROUPS  (TOP + ORDER BY aggregate) ==== */

-- 6a. Top 3 customers by revenue
SELECT TOP (3) c.CustomerName, SUM(o.TotalAmount) AS Revenue
FROM dbo.Customers c
JOIN dbo.Orders o ON o.CustomerID = c.CustomerID
GROUP BY c.CustomerName
ORDER BY Revenue DESC;   -- Esha 158000, Aarav 128000, Farhan 88500
GO

-- 6b. Top 3 products by units sold
SELECT TOP (3) p.ProductName, SUM(od.Quantity) AS Units, SUM(od.Quantity * od.UnitPrice) AS Revenue
FROM dbo.OrderDetails od
JOIN dbo.Products p ON p.ProductID = od.ProductID
GROUP BY p.ProductName
ORDER BY Units DESC;   -- Pen 150, Notebook 20, Mouse 14
GO

-- 6c. WITH TIES: "the customer with the most orders" - two customers have 4, so both come back
SELECT TOP (1) WITH TIES c.CustomerName, COUNT(*) AS Orders
FROM dbo.Customers c
JOIN dbo.Orders o ON o.CustomerID = c.CustomerID
GROUP BY c.CustomerName
ORDER BY Orders DESC;   -- Aarav Sharma 4, Bhavna Mehta 4
GO

-- 6d. Bottom-N = ORDER BY ... ASC: the department with the smallest payroll (Anjali's NULL group excluded via WHERE)
SELECT TOP (1) d.DepartmentName, SUM(e.Salary) AS Payroll
FROM dbo.Departments d
JOIN dbo.Employees e ON e.DepartmentID = d.DepartmentID
GROUP BY d.DepartmentName
ORDER BY Payroll ASC;   -- HR 60000
GO

/* ------------------------------------------------------------
   DONE. Next: Exercises.sql
   (No CLEANUP needed: this file created nothing.)
   ------------------------------------------------------------ */
