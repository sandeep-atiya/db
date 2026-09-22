/* ============================================================
   LEVEL 05 - SELECT MASTERY  |  02_Practice_Sorting_Top_Paging.sql
   ------------------------------------------------------------
   Topics : ORDER BY (many columns, ASC/DESC mix, expression, alias,
            ordinal, NULL order, ORDER BY in subquery), TOP (n) /
            PERCENT / WITH TIES, DISTINCT (one & many columns, vs
            GROUP BY), OFFSET ... FETCH paging, column aliases,
            calculated columns, string concatenation, CASE preview

   HOW TO PRACTICE: run block by block, predict the output first.
   Everything is READ-ONLY on the real tables.
   ============================================================ */

USE SQLPractice;
GO


/* ============================================================
   1. ORDER BY
   ============================================================ */
-- Without ORDER BY the row order is NOT guaranteed - not even with a clustered index.
-- ORDER BY runs after SELECT, so it may use column aliases; ASC is the default.

-- 1a. One column, ascending (default)
SELECT EmployeeName, Salary FROM dbo.Employees ORDER BY Salary;             -- Anjali 48000 first ... Sneha 90000 last
GO

-- 1b. Several columns with an ASC / DESC mix: department, then highest salary first, then name as tiebreaker
SELECT EmployeeName, DepartmentID, Salary
FROM dbo.Employees
ORDER BY DepartmentID ASC, Salary DESC, EmployeeName ASC;
-- Anjali (NULL dept) first, then IT: Rahul, Amit, Pooja (Amit before Pooja: same salary, name decides), Sales: Priya, Vikram, Neha ...
GO

-- 1c. By an expression
SELECT EmployeeName, LEN(EmployeeName) AS NameLength
FROM dbo.Employees
ORDER BY LEN(EmployeeName), EmployeeName;                                   -- Amit, Neha, Ravi (4), Karan ... (5), Anjali, Deepak, Vikram (6)
GO

-- 1d. By an alias (allowed: ORDER BY runs after SELECT)
SELECT EmployeeName, Salary * 12 AS AnnualSalary
FROM dbo.Employees
ORDER BY AnnualSalary DESC;                                                 -- Sneha 1080000 first
GO

-- 1e. By ordinal position - works, but DISCOURAGED: adding a column to the SELECT silently changes the sort
SELECT EmployeeName, Salary FROM dbo.Employees ORDER BY 2 DESC;             -- 2 = Salary
GO

-- 1f. By a column that is NOT in the SELECT list (fine, unless DISTINCT is used - see 3f)
SELECT EmployeeName FROM dbo.Employees ORDER BY HireDate;                   -- Sneha (2020) first, Anjali (2024-05) last
GO

-- 1g. NULL sorts as the SMALLEST value: first in ASC, last in DESC
SELECT EmployeeName, DepartmentID FROM dbo.Employees ORDER BY DepartmentID;        -- Anjali (NULL) is row 1
SELECT EmployeeName, DepartmentID FROM dbo.Employees ORDER BY DepartmentID DESC;   -- Anjali (NULL) is row 12
GO
-- Want ASC but NULLs LAST? Sort by "is it null" first, then by the value
SELECT EmployeeName, DepartmentID
FROM dbo.Employees
ORDER BY CASE WHEN DepartmentID IS NULL THEN 1 ELSE 0 END, DepartmentID;           -- Anjali is row 12
GO

-- 1h. ORDER BY is NOT allowed inside a subquery / derived table / view / CTE (unless TOP or OFFSET is there)
--     (compile-time error -> EXEC lets CATCH show it)
BEGIN TRY
    EXEC ('SELECT x.EmployeeName FROM (SELECT EmployeeName FROM dbo.Employees ORDER BY EmployeeName) AS x;');
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO
-- Sort in the OUTER query instead. (TOP (100) PERCENT ... ORDER BY inside is accepted but does NOT guarantee order.)
SELECT x.EmployeeName
FROM (SELECT EmployeeName FROM dbo.Employees) AS x
ORDER BY x.EmployeeName;                                                    -- Amit first, Vikram last
GO


/* ============================================================
   2. TOP
   ============================================================ */

-- 2a. TOP (n) + ORDER BY = "the n highest / lowest". Always write the parentheses (required in DML, good habit).
SELECT TOP (3) EmployeeName, Salary FROM dbo.Employees ORDER BY Salary DESC;   -- Sneha 90000, Rahul 85000, Priya 75000
SELECT TOP (1) EmployeeName, Salary FROM dbo.Employees ORDER BY Salary;        -- Anjali 48000
GO

-- 2b. TOP without ORDER BY = "any 3 rows" (usually the first found, never guaranteed)
SELECT TOP (3) EmployeeName FROM dbo.Employees;
GO

-- 2c. TOP (n) PERCENT: rounds UP. 30 % of 12 rows = 3.6 -> 4 rows
SELECT TOP (30) PERCENT EmployeeName, Salary FROM dbo.Employees ORDER BY Salary DESC;   -- 4 rows: Sneha, Rahul, Priya, Deepak
GO

-- 2d. WITH TIES: if the last row has "twins" with the same ORDER BY value, include them too.
--     Sorted by salary DESC the 6th row is 65000 - and both Amit and Pooja earn 65000.
SELECT TOP (6)           EmployeeName, Salary FROM dbo.Employees ORDER BY Salary DESC;   -- 6 rows (Amit OR Pooja, arbitrary)
SELECT TOP (6) WITH TIES EmployeeName, Salary FROM dbo.Employees ORDER BY Salary DESC;   -- 7 rows (Amit AND Pooja)
GO
-- WITH TIES REQUIRES an ORDER BY. Classic use: "the highest paid, and everyone tied with them":
SELECT TOP (1) WITH TIES EmployeeName, DepartmentID FROM dbo.Employees ORDER BY DepartmentID DESC;   -- 2 rows: Karan, Meera (both dept 5)
GO

-- 2e. TOP with a variable
DECLARE @n INT = 2;
SELECT TOP (@n) ProductName, Price FROM dbo.Products ORDER BY Price DESC;    -- Laptop 75000, Monitor 25000
GO


/* ============================================================
   3. DISTINCT
   ============================================================ */

-- 3a. One column: each value once
SELECT DISTINCT Category FROM dbo.Products;                                 -- Electronics, Furniture, Stationery (3)
SELECT DISTINCT City     FROM dbo.Customers;                                -- 5 cities
GO

-- 3b. Several columns: each COMBINATION once (DISTINCT applies to the whole row, not to the first column)
SELECT DISTINCT DepartmentID, ManagerID
FROM dbo.Employees
ORDER BY DepartmentID, ManagerID;                                           -- 10 rows (12 employees, 2 duplicate pairs)
GO

-- 3c. NULLs count as ONE value for DISTINCT
SELECT DISTINCT Email FROM dbo.Customers;                                   -- 7 rows: 6 emails + 1 NULL
GO

-- 3d. COUNT(DISTINCT col)
SELECT COUNT(DISTINCT City) AS Cities, COUNT(City) AS NonNullCities, COUNT(*) AS Rows_ FROM dbo.Customers;   -- 5, 8, 8
GO

-- 3e. DISTINCT vs GROUP BY (preview of Level 07): same rows, but GROUP BY can also count / sum
SELECT DISTINCT Category FROM dbo.Products;                                 -- 3 rows
SELECT Category FROM dbo.Products GROUP BY Category;                        -- the same 3 rows
SELECT Category, COUNT(*) AS Products FROM dbo.Products GROUP BY Category;  -- Electronics 6, Furniture 3, Stationery 2
GO

-- 3f. With DISTINCT, ORDER BY may only use columns from the SELECT list (compile-time error -> EXEC)
BEGIN TRY
    EXEC ('SELECT DISTINCT DepartmentID FROM dbo.Employees ORDER BY Salary;');
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO


/* ============================================================
   4. OFFSET ... FETCH  (paging, SQL Server 2012+)
   ============================================================ */
-- ORDER BY <deterministic sort> OFFSET <skip> ROWS FETCH NEXT <take> ROWS ONLY

-- 4a. OFFSET / FETCH needs an ORDER BY (compile-time error -> EXEC)
BEGIN TRY
    EXEC ('SELECT EmployeeName FROM dbo.Employees OFFSET 5 ROWS FETCH NEXT 5 ROWS ONLY;');
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO

-- 4b. Pages of 5, ordered by EmployeeID
SELECT EmployeeID, EmployeeName FROM dbo.Employees ORDER BY EmployeeID OFFSET 0  ROWS FETCH NEXT 5 ROWS ONLY;   -- page 1: 101-105
SELECT EmployeeID, EmployeeName FROM dbo.Employees ORDER BY EmployeeID OFFSET 5  ROWS FETCH NEXT 5 ROWS ONLY;   -- page 2: 106-110
SELECT EmployeeID, EmployeeName FROM dbo.Employees ORDER BY EmployeeID OFFSET 10 ROWS FETCH NEXT 5 ROWS ONLY;   -- page 3: 111, 112 (only 2 left)
GO

-- 4c. The page formula with variables:  skip = (PageNo - 1) * PageSize
DECLARE @PageSize INT = 5, @PageNo INT = 3;
SELECT EmployeeID, EmployeeName
FROM dbo.Employees
ORDER BY EmployeeID
OFFSET (@PageNo - 1) * @PageSize ROWS
FETCH NEXT @PageSize ROWS ONLY;                                             -- 111 Deepak, 112 Meera
SELECT CEILING(COUNT(*) * 1.0 / @PageSize) AS TotalPages FROM dbo.Employees; -- 3
GO

-- 4d. OFFSET alone = skip n rows, return all the rest
SELECT EmployeeID, EmployeeName FROM dbo.Employees ORDER BY EmployeeID OFFSET 10 ROWS;   -- 111, 112
GO

-- 4e. The sort must be DETERMINISTIC or a row can appear on two pages / on none.
--     Salary alone is not unique (Amit = Pooja = 65000): add EmployeeID as a tiebreaker.
SELECT EmployeeName, Salary, EmployeeID
FROM dbo.Employees
ORDER BY Salary DESC, EmployeeID
OFFSET 5 ROWS FETCH NEXT 5 ROWS ONLY;                                       -- page 2: Amit, Pooja, Vikram, Ravi, Meera
GO
-- TOP vs OFFSET/FETCH: TOP cannot skip rows; the two cannot be combined in one query;
-- FETCH FIRST = FETCH NEXT (synonyms).


/* ============================================================
   5. ALIASES, CALCULATED COLUMNS, CONCATENATION, CASE
   ============================================================ */

-- 5a. Three ways to alias a column (+ brackets or quotes when the alias has spaces); AS is optional but clearer
SELECT EmployeeName AS Name,                -- ANSI style (recommended)
       Salary       MonthlySalary,          -- AS omitted
       Annual     = Salary * 12,            -- T-SQL "alias = expression" style
       Salary * 12 AS [Annual Salary],      -- alias with a space
       Salary / 12 AS "Per Month"           -- double quotes work only with QUOTED_IDENTIFIER ON (default in SSMS)
FROM dbo.Employees
WHERE EmployeeID = 101;                     -- Rahul 85000 1020000 1020000 7083.333333
GO
-- Table aliases (used in every join from Level 08 on):
SELECT e.EmployeeName, e.Salary FROM dbo.Employees AS e WHERE e.DepartmentID = 4;   -- Sneha, Deepak
GO

-- 5b. Calculated columns: any expression on the row's columns
SELECT ProductName, Price, Stock, Price * Stock AS StockValue
FROM dbo.Products
WHERE Category = 'Furniture';               -- Chair 160000, Desk 225000, Bookshelf 60000
GO
-- Integer division inside a calculation (Level 02 recap): Stock is INT
SELECT Stock, Stock / 3 AS IntDivision, Stock / 3.0 AS DecimalDivision
FROM dbo.Products WHERE ProductID = 2;      -- 100, 33, 33.333333
GO

-- 5c. String concatenation: + (NULL swallows everything), CONCAT (NULL -> ''), CONCAT_WS (2017+, separator, skips NULL)
SELECT CustomerName,
       CustomerName + ' <' + Email + '>'              AS WithPlus,      -- NULL for Farhan and Hina!
       CONCAT(CustomerName, ' <', Email, '>')         AS WithConcat,    -- 'Farhan Ali <>'
       CONCAT_WS(' - ', CustomerName, Email, City)    AS WithConcatWs   -- 'Farhan Ali - Mumbai' (NULL skipped)
FROM dbo.Customers
WHERE City = 'Mumbai';                      -- Bhavna, Farhan
GO
-- + with a number is a CONVERSION, not a concatenation: 'Salary: ' + 85000 fails, CONCAT converts for you
BEGIN TRY
    SELECT 'Salary: ' + Salary FROM dbo.Employees WHERE EmployeeID = 101;
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO
SELECT 'Salary: ' + CAST(Salary AS VARCHAR(20)) AS WithCast,
       CONCAT('Salary: ', Salary)              AS WithConcat
FROM dbo.Employees WHERE EmployeeID = 101;   -- Salary: 85000.00  (both)
GO

-- 5d. CASE in SELECT (preview of Level 06): a searched CASE turns numbers into labels
SELECT EmployeeName, Salary,
       CASE WHEN Salary >= 80000 THEN 'High'
            WHEN Salary >= 60000 THEN 'Mid'
            ELSE 'Low'
       END AS SalaryBand
FROM dbo.Employees
ORDER BY Salary DESC;                        -- High: Sneha, Rahul | Mid: Priya ... Ravi (7) | Low: Meera, Neha, Anjali
GO
-- Simple CASE (compares one expression to values) and CASE inside ORDER BY for a custom sort
SELECT OrderID, Status,
       CASE Status WHEN 'Pending'   THEN 'Waiting'
                   WHEN 'Completed' THEN 'Done'
                   ELSE 'Dropped' END AS StatusLabel
FROM dbo.Orders
ORDER BY CASE Status WHEN 'Pending' THEN 1 WHEN 'Completed' THEN 2 ELSE 3 END, OrderID;
-- 1015, 1017 (Pending) first, then the 16 Completed, then 1006 (Cancelled) last
GO

-- 5e. Everything together: a small report
SELECT CONCAT(ProductName, ' (', Category, ')') AS Label,
       Price,
       Stock,
       Price * Stock AS StockValue,
       CASE WHEN Stock = 0  THEN 'OUT'
            WHEN Stock < 20 THEN 'LOW'
            ELSE 'OK' END   AS StockStatus
FROM dbo.Products
ORDER BY StockValue DESC;
-- Laptop 750000 LOW, Monitor 625000 OK, Desk 225000 LOW, Chair 160000 OK, Webcam 135000 OK,
-- Keyboard 125000 OK, Mouse 100000 OK, Bookshelf 60000 LOW, Notebook 25000 OK, Pen 10000 OK, Headphones 0 OUT
GO

/* ------------------------------------------------------------
   DONE. Next: Exercises.sql
   ------------------------------------------------------------ */
