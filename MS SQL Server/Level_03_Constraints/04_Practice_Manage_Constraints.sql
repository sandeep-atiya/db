/* ============================================================
   LEVEL 03 - CONSTRAINTS  |  04_Practice_Manage_Constraints.sql
   ------------------------------------------------------------
   Topics : naming conventions (PK_/FK_/UQ_/CK_/DF_), ALTER TABLE
            ADD / DROP CONSTRAINT, WITH NOCHECK, NOCHECK / CHECK
            CONSTRAINT (disable / enable), trusted vs untrusted,
            finding constraints (sys.key_constraints, sys.foreign_keys,
            sys.check_constraints, sys.default_constraints,
            INFORMATION_SCHEMA.TABLE_CONSTRAINTS), and the REAL
            constraints of the 6 SQLPractice tables (read-only).

   HOW TO PRACTICE: run block by block, predict the output first.
   Works on fresh copies dbo.L03_Departments / dbo.L03_Employees.
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
   1. NAMING CONVENTIONS
   ============================================================ */
-- Unnamed constraints get random names such as PK__L03_Unna__3214EC07A1B2C3D4.
-- You need the NAME to drop / disable / enable a constraint, so always name them:
--     PK_Table            FK_ChildTable_ParentTable     UQ_Table_Column
--     CK_Table_Column     DF_Table_Column

-- 1a. Unnamed: look at what SQL Server invents
CREATE TABLE dbo.L03_Unnamed
(
    Id     INT         PRIMARY KEY,
    Code   VARCHAR(10) UNIQUE,
    Qty    INT         CHECK (Qty >= 0),
    Status VARCHAR(10) DEFAULT ('New')
);
GO
SELECT name, type_desc
FROM sys.objects
WHERE parent_object_id = OBJECT_ID('dbo.L03_Unnamed') AND type IN ('PK', 'UQ', 'C', 'D')
ORDER BY type_desc;   -- 4 rows, names end in random hex
GO

-- 1b. Named: every name tells you the table and the purpose
SELECT name, type_desc
FROM sys.objects
WHERE parent_object_id = OBJECT_ID('dbo.L03_Employees') AND type IN ('PK', 'UQ', 'C', 'F', 'D')
ORDER BY type_desc, name;   -- 5 rows: CK_, FK_ x2, PK_, UQ_
GO
DROP TABLE dbo.L03_Unnamed;
GO


/* ============================================================
   2. ADD / DROP CONSTRAINTS WITH ALTER TABLE
   ============================================================ */
-- Start from a bare table and add each constraint type afterwards.
CREATE TABLE dbo.L03_Assets
(
    AssetID    INT           NOT NULL,
    AssetTag   VARCHAR(20)   NULL,
    AssetName  VARCHAR(100)  NOT NULL,
    EmployeeID INT           NULL,
    Cost       DECIMAL(10,2) NULL,
    Status     VARCHAR(10)   NULL
);
GO

-- 2a. PRIMARY KEY
ALTER TABLE dbo.L03_Assets ADD CONSTRAINT PK_L03_Assets PRIMARY KEY (AssetID);
-- 2b. UNIQUE
ALTER TABLE dbo.L03_Assets ADD CONSTRAINT UQ_L03_Assets_Tag UNIQUE (AssetTag);
-- 2c. FOREIGN KEY
ALTER TABLE dbo.L03_Assets ADD CONSTRAINT FK_L03_Assets_Employees
    FOREIGN KEY (EmployeeID) REFERENCES dbo.L03_Employees (EmployeeID);
-- 2d. CHECK
ALTER TABLE dbo.L03_Assets ADD CONSTRAINT CK_L03_Assets_Cost CHECK (Cost >= 0);
-- 2e. DEFAULT  (note "FOR column": DEFAULT is the only constraint written this way)
ALTER TABLE dbo.L03_Assets ADD CONSTRAINT DF_L03_Assets_Status DEFAULT ('InUse') FOR Status;
-- 2f. Several at once
ALTER TABLE dbo.L03_Assets ADD
    CONSTRAINT CK_L03_Assets_Status CHECK (Status IN ('InUse', 'Spare', 'Scrapped')),
    CONSTRAINT DF_L03_Assets_Cost   DEFAULT (0) FOR Cost;
GO
SELECT name, type_desc
FROM sys.objects
WHERE parent_object_id = OBJECT_ID('dbo.L03_Assets') AND type IN ('PK', 'UQ', 'C', 'F', 'D')
ORDER BY name;   -- 7 rows
GO
INSERT INTO dbo.L03_Assets (AssetID, AssetTag, AssetName, EmployeeID)
VALUES (1, 'LT-001', 'Laptop', 101), (2, 'LT-002', 'Laptop', 102);
SELECT * FROM dbo.L03_Assets;   -- Cost 0.00, Status InUse (defaults)
GO

-- 2g. DROP CONSTRAINT: the same statement for every kind - you only need the NAME
ALTER TABLE dbo.L03_Assets DROP CONSTRAINT UQ_L03_Assets_Tag;
ALTER TABLE dbo.L03_Assets DROP CONSTRAINT DF_L03_Assets_Cost, CK_L03_Assets_Cost;   -- several at once
GO

-- 2h. There is no "ALTER CONSTRAINT". To change a rule: DROP it and ADD it again.
ALTER TABLE dbo.L03_Assets DROP CONSTRAINT CK_L03_Assets_Status;
ALTER TABLE dbo.L03_Assets ADD  CONSTRAINT CK_L03_Assets_Status CHECK (Status IN ('InUse', 'Spare', 'Scrapped', 'Lost'));
GO

-- 2i. A PK / UNIQUE that an FK points to cannot be dropped
--     (real message, Msg 3725: "The constraint 'PK_L03_Employees' is being referenced by table 'L03_Assets' ...")
BEGIN TRY
    EXEC ('ALTER TABLE dbo.L03_Employees DROP CONSTRAINT PK_L03_Employees;');
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO

-- 2j. A column that still has a constraint cannot be dropped (drop DF_ / CK_ first)
BEGIN TRY
    ALTER TABLE dbo.L03_Assets DROP COLUMN Status;
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO


/* ============================================================
   3. WITH NOCHECK, NOCHECK / CHECK CONSTRAINT  (disable and enable)
   ============================================================ */
-- Only FOREIGN KEY and CHECK constraints can be disabled. PK / UNIQUE are indexes - never.
-- "trusted" = SQL Server has verified EVERY row against the rule. Untrusted rules still block
-- new bad rows, but the optimizer cannot rely on them (Level 18).

-- 3a. WITH NOCHECK: add a rule WITHOUT validating existing rows (Rahul 85000 and Sneha 90000 break it)
ALTER TABLE dbo.L03_Employees WITH NOCHECK
    ADD CONSTRAINT CK_L03_Employees_SalaryMax CHECK (Salary <= 80000);
GO
SELECT name, is_not_trusted, is_disabled
FROM sys.check_constraints
WHERE parent_object_id = OBJECT_ID('dbo.L03_Employees');   -- SalaryMax: is_not_trusted = 1
GO
-- New rows ARE checked from now on (test rows get their own Email: the UNIQUE allows only one NULL)
BEGIN TRY
    INSERT INTO dbo.L03_Employees (EmployeeID, EmployeeName, Email, Salary)
    VALUES (201, 'Rich', 'rich@example.com', 95000);
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO

-- 3b. Disable an FK (typical before a bulk load), then insert a row that breaks it
ALTER TABLE dbo.L03_Employees NOCHECK CONSTRAINT FK_L03_Employees_Departments;
INSERT INTO dbo.L03_Employees (EmployeeID, EmployeeName, Email, DepartmentID, Salary)
VALUES (202, 'Orphan', 'orphan@example.com', 99, 50000);           -- accepted! department 99 does not exist
SELECT name, is_disabled, is_not_trusted
FROM sys.foreign_keys WHERE name = 'FK_L03_Employees_Departments';   -- 1, 1
GO

-- 3c. CHECK CONSTRAINT (without WITH CHECK) re-enables but does NOT look at existing rows -> still untrusted
ALTER TABLE dbo.L03_Employees CHECK CONSTRAINT FK_L03_Employees_Departments;
SELECT name, is_disabled, is_not_trusted
FROM sys.foreign_keys WHERE name = 'FK_L03_Employees_Departments';   -- 0, 1
GO

-- 3d. WITH CHECK CHECK CONSTRAINT = re-enable AND validate every row -> fails while the orphan exists
BEGIN TRY
    ALTER TABLE dbo.L03_Employees WITH CHECK CHECK CONSTRAINT FK_L03_Employees_Departments;
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO
DELETE FROM dbo.L03_Employees WHERE EmployeeID = 202;                             -- remove the bad row
ALTER TABLE dbo.L03_Employees WITH CHECK CHECK CONSTRAINT FK_L03_Employees_Departments;   -- trusted again
SELECT name, is_disabled, is_not_trusted
FROM sys.foreign_keys WHERE name = 'FK_L03_Employees_Departments';   -- 0, 0
GO

-- 3e. ALL at once (the usual pattern around a big data load)
ALTER TABLE dbo.L03_Employees NOCHECK CONSTRAINT ALL;         -- disables every FK and CHECK on the table
SELECT name, is_disabled FROM sys.foreign_keys
WHERE parent_object_id = OBJECT_ID('dbo.L03_Employees');      -- both 1
GO
BEGIN TRY
    ALTER TABLE dbo.L03_Employees WITH CHECK CHECK CONSTRAINT ALL;   -- SalaryMax still has 2 violators -> fails
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO
ALTER TABLE dbo.L03_Employees DROP CONSTRAINT CK_L03_Employees_SalaryMax;
ALTER TABLE dbo.L03_Employees WITH CHECK CHECK CONSTRAINT ALL;       -- OK: everything enabled AND trusted
SELECT name, is_disabled, is_not_trusted FROM sys.foreign_keys
WHERE parent_object_id = OBJECT_ID('dbo.L03_Employees');      -- 0, 0 for both
GO


/* ============================================================
   4. FINDING CONSTRAINTS (catalog views)
   ============================================================ */
-- 4a. PK + UNIQUE -> sys.key_constraints
SELECT OBJECT_NAME(parent_object_id) AS TableName, name, type_desc, unique_index_id
FROM sys.key_constraints
WHERE OBJECT_NAME(parent_object_id) LIKE 'L03[_]%'
ORDER BY TableName, type_desc;   -- 5 rows
GO

-- 4b. FOREIGN KEY -> sys.foreign_keys (+ sys.foreign_key_columns for the column names)
SELECT fk.name,
       OBJECT_NAME(fk.parent_object_id)     AS ChildTable,  cp.name AS ChildColumn,
       OBJECT_NAME(fk.referenced_object_id) AS ParentTable, cr.name AS ParentColumn,
       fk.delete_referential_action_desc, fk.update_referential_action_desc, fk.is_disabled, fk.is_not_trusted
FROM sys.foreign_keys fk
JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
JOIN sys.columns cp ON cp.object_id = fkc.parent_object_id     AND cp.column_id = fkc.parent_column_id
JOIN sys.columns cr ON cr.object_id = fkc.referenced_object_id AND cr.column_id = fkc.referenced_column_id
WHERE OBJECT_NAME(fk.parent_object_id) LIKE 'L03[_]%'
ORDER BY fk.name;   -- 3 rows
GO

-- 4c. CHECK -> sys.check_constraints (definition = the rule text)
SELECT OBJECT_NAME(parent_object_id) AS TableName, name, definition, is_disabled, is_not_trusted
FROM sys.check_constraints
WHERE OBJECT_NAME(parent_object_id) LIKE 'L03[_]%'
ORDER BY TableName, name;   -- 2 rows
GO

-- 4d. DEFAULT -> sys.default_constraints (join sys.columns to see WHICH column)
SELECT OBJECT_NAME(dc.parent_object_id) AS TableName, dc.name, c.name AS ColumnName, dc.definition
FROM sys.default_constraints dc
JOIN sys.columns c ON c.object_id = dc.parent_object_id AND c.column_id = dc.parent_column_id
WHERE OBJECT_NAME(dc.parent_object_id) LIKE 'L03[_]%';   -- 1 row: DF_L03_Assets_Status
GO

-- 4e. ANSI view: PK / UNIQUE / FK / CHECK in one list (DEFAULTs are NOT constraints in the ANSI sense)
SELECT TABLE_NAME, CONSTRAINT_NAME, CONSTRAINT_TYPE
FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS
WHERE TABLE_NAME LIKE 'L03[_]%'
ORDER BY TABLE_NAME, CONSTRAINT_TYPE, CONSTRAINT_NAME;   -- 10 rows
GO

-- 4f. Quick look for one table
EXEC sp_helpconstraint 'dbo.L03_Employees';
GO


/* ============================================================
   5. THE REAL CONSTRAINTS OF THE 6 BASE TABLES  (read-only)
   ============================================================ */
-- 5a. Everything, one row per constraint
SELECT OBJECT_NAME(o.parent_object_id) AS TableName, o.name AS ConstraintName, o.type_desc
FROM sys.objects o
WHERE o.type IN ('PK', 'UQ', 'F', 'C', 'D')
  AND o.parent_object_id IN (OBJECT_ID('dbo.Departments'), OBJECT_ID('dbo.Employees'),
                             OBJECT_ID('dbo.Customers'),   OBJECT_ID('dbo.Products'),
                             OBJECT_ID('dbo.Orders'),      OBJECT_ID('dbo.OrderDetails'))
ORDER BY TableName, o.type_desc, o.name;
-- expect 20 rows: 6 PK, 2 UNIQUE, 6 FK, 5 CHECK, 1 DEFAULT
GO

-- 5b. The FK map of SQLPractice: 6 foreign keys, all NO_ACTION (nothing cascades in this dataset)
SELECT fk.name, OBJECT_NAME(fk.parent_object_id) AS ChildTable,
       OBJECT_NAME(fk.referenced_object_id) AS ParentTable, fk.delete_referential_action_desc
FROM sys.foreign_keys fk
WHERE fk.parent_object_id IN (OBJECT_ID('dbo.Employees'), OBJECT_ID('dbo.Orders'), OBJECT_ID('dbo.OrderDetails'))
ORDER BY ChildTable, fk.name;
GO

-- 5c. The 5 CHECK rules
SELECT OBJECT_NAME(parent_object_id) AS TableName, name, definition
FROM sys.check_constraints
WHERE parent_object_id IN (OBJECT_ID('dbo.Employees'), OBJECT_ID('dbo.Products'),
                           OBJECT_ID('dbo.Orders'), OBJECT_ID('dbo.OrderDetails'))
ORDER BY TableName, name;
GO

-- 5d. The only DEFAULT (Orders.Status) and the only IDENTITY (OrderDetails.OrderDetailID)
SELECT OBJECT_NAME(parent_object_id) AS TableName, name, definition
FROM sys.default_constraints
WHERE parent_object_id = OBJECT_ID('dbo.Orders');
SELECT OBJECT_NAME(object_id) AS TableName, name, seed_value, increment_value, last_value
FROM sys.identity_columns
WHERE object_id = OBJECT_ID('dbo.OrderDetails');
-- seed 1, increment 1; last_value = the highest OrderDetailID handed out so far (26 after 00_Reset_All)
GO


/* ============================================================
   6. CLEANUP
   ============================================================ */
DROP TABLE IF EXISTS dbo.L03_Assets;
DROP TABLE IF EXISTS dbo.L03_Unnamed;
DROP TABLE IF EXISTS dbo.L03_Employees;
DROP TABLE IF EXISTS dbo.L03_Departments;
GO
/* DONE. Next: Exercises.sql */
