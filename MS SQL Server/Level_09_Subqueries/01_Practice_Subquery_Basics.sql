/* ============================================================
   LEVEL 09 - SUBQUERIES  |  01_Practice_Subquery_Basics.sql
   ------------------------------------------------------------
   Topics : what a subquery is and where it can appear
            (SELECT list, FROM = derived table, WHERE, HAVING),
            scalar subquery (and the "more than 1 row" error),
            multi-row subquery: IN / NOT IN, ANY / SOME, ALL,
            correlated subquery (runs once per outer row),
            EXISTS / NOT EXISTS, the NOT IN + NULL trap.

   HOW TO PRACTICE: run block by block, predict the output first.
   This file only READS the base tables (nothing to clean up).
   File 02 continues with HAVING, derived tables, nesting,
   UPDATE/DELETE with subquery and the Nth highest salary.
   ============================================================ */

USE SQLPractice;
GO


/* ============================================================
   1. WHAT IS A SUBQUERY AND WHERE CAN IT APPEAR
   ============================================================
   A subquery = a SELECT written inside another statement, always
   in parentheses. The INNER query gives a value / list / table
   that the OUTER query uses. Four places it can sit:
     (1) SELECT list  -> must return ONE value (scalar)
     (2) FROM         -> returns a table = "derived table", needs an alias
     (3) WHERE        -> scalar (=, >) or list (IN, ANY, ALL, EXISTS)
     (4) HAVING       -> same as WHERE but after GROUP BY
   ============================================================ */

-- 1a. In the SELECT list: every employee next to the company average.
--     The inner query returns exactly one value, so it can act like a column.
SELECT e.EmployeeName,
       e.Salary,
       (SELECT AVG(Salary) FROM dbo.Employees) AS CompanyAvg
FROM dbo.Employees e;
GO
-- expect 12 rows, CompanyAvg = 67083.333333 on every row (805000 / 12)

-- 1b. In the FROM clause: the inner query becomes a table ("derived table").
--     RULE: a derived table MUST have an alias (here: da).
SELECT da.DepartmentID, da.AvgSalary
FROM (SELECT DepartmentID, AVG(Salary) AS AvgSalary
      FROM dbo.Employees
      GROUP BY DepartmentID) AS da
ORDER BY da.DepartmentID;
GO
-- expect 6 rows: NULL 48000, 1 71666.67, 2 64000, 3 60000, 4 81000, 5 64000

-- 1c. Forgetting the alias is a SYNTAX error. A syntax error kills the whole
--     batch before TRY/CATCH can act, so we run the bad text as a string.
BEGIN TRY
    EXEC sp_executesql N'SELECT * FROM (SELECT DepartmentID, AVG(Salary) AS AvgSalary
                                        FROM dbo.Employees GROUP BY DepartmentID);';
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();   -- Incorrect syntax near ';'
END CATCH
GO

-- 1d. In WHERE: compare each row with a value the inner query computes.
SELECT EmployeeName, Salary
FROM dbo.Employees
WHERE Salary > (SELECT AVG(Salary) FROM dbo.Employees)
ORDER BY Salary DESC;
GO
-- expect 5 rows: Sneha 90000, Rahul 85000, Priya 75000, Deepak 72000, Karan 70000

-- 1e. In HAVING (preview, more in file 02): departments paying above the company average.
SELECT DepartmentID, AVG(Salary) AS AvgSalary
FROM dbo.Employees
GROUP BY DepartmentID
HAVING AVG(Salary) > (SELECT AVG(Salary) FROM dbo.Employees);
GO
-- expect 2 rows: 1 (IT) 71666.67, 4 (Finance) 81000


/* ============================================================
   2. SCALAR SUBQUERY  (returns exactly 1 row, 1 column)
   ============================================================ */

-- 2a. Classic interview question: employees earning above the company average.
--     The inner query runs ONCE, its single value is reused for every row.
SELECT EmployeeName, Salary,
       Salary - (SELECT AVG(Salary) FROM dbo.Employees) AS AboveAvgBy
FROM dbo.Employees
WHERE Salary > (SELECT AVG(Salary) FROM dbo.Employees)
ORDER BY Salary DESC;
GO
-- expect 5 rows; Sneha AboveAvgBy = 22916.666667

-- 2b. A scalar subquery that finds NO row returns NULL (not an error).
--     Legal (DepartmentID 6) has no employees.
SELECT (SELECT AVG(Salary) FROM dbo.Employees WHERE DepartmentID = 6) AS LegalAvg;
GO
-- expect 1 row: NULL

-- 2c. THE ERROR: a scalar position gets MORE THAN ONE row.
--     Sales (DepartmentID 2) has 3 employees -> 3 salaries -> SQL Server cannot
--     pick one for the ">" comparison. Runtime error 512, caught by TRY/CATCH.
BEGIN TRY
    SELECT EmployeeName, Salary
    FROM dbo.Employees
    WHERE Salary > (SELECT Salary FROM dbo.Employees WHERE DepartmentID = 2);
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
    -- "Subquery returned more than 1 value. This is not permitted when the
    --  subquery follows =, !=, <, <= , >, >= or when the subquery is used as an expression."
END CATCH
GO
-- Fix options: aggregate it (MAX / MIN / AVG), or use ALL / ANY / IN (section 3 and 4).
-- Danger: this error appears only when the DATA has 2+ rows. It may pass in dev
-- with 1 row and break in production. Prefer an aggregate whenever you mean one value.


/* ============================================================
   3. MULTI-ROW SUBQUERY: IN / NOT IN
   ============================================================
   IN  (list)  = "is my value equal to ANY value in the list"
   The list can be a subquery returning MANY rows but ONE column.
   ============================================================ */

-- 3a. Employees who work in a department located in Delhi (IT, HR, Legal).
SELECT EmployeeName, DepartmentID
FROM dbo.Employees
WHERE DepartmentID IN (SELECT DepartmentID FROM dbo.Departments WHERE Location = 'Delhi')
ORDER BY EmployeeName;
GO
-- expect 4 rows: Amit, Pooja, Rahul (IT) and Ravi (HR). Legal has nobody.

-- 3b. Customers who placed at least one order.
SELECT CustomerID, CustomerName
FROM dbo.Customers
WHERE CustomerID IN (SELECT CustomerID FROM dbo.Orders);
GO
-- expect 7 rows (everyone except Hina Khan, 8)

-- 3c. Products that were NEVER ordered (anti-join with NOT IN).
--     Safe here because OrderDetails.ProductID is NOT NULL (see section 7 for why that matters).
SELECT ProductID, ProductName
FROM dbo.Products
WHERE ProductID NOT IN (SELECT ProductID FROM dbo.OrderDetails);
GO
-- expect 1 row: 11 Webcam

-- 3d. A subquery in IN may return 2 columns? NO -> error. One column only.
BEGIN TRY
    EXEC sp_executesql N'SELECT * FROM dbo.Customers
                         WHERE CustomerID IN (SELECT CustomerID, OrderID FROM dbo.Orders);';
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();   -- Only one expression can be specified in the select list ...
END CATCH
GO


/* ============================================================
   4. ANY / SOME / ALL  (compare with a whole list)
   ============================================================
   x > ANY (list)  -> true if x is bigger than AT LEAST ONE value  (= x > MIN)
   x > ALL (list)  -> true if x is bigger than EVERY value         (= x > MAX)
   x = ANY (list)  -> exactly the same as  x IN (list)
   SOME is just another spelling of ANY.
   ============================================================ */

-- 4a. Salary higher than EVERY employee of the Sales department (Sales max = 75000).
SELECT EmployeeName, Salary
FROM dbo.Employees
WHERE Salary > ALL (SELECT Salary FROM dbo.Employees WHERE DepartmentID = 2)
ORDER BY Salary DESC;
GO
-- expect 2 rows: Sneha 90000, Rahul 85000

-- 4b. Same result with an aggregate - easier to read, most people write it this way.
SELECT EmployeeName, Salary
FROM dbo.Employees
WHERE Salary > (SELECT MAX(Salary) FROM dbo.Employees WHERE DepartmentID = 2)
ORDER BY Salary DESC;
GO
-- expect the same 2 rows

-- 4c. Salary higher than AT LEAST ONE Sales employee (Sales min = 55000).
SELECT COUNT(*) AS EarnMoreThanSomeSalesPerson
FROM dbo.Employees
WHERE Salary > ANY (SELECT Salary FROM dbo.Employees WHERE DepartmentID = 2);
GO
-- expect 10 (everyone except Neha 55000 - not strictly greater - and Anjali 48000)

-- 4d. = ANY  is  IN.   SOME = ANY.
SELECT EmployeeName
FROM dbo.Employees
WHERE DepartmentID = SOME (SELECT DepartmentID FROM dbo.Departments WHERE Location = 'Pune');
GO
-- expect 2 rows: Karan, Meera (Marketing is in Pune)

-- 4e. TRAP: ALL against an EMPTY list is TRUE for every row. Legal has no employees,
--     so "earns more than everyone in Legal" is true for all 12 people.
SELECT COUNT(*) AS RowsReturned
FROM dbo.Employees
WHERE Salary > ALL (SELECT Salary FROM dbo.Employees WHERE DepartmentID = 6);
GO
-- expect 12   (with MAX instead: Salary > NULL -> UNKNOWN -> 0 rows. Different!)


/* ============================================================
   5. CORRELATED SUBQUERY  (inner query uses a column of the outer row)
   ============================================================
   A normal subquery runs ONCE. A correlated subquery refers to the
   outer table (e.DepartmentID below), so logically it runs ONCE PER
   OUTER ROW - like a loop: for each employee, compute the average of
   HIS/HER department, then compare.
   ============================================================ */

-- 5a. Employees earning above the average of THEIR OWN department.
SELECT e.EmployeeName, e.DepartmentID, e.Salary
FROM dbo.Employees e
WHERE e.Salary > (SELECT AVG(x.Salary)
                  FROM dbo.Employees x
                  WHERE x.DepartmentID = e.DepartmentID)   -- <- correlation
ORDER BY e.DepartmentID;
GO
-- expect 4 rows: Rahul (IT avg 71666.67), Priya (Sales avg 64000),
--                Sneha (Finance avg 81000), Karan (Marketing avg 64000)
-- Anjali (DepartmentID NULL): NULL = NULL is never true -> inner AVG is NULL
-- -> 48000 > NULL is UNKNOWN -> row dropped.

-- 5b. Correlated subquery in the SELECT list: show the department average
--     and how many colleagues share the department.
SELECT e.EmployeeName, e.Salary,
       (SELECT AVG(x.Salary) FROM dbo.Employees x WHERE x.DepartmentID = e.DepartmentID) AS DeptAvg,
       (SELECT COUNT(*)      FROM dbo.Employees x WHERE x.DepartmentID = e.DepartmentID) AS DeptHeadcount
FROM dbo.Employees e
ORDER BY e.DepartmentID, e.Salary DESC;
GO
-- expect 12 rows; Anjali: DeptAvg NULL, DeptHeadcount 0

-- 5c. Each customer with the number of orders (0 for Hina - no join needed).
SELECT c.CustomerName,
       (SELECT COUNT(*) FROM dbo.Orders o WHERE o.CustomerID = c.CustomerID) AS OrderCount
FROM dbo.Customers c
ORDER BY OrderCount DESC, c.CustomerName;
GO
-- expect 8 rows: Aarav 4, Bhavna 4, Chirag 3, Divya 2, Esha 2, Farhan 2, Gaurav 2, Hina 0


/* ============================================================
   6. EXISTS / NOT EXISTS
   ============================================================
   EXISTS (subquery) is TRUE as soon as the subquery finds ONE row.
   It never returns data, so what you SELECT inside does not matter
   (SELECT 1, SELECT *, SELECT 'x' are all the same). It stops at the
   first match = efficient. Almost always written correlated.
   ============================================================ */

-- 6a. Customers who have at least one order.
SELECT c.CustomerID, c.CustomerName
FROM dbo.Customers c
WHERE EXISTS (SELECT 1 FROM dbo.Orders o WHERE o.CustomerID = c.CustomerID);
GO
-- expect 7 rows

-- 6b. Customers WITHOUT any order (anti-join).
SELECT c.CustomerID, c.CustomerName
FROM dbo.Customers c
WHERE NOT EXISTS (SELECT 1 FROM dbo.Orders o WHERE o.CustomerID = c.CustomerID);
GO
-- expect 1 row: 8 Hina Khan

-- 6c. Departments with no employees.
SELECT d.DepartmentID, d.DepartmentName
FROM dbo.Departments d
WHERE NOT EXISTS (SELECT 1 FROM dbo.Employees e WHERE e.DepartmentID = d.DepartmentID);
GO
-- expect 1 row: 6 Legal

-- 6d. Products never ordered - the NOT EXISTS version of 3c.
SELECT p.ProductID, p.ProductName
FROM dbo.Products p
WHERE NOT EXISTS (SELECT * FROM dbo.OrderDetails od WHERE od.ProductID = p.ProductID);
GO
-- expect 1 row: 11 Webcam

-- 6e. EXISTS with TWO conditions inside: customers who bought a Laptop (ProductID 1).
SELECT c.CustomerName
FROM dbo.Customers c
WHERE EXISTS (SELECT 1
              FROM dbo.Orders o
              JOIN dbo.OrderDetails od ON od.OrderID = o.OrderID
              WHERE o.CustomerID = c.CustomerID
                AND od.ProductID = 1);
GO
-- expect 3 rows: Aarav Sharma (1001), Esha Kapoor (1014), Farhan Ali (1008)


/* ============================================================
   7. THE NOT IN + NULL TRAP  (top interview question)
   ============================================================ */

-- 7a. "Departments with no employees" written with NOT IN.
--     Employees.DepartmentID contains a NULL (Anjali, the contractor).
SELECT DepartmentID, DepartmentName
FROM dbo.Departments
WHERE DepartmentID NOT IN (SELECT DepartmentID FROM dbo.Employees);
GO
-- expect 0 rows  <- WRONG, we know Legal has nobody!
-- WHY: NOT IN (1, 2, ..., NULL) means  <> 1 AND <> 2 AND ... AND <> NULL.
--      "6 <> NULL" is UNKNOWN, and TRUE AND UNKNOWN = UNKNOWN, and WHERE keeps
--      only TRUE. So EVERY row is dropped when the list contains even one NULL.

-- 7b. Fix 1: remove NULLs from the list.
SELECT DepartmentID, DepartmentName
FROM dbo.Departments
WHERE DepartmentID NOT IN (SELECT DepartmentID FROM dbo.Employees WHERE DepartmentID IS NOT NULL);
GO
-- expect 1 row: 6 Legal

-- 7c. Fix 2 (preferred): NOT EXISTS is NULL-safe - a NULL simply never matches.
SELECT d.DepartmentID, d.DepartmentName
FROM dbo.Departments d
WHERE NOT EXISTS (SELECT 1 FROM dbo.Employees e WHERE e.DepartmentID = d.DepartmentID);
GO
-- expect 1 row: 6 Legal

-- 7d. Plain IN is not affected the same way: a NULL in the list just cannot match.
SELECT COUNT(*) AS DeptsWithEmployees
FROM dbo.Departments
WHERE DepartmentID IN (SELECT DepartmentID FROM dbo.Employees);
GO
-- expect 5 (IT, Sales, HR, Finance, Marketing)

/* ------------------------------------------------------------
   RULE OF THUMB
     - Need one value            -> scalar subquery with an aggregate
     - Need "is in a list"       -> IN   (or = ANY)
     - Need "not in a list"      -> NOT EXISTS (NULL-safe), or NOT IN + IS NOT NULL
     - Need "bigger than all"    -> > ALL or > (SELECT MAX ...)
     - Need per-row comparison   -> correlated subquery (or a window function, Level 11)
   DONE. Next: 02_Practice_Subquery_Advanced.sql
   ------------------------------------------------------------ */
