/* ============================================================
   LEVEL 06 - FUNCTIONS  |  03_Practice_Numeric_Conditional.sql
   ------------------------------------------------------------
   Topics : NUMERIC  - ROUND (incl. negative length and truncate),
            CEILING, FLOOR, ABS, POWER, SQRT, SQUARE, % (modulo),
            SIGN, RAND, integer division, casting for percentages.
            CONDITIONAL - CASE (simple / searched / ORDER BY /
            UPDATE-style / nested), IIF, COALESCE vs ISNULL,
            NULLIF (divide-by-zero guard), CHOOSE, GREATEST / LEAST,
            custom sort order with CASE.
   HOW TO PRACTICE: run block by block, predict the output first.
   The only data change (UPDATE with CASE) is inside a ROLLBACK.
   ============================================================ */

USE SQLPractice;
GO


/* ==== 1. ROUND ==== */

-- 1a. ROUND(number, length): length = digits AFTER the point. Result keeps the input's type/scale,
--     so 123.456 rounded to 2 places prints as 123.460 (scale 3 stays).
SELECT ROUND(123.456, 2)  AS TwoPlaces,     -- 123.460
       ROUND(123.456, 0)  AS WholeNumber,   -- 123.000
       ROUND(123.456, 1)  AS OnePlace,      -- 123.500
       ROUND(2.5, 0)      AS HalfUp,        -- 3.0   (rounds half AWAY from zero)
       ROUND(-2.5, 0)     AS HalfDown;      -- -3.0
GO

-- 1b. NEGATIVE length rounds to the LEFT of the point (tens, hundreds, ...)
SELECT ROUND(1234.5, -1) AS Tens,        -- 1230.0
       ROUND(1234.5, -2) AS Hundreds,    -- 1200.0
       ROUND(1250, -2)   AS Half_Hundreds; -- 1300  (integer input, integer output)
GO

-- 1c. Third argument <> 0 means TRUNCATE (cut, do not round)
SELECT ROUND(123.456, 2, 1) AS Truncated,   -- 123.450
       ROUND(123.456, 2)    AS Rounded,     -- 123.460
       ROUND(-123.456, 2, 1) AS TruncNeg;   -- -123.450
GO

-- 1d. Real data: average salary rounded for display (AVG explained in Level 07)
SELECT AVG(Salary) AS RawAvg, ROUND(AVG(Salary), 0) AS Rounded, CAST(AVG(Salary) AS DECIMAL(10,2)) AS Cast2
FROM dbo.Employees;   -- 67083.333333, 67083.000000, 67083.33
GO


/* ==== 2. CEILING, FLOOR, ABS, POWER, SQRT, SQUARE ==== */

-- 2a. CEILING = next integer up, FLOOR = next integer down. Watch the negatives.
SELECT CEILING(4.1) AS CeilPos,   -- 5
       FLOOR(4.9)   AS FloorPos,  -- 4
       CEILING(-4.1) AS CeilNeg,  -- -4  (up = towards +infinity)
       FLOOR(-4.1)   AS FloorNeg; -- -5
GO

-- 2b. Practical: how many boxes of 12 for 50 pens? -> CEILING(50 / 12.0) = 5 (not 50/12 = 4)
SELECT 50 / 12 AS IntDiv, CEILING(50 / 12.0) AS BoxesNeeded;   -- 4, 5
GO

-- 2c. ABS, POWER, SQRT, SQUARE
SELECT ABS(-150.5)     AS AbsVal,      -- 150.5
       POWER(2, 10)    AS TwoPow10,    -- 1024
       POWER(10, 2)    AS Hundred,     -- 100
       SQRT(144)       AS Root,        -- 12  (FLOAT)
       SQUARE(12)      AS Sq,          -- 144 (FLOAT)
       POWER(12, 2)    AS SqViaPower;  -- 144 (INT, because the first argument is INT)
GO

-- 2d. POWER returns the TYPE OF THE FIRST ARGUMENT -> POWER(2, 0.5) is 1, not 1.41
SELECT POWER(2, 0.5) AS IntBase, POWER(2.0, 0.5) AS DecBase, SQRT(2) AS Sqrt2;   -- 1, 1.4, 1.4142135623731
GO


/* ==== 3. % (MODULO), SIGN ==== */

-- 3a. % gives the remainder. n % 2 = 0 -> even. Classic interview: "select every 2nd row / odd IDs".
SELECT 7 % 2 AS Rem7_2, 10 % 3 AS Rem10_3, 10 % 5 AS Rem10_5;   -- 1, 1, 0
GO
SELECT EmployeeID, EmployeeName, CASE WHEN EmployeeID % 2 = 0 THEN 'Even' ELSE 'Odd' END AS IdParity
FROM dbo.Employees
WHERE EmployeeID % 2 = 1;   -- 6 rows: 101, 103, 105, 107, 109, 111
GO

-- 3b. SIGN returns -1, 0 or 1. Useful to classify "below / equal / above".
SELECT SIGN(-5) AS Neg, SIGN(0) AS Zero, SIGN(5) AS Pos;   -- -1, 0, 1
SELECT EmployeeName, Salary, SIGN(Salary - 65000) AS VsBenchmark
FROM dbo.Employees
WHERE EmployeeID IN (101, 102, 104);   -- Rahul 1.00, Amit .00, Neha -1.00  (SIGN keeps the DECIMAL type of Salary)
GO


/* ==== 4. RAND ==== */

-- 4a. RAND() = float in [0, 1). WITH a seed it is repeatable (same seed -> same number).
SELECT RAND() AS Random1, RAND() AS Random2, RAND(42) AS Seeded;   -- (varies), (varies), 0.714... every time
GO

-- 4b. TRAP: RAND() is evaluated ONCE per query, so every row gets the SAME value.
SELECT EmployeeID, RAND() AS SameForAllRows
FROM dbo.Employees
WHERE EmployeeID <= 103;   -- 3 identical values
GO

-- 4c. Per-row random: use CHECKSUM(NEWID()) (NEWID is generated per row). Random 1..100:
SELECT EmployeeID, ABS(CHECKSUM(NEWID())) % 100 + 1 AS Dice1to100
FROM dbo.Employees
WHERE EmployeeID <= 103;   -- 3 different values (varies)
GO
-- Random integer between 1 and 6 with RAND: FLOOR(RAND() * 6) + 1
SELECT FLOOR(RAND() * 6) + 1 AS DiceRoll;   -- (varies) 1.0 .. 6.0  (FLOAT - wrap in CAST(... AS INT) if you need an integer)
GO


/* ==== 5. INTEGER DIVISION REMINDER and CASTING FOR PERCENTAGES ==== */

-- 5a. INT / INT = INT (truncated). Make one side decimal to keep the fraction.
SELECT 7 / 2 AS IntDiv, 7 / 2.0 AS DecDiv, CAST(7 AS DECIMAL(5,2)) / 2 AS CastDiv, 7 * 1.0 / 2 AS TimesOne;   -- 3, 3.5, 3.5, 3.5
GO

-- 5b. Percentage trap: 16 completed of 19 orders. Integer maths gives 0 or 84; decimal gives 84.21.
SELECT 16 / 19 * 100                              AS Wrong_Zero,     -- 0   (16/19 = 0 first)
       16 * 100 / 19                              AS Int_Pct,        -- 84  (fraction lost)
       16 * 100.0 / 19                            AS Dec_Pct,        -- 84.210526
       CAST(16 * 100.0 / 19 AS DECIMAL(5,2))      AS Pct_2dp,        -- 84.21
       FORMAT(16.0 / 19, 'P1')                    AS Pct_Formatted;  -- 84.2%
GO

-- 5c. Real data: each product's share of total stock. Stock is INT -> multiply by 100.0 first.
DECLARE @TotalStock INT;
SELECT @TotalStock = SUM(Stock) FROM dbo.Products;          -- 1755
SELECT ProductName, Stock,
       Stock * 100 / @TotalStock                             AS IntPct,   -- Laptop 0, Pen 56
       CAST(Stock * 100.0 / @TotalStock AS DECIMAL(5,2))     AS Pct      -- Laptop 0.57, Pen 56.98
FROM dbo.Products
WHERE ProductID IN (1, 8);
GO


/* ==== 6. CASE - simple and searched ==== */

-- 6a. SIMPLE CASE: compares ONE expression to a list of values (like a switch).
SELECT OrderID, Status,
       CASE Status
            WHEN 'Completed' THEN 'Done'
            WHEN 'Pending'   THEN 'In progress'
            WHEN 'Cancelled' THEN 'Lost'
       END AS StatusLabel
FROM dbo.Orders
WHERE OrderID IN (1001, 1006, 1015);   -- Done, Lost, In progress
GO

-- 6b. SEARCHED CASE: each WHEN is a full boolean condition. Evaluated top-down, FIRST true WHEN wins.
SELECT EmployeeName, Salary,
       CASE WHEN Salary >= 80000 THEN 'High'
            WHEN Salary >= 60000 THEN 'Mid'
            ELSE 'Low'
       END AS SalaryBand
FROM dbo.Employees
ORDER BY Salary DESC;   -- High: Sneha, Rahul | Mid: Priya, Deepak, Karan, Amit, Pooja, Vikram, Ravi | Low: Meera, Neha, Anjali
GO

-- 6c. No ELSE and nothing matches -> NULL. Order of WHENs matters (overlapping conditions).
SELECT EmployeeName, Salary,
       CASE WHEN Salary >= 90000 THEN 'Top' END                          AS NoElse,          -- NULL for everyone except Sneha
       CASE WHEN Salary >= 60000 THEN 'Mid' WHEN Salary >= 80000 THEN 'High' END AS WrongOrder  -- Rahul gets 'Mid' (first WHEN already true)
FROM dbo.Employees
WHERE EmployeeID IN (101, 104, 106);
GO

-- 6d. CASE with aggregates: count employees per band (full treatment in Level 07)
SELECT CASE WHEN Salary >= 80000 THEN 'High' WHEN Salary >= 60000 THEN 'Mid' ELSE 'Low' END AS SalaryBand,
       COUNT(*) AS Employees
FROM dbo.Employees
GROUP BY CASE WHEN Salary >= 80000 THEN 'High' WHEN Salary >= 60000 THEN 'Mid' ELSE 'Low' END
ORDER BY Employees DESC;   -- Mid 7, Low 3, High 2
GO

-- 6e. NESTED CASE: a CASE inside a CASE branch
SELECT OrderID, Status, TotalAmount,
       CASE WHEN Status = 'Completed'
            THEN CASE WHEN TotalAmount >= 50000 THEN 'Big win' ELSE 'Win' END
            ELSE 'Not counted'
       END AS Outcome
FROM dbo.Orders
WHERE OrderID IN (1001, 1002, 1006, 1015);   -- Big win, Win, Not counted, Not counted
GO

-- 6f. UPDATE-style CASE: preview the new prices in a SELECT first ...
SELECT ProductName, Category, Price,
       CASE Category WHEN 'Electronics' THEN Price * 1.10
                     WHEN 'Furniture'   THEN Price * 1.05
                     ELSE Price END AS ProposedPrice
FROM dbo.Products
WHERE ProductID IN (1, 4, 7);   -- 82500.0000, 8400.0000, 50.0000  (DECIMAL * 1.10 grows the scale)
GO
-- ... then the same CASE inside a real UPDATE (rolled back, so the base table is untouched)
BEGIN TRAN;
    UPDATE dbo.Products
    SET Price = CASE Category WHEN 'Electronics' THEN Price * 1.10
                              WHEN 'Furniture'   THEN Price * 1.05
                              ELSE Price END;
    SELECT ProductName, Price AS PriceInsideTran FROM dbo.Products WHERE ProductID IN (1, 4, 7);   -- 82500, 8400, 50
ROLLBACK TRAN;
SELECT ProductName, Price AS PriceAfterRollback FROM dbo.Products WHERE ProductID IN (1, 4, 7);    -- 75000, 8000, 50
GO


/* ==== 7. IIF ==== */

-- 7a. IIF(condition, true_value, false_value) = shorthand for a 2-branch CASE (2012+).
SELECT EmployeeName, Salary, IIF(Salary >= 70000, 'Senior', 'Junior') AS Grade
FROM dbo.Employees
WHERE EmployeeID IN (101, 102);   -- Senior, Junior
GO

-- 7b. NULL comparisons are UNKNOWN -> IIF takes the FALSE branch. Nested IIF works but gets ugly fast.
SELECT IIF(NULL > 5, 'yes', 'no') AS NullGoesFalse,                                   -- no
       IIF(1 > 2, 'a', IIF(2 > 1, 'b', 'c')) AS Nested;                               -- b
GO


/* ==== 8. COALESCE vs ISNULL ==== */

-- 8a. Both replace NULL. ISNULL takes exactly 2 arguments; COALESCE takes 2 or more and returns the FIRST non-NULL.
SELECT CustomerName,
       ISNULL(Email, 'no email')                 AS IsNullVersion,
       COALESCE(Email, City, 'unknown')          AS FirstNonNull      -- Farhan: Mumbai (email NULL -> falls to City)
FROM dbo.Customers
WHERE CustomerID IN (1, 6);
GO

-- 8b. DATA TYPE difference: ISNULL returns the type of the FIRST argument (may TRUNCATE);
--     COALESCE returns the highest-precedence type of ALL arguments.
DECLARE @short VARCHAR(3) = NULL;
SELECT ISNULL(@short, 'Mumbai') AS IsNull_Truncated,    -- Mum   (!)
       COALESCE(@short, 'Mumbai') AS Coalesce_Full;     -- Mumbai
GO

-- 8c. COALESCE with only NULL constants is an error; ISNULL(NULL, NULL) is allowed (returns INT NULL).
--     (This is a COMPILE-time error, so it is run through sp_executesql to make TRY/CATCH able to catch it.)
BEGIN TRY
    EXEC sp_executesql N'SELECT COALESCE(NULL, NULL) AS Bad;';
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO
SELECT ISNULL(NULL, NULL) AS IsNullOK;   -- NULL
GO

-- 8d. Other differences (no query needed):
--     * COALESCE is ANSI standard (portable); ISNULL is SQL Server only.
--     * COALESCE(a, b) is rewritten as CASE WHEN a IS NOT NULL THEN a ELSE b END -> a subquery in 'a' may run twice.
--     * ISNULL(col, 0) in SELECT INTO / computed columns produces a NOT NULL column; COALESCE stays nullable.

-- 8e. Real data: contractors (NULL DepartmentID) shown as 0 / 'None'
SELECT EmployeeName, ISNULL(DepartmentID, 0) AS DeptOrZero, COALESCE(CAST(DepartmentID AS VARCHAR(5)), 'None') AS DeptOrNone
FROM dbo.Employees
WHERE EmployeeID IN (101, 110);   -- Rahul 1 / 1 ; Anjali 0 / None
GO


/* ==== 9. NULLIF - divide-by-zero guard ==== */

-- 9a. NULLIF(a, b) returns NULL when a = b, otherwise a. Headphones has Stock = 0.
BEGIN TRY
    SELECT ProductName, Price / Stock AS PricePerUnitStock FROM dbo.Products;   -- 8 rows stream out, then fails on Headphones
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO
SELECT ProductName, Stock,
       Price / NULLIF(Stock, 0)                             AS PricePerUnitStock,   -- Headphones -> NULL, no error
       CAST(Price / NULLIF(Stock, 0) AS DECIMAL(10,2))      AS Tidy                 -- decimal division inflates the scale; CAST for display
FROM dbo.Products
WHERE ProductID IN (1, 9);   -- Laptop 7500.00, Headphones NULL
GO

-- 9b. NULLIF to turn empty strings into NULL (cleaning imported data), then label them.
--     Note the 8b trap in action: TRIM('   ') is VARCHAR(3), so ISNULL(...) would give '(bl'. COALESCE is safe.
SELECT COALESCE(NULLIF(TRIM('   '), ''), '(blank)') AS Cleaned,        -- (blank)
       ISNULL(NULLIF(TRIM('   '), ''), '(blank)')   AS IsNullTruncates; -- (bl
GO


/* ==== 10. CHOOSE ==== */

-- CHOOSE(index, v1, v2, ...) returns the value at position index (1-based); out of range -> NULL. (2012+)
SELECT CHOOSE(3, 'a', 'b', 'c') AS Third, CHOOSE(0, 'a', 'b') AS OutOfRange;   -- c, NULL
GO
-- Real data: quarter name from month number, and fiscal quarter for India (FY starts in April)
SELECT OrderID, OrderDate,
       CHOOSE(MONTH(OrderDate), 'Q1','Q1','Q1','Q2','Q2','Q2','Q3','Q3','Q3','Q4','Q4','Q4') AS CalQuarter,
       CHOOSE(MONTH(OrderDate), 'Q4','Q4','Q4','Q1','Q1','Q1','Q2','Q2','Q2','Q3','Q3','Q3') AS IndiaFY_Quarter
FROM dbo.Orders
WHERE OrderID IN (1001, 1005, 1013, 1019);   -- Jan Q1/Q4, Feb Q1/Q4, Jun Q2/Q1, Sep Q3/Q2
GO


/* ==== 11. GREATEST / LEAST  (2022+) ==== */

-- 11a. Row-wise max / min across a LIST of values (MAX / MIN work DOWN a column, not across a row).
SELECT GREATEST(10, 25, 7) AS Biggest, LEAST(10, 25, 7) AS Smallest,   -- 25, 7
       GREATEST(5, NULL, 3) AS NullsIgnored;                           -- 5  (NULL only if ALL are NULL)
GO

-- 11b. Real data: cap a discount price at a floor of 1000, and "units we can ship now" = min(stock, 20)
SELECT ProductName, Price, Stock,
       GREATEST(Price * 0.5, 1000) AS HalfPriceButMin1000,   -- Pen 1000.000, Laptop 37500.000
       LEAST(Stock, 20)            AS ShippableNow           -- Pen 20, Laptop 10
FROM dbo.Products
WHERE ProductID IN (1, 8);
GO
-- Pre-2022 way: CASE WHEN Price * 0.5 > 1000 THEN Price * 0.5 ELSE 1000 END


/* ==== 12. SORTING WITH CASE (custom order for Orders.Status) ==== */

-- 12a. Alphabetical order would be Cancelled, Completed, Pending. Business wants Pending FIRST.
SELECT OrderID, Status, OrderDate
FROM dbo.Orders
ORDER BY CASE Status WHEN 'Pending' THEN 1 WHEN 'Completed' THEN 2 WHEN 'Cancelled' THEN 3 END,
         OrderDate;   -- 1015, 1017 (Pending) then 1001 ... (Completed) then 1006 (Cancelled) last
GO

-- 12b. NULLs last (ascending sort puts NULL first in SQL Server): contractors at the bottom
SELECT EmployeeName, DepartmentID
FROM dbo.Employees
ORDER BY CASE WHEN DepartmentID IS NULL THEN 1 ELSE 0 END, DepartmentID, EmployeeName;   -- Anjali is the last row
GO

-- 12c. Conditional sort direction from a variable (the "dynamic ORDER BY" without dynamic SQL)
DECLARE @SortBy VARCHAR(10) = 'Name';   -- try 'Salary'
SELECT EmployeeName, Salary
FROM dbo.Employees
ORDER BY CASE WHEN @SortBy = 'Name'   THEN EmployeeName END,
         CASE WHEN @SortBy = 'Salary' THEN Salary END DESC;   -- alphabetical: Amit, Anjali, Deepak, ...
GO

/* ------------------------------------------------------------
   DONE. Next: Exercises.sql
   (No CLEANUP needed: nothing was created; the UPDATE was rolled back.)
   ------------------------------------------------------------ */
