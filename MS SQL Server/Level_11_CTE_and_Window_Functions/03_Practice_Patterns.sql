/* ============================================================
   LEVEL 11 - CTE AND WINDOW FUNCTIONS  |  03_Practice_Patterns.sql
   ------------------------------------------------------------
   Topics : the INTERVIEW PATTERNS built from CTEs + window functions:
            top-N per group, Nth highest salary (3 ways), deduplication,
            gaps and islands (streaks, missing dates, missing IDs),
            running total that resets per partition, month-over-month
            growth with LAG, first order per customer, consecutive
            orders that increased, above-department-average
            (window vs correlated subquery).

   HOW TO PRACTICE: run block by block, predict the output first.
   Creates dbo.L11_DupCustomers, dbo.L11_Logins, dbo.L11_OrderIds;
   all dropped in CLEANUP. Base tables are never changed.
   ============================================================ */

USE SQLPractice;
GO
DROP TABLE IF EXISTS dbo.L11_DupCustomers;
DROP TABLE IF EXISTS dbo.L11_Logins;
DROP TABLE IF EXISTS dbo.L11_OrderIds;
GO


/* ============================================================
   1. PATTERN: TOP-N PER GROUP
   ============================================================
   Number the rows inside each group (PARTITION BY group ORDER BY
   measure DESC), then keep rn <= N in an outer query.
   ============================================================ */

-- 1a. Highest paid employee in each department.
WITH Ranked AS
(
    SELECT e.DepartmentID, e.EmployeeName, e.Salary,
           ROW_NUMBER() OVER (PARTITION BY e.DepartmentID ORDER BY e.Salary DESC, e.EmployeeID) AS rn
    FROM dbo.Employees e
    WHERE e.DepartmentID IS NOT NULL
)
SELECT d.DepartmentName, r.EmployeeName, r.Salary
FROM Ranked r
JOIN dbo.Departments d ON d.DepartmentID = r.DepartmentID
WHERE r.rn = 1
ORDER BY d.DepartmentName;
GO
-- expect 5 rows: Finance Sneha 90000, HR Ravi 60000, IT Rahul 85000, Marketing Karan 70000, Sales Priya 75000
-- Want ALL people tied at the top? Use DENSE_RANK() ... = 1 instead of ROW_NUMBER.

-- 1b. Top 2 products per category by revenue.
WITH Rev AS
(
    SELECT p.Category, p.ProductName, SUM(od.Quantity * od.UnitPrice) AS Revenue
    FROM dbo.OrderDetails od
    JOIN dbo.Products p ON p.ProductID = od.ProductID
    GROUP BY p.Category, p.ProductName
),
Ranked AS
(
    SELECT Category, ProductName, Revenue,
           DENSE_RANK() OVER (PARTITION BY Category ORDER BY Revenue DESC) AS rk
    FROM Rev
)
SELECT Category, ProductName, Revenue, rk
FROM Ranked
WHERE rk <= 2
ORDER BY Category, rk;
GO
-- expect 6 rows: Electronics Laptop 300000 / Monitor 175000, Furniture Chair 48000 / Desk 45000,
--                Stationery Pen 1500 / Notebook 1000


/* ============================================================
   2. PATTERN: NTH HIGHEST SALARY  (three ways)
   ============================================================ */

-- 2a. DENSE_RANK (the answer interviewers want): handles ties, gives the name too.
WITH Ranked AS
(
    SELECT EmployeeName, Salary, DENSE_RANK() OVER (ORDER BY Salary DESC) AS rk
    FROM dbo.Employees
)
SELECT EmployeeName, Salary FROM Ranked WHERE rk = 2;
GO
-- expect 1 row: Rahul 85000

-- 2b. OFFSET / FETCH on the distinct salaries: skip N-1, take 1.
SELECT DISTINCT Salary
FROM dbo.Employees
ORDER BY Salary DESC
OFFSET 1 ROWS FETCH NEXT 1 ROWS ONLY;
GO
-- expect 85000.00

-- 2c. The subquery way (Level 09): biggest salary below the biggest salary.
SELECT MAX(Salary) AS SecondHighest
FROM dbo.Employees
WHERE Salary < (SELECT MAX(Salary) FROM dbo.Employees);
GO
-- expect 85000.00

-- 2d. WHY DENSE_RANK and not RANK: after the 65000 tie (positions 6 and 7),
--     RANK jumps to 8, so "RANK = 7" finds NOBODY. DENSE_RANK = 7 finds Vikram.
WITH Ranked AS
(
    SELECT EmployeeName, Salary,
           RANK()       OVER (ORDER BY Salary DESC) AS rnk,
           DENSE_RANK() OVER (ORDER BY Salary DESC) AS drk
    FROM dbo.Employees
)
SELECT 'RANK = 7' AS Method, EmployeeName, Salary FROM Ranked WHERE rnk = 7
UNION ALL
SELECT 'DENSE_RANK = 7', EmployeeName, Salary FROM Ranked WHERE drk = 7;
GO
-- expect 1 row: DENSE_RANK = 7 Vikram 62000  (the RANK branch returns nothing)


/* ============================================================
   3. PATTERN: DEDUPLICATION  (find duplicates, delete all but one)
   ============================================================ */

-- 3a. A table with duplicate customers (same name + email, different Id).
CREATE TABLE dbo.L11_DupCustomers
(
    Id           INT IDENTITY(1,1) PRIMARY KEY,
    CustomerName VARCHAR(100),
    Email        VARCHAR(150),
    City         VARCHAR(100)
);
INSERT INTO dbo.L11_DupCustomers (CustomerName, Email, City)
SELECT CustomerName, Email, City FROM dbo.Customers ORDER BY CustomerID;   -- Ids 1..8
INSERT INTO dbo.L11_DupCustomers (CustomerName, Email, City) VALUES
('Aarav Sharma', 'aarav@example.com',  'Delhi'),     -- Id 9  (dup of 1)
('Aarav Sharma', 'aarav@example.com',  'Delhi'),     -- Id 10 (dup of 1)
('Bhavna Mehta', 'bhavna@example.com', 'Mumbai');    -- Id 11 (dup of 2)
SELECT COUNT(*) AS TotalRows FROM dbo.L11_DupCustomers;
GO
-- expect 11

-- 3b. Which values are duplicated? (GROUP BY ... HAVING COUNT(*) > 1)
SELECT CustomerName, Email, COUNT(*) AS Copies
FROM dbo.L11_DupCustomers
GROUP BY CustomerName, Email
HAVING COUNT(*) > 1;
GO
-- expect 2 rows: Aarav Sharma 3, Bhavna Mehta 2

-- 3c. Which ROWS are the extra copies? Number each group by Id; rn > 1 = extras.
SELECT Id, CustomerName, Email,
       ROW_NUMBER() OVER (PARTITION BY CustomerName, Email ORDER BY Id) AS rn
FROM dbo.L11_DupCustomers
ORDER BY CustomerName, Id;
GO
-- expect 11 rows; Ids 9, 10 (Aarav) and 11 (Bhavna) have rn 2, 3 and 2

-- 3d. DELETE the extras through a CTE, keeping the LOWEST Id of each group.
WITH Numbered AS
(
    SELECT Id,
           ROW_NUMBER() OVER (PARTITION BY CustomerName, Email ORDER BY Id) AS rn
    FROM dbo.L11_DupCustomers
)
DELETE FROM Numbered WHERE rn > 1;
GO
-- expect (3 rows affected)
SELECT COUNT(*) AS RemainingRows FROM dbo.L11_DupCustomers;
GO
-- expect 8   (ORDER BY Id DESC in the window would keep the NEWEST copy instead)


/* ============================================================
   4. PATTERN: GAPS AND ISLANDS
   ============================================================
   Islands = runs of consecutive values (login streaks).
   Gaps    = the missing values between them.
   TRICK: date - ROW_NUMBER() is CONSTANT inside a consecutive run.
   ============================================================ */

-- 4a. Login history: user 1 logged in on 1,2,3 then 5,6 then 10 March; user 2 on 1 then 3,4,5.
CREATE TABLE dbo.L11_Logins (UserID INT, LoginDate DATE);
INSERT INTO dbo.L11_Logins VALUES
(1, '20250301'), (1, '20250302'), (1, '20250303'), (1, '20250305'), (1, '20250306'), (1, '20250310'),
(2, '20250301'), (2, '20250303'), (2, '20250304'), (2, '20250305');
GO

-- 4b. Step 1 - see the trick: LoginDate minus its row number is the same for a whole streak.
SELECT UserID, LoginDate,
       ROW_NUMBER() OVER (PARTITION BY UserID ORDER BY LoginDate) AS rn,
       DATEADD(DAY, -ROW_NUMBER() OVER (PARTITION BY UserID ORDER BY LoginDate), LoginDate) AS Grp
FROM dbo.L11_Logins
ORDER BY UserID, LoginDate;
GO
-- expect 10 rows; user 1: Grp = 2025-02-28 for 1-3 March, 2025-03-01 for 5-6 March, 2025-03-04 for 10 March

-- 4c. Step 2 - group by the constant: one row per streak with start, end and length.
WITH G AS
(
    SELECT UserID, LoginDate,
           DATEADD(DAY, -ROW_NUMBER() OVER (PARTITION BY UserID ORDER BY LoginDate), LoginDate) AS Grp
    FROM dbo.L11_Logins
)
SELECT UserID, MIN(LoginDate) AS StreakStart, MAX(LoginDate) AS StreakEnd, COUNT(*) AS Days
FROM G
GROUP BY UserID, Grp
ORDER BY UserID, StreakStart;
GO
-- expect 5 rows: user 1: 01-03 (3 days), 05-06 (2), 10-10 (1); user 2: 01-01 (1), 03-05 (3)

-- 4d. Longest streak per user (top-1 per group on top of the islands).
WITH G AS
(
    SELECT UserID, LoginDate,
           DATEADD(DAY, -ROW_NUMBER() OVER (PARTITION BY UserID ORDER BY LoginDate), LoginDate) AS Grp
    FROM dbo.L11_Logins
),
Streaks AS
(
    SELECT UserID, MIN(LoginDate) AS StreakStart, COUNT(*) AS Days
    FROM G GROUP BY UserID, Grp
)
SELECT UserID, StreakStart, Days
FROM (SELECT *, ROW_NUMBER() OVER (PARTITION BY UserID ORDER BY Days DESC, StreakStart) AS rn
      FROM Streaks) AS s
WHERE rn = 1;
GO
-- expect 2 rows: user 1 -> 2025-03-01, 3 days; user 2 -> 2025-03-03, 3 days

-- 4e. GAPS with LEAD: where the next login is more than 1 day away, the days in
--     between are missing.
WITH Nxt AS
(
    SELECT UserID, LoginDate,
           LEAD(LoginDate) OVER (PARTITION BY UserID ORDER BY LoginDate) AS NextLogin
    FROM dbo.L11_Logins
)
SELECT UserID,
       DATEADD(DAY, 1, LoginDate)   AS GapStart,
       DATEADD(DAY, -1, NextLogin)  AS GapEnd,
       DATEDIFF(DAY, LoginDate, NextLogin) - 1 AS MissingDays
FROM Nxt
WHERE DATEDIFF(DAY, LoginDate, NextLogin) > 1
ORDER BY UserID, GapStart;
GO
-- expect 3 rows: user 1: 03-04..03-04 (1), 03-07..03-09 (3); user 2: 03-02..03-02 (1)

-- 4f. MISSING IDs. Copy the order ids and knock three out.
SELECT OrderID INTO dbo.L11_OrderIds FROM dbo.Orders;
DELETE FROM dbo.L11_OrderIds WHERE OrderID IN (1005, 1010, 1011);
GO
-- Gap ranges with LEAD (works on every version):
WITH Nxt AS
(
    SELECT OrderID, LEAD(OrderID) OVER (ORDER BY OrderID) AS NextID
    FROM dbo.L11_OrderIds
)
SELECT OrderID + 1 AS MissingFrom, NextID - 1 AS MissingTo
FROM Nxt
WHERE NextID - OrderID > 1;
GO
-- expect 2 rows: 1005..1005, 1010..1011

-- Every single missing id (SQL Server 2022+: GENERATE_SERIES; older: a numbers CTE):
DECLARE @minId INT, @maxId INT;
SELECT @minId = MIN(OrderID), @maxId = MAX(OrderID) FROM dbo.L11_OrderIds;

SELECT s.value AS MissingOrderID
FROM GENERATE_SERIES(@minId, @maxId) AS s
WHERE NOT EXISTS (SELECT 1 FROM dbo.L11_OrderIds o WHERE o.OrderID = s.value);
GO
-- expect 3 rows: 1005, 1010, 1011


/* ============================================================
   5. PATTERN: RUNNING TOTAL THAT RESETS PER PARTITION
   ============================================================ */

-- 5a. Running spend per customer, in order of their orders. PARTITION BY = reset.
SELECT CustomerID, OrderID, OrderDate, TotalAmount,
       SUM(TotalAmount) OVER (PARTITION BY CustomerID ORDER BY OrderDate
                              ROWS UNBOUNDED PRECEDING) AS RunningSpend
FROM dbo.Orders
ORDER BY CustomerID, OrderDate;
GO
-- expect 19 rows; customer 1: 75000, 90000, 96000, 128000; customer 2: 10000, 16000, 46000, 48500


/* ============================================================
   6. PATTERN: MONTH-OVER-MONTH GROWTH WITH LAG
   ============================================================ */

-- 6a. Revenue per month, previous month, difference and growth %.
WITH Monthly AS
(
    SELECT MONTH(OrderDate) AS Mth, SUM(TotalAmount) AS Revenue
    FROM dbo.Orders
    GROUP BY MONTH(OrderDate)
),
WithPrev AS
(
    SELECT Mth, Revenue, LAG(Revenue) OVER (ORDER BY Mth) AS PrevRevenue
    FROM Monthly
)
SELECT Mth, Revenue, PrevRevenue,
       Revenue - PrevRevenue AS Diff,
       CAST((Revenue - PrevRevenue) * 100.0 / PrevRevenue AS DECIMAL(7,2)) AS GrowthPct
FROM WithPrev
ORDER BY Mth;
GO
-- expect 9 rows: Mth 1 NULLs, Mth 2 -37000 (-33.64), Mth 5 +34500 (460.00), Mth 6 +135500 (322.62), Mth 9 -76500 (-96.84)


/* ============================================================
   7. PATTERN: FIRST ORDER PER CUSTOMER
   ============================================================ */

-- 7a. ROW_NUMBER by date inside each customer, keep rn = 1.
WITH Numbered AS
(
    SELECT CustomerID, OrderID, OrderDate, TotalAmount,
           ROW_NUMBER() OVER (PARTITION BY CustomerID ORDER BY OrderDate, OrderID) AS rn
    FROM dbo.Orders
)
SELECT CustomerID, OrderID, OrderDate, TotalAmount
FROM Numbered
WHERE rn = 1
ORDER BY CustomerID;
GO
-- expect 7 rows: 1001, 1002, 1003, 1005, 1006, 1008, 1011

-- 7b. Same idea for "first AND last" in one row per customer (no GROUP BY needed for the ids).
WITH X AS
(
    SELECT DISTINCT CustomerID,
           FIRST_VALUE(OrderID) OVER (PARTITION BY CustomerID ORDER BY OrderDate) AS FirstOrder,
           FIRST_VALUE(OrderID) OVER (PARTITION BY CustomerID ORDER BY OrderDate DESC) AS LastOrder,
           COUNT(*) OVER (PARTITION BY CustomerID) AS Orders
    FROM dbo.Orders
)
SELECT * FROM X ORDER BY CustomerID;
GO
-- expect 7 rows; customer 1: 1001 / 1015 / 4


/* ============================================================
   8. PATTERN: CONSECUTIVE ORDERS THAT INCREASED IN AMOUNT
   ============================================================ */

-- 8a. Orders that were BIGGER than the same customer's previous order.
WITH WithPrev AS
(
    SELECT CustomerID, OrderID, OrderDate, TotalAmount,
           LAG(TotalAmount) OVER (PARTITION BY CustomerID ORDER BY OrderDate) AS PrevAmount
    FROM dbo.Orders
)
SELECT CustomerID, OrderID, PrevAmount, TotalAmount
FROM WithPrev
WHERE TotalAmount > PrevAmount           -- NULL PrevAmount (first order) drops out automatically
ORDER BY CustomerID, OrderDate;
GO
-- expect 5 rows: 1015 (6000 -> 32000), 1012 (6000 -> 30000), 1017 (1500 -> 4000),
--                1014 (8000 -> 150000), 1018 (12000 -> 75000)

-- 8b. Customers whose orders increased EVERY time (all steps up, at least 2 orders).
WITH WithPrev AS
(
    SELECT CustomerID, TotalAmount,
           LAG(TotalAmount) OVER (PARTITION BY CustomerID ORDER BY OrderDate) AS PrevAmount
    FROM dbo.Orders
)
SELECT CustomerID, COUNT(*) AS Orders
FROM WithPrev
GROUP BY CustomerID
HAVING COUNT(*) >= 2
   AND SUM(CASE WHEN TotalAmount <= PrevAmount THEN 1 ELSE 0 END) = 0;
GO
-- expect 2 rows: customer 5 (8000 -> 150000), customer 7 (12000 -> 75000)


/* ============================================================
   9. PATTERN: ABOVE DEPARTMENT AVERAGE - WINDOW vs CORRELATED
   ============================================================ */

-- 9a. Window version: one pass over Employees, the average travels with each row.
WITH WithAvg AS
(
    SELECT EmployeeName, DepartmentID, Salary,
           AVG(Salary) OVER (PARTITION BY DepartmentID) AS DeptAvg
    FROM dbo.Employees
    WHERE DepartmentID IS NOT NULL
)
SELECT EmployeeName, DepartmentID, Salary, DeptAvg
FROM WithAvg
WHERE Salary > DeptAvg
ORDER BY DepartmentID;
GO
-- expect 4 rows: Rahul, Priya, Sneha, Karan

-- 9b. Correlated subquery version (Level 09): logically re-computed for every row.
SELECT e.EmployeeName, e.DepartmentID, e.Salary
FROM dbo.Employees e
WHERE e.Salary > (SELECT AVG(x.Salary) FROM dbo.Employees x WHERE x.DepartmentID = e.DepartmentID)
ORDER BY e.DepartmentID;
GO
-- expect the same 4 rows
-- Interview answer: both are correct; the window version reads the table once and
-- can show the average next to the row, the correlated one is shorter for a pure filter.


/* ============================================================
   10. CLEANUP
   ============================================================ */
DROP TABLE IF EXISTS dbo.L11_DupCustomers;
DROP TABLE IF EXISTS dbo.L11_Logins;
DROP TABLE IF EXISTS dbo.L11_OrderIds;
GO
/* DONE. Next: 04_Practice_Pivot_Unpivot.sql */
