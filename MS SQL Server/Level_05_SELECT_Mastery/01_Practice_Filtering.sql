/* ============================================================
   LEVEL 05 - SELECT MASTERY  |  01_Practice_Filtering.sql
   ------------------------------------------------------------
   Topics : logical order of query processing, WHERE with AND / OR /
            NOT and parentheses (precedence), IN / NOT IN, BETWEEN
            (inclusive, date trap), LIKE (%, _, [abc], [a-f], [^x],
            ESCAPE, NOT LIKE), IS NULL / IS NOT NULL (why = NULL fails,
            NOT IN + NULL preview)

   HOW TO PRACTICE: run block by block, predict the output first.
   Everything is READ-ONLY on the real tables (Employees, Customers,
   Products, Orders). Nothing is created or changed.
   Next: 02_Practice_Sorting_Top_Paging.sql
   ============================================================ */

USE SQLPractice;
GO


/* ============================================================
   1. LOGICAL ORDER OF QUERY PROCESSING
   ============================================================ */
-- You WRITE the clauses in this order:
--     SELECT ... FROM ... WHERE ... GROUP BY ... HAVING ... ORDER BY ...
-- SQL Server RUNS them in this order:
--     1 FROM  ->  2 WHERE  ->  3 GROUP BY  ->  4 HAVING  ->  5 SELECT  ->  6 DISTINCT  ->  7 ORDER BY  ->  8 TOP / OFFSET-FETCH
-- Mental model: rows come out of FROM, WHERE throws some away, GROUP BY folds them, HAVING throws groups
-- away, SELECT shapes the columns (aliases are born HERE), DISTINCT removes duplicates, ORDER BY sorts,
-- TOP / OFFSET keeps a slice.
-- Consequence: an alias created in SELECT (step 5) does not exist yet in WHERE (step 2),
-- but it DOES exist in ORDER BY (step 7).

-- 1a. Alias in WHERE -> "Invalid column name" (a compile-time error, so EXEC is used to let CATCH show it)
BEGIN TRY
    EXEC ('SELECT EmployeeName, Salary * 12 AS AnnualSalary FROM dbo.Employees WHERE AnnualSalary > 800000;');
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO

-- 1b. Fix: repeat the expression in WHERE. The alias IS fine in ORDER BY.
SELECT EmployeeName, Salary * 12 AS AnnualSalary
FROM dbo.Employees
WHERE Salary * 12 > 800000
ORDER BY AnnualSalary DESC;
-- 5 rows: Sneha 1080000, Rahul 1020000, Priya 900000, Deepak 864000, Karan 840000
GO
-- (Level 09 / 11: a subquery or CTE lets you filter on the alias, because the outer query's FROM sees it.)


/* ============================================================
   2. WHERE WITH AND / OR / NOT  AND PARENTHESES
   ============================================================ */

-- 2a. AND: both conditions must be true
SELECT EmployeeName, DepartmentID, Salary
FROM dbo.Employees
WHERE DepartmentID = 2 AND Salary > 60000;            -- 2 rows: Priya 75000, Vikram 62000
GO

-- 2b. OR: at least one condition true
SELECT EmployeeName, DepartmentID
FROM dbo.Employees
WHERE DepartmentID = 3 OR DepartmentID = 4;           -- 3 rows: Ravi, Sneha, Deepak
GO

-- 2c. NOT: reverses a condition. Watch the NULL: Anjali (DepartmentID NULL) is NOT returned,
--     because NOT (NULL = 1) is NOT (UNKNOWN) = UNKNOWN, and WHERE keeps only TRUE.
SELECT EmployeeName, DepartmentID
FROM dbo.Employees
WHERE NOT DepartmentID = 1;                           -- 8 rows (12 - 3 in IT - Anjali)
GO

-- 2d. PRECEDENCE: AND binds tighter than OR (like * before + in maths).
--     Wanted: "employees of department 1 or 2 who earn more than 70000".
-- WRONG (no parentheses): read as  DepartmentID = 1  OR  (DepartmentID = 2 AND Salary > 70000)
SELECT EmployeeName, DepartmentID, Salary
FROM dbo.Employees
WHERE DepartmentID = 1 OR DepartmentID = 2 AND Salary > 70000;
-- 4 rows: Rahul, Amit, Pooja (all of IT, whatever they earn) + Priya
GO
-- RIGHT: parentheses say what you mean
SELECT EmployeeName, DepartmentID, Salary
FROM dbo.Employees
WHERE (DepartmentID = 1 OR DepartmentID = 2) AND Salary > 70000;
-- 2 rows: Rahul 85000, Priya 75000
GO
-- Rule: the moment you mix AND and OR, add parentheses - even when they are not needed.

-- 2e. NOT with parentheses:  NOT (A OR B)  =  NOT A AND NOT B
SELECT EmployeeName, DepartmentID
FROM dbo.Employees
WHERE NOT (DepartmentID = 1 OR DepartmentID = 2);     -- 5 rows: Ravi, Sneha, Karan, Deepak, Meera (Anjali excluded again)
GO


/* ============================================================
   3. IN  /  NOT IN
   ============================================================ */

-- 3a. IN = a shorter way to write several ORs on the same column
SELECT EmployeeName, DepartmentID
FROM dbo.Employees
WHERE DepartmentID IN (1, 3, 5);                       -- 6 rows: Rahul, Amit, Pooja, Ravi, Karan, Meera
GO
SELECT CustomerName, City
FROM dbo.Customers
WHERE City IN ('Delhi', 'Pune');                       -- 4 rows: Aarav, Chirag, Hina (Delhi), Divya (Pune)
GO

-- 3b. NOT IN: everything except the list ... except NULLs, which are silently dropped
SELECT EmployeeName, DepartmentID
FROM dbo.Employees
WHERE DepartmentID NOT IN (1, 2);                      -- 5 rows (Anjali missing: NULL NOT IN (1,2) is UNKNOWN)
GO

-- 3c. THE TRAP: a NULL inside the NOT IN list makes the whole query return NOTHING.
--     x NOT IN (1, 2, NULL)  =  x <> 1 AND x <> 2 AND x <> NULL  ->  the last part is UNKNOWN -> no row passes.
SELECT EmployeeName, DepartmentID
FROM dbo.Employees
WHERE DepartmentID NOT IN (1, 2, NULL);                -- 0 rows!
GO
-- (Section 6 shows the same trap with a subquery; NOT EXISTS is the fix - Level 09.)

-- 3d. IN with a subquery (preview of Level 09): employees whose department is in Delhi
SELECT EmployeeName, DepartmentID
FROM dbo.Employees
WHERE DepartmentID IN (SELECT DepartmentID FROM dbo.Departments WHERE Location = 'Delhi');
-- 4 rows: Rahul, Amit, Pooja (IT) + Ravi (HR); Legal has nobody
GO


/* ============================================================
   4. BETWEEN
   ============================================================ */

-- 4a. BETWEEN a AND b is INCLUSIVE:  >= a AND <= b. Ravi (60000) and Karan (70000) are both in.
SELECT EmployeeName, Salary
FROM dbo.Employees
WHERE Salary BETWEEN 60000 AND 70000
ORDER BY Salary;                                       -- 5 rows: Ravi 60000, Vikram 62000, Amit 65000, Pooja 65000, Karan 70000
GO
-- Same thing written long:
SELECT COUNT(*) AS SameCount FROM dbo.Employees WHERE Salary >= 60000 AND Salary <= 70000;   -- 5
GO

-- 4b. Lower bound must come first. Reversed bounds are legal but match nothing.
SELECT COUNT(*) AS ReversedBounds FROM dbo.Employees WHERE Salary BETWEEN 70000 AND 60000;   -- 0
GO

-- 4c. NOT BETWEEN
SELECT EmployeeName, Salary
FROM dbo.Employees
WHERE Salary NOT BETWEEN 60000 AND 70000
ORDER BY Salary;                                       -- 7 rows: Anjali 48000 ... Sneha 90000
GO

-- 4d. Dates. OrderDate is a DATE (no time), so BETWEEN two dates is safe: February 2025
SELECT OrderID, OrderDate
FROM dbo.Orders
WHERE OrderDate BETWEEN '2025-02-01' AND '2025-02-28';   -- 3 rows: 1004, 1005, 1006
GO
-- THE DATE TRAP: with DATETIME / DATETIME2 columns the upper bound '2025-02-28' means midnight,
-- so everything that happened ON Feb 28 after 00:00 is EXCLUDED.
SELECT CASE WHEN CAST('2025-02-28 10:00' AS DATETIME) BETWEEN '2025-02-01' AND '2025-02-28'
            THEN 'inside' ELSE 'OUTSIDE' END AS BetweenResult;                     -- OUTSIDE
-- Safe pattern for any date/time type:  >= first day  AND  < first day of NEXT month
SELECT CASE WHEN CAST('2025-02-28 10:00' AS DATETIME) >= '2025-02-01'
             AND CAST('2025-02-28 10:00' AS DATETIME) <  '2025-03-01'
            THEN 'inside' ELSE 'OUTSIDE' END AS HalfOpenResult;                    -- inside
GO
SELECT OrderID, OrderDate
FROM dbo.Orders
WHERE OrderDate >= '2025-02-01' AND OrderDate < '2025-03-01';   -- same 3 rows, and future-proof
GO

-- 4e. BETWEEN on strings compares alphabetically: 'Chirag Patel' > 'C', so he is OUT
SELECT CustomerName
FROM dbo.Customers
WHERE CustomerName BETWEEN 'A' AND 'C';                -- 2 rows: Aarav Sharma, Bhavna Mehta
GO


/* ============================================================
   5. LIKE
   ============================================================ */
-- %  = any string (0 or more chars)      _ = exactly one char
-- [abc] = one char from the set          [a-f] = one char in the range        [^x] = one char NOT x

-- 5a. %
SELECT EmployeeName FROM dbo.Employees WHERE EmployeeName LIKE 'R%';      -- starts with R: Rahul, Ravi (2)
SELECT EmployeeName FROM dbo.Employees WHERE EmployeeName LIKE '%a';      -- ends with a: Priya, Neha, Sneha, Pooja, Meera (5)
SELECT EmployeeName FROM dbo.Employees WHERE EmployeeName LIKE '%an%';    -- contains "an": Karan, Anjali (2)
GO

-- 5b. _  (one character each)
SELECT EmployeeName FROM dbo.Employees WHERE EmployeeName LIKE 'Ne_a';    -- Neha
SELECT EmployeeName FROM dbo.Employees WHERE EmployeeName LIKE '____';    -- exactly 4 letters: Amit, Neha, Ravi (3)
GO

-- 5c. Character sets and ranges
SELECT EmployeeName FROM dbo.Employees WHERE EmployeeName LIKE '[PR]%';   -- starts with P or R: Rahul, Priya, Ravi, Pooja (4)
SELECT EmployeeName FROM dbo.Employees WHERE EmployeeName LIKE '[A-D]%';  -- starts with A..D: Amit, Anjali, Deepak (3)
SELECT EmployeeName FROM dbo.Employees WHERE EmployeeName LIKE '[^A-M]%'; -- does NOT start with A..M: 7 rows
GO

-- 5d. ESCAPE: searching for a literal % or _ (the base tables have none, so a small VALUES list is used)
SELECT v.Txt
FROM (VALUES ('50% off'), ('discount_code'), ('plain')) AS v(Txt)
WHERE v.Txt LIKE '%_%';                                -- naive: _ matches ANY char -> all 3 rows
SELECT v.Txt
FROM (VALUES ('50% off'), ('discount_code'), ('plain')) AS v(Txt)
WHERE v.Txt LIKE '%\_%' ESCAPE '\';                    -- \_ = a real underscore -> discount_code
SELECT v.Txt
FROM (VALUES ('50% off'), ('discount_code'), ('plain')) AS v(Txt)
WHERE v.Txt LIKE '%[%]%';                              -- [%] = a real percent sign -> 50% off (works without ESCAPE)
GO

-- 5e. NOT LIKE (NULLs are dropped here too: Anjali has no email)
SELECT CustomerName, City FROM dbo.Customers WHERE City NOT LIKE '%a%';  -- cities without an "a": Delhi x3, Pune (4)
SELECT COUNT(*) AS NotStartingWithR FROM dbo.Employees WHERE Email NOT LIKE 'r%';   -- 9 (11 emails - rahul, ravi; NULL ignored)
GO

-- 5f. LIKE is case-INsensitive with the default collation; force case-sensitive with COLLATE
SELECT COUNT(*) AS DefaultCollation  FROM dbo.Employees WHERE EmployeeName LIKE 'rahul';                                 -- 1
SELECT COUNT(*) AS CaseSensitive     FROM dbo.Employees WHERE EmployeeName COLLATE Latin1_General_CS_AS LIKE 'rahul';   -- 0
GO
-- Performance note (Level 19): 'abc%' can use an index seek; '%abc' cannot (leading wildcard = scan).


/* ============================================================
   6. IS NULL  /  IS NOT NULL
   ============================================================ */
-- NULL means "unknown". Any comparison with NULL (= <> < >) gives UNKNOWN, never TRUE.
-- WHERE keeps only TRUE rows, so  "= NULL"  and  "<> NULL"  both return nothing.

-- 6a. The wrong way and the right way
SELECT COUNT(*) AS EqualsNull    FROM dbo.Employees WHERE Email = NULL;        -- 0  (never works)
SELECT COUNT(*) AS NotEqualsNull FROM dbo.Employees WHERE Email <> NULL;       -- 0  (never works either)
SELECT EmployeeName             FROM dbo.Employees WHERE Email IS NULL;        -- Anjali
SELECT COUNT(*) AS HasEmail      FROM dbo.Employees WHERE Email IS NOT NULL;   -- 11
GO

-- 6b. Three-valued logic in one line
SELECT CASE WHEN NULL = NULL THEN 'TRUE' ELSE 'not TRUE (UNKNOWN)' END AS NullEqualsNull;   -- not TRUE (UNKNOWN)
GO

-- 6c. Real questions on the data
SELECT CustomerName, City FROM dbo.Customers WHERE Email IS NULL;                -- Farhan Ali, Hina Khan
SELECT OrderID, OrderDate   FROM dbo.Orders    WHERE EmployeeID IS NULL;         -- 1019 (online order)
SELECT EmployeeName         FROM dbo.Employees WHERE ManagerID IS NULL;          -- 6 heads: Rahul, Priya, Ravi, Sneha, Karan, Anjali
GO

-- 6d. NOT IN + NULL, now with a subquery: "departments that have no employee" - expected: Legal
SELECT DepartmentName
FROM dbo.Departments
WHERE DepartmentID NOT IN (SELECT DepartmentID FROM dbo.Employees);              -- 0 rows!  Anjali's NULL poisons the list
GO
-- Fix 1: remove NULLs from the list
SELECT DepartmentName
FROM dbo.Departments
WHERE DepartmentID NOT IN (SELECT DepartmentID FROM dbo.Employees WHERE DepartmentID IS NOT NULL);   -- Legal
GO
-- Fix 2 (preferred, Level 09): NOT EXISTS is immune to NULLs
SELECT d.DepartmentName
FROM dbo.Departments d
WHERE NOT EXISTS (SELECT 1 FROM dbo.Employees e WHERE e.DepartmentID = d.DepartmentID);              -- Legal
GO

-- 6e. Showing something instead of NULL (Level 06 functions, preview): ISNULL / COALESCE
SELECT CustomerName, ISNULL(Email, '(no email)') AS EmailShown
FROM dbo.Customers
WHERE Email IS NULL OR City = 'Mumbai';                                          -- Bhavna, Farhan, Hina (3)
GO

/* ------------------------------------------------------------
   DONE. Next: 02_Practice_Sorting_Top_Paging.sql
   ------------------------------------------------------------ */
