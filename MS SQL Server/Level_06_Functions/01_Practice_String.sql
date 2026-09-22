/* ============================================================
   LEVEL 06 - FUNCTIONS  |  01_Practice_String.sql
   ------------------------------------------------------------
   Topics : LEN vs DATALENGTH, LOWER/UPPER, LEFT/RIGHT/SUBSTRING,
            CHARINDEX (start position), PATINDEX, REPLACE,
            TRIM/LTRIM/RTRIM, CONCAT, CONCAT_WS, + with NULL,
            REVERSE, REPLICATE, STUFF, SPACE, STRING_SPLIT,
            STRING_AGG, FORMAT for strings, QUOTENAME,
            practical recipes (email domain, name split, initials,
            mask email, zero-pad an ID).
   HOW TO PRACTICE: run block by block, predict the output first.
   Nothing is created or changed in this file (read-only queries).
   ============================================================ */

USE SQLPractice;
GO


/* ==== 1. LEN vs DATALENGTH ==== */

-- 1a. LEN = number of characters, ignoring TRAILING spaces.
--     DATALENGTH = number of BYTES actually stored (spaces count, Unicode = 2 bytes/char).
SELECT LEN('SQL')             AS Len_SQL,           -- 3
       LEN('SQL   ')          AS Len_TrailingSpc,   -- 3  (trailing spaces ignored)
       LEN('   SQL')          AS Len_LeadingSpc,    -- 6  (leading spaces counted)
       DATALENGTH('SQL   ')   AS Bytes_Varchar,     -- 6  (spaces are stored)
       DATALENGTH(N'SQL')     AS Bytes_Nvarchar;    -- 6  (2 bytes per char)
GO

-- 1b. On real data: name lengths
SELECT CustomerName, LEN(CustomerName) AS NameLen, DATALENGTH(CustomerName) AS NameBytes
FROM dbo.Customers
ORDER BY NameLen DESC, CustomerName;   -- Aarav Sharma / Bhavna Mehta / Chirag Patel / Gaurav Singh = 12
GO

-- 1c. LEN(NULL) is NULL, LEN('') is 0  (empty string is NOT NULL)
SELECT LEN(NULL) AS LenNull, LEN('') AS LenEmpty;   -- NULL, 0
GO


/* ==== 2. LOWER / UPPER ==== */

-- Case functions. Useful for display and for case-insensitive comparisons
-- (although the default collation here is already case-insensitive).
SELECT EmployeeName, UPPER(EmployeeName) AS Upper, LOWER(EmployeeName) AS Lower, LOWER(Email) AS EmailLower
FROM dbo.Employees
WHERE EmployeeID IN (101, 110);   -- RAHUL / rahul ; Anjali email = NULL stays NULL
GO


/* ==== 3. LEFT / RIGHT / SUBSTRING ==== */

-- 3a. LEFT(s, n) = first n chars, RIGHT(s, n) = last n chars,
--     SUBSTRING(s, start, length) = start is 1-based.
SELECT LEFT('Aarav Sharma', 5)         AS FirstFive,   -- Aarav
       RIGHT('Aarav Sharma', 6)        AS LastSix,     -- Sharma
       SUBSTRING('Aarav Sharma', 7, 6) AS Middle,      -- Sharma
       SUBSTRING('Aarav Sharma', 1, 1) AS FirstChar;   -- A
GO

-- 3b. Asking for more characters than exist is NOT an error - you just get what is there.
SELECT LEFT('SQL', 10) AS LeftTooMany, SUBSTRING('SQL', 2, 100) AS SubTooMany;   -- SQL, QL
GO


/* ==== 4. CHARINDEX and PATINDEX ==== */

-- 4a. CHARINDEX(find, in_string [, start]) -> position (1-based) or 0 if not found.
SELECT CHARINDEX('@', 'rahul@example.com')      AS AtPos,       -- 6
       CHARINDEX('z', 'rahul@example.com')      AS NotFound,    -- 0
       CHARINDEX('a', 'Aarav Sharma')           AS FirstA,      -- 1  (case-insensitive collation)
       CHARINDEX('a', 'Aarav Sharma', 5)        AS A_From5,     -- 9  (search starts at position 5)
       CHARINDEX(' ', 'Aarav Sharma')           AS SpacePos;    -- 6
GO

-- 4b. Using the start position: find the SECOND dot in a string
DECLARE @s VARCHAR(50) = 'www.example.co.in';
SELECT CHARINDEX('.', @s)                                AS FirstDot,    -- 4
       CHARINDEX('.', @s, CHARINDEX('.', @s) + 1)        AS SecondDot;   -- 12
GO

-- 4c. PATINDEX works with LIKE-style patterns (% _ [ ]). CHARINDEX cannot do patterns.
SELECT PATINDEX('%[0-9]%', 'Order1001')     AS FirstDigit,      -- 6
       PATINDEX('%[^0-9]%', '123abc')       AS FirstNonDigit,   -- 4
       PATINDEX('%sh%', 'Aarav Sharma')     AS Sh_Pos,          -- 7
       PATINDEX('%xyz%', 'Aarav Sharma')    AS NotFound;        -- 0
GO

-- 4d. Real data: surname (word after the space) has an 'a' AFTER its first letter.
--     Pattern = space, one letter, anything, 'a', anything.
SELECT CustomerName
FROM dbo.Customers
WHERE PATINDEX('% [A-Z]%a%', CustomerName) > 0;   -- 6 rows: Sharma, Mehta, Patel, Nair, Kapoor, Khan  (Ali and Singh do not match)
GO


/* ==== 5. REPLACE ==== */

-- REPLACE(string, find, replace_with). Replaces ALL occurrences. Case-insensitive under default collation.
SELECT REPLACE('rahul@example.com', 'example.com', 'company.in') AS NewDomain,   -- rahul@company.in
       REPLACE('a-b-c', '-', '')                               AS RemoveDashes,  -- abc
       REPLACE('Aarav Sharma', 'a', '*')                       AS StarA;         -- **r*v Sh*rm*
GO

-- Trick: count occurrences of a character = LEN(original) - LEN(REPLACE(char removed))
SELECT CustomerName, LEN(CustomerName) - LEN(REPLACE(CustomerName, 'a', '')) AS CountOfA
FROM dbo.Customers
WHERE CustomerID <= 3;   -- Aarav Sharma 5, Bhavna Mehta 3, Chirag Patel 2
GO


/* ==== 6. TRIM / LTRIM / RTRIM ==== */

-- 6a. Remove spaces from both sides (TRIM, 2017+), left (LTRIM), right (RTRIM).
--     Brackets make the result visible.
SELECT '[' + TRIM('  SQL  ')  + ']' AS Trim,    -- [SQL]
       '[' + LTRIM('  SQL  ') + ']' AS LTrim,   -- [SQL  ]
       '[' + RTRIM('  SQL  ') + ']' AS RTrim;   -- [  SQL]
GO

-- 6b. TRIM can remove OTHER characters too (2017+):  TRIM(chars FROM string)
SELECT TRIM('*' FROM '***Sale***')     AS TrimStars,   -- Sale
       TRIM('#, ' FROM '# 1001, ')     AS TrimSet;     -- 1001   (removes any of '#', ',', ' ')
GO

-- 6c. Why it matters: '  Rahul' <> 'Rahul' in a WHERE, but trailing spaces are ignored in =
SELECT CASE WHEN 'Rahul  ' = 'Rahul' THEN 'trailing ignored' ELSE 'different' END AS Trailing,   -- trailing ignored
       CASE WHEN '  Rahul' = 'Rahul' THEN 'same' ELSE 'leading NOT ignored' END      AS Leading;    -- leading NOT ignored
GO


/* ==== 7. CONCAT, CONCAT_WS and the + NULL trap ==== */

-- 7a. THE TRAP: with + , one NULL makes the WHOLE result NULL.
--     CONCAT treats NULL as '' (empty). Farhan Ali and Hina Khan have NULL email.
SELECT CustomerName,
       CustomerName + ' <' + Email + '>'         AS PlusOperator,   -- NULL for Farhan, Hina
       CONCAT(CustomerName, ' <', Email, '>')    AS ConcatFunc      -- 'Farhan Ali <>'
FROM dbo.Customers
WHERE CustomerID IN (1, 6, 8);
GO

-- 7b. CONCAT also converts numbers/dates to text for you; + would need CAST
SELECT CONCAT('Order ', 1001, ' on ', CAST('2025-01-05' AS DATE)) AS Concat_AutoCast;   -- Order 1001 on 2025-01-05
GO
BEGIN TRY
    SELECT 'Order ' + 1001 AS PlusFails;   -- 'Order ' cannot be converted to INT
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO

-- 7c. CONCAT_WS (2017+) = concat WITH SEPARATOR. NULLs are skipped (no double separator).
SELECT CONCAT_WS(', ', 'Delhi', NULL, 'Mumbai', 'Pune') AS WithSeparator,   -- Delhi, Mumbai, Pune
       CONCAT_WS(' | ', CustomerName, Email, City)       AS CustomerLine
FROM dbo.Customers
WHERE CustomerID IN (1, 6);   -- Aarav Sharma | aarav@example.com | Delhi   /   Farhan Ali | Mumbai
GO


/* ==== 8. REVERSE, REPLICATE, STUFF, SPACE ==== */

-- 8a. REVERSE flips a string. Handy for "find the LAST occurrence" tricks.
SELECT REVERSE('SQL') AS Reversed,                                       -- LQS
       CHARINDEX(' ', REVERSE('Aarav Sharma')) AS LastSpaceFromEnd;     -- 7
GO

-- 8b. REPLICATE(string, n) repeats a string. Classic use: zero padding.
SELECT REPLICATE('0', 5)                     AS FiveZeros,      -- 00000
       REPLICATE('ab', 3)                    AS AbAbAb,         -- ababab
       REPLICATE('0', 5 - LEN('101')) + '101' AS Padded;        -- 00101
GO

-- 8c. STUFF(string, start, delete_count, insert_string): delete then insert at a position.
SELECT STUFF('Hello World', 1, 5, 'Howdy')      AS Replaced,     -- Howdy World
       STUFF('9876543210', 4, 4, 'XXXX')        AS MaskedPhone,  -- 987XXXX210
       STUFF('20250105', 5, 0, '-')             AS InsertDash;   -- 2025-0105 (delete 0 chars = pure insert)
GO

-- 8d. SPACE(n) = n spaces. Same as REPLICATE(' ', n). Useful for aligned text output.
SELECT 'ID' + SPACE(3) + 'Name' AS Header,               -- ID   Name
       LEN('ID' + SPACE(3) + 'Name') AS HeaderLen;       -- 9
GO


/* ==== 9. STRING_SPLIT  (2016+, ordinal column 2022+) ==== */

-- 9a. Turns 'a,b,c' into rows. It is a TABLE function -> use it in FROM.
SELECT value FROM STRING_SPLIT('Delhi,Mumbai,Pune', ',');   -- 3 rows
GO

-- 9b. Order of rows is NOT guaranteed unless you ask for the ordinal (3rd argument = 1, SQL 2022+).
SELECT value, ordinal
FROM STRING_SPLIT('Delhi,Mumbai,Pune', ',', 1)
ORDER BY ordinal;   -- Delhi 1, Mumbai 2, Pune 3
GO

-- 9c. Practical: filter a table by a comma-separated list (what apps send as a parameter)
DECLARE @cities VARCHAR(100) = 'Delhi,Chennai';
SELECT c.CustomerName, c.City
FROM dbo.Customers c
WHERE c.City IN (SELECT TRIM(value) FROM STRING_SPLIT(@cities, ','))
ORDER BY c.CustomerName;   -- Aarav, Chirag, Gaurav, Hina (4 rows)
GO


/* ==== 10. STRING_AGG  (2017+) - the opposite of STRING_SPLIT ==== */

-- 10a. Collapse many rows into ONE comma-separated string.
SELECT STRING_AGG(DepartmentName, ', ') AS AllDepartments
FROM dbo.Departments;   -- Finance, HR, IT, Legal, Marketing, Sales
-- (alphabetical here only because the UNIQUE index on DepartmentName is read in order - NOT guaranteed, see 10b)
GO

-- 10b. WITHIN GROUP (ORDER BY ...) makes the order inside the string deterministic.
SELECT STRING_AGG(DepartmentName, ', ') WITHIN GROUP (ORDER BY DepartmentName) AS Sorted
FROM dbo.Departments;   -- Finance, HR, IT, Legal, Marketing, Sales
GO

-- 10c. Per group (one line per department). NULL names would be skipped by STRING_AGG.
SELECT d.DepartmentName,
       STRING_AGG(e.EmployeeName, ', ') WITHIN GROUP (ORDER BY e.EmployeeName) AS Members
FROM dbo.Departments d
JOIN dbo.Employees e ON e.DepartmentID = d.DepartmentID
GROUP BY d.DepartmentName
ORDER BY d.DepartmentName;   -- IT = Amit, Pooja, Rahul ; Sales = Neha, Priya, Vikram ; (5 rows, Legal missing)
GO


/* ==== 11. FORMAT for strings, QUOTENAME ==== */

-- 11a. FORMAT(value, format) uses .NET format strings. Great for display, SLOW on big tables.
SELECT FORMAT(101, '00000')            AS ZeroPad,      -- 00101
       FORMAT(7, 'D3')                 AS D3,           -- 007
       FORMAT(1234567.891, 'N2')       AS Thousands,    -- 1,234,567.89
       FORMAT(0.256, 'P1')             AS PercentOne,   -- 25.6%
       FORMAT(75000, '#,##0')          AS Custom;       -- 75,000
GO

-- 11b. QUOTENAME wraps an identifier in [ ] so names with spaces / keywords are safe in dynamic SQL.
SELECT QUOTENAME('Order Details')      AS Brackets,     -- [Order Details]
       QUOTENAME('Select')             AS Keyword,      -- [Select]
       QUOTENAME('O''Brien', '''')     AS SingleQuoted; -- 'O''Brien'  (doubles the inner quote)
GO


/* ==== 12. PRACTICAL RECIPES (interview favourites) ==== */

-- 12a. Extract the domain from an email
SELECT Email,
       SUBSTRING(Email, CHARINDEX('@', Email) + 1, LEN(Email)) AS Domain,        -- example.com
       RIGHT(Email, LEN(Email) - CHARINDEX('@', Email))        AS Domain2,       -- same result, other way
       LEFT(Email, CHARINDEX('@', Email) - 1)                  AS UserPart       -- rahul
FROM dbo.Employees
WHERE Email IS NOT NULL AND EmployeeID <= 103;
GO

-- 12b. Split CustomerName into first and last name (works when there is exactly one space)
SELECT CustomerName,
       LEFT(CustomerName, CHARINDEX(' ', CustomerName) - 1)                       AS FirstName,   -- Aarav
       SUBSTRING(CustomerName, CHARINDEX(' ', CustomerName) + 1, LEN(CustomerName)) AS LastName,    -- Sharma
       RIGHT(CustomerName, CHARINDEX(' ', REVERSE(CustomerName)) - 1)             AS LastName2    -- Sharma (REVERSE trick)
FROM dbo.Customers
WHERE CustomerID <= 3;
GO

-- 12c. Initials: first letter of each of the two words
SELECT CustomerName,
       LEFT(CustomerName, 1) + SUBSTRING(CustomerName, CHARINDEX(' ', CustomerName) + 1, 1) AS Initials   -- AS, BM, CP
FROM dbo.Customers
WHERE CustomerID <= 3;
GO

-- 12d. Mask an email: keep first letter and the domain -> r****@example.com
SELECT Email,
       LEFT(Email, 1) + REPLICATE('*', CHARINDEX('@', Email) - 2) + SUBSTRING(Email, CHARINDEX('@', Email), LEN(Email)) AS Masked
FROM dbo.Employees
WHERE Email IS NOT NULL AND EmployeeID <= 103;   -- r****@example.com, a***@example.com, p****@example.com
GO

-- 12e. Pad an ID to 5 digits (3 ways)
SELECT EmployeeID,
       RIGHT('00000' + CAST(EmployeeID AS VARCHAR(5)), 5)             AS Pad_Right,       -- 00101
       REPLICATE('0', 5 - LEN(CAST(EmployeeID AS VARCHAR(5)))) + CAST(EmployeeID AS VARCHAR(5)) AS Pad_Replicate,
       FORMAT(EmployeeID, '00000')                                    AS Pad_Format,      -- slowest, easiest
       'EMP' + FORMAT(EmployeeID, '00000')                            AS Code             -- EMP00101
FROM dbo.Employees
WHERE EmployeeID <= 102;
GO

-- 12f. Bonus: a display-ready line per customer, NULL-safe
SELECT CONCAT_WS(' - ', FORMAT(CustomerID, '000'), UPPER(CustomerName), ISNULL(Email, 'no email'), City) AS Line
FROM dbo.Customers
ORDER BY CustomerID;   -- 001 - AARAV SHARMA - aarav@example.com - Delhi ... 006 - FARHAN ALI - no email - Mumbai
GO

/* ------------------------------------------------------------
   DONE. Next: 02_Practice_Date.sql
   (No CLEANUP needed: this file created nothing.)
   ------------------------------------------------------------ */
