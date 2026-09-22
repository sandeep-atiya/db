
CREATE DATABASE SQLPractice;
GO


USE SQLPractice;
GO


SELECT DB_NAME() AS CurrentDatabase;
GO 


-- 2. Create your first tables

CREATE TABLE Departments
(
 DepartmentID INT PRIMARY KEY, 
 DepartmentName VARCHAR(100) NOT NULL,
 Location VARCHAR(100)
);

GO


CREATE TABLE Employees 
(
  EmployeeID INT PRIMARY KEY, 
  EmployeeName VARCHAR(100) NOT NULL, 
  Email VARCHAR(150) UNIQUE, 
  DepartmentID INT, 
  Salary DECIMAL(12,2),
  HireDate Date,
  ManagerID INT NULL,

  CONSTRAINT FK_Employees_Departments
     FOREIGN KEY (DepartmentID)
	 REFERENCES Departments(DepartmentID)
);

GO 

CREATE TABLE Customers
(
  CustomerID INT PRIMARY KEY, 
  CustomerName VARCHAR(100) NOT NULL, 
  Email VARCHAR(150),
  City VARCHAR(100),
  CreateDate DATE
);

GO

CREATE TABLE Products
(
 ProductID INT PRIMARY KEY, 
 ProductName  VARCHAR(100) NOT NULL, 
 Category VARCHAR(100),
 Price DECIMAL(12,2),
 Stock INT
);
GO

CREATE TABLE Orders
(
  OrderID INT PRIMARY KEY, 
  CustomerID INT NOT NULL, 
  EmployeeID INT, 
  OrderDate DATE, 
  TotalAmount DECIMAL(12,2),

  CONSTRAINT FK_Orders_Customers
    FOREIGN KEY (CustomerID)
	REFERENCES Customers(CustomerID),

  CONSTRAINT FK_Orders_Employees
    FOREIGN KEY (EmployeeID)
	REFERENCES Employees(EmployeeID)
);

GO

-- 3. Insert practice data

INSERT INTO Departments
 (DepartmentID, DepartmentName, Location)
VALUES
 (1,'IT','Delhi'),
 (2,'Sales', 'Mumbai'),
 (3, 'HR', 'Delhi'),
 (4, 'Finance', 'Bangalore'),
 (5, 'Marketing', 'Pune');

 GO 

 INSERT INTO Employees
  (EmployeeID, EmployeeName, Email, DepartmentID, Salary, HireDate, ManagerID)
VALUES
  (101, 'Rahul', 'rahul@example.com', 1, 85000, '2022-01-10', NULL),
  (102, 'Amit', 'amit@example.com', 1, 65000, '2023-03-15', 101),
  (103, 'Priya', 'priya@example.com', 2, 75000, '2021-07-20', NULL),
  (104, 'Neha', 'neha@example.com', 2, 55000, '2024-02-12', 103),
  (105, 'Ravi', 'ravi@example.com', 3, 60000, '2022-11-01', NULL),
  (106, 'Sneha', 'sneha@example.com', 4, 90000, '2020-05-18', NULL),
  (107, 'Karan', 'karan@example.com', 5, 70000, '2023-08-25', NULL);

GO

INSERT INTO Customers
	(CustomerID, CustomerName, Email, City, CreateDate)
VALUES
(1, 'Customer A', 'a@example.com', 'Delhi', '2025-01-10'),
(2, 'Customer B', 'b@example.com', 'Mumbai', '2025-02-15'),
(3, 'Customer C', 'c@example.com', 'Delhi', '2025-03-20'),
(4, 'Customer D', 'd@example.com', 'Pune', '2025-04-05'),
(5, 'Customer E', 'e@example.com', 'Bangalore', '2025-05-12');


GO



INSERT INTO Products
 (ProductID, ProductName, Category, Price, Stock)

 VALUES
 (1, 'Laptop', 'Electronics', 75000, 10),
    (2, 'Mouse', 'Electronics', 1000, 100),
    (3, 'Keyboard', 'Electronics', 2500, 50),
    (4, 'Chair', 'Furniture', 8000, 20),
    (5, 'Desk', 'Furniture', 15000, 15),
    (6, 'Monitor', 'Electronics', 25000, 25);
GO



INSERT INTO Orders
(OrderID, CustomerID, EmployeeID, OrderDate, TotalAmount)
VALUES 
    (1001, 1, 103, '2025-06-01', 75000),
    (1002, 2, 104, '2025-06-02', 10000),
    (1003, 3, 103, '2025-06-03', 25000),
    (1004, 1, 104, '2025-06-05', 15000),
    (1005, 4, 103, '2025-06-10', 50000),
    (1006, 5, 104, '2025-06-15', 8000);
GO



-- Level 1 — Database basics

/*
CREATE DATABASE
ALTER DATABASE
DROP DATABASE

USE
GO

CREATE TABLE
ALTER TABLE
DROP TABLE

CREATE SCHEMA
DROP SCHEMA

*/

-- Step 1: Create a new database named PracticeDB
CREATE DATABASE PracticeDB;
GO

-- Step 2: Switch context to your new database
USE PracticeDB;
GO

-- Step 3: Modify database properties (e.g., set to READ_ONLY mode)
ALTER DATABASE PracticeDB SET READ_ONLY;
GO

-- Revert back to READ_WRITE so we can work with tables
ALTER DATABASE PracticeDB SET READ_WRITE;
GO


--Note on DROP DATABASE:
--To drop a database, you must switch out of it first (e.g., USE master;) because SQL Server won't let you delete an active database.

USE master;
GO
DROP DATABASE PracticeDB;
GO


-- 2. Schema Operations (CREATE, DROP)
-- Schemas help you organize objects logically inside a database (e.g., separating Sales data from HR data).

USE PracticeDB;
GO

-- Step 1: Create a custom schema named 'Sales'
CREATE SCHEMA Sales;
GO

-- Step 2: Create another schema named 'HR'
CREATE SCHEMA HR;
GO

-- Step 3: Drop a schema (Schema MUST be empty before dropping)
DROP SCHEMA HR;
GO


-- 3. Table Operations (CREATE, ALTER, DROP)
-- Now we will create tables inside both the default dbo schema and our custom Sales schema, then alter their structure.

-- Creating Tables

USE PracticeDB;
GO

-- 1. Create a table in the default 'dbo' schema
CREATE TABLE Employees (
    EmployeeID INT PRIMARY KEY IDENTITY(1,1),
    FirstName NVARCHAR(50) NOT NULL,
    LastName NVARCHAR(50) NOT NULL,
    HireDate DATE DEFAULT GETDATE()
);
GO

-- 2. Create a table in the custom 'Sales' schema
CREATE TABLE Sales.Customers (
    CustomerID INT PRIMARY KEY IDENTITY(100,1),
    CustomerName NVARCHAR(100) NOT NULL,
    Email VARCHAR(100) UNIQUE
);
GO


--==Altering Tables

-- Step 1: Add a new column to Employees
ALTER TABLE Employees
ADD Salary DECIMAL(10, 2);
GO

-- Step 2: Modify an existing column datatype
ALTER TABLE Employees
ALTER COLUMN FirstName NVARCHAR(100) NOT NULL;
GO

-- Step 3: Remove a column from Employees
ALTER TABLE Employees
DROP COLUMN HireDate;
GO


-- Dropping Tables

-- Drop the Customers table inside the Sales schema
DROP TABLE Sales.Customers;
GO

-- Drop the Employees table inside the dbo schema
DROP TABLE Employees;
GO





-- Level 2 — Data types

/*

INT
BIGINT
DECIMAL
NUMERIC
FLOAT
VARCHAR
NVARCHAR
CHAR
DATE
DATETIME
DATETIME2
TIME
BIT
UNIQUEIDENTIFIER

*/

USE PracticeDB;
GO

-- 1. Create a table demonstrating all Level 2 data types
CREATE TABLE DataTypeDef (
    -- Numeric Types
    RecordID INT IDENTITY(1,1) PRIMARY KEY,
    LargeCounter BIGINT,
    ExactPrice DECIMAL(10, 2),        -- Max 10 digits total, 2 after decimal
    ScientificVal FLOAT,
    IsActive BIT,

    -- String Types
    CountryCode CHAR(2),               -- Always reserves 2 bytes
    Username VARCHAR(50),              -- Variable length ASCII
    LocalizedName NVARCHAR(100),       -- Supports Unicode (Chinese, Hindi, Arabic, etc.)

    -- Date & Time Types
    BirthDate DATE,
    ShiftStartTime TIME,
    LegacyLogTime DATETIME,
    ModernLogTime DATETIME2,

    -- System / GUID
    RowGUID UNIQUEIDENTIFIER DEFAULT NEWID()
);
GO

-- 2. Insert valid data into all types
INSERT INTO DataTypeDef (
    LargeCounter, 
    ExactPrice, 
    ScientificVal, 
    IsActive, 
    CountryCode, 
    Username, 
    LocalizedName, 
    BirthDate, 
    ShiftStartTime, 
    LegacyLogTime, 
    ModernLogTime
)
VALUES (
    9223372036854775807,              -- Max BIGINT value
    1299.99,                          -- DECIMAL(10,2)
    3.1415926535,                     -- FLOAT
    1,                                -- BIT (True)
    'US',                             -- CHAR(2)
    'john_doe',                       -- VARCHAR
    N'こんにちは / Hello',              -- NVARCHAR (N prefix preserves Unicode)
    '1995-06-15',                     -- DATE
    '08:30:00',                       -- TIME
    GETDATE(),                        -- DATETIME
    SYSDATETIME()                     -- DATETIME2
);
GO

-- 3. Query the data
SELECT * FROM DataTypeDef;
GO













-- ============> 1. Constraint Quick Reference

USE PracticeDB;
GO

-- Cleanup existing tables if re-running script
IF OBJECT_ID('dbo.Employees', 'U') IS NOT NULL DROP TABLE dbo.Employees;
IF OBJECT_ID('dbo.Departments', 'U') IS NOT NULL DROP TABLE dbo.Departments;
GO

-- 1. Create Parent Table: Departments
CREATE TABLE Departments (
    DepartmentID INT IDENTITY(10, 10) PRIMARY KEY, -- Seeds at 10, increments by 10
    DeptName NVARCHAR(50) NOT NULL UNIQUE          -- NOT NULL + UNIQUE combined
);
GO

-- 2. Create Child Table: Employees with explicit constraints
CREATE TABLE Employees (
    EmployeeID INT IDENTITY(1,1) PRIMARY KEY,      -- IDENTITY + PRIMARY KEY
    NationalID VARCHAR(20) NOT NULL,
    FirstName NVARCHAR(50) NOT NULL,
    LastName NVARCHAR(50) NOT NULL,
    Email VARCHAR(100) NOT NULL,
    Age INT NOT NULL,
    Salary DECIMAL(10,2) NOT NULL,
    EmploymentStatus VARCHAR(20) DEFAULT 'Active', -- DEFAULT value
    HireDate DATE DEFAULT GETDATE(),               -- DEFAULT function
    DepartmentID INT NOT NULL,

    -- Named Constraints (Best Practice)
    CONSTRAINT UQ_Employees_NationalID UNIQUE (NationalID),
    CONSTRAINT UQ_Employees_Email UNIQUE (Email),
    CONSTRAINT CHK_Employees_Age CHECK (Age >= 18 AND Age <= 70),
    CONSTRAINT CHK_Employees_Salary CHECK (Salary > 0),
    CONSTRAINT FK_Employees_Departments FOREIGN KEY (DepartmentID)
        REFERENCES Departments(DepartmentID)
        ON DELETE CASCADE                          -- If Dept is deleted, remove employees
);
GO




-- ===> 3. Hands-On Execution & Constraint Validation


-- A. Inserting Valid Data

-- Insert Parent Records
INSERT INTO Departments (DeptName) 
VALUES ('Human Resources'), ('Engineering'), ('Finance');

-- View generated IDENTITY values (10, 20, 30)
SELECT * FROM Departments;

-- Insert Valid Employee Data
INSERT INTO Employees (NationalID, FirstName, LastName, Email, Age, Salary, DepartmentID)
VALUES 
('NAT-1001', 'Alice', 'Smith', 'alice@company.com', 29, 75000.00, 20),
('NAT-1002', 'Bob', 'Jones', 'bob@company.com', 41, 92000.00, 20);

SELECT * FROM Employees;



-- B. Testing Constraint Violations (Run one by one)

-- ❌ Test 1: UNIQUE Constraint Violation (Duplicate Email)
INSERT INTO Employees (NationalID, FirstName, LastName, Email, Age, Salary, DepartmentID)
VALUES ('NAT-1003', 'Charlie', 'Brown', 'alice@company.com', 30, 50000.00, 10);
-- Error: Violation of UNIQUE KEY constraint 'UQ_Employees_Email'.

-- ❌ Test 2: CHECK Constraint Violation (Underage)
INSERT INTO Employees (NationalID, FirstName, LastName, Email, Age, Salary, DepartmentID)
VALUES ('NAT-1004', 'David', 'Miller', 'david@company.com', 16, 40000.00, 10);
-- Error: The INSERT statement conflicted with the CHECK constraint 'CHK_Employees_Age'.

-- ❌ Test 3: FOREIGN KEY Constraint Violation (Non-existent DepartmentID = 99)
INSERT INTO Employees (NationalID, FirstName, LastName, Email, Age, Salary, DepartmentID)
VALUES ('NAT-1005', 'Eva', 'Green', 'eva@company.com', 35, 65000.00, 99);
-- Error: The INSERT statement conflicted with the FOREIGN KEY constraint 'FK_Employees_Departments'.



-- 4. Altering Existing Constraints

-- Add a CHECK constraint to an existing table
ALTER TABLE Employees
ADD CONSTRAINT CHK_Employees_EmailFormat 
CHECK (Email LIKE '%@%.%');
GO

-- Drop a constraint
ALTER TABLE Employees
DROP CONSTRAINT CHK_Employees_Salary;
GO




-- 2. SQL Practice Setup

USE PracticeDB;
GO

-- Cleanup if table already exists
IF OBJECT_ID('dbo.Products', 'U') IS NOT NULL DROP TABLE dbo.Products;
GO

-- Create target table
CREATE TABLE Products (
    ProductID INT IDENTITY(1,1) PRIMARY KEY,
    ProductName NVARCHAR(100) NOT NULL,
    Category NVARCHAR(50) NOT NULL,
    UnitPrice DECIMAL(10,2) NOT NULL,
    StockQuantity INT NOT NULL DEFAULT 0,
    IsDiscontinued BIT NOT NULL DEFAULT 0
);
GO



-- 3. Practice Operations

-- ====>  A. CREATE (INSERT) 

-- 1. Insert a single row (Specifying columns)
INSERT INTO Products (ProductName, Category, UnitPrice, StockQuantity)
VALUES ('Mechanical Keyboard', 'Electronics', 89.99, 45);

-- 2. Insert multiple rows in a single batch
INSERT INTO Products (ProductName, Category, UnitPrice, StockQuantity)
VALUES 
    ('Wireless Mouse', 'Electronics', 25.50, 120),
    ('Ergonomic Chair', 'Furniture', 249.99, 15),
    ('Desk Lamp', 'Furniture', 34.00, 50),
    ('USB-C Cable', 'Electronics', 12.00, 200);

-- 3. Insert and capture generated keys using the OUTPUT clause
INSERT INTO Products (ProductName, Category, UnitPrice, StockQuantity)
OUTPUT inserted.ProductID, inserted.ProductName
VALUES ('Gaming Monitor 27"', 'Electronics', 320.00, 20);
GO


--- ===> B. READ (SELECT)

-- 1. Read all columns and rows
SELECT * FROM Products;

-- 2. Select specific columns with aliases & calculated columns
SELECT 
    ProductName,
    UnitPrice,
    StockQuantity,
    (UnitPrice * StockQuantity) AS TotalInventoryValue
FROM Products;

-- 3. Filter with WHERE conditions
SELECT ProductName, Category, UnitPrice 
FROM Products
WHERE Category = 'Electronics' AND UnitPrice > 30.00;

-- 4. Sort results with ORDER BY
SELECT ProductName, UnitPrice, StockQuantity
FROM Products
ORDER BY UnitPrice DESC;
GO


--- C. UPDATE (UPDATE)

-- 1. Update a single column for a specific record
UPDATE Products
SET UnitPrice = 79.99
WHERE ProductID = 1;

-- 2. Update multiple columns at once
UPDATE Products
SET StockQuantity = StockQuantity + 25,
    UnitPrice = 29.99
WHERE ProductName = 'Wireless Mouse';

-- 3. Conditional Update based on criteria
UPDATE Products
SET IsDiscontinued = 1
WHERE StockQuantity = 0;

-- Verify updates
SELECT * FROM Products;
GO



-- D. DELETE (DELETE)


-- 1. Delete a single record using Primary Key
DELETE FROM Products
WHERE ProductID = 5; -- Deletes 'Gaming Monitor 27"'

-- 2. Delete rows matching a condition
DELETE FROM Products
WHERE Category = 'Furniture' AND UnitPrice < 40.00; -- Deletes 'Desk Lamp'

-- 3. Safely capture deleted rows using the OUTPUT clause
DELETE FROM Products
OUTPUT deleted.ProductID, deleted.ProductName, deleted.UnitPrice
WHERE IsDiscontinued = 1;

-- Verify final state
SELECT * FROM Products;
GO


--- 4. DELETE vs TRUNCATE


-- Option A: DELETE (Slower, logs row-by-row, preserves IDENTITY counter)
DELETE FROM Products;

-- Option B: TRUNCATE (Faster, deallocates pages, RESETS IDENTITY back to seed)
TRUNCATE TABLE Products;



-- Level 5 — SELECT mastery

--- 2. Practice Environment Setup

USE PracticeDB;
GO

IF OBJECT_ID('dbo.Customers', 'U') IS NOT NULL DROP TABLE dbo.Customers;
GO

CREATE TABLE Customers (
    CustomerID INT IDENTITY(1,1) PRIMARY KEY,
    FirstName NVARCHAR(50) NOT NULL,
    LastName NVARCHAR(50) NOT NULL,
    Country NVARCHAR(50) NOT NULL,
    City NVARCHAR(50) NOT NULL,
    Score INT NULL,
    Email NVARCHAR(100) NULL
);
GO

INSERT INTO Customers (FirstName, LastName, Country, City, Score, Email) VALUES
('John', 'Doe', 'USA', 'New York', 85, 'john.doe@example.com'),
('Jane', 'Smith', 'USA', 'Chicago', NULL, 'jane.smith@example.com'),
('Alice', 'Johnson', 'Canada', 'Toronto', 92, 'alice.j@domain.ca'),
('Bob', 'Williams', 'UK', 'London', 45, NULL),
('Charlie', 'Brown', 'USA', 'New York', 78, 'charlie@example.com'),
('David', 'Jones', 'UK', 'Manchester', 85, 'david.j@domain.uk'),
('Emma', 'Miller', 'Germany', 'Berlin', 95, 'emma.m@domain.de'),
('Frank', 'Davis', 'Canada', 'Vancouver', 60, NULL),
('Grace', 'Wilson', 'USA', 'Chicago', 88, 'grace.w@example.com');
GO



-- 3. Practical SQL Script

-- A. Logical Operators & Value Filtering (AND, OR, NOT, IN, BETWEEN)

-- 1. Combine AND, OR, and NOT (Use parentheses to control precedence)
SELECT * FROM Customers
WHERE (Country = 'USA' OR Country = 'Canada')
  AND NOT (City = 'Chicago');

-- 2. Filter using IN / NOT IN
SELECT * FROM Customers
WHERE Country IN ('USA', 'UK', 'Germany');

-- 3. Range filtering with BETWEEN (Inclusive)
SELECT FirstName, LastName, Score FROM Customers
WHERE Score BETWEEN 70 AND 90;


-- B. Pattern Matching (LIKE) & Null Handling (IS NULL)

-- 1. LIKE Wildcards:
-- '%' matches any sequence of characters
-- '_' matches a single character
SELECT * FROM Customers
WHERE Email LIKE '%@example.com';       -- Ends with @example.com

SELECT * FROM Customers
WHERE FirstName LIKE 'J___';           -- Starts with J followed by exactly 3 letters (John, Jane)

-- 2. Handling NULL values properly (Never use = NULL)
SELECT * FROM Customers
WHERE Score IS NULL;

SELECT * FROM Customers
WHERE Email IS NOT NULL;



-- C. Result Ordering, Deduplication, and Top Records (ORDER BY, DISTINCT, TOP)

-- 1. DISTINCT values
SELECT DISTINCT Country FROM Customers;

-- 2. ORDER BY multiple columns (Score descending, then LastName ascending)
SELECT FirstName, LastName, Score FROM Customers
WHERE Score IS NOT NULL
ORDER BY Score DESC, LastName ASC;

-- 3. TOP N records
SELECT TOP (3) FirstName, LastName, Score 
FROM Customers
WHERE Score IS NOT NULL
ORDER BY Score DESC;


-- D. Result Set Pagination (OFFSET ... FETCH)

-- Page 1: Fetch first 3 records (Skip 0, Take 3)
SELECT CustomerID, FirstName, LastName, Score
FROM Customers
ORDER BY CustomerID
OFFSET 0 ROWS FETCH NEXT 3 ROWS ONLY;

-- Page 2: Fetch next 3 records (Skip 3, Take 3)
SELECT CustomerID, FirstName, LastName, Score
FROM Customers
ORDER BY CustomerID
OFFSET 3 ROWS FETCH NEXT 3 ROWS ONLY;

-- Page 3: Fetch next 3 records (Skip 6, Take 3)
SELECT CustomerID, FirstName, LastName, Score
FROM Customers
ORDER BY CustomerID
OFFSET 6 ROWS FETCH NEXT 3 ROWS ONLY;


-- 2. Practice Environment Setup

USE PracticeDB;
GO

IF OBJECT_ID('dbo.EmployeeDetails', 'U') IS NOT NULL DROP TABLE dbo.EmployeeDetails;
GO

CREATE TABLE EmployeeDetails (
    EmpID INT IDENTITY(1,1) PRIMARY KEY,
    FullName NVARCHAR(100) NOT NULL,
    Email NVARCHAR(100) NULL,
    HireDate DATE NOT NULL,
    BaseSalary DECIMAL(10,2) NOT NULL,
    Bonus DECIMAL(10,2) NULL,
    SalesTarget INT NOT NULL,
    ActualSales INT NOT NULL
);
GO

INSERT INTO EmployeeDetails (FullName, Email, HireDate, BaseSalary, Bonus, SalesTarget, ActualSales) VALUES
('  john DOE  ', 'john.doe@company.com', '2020-03-15', 75000.456, 5000.00, 100, 120),
('jane Smith', 'JANE.SMITH@COMPANY.COM', '2022-07-01', 82000.123, NULL, 150, 150),
('  alice JOHNSON ', NULL, '2018-11-20', 95000.000, 12000.50, 200, 180),
('bob Williams', 'bob.w@company.com', '2024-01-10', 60000.890, 0.00, 80, 80);
GO



-- 3. Practical SQL Scripts

--->> A. String Functions

SELECT 
    -- Cleaning whitespace and standardizing casing
    FullName AS RawName,
    TRIM(FullName) AS TrimmedName,
    UPPER(TRIM(FullName)) AS UpperName,
    LOWER(TRIM(FullName)) AS LowerName,
    LEN(TRIM(FullName)) AS NameLength,

    -- Extracting parts of strings
    LEFT(TRIM(FullName), 4) AS First4Chars,
    RIGHT(TRIM(FullName), 4) AS Last4Chars,
    
    -- Parsing domain from email using CHARINDEX and SUBSTRING
    Email,
    CHARINDEX('@', Email) AS AtSymbolPosition,
    SUBSTRING(Email, CHARINDEX('@', Email) + 1, LEN(Email)) AS EmailDomain,

    -- Replacing and Concatenating
    REPLACE(Email, 'company.com', 'enterprise.org') AS UpdatedEmail,
    CONCAT(TRIM(FullName), ' <', ISNULL(Email, 'No Email'), '>') AS FormattedContact
FROM EmployeeDetails;


--> B. Date Functions

SELECT 
    EmpID,
    HireDate,
    
    -- Current system dates
    GETDATE() AS CurrentDateTime,
    SYSDATETIME() AS HighPrecisionDateTime,
    
    -- Date Math
    DATEADD(year, 1, HireDate) AS ProbationEnd,
    DATEDIFF(month, HireDate, GETDATE()) AS MonthsEmployed,
    DATEDIFF(year, HireDate, GETDATE()) AS YearsEmployed,
    
    -- Date Extractions
    YEAR(HireDate) AS HireYear,
    MONTH(HireDate) AS HireMonth,
    DAY(HireDate) AS HireDay,
    DATENAME(weekday, HireDate) AS DayOfWeekHired,
    DATENAME(month, HireDate) AS MonthNameHired,
    
    -- End of month calculation
    EOMONTH(HireDate) AS EndOfHireMonth
FROM EmployeeDetails;


-- C. Numeric Functions

SELECT 
    BaseSalary,
    
    -- Rounding variations
    ROUND(BaseSalary, 2) AS Rounded2Decimals,
    ROUND(BaseSalary, 0) AS RoundedWholeNumber,
    CEILING(BaseSalary) AS CeilSalary,  -- Rounds up
    FLOOR(BaseSalary) AS FloorSalary,    -- Rounds down
    
    -- Math operations
    ABS(-150.50) AS AbsoluteValue,
    POWER(2, 3) AS TwoToPowerThree,
    SQRT(ActualSales) AS SalesSquareRoot
FROM EmployeeDetails;


--> D. Conditional Functions (CASE, IIF, COALESCE, ISNULL, NULLIF)

SELECT 
    FullName,
    BaseSalary,
    Bonus,
    
    -- NULL Handling: ISNULL vs COALESCE
    ISNULL(Bonus, 0) AS SafeBonus_ISNULL,
    COALESCE(Bonus, BaseSalary * 0.05, 0) AS SafeBonus_COALESCE, -- Tries Bonus, fallback to 5% salary
    
    -- Preventing Division by Zero using NULLIF
    -- If SalesTarget = ActualSales, NULLIF turns bottom value to NULL to avoid divide-by-zero
    ActualSales,
    SalesTarget,
    (ActualSales * 100.0) / NULLIF(SalesTarget, 0) AS TargetCompletionPercentage,

    -- Ternary Logic with IIF
    IIF(ActualSales >= SalesTarget, 'Target Met', 'Underperformed') AS Performance_IIF,

    -- Multi-branch Logic with CASE
    CASE 
        WHEN ActualSales > SalesTarget THEN 'Exceeded Target'
        WHEN ActualSales = SalesTarget THEN 'Met Target Exactly'
        ELSE 'Needs Improvement'
    END AS Performance_CASE
FROM EmployeeDetails;


---> 3. Practice Setup Script

USE PracticeDB;
GO

IF OBJECT_ID('dbo.Orders', 'U') IS NOT NULL DROP TABLE dbo.Orders;
GO

CREATE TABLE Orders (
    OrderID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerRegion NVARCHAR(50) NOT NULL,
    Category NVARCHAR(50) NOT NULL,
    OrderAmount DECIMAL(10,2) NULL, -- Includes NULLs to show behavior
    OrderDate DATE NOT NULL
);
GO

INSERT INTO Orders (CustomerRegion, Category, OrderAmount, OrderDate) VALUES
('North America', 'Electronics', 1200.00, '2026-01-15'),
('North America', 'Electronics', 800.00,  '2026-01-20'),
('North America', 'Furniture',   450.00,  '2026-02-05'),
('North America', 'Furniture',   NULL,    '2026-02-10'), -- NULL amount
('Europe',        'Electronics', 1500.00, '2026-01-18'),
('Europe',        'Electronics', 950.00,  '2026-02-12'),
('Europe',        'Furniture',   300.00,  '2026-02-15'),
('Asia',          'Electronics', 2100.00, '2026-01-10'),
('Asia',          'Electronics', 1800.00, '2026-02-22'),
('Asia',          'Furniture',   NULL,    '2026-02-25'); -- NULL amount
GO



---> 4. Practical SQL Queries

-- A. Basic Aggregations Across the Whole Table

SELECT 
    COUNT(*) AS TotalRows,
    COUNT(OrderAmount) AS NonNullOrderCount,
    SUM(OrderAmount) AS TotalRevenue,
    AVG(OrderAmount) AS AverageOrderValue,
    MIN(OrderAmount) AS SmallestOrder,
    MAX(OrderAmount) AS LargestOrder,
    MIN(OrderDate) AS EarliestOrderDate,
    MAX(OrderDate) AS LatestOrderDate
FROM Orders;


------

-- B. Grouping by Single & Multiple Columns (GROUP BY)


-- 1. Summarize by a single column (CustomerRegion)
SELECT 
    CustomerRegion,
    COUNT(*) AS TotalOrders,
    SUM(OrderAmount) AS RegionalRevenue,
    AVG(OrderAmount) AS AvgRegionalOrder
FROM Orders
GROUP BY CustomerRegion
ORDER BY RegionalRevenue DESC;

-- 2. Summarize by multiple columns (CustomerRegion AND Category)
SELECT 
    CustomerRegion,
    Category,
    COUNT(*) AS ItemCount,
    SUM(OrderAmount) AS CategoryRevenue
FROM Orders
GROUP BY CustomerRegion, Category
ORDER BY CustomerRegion, Category;


--- C. Filtering Groups with HAVING vs WHERE

-- WHERE vs HAVING Example:
-- 1. WHERE filters individual rows (only consider Electronics orders)
-- 2. GROUP BY groups the remaining rows by region
-- 3. HAVING filters groups that generated over $2,000 in revenue
SELECT 
    CustomerRegion,
    SUM(OrderAmount) AS ElectronicsRevenue,
    COUNT(*) AS ElectronicsOrderCount
FROM Orders
WHERE Category = 'Electronics'              -- Row filter (before grouping)
GROUP BY CustomerRegion
HAVING SUM(OrderAmount) > 2000.00          -- Group filter (after grouping)
ORDER BY ElectronicsRevenue DESC;



----> D. Counting Distinct Values inside Aggregates

-- Count unique categories per region
SELECT 
    CustomerRegion,
    COUNT(Category) AS TotalCategoryEntries,
    COUNT(DISTINCT Category) AS UniqueCategoriesCount
FROM Orders
GROUP BY CustomerRegion;


----

-- 2. Practice Setup Script

USE PracticeDB;
GO

-- Clean up existing tables
IF OBJECT_ID('dbo.ProjectAssignments', 'U') IS NOT NULL DROP TABLE dbo.ProjectAssignments;
IF OBJECT_ID('dbo.Staff', 'U') IS NOT NULL DROP TABLE dbo.Staff;
IF OBJECT_ID('dbo.Dept', 'U') IS NOT NULL DROP TABLE dbo.Dept;
IF OBJECT_ID('dbo.Colors', 'U') IS NOT NULL DROP TABLE dbo.Colors;
IF OBJECT_ID('dbo.Sizes', 'U') IS NOT NULL DROP TABLE dbo.Sizes;
GO

-- 1. Departments Table
CREATE TABLE Dept (
    DeptID INT PRIMARY KEY,
    DeptName NVARCHAR(50) NOT NULL
);

INSERT INTO Dept VALUES 
(10, 'Engineering'),
(20, 'Sales'),
(30, 'Marketing'),
(40, 'Legal'); -- No staff assigned here

-- 2. Staff Table (Contains ManagerID for Self Join)
CREATE TABLE Staff (
    StaffID INT PRIMARY KEY,
    Name NVARCHAR(50) NOT NULL,
    DeptID INT NULL,             -- NULL indicates no assigned department
    ManagerID INT NULL           -- Links back to Staff.StaffID
);

INSERT INTO Staff VALUES 
(1, 'Alice (VP)',    10, NULL),  -- Top Manager
(2, 'Bob (Dev)',     10, 1),     -- Reports to Alice
(3, 'Charlie (Dev)', 10, 1),     -- Reports to Alice
(4, 'David (Sales)', 20, NULL),  -- Sales Manager
(5, 'Eva (Sales)',   20, 4),     -- Reports to David
(6, 'Frank (Contractor)', NULL, NULL); -- No Dept, No Manager

-- 3. Product Combinations Tables (For Cross Join)
CREATE TABLE Sizes (SizeName NVARCHAR(10));
INSERT INTO Sizes VALUES ('Small'), ('Medium'), ('Large');

CREATE TABLE Colors (ColorName NVARCHAR(10));
INSERT INTO Colors VALUES ('Red'), ('Blue');
GO


----> 3. Practical SQL Queries

SELECT 
    e.StaffID,
    e.Name AS EmployeeName,
    d.DeptID,
    d.DeptName
FROM Staff e
INNER JOIN Dept d ON e.DeptID = d.DeptID;



-- B. LEFT JOIN (All Left + Matching Right)

SELECT 
    e.StaffID,
    e.Name AS EmployeeName,
    ISNULL(d.DeptName, 'Unassigned / Contractor') AS Department
FROM Staff e
LEFT JOIN Dept d ON e.DeptID = d.DeptID;


-- C. RIGHT JOIN (All Right + Matching Left)

SELECT 
    d.DeptID,
    d.DeptName,
    e.Name AS EmployeeName
FROM Staff e
RIGHT JOIN Dept d ON e.DeptID = d.DeptID;


-- D. FULL OUTER JOIN (Everything from Both Sides)

SELECT 
    e.Name AS EmployeeName,
    d.DeptName
FROM Staff e
FULL OUTER JOIN Dept d ON e.DeptID = d.DeptID;


-- E. SELF JOIN (Joining Table to Itself)

SELECT 
    emp.Name AS Employee,
    ISNULL(mgr.Name, 'Top Executive / No Manager') AS Manager
FROM Staff emp
LEFT JOIN Staff mgr ON emp.ManagerID = mgr.StaffID;


-- F. CROSS JOIN (Cartesian Product)

SELECT 
    s.SizeName,
    c.ColorName,
    CONCAT(s.SizeName, ' - ', c.ColorName) AS SKU_Variant
FROM Sizes s
CROSS JOIN Colors c;


-- 4. Unmatched Records (Anti-Joins)

-- Find Departments that have NO assigned employees
SELECT 
    d.DeptID,
    d.DeptName
FROM Dept d
LEFT JOIN Staff e ON d.DeptID = e.DeptID
WHERE e.StaffID IS NULL;




----------==============================---------------

--- 2. Practice Setup Script

USE PracticeDB;
GO

-- Clean up existing tables
IF OBJECT_ID('dbo.Sales', 'U') IS NOT NULL DROP TABLE dbo.Sales;
IF OBJECT_ID('dbo.Emp', 'U') IS NOT NULL DROP TABLE dbo.Emp;
IF OBJECT_ID('dbo.Department', 'U') IS NOT NULL DROP TABLE dbo.Department;
GO

-- 1. Departments
CREATE TABLE Department (
    DeptID INT PRIMARY KEY,
    DeptName NVARCHAR(50) NOT NULL
);

INSERT INTO Department VALUES 
(10, 'Engineering'),
(20, 'Sales'),
(30, 'Marketing'),
(40, 'Research'); -- No staff assigned

-- 2. Employees
CREATE TABLE Emp (
    EmpID INT PRIMARY KEY,
    EmpName NVARCHAR(50) NOT NULL,
    DeptID INT NULL,
    Salary DECIMAL(10,2) NOT NULL
);

INSERT INTO Emp VALUES 
(1, 'Alice', 10, 95000.00),
(2, 'Bob', 10, 70000.00),
(3, 'Charlie', 20, 85000.00),
(4, 'David', 20, 60000.00),
(5, 'Eva', 30, 75000.00),
(6, 'Frank', NULL, 50000.00); -- Unassigned employee

-- 3. Sales Transactions
CREATE TABLE Sales (
    SaleID INT PRIMARY KEY,
    EmpID INT NOT NULL,
    SaleAmount DECIMAL(10,2) NOT NULL
);

INSERT INTO Sales VALUES 
(101, 3, 1200.00),
(102, 3, 3500.00),
(103, 4, 800.00);
GO


-- 3. Practical SQL Scripts

-- A. Scalar Subquery (Returns 1 Row, 1 Column)

SELECT 
    EmpID, 
    EmpName, 
    Salary,
    (SELECT AVG(Salary) FROM Emp) AS CompanyAvgSalary,
    Salary - (SELECT AVG(Salary) FROM Emp) AS DifferenceFromAvg
FROM Emp
WHERE Salary > (SELECT AVG(Salary) FROM Emp);


-- B. Multi-Row Subquery (IN / NOT IN)

-- 1. Get employees working in Engineering or Sales using IN
SELECT EmpName, Salary, DeptID
FROM Emp
WHERE DeptID IN (
    SELECT DeptID 
    FROM Department 
    WHERE DeptName IN ('Engineering', 'Sales')
);

-- 2. Get employees who have zero sales recorded using NOT IN
SELECT EmpName, Salary 
FROM Emp
WHERE EmpID NOT IN (
    SELECT DISTINCT EmpID 
    FROM Sales
);


-- C. Correlated Subquery

SELECT 
    e.EmpID, 
    e.EmpName, 
    e.DeptID, 
    e.Salary
FROM Emp e
WHERE e.Salary > (
    -- Outer query column (e.DeptID) passed into inner query
    SELECT AVG(inner_e.Salary) 
    FROM Emp inner_e 
    WHERE inner_e.DeptID = e.DeptID
);


-- D. Existence Checks (EXISTS / NOT EXISTS)

-- 1. EXISTS: Find departments that have at least one assigned employee
SELECT d.DeptID, d.DeptName
FROM Department d
WHERE EXISTS (
    SELECT 1 
    FROM Emp e 
    WHERE e.DeptID = d.DeptID
);

-- 2. NOT EXISTS: Find departments with NO assigned employees (e.g., 'Research')
SELECT d.DeptID, d.DeptName
FROM Department d
WHERE NOT EXISTS (
    SELECT 1 
    FROM Emp e 
    WHERE e.DeptID = d.DeptID
);


