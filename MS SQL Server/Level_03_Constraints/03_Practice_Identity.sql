/* ============================================================
   LEVEL 03 - CONSTRAINTS  |  03_Practice_Identity.sql
   ------------------------------------------------------------
   Topics : IDENTITY (seed / increment), SCOPE_IDENTITY vs @@IDENTITY
            vs IDENT_CURRENT, SET IDENTITY_INSERT, DBCC CHECKIDENT,
            gaps after ROLLBACK / DELETE, identity metadata

   HOW TO PRACTICE: run block by block, predict the output first.
   Works on fresh copies dbo.L03_Departments / dbo.L03_Employees plus
   two small demo tables (dbo.L03_Tickets, dbo.L03_TicketAudit).
   Base tables are only read. Everything is dropped at the end.
   Next: 04_Practice_Manage_Constraints.sql
   ============================================================ */

USE SQLPractice;
GO

/* ---------- Rebuild the helper copies (drops every L03 object of this level, children first) ---------- */
DROP TRIGGER IF EXISTS dbo.trg_L03_TicketAudit;
DROP TABLE IF EXISTS dbo.L03_TicketAudit;
DROP TABLE IF EXISTS dbo.L03_Tickets;
DROP TABLE IF EXISTS dbo.L03_ProjectAssignments;
DROP TABLE IF EXISTS dbo.L03_Projects;
DROP TABLE IF EXISTS dbo.L03_Assets;
DROP TABLE IF EXISTS dbo.L03_Unnamed;
DROP TABLE IF EXISTS dbo.L03_NullablePK;
DROP TABLE IF EXISTS dbo.L03_Employees;
DROP TABLE IF EXISTS dbo.L03_Departments;
GO
CREATE TABLE dbo.L03_Departments
(
    DepartmentID   INT          NOT NULL,
    DepartmentName VARCHAR(100) NOT NULL,
    Location       VARCHAR(100) NULL,
    CONSTRAINT PK_L03_Departments      PRIMARY KEY (DepartmentID),
    CONSTRAINT UQ_L03_Departments_Name UNIQUE (DepartmentName)
);
CREATE TABLE dbo.L03_Employees
(
    EmployeeID   INT           NOT NULL,
    EmployeeName VARCHAR(100)  NOT NULL,
    Email        VARCHAR(150)  NULL,
    DepartmentID INT           NULL,
    Salary       DECIMAL(12,2) NULL,
    HireDate     DATE          NULL,
    ManagerID    INT           NULL,
    CONSTRAINT PK_L03_Employees             PRIMARY KEY (EmployeeID),
    CONSTRAINT UQ_L03_Employees_Email       UNIQUE (Email),
    CONSTRAINT CK_L03_Employees_Salary      CHECK (Salary > 0),
    CONSTRAINT FK_L03_Employees_Departments FOREIGN KEY (DepartmentID) REFERENCES dbo.L03_Departments (DepartmentID),
    CONSTRAINT FK_L03_Employees_Manager     FOREIGN KEY (ManagerID)    REFERENCES dbo.L03_Employees (EmployeeID)
);
INSERT INTO dbo.L03_Departments (DepartmentID, DepartmentName, Location)
SELECT DepartmentID, DepartmentName, Location FROM dbo.Departments;
INSERT INTO dbo.L03_Employees (EmployeeID, EmployeeName, Email, DepartmentID, Salary, HireDate, ManagerID)
SELECT EmployeeID, EmployeeName, Email, DepartmentID, Salary, HireDate, ManagerID FROM dbo.Employees;
GO


/* ============================================================
   1. IDENTITY
   ============================================================ */
-- IDENTITY(seed, increment) = SQL Server generates the number for you.
-- One identity column per table. You normally never insert it or update it.

-- 1a. Seed 1000, step 10
CREATE TABLE dbo.L03_Tickets
(
    TicketID   INT          NOT NULL IDENTITY(1000, 10) CONSTRAINT PK_L03_Tickets PRIMARY KEY,
    Subject    VARCHAR(100) NOT NULL,
    EmployeeID INT          NULL CONSTRAINT FK_L03_Tickets_Employees REFERENCES dbo.L03_Employees (EmployeeID)
);
INSERT INTO dbo.L03_Tickets (Subject, EmployeeID)
VALUES ('Laptop slow', 102), ('VPN down', 104), ('New badge', 105);
SELECT * FROM dbo.L03_Tickets;   -- 1000, 1010, 1020
GO

-- 1b. You cannot supply the value yourself (by default) ...
BEGIN TRY
    INSERT INTO dbo.L03_Tickets (TicketID, Subject) VALUES (5, 'Manual id');
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO
-- ... and you can never UPDATE it (compile-time refusal, so EXEC is used to let CATCH see it;
--     real message, Msg 8102: "Cannot update identity column 'TicketID'.")
BEGIN TRY
    EXEC ('UPDATE dbo.L03_Tickets SET TicketID = 1 WHERE TicketID = 1000;');
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO

-- 1c. SCOPE_IDENTITY() vs @@IDENTITY vs IDENT_CURRENT('table')
--     SCOPE_IDENTITY()   = last identity created in THIS scope (your batch / procedure)   <- use this one
--     @@IDENTITY         = last identity in THIS session, ANY scope (a trigger changes it!)
--     IDENT_CURRENT('t') = last identity for THAT table, ANY session (another user may have inserted)
--     To show the trap we add an audit table + an AFTER INSERT trigger (triggers = Level 20, just read it).
CREATE TABLE dbo.L03_TicketAudit
(
    AuditID  INT          NOT NULL IDENTITY(500, 1) CONSTRAINT PK_L03_TicketAudit PRIMARY KEY,
    TicketID INT          NOT NULL,
    LoggedAt DATETIME2(0) NOT NULL CONSTRAINT DF_L03_TicketAudit_LoggedAt DEFAULT (SYSDATETIME())
);
GO
CREATE TRIGGER dbo.trg_L03_TicketAudit ON dbo.L03_Tickets AFTER INSERT AS
BEGIN
    INSERT INTO dbo.L03_TicketAudit (TicketID) SELECT TicketID FROM inserted;
END
GO
INSERT INTO dbo.L03_Tickets (Subject, EmployeeID) VALUES ('Printer jam', 108);
SELECT SCOPE_IDENTITY()                      AS Scope_Identity,   -- 1030 (my insert)
       @@IDENTITY                            AS AtAt_Identity,    -- 500  (the trigger's insert!)
       IDENT_CURRENT('dbo.L03_Tickets')      AS Ident_Tickets,    -- 1030
       IDENT_CURRENT('dbo.L03_TicketAudit')  AS Ident_Audit;      -- 500
GO

-- 1d. SET IDENTITY_INSERT: temporarily allow your own value (a column list is mandatory)
SET IDENTITY_INSERT dbo.L03_Tickets ON;
INSERT INTO dbo.L03_Tickets (TicketID, Subject) VALUES (5,    'Imported ticket');    -- lower than counter: counter unchanged
INSERT INTO dbo.L03_Tickets (TicketID, Subject) VALUES (2000, 'Imported ticket 2');  -- higher: counter jumps to 2000
SET IDENTITY_INSERT dbo.L03_Tickets OFF;
INSERT INTO dbo.L03_Tickets (Subject) VALUES ('After import');
SELECT TicketID, Subject FROM dbo.L03_Tickets ORDER BY TicketID;   -- 5, 1000, 1010, 1020, 1030, 2000, 2010
GO
-- Only ONE table per session can have IDENTITY_INSERT ON at a time. Switch it OFF when done.

-- 1e. DBCC CHECKIDENT: look at the counter, or reset it
DBCC CHECKIDENT ('dbo.L03_Tickets', NORESEED);   -- prints: current identity value '2010', current column value '2010'
GO
DELETE FROM dbo.L03_Tickets WHERE TicketID >= 2000;
DBCC CHECKIDENT ('dbo.L03_Tickets', RESEED, 1030) WITH NO_INFOMSGS;   -- next value = 1030 + 10
INSERT INTO dbo.L03_Tickets (Subject) VALUES ('After reseed');
SELECT MAX(TicketID) AS NewestTicket FROM dbo.L03_Tickets;   -- 1040
GO
-- QUIRK: on a table that has NEVER had a row (or right after TRUNCATE), RESEED n makes the NEXT
-- row = n itself, not n + increment. So "RESEED 0" on a brand-new table gives a first id of 0!
-- That is why 00_Setup empties dbo.OrderDetails with TRUNCATE (which resets the counter to the
-- seed correctly) instead of DELETE + RESEED 0. Safe reset recipe: TRUNCATE, or RESEED to
-- (seed - increment) only when the table has already been used.

-- 1f. Gaps are normal: a ROLLBACK does not give the number back
BEGIN TRAN;
    INSERT INTO dbo.L03_Tickets (Subject) VALUES ('Will be rolled back');   -- takes 1050
ROLLBACK;
INSERT INTO dbo.L03_Tickets (Subject) VALUES ('After rollback');            -- gets 1060; 1050 is lost forever
SELECT TicketID, Subject FROM dbo.L03_Tickets WHERE TicketID >= 1040;       -- 1040, 1060
GO
-- DELETE does not reuse numbers either. Only TRUNCATE (Level 04) or RESEED restart the counter.

-- 1g. RESEED below existing rows = a PK collision on the next insert
DBCC CHECKIDENT ('dbo.L03_Tickets', RESEED, 1000) WITH NO_INFOMSGS;   -- next = 1010, but 1010 exists!
GO
BEGIN TRY
    INSERT INTO dbo.L03_Tickets (Subject) VALUES ('Collision');
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO
-- Safe reseed = the current MAX of the column
DECLARE @max INT = (SELECT MAX(TicketID) FROM dbo.L03_Tickets);
DBCC CHECKIDENT ('dbo.L03_Tickets', RESEED, @max) WITH NO_INFOMSGS;
INSERT INTO dbo.L03_Tickets (Subject) VALUES ('Safe again');
SELECT MAX(TicketID) AS NewestTicket FROM dbo.L03_Tickets;   -- 1070
GO

-- 1h. Identity metadata: sys.identity_columns, IDENT_SEED, IDENT_INCR
SELECT OBJECT_NAME(object_id) AS TableName, name AS ColumnName, seed_value, increment_value, last_value
FROM sys.identity_columns
WHERE object_id IN (OBJECT_ID('dbo.L03_Tickets'), OBJECT_ID('dbo.L03_TicketAudit'), OBJECT_ID('dbo.OrderDetails'))
ORDER BY TableName;
-- L03_TicketAudit 500/1/last 507, L03_Tickets 1000/10/last 1070, OrderDetails 1/1/last 25 (see the quirk above)
SELECT IDENT_SEED('dbo.L03_Tickets') AS Seed, IDENT_INCR('dbo.L03_Tickets') AS Incr;   -- 1000, 10
GO


/* ============================================================
   2. CLEANUP
   ============================================================ */
DROP TRIGGER IF EXISTS dbo.trg_L03_TicketAudit;
DROP TABLE IF EXISTS dbo.L03_TicketAudit;
DROP TABLE IF EXISTS dbo.L03_Tickets;
DROP TABLE IF EXISTS dbo.L03_Employees;
DROP TABLE IF EXISTS dbo.L03_Departments;
GO
/* DONE. Next: 04_Practice_Manage_Constraints.sql */
