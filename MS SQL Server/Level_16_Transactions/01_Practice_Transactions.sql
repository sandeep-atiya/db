/* ============================================================
   LEVEL 16 - TRANSACTIONS  |  01_Practice_Transactions.sql
   ------------------------------------------------------------
   Topics : what a transaction is, ACID, autocommit / explicit /
            implicit transactions, BEGIN TRAN / COMMIT / ROLLBACK,
            @@TRANCOUNT, nested transactions, SAVE TRANSACTION,
            TRY/CATCH + ROLLBACK, XACT_STATE(), SET XACT_ABORT ON,
            the standard procedure template, table variable vs
            temp table on ROLLBACK, transaction log basics,
            naming transactions, batching commits in a loop.
   HOW TO PRACTICE: run block by block, predict the output first.
   Works on a COPY table dbo.L16_Accounts (never on the base tables).
   ============================================================ */

USE SQLPractice;
GO
SET NOCOUNT ON;              -- hide "(n rows affected)" so the results are easier to read
GO
DROP PROCEDURE IF EXISTS dbo.usp_L16_Transfer;
DROP TABLE IF EXISTS dbo.L16_Accounts, dbo.L16_Log;
GO

-- Helper: one bank account per customer, everyone starts with 10,000
SELECT c.CustomerID AS AccountID, c.CustomerName AS Owner, CAST(10000 AS DECIMAL(12,2)) AS Balance
INTO dbo.L16_Accounts
FROM dbo.Customers c;
ALTER TABLE dbo.L16_Accounts ADD CONSTRAINT PK_L16_Accounts PRIMARY KEY (AccountID);
ALTER TABLE dbo.L16_Accounts ADD CONSTRAINT CK_L16_Accounts_Balance CHECK (Balance >= 0);
SELECT * FROM dbo.L16_Accounts ORDER BY AccountID;     -- 8 rows, all 10000.00
GO


/* ============================================================
   1. WHAT IS A TRANSACTION?  ACID
   ============================================================
   A transaction = a group of statements that must succeed or fail
   AS ONE UNIT. Bank transfer: debit A + credit B. Half of it must
   never happen.

   A - Atomicity   : all or nothing  (COMMIT applies all, ROLLBACK undoes all)
   C - Consistency : the database goes from one VALID state to another
                     (constraints are never left violated)
   I - Isolation   : other sessions do not see half-done work
                     (locks / row versions - file 02 and 03)
   D - Durability  : once COMMIT returns, the change survives a crash
                     (it is written to the transaction LOG first)
   ============================================================ */

-- 1a. ATOMICITY: both statements, or none. Here: none (ROLLBACK).
BEGIN TRAN;
    UPDATE dbo.L16_Accounts SET Balance = Balance - 3000 WHERE AccountID = 1;
    UPDATE dbo.L16_Accounts SET Balance = Balance + 3000 WHERE AccountID = 2;
    SELECT AccountID, Balance FROM dbo.L16_Accounts WHERE AccountID IN (1, 2);  -- 7000 / 13000 (inside)
ROLLBACK;
SELECT AccountID, Balance FROM dbo.L16_Accounts WHERE AccountID IN (1, 2);      -- 10000 / 10000 (undone)
GO

-- 1b. CONSISTENCY: the CHECK constraint refuses an invalid state, the transaction
--     is rolled back in CATCH, so the earlier credit is undone too.
BEGIN TRY
    BEGIN TRAN;
        UPDATE dbo.L16_Accounts SET Balance = Balance + 20000 WHERE AccountID = 2;   -- ok
        UPDATE dbo.L16_Accounts SET Balance = Balance - 20000 WHERE AccountID = 1;   -- -10000 -> CHECK fails
    COMMIT;
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
    IF @@TRANCOUNT > 0 ROLLBACK;
END CATCH
SELECT AccountID, Balance FROM dbo.L16_Accounts WHERE AccountID IN (1, 2);      -- 10000 / 10000
GO

-- 1c. ISOLATION: your own session sees its uncommitted change; other sessions
--     (by default) wait or see the old value. See 03_Two_Sessions_Demo.sql.
-- 1d. DURABILITY: the change is written to the log before COMMIT returns (section 10).


/* ============================================================
   2. AUTOCOMMIT vs EXPLICIT vs IMPLICIT TRANSACTIONS
   ============================================================ */

-- 2a. AUTOCOMMIT (the default): every single statement is its own transaction.
--     @@TRANCOUNT = number of open BEGIN TRANs in this session.
SELECT @@TRANCOUNT AS Before;                                            -- 0
UPDATE dbo.L16_Accounts SET Balance = Balance WHERE AccountID = 1;       -- committed immediately
SELECT @@TRANCOUNT AS After;                                             -- 0
GO

-- 2b. EXPLICIT: you write BEGIN TRAN ... COMMIT / ROLLBACK yourself (sections 3+).

-- 2c. IMPLICIT (SET IMPLICIT_TRANSACTIONS ON): SQL Server starts a transaction for
--     you at the first DML/DDL statement, but YOU must COMMIT or ROLLBACK.
--     (ANSI default, Oracle style; also what some ODBC/JDBC drivers switch on.)
--     Forgetting COMMIT leaves locks open = classic production blocking bug.
SET IMPLICIT_TRANSACTIONS ON;
SELECT @@TRANCOUNT AS BeforeUpdate;                                      -- 0
UPDATE dbo.L16_Accounts SET Balance = Balance WHERE AccountID = 1;
SELECT @@TRANCOUNT AS AfterUpdate;                                       -- 1  (opened for you!)
ROLLBACK;
SELECT @@TRANCOUNT AS AfterRollback;                                     -- 0
SET IMPLICIT_TRANSACTIONS OFF;                                           -- back to autocommit
SELECT CASE WHEN @@OPTIONS & 2 = 2 THEN 'ON' ELSE 'OFF' END AS ImplicitTransactions;   -- OFF
GO


/* ============================================================
   3. BEGIN TRAN / COMMIT / ROLLBACK  - the bank transfer
   ============================================================ */

-- 3a. Successful transfer: 3000 from account 1 to account 2, then COMMIT
BEGIN TRAN;
    UPDATE dbo.L16_Accounts SET Balance = Balance - 3000 WHERE AccountID = 1;
    UPDATE dbo.L16_Accounts SET Balance = Balance + 3000 WHERE AccountID = 2;
COMMIT;
SELECT AccountID, Balance FROM dbo.L16_Accounts WHERE AccountID IN (1, 2);      -- 7000 / 13000
GO

-- 3b. Business rule checked INSIDE the transaction: roll back when the balance would go negative
DECLARE @From INT = 1, @To INT = 3, @Amount DECIMAL(12,2) = 20000;

BEGIN TRAN;
    UPDATE dbo.L16_Accounts SET Balance = Balance + @Amount WHERE AccountID = @To;

    IF (SELECT Balance FROM dbo.L16_Accounts WHERE AccountID = @From) < @Amount
    BEGIN
        ROLLBACK;
        PRINT 'Insufficient funds - rolled back';
    END
    ELSE
    BEGIN
        UPDATE dbo.L16_Accounts SET Balance = Balance - @Amount WHERE AccountID = @From;
        COMMIT;
        PRINT 'Transfer done';
    END
SELECT AccountID, Balance FROM dbo.L16_Accounts WHERE AccountID IN (1, 3);      -- 7000 / 10000 (unchanged)
GO

-- Reset balances for the next sections
UPDATE dbo.L16_Accounts SET Balance = 10000;
GO


/* ============================================================
   4. @@TRANCOUNT  before / inside / after
   ============================================================ */
SELECT @@TRANCOUNT AS Step1_Before;          -- 0
BEGIN TRAN;
SELECT @@TRANCOUNT AS Step2_Inside;          -- 1
UPDATE dbo.L16_Accounts SET Balance = Balance - 1 WHERE AccountID = 1;
SELECT @@TRANCOUNT AS Step3_StillInside;     -- 1 (a statement does not change it)
COMMIT;
SELECT @@TRANCOUNT AS Step4_After;           -- 0
GO

-- ROLLBACK / COMMIT without an open transaction -> error 3903 / 3902
BEGIN TRY
    ROLLBACK;
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
UPDATE dbo.L16_Accounts SET Balance = 10000;   -- reset (step 3 above committed a -1)
GO


/* ============================================================
   5. NESTED BEGIN TRAN  (there is really only ONE transaction)
   ============================================================
   Inner BEGIN TRAN  : @@TRANCOUNT + 1, nothing else.
   Inner COMMIT      : @@TRANCOUNT - 1, NOTHING is committed yet!
   Outer COMMIT      : @@TRANCOUNT 1 -> 0, now everything is committed.
   ANY ROLLBACK      : undoes EVERYTHING, @@TRANCOUNT -> 0.
   ============================================================ */

-- 5a. Inner COMMIT does not commit: the outer ROLLBACK still undoes the inner work
BEGIN TRAN;                                                     -- outer
    UPDATE dbo.L16_Accounts SET Balance = 1 WHERE AccountID = 1;
    SELECT @@TRANCOUNT AS AfterOuterBegin;                      -- 1
    BEGIN TRAN;                                                 -- inner
        UPDATE dbo.L16_Accounts SET Balance = 2 WHERE AccountID = 2;
        SELECT @@TRANCOUNT AS AfterInnerBegin;                  -- 2
    COMMIT;                                                     -- inner "commit"
    SELECT @@TRANCOUNT AS AfterInnerCommit;                     -- 1  (still open!)
ROLLBACK;                                                       -- outer rollback
SELECT @@TRANCOUNT AS AfterRollback;                            -- 0
SELECT AccountID, Balance FROM dbo.L16_Accounts WHERE AccountID IN (1, 2);   -- 10000 / 10000: BOTH undone
GO

-- 5b. A ROLLBACK inside the inner level kills the whole thing; the outer COMMIT then fails
BEGIN TRAN;
    BEGIN TRAN;
        UPDATE dbo.L16_Accounts SET Balance = 2 WHERE AccountID = 2;
    ROLLBACK;                                                   -- rolls back ALL levels
    SELECT @@TRANCOUNT AS AfterInnerRollback;                   -- 0
BEGIN TRY
    COMMIT;                                                     -- nothing to commit -> error 3902
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO
-- Lesson: in a procedure never ROLLBACK blindly when the CALLER may have an open
-- transaction - check @@TRANCOUNT / XACT_STATE() first (section 8).


/* ============================================================
   6. SAVE TRANSACTION  - partial rollback to a savepoint
   ============================================================ */
BEGIN TRAN;
    UPDATE dbo.L16_Accounts SET Balance = Balance - 1000 WHERE AccountID = 1;   -- step A
    SAVE TRANSACTION AfterDebit;                                                -- savepoint
    UPDATE dbo.L16_Accounts SET Balance = Balance - 1000 WHERE AccountID = 2;   -- step B
    ROLLBACK TRANSACTION AfterDebit;   -- undo ONLY step B; the transaction stays OPEN
    SELECT @@TRANCOUNT AS StillOpen;   -- 1
COMMIT;                                -- commits step A
SELECT AccountID, Balance FROM dbo.L16_Accounts WHERE AccountID IN (1, 2);   -- 9000 / 10000
GO
-- Notes: savepoint names can be reused (rollback goes to the LAST one with that name);
-- savepoints are not allowed in distributed transactions.
UPDATE dbo.L16_Accounts SET Balance = 10000;   -- reset
GO


/* ============================================================
   7. TRY / CATCH + ROLLBACK, XACT_STATE()
   ============================================================
   XACT_STATE()  1 = active transaction, can COMMIT
                 0 = no transaction
                -1 = active but UNCOMMITTABLE ("doomed"): only ROLLBACK allowed
   ============================================================ */

-- 7a. The basic pattern: any error jumps to CATCH, CATCH rolls back
BEGIN TRY
    BEGIN TRAN;
        UPDATE dbo.L16_Accounts SET Balance = Balance - 500 WHERE AccountID = 1;
        INSERT INTO dbo.L16_Accounts (AccountID, Owner, Balance) VALUES (1, 'Dup', 0);   -- PK violation
    COMMIT;
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
    SELECT XACT_STATE() AS XactState, @@TRANCOUNT AS TranCount;   -- 1 / 1 : still open & committable
    IF @@TRANCOUNT > 0 ROLLBACK;
END CATCH
SELECT Balance FROM dbo.L16_Accounts WHERE AccountID = 1;       -- 10000 (debit undone)
GO
-- Danger: with XACT_STATE() = 1 you COULD commit the half-done work by mistake.
-- Most errors (PK violation, CHECK) do NOT doom the transaction on their own.

-- 7b. XACT_STATE() = -1 : uncommittable. Happens with SET XACT_ABORT ON (next section)
--     and also for some severe errors even without it, e.g. a conversion failure:
BEGIN TRY
    BEGIN TRAN;
        UPDATE dbo.L16_Accounts SET Balance = Balance - 500 WHERE AccountID = 1;
        SELECT CAST('abc' AS INT);                                  -- conversion error
    COMMIT;
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
    SELECT XACT_STATE() AS XactState, @@TRANCOUNT AS TranCount;   -- -1 / 1 : doomed
    BEGIN TRY
        COMMIT;                                                     -- not allowed on a doomed transaction
    END TRY
    BEGIN CATCH
        PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();                 -- error 3930
    END CATCH
    IF XACT_STATE() <> 0 ROLLBACK;                                  -- the only way out
END CATCH
SELECT XACT_STATE() AS AfterCatch, @@TRANCOUNT AS TranCount;        -- 0 / 0
GO


/* ============================================================
   8. SET XACT_ABORT ON
   ============================================================
   OFF (default): a run-time error aborts only the STATEMENT; the batch
                  continues and the transaction STAYS OPEN (locks held!)
                  unless you handle it -> classic bug.
   ON           : any run-time error aborts the whole BATCH and rolls the
                  transaction back automatically. Inside TRY/CATCH the
                  transaction is instead marked uncommittable (-1) so the
                  CATCH block cannot accidentally COMMIT it.
   Also required for distributed transactions. RULE: put it in every
   procedure that writes data.
   ============================================================ */
SET XACT_ABORT ON;
BEGIN TRY
    BEGIN TRAN;
        UPDATE dbo.L16_Accounts SET Balance = Balance - 500 WHERE AccountID = 1;
        INSERT INTO dbo.L16_Accounts (AccountID, Owner, Balance) VALUES (1, 'Dup', 0);   -- same PK error as 7a
    COMMIT;
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
    SELECT XACT_STATE() AS XactState, @@TRANCOUNT AS TranCount;   -- -1 / 1 : now DOOMED (compare with 7a)
    IF XACT_STATE() <> 0 ROLLBACK;
END CATCH
SET XACT_ABORT OFF;
SELECT Balance FROM dbo.L16_Accounts WHERE AccountID = 1;       -- 10000
GO
-- Without TRY/CATCH (not run here, it would stop this script):
--   SET XACT_ABORT ON; BEGIN TRAN; UPDATE ...; INSERT <error>; COMMIT;
--   -> batch stops at the error, the transaction is rolled back, @@TRANCOUNT = 0.
--   With XACT_ABORT OFF the same script prints the error, SKIPS nothing else,
--   reaches COMMIT and commits the UPDATE.  Try it in SSMS to believe it.


/* ============================================================
   9. THE STANDARD PROCEDURE TEMPLATE (transaction + error handling)
   ============================================================ */
CREATE PROCEDURE dbo.usp_L16_Transfer
    @FromAccount INT,
    @ToAccount   INT,
    @Amount      DECIMAL(12,2)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;                    -- errors doom the transaction, never half-commits

    BEGIN TRY
        IF @Amount <= 0
            THROW 50001, 'Amount must be positive.', 1;

        BEGIN TRAN;

            UPDATE dbo.L16_Accounts SET Balance = Balance - @Amount WHERE AccountID = @FromAccount;
            IF @@ROWCOUNT = 0
                THROW 50002, 'From-account not found.', 1;

            UPDATE dbo.L16_Accounts SET Balance = Balance + @Amount WHERE AccountID = @ToAccount;
            IF @@ROWCOUNT = 0
                THROW 50003, 'To-account not found.', 1;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;      -- (XACT_STATE() <> 0 works too)
        THROW;                            -- re-raise the ORIGINAL error to the caller
    END CATCH
END
GO

-- 9a. Success
EXEC dbo.usp_L16_Transfer @FromAccount = 1, @ToAccount = 2, @Amount = 2500;
SELECT AccountID, Balance FROM dbo.L16_Accounts WHERE AccountID IN (1, 2);   -- 7500 / 12500
GO
-- 9b. Failure: insufficient funds -> CHECK constraint -> rolled back, error re-thrown
BEGIN TRY
    EXEC dbo.usp_L16_Transfer @FromAccount = 1, @ToAccount = 2, @Amount = 99999;
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
SELECT AccountID, Balance FROM dbo.L16_Accounts WHERE AccountID IN (1, 2);   -- 7500 / 12500 (unchanged)
GO
-- 9c. Failure: unknown account -> our own THROW
BEGIN TRY
    EXEC dbo.usp_L16_Transfer @FromAccount = 1, @ToAccount = 999, @Amount = 10;
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
SELECT AccountID, Balance FROM dbo.L16_Accounts WHERE AccountID = 1;         -- 7500 (debit undone)
GO
UPDATE dbo.L16_Accounts SET Balance = 10000;   -- reset
GO


/* ============================================================
   10. TABLE VARIABLE vs TEMP TABLE on ROLLBACK  (recap of Level 12)
   ============================================================ */
DROP TABLE IF EXISTS #L16_Temp;
CREATE TABLE #L16_Temp (ID INT);
DECLARE @tv TABLE (ID INT);

BEGIN TRAN;
    INSERT INTO #L16_Temp VALUES (1), (2), (3);
    INSERT INTO @tv       VALUES (1), (2), (3);
ROLLBACK;

SELECT (SELECT COUNT(*) FROM #L16_Temp) AS TempTableRows,     -- 0  (temp tables ARE transactional)
       (SELECT COUNT(*) FROM @tv)       AS TableVariableRows; -- 3  (table variables are NOT)
DROP TABLE #L16_Temp;
GO
-- Use: log error details into a table variable BEFORE the rollback; they survive.


/* ============================================================
   11. WHAT IS LOGGED?  Transaction log basics
   ============================================================
   Every change is first written to the LOG (.ldf) as log records
   (before-image / after-image), then to data pages later. COMMIT
   = "log records are on disk" -> durability. ROLLBACK = read the
   log backwards and undo. A LONG transaction:
     - holds its locks the whole time (blocking),
     - keeps the log from being truncated (log file grows),
     - makes ROLLBACK take as long as the work itself.
   ============================================================ */
BEGIN TRAN;
    UPDATE dbo.L16_Accounts SET Balance = Balance + 1;           -- 8 rows
    SELECT t.database_transaction_log_record_count AS LogRecords,
           t.database_transaction_log_bytes_used   AS LogBytes
    FROM sys.dm_tran_database_transactions t
    JOIN sys.dm_tran_session_transactions  s ON s.transaction_id = t.transaction_id
    WHERE s.session_id = @@SPID AND t.database_id = DB_ID();
    -- expect 9 records (1 BEGIN + 8 row updates) and about 1 KB
ROLLBACK;
GO
-- Is something stopping the log from being reused? NOTHING / LOG_BACKUP are normal;
-- ACTIVE_TRANSACTION means a long open transaction is pinning the log.
SELECT name, recovery_model_desc, log_reuse_wait_desc FROM sys.databases WHERE name = DB_NAME();
SELECT total_log_size_in_bytes / 1024 AS LogKB, used_log_space_in_percent AS UsedPct
FROM sys.dm_db_log_space_usage;
GO
-- Long-running open transactions on the server right now (none expected):
SELECT s.session_id, t.transaction_begin_time, DATEDIFF(SECOND, t.transaction_begin_time, GETDATE()) AS OpenSeconds
FROM sys.dm_tran_active_transactions t
JOIN sys.dm_tran_session_transactions s ON s.transaction_id = t.transaction_id
ORDER BY t.transaction_begin_time;
GO


/* ============================================================
   12. NAMING TRANSACTIONS
   ============================================================ */
-- The name is optional documentation. Only the OUTERMOST name matters;
-- ROLLBACK TRAN <name> must use that outermost name (or a savepoint name).
BEGIN TRAN Transfer_1_to_2;
    UPDATE dbo.L16_Accounts SET Balance = Balance - 100 WHERE AccountID = 1;
    UPDATE dbo.L16_Accounts SET Balance = Balance + 100 WHERE AccountID = 2;
COMMIT TRAN Transfer_1_to_2;
GO
BEGIN TRAN OuterTran;
    BEGIN TRAN InnerTran;
    BEGIN TRY
        ROLLBACK TRAN InnerTran;         -- error 6401: inner names are ignored
    END TRY
    BEGIN CATCH
        PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
    END CATCH
ROLLBACK TRAN OuterTran;                 -- fine: outermost name
SELECT @@TRANCOUNT AS TranCount;         -- 0
GO
-- BEGIN TRAN name WITH MARK 'description' also writes a mark into the log so a
-- restore can stop exactly there (RESTORE ... WITH STOPATMARK).
UPDATE dbo.L16_Accounts SET Balance = 10000;   -- reset
GO


/* ============================================================
   13. TRANSACTION IN A LOOP - batching commits
   ============================================================
   Every COMMIT = a log flush to disk. 3000 rows in autocommit =
   3000 flushes. One big transaction = 1 flush but locks/log held
   for the whole run. Batches (commit every N rows) are the
   practical middle ground for large loads/deletes.
   ============================================================ */
CREATE TABLE dbo.L16_Log (ID INT NOT NULL PRIMARY KEY, Note VARCHAR(30) NOT NULL);
GO
-- 13a. autocommit: one transaction per INSERT
DECLARE @i INT = 1, @t0 DATETIME2(3) = SYSDATETIME();
WHILE @i <= 3000
BEGIN
    INSERT INTO dbo.L16_Log (ID, Note) VALUES (@i, 'autocommit');
    SET @i += 1;
END
PRINT 'autocommit   : ' + CAST(DATEDIFF(MILLISECOND, @t0, SYSDATETIME()) AS VARCHAR(10)) + ' ms';
TRUNCATE TABLE dbo.L16_Log;
GO
-- 13b. one big transaction
DECLARE @i INT = 1, @t0 DATETIME2(3) = SYSDATETIME();
BEGIN TRAN;
WHILE @i <= 3000
BEGIN
    INSERT INTO dbo.L16_Log (ID, Note) VALUES (@i, 'one tran');
    SET @i += 1;
END
COMMIT;
PRINT 'one big tran : ' + CAST(DATEDIFF(MILLISECOND, @t0, SYSDATETIME()) AS VARCHAR(10)) + ' ms';
TRUNCATE TABLE dbo.L16_Log;
GO
-- 13c. batches: commit every 500 rows
DECLARE @i INT = 1, @t0 DATETIME2(3) = SYSDATETIME();
BEGIN TRAN;
WHILE @i <= 3000
BEGIN
    INSERT INTO dbo.L16_Log (ID, Note) VALUES (@i, 'batch');
    IF @i % 500 = 0
    BEGIN
        COMMIT;                -- release locks, flush log
        BEGIN TRAN;            -- start the next batch
    END
    SET @i += 1;
END
IF @@TRANCOUNT > 0 COMMIT;     -- the last (possibly partial) batch
PRINT 'batched 500  : ' + CAST(DATEDIFF(MILLISECOND, @t0, SYSDATETIME()) AS VARCHAR(10)) + ' ms';
SELECT COUNT(*) AS Rows FROM dbo.L16_Log;    -- 3000
GO
-- expect: autocommit slowest, one big tran fastest, batches close to the big one.
-- Same idea for big DELETEs:  WHILE 1=1 BEGIN DELETE TOP (5000) ... ; IF @@ROWCOUNT = 0 BREAK; END


/* ============================================================
   14. CLEANUP
   ============================================================ */
SET XACT_ABORT OFF;
SET IMPLICIT_TRANSACTIONS OFF;
IF @@TRANCOUNT > 0 ROLLBACK;
DROP PROCEDURE IF EXISTS dbo.usp_L16_Transfer;
DROP TABLE IF EXISTS dbo.L16_Accounts, dbo.L16_Log;
GO
SELECT name FROM sys.objects WHERE name LIKE '%L16%';   -- expect 0 rows
GO
/* DONE. Next: 02_Practice_Isolation_Locks.sql */
