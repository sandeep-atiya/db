/* ============================================================
   LEVEL 16 - TRANSACTIONS  |  Exercises.sql
   ------------------------------------------------------------
   Try each question in the "YOUR ANSWERS" area FIRST.
   Then scroll down to SOLUTIONS and compare.
   All work is on a COPY table dbo.L16_Ex_Accounts (dropped at the end).
   ============================================================ */

USE SQLPractice;
GO
SET NOCOUNT ON;
GO
DROP PROCEDURE IF EXISTS dbo.usp_L16_Ex_Transfer, dbo.usp_L16_Ex_Retry;
DROP TABLE IF EXISTS dbo.L16_Ex_Accounts;
GO

/* ------------------------------------------------------------
   QUESTIONS
   ------------------------------------------------------------
   Q1.  Create dbo.L16_Ex_Accounts from dbo.Customers: AccountID (= CustomerID, PK),
        Owner, Balance = 5000 for everyone, and a CHECK that Balance >= 0. Show it.

   Q2.  In ONE explicit transaction move 2000 from account 3 to account 4 and COMMIT.
        Show both balances.

   Q3.  Start a transaction, set EVERY balance to 0, show SUM(Balance), ROLLBACK,
        show SUM(Balance) again. Predict both numbers before running.

   Q4.  Predict the 4 values of @@TRANCOUNT:
        BEGIN TRAN -> (1) BEGIN TRAN -> (2) COMMIT -> (3) COMMIT -> (4). Then run it.

   Q5.  Savepoint: debit 1000 from account 1, SAVE TRANSACTION, debit 1000 from
        account 2, roll back to the savepoint, COMMIT. Show accounts 1 and 2.

   Q6.  With TRY/CATCH try to move 9000 from account 5 to 6 (5 has only 5000).
        In CATCH print the error, print XACT_STATE(), roll back. Show 5 and 6.

   Q7.  Repeat Q6 with SET XACT_ABORT ON. What does XACT_STATE() show now, and why
        must you ROLLBACK (not COMMIT)?

   Q8.  Write dbo.usp_L16_Ex_Transfer(@From, @To, @Amount) with the standard template
        (SET XACT_ABORT ON, TRY/CATCH, THROW for @Amount <= 0, ROLLBACK + THROW in CATCH).
        Test: 500 from 7 to 8 (works), then @Amount = 0 (fails, nothing changes).

   Q9.  Show your session's isolation level in two ways. Switch to REPEATABLE READ,
        BEGIN TRAN, read account 1, list the locks your session holds, ROLLBACK,
        switch back to READ COMMITTED.

   Q10. Inside a transaction read account 1 WITH (UPDLOCK); show the lock mode your
        session holds on the KEY; roll back. Why would you use this hint?

   Q11. Write the query that lists blocked sessions with their blocker spid, wait type
        and the blocked statement text (0 rows expected right now).

   Q12. Write dbo.usp_L16_Ex_Retry(@AccountID, @Delta): update the balance inside a
        transaction, retry up to 3 times when ERROR_NUMBER() = 1205, re-throw any
        other error. Call it with @Delta = 10 on account 1 and show the balance.

   Q13. Predict: after BEGIN TRAN, insert 3 rows into a temp table AND a table
        variable, then ROLLBACK - how many rows does each contain? Prove it.
   ------------------------------------------------------------ */

-- YOUR ANSWERS HERE (write below, run, compare)










/* ============================================================
   SOLUTIONS
   ============================================================ */

-- Q1
SELECT c.CustomerID AS AccountID, c.CustomerName AS Owner, CAST(5000 AS DECIMAL(12,2)) AS Balance
INTO dbo.L16_Ex_Accounts
FROM dbo.Customers c;
ALTER TABLE dbo.L16_Ex_Accounts ADD CONSTRAINT PK_L16_Ex_Accounts PRIMARY KEY (AccountID);
ALTER TABLE dbo.L16_Ex_Accounts ADD CONSTRAINT CK_L16_Ex_Balance CHECK (Balance >= 0);
SELECT * FROM dbo.L16_Ex_Accounts ORDER BY AccountID;     -- 8 rows, 5000.00 each
GO

-- Q2
BEGIN TRAN;
    UPDATE dbo.L16_Ex_Accounts SET Balance = Balance - 2000 WHERE AccountID = 3;
    UPDATE dbo.L16_Ex_Accounts SET Balance = Balance + 2000 WHERE AccountID = 4;
COMMIT;
SELECT AccountID, Balance FROM dbo.L16_Ex_Accounts WHERE AccountID IN (3, 4);   -- 3000 / 7000
GO

-- Q3
BEGIN TRAN;
    UPDATE dbo.L16_Ex_Accounts SET Balance = 0;
    SELECT SUM(Balance) AS InsideTran FROM dbo.L16_Ex_Accounts;      -- 0.00
ROLLBACK;
SELECT SUM(Balance) AS AfterRollback FROM dbo.L16_Ex_Accounts;       -- 40000.00 (8 x 5000; Q2 moved money, did not create it)
GO

-- Q4
BEGIN TRAN;
SELECT @@TRANCOUNT AS V1;    -- 1
BEGIN TRAN;
SELECT @@TRANCOUNT AS V2;    -- 2
COMMIT;
SELECT @@TRANCOUNT AS V3;    -- 1  (inner COMMIT only decrements)
COMMIT;
SELECT @@TRANCOUNT AS V4;    -- 0
GO

-- Q5
BEGIN TRAN;
    UPDATE dbo.L16_Ex_Accounts SET Balance = Balance - 1000 WHERE AccountID = 1;
    SAVE TRANSACTION BeforeSecond;
    UPDATE dbo.L16_Ex_Accounts SET Balance = Balance - 1000 WHERE AccountID = 2;
    ROLLBACK TRANSACTION BeforeSecond;
COMMIT;
SELECT AccountID, Balance FROM dbo.L16_Ex_Accounts WHERE AccountID IN (1, 2);   -- 4000 / 5000
GO

-- Q6
BEGIN TRY
    BEGIN TRAN;
        UPDATE dbo.L16_Ex_Accounts SET Balance = Balance + 9000 WHERE AccountID = 6;
        UPDATE dbo.L16_Ex_Accounts SET Balance = Balance - 9000 WHERE AccountID = 5;   -- CHECK fails
    COMMIT;
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
    SELECT XACT_STATE() AS XactState;     -- 1 : still committable (a CHECK error does not doom it)
    IF @@TRANCOUNT > 0 ROLLBACK;
END CATCH
SELECT AccountID, Balance FROM dbo.L16_Ex_Accounts WHERE AccountID IN (5, 6);   -- 5000 / 5000
GO

-- Q7
SET XACT_ABORT ON;
BEGIN TRY
    BEGIN TRAN;
        UPDATE dbo.L16_Ex_Accounts SET Balance = Balance + 9000 WHERE AccountID = 6;
        UPDATE dbo.L16_Ex_Accounts SET Balance = Balance - 9000 WHERE AccountID = 5;
    COMMIT;
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
    SELECT XACT_STATE() AS XactState;     -- -1 : XACT_ABORT made it uncommittable; COMMIT would raise 3930
    IF XACT_STATE() <> 0 ROLLBACK;
END CATCH
SET XACT_ABORT OFF;
SELECT AccountID, Balance FROM dbo.L16_Ex_Accounts WHERE AccountID IN (5, 6);   -- 5000 / 5000
GO

-- Q8
CREATE PROCEDURE dbo.usp_L16_Ex_Transfer
    @From INT, @To INT, @Amount DECIMAL(12,2)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        IF @Amount <= 0 THROW 50001, 'Amount must be positive.', 1;
        BEGIN TRAN;
            UPDATE dbo.L16_Ex_Accounts SET Balance = Balance - @Amount WHERE AccountID = @From;
            IF @@ROWCOUNT = 0 THROW 50002, 'From-account not found.', 1;
            UPDATE dbo.L16_Ex_Accounts SET Balance = Balance + @Amount WHERE AccountID = @To;
            IF @@ROWCOUNT = 0 THROW 50003, 'To-account not found.', 1;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO
EXEC dbo.usp_L16_Ex_Transfer @From = 7, @To = 8, @Amount = 500;
SELECT AccountID, Balance FROM dbo.L16_Ex_Accounts WHERE AccountID IN (7, 8);   -- 4500 / 5500
BEGIN TRY
    EXEC dbo.usp_L16_Ex_Transfer @From = 7, @To = 8, @Amount = 0;
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();                                  -- Amount must be positive.
END CATCH
SELECT AccountID, Balance FROM dbo.L16_Ex_Accounts WHERE AccountID IN (7, 8);   -- 4500 / 5500 (unchanged)
GO

-- Q9
DBCC USEROPTIONS;                                                    -- last row: isolation level read committed
SELECT transaction_isolation_level FROM sys.dm_exec_sessions WHERE session_id = @@SPID;   -- 2
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
BEGIN TRAN;
    SELECT Balance FROM dbo.L16_Ex_Accounts WHERE AccountID = 1;
    SELECT resource_type, request_mode FROM sys.dm_tran_locks
    WHERE request_session_id = @@SPID ORDER BY resource_type;
    -- DATABASE S, KEY S (held!), OBJECT IS, PAGE IS
ROLLBACK;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
GO

-- Q10
BEGIN TRAN;
    SELECT Balance FROM dbo.L16_Ex_Accounts WITH (UPDLOCK) WHERE AccountID = 1;
    SELECT resource_type, request_mode FROM sys.dm_tran_locks
    WHERE request_session_id = @@SPID AND resource_type = 'KEY';    -- KEY U
ROLLBACK;
-- Why: "read a row, then update it" with plain S locks lets two sessions both read, then both
-- wait for X = deadlock. With UPDLOCK only one session can hold U, the other simply waits.
GO

-- Q11
SELECT r.session_id AS Blocked, r.blocking_session_id AS Blocker, r.wait_type, r.wait_time,
       t.text AS BlockedSql
FROM sys.dm_exec_requests r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.blocking_session_id <> 0;         -- 0 rows now
GO

-- Q12
CREATE PROCEDURE dbo.usp_L16_Ex_Retry
    @AccountID INT, @Delta DECIMAL(12,2)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @Attempt INT = 1;
    WHILE @Attempt <= 3
    BEGIN
        BEGIN TRY
            BEGIN TRAN;
                UPDATE dbo.L16_Ex_Accounts SET Balance = Balance + @Delta WHERE AccountID = @AccountID;
            COMMIT;
            RETURN 0;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK;
            IF ERROR_NUMBER() = 1205 AND @Attempt < 3
            BEGIN
                WAITFOR DELAY '00:00:00.200';
                SET @Attempt += 1;
            END
            ELSE
                THROW;
        END CATCH
    END
END
GO
EXEC dbo.usp_L16_Ex_Retry @AccountID = 1, @Delta = 10;
SELECT Balance FROM dbo.L16_Ex_Accounts WHERE AccountID = 1;   -- 4010.00 (4000 after Q5 + 10)
GO

-- Q13
DROP TABLE IF EXISTS #L16_Ex;
CREATE TABLE #L16_Ex (ID INT);
DECLARE @tv TABLE (ID INT);
BEGIN TRAN;
    INSERT INTO #L16_Ex VALUES (1), (2), (3);
    INSERT INTO @tv     VALUES (1), (2), (3);
ROLLBACK;
SELECT (SELECT COUNT(*) FROM #L16_Ex) AS TempTable,      -- 0 : rolled back
       (SELECT COUNT(*) FROM @tv)     AS TableVariable;  -- 3 : table variables ignore ROLLBACK
DROP TABLE #L16_Ex;
GO

/* ---------------- cleanup ---------------- */
IF @@TRANCOUNT > 0 ROLLBACK;
SET XACT_ABORT OFF;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
DROP PROCEDURE IF EXISTS dbo.usp_L16_Ex_Transfer, dbo.usp_L16_Ex_Retry;
DROP TABLE IF EXISTS dbo.L16_Ex_Accounts;
GO
