/* ============================================================
   LEVEL 11 - CTE AND WINDOW FUNCTIONS  |  Exercises.sql
   ------------------------------------------------------------
   Try each question FIRST in the "YOUR ANSWERS" area, then compare
   with SOLUTIONS below. Q10 and Q12 create helper tables and drop them.
   ============================================================ */

USE SQLPractice;
GO

/* ------------------------------------------------------------
   QUESTIONS
   ------------------------------------------------------------
   Q1.  With a CTE: department name, employee count and average salary,
        only for departments whose average is above 65000.

   Q2.  With a RECURSIVE CTE generate every date of January 2025 and
        count how many of those days had NO order.

   Q3.  Org chart: every employee with Level (1 = no manager) and a Path
        like 'Rahul > Amit', ordered by Path. Then, with a second recursive
        CTE, list all managers ABOVE Meera (EmployeeID 112).

   Q4.  Rank all employees by salary with ROW_NUMBER, RANK and DENSE_RANK
        in one query. In a comment, explain why Vikram gets RANK 8 but
        DENSE_RANK 7.

   Q5.  The highest-paid employee of each department (department NAME,
        employee, salary). Skip the employee without a department.

   Q6.  For every order: the same customer's previous order amount
        (0 if none) and the difference. Order by customer, date.

   Q7.  Revenue per month with a running total and a 3-month moving average.

   Q8.  Each product's revenue and its percentage of total revenue
        (2 decimals), highest first.

   Q9.  The THIRD highest salary and who earns it, using DENSE_RANK.

   Q10. Copy Orders into dbo.L11_Ex_Orders and insert 3 duplicate rows
        (new OrderIDs 2001, 2002, 2003 that repeat the CustomerID, EmployeeID,
        OrderDate, TotalAmount and Status of orders 1001, 1001 and 1002).
        Delete the duplicates keeping the LOWEST OrderID, show the count, drop.

   Q11. PIVOT: number of orders per salesperson (use 'Online' when
        EmployeeID is NULL) per Status: Pending / Completed / Cancelled.
        Then write the same with CASE.

   Q12. Gaps and islands: create dbo.L11_Ex_Attendance (EmpID INT, WorkDate DATE)
        with EmpID 101 on 2025-06-02, 06-03, 06-04, 06-09, 06-10, 06-16.
        Show each streak of consecutive days (start, end, days). Drop it.
   ------------------------------------------------------------ */

-- YOUR ANSWERS HERE (write below, run, compare)










/* ============================================================
   SOLUTIONS
   ============================================================ */

-- Q1
WITH DeptStats AS
(
    SELECT d.DepartmentName, COUNT(*) AS Employees, AVG(e.Salary) AS AvgSalary
    FROM dbo.Employees e
    JOIN dbo.Departments d ON d.DepartmentID = e.DepartmentID
    GROUP BY d.DepartmentName
)
SELECT DepartmentName, Employees, AvgSalary
FROM DeptStats
WHERE AvgSalary > 65000
ORDER BY AvgSalary DESC;
GO
-- 2 rows: Finance 2 81000, IT 3 71666.67

-- Q2
WITH Days AS
(
    SELECT CAST('20250101' AS DATE) AS d
    UNION ALL
    SELECT DATEADD(DAY, 1, d) FROM Days WHERE d < '20250131'
)
SELECT COUNT(*) AS DaysWithoutOrders
FROM Days
WHERE NOT EXISTS (SELECT 1 FROM dbo.Orders o WHERE o.OrderDate = Days.d);
GO
-- 28  (31 days, orders on 5, 12 and 20 January)

-- Q3
WITH Org AS
(
    SELECT EmployeeID, EmployeeName, ManagerID, 1 AS Lvl, CAST(EmployeeName AS VARCHAR(500)) AS Path
    FROM dbo.Employees WHERE ManagerID IS NULL
    UNION ALL
    SELECT e.EmployeeID, e.EmployeeName, e.ManagerID, o.Lvl + 1, CAST(o.Path + ' > ' + e.EmployeeName AS VARCHAR(500))
    FROM dbo.Employees e JOIN Org o ON o.EmployeeID = e.ManagerID
)
SELECT Lvl, EmployeeName, Path FROM Org ORDER BY Path;
GO
-- 12 rows, 6 at level 1 and 6 at level 2
WITH Up AS
(
    SELECT EmployeeID, EmployeeName, ManagerID, 0 AS StepsUp
    FROM dbo.Employees WHERE EmployeeID = 112
    UNION ALL
    SELECT m.EmployeeID, m.EmployeeName, m.ManagerID, u.StepsUp + 1
    FROM dbo.Employees m JOIN Up u ON u.ManagerID = m.EmployeeID
)
SELECT StepsUp, EmployeeName FROM Up WHERE StepsUp > 0;
GO
-- 1 row: Karan

-- Q4
SELECT EmployeeName, Salary,
       ROW_NUMBER() OVER (ORDER BY Salary DESC, EmployeeID) AS RowNum,
       RANK()       OVER (ORDER BY Salary DESC) AS Rnk,
       DENSE_RANK() OVER (ORDER BY Salary DESC) AS DenseRnk
FROM dbo.Employees
ORDER BY Salary DESC, EmployeeID;
GO
-- Amit and Pooja tie at 65000 -> both RANK 6 and DENSE_RANK 6 (RowNum 6 and 7).
-- RANK counts the rows above Vikram (7 rows) so he gets 8; DENSE_RANK counts the
-- DISTINCT salaries above him (6 values) so he gets 7.

-- Q5
WITH Ranked AS
(
    SELECT DepartmentID, EmployeeName, Salary,
           ROW_NUMBER() OVER (PARTITION BY DepartmentID ORDER BY Salary DESC, EmployeeID) AS rn
    FROM dbo.Employees
    WHERE DepartmentID IS NOT NULL
)
SELECT d.DepartmentName, r.EmployeeName, r.Salary
FROM Ranked r
JOIN dbo.Departments d ON d.DepartmentID = r.DepartmentID
WHERE r.rn = 1
ORDER BY d.DepartmentName;
GO
-- 5 rows: Finance Sneha, HR Ravi, IT Rahul, Marketing Karan, Sales Priya

-- Q6
SELECT CustomerID, OrderID, OrderDate, TotalAmount,
       LAG(TotalAmount, 1, 0) OVER (PARTITION BY CustomerID ORDER BY OrderDate) AS PrevAmount,
       TotalAmount - LAG(TotalAmount, 1, 0) OVER (PARTITION BY CustomerID ORDER BY OrderDate) AS Diff
FROM dbo.Orders
ORDER BY CustomerID, OrderDate;
GO
-- 19 rows; customer 1: 75000 (diff 75000), 15000 (-60000), 6000 (-9000), 32000 (+26000)

-- Q7
WITH Monthly AS
(
    SELECT MONTH(OrderDate) AS Mth, SUM(TotalAmount) AS Revenue
    FROM dbo.Orders
    GROUP BY MONTH(OrderDate)
)
SELECT Mth, Revenue,
       SUM(Revenue) OVER (ORDER BY Mth ROWS UNBOUNDED PRECEDING) AS RunningTotal,
       AVG(Revenue) OVER (ORDER BY Mth ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS MovingAvg3
FROM Monthly
ORDER BY Mth;
GO
-- 9 rows; Mth 3: running 267500, moving avg 89166.67; Mth 9: running 618000, moving avg 41166.67

-- Q8
WITH Rev AS
(
    SELECT p.ProductName, SUM(od.Quantity * od.UnitPrice) AS Revenue
    FROM dbo.OrderDetails od
    JOIN dbo.Products p ON p.ProductID = od.ProductID
    GROUP BY p.ProductName
)
SELECT ProductName, Revenue,
       CAST(Revenue * 100.0 / SUM(Revenue) OVER () AS DECIMAL(5,2)) AS PctOfTotal
FROM Rev
ORDER BY Revenue DESC;
GO
-- 10 rows: Laptop 300000 48.54, Monitor 175000 28.32, Chair 48000 7.77 ... Notebook 1000 0.16

-- Q9
WITH Ranked AS
(
    SELECT EmployeeName, Salary, DENSE_RANK() OVER (ORDER BY Salary DESC) AS rk
    FROM dbo.Employees
)
SELECT EmployeeName, Salary FROM Ranked WHERE rk = 3;
GO
-- 1 row: Priya 75000

-- Q10
DROP TABLE IF EXISTS dbo.L11_Ex_Orders;
SELECT * INTO dbo.L11_Ex_Orders FROM dbo.Orders;
INSERT INTO dbo.L11_Ex_Orders (OrderID, CustomerID, EmployeeID, OrderDate, TotalAmount, Status)
SELECT 2001, CustomerID, EmployeeID, OrderDate, TotalAmount, Status FROM dbo.Orders WHERE OrderID = 1001
UNION ALL
SELECT 2002, CustomerID, EmployeeID, OrderDate, TotalAmount, Status FROM dbo.Orders WHERE OrderID = 1001
UNION ALL
SELECT 2003, CustomerID, EmployeeID, OrderDate, TotalAmount, Status FROM dbo.Orders WHERE OrderID = 1002;
SELECT COUNT(*) AS BeforeDelete FROM dbo.L11_Ex_Orders;
GO
-- 22
WITH Numbered AS
(
    SELECT OrderID,
           ROW_NUMBER() OVER (PARTITION BY CustomerID, EmployeeID, OrderDate, TotalAmount, Status
                              ORDER BY OrderID) AS rn
    FROM dbo.L11_Ex_Orders
)
DELETE FROM Numbered WHERE rn > 1;
GO
-- (3 rows affected)
SELECT COUNT(*) AS AfterDelete FROM dbo.L11_Ex_Orders;
DROP TABLE IF EXISTS dbo.L11_Ex_Orders;
GO
-- 19

-- Q11
SELECT Salesperson, [Pending], [Completed], [Cancelled]
FROM (SELECT ISNULL(e.EmployeeName, 'Online') AS Salesperson, o.Status, o.OrderID
      FROM dbo.Orders o
      LEFT JOIN dbo.Employees e ON e.EmployeeID = o.EmployeeID) AS src
PIVOT (COUNT(OrderID) FOR Status IN ([Pending], [Completed], [Cancelled])) AS pv
ORDER BY Salesperson;
GO
-- 4 rows: Neha 0/5/1, Online 0/1/0, Priya 1/6/0, Vikram 1/4/0
SELECT ISNULL(e.EmployeeName, 'Online') AS Salesperson,
       SUM(CASE WHEN o.Status = 'Pending'   THEN 1 ELSE 0 END) AS Pending,
       SUM(CASE WHEN o.Status = 'Completed' THEN 1 ELSE 0 END) AS Completed,
       SUM(CASE WHEN o.Status = 'Cancelled' THEN 1 ELSE 0 END) AS Cancelled
FROM dbo.Orders o
LEFT JOIN dbo.Employees e ON e.EmployeeID = o.EmployeeID
GROUP BY ISNULL(e.EmployeeName, 'Online')
ORDER BY Salesperson;
GO
-- same 4 rows

-- Q12
DROP TABLE IF EXISTS dbo.L11_Ex_Attendance;
CREATE TABLE dbo.L11_Ex_Attendance (EmpID INT, WorkDate DATE);
INSERT INTO dbo.L11_Ex_Attendance VALUES
(101, '20250602'), (101, '20250603'), (101, '20250604'), (101, '20250609'), (101, '20250610'), (101, '20250616');
GO
WITH G AS
(
    SELECT EmpID, WorkDate,
           DATEADD(DAY, -ROW_NUMBER() OVER (PARTITION BY EmpID ORDER BY WorkDate), WorkDate) AS Grp
    FROM dbo.L11_Ex_Attendance
)
SELECT EmpID, MIN(WorkDate) AS StreakStart, MAX(WorkDate) AS StreakEnd, COUNT(*) AS Days
FROM G
GROUP BY EmpID, Grp
ORDER BY StreakStart;
GO
-- 3 rows: 06-02..06-04 (3), 06-09..06-10 (2), 06-16..06-16 (1)
DROP TABLE IF EXISTS dbo.L11_Ex_Attendance;
GO
