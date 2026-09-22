/* ============================================================
   00_SETUP  |  03_Insert_Sample_Data.sql
   ------------------------------------------------------------
   Loads sample data used by EVERY level.
   Safe to re-run: tables are emptied first (children -> parents).

   The data is small on purpose so you can predict results by
   hand, but it contains the "tricky" cases interviewers love:
     - Employees with NULL DepartmentID (contractor)
     - Department with no employees (Legal)
     - Duplicate salaries (RANK vs DENSE_RANK)
     - Customers with NULL email and with no orders
     - Product never ordered (Webcam), product with 0 stock
     - Orders with NULL EmployeeID (online order)
     - Order status: Pending / Completed / Cancelled
   ============================================================ */

USE SQLPractice;
GO

/* ---------- Empty tables (children first) ---------- */
-- TRUNCATE resets the IDENTITY back to 1 (allowed here: no foreign key points TO OrderDetails).
-- The other tables are referenced by foreign keys, so they need DELETE.
TRUNCATE TABLE dbo.OrderDetails;
DELETE FROM dbo.Orders;
DELETE FROM dbo.Employees;
DELETE FROM dbo.Departments;
DELETE FROM dbo.Customers;
DELETE FROM dbo.Products;
GO

/* ---------- 1. Departments (6) ---------- */
INSERT INTO dbo.Departments (DepartmentID, DepartmentName, Location) VALUES
(1, 'IT',        'Delhi'),
(2, 'Sales',     'Mumbai'),
(3, 'HR',        'Delhi'),
(4, 'Finance',   'Bangalore'),
(5, 'Marketing', 'Pune'),
(6, 'Legal',     'Delhi');      -- no employees (LEFT JOIN / NOT EXISTS practice)
GO

/* ---------- 2. Employees (12) ---------- */
INSERT INTO dbo.Employees (EmployeeID, EmployeeName, Email, DepartmentID, Salary, HireDate, ManagerID) VALUES
(101, 'Rahul',  'rahul@example.com',  1,    85000, '2022-01-10', NULL),   -- IT head
(102, 'Amit',   'amit@example.com',   1,    65000, '2023-03-15', 101),
(103, 'Priya',  'priya@example.com',  2,    75000, '2021-07-20', NULL),   -- Sales head
(104, 'Neha',   'neha@example.com',   2,    55000, '2024-02-12', 103),
(105, 'Ravi',   'ravi@example.com',   3,    60000, '2022-11-01', NULL),   -- HR head
(106, 'Sneha',  'sneha@example.com',  4,    90000, '2020-05-18', NULL),   -- Finance head (highest paid)
(107, 'Karan',  'karan@example.com',  5,    70000, '2023-08-25', NULL),   -- Marketing head
(108, 'Pooja',  'pooja@example.com',  1,    65000, '2023-06-01', 101),    -- same salary as Amit
(109, 'Vikram', 'vikram@example.com', 2,    62000, '2022-09-14', 103),
(110, 'Anjali', NULL,                 NULL, 48000, '2024-05-20', NULL),   -- contractor: no dept, no email
(111, 'Deepak', 'deepak@example.com', 4,    72000, '2021-03-03', 106),
(112, 'Meera',  'meera@example.com',  5,    58000, '2024-01-08', 107);
GO

/* ---------- 3. Customers (8) ---------- */
INSERT INTO dbo.Customers (CustomerID, CustomerName, Email, City, CreatedDate) VALUES
(1, 'Aarav Sharma', 'aarav@example.com',  'Delhi',     '2024-11-05'),
(2, 'Bhavna Mehta', 'bhavna@example.com', 'Mumbai',    '2024-12-12'),
(3, 'Chirag Patel', 'chirag@example.com', 'Delhi',     '2025-01-08'),
(4, 'Divya Nair',   'divya@example.com',  'Pune',      '2025-01-25'),
(5, 'Esha Kapoor',  'esha@example.com',   'Bangalore', '2025-02-10'),
(6, 'Farhan Ali',   NULL,                 'Mumbai',    '2025-03-01'),   -- no email
(7, 'Gaurav Singh', 'gaurav@example.com', 'Chennai',   '2025-04-20'),
(8, 'Hina Khan',    NULL,                 'Delhi',     '2025-06-15');   -- no email, no orders
GO

/* ---------- 4. Products (11) ---------- */
INSERT INTO dbo.Products (ProductID, ProductName, Category, Price, Stock) VALUES
(1,  'Laptop',     'Electronics', 75000, 10),
(2,  'Mouse',      'Electronics',  1000, 100),
(3,  'Keyboard',   'Electronics',  2500, 50),
(4,  'Chair',      'Furniture',    8000, 20),
(5,  'Desk',       'Furniture',   15000, 15),
(6,  'Monitor',    'Electronics', 25000, 25),
(7,  'Notebook',   'Stationery',     50, 500),
(8,  'Pen',        'Stationery',     10, 1000),
(9,  'Headphones', 'Electronics',  3000, 0),     -- out of stock
(10, 'Bookshelf',  'Furniture',   12000, 5),
(11, 'Webcam',     'Electronics',  4500, 30);    -- never ordered
GO

/* ---------- 5. Orders (19)  Jan -> Sep 2025 ---------- */
INSERT INTO dbo.Orders (OrderID, CustomerID, EmployeeID, OrderDate, TotalAmount, Status) VALUES
(1001, 1, 103,  '2025-01-05',  75000, 'Completed'),
(1002, 2, 104,  '2025-01-12',  10000, 'Completed'),
(1003, 3, 103,  '2025-01-20',  25000, 'Completed'),
(1004, 1, 104,  '2025-02-03',  15000, 'Completed'),
(1005, 4, 103,  '2025-02-14',  50000, 'Completed'),
(1006, 5, 104,  '2025-02-28',   8000, 'Cancelled'),
(1007, 2, 109,  '2025-03-10',   6000, 'Completed'),
(1008, 6, 109,  '2025-03-18',  78500, 'Completed'),
(1009, 1, 103,  '2025-04-02',   6000, 'Completed'),
(1010, 3, 104,  '2025-04-15',   1500, 'Completed'),
(1011, 7, 109,  '2025-05-06',  12000, 'Completed'),
(1012, 2, 103,  '2025-05-21',  30000, 'Completed'),
(1013, 4, 104,  '2025-06-01',  27500, 'Completed'),
(1014, 5, 109,  '2025-06-19', 150000, 'Completed'),
(1015, 1, 103,  '2025-07-07',  32000, 'Pending'),
(1016, 6, 104,  '2025-07-25',  10000, 'Completed'),
(1017, 3, 109,  '2025-08-09',   4000, 'Pending'),
(1018, 7, 103,  '2025-08-30',  75000, 'Completed'),
(1019, 2, NULL, '2025-09-05',   2500, 'Completed');   -- online order, no salesperson
GO

/* ---------- 6. OrderDetails (26)  (line totals add up to Orders.TotalAmount) ---------- */
INSERT INTO dbo.OrderDetails (OrderID, ProductID, Quantity, UnitPrice) VALUES
(1001, 1,  1,  75000),
(1002, 4,  1,   8000), (1002, 2,  2,  1000),
(1003, 6,  1,  25000),
(1004, 5,  1,  15000),
(1005, 6,  2,  25000),
(1006, 4,  1,   8000),
(1007, 3,  2,   2500), (1007, 2,  1,  1000),
(1008, 1,  1,  75000), (1008, 2,  1,  1000), (1008, 3, 1, 2500),
(1009, 9,  2,   3000),
(1010, 7, 20,     50), (1010, 8, 50,    10),
(1011, 10, 1,  12000),
(1012, 5,  2,  15000),
(1013, 6,  1,  25000), (1013, 3,  1,  2500),
(1014, 1,  2,  75000),
(1015, 4,  4,   8000),
(1016, 2, 10,   1000),
(1017, 9,  1,   3000), (1017, 8, 100,   10),
(1018, 6,  3,  25000),
(1019, 3,  1,   2500);
GO

/* ---------- Verify row counts ---------- */
SELECT 'Departments' AS TableName, COUNT(*) AS RowsCount FROM dbo.Departments
UNION ALL SELECT 'Employees',    COUNT(*) FROM dbo.Employees
UNION ALL SELECT 'Customers',    COUNT(*) FROM dbo.Customers
UNION ALL SELECT 'Products',     COUNT(*) FROM dbo.Products
UNION ALL SELECT 'Orders',       COUNT(*) FROM dbo.Orders
UNION ALL SELECT 'OrderDetails', COUNT(*) FROM dbo.OrderDetails;
GO

/* ---------- Sanity check: every order total = sum of its lines ---------- */
SELECT o.OrderID, o.TotalAmount, SUM(d.Quantity * d.UnitPrice) AS LineTotal
FROM dbo.Orders o
JOIN dbo.OrderDetails d ON d.OrderID = o.OrderID
GROUP BY o.OrderID, o.TotalAmount
HAVING o.TotalAmount <> SUM(d.Quantity * d.UnitPrice);   -- expect 0 rows
GO
