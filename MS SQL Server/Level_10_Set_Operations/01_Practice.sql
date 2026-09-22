/* ============================================================
   LEVEL 10 - SET OPERATIONS  |  01_Practice.sql
   ------------------------------------------------------------
   Topics : UNION, UNION ALL, INTERSECT, EXCEPT, the rules (column
            count, types, names, ORDER BY, TOP per branch), NULLs
            are equal for set operators, precedence, practical uses:
            contact list, cities, compare two tables (EXCEPT both
            ways), UNION ALL lookup list, UNION vs JOIN,
            UNION ALL + GROUP BY instead of FULL OUTER JOIN.

   HOW TO PRACTICE: run block by block, predict the output first.
   Creates ONE copy table dbo.L10_Products_Copy, dropped at the end.
   ============================================================ */

USE SQLPractice;
GO
DROP TABLE IF EXISTS dbo.L10_Products_Copy;
GO


/* ============================================================
   1. THE FOUR OPERATORS  (rows stacked on top of each other)
   ============================================================
   A JOIN puts tables side by side (more COLUMNS).
   A set operator puts query results one under the other (more ROWS).
   Example data: Customers.City vs Departments.Location.
     Customers  : Delhi, Mumbai, Delhi, Pune, Bangalore, Mumbai, Chennai, Delhi   (8)
     Departments: Delhi, Mumbai, Delhi, Bangalore, Pune, Delhi                    (6)
   ============================================================ */

-- 1a. UNION = A + B, duplicates REMOVED (so it must sort/hash -> result comes out sorted).
SELECT City FROM dbo.Customers
UNION
SELECT Location FROM dbo.Departments;
GO
-- expect 5 rows: Bangalore, Chennai, Delhi, Mumbai, Pune

-- 1b. UNION ALL = A + B, duplicates KEPT, no de-dup work -> faster. Use it when you
--     know there are no duplicates or you want to count them.
SELECT City FROM dbo.Customers
UNION ALL
SELECT Location FROM dbo.Departments;
GO
-- expect 14 rows (8 + 6), Delhi appears 6 times

-- 1c. INTERSECT = only values present in BOTH (distinct).
SELECT City FROM dbo.Customers
INTERSECT
SELECT Location FROM dbo.Departments;
GO
-- expect 4 rows: Bangalore, Delhi, Mumbai, Pune  (cities with customers AND an office)

-- 1d. EXCEPT = in A but NOT in B (distinct). ORDER MATTERS: A EXCEPT B <> B EXCEPT A.
SELECT City FROM dbo.Customers
EXCEPT
SELECT Location FROM dbo.Departments;
GO
-- expect 1 row: Chennai  (customers there, but no office)

SELECT Location FROM dbo.Departments
EXCEPT
SELECT City FROM dbo.Customers;
GO
-- expect 0 rows  (every office city has at least one customer)


/* ============================================================
   2. THE RULES
   ============================================================ */

-- 2a. Same NUMBER of columns in every branch. (Compile error -> run as a string.)
BEGIN TRY
    EXEC sp_executesql N'SELECT EmployeeID, EmployeeName FROM dbo.Employees
                         UNION
                         SELECT CustomerID FROM dbo.Customers;';
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
    -- All queries combined using a UNION, INTERSECT or EXCEPT operator must have
    -- an equal number of expressions in their target lists.
END CATCH
GO

-- 2b. COMPATIBLE types, position by position. INT in branch 1 vs a name in branch 2:
--     SQL Server tries to convert the name to INT (higher precedence) and fails.
BEGIN TRY
    SELECT EmployeeID   AS Val FROM dbo.Employees
    UNION
    SELECT CustomerName        FROM dbo.Customers;
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();   -- Conversion failed when converting the varchar value ...
END CATCH
GO
-- Fix: make the types match yourself.
SELECT CAST(EmployeeID AS VARCHAR(10)) AS Val FROM dbo.Employees
UNION
SELECT CustomerName FROM dbo.Customers;
GO
-- expect 20 rows (12 ids + 8 names, all different)

-- 2c. Column NAMES come from the FIRST query. Aliases in later branches are ignored.
SELECT EmployeeName AS Person FROM dbo.Employees
UNION ALL
SELECT CustomerName AS Cust   FROM dbo.Customers;
GO
-- expect 20 rows; the column header is "Person", not "Cust"

-- 2d. ORDER BY goes ONCE, at the very end, and must use FIRST-query names.
BEGIN TRY
    EXEC sp_executesql N'SELECT EmployeeName AS Person FROM dbo.Employees
                         UNION ALL
                         SELECT CustomerName AS Cust FROM dbo.Customers
                         ORDER BY Cust;';
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();   -- Invalid column name 'Cust'.
END CATCH
GO
SELECT EmployeeName AS Person FROM dbo.Employees
UNION ALL
SELECT CustomerName          FROM dbo.Customers
ORDER BY Person;
GO
-- expect 20 rows, Aarav Sharma first, Vikram last

-- 2e. TOP / ORDER BY inside a branch is NOT allowed ...
BEGIN TRY
    EXEC sp_executesql N'SELECT TOP (2) EmployeeName FROM dbo.Employees ORDER BY Salary DESC
                         UNION ALL
                         SELECT TOP (2) ProductName FROM dbo.Products ORDER BY Price DESC;';
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();   -- Incorrect syntax near the keyword 'UNION'.
END CATCH
GO
-- ... so wrap each branch in a derived table (or a CTE). The 2 highest salaries
--     and the 2 most expensive products in ONE list:
SELECT t.Name, t.Amount, t.Kind
FROM (SELECT TOP (2) EmployeeName AS Name, Salary AS Amount, 'Employee' AS Kind
      FROM dbo.Employees ORDER BY Salary DESC) AS t
UNION ALL
SELECT p.Name, p.Amount, p.Kind
FROM (SELECT TOP (2) ProductName, Price, 'Product'
      FROM dbo.Products ORDER BY Price DESC) AS p (Name, Amount, Kind);
GO
-- expect 4 rows: Sneha 90000, Rahul 85000, Laptop 75000, Monitor 25000

-- 2f. Same trick for OFFSET / FETCH per branch: the 2nd and 3rd of each list.
SELECT * FROM (SELECT EmployeeName AS Name, Salary AS Amount FROM dbo.Employees
               ORDER BY Salary DESC OFFSET 1 ROWS FETCH NEXT 2 ROWS ONLY) AS e
UNION ALL
SELECT * FROM (SELECT ProductName, Price FROM dbo.Products
               ORDER BY Price DESC OFFSET 1 ROWS FETCH NEXT 2 ROWS ONLY) AS p;
GO
-- expect 4 rows: Rahul 85000, Priya 75000, Monitor 25000, Desk 15000


/* ============================================================
   3. NULLs ARE EQUAL FOR SET OPERATORS  (unlike = )
   ============================================================ */

-- 3a. In WHERE, NULL = NULL is UNKNOWN -> no row. For UNION / INTERSECT / EXCEPT
--     two NULLs are treated as the SAME value (they use "IS NOT DISTINCT FROM" logic).
SELECT 'equal' AS WhereTest WHERE NULL = NULL;          -- expect 0 rows
SELECT NULL AS IntersectTest INTERSECT SELECT NULL;     -- expect 1 row: NULL
GO

-- 3b. Emails: Employees has 11 emails + 1 NULL, Customers has 6 emails + 2 NULLs.
SELECT COUNT(*) AS UnionRows
FROM (SELECT Email FROM dbo.Employees
      UNION
      SELECT Email FROM dbo.Customers) AS u;
GO
-- expect 18  = 17 distinct emails + ONE NULL (all three NULLs collapsed into one)

SELECT COUNT(*) AS UnionAllRows
FROM (SELECT Email FROM dbo.Employees
      UNION ALL
      SELECT Email FROM dbo.Customers) AS u;
GO
-- expect 20

-- 3c. EXCEPT also matches NULL with NULL: the customers' NULL email is removed
--     because Employees has a NULL email too.
SELECT Email FROM dbo.Customers
EXCEPT
SELECT Email FROM dbo.Employees;
GO
-- expect 6 rows: aarav, bhavna, chirag, divya, esha, gaurav  (no NULL row)


/* ============================================================
   4. PRECEDENCE WHEN MIXING  (INTERSECT first, then left to right)
   ============================================================ */

-- 4a. INTERSECT binds tighter than UNION / EXCEPT, like * before +.
--     Read this as:  1  UNION  (2 INTERSECT 2)
SELECT 1 AS v UNION SELECT 2 INTERSECT SELECT 2;
GO
-- expect 2 rows: 1, 2

-- 4b. Parentheses change it: (1 UNION 2) INTERSECT 2
(SELECT 1 AS v UNION SELECT 2) INTERSECT SELECT 2;
GO
-- expect 1 row: 2

-- 4c. UNION and EXCEPT have equal rank -> evaluated LEFT TO RIGHT.
SELECT 1 AS v UNION SELECT 2 EXCEPT SELECT 2;     -- (1 UNION 2) EXCEPT 2
GO
-- expect 1 row: 1
SELECT 2 AS v EXCEPT SELECT 2 UNION SELECT 2;     -- (2 EXCEPT 2) UNION 2
GO
-- expect 1 row: 2
-- LESSON: whenever you mix operators, ALWAYS write the parentheses.


/* ============================================================
   5. PRACTICAL: ONE CONTACT LIST FROM TWO TABLES
   ============================================================ */

-- 5a. Employees and Customers in one list with a Type column (a literal per branch).
SELECT 'Employee' AS ContactType, EmployeeName AS Name, Email, NULL AS City
FROM dbo.Employees
UNION ALL
SELECT 'Customer', CustomerName, Email, City
FROM dbo.Customers
ORDER BY ContactType, Name;
GO
-- expect 20 rows: 8 customers first (Aarav ... Hina), then 12 employees (Amit ... Vikram)


/* ============================================================
   6. PRACTICAL: COMPARE TWO TABLES  (interview classic)
   ============================================================
   "Given a table and its copy, find the rows that differ."
   Answer: (A EXCEPT B) UNION ALL (B EXCEPT A). EXCEPT compares ALL
   columns and treats NULLs as equal, so it is the perfect diff tool.
   ============================================================ */

-- 6a. Make a copy and change it: one price edited, one new product.
SELECT * INTO dbo.L10_Products_Copy FROM dbo.Products;
UPDATE dbo.L10_Products_Copy SET Price = 1200 WHERE ProductID = 2;                     -- Mouse 1000 -> 1200
INSERT INTO dbo.L10_Products_Copy VALUES (12, 'Printer', 'Electronics', 9000, 8);       -- new row
GO

-- 6b. Rows in the ORIGINAL that are not (exactly) in the copy.
SELECT * FROM dbo.Products
EXCEPT
SELECT * FROM dbo.L10_Products_Copy;
GO
-- expect 1 row: 2 Mouse 1000 (the old version of the edited row)

-- 6c. Rows in the COPY that are not in the original.
SELECT * FROM dbo.L10_Products_Copy
EXCEPT
SELECT * FROM dbo.Products;
GO
-- expect 2 rows: 2 Mouse 1200 (new version), 12 Printer (added)

-- 6d. Both directions in one result with a label. Each EXCEPT must be wrapped
--     (a derived table) so the label and the UNION ALL do not confuse precedence.
SELECT 'Only in original' AS Side, d.*
FROM (SELECT * FROM dbo.Products EXCEPT SELECT * FROM dbo.L10_Products_Copy) AS d
UNION ALL
SELECT 'Only in copy', d.*
FROM (SELECT * FROM dbo.L10_Products_Copy EXCEPT SELECT * FROM dbo.Products) AS d
ORDER BY Side, ProductID;
GO
-- expect 3 rows

-- 6e. "Are the two tables identical?" -> both EXCEPTs empty.
SELECT CASE WHEN EXISTS (SELECT * FROM dbo.Products EXCEPT SELECT * FROM dbo.L10_Products_Copy)
              OR EXISTS (SELECT * FROM dbo.L10_Products_Copy EXCEPT SELECT * FROM dbo.Products)
            THEN 'Different' ELSE 'Identical' END AS Comparison;
GO
-- expect Different


/* ============================================================
   7. UNION ALL TO BUILD A SMALL LOOKUP LIST ON THE FLY
   ============================================================ */

-- 7a. A status list with a display order, without creating a table.
--     LEFT JOIN from the list so a status with 0 orders would still appear.
SELECT s.Status, s.SortOrder, COUNT(o.OrderID) AS Orders
FROM (SELECT 1 AS SortOrder, 'Pending'   AS Status
      UNION ALL SELECT 2, 'Completed'
      UNION ALL SELECT 3, 'Cancelled') AS s
LEFT JOIN dbo.Orders o ON o.Status = s.Status
GROUP BY s.Status, s.SortOrder
ORDER BY s.SortOrder;
GO
-- expect 3 rows: Pending 2, Completed 16, Cancelled 1

-- 7b. Modern shorthand for the same thing: the VALUES table constructor.
SELECT s.Status, COUNT(o.OrderID) AS Orders
FROM (VALUES (1, 'Pending'), (2, 'Completed'), (3, 'Cancelled')) AS s (SortOrder, Status)
LEFT JOIN dbo.Orders o ON o.Status = s.Status
GROUP BY s.SortOrder, s.Status
ORDER BY s.SortOrder;
GO
-- expect the same 3 rows


/* ============================================================
   8. UNION vs JOIN  (rows vs columns)
   ============================================================ */

-- 8a. UNION ALL: same columns, MORE ROWS (12 + 8 = 20 rows, 2 columns).
SELECT EmployeeID AS Id, EmployeeName AS Name FROM dbo.Employees
UNION ALL
SELECT CustomerID, CustomerName FROM dbo.Customers;
GO
-- expect 20 rows x 2 columns

-- 8b. JOIN: related rows, MORE COLUMNS (11 rows: employees WITH a department).
SELECT e.EmployeeID, e.EmployeeName, d.DepartmentName, d.Location
FROM dbo.Employees e
JOIN dbo.Departments d ON d.DepartmentID = e.DepartmentID;
GO
-- expect 11 rows x 4 columns (Anjali has no department -> dropped by the inner join)


/* ============================================================
   9. UNION ALL + GROUP BY  AS AN ALTERNATIVE TO FULL OUTER JOIN
   ============================================================
   Question: per city, how many employees (via department location)
   and how many customers? Some cities exist only on one side
   (Chennai has customers but no office).
   ============================================================ */

-- 9a. FULL OUTER JOIN version: aggregate each side, join, COALESCE the key.
SELECT COALESCE(e.City, c.City) AS City,
       ISNULL(e.Employees, 0)   AS Employees,
       ISNULL(c.Customers, 0)   AS Customers
FROM (SELECT d.Location AS City, COUNT(*) AS Employees
      FROM dbo.Employees e
      JOIN dbo.Departments d ON d.DepartmentID = e.DepartmentID
      GROUP BY d.Location) AS e
FULL OUTER JOIN (SELECT City, COUNT(*) AS Customers
                 FROM dbo.Customers
                 GROUP BY City) AS c ON c.City = e.City
ORDER BY City;
GO
-- expect 5 rows: Bangalore 2/1, Chennai 0/1, Delhi 4/3, Mumbai 3/2, Pune 2/1

-- 9b. UNION ALL + GROUP BY version: stack both sides with a 0 in the "other"
--     column, then SUM. No join, no COALESCE, easy to extend to 3+ sources.
SELECT City, SUM(Employees) AS Employees, SUM(Customers) AS Customers
FROM (SELECT d.Location AS City, 1 AS Employees, 0 AS Customers
      FROM dbo.Employees e
      JOIN dbo.Departments d ON d.DepartmentID = e.DepartmentID
      UNION ALL
      SELECT City, 0, 1
      FROM dbo.Customers) AS u
GROUP BY City
ORDER BY City;
GO
-- expect the same 5 rows


/* ============================================================
   10. CLEANUP
   ============================================================ */
DROP TABLE IF EXISTS dbo.L10_Products_Copy;
GO
/* DONE. Next: Exercises.sql */
