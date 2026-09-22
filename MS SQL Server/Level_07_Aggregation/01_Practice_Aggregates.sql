/* ============================================================
   LEVEL 07 - AGGREGATION  |  01_Practice_Aggregates.sql
   ------------------------------------------------------------
   Topics : COUNT(*) vs COUNT(col) vs COUNT(DISTINCT col),
            SUM / AVG / MIN / MAX (NULL behaviour, integer AVG trap,
            MIN/MAX on dates and strings), aggregates without
            GROUP BY, GROUP BY one / many columns / expressions,
            the "invalid in the select list" error, WHERE vs HAVING,
            HAVING without GROUP BY, ORDER BY aggregate and alias.
   HOW TO PRACTICE: run block by block, predict the output first.
   Nothing is created or changed in this file (read-only queries).
   ============================================================ */

USE SQLPractice;
GO


/* ==== 1. WHAT IS AN AGGREGATE? ==== */
-- An aggregate function looks at MANY rows and returns ONE value.
-- Without GROUP BY the whole table is one group -> exactly one result row.
SELECT COUNT(*) AS Employees, SUM(Salary) AS Payroll, AVG(Salary) AS AvgSalary,
       MIN(Salary) AS Lowest, MAX(Salary) AS Highest
FROM dbo.Employees;   -- 12, 805000.00, 67083.333333, 48000.00, 90000.00
GO


/* ==== 2. COUNT(*) vs COUNT(column) vs COUNT(DISTINCT column) ==== */

-- 2a. COUNT(*) counts ROWS. COUNT(col) counts NON-NULL values. COUNT(DISTINCT col) counts different non-NULL values.
--     Anjali has DepartmentID NULL; 5 different departments have staff.
SELECT COUNT(*)                     AS AllRows,        -- 12
       COUNT(DepartmentID)          AS WithDept,       -- 11  (NULL not counted)
       COUNT(DISTINCT DepartmentID) AS DistinctDepts,  -- 5   (1,2,3,4,5 - NULL ignored)
       COUNT(1)                     AS CountOne        -- 12  (same as COUNT(*), not faster)
FROM dbo.Employees;
GO

-- 2b. Customers: 2 have NULL email, 5 different cities
SELECT COUNT(*) AS Customers, COUNT(Email) AS WithEmail, COUNT(*) - COUNT(Email) AS WithoutEmail,
       COUNT(DISTINCT City) AS Cities
FROM dbo.Customers;   -- 8, 6, 2, 5
GO

-- 2c. Orders: one order has no salesperson
SELECT COUNT(*) AS Orders, COUNT(EmployeeID) AS WithSalesperson, COUNT(DISTINCT EmployeeID) AS DistinctSalespeople
FROM dbo.Orders;   -- 19, 18, 3
GO


/* ==== 3. SUM, AVG, MIN, MAX ==== */

-- 3a. All of them IGNORE NULL. So AVG = SUM / COUNT(col), NOT SUM / COUNT(*).
--     A tiny inline table makes it obvious: bonuses 10, 20 and NULL.
SELECT SUM(b.Bonus) AS Total, AVG(b.Bonus) AS AvgIgnoresNull, SUM(b.Bonus) / COUNT(*) AS DividedByAllRows,
       COUNT(b.Bonus) AS NonNull, COUNT(*) AS Rows
FROM (VALUES (10), (20), (NULL)) AS b(Bonus);   -- 30, 15, 10, 2, 3
GO
-- If you WANT NULL to count as zero: AVG(ISNULL(Bonus, 0))  -> 10

-- 3b. INTEGER AVG TRAP: AVG of an INT column returns an INT (truncated). Stock is INT.
SELECT SUM(Stock) AS TotalStock, COUNT(*) AS Products,
       AVG(Stock)          AS AvgTruncated,   -- 159      (1755 / 11 = 159.54 -> cut)
       AVG(Stock * 1.0)    AS AvgDecimal,     -- 159.545454
       AVG(CAST(Stock AS DECIMAL(10,2))) AS AvgCast   -- 159.545454
FROM dbo.Products;
GO

-- 3c. MIN / MAX work on numbers, DATES and STRINGS (alphabetical).
SELECT MIN(OrderDate) AS FirstOrder, MAX(OrderDate) AS LastOrder          -- 2025-01-05, 2025-09-05
FROM dbo.Orders;
SELECT MIN(HireDate)  AS LongestServing, MAX(HireDate) AS Newest,        -- 2020-05-18 (Sneha), 2024-05-20 (Anjali)
       MIN(EmployeeName) AS FirstAlpha, MAX(EmployeeName) AS LastAlpha   -- Amit, Vikram
FROM dbo.Employees;
GO

-- 3d. Aggregates over ZERO rows: COUNT gives 0, the others give NULL.
SELECT COUNT(*) AS Cnt, SUM(Salary) AS Total, AVG(Salary) AS Avg, MAX(Salary) AS Mx
FROM dbo.Employees
WHERE Salary > 1000000;   -- 0, NULL, NULL, NULL
GO

-- 3e. Aggregates can take expressions: revenue = quantity * price
SELECT SUM(Quantity) AS UnitsSold, SUM(Quantity * UnitPrice) AS Revenue, AVG(Quantity) AS AvgQtyTruncated, MAX(Quantity * UnitPrice) AS BiggestLine
FROM dbo.OrderDetails;   -- 213, 618000.00, 8 (213/26 = 8.19), 150000.00
GO


/* ==== 4. AGGREGATE + PLAIN COLUMN WITHOUT GROUP BY = ERROR ==== */

-- 4a. "Show the highest salary" is fine. "Show the name AND the highest salary" is NOT: one name for 12 rows? SQL refuses.
--     (Msg 8120 is a compile-time error, so it is run via sp_executesql to make TRY/CATCH able to catch it.)
BEGIN TRY
    EXEC sp_executesql N'SELECT EmployeeName, MAX(Salary) FROM dbo.Employees;';
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO
-- Fix 1: filter instead of aggregate (Level 09 will do it with a subquery)
SELECT TOP (1) EmployeeName, Salary FROM dbo.Employees ORDER BY Salary DESC;   -- Sneha 90000
GO


/* ==== 5. GROUP BY - ONE COLUMN ==== */

-- 5a. GROUP BY makes one row PER DISTINCT VALUE of the column. Aggregates then work inside each group.
--     NULL forms its OWN group (Anjali).
SELECT DepartmentID, COUNT(*) AS Employees, SUM(Salary) AS Payroll, AVG(Salary) AS AvgSalary
FROM dbo.Employees
GROUP BY DepartmentID
ORDER BY DepartmentID;
-- NULL 1 48000 | 1 3 215000 71666.67 | 2 3 192000 64000 | 3 1 60000 | 4 2 162000 81000 | 5 2 128000 64000   (6 rows)
GO

-- 5b. Orders per status
SELECT Status, COUNT(*) AS Orders, SUM(TotalAmount) AS Amount
FROM dbo.Orders
GROUP BY Status;   -- Cancelled 1 8000 | Completed 16 574000 | Pending 2 36000
GO

-- 5c. Products per category with stock and average price
SELECT Category, COUNT(*) AS Products, SUM(Stock) AS Stock, AVG(Price) AS AvgPrice, MAX(Price) AS Priciest
FROM dbo.Products
GROUP BY Category;   -- Electronics 6 215 18500 75000 | Furniture 3 40 11666.666666 15000 | Stationery 2 1500 30 50
GO


/* ==== 6. GROUP BY - MANY COLUMNS ==== */

-- One row per DISTINCT COMBINATION. Every non-aggregated column in SELECT must be in GROUP BY.
SELECT CustomerID, Status, COUNT(*) AS Orders, SUM(TotalAmount) AS Amount
FROM dbo.Orders
GROUP BY CustomerID, Status
ORDER BY CustomerID, Status;   -- 10 rows: 1 Completed 3 / 1 Pending 1 / 2 Completed 4 / 3 Completed 2 / 3 Pending 1 / ...
GO

-- Order of columns in GROUP BY does not change the groups, only (maybe) the default output order.
SELECT City, COUNT(*) AS Customers, COUNT(Email) AS WithEmail
FROM dbo.Customers
GROUP BY City
ORDER BY Customers DESC, City;   -- Delhi 3 2 | Mumbai 2 1 | Bangalore 1 1 | Chennai 1 1 | Pune 1 1
GO


/* ==== 7. GROUP BY - EXPRESSIONS  (YEAR, MONTH, CASE ...) ==== */

-- 7a. You can group by an expression. The SAME expression must appear in SELECT (or be wrapped in an aggregate).
SELECT YEAR(OrderDate) AS Yr, MONTH(OrderDate) AS Mth, COUNT(*) AS Orders, SUM(TotalAmount) AS Revenue
FROM dbo.Orders
GROUP BY YEAR(OrderDate), MONTH(OrderDate)
ORDER BY Yr, Mth;   -- 2025 1 3 110000 | 2025 2 3 73000 | 2025 3 2 84500 | ... | 2025 9 1 2500   (9 rows)
GO

-- 7b. Quarter, using DATEPART, plus the month NAME (both must be in GROUP BY)
SELECT DATEPART(quarter, OrderDate) AS Qtr, COUNT(*) AS Orders, SUM(TotalAmount) AS Revenue
FROM dbo.Orders
GROUP BY DATEPART(quarter, OrderDate)
ORDER BY Qtr;   -- 1 8 267500 | 2 6 227000 | 3 5 123500
GO

-- 7c. Grouping by a CASE bucket (salary bands)
SELECT CASE WHEN Salary >= 80000 THEN 'High' WHEN Salary >= 60000 THEN 'Mid' ELSE 'Low' END AS Band,
       COUNT(*) AS Employees, MIN(Salary) AS MinSal, MAX(Salary) AS MaxSal
FROM dbo.Employees
GROUP BY CASE WHEN Salary >= 80000 THEN 'High' WHEN Salary >= 60000 THEN 'Mid' ELSE 'Low' END
ORDER BY MinSal DESC;   -- High 2 85000 90000 | Mid 7 60000 75000 | Low 3 48000 58000
GO


/* ==== 8. THE CLASSIC ERROR: "column is invalid in the select list ..." ==== */

-- 8a. EmployeeName is neither aggregated nor in GROUP BY -> Msg 8120.
BEGIN TRY
    EXEC sp_executesql N'SELECT DepartmentID, EmployeeName, COUNT(*) FROM dbo.Employees GROUP BY DepartmentID;';
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO

-- 8b. Fix A: add the column to GROUP BY (changes the grouping - now one row per employee, count is 1 each)
SELECT DepartmentID, EmployeeName, COUNT(*) AS Cnt
FROM dbo.Employees
GROUP BY DepartmentID, EmployeeName
ORDER BY DepartmentID, EmployeeName;   -- 12 rows, Cnt = 1
GO

-- 8c. Fix B: wrap it in an aggregate (which name do you want? MIN = alphabetically first)
SELECT DepartmentID, MIN(EmployeeName) AS FirstName, COUNT(*) AS Cnt
FROM dbo.Employees
GROUP BY DepartmentID
ORDER BY DepartmentID;   -- NULL Anjali 1 | 1 Amit 3 | 2 Neha 3 | 3 Ravi 1 | 4 Deepak 2 | 5 Karan 2
GO

-- 8d. Fix C: STRING_AGG (Level 06) if you want ALL the names
SELECT DepartmentID, STRING_AGG(EmployeeName, ', ') WITHIN GROUP (ORDER BY EmployeeName) AS Names, COUNT(*) AS Cnt
FROM dbo.Employees
GROUP BY DepartmentID
ORDER BY DepartmentID;   -- 1 -> Amit, Pooja, Rahul  3
GO


/* ==== 9. WHERE vs HAVING ==== */
-- Logical order:  FROM -> WHERE -> GROUP BY -> HAVING -> SELECT -> ORDER BY
--   WHERE  filters ROWS   BEFORE grouping  (cannot use aggregates)
--   HAVING filters GROUPS AFTER  grouping  (can use aggregates)

-- 9a. HAVING: departments with more than 2 employees
SELECT DepartmentID, COUNT(*) AS Employees
FROM dbo.Employees
GROUP BY DepartmentID
HAVING COUNT(*) > 2;   -- 1 (3), 2 (3)
GO

-- 9b. WHERE and HAVING together: among employees earning > 60000, departments with at least 2 such people
SELECT DepartmentID, COUNT(*) AS HighEarners, SUM(Salary) AS Payroll
FROM dbo.Employees
WHERE Salary > 60000              -- row filter first: Ravi (60000), Neha, Anjali, Meera drop out
GROUP BY DepartmentID
HAVING COUNT(*) >= 2              -- group filter after: Marketing (only Karan) drops out
ORDER BY DepartmentID;   -- 1 3 215000 | 2 2 137000 | 4 2 162000
GO

-- 9c. An aggregate in WHERE is an error (rows are not grouped yet at that point)
BEGIN TRY
    EXEC sp_executesql N'SELECT DepartmentID FROM dbo.Employees WHERE COUNT(*) > 2 GROUP BY DepartmentID;';
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO

-- 9d. HAVING without GROUP BY: the whole table is one group; the row appears only if the condition holds.
SELECT COUNT(*) AS Orders, SUM(TotalAmount) AS Revenue FROM dbo.Orders HAVING COUNT(*) > 10;    -- 1 row: 19, 618000
SELECT COUNT(*) AS Orders, SUM(TotalAmount) AS Revenue FROM dbo.Orders HAVING COUNT(*) > 100;   -- 0 rows
GO

-- 9e. A non-aggregate condition CAN go in HAVING, but WHERE is better (filters earlier = less work).
SELECT Status, COUNT(*) AS Orders FROM dbo.Orders GROUP BY Status HAVING Status <> 'Cancelled';   -- works, but ...
SELECT Status, COUNT(*) AS Orders FROM dbo.Orders WHERE Status <> 'Cancelled' GROUP BY Status;    -- ... prefer this
GO


/* ==== 10. ORDER BY AGGREGATE AND ALIAS ==== */

-- 10a. Sort by the aggregate itself, or by its alias (ORDER BY runs AFTER SELECT, so aliases are visible there)
SELECT DepartmentID, SUM(Salary) AS Payroll
FROM dbo.Employees
GROUP BY DepartmentID
ORDER BY SUM(Salary) DESC;   -- 1 215000, 2 192000, 4 162000, 5 128000, 3 60000, NULL 48000
GO
SELECT DepartmentID, SUM(Salary) AS Payroll
FROM dbo.Employees
GROUP BY DepartmentID
ORDER BY Payroll DESC;       -- same result using the alias
GO

-- 10b. But an alias is NOT visible in WHERE / GROUP BY / HAVING (they run before SELECT) -> Msg 207
BEGIN TRY
    EXEC sp_executesql N'SELECT DepartmentID, SUM(Salary) AS Payroll FROM dbo.Employees GROUP BY DepartmentID HAVING Payroll > 100000;';
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO
SELECT DepartmentID, SUM(Salary) AS Payroll
FROM dbo.Employees
GROUP BY DepartmentID
HAVING SUM(Salary) > 100000        -- repeat the expression
ORDER BY Payroll DESC;   -- 1 215000, 2 192000, 4 162000, 5 128000
GO

-- 10c. Sort by two aggregates: most orders first, then highest revenue
SELECT CustomerID, COUNT(*) AS Orders, SUM(TotalAmount) AS Revenue
FROM dbo.Orders
GROUP BY CustomerID
ORDER BY Orders DESC, Revenue DESC;   -- 1 (4, 128000), 2 (4, 48500), 3 (3, 30500), 5 (2, 158000), 6 (2, 88500), 7 (2, 87000), 4 (2, 77500)
GO

/* ------------------------------------------------------------
   DONE. Next: 02_Practice_Advanced_Grouping.sql
   (No CLEANUP needed: this file created nothing.)
   ------------------------------------------------------------ */
