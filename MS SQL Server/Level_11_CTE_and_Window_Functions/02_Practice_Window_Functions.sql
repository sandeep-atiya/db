/* ============================================================
   LEVEL 11 - CTE AND WINDOW FUNCTIONS  |  02_Practice_Window_Functions.sql
   ------------------------------------------------------------
   Topics : OVER() (aggregate without collapsing rows), PARTITION BY,
            ORDER BY inside OVER, ROW_NUMBER / RANK / DENSE_RANK / NTILE,
            LAG / LEAD (offset, default), FIRST_VALUE / LAST_VALUE
            (the default-frame trap), SUM/AVG/COUNT/MIN/MAX OVER,
            running total (ROWS vs RANGE), moving average, percent of
            total, cumulative percent, PERCENT_RANK / CUME_DIST,
            "window functions cannot be used in WHERE", WINDOW clause.

   HOW TO PRACTICE: run block by block, predict the output first.
   This file only READS the base tables (nothing to clean up).
   Salaries, highest first: Sneha 90000, Rahul 85000, Priya 75000,
   Deepak 72000, Karan 70000, Amit 65000, Pooja 65000, Vikram 62000,
   Ravi 60000, Meera 58000, Neha 55000, Anjali 48000.
   ============================================================ */

USE SQLPractice;
GO


/* ============================================================
   1. OVER() - AN AGGREGATE THAT DOES NOT COLLAPSE THE ROWS
   ============================================================
   GROUP BY gives ONE row per group and loses the detail.
   <aggregate>() OVER (...) computes the same number but keeps EVERY
   row, and puts the number next to it. The OVER() part is the
   "window" = the set of rows the function looks at.
   ============================================================ */

-- 1a. GROUP BY: 6 rows, no names.
SELECT DepartmentID, AVG(Salary) AS AvgSalary
FROM dbo.Employees
GROUP BY DepartmentID;
GO
-- expect 6 rows

-- 1b. OVER (): 12 rows, every employee next to the company average and total.
SELECT EmployeeName, Salary,
       AVG(Salary) OVER () AS CompanyAvg,
       SUM(Salary) OVER () AS CompanyTotal,
       CAST(Salary * 100.0 / SUM(Salary) OVER () AS DECIMAL(5,2)) AS PctOfPayroll
FROM dbo.Employees
ORDER BY Salary DESC;
GO
-- expect 12 rows; CompanyAvg 67083.33, CompanyTotal 805000, Sneha 11.18 %


/* ============================================================
   2. PARTITION BY - "GROUP BY inside the window"
   ============================================================ */

-- 2a. Department average next to each employee, and the gap.
SELECT EmployeeName, DepartmentID, Salary,
       AVG(Salary) OVER (PARTITION BY DepartmentID) AS DeptAvg,
       Salary - AVG(Salary) OVER (PARTITION BY DepartmentID) AS VsDeptAvg
FROM dbo.Employees
ORDER BY DepartmentID, Salary DESC;
GO
-- expect 12 rows; Rahul VsDeptAvg 13333.33, Amit -6666.67
-- NOTE: Anjali (NULL dept) is a partition of her own -> DeptAvg 48000, gap 0.
--       A correlated subquery (Level 09) gave NULL there. Different tools, different NULL rules.

-- 2b. Several partition aggregates at once.
SELECT EmployeeName, DepartmentID, Salary,
       COUNT(*)    OVER (PARTITION BY DepartmentID) AS DeptHeadcount,
       MAX(Salary) OVER (PARTITION BY DepartmentID) AS DeptMax,
       MIN(Salary) OVER (PARTITION BY DepartmentID) AS DeptMin,
       SUM(Salary) OVER (PARTITION BY DepartmentID) AS DeptPayroll
FROM dbo.Employees
ORDER BY DepartmentID, Salary DESC;
GO
-- expect 12 rows; IT: headcount 3, max 85000, min 65000, payroll 215000


/* ============================================================
   3. ORDER BY INSIDE OVER -> RANKING FUNCTIONS
   ============================================================
   ROW_NUMBER : 1,2,3,4...  always unique, ties broken arbitrarily
   RANK       : 1,2,2,4...  ties share a rank, then a GAP
   DENSE_RANK : 1,2,2,3...  ties share a rank, NO gap
   NTILE(n)   : splits the rows into n equal buckets
   ============================================================ */

-- 3a. All three side by side. Amit and Pooja both earn 65000 -> watch positions 6 and 7.
--     ROW_NUMBER gets EmployeeID as a tie-breaker so its result is repeatable.
SELECT EmployeeName, Salary,
       ROW_NUMBER() OVER (ORDER BY Salary DESC, EmployeeID) AS RowNum,
       RANK()       OVER (ORDER BY Salary DESC)             AS Rnk,
       DENSE_RANK() OVER (ORDER BY Salary DESC)             AS DenseRnk
FROM dbo.Employees
ORDER BY Salary DESC, EmployeeID;
GO
-- expect: Amit  65000 -> 6, 6, 6
--         Pooja 65000 -> 7, 6, 6
--         Vikram 62000 -> 8, 8, 7   (RANK skips 7, DENSE_RANK does not)
--         Anjali 48000 -> 12, 12, 11

-- 3b. NTILE(4): 12 rows into 4 salary bands of 3.
SELECT EmployeeName, Salary,
       NTILE(4) OVER (ORDER BY Salary DESC, EmployeeID) AS SalaryBand
FROM dbo.Employees
ORDER BY Salary DESC, EmployeeID;
GO
-- expect band 1 = Sneha, Rahul, Priya ... band 4 = Meera, Neha, Anjali
-- (if rows do not divide evenly, the FIRST buckets get the extra row)

-- 3c. Ranking WITHIN a partition: position inside the department.
SELECT DepartmentID, EmployeeName, Salary,
       DENSE_RANK() OVER (PARTITION BY DepartmentID ORDER BY Salary DESC) AS RankInDept
FROM dbo.Employees
ORDER BY DepartmentID, RankInDept;
GO
-- expect 12 rows; IT: Rahul 1, Amit 2, Pooja 2; Sales: Priya 1, Vikram 2, Neha 3


/* ============================================================
   4. LAG / LEAD - LOOK AT THE PREVIOUS / NEXT ROW
   ============================================================
   LAG(col, offset, default)  -> value from N rows BEFORE (default NULL)
   LEAD(col, offset, default) -> value from N rows AFTER
   Needs ORDER BY inside OVER; PARTITION BY restarts per group.
   ============================================================ */

-- 4a. Previous order date per customer, and days since it.
SELECT CustomerID, OrderID, OrderDate,
       LAG(OrderDate) OVER (PARTITION BY CustomerID ORDER BY OrderDate) AS PrevOrderDate,
       DATEDIFF(DAY, LAG(OrderDate) OVER (PARTITION BY CustomerID ORDER BY OrderDate), OrderDate) AS DaysSincePrev
FROM dbo.Orders
ORDER BY CustomerID, OrderDate;
GO
-- expect 19 rows; customer 1: NULL, 29, 58, 96;  customer 2: NULL, 57, 72, 107

-- 4b. Offset and default: 2 orders back, and 0 instead of NULL for the first row.
--     LEAD gives the NEXT order (NULL on the last one).
SELECT CustomerID, OrderID, TotalAmount,
       LAG(TotalAmount, 1, 0)  OVER (PARTITION BY CustomerID ORDER BY OrderDate) AS PrevAmount,
       LAG(TotalAmount, 2, 0)  OVER (PARTITION BY CustomerID ORDER BY OrderDate) AS TwoBackAmount,
       LEAD(OrderDate)         OVER (PARTITION BY CustomerID ORDER BY OrderDate) AS NextOrderDate
FROM dbo.Orders
WHERE CustomerID IN (1, 2)
ORDER BY CustomerID, OrderDate;
GO
-- expect 8 rows; customer 1 row 3 (1009): PrevAmount 15000, TwoBackAmount 75000, NextOrderDate 2025-07-07


/* ============================================================
   5. FIRST_VALUE / LAST_VALUE  (and the default-frame trap)
   ============================================================ */

-- 5a. FIRST_VALUE works as expected: the top earner of each department on every row.
--     LAST_VALUE looks WRONG: with ORDER BY the default frame is
--     "RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW", so the window ENDS at
--     the current row and LAST_VALUE is just ... the current row (or its peer).
SELECT DepartmentID, EmployeeName, Salary,
       FIRST_VALUE(EmployeeName) OVER (PARTITION BY DepartmentID ORDER BY Salary DESC) AS TopEarner,
       LAST_VALUE(EmployeeName)  OVER (PARTITION BY DepartmentID ORDER BY Salary DESC) AS WrongLowest
FROM dbo.Employees
ORDER BY DepartmentID, Salary DESC;
GO
-- expect 12 rows; Sales: Priya -> WrongLowest Priya, Vikram -> Vikram, Neha -> Neha
-- IT: Amit -> Pooja and Pooja -> Pooja (65000 peers are inside a RANGE frame together)

-- 5b. FIX: tell the frame to run to the END of the partition.
SELECT DepartmentID, EmployeeName, Salary,
       FIRST_VALUE(EmployeeName) OVER (PARTITION BY DepartmentID ORDER BY Salary DESC) AS TopEarner,
       LAST_VALUE(EmployeeName)  OVER (PARTITION BY DepartmentID ORDER BY Salary DESC
                                       ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS LowestEarner
FROM dbo.Employees
ORDER BY DepartmentID, Salary DESC;
GO
-- expect Sales: LowestEarner = Neha on all 3 rows; IT = Pooja; Finance = Deepak
-- (alternative: FIRST_VALUE with ORDER BY Salary ASC - no frame worries)


/* ============================================================
   6. SUM / AVG / COUNT / MIN / MAX OVER  - summary in one query
   ============================================================ */

-- 6a. Per-order share of the customer's total, plus customer stats on every row.
SELECT CustomerID, OrderID, TotalAmount,
       SUM(TotalAmount)   OVER (PARTITION BY CustomerID) AS CustTotal,
       AVG(TotalAmount)   OVER (PARTITION BY CustomerID) AS CustAvg,
       COUNT(*)           OVER (PARTITION BY CustomerID) AS CustOrders,
       MIN(TotalAmount)   OVER (PARTITION BY CustomerID) AS CustMin,
       MAX(TotalAmount)   OVER (PARTITION BY CustomerID) AS CustMax
FROM dbo.Orders
WHERE CustomerID IN (1, 5)
ORDER BY CustomerID, OrderDate;
GO
-- expect 6 rows; customer 1: total 128000, avg 32000, 4 orders, min 6000, max 75000


/* ============================================================
   7. RUNNING TOTAL  (ORDER BY inside an aggregate's OVER)
   ============================================================
   Adding ORDER BY to SUM() OVER turns it into a running total:
   "sum of all rows from the start of the partition up to this row".
   ============================================================ */

-- 7a. Running revenue by month.
WITH Monthly AS
(
    SELECT MONTH(OrderDate) AS Mth, SUM(TotalAmount) AS Revenue
    FROM dbo.Orders
    GROUP BY MONTH(OrderDate)
)
SELECT Mth, Revenue,
       SUM(Revenue) OVER (ORDER BY Mth ROWS UNBOUNDED PRECEDING) AS RunningTotal
FROM Monthly
ORDER BY Mth;
GO
-- expect 9 rows: 110000, 183000, 267500, 275000, 317000, 494500, 536500, 615500, 618000

-- 7b. ROWS vs RANGE. The default frame with ORDER BY is RANGE, and RANGE treats
--     rows with the SAME ORDER BY value as one block ("peers"): they all get the
--     total INCLUDING each other. Amit and Pooja (both 65000) show the difference.
SELECT EmployeeName, Salary,
       SUM(Salary) OVER (ORDER BY Salary)                        AS Range_Default,   -- peers share
       SUM(Salary) OVER (ORDER BY Salary ROWS UNBOUNDED PRECEDING) AS Rows_OneByOne  -- row by row
FROM dbo.Employees
ORDER BY Salary, EmployeeID;
GO
-- expect Amit and Pooja: Range_Default = 413000 on BOTH rows;
--        Rows_OneByOne = 348000 on one and 413000 on the other (which one is arbitrary -
--        add a unique tie-breaker like EmployeeID to the ORDER BY to make ROWS repeatable).
-- Rule: for running totals ALWAYS write ROWS UNBOUNDED PRECEDING - correct AND faster.


/* ============================================================
   8. MOVING AVERAGE  (a sliding frame)
   ============================================================ */

-- 8a. 3-month moving average: this month and the 2 before it.
WITH Monthly AS
(
    SELECT MONTH(OrderDate) AS Mth, SUM(TotalAmount) AS Revenue
    FROM dbo.Orders
    GROUP BY MONTH(OrderDate)
)
SELECT Mth, Revenue,
       AVG(Revenue) OVER (ORDER BY Mth ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS MovingAvg3,
       COUNT(*)     OVER (ORDER BY Mth ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS RowsInFrame
FROM Monthly
ORDER BY Mth;
GO
-- expect Mth 1: 110000 (1 row), Mth 2: 91500 (2 rows), Mth 3: 89166.67, Mth 6: 75666.67, Mth 9: 41166.67


/* ============================================================
   9. PERCENT OF TOTAL AND CUMULATIVE PERCENT
   ============================================================ */

-- 9a. Each department's share of the payroll. A window function can sit ON TOP of
--     a GROUP BY aggregate: SUM(SUM(Salary)) OVER () = total of the group totals.
SELECT DepartmentID,
       SUM(Salary) AS DeptPayroll,
       CAST(SUM(Salary) * 100.0 / SUM(SUM(Salary)) OVER () AS DECIMAL(5,2)) AS PctOfTotal
FROM dbo.Employees
GROUP BY DepartmentID
ORDER BY DeptPayroll DESC;
GO
-- expect 6 rows: IT 215000 26.71, Sales 192000 23.85, Finance 162000 20.12,
--                Marketing 128000 15.90, HR 60000 7.45, NULL 48000 5.96

-- 9b. Cumulative percent of revenue by month (running total / grand total).
WITH Monthly AS
(
    SELECT MONTH(OrderDate) AS Mth, SUM(TotalAmount) AS Revenue
    FROM dbo.Orders
    GROUP BY MONTH(OrderDate)
)
SELECT Mth, Revenue,
       SUM(Revenue) OVER (ORDER BY Mth ROWS UNBOUNDED PRECEDING) AS RunningTotal,
       CAST(SUM(Revenue) OVER (ORDER BY Mth ROWS UNBOUNDED PRECEDING) * 100.0
            / SUM(Revenue) OVER () AS DECIMAL(5,2)) AS CumulativePct
FROM Monthly
ORDER BY Mth;
GO
-- expect Mth 1: 17.80, Mth 3: 43.28, Mth 6: 80.02, Mth 9: 100.00


/* ============================================================
   10. PERCENT_RANK / CUME_DIST  (brief - "where do I stand?")
   ============================================================
   PERCENT_RANK = (RANK - 1) / (rows - 1)   -> 0 for the first, 1 for the last
   CUME_DIST    = rows with value <= mine / rows  -> fraction at or below me
   ============================================================ */
SELECT EmployeeName, Salary,
       CAST(PERCENT_RANK() OVER (ORDER BY Salary) AS DECIMAL(5,3)) AS PctRank,
       CAST(CUME_DIST()    OVER (ORDER BY Salary) AS DECIMAL(5,3)) AS CumeDist
FROM dbo.Employees
ORDER BY Salary;
GO
-- expect Anjali 0.000 / 0.083, Amit & Pooja 0.455 / 0.583, Sneha 1.000 / 1.000


/* ============================================================
   11. WINDOW FUNCTIONS CANNOT BE USED IN WHERE (or HAVING)
   ============================================================
   They are computed AFTER WHERE / GROUP BY / HAVING, so the WHERE
   clause cannot see them. Wrap the query in a CTE, filter outside.
   ============================================================ */

-- 11a. The error (compile-time, so run as a string).
BEGIN TRY
    EXEC sp_executesql N'SELECT EmployeeName, Salary
                         FROM dbo.Employees
                         WHERE ROW_NUMBER() OVER (ORDER BY Salary DESC) <= 3;';
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();   -- Windowed functions can only appear in the SELECT or ORDER BY clauses.
END CATCH
GO

-- 11b. The fix: CTE (or derived table), then filter on the computed column.
WITH Ranked AS
(
    SELECT EmployeeName, Salary,
           ROW_NUMBER() OVER (ORDER BY Salary DESC) AS RowNum
    FROM dbo.Employees
)
SELECT EmployeeName, Salary
FROM Ranked
WHERE RowNum <= 3
ORDER BY RowNum;
GO
-- expect 3 rows: Sneha, Rahul, Priya


/* ============================================================
   12. THE WINDOW CLAUSE  (SQL Server 2022+, compat level 160+)
   ============================================================
   Name a window once, reuse it in many functions. Less repetition,
   fewer copy-paste mistakes. A named window can still be extended
   with a frame: OVER (w ROWS ...).
   ============================================================ */
SELECT EmployeeName, DepartmentID, Salary,
       ROW_NUMBER() OVER w AS RowNum,
       RANK()       OVER w AS Rnk,
       DENSE_RANK() OVER w AS DenseRnk,
       SUM(Salary)  OVER (w ROWS UNBOUNDED PRECEDING) AS RunningDeptPayroll
FROM dbo.Employees
WINDOW w AS (PARTITION BY DepartmentID ORDER BY Salary DESC, EmployeeID)
ORDER BY DepartmentID, Salary DESC, EmployeeID;
GO
-- expect 12 rows; IT: Rahul 1/1/1 85000, Amit 2/2/2 150000, Pooja 3/3/3 215000
-- (EmployeeID inside w breaks the 65000 tie for EVERY function - leave it out of
--  the window if you want RANK / DENSE_RANK to show the tie)

/* ------------------------------------------------------------
   DONE. Next: 03_Practice_Patterns.sql (the interview patterns)
   ------------------------------------------------------------ */
