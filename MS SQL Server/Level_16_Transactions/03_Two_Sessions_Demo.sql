/* ============================================================
   LEVEL 16 - TRANSACTIONS  |  03_Two_Sessions_Demo.sql
   ------------------------------------------------------------
   Topics : dirty read, non-repeatable read, phantom read, blocking
            + finding the blocker + KILL, a real deadlock, SNAPSHOT
            vs READ COMMITTED - all need TWO connections.
   HOW TO PRACTICE: this file is ONE BIG COMMENT so that F5 does
   nothing. Open TWO query windows in SSMS (call them SESSION A and
   SESSION B, both on SQLPractice) and copy-paste the steps in the
   given order. Watch the "expected" lines.
   ============================================================ */

USE SQLPractice;
GO

/* ============================================================
   STEP 0 - SETUP  (run once, in SESSION A)
   ============================================================

    USE SQLPractice;
    DROP TABLE IF EXISTS dbo.L16_Accounts;
    SELECT c.CustomerID AS AccountID, c.CustomerName AS Owner, CAST(10000 AS DECIMAL(12,2)) AS Balance
    INTO dbo.L16_Accounts FROM dbo.Customers c;
    ALTER TABLE dbo.L16_Accounts ADD CONSTRAINT PK_L16_Accounts PRIMARY KEY (AccountID);
    SELECT @@SPID AS SessionA_Spid;        -- note this number

   In SESSION B run:   USE SQLPractice;  SELECT @@SPID AS SessionB_Spid;
   Tip: while a window is blocked, its status bar shows "Executing query..." with a running clock.


   ============================================================
   (a) DIRTY READ  with READ UNCOMMITTED  (and why it is dangerous)
   ============================================================

   SESSION A - step 1: change a row but do NOT commit
        BEGIN TRAN;
        UPDATE dbo.L16_Accounts SET Balance = 999999 WHERE AccountID = 1;

   SESSION B - step 2: read it the normal way (READ COMMITTED)
        SELECT Balance FROM dbo.L16_Accounts WHERE AccountID = 1;
        -- expected: the query WAITS (blocked by A's X lock). Press the red Cancel button.

   SESSION B - step 3: read it with NOLOCK / READ UNCOMMITTED
        SELECT Balance FROM dbo.L16_Accounts WITH (NOLOCK) WHERE AccountID = 1;
        -- expected: 999999.00 returned immediately  <- a DIRTY READ

   SESSION A - step 4: undo
        ROLLBACK;

   SESSION B - step 5: read again normally
        SELECT Balance FROM dbo.L16_Accounts WHERE AccountID = 1;
        -- expected: 10000.00. B saw a value (999999) that NEVER existed.


   ============================================================
   (b) NON-REPEATABLE READ  (READ COMMITTED vs REPEATABLE READ)
   ============================================================

   SESSION A - step 1:
        SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
        BEGIN TRAN;
        SELECT Balance FROM dbo.L16_Accounts WHERE AccountID = 2;     -- expected 10000.00

   SESSION B - step 2: (autocommit, finishes immediately - A holds no lock after its read)
        UPDATE dbo.L16_Accounts SET Balance = 5000 WHERE AccountID = 2;

   SESSION A - step 3: same SELECT, same transaction
        SELECT Balance FROM dbo.L16_Accounts WHERE AccountID = 2;     -- expected 5000.00  <- NON-REPEATABLE
        COMMIT;

   Now the same with REPEATABLE READ:

   SESSION A - step 4:
        SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
        BEGIN TRAN;
        SELECT Balance FROM dbo.L16_Accounts WHERE AccountID = 2;     -- 5000.00, S lock is now HELD

   SESSION B - step 5:
        UPDATE dbo.L16_Accounts SET Balance = 7000 WHERE AccountID = 2;
        -- expected: WAITS (blocked by A's S lock)

   SESSION A - step 6:
        SELECT Balance FROM dbo.L16_Accounts WHERE AccountID = 2;     -- still 5000.00 (repeatable)
        COMMIT;                                                       -- B's UPDATE now completes
        SET TRANSACTION ISOLATION LEVEL READ COMMITTED;

   SESSION B - step 7: check
        SELECT Balance FROM dbo.L16_Accounts WHERE AccountID = 2;     -- 7000.00


   ============================================================
   (c) PHANTOM READ  (REPEATABLE READ vs SERIALIZABLE)
   ============================================================

   SESSION A - step 1:
        SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
        BEGIN TRAN;
        SELECT COUNT(*) AS Rich FROM dbo.L16_Accounts WHERE Balance >= 10000;   -- expected 6 (after (b))

   SESSION B - step 2: insert a NEW row that matches A's WHERE
        INSERT INTO dbo.L16_Accounts (AccountID, Owner, Balance) VALUES (9, 'Phantom', 10000);
        -- expected: succeeds at once (REPEATABLE READ locks existing rows, not the RANGE)

   SESSION A - step 3:
        SELECT COUNT(*) AS Rich FROM dbo.L16_Accounts WHERE Balance >= 10000;   -- expected 7  <- PHANTOM
        COMMIT;

   Now with SERIALIZABLE:

   SESSION A - step 4:
        SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
        BEGIN TRAN;
        SELECT COUNT(*) AS Rich FROM dbo.L16_Accounts WHERE Balance >= 10000;   -- 7, range locks held

   SESSION B - step 5:
        INSERT INTO dbo.L16_Accounts (AccountID, Owner, Balance) VALUES (10, 'Phantom2', 10000);
        -- expected: WAITS (the range is locked)

   SESSION A - step 6:
        SELECT COUNT(*) AS Rich FROM dbo.L16_Accounts WHERE Balance >= 10000;   -- still 7
        COMMIT;                                                                  -- B's INSERT completes
        SET TRANSACTION ISOLATION LEVEL READ COMMITTED;

   SESSION A - step 7: cleanup the phantoms
        DELETE FROM dbo.L16_Accounts WHERE AccountID IN (9, 10);


   ============================================================
   (d) BLOCKING: cause it, FIND the blocker, KILL it
   ============================================================

   SESSION A - step 1: the classic bug - a transaction left open
        BEGIN TRAN;
        UPDATE dbo.L16_Accounts SET Balance = Balance + 1 WHERE AccountID = 3;
        -- (now go for coffee = never commit)

   SESSION B - step 2:
        UPDATE dbo.L16_Accounts SET Balance = Balance + 1 WHERE AccountID = 3;
        -- expected: WAITS forever (LCK_M_U on the same key)

   Open a THIRD window (SESSION C) and find the blocker:
        SELECT r.session_id AS Blocked, r.blocking_session_id AS Blocker, r.wait_type, r.wait_time,
               t.text AS BlockedSql
        FROM sys.dm_exec_requests r
        CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
        WHERE r.blocking_session_id <> 0;
        -- expected 1 row: Blocked = B's spid, Blocker = A's spid, wait_type LCK_M_U

        EXEC sp_who2;            -- find B's row: BlkBy column shows A's spid; A's Status = sleeping
                                 -- (a SLEEPING session with an open transaction = the usual culprit)
        SELECT session_id, open_transaction_count, status, last_request_end_time
        FROM sys.dm_exec_sessions WHERE session_id = <A's spid>;    -- open_transaction_count = 1

        DBCC INPUTBUFFER(<A's spid>);   -- what A last ran (the UPDATE)

   SESSION C - step 3: kill the blocker (its open transaction is rolled back)
        KILL <A's spid>;
        -- expected: B's UPDATE finishes immediately; A's window shows
        -- "A severe error occurred on the current command" - reconnect it.

   SESSION B - step 4: check - only B's +1 was applied
        SELECT Balance FROM dbo.L16_Accounts WHERE AccountID = 3;    -- 10001.00

   Also try in SESSION B before killing:  SET LOCK_TIMEOUT 2000;  then the UPDATE
   -> after 2 s: error 1222 "Lock request time out period exceeded". SET LOCK_TIMEOUT -1;


   ============================================================
   (e) A REAL DEADLOCK  (each session holds one row and wants the other's)
   ============================================================

   SESSION A - step 1:
        BEGIN TRAN;
        UPDATE dbo.L16_Accounts SET Balance = Balance - 100 WHERE AccountID = 1;    -- A holds row 1

   SESSION B - step 2:
        BEGIN TRAN;
        UPDATE dbo.L16_Accounts SET Balance = Balance - 100 WHERE AccountID = 2;    -- B holds row 2

   SESSION A - step 3:
        UPDATE dbo.L16_Accounts SET Balance = Balance + 100 WHERE AccountID = 2;    -- A waits for B

   SESSION B - step 4:
        UPDATE dbo.L16_Accounts SET Balance = Balance + 100 WHERE AccountID = 1;    -- B waits for A = DEADLOCK
        -- expected within ~5 seconds: ONE window gets
        --   Msg 1205 "Transaction (Process ID nn) was deadlocked on lock resources with another
        --   process and has been chosen as the deadlock victim. Rerun the transaction."
        -- and its transaction is rolled back (@@TRANCOUNT = 0 there).
        -- The OTHER window's UPDATE completes; it still has an open transaction.

   SURVIVOR window - step 5:
        COMMIT;

   Both - step 6: verify and look at the graph
        SELECT * FROM dbo.L16_Accounts WHERE AccountID IN (1, 2);
        -- run the "7c deadlock graph" query from 02_Practice_Isolation_Locks.sql -> 1 row now

   Variation: run  SET DEADLOCK_PRIORITY HIGH;  in SESSION A before step 1 -> B is always the victim.
   Fix demo: make both sessions update row 1 FIRST, then row 2 (same order) -> no deadlock, only a short wait.


   ============================================================
   (f) SNAPSHOT vs READ COMMITTED  (readers do not block, do not get blocked)
   ============================================================

   SESSION A - step 0 (once):
        ALTER DATABASE SQLPractice SET ALLOW_SNAPSHOT_ISOLATION ON;

   SESSION A - step 1:
        SET TRANSACTION ISOLATION LEVEL SNAPSHOT;
        BEGIN TRAN;
        SELECT Balance FROM dbo.L16_Accounts WHERE AccountID = 4;    -- expected 10000.00 (snapshot taken NOW)

   SESSION B - step 2: (autocommit)
        UPDATE dbo.L16_Accounts SET Balance = 7777 WHERE AccountID = 4;
        -- expected: completes immediately - a snapshot reader never blocks a writer

   SESSION A - step 3:
        SELECT Balance FROM dbo.L16_Accounts WHERE AccountID = 4;    -- still 10000.00 (transaction-level snapshot)
        COMMIT;
        SELECT Balance FROM dbo.L16_Accounts WHERE AccountID = 4;    -- 7777.00 (new transaction, new snapshot)

   Compare with READ COMMITTED (default) in SESSION A:
        SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
        BEGIN TRAN;
        SELECT Balance FROM dbo.L16_Accounts WHERE AccountID = 4;    -- 7777.00
   SESSION B:
        BEGIN TRAN;
        UPDATE dbo.L16_Accounts SET Balance = 8888 WHERE AccountID = 4;   -- keep it open
   SESSION A:
        SELECT Balance FROM dbo.L16_Accounts WHERE AccountID = 4;    -- WAITS (blocked by B's X lock)
   SESSION B:
        COMMIT;                                                       -- A now returns 8888.00
   SESSION A:
        COMMIT;

   Update conflict under SNAPSHOT (the price of optimistic concurrency):
   SESSION A:
        SET TRANSACTION ISOLATION LEVEL SNAPSHOT;
        BEGIN TRAN;
        SELECT Balance FROM dbo.L16_Accounts WHERE AccountID = 5;
   SESSION B:
        UPDATE dbo.L16_Accounts SET Balance = 1 WHERE AccountID = 5;      -- commits
   SESSION A:
        UPDATE dbo.L16_Accounts SET Balance = 2 WHERE AccountID = 5;
        -- expected: Msg 3960 "Snapshot isolation transaction aborted due to update conflict..."
        -- A's transaction is rolled back. Use UPDLOCK on the first read, or retry.
        SET TRANSACTION ISOLATION LEVEL READ COMMITTED;

   SESSION A - final cleanup:
        ALTER DATABASE SQLPractice SET ALLOW_SNAPSHOT_ISOLATION OFF;
        DROP TABLE IF EXISTS dbo.L16_Accounts;

   ============================================================ */
