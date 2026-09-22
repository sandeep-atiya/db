/* ============================================================
   LEVEL 11 - CTE AND WINDOW FUNCTIONS  |  01_Practice_CTE.sql
   ------------------------------------------------------------
   Topics : WITH syntax and why (readability, reuse), multiple CTEs,
            CTE referencing a previous CTE, CTE vs subquery vs
            derived table vs temp table (scope, not materialised),
            the "previous statement must be terminated with a
            semicolon" error, CTE in INSERT / UPDATE / DELETE
            (on a copy dbo.L11_Products), RECURSIVE CTE: anatomy,
            org chart with Level + Path, reverse (managers above),
            number series, date series, MAXRECURSION and the
            default-100 error, infinite recursion guard.

   HOW TO PRACTICE: run block by block, predict the output first.
   Creates dbo.L11_Products, dbo.L11_Cycle, #L11_DeptAvg; all are
   dropped in CLEANUP. Base tables are never changed (one demo
   updates Employees INSIDE a transaction and rolls it back).
   ============================================================ */

USE SQLPractice;
GO
DROP TABLE IF EXISTS dbo.L11_Products;
DROP TABLE IF EXISTS dbo.L11_Cycle;
DROP TABLE IF EXISTS #L11_DeptAvg;
GO


/* ============================================================
   1. WITH SYNTAX - A NAMED, TEMPORARY RESULT FOR ONE STATEMENT
   ============================================================
   WITH Name (optional column list) AS ( SELECT ... )
   SELECT ... FROM Name;
   The CTE (Common Table Expression) exists ONLY for the statement
   that follows it. Think "a derived table with a name on top".
   ============================================================ */

-- 1a. Department averages as a CTE ...
WITH DeptAvg AS
(
    SELECT DepartmentID, AVG(Salary) AS AvgSalary
    FROM dbo.Employees
    GROUP BY DepartmentID
)
SELECT DepartmentID, AvgSalary
FROM DeptAvg
ORDER BY DepartmentID;
GO
-- expect 6 rows: NULL 48000, 1 71666.67, 2 64000, 3 60000, 4 81000, 5 64000

-- 1b. ... is the same as a derived table, just read top-down instead of inside-out.
SELECT da.DepartmentID, da.AvgSalary
FROM (SELECT DepartmentID, AVG(Salary) AS AvgSalary
      FROM dbo.Employees
      GROUP BY DepartmentID) AS da
ORDER BY da.DepartmentID;
GO
-- expect the same 6 rows

-- 1c. WHY a CTE: you can use the name MORE THAN ONCE in the statement.
--     Compare every department average with the IT average (DepartmentID 1).
WITH DeptAvg AS
(
    SELECT DepartmentID, AVG(Salary) AS AvgSalary
    FROM dbo.Employees
    GROUP BY DepartmentID
)
SELECT a.DepartmentID, a.AvgSalary, a.AvgSalary - it.AvgSalary AS VsIT
FROM DeptAvg a
CROSS JOIN DeptAvg it
WHERE it.DepartmentID = 1
ORDER BY a.DepartmentID;
GO
-- expect 6 rows; Finance VsIT = 9333.33, Sales VsIT = -7666.67


/* ============================================================
   2. MULTIPLE CTEs, AND A CTE THAT USES A PREVIOUS CTE
   ============================================================
   WITH A AS (...), B AS (... FROM A ...), C AS (... FROM B ...)
   One WITH, comma separated, each can reference the ones ABOVE it.
   ============================================================ */

-- 2a. Two CTEs: department averages, then employees above their own average.
WITH DeptAvg AS
(
    SELECT DepartmentID, AVG(Salary) AS AvgSalary
    FROM dbo.Employees
    GROUP BY DepartmentID
),
AboveAvg AS
(
    SELECT e.EmployeeName, e.DepartmentID, e.Salary, da.AvgSalary
    FROM dbo.Employees e
    JOIN DeptAvg da ON da.DepartmentID = e.DepartmentID     -- uses the first CTE
    WHERE e.Salary > da.AvgSalary
)
SELECT EmployeeName, DepartmentID, Salary, AvgSalary
FROM AboveAvg
ORDER BY DepartmentID;
GO
-- expect 4 rows: Rahul, Priya, Sneha, Karan

-- 2b. Three steps: per-customer totals -> average of those -> customers above it.
WITH CustTotals AS
(
    SELECT CustomerID, SUM(TotalAmount) AS Spent
    FROM dbo.Orders
    GROUP BY CustomerID
),
AvgSpent AS
(
    SELECT AVG(Spent) AS AvgSpent FROM CustTotals
)
SELECT c.CustomerName, ct.Spent, a.AvgSpent
FROM CustTotals ct
JOIN dbo.Customers c ON c.CustomerID = ct.CustomerID
CROSS JOIN AvgSpent a
WHERE ct.Spent > a.AvgSpent
ORDER BY ct.Spent DESC;
GO
-- expect 3 rows: Esha 158000, Aarav 128000, Farhan 88500  (AvgSpent = 88285.714285)


/* ============================================================
   3. CTE vs SUBQUERY vs DERIVED TABLE vs TEMP TABLE
   ============================================================ */

-- 3a. SCOPE: a CTE lives for ONE statement. The next statement cannot see it.
--     (Name-resolution errors escape same-batch TRY/CATCH, so run it as a string.)
BEGIN TRY
    EXEC sp_executesql N'WITH DeptAvg AS (SELECT DepartmentID, AVG(Salary) AS AvgSalary
                                          FROM dbo.Employees GROUP BY DepartmentID)
                         SELECT COUNT(*) AS FirstUse FROM DeptAvg;
                         SELECT COUNT(*) AS SecondUse FROM DeptAvg;';   -- <- gone already
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();   -- Invalid object name 'DeptAvg'.
END CATCH
GO

-- 3b. NOT MATERIALISED: a CTE is inlined like a view. Reference it twice and
--     it is EVALUATED twice. NEWID() proves it: two references, two different values.
WITH R AS (SELECT NEWID() AS g)
SELECT a.g AS FirstRef, b.g AS SecondRef,
       CASE WHEN a.g = b.g THEN 'same' ELSE 'different' END AS Evaluated
FROM R a CROSS JOIN R b;
GO
-- expect 1 row: different   (an expensive CTE used 3 times costs 3 times!)

-- 3c. TEMP TABLE: really stored (in tempdb), lives for the whole session,
--     can be used by MANY statements, can have indexes and statistics.
SELECT DepartmentID, AVG(Salary) AS AvgSalary
INTO #L11_DeptAvg
FROM dbo.Employees
GROUP BY DepartmentID;
GO
SELECT COUNT(*) AS Statement1 FROM #L11_DeptAvg;
GO
SELECT COUNT(*) AS Statement2 FROM #L11_DeptAvg;    -- still there after GO
GO
-- expect 6 and 6

/* 3d. WHEN TO USE WHICH
   ------------------------------------------------------------------------
   Subquery      : one value / one list inside WHERE or SELECT. Short.
   Derived table : table-shaped result used once, inside FROM. Needs alias.
   CTE           : same as derived table but named, readable top-down,
                   reusable inside the SAME statement, and the ONLY way to recurse.
   Temp table    : result needed by several statements, or big/expensive and
                   referenced many times, or you want an index on it.
   Table variable: small row sets in procedures (no stats, few rows).
   ------------------------------------------------------------------------ */


/* ============================================================
   4. THE SEMICOLON ERROR
   ============================================================
   WITH is also used by table hints (WITH (NOLOCK)), so the parser
   needs the PREVIOUS statement to end with ; to know a CTE starts.
   ============================================================ */

-- 4a. Previous statement without ; -> the famous message.
BEGIN TRY
    EXEC sp_executesql N'PRINT ''Report''
                         WITH DeptAvg AS (SELECT DepartmentID, AVG(Salary) AS AvgSalary
                                          FROM dbo.Employees GROUP BY DepartmentID)
                         SELECT * FROM DeptAvg;';
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
    -- Incorrect syntax near the keyword 'with'. If this statement is a common
    -- table expression ... the previous statement must be terminated with a semicolon.
END CATCH
GO

-- 4b. Fix: terminate the previous statement. (Old habit: write ";WITH" - it works,
--     but the clean fix is to end EVERY statement with a semicolon.)
PRINT 'Report';
WITH DeptAvg AS (SELECT DepartmentID, AVG(Salary) AS AvgSalary
                 FROM dbo.Employees GROUP BY DepartmentID)
SELECT COUNT(*) AS DeptCount FROM DeptAvg;
GO
-- expect 6


/* ============================================================
   5. CTE IN INSERT / UPDATE / DELETE  (on the copy dbo.L11_Products)
   ============================================================
   A CTE over ONE base table is updatable: UPDATE/DELETE the CTE
   name and the base table changes. Great for "select first, check
   the rows, then turn the SELECT into a DELETE" workflows.
   ============================================================ */

-- 5a. Make the copy.
SELECT * INTO dbo.L11_Products FROM dbo.Products;
GO

-- 5b. UPDATE through a CTE: 20% off every product that was never sold.
WITH NeverSold AS
(
    SELECT p.ProductID, p.ProductName, p.Price
    FROM dbo.L11_Products p
    WHERE NOT EXISTS (SELECT 1 FROM dbo.OrderDetails od WHERE od.ProductID = p.ProductID)
)
UPDATE NeverSold SET Price = Price * 0.80;
GO
-- expect (1 row affected)
SELECT ProductName, Price FROM dbo.L11_Products WHERE ProductID = 11;
GO
-- expect Webcam 3600.00

-- 5c. DELETE through a CTE: remove products with stock below 10.
WITH LowStock AS
(
    SELECT * FROM dbo.L11_Products WHERE Stock < 10
)
DELETE FROM LowStock;
GO
-- expect (2 rows affected): Headphones (0), Bookshelf (5)
SELECT COUNT(*) AS Remaining FROM dbo.L11_Products;
GO
-- expect 9

-- 5d. INSERT ... SELECT from a CTE: add "bulk pack" versions of the stationery items.
WITH Src AS
(
    SELECT ProductID + 100 AS ProductID, ProductName + ' (bulk)' AS ProductName,
           Category, Price * 0.90 AS Price, Stock
    FROM dbo.L11_Products
    WHERE Category = 'Stationery'
)
INSERT INTO dbo.L11_Products (ProductID, ProductName, Category, Price, Stock)
SELECT ProductID, ProductName, Category, Price, Stock FROM Src;
GO
-- expect (2 rows affected)
SELECT ProductID, ProductName, Price FROM dbo.L11_Products WHERE ProductID > 100;
GO
-- expect 107 Notebook (bulk) 45.00, 108 Pen (bulk) 9.00


/* ============================================================
   6. RECURSIVE CTE
   ============================================================
   ANATOMY
     WITH R AS
     (
         <anchor member>          -- runs ONCE, gives the starting rows
         UNION ALL
         <recursive member>       -- references R, runs again and again
                                  -- on the rows produced by the previous round
                                  -- until a round produces 0 rows
     )
     SELECT ... FROM R;
   Rules: UNION ALL (not UNION), same column count and TYPES in both
   members, no aggregates / TOP / OUTER JOIN to R in the recursive member.
   ============================================================ */

-- 6a. Number series 1..100 (the "hello world" of recursion).
WITH Numbers AS
(
    SELECT 1 AS n                              -- anchor
    UNION ALL
    SELECT n + 1 FROM Numbers WHERE n < 100    -- recursive member + stop condition
)
SELECT COUNT(*) AS HowMany, MIN(n) AS FirstN, MAX(n) AS LastN, SUM(n) AS Total
FROM Numbers;
GO
-- expect 100, 1, 100, 5050
-- SQL Server 2022+: SELECT value FROM GENERATE_SERIES(1, 100);  does the same, faster.

-- 6b. Date series: every day of September 2025, then "days with no order".
WITH Days AS
(
    SELECT CAST('20250901' AS DATE) AS d
    UNION ALL
    SELECT DATEADD(DAY, 1, d) FROM Days WHERE d < EOMONTH('20250901')
)
SELECT COUNT(DISTINCT d.d) AS DaysInMonth,
       COUNT(DISTINCT CASE WHEN o.OrderID IS NULL THEN d.d END) AS DaysWithoutOrders
FROM Days d
LEFT JOIN dbo.Orders o ON o.OrderDate = d.d;
GO
-- expect 30, 29   (only 2025-09-05 has an order)
-- (a calendar CTE + LEFT JOIN is THE way to report days/months that have no data)

-- 6c. ORG CHART from Employees.ManagerID with Level and Path.
--     Anchor = people with no manager (the heads). Each round adds their reports.
--     Path must have the SAME type in both members -> CAST both to VARCHAR(500).
WITH Org AS
(
    SELECT EmployeeID, EmployeeName, ManagerID,
           1 AS Lvl,
           CAST(EmployeeName AS VARCHAR(500)) AS Path
    FROM dbo.Employees
    WHERE ManagerID IS NULL
    UNION ALL
    SELECT e.EmployeeID, e.EmployeeName, e.ManagerID,
           o.Lvl + 1,
           CAST(o.Path + ' > ' + e.EmployeeName AS VARCHAR(500))
    FROM dbo.Employees e
    JOIN Org o ON o.EmployeeID = e.ManagerID          -- child joins to the previous round
)
SELECT Lvl, EmployeeID, EmployeeName, ManagerID, Path
FROM Org
ORDER BY Path;
GO
-- expect 12 rows: 6 heads at Lvl 1 (Anjali, Karan, Priya, Rahul, Ravi, Sneha),
--                 6 reports at Lvl 2, e.g. "Rahul > Amit", "Sneha > Deepak"

-- 6d. The real data is only 2 levels deep. Inside a transaction, make Pooja report
--     to Amit (instead of Rahul) to get a 3-level chain, look, then ROLLBACK.
BEGIN TRAN;
UPDATE dbo.Employees SET ManagerID = 102 WHERE EmployeeID = 108;    -- Pooja -> Amit

WITH Org AS
(
    SELECT EmployeeID, EmployeeName, ManagerID, 1 AS Lvl, CAST(EmployeeName AS VARCHAR(500)) AS Path
    FROM dbo.Employees WHERE ManagerID IS NULL
    UNION ALL
    SELECT e.EmployeeID, e.EmployeeName, e.ManagerID, o.Lvl + 1, CAST(o.Path + ' > ' + e.EmployeeName AS VARCHAR(500))
    FROM dbo.Employees e JOIN Org o ON o.EmployeeID = e.ManagerID
)
SELECT Lvl, EmployeeName, Path FROM Org WHERE Path LIKE 'Rahul%' ORDER BY Path;
-- expect 3 rows: Rahul (1), Rahul > Amit (2), Rahul > Amit > Pooja (3)

-- 6e. REVERSE direction: all managers ABOVE an employee (walk UP the chain).
--     Anchor = the employee; each round joins to the manager of the previous row.
WITH Up AS
(
    SELECT EmployeeID, EmployeeName, ManagerID, 0 AS StepsUp
    FROM dbo.Employees WHERE EmployeeID = 108                          -- Pooja
    UNION ALL
    SELECT m.EmployeeID, m.EmployeeName, m.ManagerID, u.StepsUp + 1
    FROM dbo.Employees m
    JOIN Up u ON u.ManagerID = m.EmployeeID                            -- manager of previous row
)
SELECT StepsUp, EmployeeName FROM Up WHERE StepsUp > 0 ORDER BY StepsUp;
-- expect 2 rows: 1 Amit, 2 Rahul

ROLLBACK TRAN;
GO
SELECT EmployeeName, ManagerID FROM dbo.Employees WHERE EmployeeID = 108;
GO
-- expect Pooja 101  (back to normal)

-- 6f. MAXRECURSION: the default limit is 100 rounds. 1..200 needs 199 rounds -> error.
BEGIN TRY
    WITH Numbers AS (SELECT 1 AS n UNION ALL SELECT n + 1 FROM Numbers WHERE n < 200)
    SELECT COUNT(*) AS HowMany FROM Numbers;
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
    -- The statement terminated. The maximum recursion 100 has been exhausted ...
END CATCH
GO
-- Raise the limit for THIS statement with a query hint (0 = no limit - dangerous).
WITH Numbers AS (SELECT 1 AS n UNION ALL SELECT n + 1 FROM Numbers WHERE n < 200)
SELECT COUNT(*) AS HowMany FROM Numbers
OPTION (MAXRECURSION 500);
GO
-- expect 200

-- 6g. INFINITE RECURSION GUARD. Bad data with a cycle: 1 -> 3 -> 2 -> 1 -> ...
CREATE TABLE dbo.L11_Cycle (NodeID INT, ParentID INT);
INSERT INTO dbo.L11_Cycle VALUES (1, 3), (2, 1), (3, 2);
GO
-- Without a guard the CTE walks the loop forever and only MAXRECURSION stops it.
BEGIN TRY
    WITH Walk AS
    (
        SELECT NodeID, ParentID, 1 AS Lvl FROM dbo.L11_Cycle WHERE NodeID = 1
        UNION ALL
        SELECT c.NodeID, c.ParentID, w.Lvl + 1
        FROM dbo.L11_Cycle c JOIN Walk w ON c.NodeID = w.ParentID
    )
    SELECT COUNT(*) AS Visited FROM Walk;
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO
-- Guard: carry the Path and refuse to visit a node that is already in it.
WITH Walk AS
(
    SELECT NodeID, ParentID, 1 AS Lvl, CAST('>1>' AS VARCHAR(500)) AS Path
    FROM dbo.L11_Cycle WHERE NodeID = 1
    UNION ALL
    SELECT c.NodeID, c.ParentID, w.Lvl + 1,
           CAST(w.Path + CAST(c.NodeID AS VARCHAR(10)) + '>' AS VARCHAR(500))
    FROM dbo.L11_Cycle c
    JOIN Walk w ON c.NodeID = w.ParentID
    WHERE CHARINDEX('>' + CAST(c.NodeID AS VARCHAR(10)) + '>', w.Path) = 0   -- not seen yet
)
SELECT NodeID, ParentID, Lvl, Path FROM Walk ORDER BY Lvl;
GO
-- expect 3 rows: 1, 3, 2 - then it stops because 1 is already in the path
-- Simpler guard for known-depth trees: WHERE w.Lvl < 20  (plus MAXRECURSION as a backstop).


/* ============================================================
   7. CLEANUP
   ============================================================ */
DROP TABLE IF EXISTS dbo.L11_Products;
DROP TABLE IF EXISTS dbo.L11_Cycle;
DROP TABLE IF EXISTS #L11_DeptAvg;
GO
/* DONE. Next: 02_Practice_Window_Functions.sql */
