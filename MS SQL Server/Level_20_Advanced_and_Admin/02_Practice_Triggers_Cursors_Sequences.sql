/* ============================================================
   LEVEL 20 - ADVANCED AND ADMIN  |  02_Practice_Triggers_Cursors_Sequences.sql
   ------------------------------------------------------------
   Topics : AFTER triggers with inserted/deleted (audit table), UPDATE()
            and COLUMNS_UPDATED(), multi-row safety, INSTEAD OF trigger on
            a view (soft delete), DDL trigger (blocks DROP TABLE),
            DISABLE / ENABLE TRIGGER, sys.triggers, nested / recursive
            trigger settings, why triggers are risky; cursors (full syntax,
            options, the same task set-based, timing); sequences (CREATE,
            NEXT VALUE FOR, sp_sequence_get_range, RESTART, CACHE, shared
            across tables, gaps); IDENTITY recap (SCOPE_IDENTITY,
            IDENT_CURRENT, reseed).

   HOW TO PRACTICE: run block by block, predict the output first.
   Works on a COPY dbo.L20_Orders; base tables are never changed.
   ============================================================ */

USE SQLPractice;
GO
SET QUOTED_IDENTIFIER ON;      -- the DDL trigger reads EVENTDATA() with an XML method -> needs ON (sqlcmd default is OFF)
SET NOCOUNT ON;
GO


/* ============================================================
   0. SETUP - a copy of Orders + an audit table
   ============================================================ */
DROP TABLE IF EXISTS dbo.L20_OrderAudit;
DROP VIEW  IF EXISTS dbo.vw_L20_ActiveOrders;
DROP TABLE IF EXISTS dbo.L20_Orders;
GO
SELECT * INTO dbo.L20_Orders FROM dbo.Orders;                           -- 19 rows
ALTER TABLE dbo.L20_Orders ADD CONSTRAINT PK_L20_Orders PRIMARY KEY (OrderID);
CREATE TABLE dbo.L20_OrderAudit
(
    AuditID    INT IDENTITY(1,1) PRIMARY KEY,
    OrderID    INT           NOT NULL,
    Action     CHAR(1)       NOT NULL,          -- I / U / D
    OldAmount  DECIMAL(12,2) NULL,
    NewAmount  DECIMAL(12,2) NULL,
    ChangedBy  SYSNAME       NOT NULL DEFAULT SUSER_SNAME(),
    ChangedAt  DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME()
);
GO


/* ============================================================
   1. AFTER TRIGGER - the inserted and deleted pseudo-tables
   ============================================================
   inserted = the new rows (INSERT / UPDATE), deleted = the old rows (DELETE / UPDATE).
   A trigger fires ONCE PER STATEMENT, not once per row -> write it for MANY rows (set-based).
   ============================================================ */
CREATE OR ALTER TRIGGER dbo.trg_L20_Orders_Audit
ON dbo.L20_Orders
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;                                                     -- otherwise "(n rows affected)" from the trigger confuses apps
    INSERT INTO dbo.L20_OrderAudit (OrderID, Action, OldAmount, NewAmount)
    SELECT COALESCE(i.OrderID, d.OrderID),
           CASE WHEN i.OrderID IS NOT NULL AND d.OrderID IS NOT NULL THEN 'U'
                WHEN i.OrderID IS NOT NULL THEN 'I' ELSE 'D' END,
           d.TotalAmount, i.TotalAmount
    FROM inserted i
    FULL OUTER JOIN deleted d ON d.OrderID = i.OrderID;                 -- FULL join covers all three cases in one statement

    IF UPDATE(TotalAmount) PRINT 'trigger: TotalAmount was in the INSERT/SET list';   -- true even if the value did not change
    PRINT 'trigger: COLUMNS_UPDATED() = ' + CONVERT(VARCHAR(20), COLUMNS_UPDATED(), 1);   -- bitmask, one bit per column (col 1 = bit 1)
END
GO
-- 1a. Multi-row UPDATE: one trigger execution, TWO audit rows (a trigger written with "SELECT @x = ... FROM inserted" would lose one)
UPDATE dbo.L20_Orders SET TotalAmount = TotalAmount + 1 WHERE OrderID IN (1001, 1002);    -- COLUMNS_UPDATED 0x10 = column 5 (TotalAmount)
INSERT INTO dbo.L20_Orders (OrderID, CustomerID, EmployeeID, OrderDate, TotalAmount, Status)
VALUES (2001, 1, 101, '2025-10-01', 100, 'Pending');                                     -- 0x3F = all 6 columns
DELETE FROM dbo.L20_Orders WHERE OrderID = 2001;                                          -- 0x (nothing updated)
UPDATE dbo.L20_Orders SET Status = 'Pending' WHERE OrderID = 1003;                        -- 0x20 = column 6 (Status), UPDATE(TotalAmount) false
GO
SELECT AuditID, OrderID, Action, OldAmount, NewAmount, ChangedBy FROM dbo.L20_OrderAudit ORDER BY AuditID;
-- expect 5 rows: U 1001 (75000 -> 75001), U 1002 (10000 -> 10001), I 2001 (NULL -> 100), D 2001 (100 -> NULL), U 1003 (25000 -> 25000)
GO
-- 1b. A trigger runs INSIDE the statement's transaction: RAISERROR + ROLLBACK cancels the change.
CREATE OR ALTER TRIGGER dbo.trg_L20_Orders_NoCancelCompleted
ON dbo.L20_Orders
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM inserted i JOIN deleted d ON d.OrderID = i.OrderID
               WHERE d.Status = 'Completed' AND i.Status = 'Cancelled')
    BEGIN
        RAISERROR ('A completed order cannot be cancelled.', 16, 1);
        ROLLBACK TRANSACTION;
    END
END
GO
BEGIN TRY
    UPDATE dbo.L20_Orders SET Status = 'Cancelled' WHERE OrderID = 1001;    -- 1001 is Completed
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO
SELECT OrderID, Status FROM dbo.L20_Orders WHERE OrderID = 1001;       -- still Completed
GO
-- (Level 03 rule: if a CHECK constraint can express it, use the constraint - cheaper and cannot be disabled by accident.)
-- Remove the rule again: section 2 will cancel a completed order on purpose, and its INSTEAD OF trigger's
-- UPDATE would fire this AFTER UPDATE trigger (nested triggers!) and roll everything back.
DROP TRIGGER dbo.trg_L20_Orders_NoCancelCompleted;
GO


/* ============================================================
   2. INSTEAD OF TRIGGER - replace the action (here: turn DELETE into a soft delete)
   ============================================================ */
CREATE OR ALTER VIEW dbo.vw_L20_ActiveOrders AS
SELECT OrderID, CustomerID, TotalAmount, Status FROM dbo.L20_Orders WHERE Status <> 'Cancelled';
GO
CREATE OR ALTER TRIGGER dbo.trg_L20_ActiveOrders_Delete
ON dbo.vw_L20_ActiveOrders
INSTEAD OF DELETE
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE o SET Status = 'Cancelled'
    FROM dbo.L20_Orders o JOIN deleted d ON d.OrderID = o.OrderID;      -- the "delete" becomes an update
END
GO
DELETE FROM dbo.vw_L20_ActiveOrders WHERE OrderID = 1004;               -- nothing is deleted...
SELECT OrderID, Status FROM dbo.L20_Orders WHERE OrderID = 1004;        -- ... 1004 is now Cancelled
SELECT COUNT(*) AS ActiveOrders FROM dbo.vw_L20_ActiveOrders;           -- 17 (19 minus 1006 and 1004)
GO
-- INSTEAD OF triggers also make a multi-table view updatable, and can validate before the write happens.


/* ============================================================
   3. DDL TRIGGER - react to CREATE / ALTER / DROP (here: block DROP TABLE)
   ============================================================ */
CREATE OR ALTER TRIGGER trg_L20_NoDropTable
ON DATABASE
FOR DROP_TABLE
AS
BEGIN
    DECLARE @e XML = EVENTDATA();                                       -- who / what / which statement, as XML
    DECLARE @obj SYSNAME = @e.value('(/EVENT_INSTANCE/ObjectName)[1]', 'sysname');   -- (XML methods cannot sit directly inside PRINT)
    PRINT 'DDL trigger: ' + @obj + ' cannot be dropped in this database.';
    ROLLBACK;                                                           -- DDL runs in a transaction too
END
GO
BEGIN TRY
    DROP TABLE dbo.L20_OrderAudit;
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();                        -- "The transaction ended in the trigger. The batch has been aborted."
END CATCH
GO
SELECT CASE WHEN OBJECT_ID('dbo.L20_OrderAudit') IS NOT NULL THEN 1 ELSE 0 END AS AuditTableStillExists;   -- 1
GO
DROP TRIGGER trg_L20_NoDropTable ON DATABASE;                           -- remove it, or CLEANUP cannot drop anything!
GO
-- Real-world use: audit schema changes into a table (EVENTDATA() XML has login, object, TSQL command), block on production.


/* ============================================================
   4. MANAGING TRIGGERS: sys.triggers, DISABLE / ENABLE, nested and recursive settings
   ============================================================ */
SELECT name, OBJECT_NAME(parent_id) AS ParentObject, type_desc, is_disabled, is_instead_of_trigger
FROM sys.triggers WHERE name LIKE 'trg_L20%';                          -- 2 rows: the audit trigger (table) and the INSTEAD OF trigger (view)
GO
DISABLE TRIGGER dbo.trg_L20_Orders_Audit ON dbo.L20_Orders;            -- bulk load without auditing
UPDATE dbo.L20_Orders SET TotalAmount = TotalAmount + 1 WHERE OrderID = 1001;   -- no audit row, no PRINT
ENABLE TRIGGER dbo.trg_L20_Orders_Audit ON dbo.L20_Orders;
SELECT COUNT(*) AS AuditRows FROM dbo.L20_OrderAudit;
-- expect 6: the 5 rows of section 1 + 1 for the soft delete of 1004 (the INSTEAD OF trigger's UPDATE fired
-- the audit trigger - nested triggers again). The rolled-back update of 1001 in 1b left NO row.
GO
DROP TRIGGER dbo.trg_L20_Orders_Audit;      -- done with auditing (section 5 would otherwise fire it 19 times)
GO
-- Server-wide: 'nested triggers' (a trigger's DML fires other tables' triggers, max 32 levels, default ON);
-- per database: RECURSIVE_TRIGGERS (a trigger firing itself, default OFF).
SELECT name, value_in_use FROM sys.configurations WHERE name = 'nested triggers';          -- 1
SELECT is_recursive_triggers_on FROM sys.databases WHERE name = DB_NAME();                 -- 0
GO
/* WHY TRIGGERS ARE RISKY
   - Invisible: nobody sees them in the app code; a slow UPDATE is "mysterious".
   - Run inside the caller's transaction: a slow trigger holds the caller's locks longer.
   - Row-by-row logic ("SELECT @id = OrderID FROM inserted") silently breaks on multi-row statements.
   - Nested chains and recursion are hard to reason about.
   Prefer constraints for rules, temporal tables for history, and explicit code in procedures where possible. */


/* ============================================================
   5. CURSORS - row-by-row processing (know the syntax, avoid it when a set-based statement exists)
   ============================================================ */
-- 5a. Realistic task: recompute each order's TotalAmount from its lines, one order at a time.
DECLARE @OrderID INT, @Total DECIMAL(12,2), @rows INT = 0;

DECLARE cur_orders CURSOR LOCAL FAST_FORWARD FOR                        -- LOCAL: dies with the batch; FAST_FORWARD: read-only, forward-only, fastest
    SELECT OrderID FROM dbo.L20_Orders ORDER BY OrderID;

OPEN cur_orders;
FETCH NEXT FROM cur_orders INTO @OrderID;
WHILE @@FETCH_STATUS = 0                                                -- 0 = row fetched, -1 = end, -2 = row gone
BEGIN
    SELECT @Total = SUM(Quantity * UnitPrice) FROM dbo.OrderDetails WHERE OrderID = @OrderID;
    UPDATE dbo.L20_Orders SET TotalAmount = @Total WHERE OrderID = @OrderID;
    SET @rows += 1;
    FETCH NEXT FROM cur_orders INTO @OrderID;
END
CLOSE cur_orders;                                                       -- release the rows
DEALLOCATE cur_orders;                                                  -- release the cursor object
SELECT @rows AS OrdersProcessed;                                        -- 19
GO
/* CURSOR OPTIONS (DECLARE name CURSOR [LOCAL|GLOBAL] [FORWARD_ONLY|SCROLL] [STATIC|KEYSET|DYNAMIC|FAST_FORWARD] [READ_ONLY] FOR ...)
   STATIC   = works on a tempdb snapshot;  DYNAMIC = sees other sessions' changes;  KEYSET = keys fixed, values live;
   SCROLL   = FETCH FIRST/LAST/PRIOR/ABSOLUTE n allowed;  FOR UPDATE OF col = positioned updates (WHERE CURRENT OF cur).
   Always CLOSE + DEALLOCATE, or use LOCAL so the batch end does it.                                                   */

-- 5b. The SAME task set-based: one UPDATE with a derived table
UPDATE o
SET TotalAmount = x.Total
FROM dbo.L20_Orders o
JOIN (SELECT OrderID, SUM(Quantity * UnitPrice) AS Total FROM dbo.OrderDetails GROUP BY OrderID) x ON x.OrderID = o.OrderID;
SELECT COUNT(*) AS Mismatches FROM dbo.L20_Orders o JOIN dbo.Orders b ON b.OrderID = o.OrderID WHERE o.TotalAmount <> b.TotalAmount;   -- 0 (totals restored)
GO
-- 5c. TIMING on 20,000 rows: cursor vs one statement
DROP TABLE IF EXISTS dbo.L20_Numbers;
SELECT value AS N, CAST(0 AS BIGINT) AS Square INTO dbo.L20_Numbers FROM GENERATE_SERIES(1, 20000);
CREATE UNIQUE CLUSTERED INDEX CX_L20_Numbers ON dbo.L20_Numbers (N);
GO
DECLARE @t0 DATETIME2 = SYSDATETIME(), @n INT;
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT N FROM dbo.L20_Numbers;
OPEN c; FETCH NEXT FROM c INTO @n;
WHILE @@FETCH_STATUS = 0
BEGIN
    UPDATE dbo.L20_Numbers SET Square = CAST(@n AS BIGINT) * @n WHERE N = @n;
    FETCH NEXT FROM c INTO @n;
END
CLOSE c; DEALLOCATE c;
SELECT 'cursor, 20000 fetches' AS Method, DATEDIFF(MILLISECOND, @t0, SYSDATETIME()) AS Ms;   -- about 300-3000 ms depending on the box
GO
DECLARE @t0 DATETIME2 = SYSDATETIME();
UPDATE dbo.L20_Numbers SET Square = CAST(N AS BIGINT) * N;
SELECT 'one UPDATE' AS Method, DATEDIFF(MILLISECOND, @t0, SYSDATETIME()) AS Ms;                -- about 10 ms
GO
-- When is a cursor OK? Calling a proc per row (e.g. one backup per database), admin scripts, tiny row counts.


/* ============================================================
   6. SEQUENCES - a number generator that is NOT tied to one table
   ============================================================ */
DROP SEQUENCE IF EXISTS dbo.seq_L20_Invoice;
CREATE SEQUENCE dbo.seq_L20_Invoice AS INT START WITH 1000 INCREMENT BY 1 MINVALUE 1 NO CYCLE CACHE 10;
GO
-- 6a. NEXT VALUE FOR: each reference in a DIFFERENT statement gives a new number; twice in the SAME row = same number.
SELECT NEXT VALUE FOR dbo.seq_L20_Invoice AS FirstCall;                                  -- 1000
SELECT NEXT VALUE FOR dbo.seq_L20_Invoice AS A, NEXT VALUE FOR dbo.seq_L20_Invoice AS B; -- 1001, 1001 (once per row!)
GO
-- 6b. Shared across tables: invoices and credit notes draw from ONE numbering
DROP TABLE IF EXISTS dbo.L20_Invoices, dbo.L20_CreditNotes;
CREATE TABLE dbo.L20_Invoices    (InvoiceNo INT NOT NULL DEFAULT (NEXT VALUE FOR dbo.seq_L20_Invoice) PRIMARY KEY, CustomerID INT NOT NULL);
CREATE TABLE dbo.L20_CreditNotes (CreditNo  INT NOT NULL DEFAULT (NEXT VALUE FOR dbo.seq_L20_Invoice) PRIMARY KEY, CustomerID INT NOT NULL);
INSERT INTO dbo.L20_Invoices (CustomerID) VALUES (1), (2);
INSERT INTO dbo.L20_CreditNotes (CustomerID) VALUES (1);
INSERT INTO dbo.L20_Invoices (CustomerID) VALUES (3);
SELECT 'Invoice' AS Kind, InvoiceNo AS No, CustomerID FROM dbo.L20_Invoices
UNION ALL SELECT 'CreditNote', CreditNo, CustomerID FROM dbo.L20_CreditNotes ORDER BY No;   -- 1002, 1003 invoices, 1004 credit note, 1005 invoice
GO
-- 6c. sp_sequence_get_range: reserve a block of numbers for an application (e.g. 5 at once)
DECLARE @first SQL_VARIANT, @last SQL_VARIANT;
EXEC sp_sequence_get_range @sequence_name = N'dbo.seq_L20_Invoice', @range_size = 5,
                           @range_first_value = @first OUTPUT, @range_last_value = @last OUTPUT;
SELECT CAST(@first AS INT) AS RangeFirst, CAST(@last AS INT) AS RangeLast;                 -- 1006, 1010
GO
-- 6d. Metadata, RESTART, and gaps: CACHE 10 keeps numbers in memory; a crash or restart loses the unused
--     part of the cache (gap). A rolled-back transaction also consumes its number (gap). Gaps are normal.
SELECT name, current_value, increment, cache_size, is_cycling FROM sys.sequences WHERE name = 'seq_L20_Invoice';   -- current_value 1010
ALTER SEQUENCE dbo.seq_L20_Invoice RESTART WITH 5000;
SELECT NEXT VALUE FOR dbo.seq_L20_Invoice AS AfterRestart;                                 -- 5000
GO
/* SEQUENCE vs IDENTITY
   IDENTITY : one column of one table, value known only after INSERT (SCOPE_IDENTITY), cannot be shared, cannot ask for the next value first.
   SEQUENCE : object of its own, usable in DEFAULTs of many tables, value can be fetched BEFORE the insert, ranges,
              RESTART / CYCLE, can be used in a SELECT. Both can have gaps. Both are not "row numbers" (Level 11 for that).   */


/* ============================================================
   7. IDENTITY RECAP
   ============================================================ */
INSERT INTO dbo.L20_OrderAudit (OrderID, Action) VALUES (9999, 'I');
SELECT SCOPE_IDENTITY() AS ScopeIdentity,                              -- last identity in THIS scope (proc/batch) - the one to use
       @@IDENTITY       AS AtAtIdentity,                               -- last identity in the session, ANY scope (a trigger could change it!)
       IDENT_CURRENT('dbo.L20_OrderAudit') AS IdentCurrent;            -- last identity of the table, any session
-- expect all three = 8: 6 audit rows exist, but the audit row of the ROLLED-BACK update in 1b already burned
-- value 6 (identity values are never given back), so this row gets 8. Gaps are normal.
GO
-- Reseed: next value becomes 100 + 1. (RESEED can also fix a broken identity after a bad delete.)
DBCC CHECKIDENT ('dbo.L20_OrderAudit', RESEED, 100) WITH NO_INFOMSGS;
INSERT INTO dbo.L20_OrderAudit (OrderID, Action) VALUES (9999, 'I');
SELECT SCOPE_IDENTITY() AS AfterReseed;                                -- 101
DBCC CHECKIDENT ('dbo.L20_OrderAudit', NORESEED);                      -- prints current identity value (101) and current column value
GO


/* ============================================================
   8. CLEANUP
   ============================================================ */
DROP TRIGGER IF EXISTS dbo.trg_L20_ActiveOrders_Delete;
DROP VIEW    IF EXISTS dbo.vw_L20_ActiveOrders;
DROP TABLE   IF EXISTS dbo.L20_OrderAudit;
DROP TABLE   IF EXISTS dbo.L20_Orders;                                  -- drops its triggers too
DROP TABLE   IF EXISTS dbo.L20_Numbers;
DROP TABLE   IF EXISTS dbo.L20_Invoices, dbo.L20_CreditNotes;           -- before the sequence (their DEFAULTs reference it)
DROP SEQUENCE IF EXISTS dbo.seq_L20_Invoice;
IF EXISTS (SELECT 1 FROM sys.triggers WHERE name = 'trg_L20_NoDropTable' AND parent_class_desc = 'DATABASE')
    DROP TRIGGER trg_L20_NoDropTable ON DATABASE;
GO
/* DONE. Next: 03_Practice_JSON_XML.sql */
