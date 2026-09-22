/* ============================================================
   LEVEL 05 - SELECT MASTERY  |  Exercises.sql
   ------------------------------------------------------------
   Try each question in the "YOUR ANSWERS" area FIRST.
   Then scroll down to SOLUTIONS and compare.
   All questions are READ-ONLY on the SQLPractice tables.
   ============================================================ */

USE SQLPractice;
GO

/* ------------------------------------------------------------
   QUESTIONS
   ------------------------------------------------------------
   Q1.  Employees of department 2 who earn more than 60000 (name, salary).

   Q2.  Employees of department 1 OR 2 who earn more than 70000.
        First write it WITHOUT parentheses and count the rows, then
        write it correctly. Explain the difference in a comment.

   Q3.  Customers who live neither in Delhi nor in Mumbai (use NOT IN).

   Q4.  Orders placed in March 2025. Write it once with BETWEEN and once
        with the safe  >= ... AND < ...  pattern. Why is the second better?

   Q5.  Employees whose name starts with a letter from N to Z AND ends with 'a'.

   Q6.  Customers who have no email OR live in Delhi, sorted by name.
        (Hina must appear only once.)

   Q7.  Departments that have no employee. Write it with NOT IN and a subquery
        on dbo.Employees. It returns nothing - explain why in a comment and fix it.

   Q8.  The 3 most expensive products, then the top 30 percent most expensive
        products. How many rows does the second query return, and why?

   Q9.  The 6 best paid employees INCLUDING everyone tied with the 6th.
        How many rows?

   Q10. (a) How many different cities do customers live in?
        (b) How many different (DepartmentID, ManagerID) combinations exist
            in dbo.Employees? Show them.

   Q11. Page 2 of the employee list, page size 4, newest hire first
        (add EmployeeID as tiebreaker). Use variables for page size and number.

   Q12. Report for Electronics products: Label = "Name (Category)", Price,
        Stock, StockValue = Price * Stock, and StockStatus = OUT when stock
        is 0, LOW when below 20, otherwise OK. Highest StockValue first.
   ------------------------------------------------------------ */

-- YOUR ANSWERS HERE (write below, run, compare)










/* ============================================================
   SOLUTIONS
   ============================================================ */

-- Q1
SELECT EmployeeName, Salary
FROM dbo.Employees
WHERE DepartmentID = 2 AND Salary > 60000;                                  -- Priya 75000, Vikram 62000
GO

-- Q2
SELECT COUNT(*) AS WithoutParentheses
FROM dbo.Employees
WHERE DepartmentID = 1 OR DepartmentID = 2 AND Salary > 70000;              -- 4: AND binds first -> dept 1 (all) OR (dept 2 AND > 70000)
SELECT EmployeeName, DepartmentID, Salary
FROM dbo.Employees
WHERE (DepartmentID = 1 OR DepartmentID = 2) AND Salary > 70000;            -- 2 rows: Rahul, Priya
GO

-- Q3
SELECT CustomerName, City
FROM dbo.Customers
WHERE City NOT IN ('Delhi', 'Mumbai');                                      -- Divya (Pune), Esha (Bangalore), Gaurav (Chennai)
GO

-- Q4
SELECT OrderID, OrderDate FROM dbo.Orders
WHERE OrderDate BETWEEN '2025-03-01' AND '2025-03-31';                      -- 1007, 1008
SELECT OrderID, OrderDate FROM dbo.Orders
WHERE OrderDate >= '2025-03-01' AND OrderDate < '2025-04-01';               -- 1007, 1008
-- The half-open range also works on DATETIME columns (BETWEEN '...03-31' would drop rows after midnight on the 31st)
-- and does not depend on knowing the last day of the month.
GO

-- Q5
SELECT EmployeeName
FROM dbo.Employees
WHERE EmployeeName LIKE '[N-Z]%a';                                          -- Priya, Neha, Sneha, Pooja (4)
GO

-- Q6
SELECT CustomerName, Email, City
FROM dbo.Customers
WHERE Email IS NULL OR City = 'Delhi'
ORDER BY CustomerName;                                                      -- Aarav, Chirag, Farhan, Hina (4)
GO

-- Q7
SELECT DepartmentName FROM dbo.Departments
WHERE DepartmentID NOT IN (SELECT DepartmentID FROM dbo.Employees);         -- 0 rows: Anjali's NULL DepartmentID is in the list,
                                                                            -- so every comparison ends UNKNOWN
SELECT DepartmentName FROM dbo.Departments
WHERE DepartmentID NOT IN (SELECT DepartmentID FROM dbo.Employees WHERE DepartmentID IS NOT NULL);   -- Legal
GO

-- Q8
SELECT TOP (3) ProductName, Price FROM dbo.Products ORDER BY Price DESC;    -- Laptop, Monitor, Desk
SELECT TOP (30) PERCENT ProductName, Price FROM dbo.Products ORDER BY Price DESC;
-- 4 rows (Laptop, Monitor, Desk, Bookshelf): 30 % of 11 = 3.3, and PERCENT rounds UP
GO

-- Q9
SELECT TOP (6) WITH TIES EmployeeName, Salary
FROM dbo.Employees
ORDER BY Salary DESC;                                                       -- 7 rows: Amit and Pooja both earn 65000 (6th place)
GO

-- Q10
SELECT COUNT(DISTINCT City) AS DistinctCities FROM dbo.Customers;           -- 5
SELECT DISTINCT DepartmentID, ManagerID
FROM dbo.Employees
ORDER BY DepartmentID, ManagerID;                                           -- 10 rows
GO

-- Q11
DECLARE @PageSize INT = 4, @PageNo INT = 2;
SELECT EmployeeID, EmployeeName, HireDate
FROM dbo.Employees
ORDER BY HireDate DESC, EmployeeID
OFFSET (@PageNo - 1) * @PageSize ROWS
FETCH NEXT @PageSize ROWS ONLY;                                             -- Pooja, Amit, Ravi, Vikram
GO

-- Q12
SELECT CONCAT(ProductName, ' (', Category, ')') AS Label,
       Price, Stock,
       Price * Stock AS StockValue,
       CASE WHEN Stock = 0 THEN 'OUT' WHEN Stock < 20 THEN 'LOW' ELSE 'OK' END AS StockStatus
FROM dbo.Products
WHERE Category = 'Electronics'
ORDER BY StockValue DESC;
-- 6 rows: Laptop 750000 LOW, Monitor 625000 OK, Webcam 135000 OK, Keyboard 125000 OK, Mouse 100000 OK, Headphones 0 OUT
GO
