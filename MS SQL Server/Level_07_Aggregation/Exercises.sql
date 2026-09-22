/* ============================================================
   LEVEL 07 - AGGREGATION  |  Exercises.sql
   ------------------------------------------------------------
   Try each question in the "YOUR ANSWERS" area FIRST.
   Then scroll down to SOLUTIONS and compare.
   All questions use the SQLPractice data only (nothing is changed).
   ============================================================ */

USE SQLPractice;
GO

/* ------------------------------------------------------------
   QUESTIONS
   ------------------------------------------------------------
   Q1.  Total, average (2 decimals), lowest and highest salary of
        all employees.

   Q2.  On Customers show COUNT(*), COUNT(Email) and
        COUNT(DISTINCT City) in one row. Explain the 3 numbers.

   Q3.  Employees and total salary per DepartmentID (NULL group
        included), highest total first.

   Q4.  Per product Category: number of products, average price
        rounded to 2 decimals, total stock.

   Q5.  Orders and revenue per month ('yyyy-MM'), but ONLY months
        whose revenue is above 50000, in date order.

   Q6.  Customer NAMES that placed 3 or more orders, with the count.

   Q7.  Per department NAME: headcount, average salary and the
        member names as one comma-separated string, but only the
        departments whose average salary is above 65000.

   Q8.  For EVERY customer (Hina included) show the number of
        Completed, Pending and Cancelled orders in three columns.

   Q9.  Revenue per salesperson (employee name) counting Completed
        orders only, highest first. Online orders must not appear.

   Q10. Top 3 products by revenue (Quantity * UnitPrice), with the
        units sold.

   Q11. Per category: the plain average of the line UnitPrice vs
        the weighted price per unit (revenue / units). Which one
        would you report as "average selling price"?

   Q12. (advanced) Orders and revenue per Status plus a final
        'ALL' total row, using ROLLUP and GROUPING().
   ------------------------------------------------------------ */

-- YOUR ANSWERS HERE (write below, run, compare)










/* ============================================================
   SOLUTIONS
   ============================================================ */

-- Q1
SELECT SUM(Salary) AS Total, CAST(AVG(Salary) AS DECIMAL(10,2)) AS Average, MIN(Salary) AS Lowest, MAX(Salary) AS Highest
FROM dbo.Employees;   -- 805000.00, 67083.33, 48000.00, 90000.00
GO

-- Q2
SELECT COUNT(*) AS AllRows, COUNT(Email) AS NonNullEmails, COUNT(DISTINCT City) AS DistinctCities
FROM dbo.Customers;   -- 8, 6, 5   (2 customers have NULL email; Delhi and Mumbai repeat)
GO

-- Q3
SELECT DepartmentID, COUNT(*) AS Employees, SUM(Salary) AS Payroll
FROM dbo.Employees
GROUP BY DepartmentID
ORDER BY Payroll DESC;   -- 1 3 215000 | 2 3 192000 | 4 2 162000 | 5 2 128000 | 3 1 60000 | NULL 1 48000
GO

-- Q4
SELECT Category, COUNT(*) AS Products, CAST(AVG(Price) AS DECIMAL(10,2)) AS AvgPrice, SUM(Stock) AS TotalStock
FROM dbo.Products
GROUP BY Category;   -- Electronics 6 18500.00 215 | Furniture 3 11666.67 40 | Stationery 2 30.00 1500
GO

-- Q5
SELECT CONVERT(CHAR(7), OrderDate, 120) AS YearMonth, COUNT(*) AS Orders, SUM(TotalAmount) AS Revenue
FROM dbo.Orders
GROUP BY CONVERT(CHAR(7), OrderDate, 120)
HAVING SUM(TotalAmount) > 50000
ORDER BY YearMonth;   -- 2025-01 110000 | 2025-02 73000 | 2025-03 84500 | 2025-06 177500 | 2025-08 79000  (5 rows)
GO

-- Q6
SELECT c.CustomerName, COUNT(*) AS Orders
FROM dbo.Customers c
JOIN dbo.Orders o ON o.CustomerID = c.CustomerID
GROUP BY c.CustomerName
HAVING COUNT(*) >= 3
ORDER BY Orders DESC, c.CustomerName;   -- Aarav Sharma 4, Bhavna Mehta 4, Chirag Patel 3
GO

-- Q7
SELECT d.DepartmentName, COUNT(*) AS Headcount, CAST(AVG(e.Salary) AS DECIMAL(10,2)) AS AvgSalary,
       STRING_AGG(e.EmployeeName, ', ') WITHIN GROUP (ORDER BY e.EmployeeName) AS Members
FROM dbo.Departments d
JOIN dbo.Employees e ON e.DepartmentID = d.DepartmentID
GROUP BY d.DepartmentName
HAVING AVG(e.Salary) > 65000
ORDER BY AvgSalary DESC;   -- Finance 2 81000.00 Deepak, Sneha | IT 3 71666.67 Amit, Pooja, Rahul
GO

-- Q8
SELECT c.CustomerName,
       SUM(CASE WHEN o.Status = 'Completed' THEN 1 ELSE 0 END) AS Completed,
       SUM(CASE WHEN o.Status = 'Pending'   THEN 1 ELSE 0 END) AS Pending,
       SUM(CASE WHEN o.Status = 'Cancelled' THEN 1 ELSE 0 END) AS Cancelled
FROM dbo.Customers c
LEFT JOIN dbo.Orders o ON o.CustomerID = c.CustomerID      -- LEFT JOIN keeps Hina (all zeros)
GROUP BY c.CustomerName
ORDER BY c.CustomerName;   -- Aarav 3 1 0 | Bhavna 4 0 0 | Chirag 2 1 0 | Divya 2 0 0 | Esha 1 0 1 | Farhan 2 0 0 | Gaurav 2 0 0 | Hina 0 0 0
GO

-- Q9
SELECT e.EmployeeName, COUNT(*) AS CompletedOrders, SUM(o.TotalAmount) AS Revenue
FROM dbo.Orders o
JOIN dbo.Employees e ON e.EmployeeID = o.EmployeeID        -- INNER JOIN drops the online order (EmployeeID NULL)
WHERE o.Status = 'Completed'
GROUP BY e.EmployeeName
ORDER BY Revenue DESC;   -- Priya 6 261000 | Vikram 4 246500 | Neha 5 64000
GO

-- Q10
SELECT TOP (3) p.ProductName, SUM(od.Quantity) AS Units, SUM(od.Quantity * od.UnitPrice) AS Revenue
FROM dbo.OrderDetails od
JOIN dbo.Products p ON p.ProductID = od.ProductID
GROUP BY p.ProductName
ORDER BY Revenue DESC;   -- Laptop 4 300000 | Monitor 7 175000 | Chair 6 48000
GO

-- Q11
SELECT p.Category,
       CAST(AVG(od.UnitPrice) AS DECIMAL(10,2))                                  AS AvgOfLinePrices,
       CAST(SUM(od.Quantity * od.UnitPrice) / SUM(od.Quantity) AS DECIMAL(10,2)) AS WeightedPricePerUnit
FROM dbo.OrderDetails od
JOIN dbo.Products p ON p.ProductID = od.ProductID
GROUP BY p.Category;   -- Electronics 20294.12 vs 15469.70 | Furniture 11000.00 vs 10500.00 | Stationery 23.33 vs 14.71
-- Report the WEIGHTED one: it is revenue divided by units actually sold. The plain AVG gives a 100-pen line
-- the same weight as a 1-laptop line.
GO

-- Q12
SELECT CASE WHEN GROUPING(Status) = 1 THEN 'ALL' ELSE Status END AS Status,
       COUNT(*) AS Orders, SUM(TotalAmount) AS Revenue
FROM dbo.Orders
GROUP BY ROLLUP(Status)
ORDER BY GROUPING(Status), Status;   -- Cancelled 1 8000 | Completed 16 574000 | Pending 2 36000 | ALL 19 618000
GO
