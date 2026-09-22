/* ============================================================
   LEVEL 12 - TEMPORARY OBJECTS  |  02_Practice_Table_Variables_TVP.sql
   ------------------------------------------------------------
   Topics : table variables (@T: DECLARE, batch scope, inline
            PK/UNIQUE/CHECK/INDEX, no ALTER, no statistics ->
            1-row estimate, deferred compilation 2019+, NOT undone
            by ROLLBACK), CTE recap, comparison of the four
            options, table-valued parameters (TVP), checking
            tempdb usage with DMVs.
   HOW TO PRACTICE: run block by block, predict the output first.
   ============================================================ */

USE SQLPractice;
GO
DROP PROCEDURE IF EXISTS dbo.usp_L12_OrdersForCustomers;   -- the proc must go before the type it uses
DROP TYPE IF EXISTS dbo.L12_IdList;
DROP TABLE IF EXISTS #L12_Tx;
GO


/* ==== 1. TABLE VARIABLE  @T ==== */
-- DECLARE @name TABLE (...). It ALSO lives in tempdb (the interview myth "table
-- variables are in memory" is wrong: small ones may never touch disk, but they are
-- tempdb objects). Scope = the BATCH / procedure / function it is declared in.

-- 1a. Declare, fill, read. PK / UNIQUE / CHECK / INDEX are allowed INLINE only.
DECLARE @Dept TABLE
(
    DepartmentID   INT          NOT NULL PRIMARY KEY,
    DepartmentName VARCHAR(100) NOT NULL UNIQUE,
    HeadCount      INT          NOT NULL CHECK (HeadCount >= 0),
    INDEX IX_HeadCount NONCLUSTERED (HeadCount)     -- inline index syntax (2014+)
);
INSERT INTO @Dept (DepartmentID, DepartmentName, HeadCount)
SELECT d.DepartmentID, d.DepartmentName, COUNT(e.EmployeeID)
FROM dbo.Departments d
LEFT JOIN dbo.Employees e ON e.DepartmentID = d.DepartmentID
GROUP BY d.DepartmentID, d.DepartmentName;

SELECT * FROM @Dept ORDER BY HeadCount DESC, DepartmentName;   -- 6 rows: IT 3, Sales 3, Finance 2, Marketing 2, HR 1, Legal 0
GO
-- 1b. After GO the variable is gone. (Uncomment to see: Must declare the table variable "@Dept".)
-- SELECT * FROM @Dept;

-- 1c. Same reason: dynamic SQL is its OWN batch, so it cannot see your variables either.
DECLARE @Dept TABLE (DepartmentID INT);
BEGIN TRY
    EXEC (N'SELECT * FROM @Dept;');
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();   -- Must declare the table variable "@Dept".
END CATCH
GO

-- 1d. No ALTER TABLE on a table variable: its shape is fixed at DECLARE
BEGIN TRY
    EXEC (N'DECLARE @T TABLE (n INT); ALTER TABLE @T ADD m INT;');
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();   -- Incorrect syntax near '@T'.
END CATCH
GO

-- 1e. Constraints are enforced exactly like on a table
DECLARE @P TABLE (ProductID INT PRIMARY KEY, Price DECIMAL(12,2) CHECK (Price >= 0));
INSERT INTO @P VALUES (1, 100);
BEGIN TRY
    INSERT INTO @P VALUES (1, 200);       -- duplicate key
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
BEGIN TRY
    INSERT INTO @P VALUES (2, -5);        -- CHECK violation
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
SELECT * FROM @P;                         -- 1 row: 1, 100.00
GO


/* ==== 2. NO STATISTICS -> the optimizer guesses ==== */
-- #temp tables get statistics, so the optimizer knows roughly how many rows it will
-- handle. A table variable has NONE: the optimizer assumes 1 ROW (SQL 2017 and older).
-- SQL 2019+ (compat level 150+) adds "deferred compilation": the statement is compiled
-- at first execution using the REAL row count. That fixes many bad plans, but there are
-- still no column statistics (no histogram) -> filters and joins are still guesses.
-- Why care? 1 row vs 1,000,000 rows means nested loops vs hash join, tiny vs huge
-- memory grant, serial vs parallel. Big or filtered sets -> use a #temp table.
--
-- SSMS: Ctrl+M (Include Actual Execution Plan), run, hover the Clustered Index Scan.
-- Here SET STATISTICS PROFILE ON prints the same numbers as a table:
-- compare the columns  Rows (actual)  and  EstimateRows (guess)  on the scan line.
DECLARE @N TABLE (n INT NOT NULL PRIMARY KEY);
INSERT INTO @N SELECT value FROM GENERATE_SERIES(1, 1000);

SET STATISTICS PROFILE ON;
-- old behaviour (hint = deferred compilation OFF): scan line shows Rows 1000, EstimateRows 1.0
SELECT COUNT(*) AS Cnt FROM @N
OPTION (USE HINT ('DISABLE_DEFERRED_COMPILATION_TV'));
-- 2019+ default: scan line shows Rows 1000, EstimateRows 1000.0
SELECT COUNT(*) AS Cnt FROM @N;
SET STATISTICS PROFILE OFF;
GO


/* ==== 3. ROLLBACK: #T is undone, @T is NOT  (interview favourite) ==== */
CREATE TABLE #L12_Tx (n INT);
DECLARE @Tx TABLE (n INT);

BEGIN TRAN;
    INSERT INTO #L12_Tx VALUES (1), (2), (3);
    INSERT INTO @Tx     VALUES (1), (2), (3);
ROLLBACK TRAN;

SELECT (SELECT COUNT(*) FROM #L12_Tx) AS TempTableRows,   -- 0 : rolled back like any table
       (SELECT COUNT(*) FROM @Tx)     AS TableVarRows;    -- 3 : table variables ignore ROLLBACK
GO
-- Why? Table variables are not part of the user transaction; each statement on them
-- is its own tiny internal transaction. Not a bug - a feature you can use:

-- 3a. Keep a log even when the work is rolled back
DECLARE @Log TABLE (Step VARCHAR(60) NOT NULL, LoggedAt DATETIME2(0) NOT NULL DEFAULT SYSDATETIME());
BEGIN TRAN;
    INSERT INTO @Log (Step) VALUES ('order insert started');
    -- ... imagine real INSERT / UPDATE work here ...
    INSERT INTO @Log (Step) VALUES ('stock check failed -> rolling back');
ROLLBACK TRAN;
SELECT * FROM @Log;   -- 2 rows survived: now you can INSERT them into a permanent log table
GO


/* ==== 4. CTE RECAP: the fourth option (Level 11) ==== */
-- A CTE is NOT stored anywhere. It is a named subquery that exists for ONE statement.
-- Referencing it twice in that statement runs it twice. Great for readability and
-- recursion, useless for "compute once, use many times".
WITH CustTotals AS
(
    SELECT o.CustomerID, SUM(o.TotalAmount) AS Revenue
    FROM dbo.Orders o
    WHERE o.Status = 'Completed'
    GROUP BY o.CustomerID
)
SELECT c.CustomerName, ct.Revenue
FROM CustTotals ct
JOIN dbo.Customers c ON c.CustomerID = ct.CustomerID
WHERE ct.Revenue > 80000
ORDER BY ct.Revenue DESC;     -- 4 rows: Esha 150000, Aarav 96000, Farhan 88500, Gaurav 87000
GO
-- The next statement cannot see it (uncomment to get: Invalid object name 'CustTotals'):
-- SELECT * FROM CustTotals;


/* ==== 5. THE FOUR OPTIONS SIDE BY SIDE ==== */
/*
   ------------------+------------------+-----------------+---------------------+------------------
                     | #Temp table      | ##Global temp   | @Table variable     | CTE
   ------------------+------------------+-----------------+---------------------+------------------
   Stored in         | tempdb           | tempdb          | tempdb              | nowhere (plan only)
   Visible to        | my session +     | ALL sessions    | this batch / proc   | the ONE statement
                     | procs I call     |                 |                     | that follows it
   Dropped when      | session / proc   | creator leaves  | batch ends          | statement ends
                     | ends, or DROP    | + no one uses it|                     |
   Statistics        | yes (auto)       | yes             | NO (2019+: row      | n/a
                     |                  |                 | count at compile)   |
   Indexes           | any, any time    | any, any time   | inline only         | none
   ALTER TABLE       | yes              | yes             | no                  | n/a
   ROLLBACK          | undone           | undone          | NOT undone          | n/a
   Recompiles        | can trigger      | can trigger     | fewer               | none
   Use it for        | big sets, multi- | share rows with | small sets (~< 100  | readable multi-
                     | step work, joins | another session | rows), functions,   | step logic,
                     | needing stats    | (rare)          | logging in CATCH    | recursion, 1 use
   ------------------+------------------+-----------------+---------------------+------------------
*/


/* ==== 6. TABLE-VALUED PARAMETER (TVP): pass a whole table INTO a proc ==== */
-- Problem: "orders for customers 1, 5 and 7" - a proc parameter is ONE value, not a list.
-- Old hacks: comma-separated string + STRING_SPLIT, or XML. Clean way: a TVP.

-- 6a. Step 1 - a user-defined TABLE TYPE (the shape of the list)
CREATE TYPE dbo.L12_IdList AS TABLE (Id INT NOT NULL PRIMARY KEY);
GO
-- 6b. Step 2 - a proc with a parameter of that type. TVPs MUST be READONLY.
CREATE OR ALTER PROCEDURE dbo.usp_L12_OrdersForCustomers
    @Ids dbo.L12_IdList READONLY
AS
BEGIN
    SET NOCOUNT ON;
    SELECT o.OrderID, o.CustomerID, o.OrderDate, o.TotalAmount
    FROM dbo.Orders o
    JOIN @Ids i ON i.Id = o.CustomerID           -- join to the parameter like a table
    ORDER BY o.CustomerID, o.OrderID;
END
GO
-- 6c. Step 3 - declare a variable OF THAT TYPE, fill it, pass it
DECLARE @Ids dbo.L12_IdList;
INSERT INTO @Ids (Id) VALUES (1), (5);
EXEC dbo.usp_L12_OrdersForCustomers @Ids = @Ids;   -- 6 rows: 1001, 1004, 1009, 1015 (cust 1) + 1006, 1014 (cust 5)
GO
-- 6d. Forgetting READONLY is an error (a proc may not modify a TVP)
BEGIN TRY
    EXEC (N'CREATE PROCEDURE dbo.usp_L12_Bad @Ids dbo.L12_IdList AS SELECT 1 AS x;');
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO
-- 6e. The type cannot be dropped (or altered) while something uses it
BEGIN TRY
    DROP TYPE dbo.L12_IdList;
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO
-- 6f. Where to see table types
SELECT name, is_table_type FROM sys.types WHERE is_table_type = 1;   -- L12_IdList (sys.table_types has more detail)
GO
-- From .NET / Java the client sends a DataTable / structured parameter -> ONE round trip
-- for thousands of rows. That is the real win of TVPs (bulk "give me these IDs").


/* ==== 7. CHECKING TEMPDB USAGE ==== */
-- 7a. Whole tempdb: who is eating the space? (in MB; 1 page = 8 KB)
SELECT SUM(user_object_reserved_page_count)     * 8 / 1024.0 AS UserObjectsMB,     -- #temp, ##temp, @table vars
       SUM(internal_object_reserved_page_count) * 8 / 1024.0 AS InternalObjectsMB, -- sorts, hashes, spools
       SUM(version_store_reserved_page_count)   * 8 / 1024.0 AS VersionStoreMB,    -- snapshot isolation rows
       SUM(unallocated_extent_page_count)       * 8 / 1024.0 AS FreeMB
FROM tempdb.sys.dm_db_file_space_usage;
GO
-- 7b. My own session (pages allocated / freed since the session started)
SELECT session_id,
       user_objects_alloc_page_count, user_objects_dealloc_page_count,
       internal_objects_alloc_page_count, internal_objects_dealloc_page_count
FROM sys.dm_db_session_space_usage
WHERE session_id = @@SPID;
GO
-- 7c. Top sessions right now (the DBA view: find the query that filled tempdb)
SELECT TOP (5) session_id,
       user_objects_alloc_page_count - user_objects_dealloc_page_count         AS UserPagesLive,
       internal_objects_alloc_page_count - internal_objects_dealloc_page_count AS InternalPagesLive
FROM sys.dm_db_session_space_usage
ORDER BY (user_objects_alloc_page_count - user_objects_dealloc_page_count)
       + (internal_objects_alloc_page_count - internal_objects_dealloc_page_count) DESC;
GO


/* ==== 8. CLEANUP ==== */
DROP TABLE IF EXISTS #L12_Tx;
DROP PROCEDURE IF EXISTS dbo.usp_L12_OrdersForCustomers;   -- first the proc ...
DROP TYPE IF EXISTS dbo.L12_IdList;                        -- ... then the type
GO
/* DONE. Read 03_Two_Sessions_Demo.sql, then Exercises.sql */
