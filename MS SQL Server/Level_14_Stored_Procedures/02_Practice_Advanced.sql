/* ============================================================
   LEVEL 14 - STORED PROCEDURES  |  02_Practice_Advanced.sql
   ------------------------------------------------------------
   Topics : TRY/CATCH inside a proc + ERROR_* functions, THROW vs
            RAISERROR (+ custom THROW 50001, re-throwing),
            transactions in procs with ROLLBACK in CATCH and
            @@TRANCOUNT / XACT_STATE template, dynamic SQL
            (EXEC vs sp_executesql, SQL injection demo, QUOTENAME,
            output param), temp tables inside procs (visible to
            nested procs), TVP brief (Level 12), WITH RECOMPILE /
            OPTION (RECOMPILE), EXECUTE AS, procs vs functions vs
            views, sp_ system procs worth knowing.
   HOW TO PRACTICE: run block by block, predict the output first.
   Data changes happen on the copy table dbo.L14_Accounts.
   ============================================================ */

USE SQLPractice;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
DROP PROCEDURE IF EXISTS dbo.usp_L14_SafeDivide, dbo.usp_L14_ValidateAmount, dbo.usp_L14_Transfer,
                         dbo.usp_L14_CustomerCount, dbo.usp_L14_TopN, dbo.usp_L14_OrderValue,
                         dbo.usp_L14_BuildTemp, dbo.usp_L14_ReadTemp, dbo.usp_L14_OrdersForIds,
                         dbo.usp_L14_WhoAmI;
DROP TYPE IF EXISTS dbo.L14_IdList;
DROP TABLE IF EXISTS dbo.L14_Accounts;
GO


/* ==== 1. TRY / CATCH INSIDE A PROC + the ERROR_* functions ==== */
-- In a CATCH block these functions describe the error that fired: number, message,
-- severity, state, the LINE, and (very useful) the PROCEDURE it happened in.
CREATE OR ALTER PROCEDURE dbo.usp_L14_SafeDivide
    @A INT,
    @B INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        SELECT @A / @B AS Result;                 -- @B = 0 raises error 8134
    END TRY
    BEGIN CATCH
        SELECT ERROR_NUMBER()    AS ErrNumber,    -- 8134
               ERROR_SEVERITY()  AS ErrSeverity,  -- 16
               ERROR_STATE()     AS ErrState,     -- 1
               ERROR_LINE()      AS ErrLine,      -- line of the SELECT inside the proc
               ERROR_PROCEDURE() AS ErrProcedure, -- dbo.usp_L14_SafeDivide
               ERROR_MESSAGE()   AS ErrMessage;   -- Divide by zero error encountered.
    END CATCH
END
GO
EXEC dbo.usp_L14_SafeDivide @A = 10, @B = 2;   -- Result 5
EXEC dbo.usp_L14_SafeDivide @A = 10, @B = 0;   -- the 6 error columns
GO
-- Note: TRY/CATCH does NOT catch compile errors (bad object name), severity 20+ errors,
-- or an attention/timeout. It catches ordinary run-time errors (severity 11-19).


/* ==== 2. THROW vs RAISERROR ==== */
/*
   ----------------------+--------------------------------+-------------------------------
                         | THROW (2012+, PREFER THIS)     | RAISERROR (older)
   ----------------------+--------------------------------+-------------------------------
   Custom error number   | >= 50000                       | 50000, or a sys.messages id
   Message formatting     | no (%s not supported)          | yes (%s, %d like printf)
   Severity              | always 16                      | you choose (0-25)
   Re-throw original      | THROW; with no arguments       | cannot; you rebuild the text
   Stops the batch        | yes (must be ; terminated)     | no, execution continues
   Statement before it    | must end with ;                | not required
   ----------------------+--------------------------------+-------------------------------
*/
-- 2a. Custom business error with THROW (number must be >= 50000)
CREATE OR ALTER PROCEDURE dbo.usp_L14_ValidateAmount
    @Amount DECIMAL(12,2)
AS
BEGIN
    SET NOCOUNT ON;
    IF @Amount <= 0
        THROW 50001, 'Amount must be greater than zero.', 1;   -- number, message, state
    SELECT @Amount AS AcceptedAmount;
END
GO
EXEC dbo.usp_L14_ValidateAmount @Amount = 500;    -- AcceptedAmount 500.00
BEGIN TRY
    EXEC dbo.usp_L14_ValidateAmount @Amount = -1;
END TRY
BEGIN CATCH
    PRINT 'CAUGHT ' + CAST(ERROR_NUMBER() AS VARCHAR(10)) + ' sev ' + CAST(ERROR_SEVERITY() AS VARCHAR(10)) + ': ' + ERROR_MESSAGE();
END CATCH   -- CAUGHT 50001 sev 16: Amount must be greater than zero.
GO
-- 2b. RAISERROR can FORMAT a message (THROW cannot). Error number for RAISERROR('text'..) is 50000.
BEGIN TRY
    DECLARE @bad INT = 42;
    RAISERROR ('Value %d is not allowed for customer %s.', 16, 1, @bad, 'ACME');
END TRY
BEGIN CATCH
    PRINT 'CAUGHT ' + CAST(ERROR_NUMBER() AS VARCHAR(10)) + ': ' + ERROR_MESSAGE();
END CATCH   -- CAUGHT 50000: Value 42 is not allowed for customer ACME.
GO
-- 2c. Re-throwing: log, then THROW; (no arguments) re-raises the SAME error to the caller.
CREATE OR ALTER PROCEDURE dbo.usp_L14_OrderValue
    @OrderID INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @lines INT = (SELECT COUNT(*) FROM dbo.OrderDetails WHERE OrderID = @OrderID);
        IF @lines = 0
            THROW 50002, 'No order lines found for that OrderID.', 1;
        SELECT @OrderID AS OrderID, SUM(Quantity * UnitPrice) AS Value FROM dbo.OrderDetails WHERE OrderID = @OrderID;
    END TRY
    BEGIN CATCH
        PRINT 'usp_L14_OrderValue logging error ' + CAST(ERROR_NUMBER() AS VARCHAR(10));
        THROW;   -- bubble the ORIGINAL error (number, message, line) up to the caller
    END CATCH
END
GO
EXEC dbo.usp_L14_OrderValue @OrderID = 1001;   -- 1001, 75000.00
BEGIN TRY
    EXEC dbo.usp_L14_OrderValue @OrderID = 9999;   -- no such order
END TRY
BEGIN CATCH
    PRINT 'OUTER CAUGHT ' + CAST(ERROR_NUMBER() AS VARCHAR(10)) + ': ' + ERROR_MESSAGE();   -- OUTER CAUGHT 50002: No order lines found ...
END CATCH
GO


/* ==== 3. TRANSACTIONS IN A PROC: the safe template ==== */
-- Rules a robust proc follows:
--   SET XACT_ABORT ON     -> most errors abort the batch and mark the tran doomed
--   BEGIN TRAN in TRY, COMMIT at the end of TRY
--   in CATCH: if XACT_STATE() <> 0 ROLLBACK, then log / THROW
--   XACT_STATE(): 1 = healthy tran (can commit), -1 = doomed (must roll back), 0 = none
--   @@TRANCOUNT tells you how deep you are nested
DROP TABLE IF EXISTS dbo.L14_Accounts;
CREATE TABLE dbo.L14_Accounts
(
    AccountID INT           NOT NULL PRIMARY KEY,
    Balance   DECIMAL(12,2) NOT NULL CONSTRAINT CK_L14_Accounts_Bal CHECK (Balance >= 0)
);
INSERT INTO dbo.L14_Accounts VALUES (1, 1000), (2, 500);
GO
CREATE OR ALTER PROCEDURE dbo.usp_L14_Transfer
    @FromAccount INT,
    @ToAccount   INT,
    @Amount      DECIMAL(12,2)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRAN;
            UPDATE dbo.L14_Accounts SET Balance = Balance - @Amount WHERE AccountID = @FromAccount;
            UPDATE dbo.L14_Accounts SET Balance = Balance + @Amount WHERE AccountID = @ToAccount;  -- if Balance < 0 the CHECK fires here
        COMMIT TRAN;
        SELECT 'committed' AS Result;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRAN;                 -- undo the partial transfer
        PRINT 'usp_L14_Transfer rolled back: ' + ERROR_MESSAGE();
        THROW;                             -- let the caller know it failed
    END CATCH
END
GO
-- 3a. A good transfer commits both updates
EXEC dbo.usp_L14_Transfer @FromAccount = 1, @ToAccount = 2, @Amount = 300;
SELECT * FROM dbo.L14_Accounts;   -- 1: 700.00 , 2: 800.00
GO
-- 3b. A transfer that would overdraw account 1 fails the CHECK -> BOTH updates roll back
BEGIN TRY
    EXEC dbo.usp_L14_Transfer @FromAccount = 1, @ToAccount = 2, @Amount = 5000;
END TRY
BEGIN CATCH
    PRINT 'OUTER CAUGHT ' + CAST(ERROR_NUMBER() AS VARCHAR(10)) + ': ' + ERROR_MESSAGE();   -- 547 (CHECK constraint)
END CATCH
SELECT * FROM dbo.L14_Accounts;   -- STILL 1: 700.00 , 2: 800.00  -> atomic: all or nothing
GO


/* ==== 4. DYNAMIC SQL: EXEC('...') vs sp_executesql, and SQL INJECTION ==== */
-- Dynamic SQL builds a query string at run time. Two ways to run it. One is dangerous.

-- 4a. THE DANGER: EXEC + string concatenation. Imagine a search by city where the "city"
--     comes from a user. A malicious value turns the WHERE into "OR 1=1" and returns
--     EVERYTHING (a real attacker would append DROP/UPDATE). Harmless demo here:
DECLARE @City VARCHAR(100) = ''' OR 1=1 --';                 -- attacker's input
DECLARE @sql NVARCHAR(400) = N'SELECT COUNT(*) AS Cnt FROM dbo.Customers WHERE City = ''' + @City + '''';
PRINT @sql;                                                  -- ... WHERE City = '' OR 1=1 --'
EXEC (@sql);                                                 -- Cnt = 8 : ALL customers leaked!
GO
-- 4b. THE FIX: sp_executesql with PARAMETERS. The value is passed separately, never parsed
--     as code, so 'OR 1=1' is treated as a literal city name (which matches nobody).
DECLARE @City VARCHAR(100) = ''' OR 1=1 --';
EXEC sp_executesql
     N'SELECT COUNT(*) AS Cnt FROM dbo.Customers WHERE City = @City',
     N'@City VARCHAR(100)',
     @City = @City;                                          -- Cnt = 0 : injection defeated
GO
-- 4c. When the DYNAMIC part is an OBJECT NAME (which cannot be a parameter), sanitise it
--     with QUOTENAME - it wraps the name in [ ] and doubles any ] so it cannot break out.
CREATE OR ALTER PROCEDURE dbo.usp_L14_TopN
    @TableName SYSNAME,
    @N         INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @sql NVARCHAR(300) = N'SELECT TOP (@N) * FROM dbo.' + QUOTENAME(@TableName);
    EXEC sp_executesql @sql, N'@N INT', @N = @N;             -- @N still passed as a parameter
END
GO
EXEC dbo.usp_L14_TopN @TableName = 'Departments', @N = 2;   -- 2 rows: IT, Sales
BEGIN TRY
    EXEC dbo.usp_L14_TopN @TableName = 'Employees; DROP TABLE X', @N = 1;   -- injection attempt in the name
END TRY
BEGIN CATCH
    PRINT 'QUOTENAME BLOCKED: ' + ERROR_MESSAGE();           -- Invalid object name 'dbo.Employees; DROP TABLE X'.
END CATCH
GO
-- 4d. sp_executesql can also return an OUTPUT parameter (EXEC('...') cannot)
CREATE OR ALTER PROCEDURE dbo.usp_L14_CustomerCount
    @CustomerID INT,
    @Orders     INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    EXEC sp_executesql
         N'SELECT @cnt = COUNT(*) FROM dbo.Orders WHERE CustomerID = @cid',
         N'@cid INT, @cnt INT OUTPUT',
         @cid = @CustomerID, @cnt = @Orders OUTPUT;
END
GO
DECLARE @n INT;
EXEC dbo.usp_L14_CustomerCount @CustomerID = 1, @Orders = @n OUTPUT;
SELECT @n AS OrdersOfCustomer1;   -- 4
GO


/* ==== 5. TEMP TABLES INSIDE PROCS: visible to nested procs ==== */
-- A #temp table created in a proc is visible to any proc that proc CALLS (it flows down),
-- but is dropped when the creating proc ends. This is how a pipeline shares a staging set.
CREATE OR ALTER PROCEDURE dbo.usp_L14_ReadTemp
AS
BEGIN
    SET NOCOUNT ON;
    SELECT COUNT(*) AS RowsSeenByNestedProc FROM #L14_Stage;   -- reads the CALLER's temp table
END
GO
CREATE OR ALTER PROCEDURE dbo.usp_L14_BuildTemp
AS
BEGIN
    SET NOCOUNT ON;
    CREATE TABLE #L14_Stage (EmployeeID INT PRIMARY KEY, Salary DECIMAL(12,2));
    INSERT INTO #L14_Stage SELECT EmployeeID, Salary FROM dbo.Employees WHERE DepartmentID = 2;   -- 3 rows
    EXEC dbo.usp_L14_ReadTemp;                                  -- nested proc sees #L14_Stage
    SELECT OBJECT_ID('tempdb..#L14_Stage') AS ExistsInsideBuild;  -- a number
END
GO
EXEC dbo.usp_L14_BuildTemp;                                    -- RowsSeenByNestedProc = 3, then a number
SELECT OBJECT_ID('tempdb..#L14_Stage') AS ExistsAfterBuild;    -- NULL: dropped when usp_L14_BuildTemp ended
GO


/* ==== 6. TABLE-VALUED PARAMETER (brief - full treatment in Level 12) ==== */
-- Pass a whole list of ids into a proc as ONE READONLY parameter of a table type.
CREATE TYPE dbo.L14_IdList AS TABLE (Id INT NOT NULL PRIMARY KEY);
GO
CREATE OR ALTER PROCEDURE dbo.usp_L14_OrdersForIds
    @Ids dbo.L14_IdList READONLY        -- TVPs must be READONLY
AS
BEGIN
    SET NOCOUNT ON;
    SELECT o.OrderID, o.CustomerID, o.TotalAmount
    FROM dbo.Orders o
    JOIN @Ids i ON i.Id = o.CustomerID
    ORDER BY o.OrderID;
END
GO
DECLARE @ids dbo.L14_IdList;
INSERT INTO @ids (Id) VALUES (5), (7);
EXEC dbo.usp_L14_OrdersForIds @Ids = @ids;   -- 4 rows: 1005, 1014 (cust 5) + 1011, 1018 (cust 7)
GO


/* ==== 7. WITH RECOMPILE / OPTION (RECOMPILE)  (parameter sniffing - preview Level 19) ==== */
-- SQL Server caches the plan built for the FIRST parameter value it sees ("parameter
-- sniffing"). Usually good; occasionally the first value is atypical and everyone else
-- gets a bad plan. Two escape hatches:
--   CREATE PROCEDURE ... WITH RECOMPILE   -> rebuild the WHOLE proc's plan every call
--                                            (never cached; note it does NOT appear in
--                                             sys.dm_exec_procedure_stats)
--   ... query ... OPTION (RECOMPILE)      -> rebuild only THAT statement (usually better)
CREATE OR ALTER PROCEDURE dbo.usp_L14_OrdersByStatus
    @Status VARCHAR(20)
WITH RECOMPILE                           -- whole-proc recompile every execution
AS
BEGIN
    SET NOCOUNT ON;
    SELECT OrderID, CustomerID, TotalAmount
    FROM dbo.Orders
    WHERE Status = @Status
    OPTION (RECOMPILE);                  -- and this single statement is also recompiled
END
GO
EXEC dbo.usp_L14_OrdersByStatus @Status = 'Pending';   -- 2 rows: 1015, 1017
DROP PROCEDURE dbo.usp_L14_OrdersByStatus;
GO


/* ==== 8. EXECUTE AS (brief): run the proc under a different identity ==== */
-- By default a proc runs as the CALLER. EXECUTE AS changes that - used to let a user run
-- a proc that touches tables they cannot read directly ("ownership chaining" alternative).
CREATE OR ALTER PROCEDURE dbo.usp_L14_WhoAmI
WITH EXECUTE AS CALLER            -- also: OWNER, SELF, 'SomeUser'
AS
BEGIN
    SET NOCOUNT ON;
    SELECT USER_NAME() AS RunsAsUser, ORIGINAL_LOGIN() AS ActualLogin;
END
GO
EXEC dbo.usp_L14_WhoAmI;   -- RunsAsUser dbo , ActualLogin <your Windows login>
GO


/* ==== 9. PROC vs FUNCTION vs VIEW ==== */
/*
   -------------------+----------------------+------------------------+---------------------
                      | STORED PROCEDURE     | FUNCTION               | VIEW
   -------------------+----------------------+------------------------+---------------------
   Call with          | EXEC                 | inside a SELECT        | SELECT FROM it
   Returns            | 0..n result sets,    | one scalar OR one      | one virtual table
                      | OUTPUT, RETURN code  | table                  |
   Parameters         | in / out             | in only                | none (use inline TVF)
   Can do INSERT/UPD  | yes                  | NO (only table vars    | through it (limited)
                      |                      | inside)                |
   Can call in a query| no                   | yes                    | yes
   TRY/CATCH, TRAN    | yes                  | no                     | no
   Side effects       | allowed              | not allowed            | none
   Use for            | actions, workflows,  | reusable calculations, | reusable SELECT,
                      | multi-step logic     | computed columns       | security, hiding joins
   -------------------+----------------------+------------------------+---------------------
*/


/* ==== 10. sp_ SYSTEM PROCEDURES WORTH KNOWING ==== */
-- sp_help     'obj'                 -> columns, indexes, constraints, parameters of an object
-- sp_helptext 'obj'                 -> the T-SQL definition (proc / view / function)
-- sp_rename   'old', 'new'          -> rename a table / column / object (does NOT update the
--                                      stored definition text - warns you; prefer CREATE OR ALTER)
-- sp_who2                           -> active sessions (SPID, status, BlkBy = who blocks whom)
-- sp_depends / better: the DMVs     -> dependencies
EXEC sp_help 'dbo.Orders';                 -- structure of a table
EXEC sp_helptext 'dbo.usp_L14_Transfer';   -- text of our proc
GO
-- Modern dependency views (sp_depends is deprecated / unreliable):
SELECT referencing_schema_name, referencing_entity_name
FROM sys.dm_sql_referencing_entities('dbo.L14_Accounts', 'OBJECT');   -- usp_L14_Transfer
GO


/* ==== 11. CLEANUP ==== */
DROP PROCEDURE IF EXISTS dbo.usp_L14_SafeDivide, dbo.usp_L14_ValidateAmount, dbo.usp_L14_Transfer,
                         dbo.usp_L14_CustomerCount, dbo.usp_L14_TopN, dbo.usp_L14_OrderValue,
                         dbo.usp_L14_BuildTemp, dbo.usp_L14_ReadTemp, dbo.usp_L14_OrdersForIds,
                         dbo.usp_L14_WhoAmI;
DROP TYPE IF EXISTS dbo.L14_IdList;
DROP TABLE IF EXISTS dbo.L14_Accounts;
GO
/* DONE. Next: Exercises.sql */
