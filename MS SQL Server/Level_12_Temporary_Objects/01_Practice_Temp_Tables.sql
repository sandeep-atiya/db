/* ============================================================
   LEVEL 12 - TEMPORARY OBJECTS  |  01_Practice_Temp_Tables.sql
   ------------------------------------------------------------
   Topics : what tempdb is and why it matters, local temp tables
            (#T: CREATE TABLE #, SELECT ... INTO #, scope, DROP IF
            EXISTS, PK / indexes / constraints / statistics, the
            real name in tempdb.sys.tables), global temp tables
            (##T), INSERT ... EXEC into #T, the "stage in #temp
            then join" performance pattern.
   HOW TO PRACTICE: run block by block, predict the output first.
   Everything here runs in ONE query window. The two-window part
   (who can see a ## table) is described in 03_Two_Sessions_Demo.sql.
   ============================================================ */

USE SQLPractice;
GO
-- Clean start (temp tables die with the session, but this file may be re-run in the same window)
DROP TABLE IF EXISTS #L12_Emp, #L12_PendingOrders, #L12_Nums, #L12_CustOrders, #L12_CustTotals, ##L12_Global;
DROP PROCEDURE IF EXISTS dbo.usp_L12_ReadCallersTemp, dbo.usp_L12_MakeOwnTemp, dbo.usp_L12_GetOrders;
GO


/* ==== 1. WHAT IS TEMPDB ==== */
-- tempdb is ONE system database shared by EVERY database and EVERY user on the
-- server. It holds: #temp tables, ##global temp tables, table variables, work
-- tables for sorts / hashes / spools, cursors, row versions (snapshot isolation).
-- It is rebuilt from "model" every time the service restarts -> nothing survives,
-- and a busy (or full) tempdb slows down EVERYBODY. That is why it matters.

-- 1a. tempdb's create_date = the last time SQL Server was restarted
SELECT name, create_date AS RebuiltAt_LastRestart
FROM sys.databases
WHERE name = 'tempdb';
GO

-- 1b. Its files (best practice: several equal-size data files on a fast disk)
SELECT name AS LogicalName, type_desc, size * 8 / 1024 AS SizeMB, physical_name
FROM tempdb.sys.database_files;
GO


/* ==== 2. LOCAL TEMP TABLE  #T ==== */
-- One # = local. Only YOUR session (and any proc you call from it) can see it.
-- Lives in tempdb. Dropped automatically when your session (or the proc that
-- created it) ends. DROP TABLE IF EXISTS first, so a block can be re-run.

-- 2a. CREATE TABLE #... : you control columns, PK, constraints
CREATE TABLE #L12_Emp
(
    EmployeeID   INT           NOT NULL PRIMARY KEY,   -- unnamed on purpose: see 2f
    EmployeeName VARCHAR(100)  NOT NULL,
    Salary       DECIMAL(12,2) NULL
);
INSERT INTO #L12_Emp (EmployeeID, EmployeeName, Salary)
SELECT e.EmployeeID, e.EmployeeName, e.Salary
FROM dbo.Employees e
WHERE e.DepartmentID = 1;                 -- IT

SELECT * FROM #L12_Emp;                   -- 3 rows: Rahul 85000, Amit 65000, Pooja 65000
GO

-- 2b. SELECT ... INTO #... : creates AND fills the table in one statement.
--     Column names / types / NOT NULL are copied; constraints and indexes are NOT.
SELECT o.OrderID, o.CustomerID, o.OrderDate, o.TotalAmount
INTO #L12_PendingOrders
FROM dbo.Orders o
WHERE o.Status = 'Pending';

SELECT * FROM #L12_PendingOrders;         -- 2 rows: 1015 (32000), 1017 (4000)
GO

-- 2c. Where does it really live? In tempdb, under a name made unique for your
--     session: your name + underscores + a hex counter = 128 characters.
--     That is how 50 users can each have their own #L12_Emp at the same time.
SELECT name, LEN(name) AS NameLength, create_date
FROM tempdb.sys.tables
WHERE name LIKE '#L12[_]Emp%';            -- [_] = literal underscore (a bare _ in LIKE means "any one char")
GO
-- The friendly way to test "does my temp table exist?" (note the TWO dots):
SELECT OBJECT_ID('tempdb..#L12_Emp')      AS Exists_ObjectId,   -- a number
       OBJECT_ID('tempdb..#L12_Nothing')  AS Missing_ObjectId;  -- NULL
GO

-- 2d. SCOPE = your session. It survives GO ...
SELECT COUNT(*) AS StillHereAfterGO FROM #L12_Emp;   -- 3
GO
--     ... and a stored procedure CALLED from this session can read it, even
--     though the proc did not create it (very common in reporting code).
CREATE OR ALTER PROCEDURE dbo.usp_L12_ReadCallersTemp
AS
BEGIN
    SET NOCOUNT ON;
    SELECT COUNT(*) AS RowsSeenInsideProc FROM #L12_Emp;
END
GO
EXEC dbo.usp_L12_ReadCallersTemp;         -- 3
GO

-- 2e. The other direction does NOT work: a temp table created INSIDE a proc is
--     dropped the moment the proc ends. The caller never sees it.
CREATE OR ALTER PROCEDURE dbo.usp_L12_MakeOwnTemp
AS
BEGIN
    SET NOCOUNT ON;
    CREATE TABLE #L12_Inside (n INT);
    INSERT INTO #L12_Inside VALUES (1), (2);
    SELECT OBJECT_ID('tempdb..#L12_Inside') AS InsideProc_ObjectId;   -- a number
END
GO
EXEC dbo.usp_L12_MakeOwnTemp;
SELECT OBJECT_ID('tempdb..#L12_Inside') AS AfterProc_ObjectId;        -- NULL: gone with the proc
GO

-- 2f. A #temp table is a REAL table: indexes, constraints, statistics all work.
CREATE TABLE #L12_Nums
(
    n      INT         NOT NULL PRIMARY KEY,           -- clustered index
    Bucket INT         NOT NULL,
    Note   VARCHAR(20) NOT NULL CHECK (Note <> '')     -- CHECK works; left UNNAMED (see gotcha below)
);
INSERT INTO #L12_Nums (n, Bucket, Note)
SELECT value, value % 10, CONCAT('row ', value)
FROM GENERATE_SERIES(1, 1000);                         -- 2022+; older versions: use a numbers CTE

CREATE NONCLUSTERED INDEX IX_L12_Nums_Bucket ON #L12_Nums (Bucket);   -- add an index any time
GO
-- Run two filtered queries ...
SELECT COUNT(*) AS RowsInBucket7 FROM #L12_Nums WHERE Bucket = 7;       -- 100
SELECT COUNT(*) AS RowsNamed500  FROM #L12_Nums WHERE Note = 'row 500';  -- 1
GO
-- ... and SQL Server has auto-created STATISTICS on Note (name _WA_Sys_...), next to
-- the PK and index statistics. Statistics = "how many rows will match?" = good plans.
-- Table variables never get these (see file 02).
SELECT s.name AS StatsName, s.auto_created, c.name AS ColumnName
FROM tempdb.sys.stats s
JOIN tempdb.sys.stats_columns sc ON sc.object_id = s.object_id AND sc.stats_id = s.stats_id
JOIN tempdb.sys.columns c        ON c.object_id = sc.object_id AND c.column_id = sc.column_id
WHERE s.object_id = OBJECT_ID('tempdb..#L12_Nums');
-- 3 rows: PK__#L12_Num... (n), IX_L12_Nums_Bucket (Bucket), _WA_Sys_... (Note, auto_created = 1)
GO
-- GOTCHA: never NAME a constraint on a temp table (CONSTRAINT PK_Temp PRIMARY KEY ...).
-- The TABLE name is made unique per session, the CONSTRAINT name is not: the second
-- session running the same code fails with "There is already an object named 'PK_Temp'".
-- Index names are per table, so naming an INDEX is safe.

-- 2g. DROP TABLE IF EXISTS works for temp tables too (silent when already gone)
DROP TABLE IF EXISTS #L12_PendingOrders;
DROP TABLE IF EXISTS #L12_PendingOrders;   -- second time: no error
GO


/* ==== 3. GLOBAL TEMP TABLE  ##T ==== */
-- Two ## = global. EVERY session on the server can see and use it. The name is NOT
-- made unique. It is dropped when the creating session ends AND no other session
-- is still running a statement on it.
CREATE TABLE ##L12_Global
(
    CustomerID INT           NOT NULL PRIMARY KEY,
    TotalSpent DECIMAL(12,2) NOT NULL
);
INSERT INTO ##L12_Global (CustomerID, TotalSpent)
SELECT o.CustomerID, SUM(o.TotalAmount)
FROM dbo.Orders o
GROUP BY o.CustomerID;

SELECT TOP (3) * FROM ##L12_Global ORDER BY TotalSpent DESC;   -- 5 (158000), 1 (128000), 6 (88500)
GO
-- In tempdb.sys.tables the name is stored EXACTLY, no padding: it must be shareable.
SELECT name, LEN(name) AS NameLength
FROM tempdb.sys.tables
WHERE name = '##L12_Global';             -- ##L12_Global, 12
GO
-- Use: hand a result to ANOTHER session (a colleague's window, a job step).
-- Risk: anyone can read, change or DROP it -> rare in production code.
-- Two-window walkthrough: 03_Two_Sessions_Demo.sql
DROP TABLE IF EXISTS ##L12_Global;
GO


/* ==== 4. INSERT ... EXEC : capture a procedure's result set ==== */
-- A proc that returns rows only sends them to the screen. To WORK with them
-- (filter, join, aggregate) you must land them in a table first.
CREATE OR ALTER PROCEDURE dbo.usp_L12_GetOrders
    @CustomerID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT o.OrderID, o.OrderDate, o.TotalAmount, o.Status
    FROM dbo.Orders o
    WHERE o.CustomerID = @CustomerID
    ORDER BY o.OrderDate;
END
GO
EXEC dbo.usp_L12_GetOrders @CustomerID = 1;   -- 4 rows on screen, nowhere else
GO

-- 4a. The target table must exist and have the same NUMBER of columns, in the
--     same ORDER, with compatible types (column names do not matter).
CREATE TABLE #L12_CustOrders
(
    OrderID     INT           NOT NULL,
    OrderDate   DATE          NULL,
    TotalAmount DECIMAL(12,2) NULL,
    Status      VARCHAR(20)   NOT NULL
);
INSERT INTO #L12_CustOrders (OrderID, OrderDate, TotalAmount, Status)
EXEC dbo.usp_L12_GetOrders @CustomerID = 1;

INSERT INTO #L12_CustOrders (OrderID, OrderDate, TotalAmount, Status)
EXEC dbo.usp_L12_GetOrders @CustomerID = 5;    -- appends

SELECT Status, COUNT(*) AS Orders, SUM(TotalAmount) AS Total
FROM #L12_CustOrders
GROUP BY Status
ORDER BY Status;   -- Cancelled 1 / 8000, Completed 4 / 246000, Pending 1 / 32000
GO
-- 4b. Works with dynamic SQL too
INSERT INTO #L12_CustOrders (OrderID, OrderDate, TotalAmount, Status)
EXEC ('SELECT OrderID, OrderDate, TotalAmount, Status FROM dbo.Orders WHERE OrderID = 1019');
SELECT COUNT(*) AS RowsNow FROM #L12_CustOrders;   -- 7
GO
-- Limits: INSERT ... EXEC cannot be nested (a proc that itself does INSERT ... EXEC
-- cannot be the source of another INSERT ... EXEC), and every result set the proc
-- returns must have the same shape. Cleaner alternative: a table-valued function (Level 15).


/* ==== 5. PERFORMANCE PATTERN: stage in #temp, then join ==== */
-- Reports often need the same heavy aggregate several times. Compute it ONCE into a
-- #temp table (with a PK), then join the small result to other tables as often as
-- you like. Bonus: the #temp gets statistics, so the joins are planned well.
SELECT o.CustomerID, COUNT(*) AS CompletedOrders, SUM(o.TotalAmount) AS Revenue
INTO #L12_CustTotals
FROM dbo.Orders o
WHERE o.Status = 'Completed'
GROUP BY o.CustomerID;

ALTER TABLE #L12_CustTotals ADD PRIMARY KEY (CustomerID);   -- index the join key
GO
-- Reuse 1: customer report
SELECT c.CustomerName, c.City, t.CompletedOrders, t.Revenue
FROM #L12_CustTotals t
JOIN dbo.Customers c ON c.CustomerID = t.CustomerID
ORDER BY t.Revenue DESC;          -- 7 rows: Esha Kapoor 150000 first ... Chirag Patel 26500 last (Hina: no orders)
GO
-- Reuse 2: city report, without re-aggregating Orders
SELECT c.City, SUM(t.Revenue) AS CityRevenue
FROM #L12_CustTotals t
JOIN dbo.Customers c ON c.CustomerID = t.CustomerID
GROUP BY c.City
ORDER BY CityRevenue DESC;        -- Bangalore 150000, Mumbai 137000, Delhi 122500, Chennai 87000, Pune 77500
GO
-- Same idea, bigger payoff: break a 6-table monster query into 2-3 staged steps.
-- Each step is easy to read, easy to check (SELECT from the #temp) and easy to tune.


/* ==== 6. CLEANUP ==== */
DROP TABLE IF EXISTS #L12_Emp, #L12_PendingOrders, #L12_Nums, #L12_CustOrders, #L12_CustTotals, ##L12_Global;
DROP PROCEDURE IF EXISTS dbo.usp_L12_ReadCallersTemp, dbo.usp_L12_MakeOwnTemp, dbo.usp_L12_GetOrders;
GO
/* DONE. Next: 02_Practice_Table_Variables_TVP.sql */
