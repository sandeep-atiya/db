/* ============================================================
   LEVEL 20 - ADVANCED AND ADMIN  |  01_Practice_Advanced_TSQL.sql
   ------------------------------------------------------------
   Topics : dynamic SQL recap (sp_executesql in/out params, QUOTENAME +
            STRING_AGG column lists, injection demo), STRING_AGG /
            STRING_SPLIT, PIVOT / UNPIVOT, GENERATE_SERIES / DATE_BUCKET /
            DATETRUNC, IS DISTINCT FROM, GREATEST / LEAST, TRIM with
            characters, APPROX_COUNT_DISTINCT, temporal (system-versioned)
            tables, computed columns (PERSISTED), sparse columns,
            full-text search (checked, runs only if installed).

   HOW TO PRACTICE: run block by block, predict the output first.
   Helper objects are prefixed L20_ and dropped in CLEANUP.
   ============================================================ */

USE SQLPractice;
GO
SET QUOTED_IDENTIFIER ON;      -- required for an index on a computed column (section 7); sqlcmd defaults to OFF
SET NOCOUNT ON;
GO


/* ============================================================
   1. DYNAMIC SQL RECAP (Level 14 in 5 minutes)
   ============================================================ */
-- 1a. sp_executesql with an INPUT parameter: the SQL text is constant, only the value changes
--     -> one cached plan, no injection possible through the value.
DECLARE @sql NVARCHAR(MAX) = N'SELECT DepartmentID, DepartmentName FROM dbo.Departments WHERE Location = @loc ORDER BY DepartmentID;';
EXEC sp_executesql @sql, N'@loc VARCHAR(100)', @loc = 'Delhi';      -- 3 rows: IT, HR, Legal
GO
-- 1b. OUTPUT parameter: get a value back from the dynamic statement
DECLARE @sql NVARCHAR(MAX) = N'SELECT @cnt = COUNT(*) FROM dbo.Employees WHERE DepartmentID = @dept;';
DECLARE @result INT;
EXEC sp_executesql @sql, N'@dept INT, @cnt INT OUTPUT', @dept = 1, @cnt = @result OUTPUT;
SELECT @result AS ItEmployees;                                       -- 3 (Rahul, Amit, Pooja)
GO
-- 1c. Building a column list safely: QUOTENAME every identifier, STRING_AGG them together (2017+)
DECLARE @cols NVARCHAR(MAX) =
    (SELECT STRING_AGG(QUOTENAME(name), ', ') WITHIN GROUP (ORDER BY column_id)
     FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Products'));
DECLARE @sql NVARCHAR(MAX) = N'SELECT TOP (3) ' + @cols + N' FROM dbo.Products ORDER BY ProductID;';
PRINT @sql;                                                          -- SELECT TOP (3) [ProductID], [ProductName], [Category], [Price], [Stock] FROM ...
EXEC sp_executesql @sql;                                             -- Laptop, Mouse, Keyboard
GO
-- 1d. SQL INJECTION: concatenating user input into the text
DECLARE @name VARCHAR(100) = 'Aarav Sharma';
DECLARE @bad NVARCHAR(MAX) = N'SELECT CustomerID, CustomerName FROM dbo.Customers WHERE CustomerName = ''' + @name + ''';';
EXEC (@bad);                                                         -- 1 row: fine so far
SET @name = 'x'' OR 1=1 --';                                         -- what an attacker types into the search box
SET @bad = N'SELECT CustomerID, CustomerName FROM dbo.Customers WHERE CustomerName = ''' + @name + ''';';
PRINT @bad;                                                          -- ... WHERE CustomerName = 'x' OR 1=1 --';
EXEC (@bad);                                                         -- ALL 8 customers leak out (imagine '; DROP TABLE ...')
-- The fix: the value travels as a PARAMETER, never as text
EXEC sp_executesql N'SELECT CustomerID, CustomerName FROM dbo.Customers WHERE CustomerName = @n;', N'@n VARCHAR(100)', @n = @name;   -- 0 rows
GO


/* ============================================================
   2. STRING_AGG and STRING_SPLIT - lists in, lists out
   ============================================================ */
-- 2a. Rows -> one comma list per group (2017+). WITHIN GROUP controls the order inside the list.
SELECT d.DepartmentName, STRING_AGG(e.EmployeeName, ', ') WITHIN GROUP (ORDER BY e.EmployeeName) AS Members
FROM dbo.Departments d
LEFT JOIN dbo.Employees e ON e.DepartmentID = d.DepartmentID
GROUP BY d.DepartmentName
ORDER BY d.DepartmentName;                                           -- 6 rows; Legal -> NULL; IT -> Amit, Pooja, Rahul
GO
-- 2b. Comma list -> rows, the real use: an app sends '1,3,5' and wants those customers' orders.
--     Never build 'IN (' + @list + ')' with dynamic SQL - join to STRING_SPLIT instead.
DECLARE @ids VARCHAR(100) = '1,3,5';
SELECT c.CustomerID, c.CustomerName, COUNT(o.OrderID) AS Orders
FROM dbo.Customers c
JOIN STRING_SPLIT(@ids, ',') s ON s.value = c.CustomerID              -- value is VARCHAR; converted to INT here (small list, fine)
LEFT JOIN dbo.Orders o ON o.CustomerID = c.CustomerID
GROUP BY c.CustomerID, c.CustomerName
ORDER BY c.CustomerID;                                               -- Aarav 4, Chirag 3, Esha 2
GO
-- 2c. SQL 2022+: the third argument 1 adds an ordinal column so you can keep the list order
SELECT value, ordinal FROM STRING_SPLIT('red,green,blue', ',', 1) ORDER BY ordinal;   -- red 1, green 2, blue 3
GO


/* ============================================================
   3. PIVOT and UNPIVOT recap
   ============================================================ */
-- 3a. PIVOT: one row per customer, one column per Status (values must be known in advance)
SELECT CustomerID, ISNULL([Completed], 0) AS Completed, ISNULL([Pending], 0) AS Pending, ISNULL([Cancelled], 0) AS Cancelled
FROM (SELECT CustomerID, Status, OrderID FROM dbo.Orders) src
PIVOT (COUNT(OrderID) FOR Status IN ([Completed], [Pending], [Cancelled])) p
ORDER BY CustomerID;                                                 -- 7 rows: customer 1 -> 3,1,0 ; customer 5 -> 1,0,1
GO
-- 3b. UNPIVOT: columns back into rows (Price and Stock become attribute/value pairs)
SELECT ProductName, Attribute, Value
FROM (SELECT ProductName, CAST(Price AS DECIMAL(12,2)) AS Price, CAST(Stock AS DECIMAL(12,2)) AS Stock
      FROM dbo.Products WHERE ProductID <= 2) src
UNPIVOT (Value FOR Attribute IN (Price, Stock)) u;                   -- 4 rows: Laptop Price 75000, Laptop Stock 10, Mouse ...
GO


/* ============================================================
   4. GENERATE_SERIES, DATE_BUCKET, DATETRUNC  (SQL 2022+)
   ============================================================ */
-- 4a. A calendar of months from GENERATE_SERIES so months WITHOUT orders still show up (0)
SELECT DATEADD(MONTH, s.value, '2025-01-01') AS MonthStart,
       COUNT(o.OrderID) AS Orders
FROM GENERATE_SERIES(0, 11) s
LEFT JOIN dbo.Orders o ON o.OrderDate >= DATEADD(MONTH, s.value, '2025-01-01')
                      AND o.OrderDate <  DATEADD(MONTH, s.value + 1, '2025-01-01')
GROUP BY s.value
ORDER BY s.value;                                                    -- 12 rows: Jan 3, Feb 3, Mar 2, Apr 2, May 2, Jun 2, Jul 2, Aug 2, Sep 1, Oct-Dec 0
GO
-- 4b. DATETRUNC(part, date) = start of the period; DATE_BUCKET(part, width, date) = start of an n-part bucket
SELECT DATETRUNC(QUARTER, OrderDate) AS QuarterStart, COUNT(*) AS Orders, SUM(TotalAmount) AS Revenue
FROM dbo.Orders
GROUP BY DATETRUNC(QUARTER, OrderDate)
ORDER BY QuarterStart;                                               -- Q1 8 orders, Q2 6, Q3 5
GO
SELECT DATE_BUCKET(WEEK, 2, OrderDate) AS TwoWeekBucket, COUNT(*) AS Orders
FROM dbo.Orders
GROUP BY DATE_BUCKET(WEEK, 2, OrderDate)
ORDER BY TwoWeekBucket;                                              -- buckets of 14 days counted from the default origin (1900-01-01)
GO


/* ============================================================
   5. IS DISTINCT FROM, GREATEST / LEAST, TRIM(chars), APPROX_COUNT_DISTINCT
   ============================================================ */
-- 5a. IS [NOT] DISTINCT FROM (2022+) = "<>" / "=" that treats NULL as a normal value
SELECT COUNT(*) AS NotEq         FROM dbo.Employees WHERE ManagerID <> 101;                    -- 4  (NULL managers are dropped)
SELECT COUNT(*) AS DistinctFrom  FROM dbo.Employees WHERE ManagerID IS DISTINCT FROM 101;      -- 10 (NULL managers included)
SELECT CASE WHEN NULL IS DISTINCT FROM NULL THEN 'different' ELSE 'same' END AS NullVsNull;    -- same
GO
-- 5b. GREATEST / LEAST (2022+): row-wise max/min across columns (before: CASE or VALUES trick)
SELECT ProductName, Price, GREATEST(Price, 5000) AS PriceFloor5000, LEAST(Stock, 20) AS StockCappedAt20
FROM dbo.Products WHERE ProductID IN (2, 6);                          -- Mouse 1000 -> 5000, stock 100 -> 20; Monitor 25000 -> 25000, 25 -> 20
GO
-- 5c. TRIM with characters (2017+) and with LEADING/TRAILING/BOTH (2022+)
SELECT TRIM('#' FROM '##123##') AS BothHash,                           -- 123
       TRIM(LEADING '0' FROM '000450') AS NoLeadingZeros,               -- 450
       TRIM(TRAILING '.' FROM 'end...') AS NoTrailingDots,              -- end
       TRIM(' -' FROM ' -- hello -- ') AS SpacesAndDashes;              -- hello
GO
-- 5d. APPROX_COUNT_DISTINCT (2019+): HyperLogLog, about 2% error, tiny memory - for billions of rows
SELECT COUNT(DISTINCT CustomerID) AS Exact, APPROX_COUNT_DISTINCT(CustomerID) AS Approx FROM dbo.Orders;   -- 7, 7 (tiny table = exact)
GO


/* ============================================================
   6. TEMPORAL (SYSTEM-VERSIONED) TABLES - the database keeps history for you
   ============================================================ */
IF OBJECT_ID('dbo.L20_Products_Temporal') IS NOT NULL
BEGIN
    ALTER TABLE dbo.L20_Products_Temporal SET (SYSTEM_VERSIONING = OFF);
    DROP TABLE dbo.L20_Products_Temporal;
    DROP TABLE IF EXISTS dbo.L20_Products_History;
END
GO
-- Two period columns (UTC, maintained by the engine) + a history table that stores every old version.
CREATE TABLE dbo.L20_Products_Temporal
(
    ProductID   INT           NOT NULL PRIMARY KEY,
    ProductName VARCHAR(100)  NOT NULL,
    Price       DECIMAL(12,2) NOT NULL,
    ValidFrom   DATETIME2(2) GENERATED ALWAYS AS ROW START NOT NULL,
    ValidTo     DATETIME2(2) GENERATED ALWAYS AS ROW END   NOT NULL,
    PERIOD FOR SYSTEM_TIME (ValidFrom, ValidTo)
)
WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = dbo.L20_Products_History));
GO
INSERT INTO dbo.L20_Products_Temporal (ProductID, ProductName, Price)
SELECT ProductID, ProductName, Price FROM dbo.Products WHERE ProductID <= 3;    -- Laptop 75000, Mouse 1000, Keyboard 2500
GO
DECLARE @before DATETIME2(2) = SYSUTCDATETIME();          -- remember "now" (UTC, like the period columns)
WAITFOR DELAY '00:00:00.200';
UPDATE dbo.L20_Products_Temporal SET Price = Price * 1.10 WHERE ProductID = 1;   -- 82500
WAITFOR DELAY '00:00:00.200';   -- a version that lives 0 ms (same DATETIME2(2) tick) is hidden by FOR SYSTEM_TIME ALL
UPDATE dbo.L20_Products_Temporal SET Price = Price * 1.20 WHERE ProductID = 1;   -- 99000
SELECT 'now'   AS Version, ProductID, Price FROM dbo.L20_Products_Temporal WHERE ProductID = 1;                             -- 99000
SELECT 'as of' AS Version, ProductID, Price FROM dbo.L20_Products_Temporal FOR SYSTEM_TIME AS OF @before WHERE ProductID = 1; -- 75000 (the past!)
SELECT 'all'   AS Version, ProductID, Price, ValidFrom, ValidTo
FROM dbo.L20_Products_Temporal FOR SYSTEM_TIME ALL WHERE ProductID = 1 ORDER BY ValidFrom;                              -- 3 versions: 75000, 82500, 99000 (last ValidTo = 9999-12-31)
GO
SELECT COUNT(*) AS HistoryRows FROM dbo.L20_Products_History;         -- 2 (the two replaced versions)
-- Other clauses: FOR SYSTEM_TIME FROM a TO b / BETWEEN a AND b / CONTAINED IN (a, b).
-- Use cases: audit without triggers, "what did the price list look like on 1 April", undo a bad update.
GO


/* ============================================================
   7. COMPUTED COLUMNS (PERSISTED) and SPARSE COLUMNS
   ============================================================ */
DROP TABLE IF EXISTS dbo.L20_OrderLines;
SELECT OrderDetailID, OrderID, ProductID, Quantity, UnitPrice INTO dbo.L20_OrderLines FROM dbo.OrderDetails;
-- 7a. A computed column is a formula; PERSISTED stores the result (and allows an index on it).
ALTER TABLE dbo.L20_OrderLines ADD LineTotal AS (Quantity * UnitPrice) PERSISTED;
CREATE INDEX IX_L20_OrderLines_LineTotal ON dbo.L20_OrderLines (LineTotal);
GO
SELECT OrderID, ProductID, Quantity, UnitPrice, LineTotal FROM dbo.L20_OrderLines WHERE LineTotal >= 75000 ORDER BY LineTotal DESC;   -- 4 rows (150000 first: order 1014 = 2 laptops)
SELECT name, is_computed, is_persisted FROM sys.computed_columns WHERE object_id = OBJECT_ID('dbo.L20_OrderLines');                   -- LineTotal 1 1
GO
-- 7b. SPARSE columns: NULLs take zero space; use for columns that are NULL in > 90% of rows.
DROP TABLE IF EXISTS dbo.L20_Sparse;
CREATE TABLE dbo.L20_Sparse (Id INT PRIMARY KEY, Name VARCHAR(50) NOT NULL, RarelyUsedNote VARCHAR(500) SPARSE NULL);
INSERT INTO dbo.L20_Sparse VALUES (1, 'a', NULL), (2, 'b', 'only this row has a note');
SELECT name, is_sparse FROM sys.columns WHERE object_id = OBJECT_ID('dbo.L20_Sparse');   -- RarelyUsedNote 1
GO


/* ============================================================
   8. FULL-TEXT SEARCH - word search on text columns (separate feature, must be installed)
   ============================================================ */
DROP TABLE IF EXISTS dbo.L20_Docs;
CREATE TABLE dbo.L20_Docs (DocID INT NOT NULL CONSTRAINT PK_L20_Docs PRIMARY KEY, Title VARCHAR(100), Body VARCHAR(MAX));
INSERT INTO dbo.L20_Docs VALUES
(1, 'Laptop care',    'Keep the laptop battery between 20 and 80 percent for a long life.'),
(2, 'Keyboard tips',  'Mechanical keyboards last longer than membrane keyboards.'),
(3, 'Monitor setup',  'Place the monitor at eye level; laptops need a stand.');
GO
IF FULLTEXTSERVICEPROPERTY('IsFullTextInstalled') = 1
BEGIN
    PRINT 'Full-text is installed: creating a catalog + index on dbo.L20_Docs and running CONTAINS / FREETEXT';
    EXEC (N'IF NOT EXISTS (SELECT 1 FROM sys.fulltext_catalogs WHERE name = ''L20_Catalog'') CREATE FULLTEXT CATALOG L20_Catalog AS DEFAULT;');
    EXEC (N'CREATE FULLTEXT INDEX ON dbo.L20_Docs (Title, Body) KEY INDEX PK_L20_Docs ON L20_Catalog WITH CHANGE_TRACKING AUTO;');
    WAITFOR DELAY '00:00:05';                                         -- population is asynchronous
    EXEC (N'SELECT DocID, Title FROM dbo.L20_Docs WHERE CONTAINS(Body, ''laptop OR laptops'');');            -- 1, 3
    EXEC (N'SELECT DocID, Title FROM dbo.L20_Docs WHERE CONTAINS(Body, ''"mechanical key*"'');');           -- 2 (prefix search)
    EXEC (N'SELECT DocID, Title FROM dbo.L20_Docs WHERE FREETEXT(Body, ''long lasting keyboard'');');       -- meaning-based, 2 (and maybe others)
    EXEC (N'DROP FULLTEXT INDEX ON dbo.L20_Docs; DROP FULLTEXT CATALOG L20_Catalog;');
END
ELSE
BEGIN
    PRINT 'Full-text search is NOT installed on this instance (SELECT FULLTEXTSERVICEPROPERTY(''IsFullTextInstalled'') = 0).';
    PRINT 'Add the "Full-Text and Semantic Extractions for Search" feature with SQL Server setup to try the syntax below.';
END
GO
/* FULL-TEXT SYNTAX (for reference):
   CREATE FULLTEXT CATALOG L20_Catalog AS DEFAULT;
   CREATE FULLTEXT INDEX ON dbo.L20_Docs (Title, Body) KEY INDEX PK_L20_Docs ON L20_Catalog WITH CHANGE_TRACKING AUTO;
   SELECT * FROM dbo.L20_Docs WHERE CONTAINS(Body, 'laptop');                 -- exact word (with inflections: FORMSOF(INFLECTIONAL, laptop))
   SELECT * FROM dbo.L20_Docs WHERE CONTAINS(Body, '"mechanical key*"');      -- phrase + prefix
   SELECT * FROM dbo.L20_Docs WHERE CONTAINS(Body, 'laptop NEAR stand');      -- proximity
   SELECT * FROM dbo.L20_Docs WHERE FREETEXT(Body, 'long lasting keyboard');  -- natural-language, ranked
   SELECT d.Title, k.RANK FROM CONTAINSTABLE(dbo.L20_Docs, Body, 'laptop') k JOIN dbo.L20_Docs d ON d.DocID = k.[KEY] ORDER BY k.RANK DESC;
   Why not LIKE '%word%'?  LIKE with a leading wildcard scans every row and every character (Level 19);
   full-text keeps an inverted word index -> milliseconds on millions of documents.                        */


/* ============================================================
   9. CLEANUP
   ============================================================ */
IF OBJECT_ID('dbo.L20_Products_Temporal') IS NOT NULL
BEGIN
    ALTER TABLE dbo.L20_Products_Temporal SET (SYSTEM_VERSIONING = OFF);   -- must switch off before dropping
    DROP TABLE dbo.L20_Products_Temporal;
    DROP TABLE IF EXISTS dbo.L20_Products_History;
END
DROP TABLE IF EXISTS dbo.L20_OrderLines;
DROP TABLE IF EXISTS dbo.L20_Sparse;
DROP TABLE IF EXISTS dbo.L20_Docs;
GO
/* DONE. Next: 02_Practice_Triggers_Cursors_Sequences.sql */
