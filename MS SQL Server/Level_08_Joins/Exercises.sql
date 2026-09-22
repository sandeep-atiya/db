/* ============================================================
   LEVEL 08 - JOINS  |  Exercises.sql
   ------------------------------------------------------------
   Try each question in the "YOUR ANSWERS" area FIRST.
   Then scroll down to SOLUTIONS and compare.
   Q11 creates a helper table dbo.L08_SalaryBands and drops it.
   ============================================================ */

USE SQLPractice;
GO

/* ------------------------------------------------------------
   QUESTIONS
   ------------------------------------------------------------
   Q1.  Every employee with department name and location.
        Employees without a department must still appear.

   Q2.  Departments that have no employees - write it two ways
        (LEFT JOIN ... IS NULL and NOT EXISTS).

   Q3.  Every order with the customer name and the salesperson
        name. The online order must show 'Online' as salesperson.

   Q4.  Every employee with the name of their manager; top-level
        employees show '(none)'.

   Q5.  Number of direct reports per manager (managers only),
        most reports first.

   Q6.  Products that were never ordered.

   Q7.  Revenue per product category counting Completed orders
        only, highest first.

   Q8.  For EVERY customer (Hina included) the number of
        Completed orders. Hint: where does the Status filter go?

   Q9.  Order 1008 in full: OrderID, OrderDate, customer name,
        city, salesperson, department, product, quantity,
        unit price and line total (5 tables).

   Q10. Total revenue by joining Orders to OrderDetails.
        First show why SUM(o.TotalAmount) gives the wrong number,
        then get the right 618000 in two different ways.

   Q11. Create dbo.L08_SalaryBands (Junior < 60000, Mid 60000 -
        74999.99, Senior >= 75000) and count employees per band
        with a non-equi join. Drop the table afterwards.

   Q12. (interview) All PAIRS of employees who work in the same
        department. Each pair once, no employee paired with itself.
        Show department name and both employee names.
   ------------------------------------------------------------ */

-- YOUR ANSWERS HERE (write below, run, compare)










/* ============================================================
   SOLUTIONS
   ============================================================ */

-- Q1
SELECT e.EmployeeName, d.DepartmentName, d.Location
FROM dbo.Employees e
LEFT JOIN dbo.Departments d ON d.DepartmentID = e.DepartmentID
ORDER BY e.EmployeeID;   -- 12 rows; Anjali NULL NULL
GO

-- Q2
SELECT d.DepartmentName
FROM dbo.Departments d
LEFT JOIN dbo.Employees e ON e.DepartmentID = d.DepartmentID
WHERE e.EmployeeID IS NULL;   -- Legal

SELECT d.DepartmentName
FROM dbo.Departments d
WHERE NOT EXISTS (SELECT 1 FROM dbo.Employees e WHERE e.DepartmentID = d.DepartmentID);   -- Legal
GO

-- Q3
SELECT o.OrderID, c.CustomerName, ISNULL(e.EmployeeName, 'Online') AS Salesperson
FROM dbo.Orders o
JOIN      dbo.Customers c ON c.CustomerID = o.CustomerID
LEFT JOIN dbo.Employees e ON e.EmployeeID = o.EmployeeID       -- LEFT: EmployeeID is NULL for 1019
ORDER BY o.OrderID;   -- 19 rows; 1019 Bhavna Mehta Online
GO

-- Q4
SELECT e.EmployeeName, ISNULL(m.EmployeeName, '(none)') AS Manager
FROM dbo.Employees e
LEFT JOIN dbo.Employees m ON m.EmployeeID = e.ManagerID
ORDER BY e.EmployeeID;   -- Rahul (none), Amit Rahul, Priya (none), Neha Priya, ... 12 rows
GO

-- Q5
SELECT m.EmployeeName AS Manager, COUNT(*) AS DirectReports
FROM dbo.Employees e
JOIN dbo.Employees m ON m.EmployeeID = e.ManagerID
GROUP BY m.EmployeeName
ORDER BY DirectReports DESC, Manager;   -- Priya 2, Rahul 2, Karan 1, Sneha 1
GO

-- Q6
SELECT p.ProductName
FROM dbo.Products p
LEFT JOIN dbo.OrderDetails od ON od.ProductID = p.ProductID
WHERE od.OrderDetailID IS NULL;   -- Webcam
GO

-- Q7
SELECT p.Category, SUM(od.Quantity * od.UnitPrice) AS Revenue
FROM dbo.OrderDetails od
JOIN dbo.Products p ON p.ProductID = od.ProductID
JOIN dbo.Orders   o ON o.OrderID   = od.OrderID
WHERE o.Status = 'Completed'
GROUP BY p.Category
ORDER BY Revenue DESC;   -- Electronics 507500 | Furniture 65000 | Stationery 1500
GO

-- Q8
SELECT c.CustomerName, COUNT(o.OrderID) AS CompletedOrders
FROM dbo.Customers c
LEFT JOIN dbo.Orders o ON o.CustomerID = c.CustomerID AND o.Status = 'Completed'   -- filter in ON, not WHERE
GROUP BY c.CustomerName
ORDER BY c.CustomerName;   -- Aarav 3, Bhavna 4, Chirag 2, Divya 2, Esha 1, Farhan 2, Gaurav 2, Hina 0
-- With WHERE o.Status = 'Completed' instead, Hina disappears (LEFT JOIN becomes INNER).
GO

-- Q9
SELECT o.OrderID, o.OrderDate, c.CustomerName, c.City,
       e.EmployeeName AS Salesperson, d.DepartmentName,
       p.ProductName, od.Quantity, od.UnitPrice, od.Quantity * od.UnitPrice AS LineTotal
FROM dbo.Orders o
JOIN      dbo.Customers    c  ON c.CustomerID   = o.CustomerID
LEFT JOIN dbo.Employees    e  ON e.EmployeeID   = o.EmployeeID
LEFT JOIN dbo.Departments  d  ON d.DepartmentID = e.DepartmentID
JOIN      dbo.OrderDetails od ON od.OrderID     = o.OrderID
JOIN      dbo.Products     p  ON p.ProductID    = od.ProductID
WHERE o.OrderID = 1008;   -- 3 rows: Farhan Ali, Mumbai, Vikram, Sales; Laptop 75000 / Mouse 1000 / Keyboard 2500
GO

-- Q10
-- Wrong: the join repeats each order once per line, so multi-line orders are summed several times
SELECT SUM(o.TotalAmount) AS WrongRevenue
FROM dbo.Orders o
JOIN dbo.OrderDetails od ON od.OrderID = o.OrderID;   -- 824000
-- Right 1: sum at the line level
SELECT SUM(od.Quantity * od.UnitPrice) AS RightRevenue
FROM dbo.Orders o
JOIN dbo.OrderDetails od ON od.OrderID = o.OrderID;   -- 618000
-- Right 2: do not join at all - Orders already holds the total (or aggregate OrderDetails first, then join)
SELECT SUM(TotalAmount) AS RightRevenue FROM dbo.Orders;   -- 618000
GO

-- Q11
DROP TABLE IF EXISTS dbo.L08_SalaryBands;
CREATE TABLE dbo.L08_SalaryBands (BandName VARCHAR(10) NOT NULL, MinSalary DECIMAL(12,2) NOT NULL, MaxSalary DECIMAL(12,2) NOT NULL);
INSERT INTO dbo.L08_SalaryBands VALUES ('Junior', 0, 59999.99), ('Mid', 60000, 74999.99), ('Senior', 75000, 9999999);

SELECT b.BandName, COUNT(e.EmployeeID) AS Employees
FROM dbo.L08_SalaryBands b
LEFT JOIN dbo.Employees e ON e.Salary BETWEEN b.MinSalary AND b.MaxSalary
GROUP BY b.BandName
ORDER BY MIN(b.MinSalary);   -- Junior 3, Mid 6, Senior 3

DROP TABLE IF EXISTS dbo.L08_SalaryBands;
GO

-- Q12
SELECT d.DepartmentName, e1.EmployeeName AS Employee1, e2.EmployeeName AS Employee2
FROM dbo.Employees e1
JOIN dbo.Employees   e2 ON e2.DepartmentID = e1.DepartmentID AND e2.EmployeeID > e1.EmployeeID   -- > gives each pair once
JOIN dbo.Departments d  ON d.DepartmentID  = e1.DepartmentID
ORDER BY d.DepartmentName, e1.EmployeeID, e2.EmployeeID;
-- 8 pairs: Finance Sneha-Deepak | IT Rahul-Amit, Rahul-Pooja, Amit-Pooja | Marketing Karan-Meera | Sales Priya-Neha, Priya-Vikram, Neha-Vikram
-- (Anjali has DepartmentID NULL: NULL never equals NULL, so she pairs with nobody - correct.)
GO
