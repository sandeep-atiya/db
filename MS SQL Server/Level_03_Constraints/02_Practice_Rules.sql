/* ============================================================
   LEVEL 03 - CONSTRAINTS  |  02_Practice_Rules.sql
   ------------------------------------------------------------
   Topics : UNIQUE (vs PK, only one NULL, composite), NOT NULL,
            CHECK (column-level, table-level / multi-column),
            DEFAULT (constants and functions)

   HOW TO PRACTICE: run block by block, predict the output first.
   Works on fresh copies dbo.L03_Departments / dbo.L03_Employees
   (rebuilt at the top, dropped at the end). Base tables are only read.
   Next: 03_Practice_Identity.sql
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
SELECT (SELECT COUNT(*) FROM dbo.L03_Departments) AS Depts, (SELECT COUNT(*) FROM dbo.L03_Employees) AS Emps;  -- 6, 12
GO
-- (Every test row in this file gets its own Email: UQ_L03_Employees_Email allows only ONE NULL,
--  and Anjali already has it. Otherwise the UNIQUE error would fire before the error we want to see.)


/* ============================================================
   1. UNIQUE
   ============================================================ */
-- UNIQUE = "no two rows may have the same value". Compared with a PK:
--   * a table may have MANY unique constraints (but only one PK)
--   * the column may be NULL - and SQL Server allows only ONE NULL (it treats NULL as a value here)
--   * it creates a NONCLUSTERED index by default

-- 1a. Duplicate email -> error 2627 "Violation of UNIQUE KEY constraint"
BEGIN TRY
    INSERT INTO dbo.L03_Employees (EmployeeID, EmployeeName, Email, Salary)
    VALUES (203, 'Rahul Clone', 'rahul@example.com', 50000);
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO

-- 1b. One NULL is fine (Anjali already has Email NULL) ... a second NULL counts as a duplicate!
SELECT EmployeeID, EmployeeName FROM dbo.L03_Employees WHERE Email IS NULL;   -- 1 row: 110 Anjali
GO
BEGIN TRY
    INSERT INTO dbo.L03_Employees (EmployeeID, EmployeeName, Email, Salary)
    VALUES (204, 'Contractor 2', NULL, 45000);
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO
-- Fix when you need "unique, but many NULLs allowed": a FILTERED unique index (Level 17) instead.
-- (A filtered index needs QUOTED_IDENTIFIER ON; SSMS has it ON, sqlcmd has it OFF by default.)
SET QUOTED_IDENTIFIER ON;
GO
ALTER TABLE dbo.L03_Employees DROP CONSTRAINT UQ_L03_Employees_Email;
CREATE UNIQUE NONCLUSTERED INDEX UX_L03_Employees_Email
    ON dbo.L03_Employees (Email) WHERE Email IS NOT NULL;
INSERT INTO dbo.L03_Employees (EmployeeID, EmployeeName, Email, Salary)
VALUES (204, 'Contractor 2', NULL, 45000);                                    -- now OK
SELECT COUNT(*) AS NullEmails FROM dbo.L03_Employees WHERE Email IS NULL;    -- 2
GO

-- 1c. Many UNIQUE constraints per table: add a second one on a new Phone column
ALTER TABLE dbo.L03_Employees ADD Phone VARCHAR(15) NULL;
GO
-- Adding UNIQUE while rows already share a value is refused - and 13 rows sharing NULL counts too!
-- (real message, Msg 1505: "... a duplicate key was found ... The duplicate key value is (<NULL>)")
BEGIN TRY
    EXEC ('ALTER TABLE dbo.L03_Employees ADD CONSTRAINT UQ_L03_Employees_Phone UNIQUE (Phone);');
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO
-- Give everyone a distinct phone first, then the constraint goes on
UPDATE dbo.L03_Employees SET Phone = '98000' + CAST(EmployeeID AS VARCHAR(10));   -- 98000101, 98000102, ...
ALTER TABLE dbo.L03_Employees ADD CONSTRAINT UQ_L03_Employees_Phone UNIQUE (Phone);
GO
BEGIN TRY
    UPDATE dbo.L03_Employees SET Phone = '98000101' WHERE EmployeeID = 102;   -- same phone as Rahul
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO

-- 1d. Composite UNIQUE: the PAIR must be unique
ALTER TABLE dbo.L03_Departments DROP CONSTRAINT UQ_L03_Departments_Name;
ALTER TABLE dbo.L03_Departments ADD CONSTRAINT UQ_L03_Departments_Name_Loc UNIQUE (DepartmentName, Location);
INSERT INTO dbo.L03_Departments (DepartmentID, DepartmentName, Location) VALUES (7, 'IT', 'Mumbai');  -- IT again, other city: OK
GO
BEGIN TRY
    INSERT INTO dbo.L03_Departments (DepartmentID, DepartmentName, Location) VALUES (8, 'IT', 'Mumbai');  -- same pair
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO

-- 1e. PK vs UNIQUE side by side: both live in sys.key_constraints and both are backed by an index
SELECT OBJECT_NAME(kc.parent_object_id) AS TableName, kc.name, kc.type_desc, i.type_desc AS IndexType
FROM sys.key_constraints kc
JOIN sys.indexes i ON i.object_id = kc.parent_object_id AND i.index_id = kc.unique_index_id
WHERE kc.parent_object_id IN (OBJECT_ID('dbo.L03_Employees'), OBJECT_ID('dbo.L03_Departments'))
ORDER BY TableName, kc.type_desc;
-- expect 4 rows: L03_Departments PK (CLUSTERED) + UQ (NONCLUSTERED), L03_Employees PK + UQ_Phone
GO

-- 1f. Put the copies back to their original shape, so the next sections start from known data
DELETE FROM dbo.L03_Employees WHERE EmployeeID = 204;
DROP INDEX UX_L03_Employees_Email ON dbo.L03_Employees;
ALTER TABLE dbo.L03_Employees ADD CONSTRAINT UQ_L03_Employees_Email UNIQUE (Email);
ALTER TABLE dbo.L03_Employees DROP CONSTRAINT UQ_L03_Employees_Phone;
ALTER TABLE dbo.L03_Employees DROP COLUMN Phone;
DELETE FROM dbo.L03_Departments WHERE DepartmentID = 7;
ALTER TABLE dbo.L03_Departments DROP CONSTRAINT UQ_L03_Departments_Name_Loc;
ALTER TABLE dbo.L03_Departments ADD CONSTRAINT UQ_L03_Departments_Name UNIQUE (DepartmentName);
SELECT (SELECT COUNT(*) FROM dbo.L03_Departments) AS Depts, (SELECT COUNT(*) FROM dbo.L03_Employees) AS Emps;  -- 6, 12
GO


/* ============================================================
   2. NOT NULL
   ============================================================ */
-- NOT NULL is a column property (not a named constraint): "this column must always hold a value".

-- 2a. Explicit NULL into a NOT NULL column -> error 515
BEGIN TRY
    INSERT INTO dbo.L03_Employees (EmployeeID, EmployeeName, Email, Salary)
    VALUES (201, NULL, 'test@example.com', 50000);
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO

-- 2b. Leaving the column OUT of the INSERT is the same thing (there is no DEFAULT to fall back on)
BEGIN TRY
    INSERT INTO dbo.L03_Employees (EmployeeID, Email, Salary) VALUES (201, 'test@example.com', 50000);
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO

-- 2c. Tightening an existing column to NOT NULL fails while it still holds NULLs.
--     (We use HireDate: a column inside a UNIQUE/PK constraint, like Email, cannot be ALTERed at all.)
UPDATE dbo.L03_Employees SET HireDate = NULL WHERE EmployeeID = 110;     -- simulate a missing value
GO
BEGIN TRY
    ALTER TABLE dbo.L03_Employees ALTER COLUMN HireDate DATE NOT NULL;
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO
-- Pattern: fill the NULLs first, THEN tighten the column
UPDATE dbo.L03_Employees SET HireDate = '2024-05-20' WHERE HireDate IS NULL;
ALTER TABLE dbo.L03_Employees ALTER COLUMN HireDate DATE NOT NULL;
GO

-- 2d. Where to see it: IS_NULLABLE (INFORMATION_SCHEMA) or is_nullable (sys.columns)
SELECT COLUMN_NAME, IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'L03_Employees' ORDER BY ORDINAL_POSITION;   -- HireDate is now NO
GO
-- Restore the original shape for the next sections
ALTER TABLE dbo.L03_Employees ALTER COLUMN HireDate DATE NULL;
GO


/* ============================================================
   3. CHECK
   ============================================================ */
-- CHECK = a true/false rule that every row must satisfy on INSERT and on UPDATE.
-- Column-level = rule about one column. Table-level = rule that compares several columns.

-- 3a. Column-level: CK_L03_Employees_Salary CHECK (Salary > 0)
BEGIN TRY
    INSERT INTO dbo.L03_Employees (EmployeeID, EmployeeName, Email, Salary)
    VALUES (201, 'Test', 'test@example.com', -100);
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO
-- UPDATE is checked as well
BEGIN TRY
    UPDATE dbo.L03_Employees SET Salary = 0 WHERE EmployeeID = 102;
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO

-- 3b. GOTCHA: NULL passes every CHECK. (NULL > 0) is UNKNOWN, and CHECK rejects only FALSE.
INSERT INTO dbo.L03_Employees (EmployeeID, EmployeeName, Email, Salary)
VALUES (201, 'No Salary Yet', 'test@example.com', NULL);
SELECT EmployeeID, EmployeeName, Salary FROM dbo.L03_Employees WHERE EmployeeID = 201;   -- inserted, Salary NULL
DELETE FROM dbo.L03_Employees WHERE EmployeeID = 201;
GO
-- If NULL must be rejected too: make the column NOT NULL, or write CHECK (Salary IS NOT NULL AND Salary > 0)

-- 3c. Table-level, multi-column CHECK: nobody can be his/her own manager
ALTER TABLE dbo.L03_Employees ADD CONSTRAINT CK_L03_Employees_NotOwnManager
    CHECK (ManagerID <> EmployeeID);
GO
BEGIN TRY
    INSERT INTO dbo.L03_Employees (EmployeeID, EmployeeName, Email, Salary, ManagerID)
    VALUES (202, 'Self Boss', 'selfboss@example.com', 50000, 202);
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO

-- 3d. Pattern rule with LIKE (must contain something@something.xx)
ALTER TABLE dbo.L03_Employees ADD CONSTRAINT CK_L03_Employees_EmailFormat
    CHECK (Email LIKE '%_@_%.__%');
GO
BEGIN TRY
    INSERT INTO dbo.L03_Employees (EmployeeID, EmployeeName, Email, Salary)
    VALUES (203, 'Bad Mail', 'not-an-email', 50000);
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO

-- 3e. List rule with IN
ALTER TABLE dbo.L03_Departments ADD CONSTRAINT CK_L03_Departments_Location
    CHECK (Location IN ('Delhi', 'Mumbai', 'Bangalore', 'Pune', 'Chennai'));
GO
BEGIN TRY
    INSERT INTO dbo.L03_Departments (DepartmentID, DepartmentName, Location) VALUES (7, 'Support', 'Kolkata');
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO

-- 3f. Adding a CHECK that EXISTING rows already break is refused (Rahul 85000, Sneha 90000)
BEGIN TRY
    ALTER TABLE dbo.L03_Employees ADD CONSTRAINT CK_L03_Employees_SalaryMax CHECK (Salary <= 80000);
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO
-- (04_Practice_Manage_Constraints.sql shows WITH NOCHECK, which skips the existing rows.)

-- 3g. Read the rules back
SELECT OBJECT_NAME(parent_object_id) AS TableName, name, definition
FROM sys.check_constraints
WHERE parent_object_id IN (OBJECT_ID('dbo.L03_Employees'), OBJECT_ID('dbo.L03_Departments'))
ORDER BY TableName, name;   -- 4 rows
GO


/* ============================================================
   4. DEFAULT
   ============================================================ */
-- DEFAULT = the value used when an INSERT does not mention the column.
-- A constant ('Active', 0) or a function (GETDATE(), SYSDATETIME(), NEWID(), SUSER_SNAME()).

-- 4a. Constant default. NOT NULL + DEFAULT on an existing table: existing rows receive the default.
ALTER TABLE dbo.L03_Employees ADD Status VARCHAR(20) NOT NULL
    CONSTRAINT DF_L03_Employees_Status DEFAULT ('Active');
GO
SELECT Status, COUNT(*) AS Cnt FROM dbo.L03_Employees GROUP BY Status;   -- Active 12
GO

-- 4b. Function defaults (evaluated at INSERT time, per row)
ALTER TABLE dbo.L03_Employees ADD
    CreatedAt DATETIME2(0)     NOT NULL CONSTRAINT DF_L03_Employees_CreatedAt DEFAULT (SYSDATETIME()),
    CreatedBy SYSNAME          NOT NULL CONSTRAINT DF_L03_Employees_CreatedBy DEFAULT (SUSER_SNAME()),
    RowGuid   UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_L03_Employees_RowGuid   DEFAULT (NEWID());
GO

-- 4c. INSERT without those columns -> the defaults fill them
INSERT INTO dbo.L03_Employees (EmployeeID, EmployeeName, Email, DepartmentID, Salary)
VALUES (204, 'Newbie', 'newbie@example.com', 1, 40000);
SELECT EmployeeID, Status, CreatedAt, CreatedBy, RowGuid FROM dbo.L03_Employees WHERE EmployeeID = 204;
GO

-- 4d. The keyword DEFAULT can be written explicitly in INSERT and UPDATE
INSERT INTO dbo.L03_Employees (EmployeeID, EmployeeName, Email, Salary, Status)
VALUES (205, 'Newbie 2', 'newbie2@example.com', 40000, DEFAULT);
UPDATE dbo.L03_Employees SET Status = 'Resigned' WHERE EmployeeID = 205;
UPDATE dbo.L03_Employees SET Status = DEFAULT    WHERE EmployeeID = 205;    -- back to Active
SELECT EmployeeID, Status FROM dbo.L03_Employees WHERE EmployeeID IN (204, 205);   -- Active, Active
GO

-- 4e. GOTCHA 1: an explicit NULL beats the default (a default only fills a MISSING column)
ALTER TABLE dbo.L03_Employees ADD Notes VARCHAR(50) NULL CONSTRAINT DF_L03_Employees_Notes DEFAULT ('none');
GO
INSERT INTO dbo.L03_Employees (EmployeeID, EmployeeName, Email, Salary, Notes)
VALUES (206, 'Newbie 3', 'newbie3@example.com', 40000, NULL);
INSERT INTO dbo.L03_Employees (EmployeeID, EmployeeName, Email, Salary)
VALUES (207, 'Newbie 4', 'newbie4@example.com', 40000);
SELECT EmployeeID, Notes FROM dbo.L03_Employees WHERE EmployeeID IN (206, 207);   -- 206 NULL, 207 none
GO

-- 4f. GOTCHA 2: adding a NULLable column with a default leaves the EXISTING rows NULL ...
SELECT COUNT(*) AS RowsWithNullNotes FROM dbo.L03_Employees WHERE Notes IS NULL;   -- 15 (14 old rows + 206)
-- ... unless you add WITH VALUES
ALTER TABLE dbo.L03_Employees DROP CONSTRAINT DF_L03_Employees_Notes;
ALTER TABLE dbo.L03_Employees DROP COLUMN Notes;
ALTER TABLE dbo.L03_Employees ADD Notes VARCHAR(50) NULL
    CONSTRAINT DF_L03_Employees_Notes DEFAULT ('none') WITH VALUES;
SELECT COUNT(*) AS RowsWithNullNotes FROM dbo.L03_Employees WHERE Notes IS NULL;   -- 0
GO

-- 4g. Where to see defaults
SELECT dc.name, c.name AS ColumnName, dc.definition
FROM sys.default_constraints dc
JOIN sys.columns c ON c.object_id = dc.parent_object_id AND c.column_id = dc.parent_column_id
WHERE dc.parent_object_id = OBJECT_ID('dbo.L03_Employees')
ORDER BY dc.name;   -- 5 rows
GO


/* ============================================================
   5. CLEANUP
   ============================================================ */
DROP TABLE IF EXISTS dbo.L03_Employees;
DROP TABLE IF EXISTS dbo.L03_Departments;
GO
/* DONE. Next: 03_Practice_Identity.sql */
