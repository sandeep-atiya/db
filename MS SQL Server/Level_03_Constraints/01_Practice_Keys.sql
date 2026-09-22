/* ============================================================
   LEVEL 03 - CONSTRAINTS  |  01_Practice_Keys.sql
   ------------------------------------------------------------
   Topics : PRIMARY KEY (single, composite, clustered by default),
            FOREIGN KEY (NO ACTION / CASCADE / SET NULL / SET DEFAULT,
            self-referencing FK)

   HOW TO PRACTICE: run block by block, predict the output first.
   Every demo works on COPIES of the base tables
   (dbo.L03_Departments, dbo.L03_Employees, ...). The 6 real
   tables are only READ. The last block drops every copy.
   Next: 02_Practice_Rules.sql
   ============================================================ */

USE SQLPractice;
GO

/* ---------- Clean start (drops every L03 object of this level, children first) ---------- */
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


/* ============================================================
   1. PRIMARY KEY
   ============================================================ */
-- PRIMARY KEY = "this column (or set of columns) identifies exactly one row".
-- Rules: values unique, never NULL, only ONE PK per table.
-- Side effect: by default the PK creates the CLUSTERED index (= physical order of the rows).

-- 1a. Same shape as dbo.Departments, rows copied from the real table
CREATE TABLE dbo.L03_Departments
(
    DepartmentID   INT          NOT NULL,
    DepartmentName VARCHAR(100) NOT NULL,
    Location       VARCHAR(100) NULL,
    CONSTRAINT PK_L03_Departments      PRIMARY KEY (DepartmentID),
    CONSTRAINT UQ_L03_Departments_Name UNIQUE (DepartmentName)
);
INSERT INTO dbo.L03_Departments (DepartmentID, DepartmentName, Location)
SELECT DepartmentID, DepartmentName, Location FROM dbo.Departments;
SELECT * FROM dbo.L03_Departments;          -- 6 rows: IT, Sales, HR, Finance, Marketing, Legal
GO

-- 1b. Duplicate key -> error 2627 "Violation of PRIMARY KEY constraint"
BEGIN TRY
    INSERT INTO dbo.L03_Departments (DepartmentID, DepartmentName, Location)
    VALUES (1, 'Support', 'Delhi');         -- DepartmentID 1 is already IT
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO

-- 1c. A PK column can never be NULL (SQL Server forces NOT NULL on it)
BEGIN TRY
    INSERT INTO dbo.L03_Departments (DepartmentID, DepartmentName) VALUES (NULL, 'Support');
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO

-- 1d. Only ONE primary key per table (use UNIQUE for the others)
--     NOTE: some DDL refusals are raised at COMPILE time, which TRY/CATCH only catches one level
--     down. Running the statement through EXEC('...') puts it one level down so CATCH sees it.
--     ERROR_MESSAGE() then shows the LAST message ("See previous errors"); the real one (Msg 1779)
--     is "Table 'L03_Departments' already has a primary key defined on it."
BEGIN TRY
    EXEC ('ALTER TABLE dbo.L03_Departments ADD CONSTRAINT PK_L03_Departments_2 PRIMARY KEY (DepartmentName);');
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO

-- 1e. Adding a PK later on a NULLable column is refused
--     (real message, Msg 8111: "Cannot define PRIMARY KEY constraint on nullable column")
CREATE TABLE dbo.L03_NullablePK (Id INT NULL, Note VARCHAR(20) NULL);
GO
BEGIN TRY
    EXEC ('ALTER TABLE dbo.L03_NullablePK ADD CONSTRAINT PK_L03_NullablePK PRIMARY KEY (Id);');
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO
-- Fix: make the column NOT NULL first, then add the PK (in a NEW batch - the ADD is checked at compile time)
ALTER TABLE dbo.L03_NullablePK ALTER COLUMN Id INT NOT NULL;
GO
ALTER TABLE dbo.L03_NullablePK ADD CONSTRAINT PK_L03_NullablePK PRIMARY KEY (Id);
GO

-- 1f. PK = CLUSTERED index by default, UNIQUE = NONCLUSTERED index by default
SELECT i.name AS IndexName, i.type_desc, i.is_primary_key, i.is_unique_constraint
FROM sys.indexes i
WHERE i.object_id = OBJECT_ID('dbo.L03_Departments');
-- expect 2 rows: PK_L03_Departments CLUSTERED / UQ_L03_Departments_Name NONCLUSTERED
GO

-- 1g. You may ask for a NONCLUSTERED PK (when another column deserves the clustered index, Level 17)
CREATE TABLE dbo.L03_Projects
(
    ProjectID   INT          NOT NULL CONSTRAINT PK_L03_Projects PRIMARY KEY NONCLUSTERED,
    ProjectName VARCHAR(100) NOT NULL
);
INSERT INTO dbo.L03_Projects (ProjectID, ProjectName)
VALUES (1, 'Website'), (2, 'Mobile App'), (3, 'Data Warehouse');
SELECT name, type_desc FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.L03_Projects');
-- expect 2 rows: (NULL) HEAP  +  PK_L03_Projects NONCLUSTERED   -> the table itself is a heap
GO

-- 1h. COMPOSITE PK: the COMBINATION must be unique; each column alone may repeat
CREATE TABLE dbo.L03_ProjectAssignments
(
    EmployeeID INT         NOT NULL,
    ProjectID  INT         NOT NULL,
    Role       VARCHAR(30) NULL,
    CONSTRAINT PK_L03_ProjectAssignments PRIMARY KEY (EmployeeID, ProjectID),
    CONSTRAINT FK_L03_ProjectAssignments_Projects FOREIGN KEY (ProjectID)
        REFERENCES dbo.L03_Projects (ProjectID)
);
INSERT INTO dbo.L03_ProjectAssignments (EmployeeID, ProjectID, Role) VALUES
(101, 1, 'Lead'), (101, 2, 'Reviewer'), (102, 1, 'Developer');   -- 101 twice, project 1 twice: fine
SELECT * FROM dbo.L03_ProjectAssignments;   -- 3 rows
GO
BEGIN TRY
    INSERT INTO dbo.L03_ProjectAssignments (EmployeeID, ProjectID, Role) VALUES (101, 1, 'Tester');  -- same PAIR
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO


/* ============================================================
   2. FOREIGN KEY
   ============================================================ */
-- FOREIGN KEY = "the value in this column must exist in the parent's PK / UNIQUE column".
-- It protects both directions: no orphan child rows, and no deleting a parent that is in use.

-- 2a. Same shape as dbo.Employees: FK to L03_Departments + self-referencing FK on ManagerID
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
INSERT INTO dbo.L03_Employees (EmployeeID, EmployeeName, Email, DepartmentID, Salary, HireDate, ManagerID)
SELECT EmployeeID, EmployeeName, Email, DepartmentID, Salary, HireDate, ManagerID FROM dbo.Employees;
SELECT COUNT(*) AS EmployeeCount FROM dbo.L03_Employees;   -- 12
GO

-- 2b. Child pointing at a parent that does not exist -> error 547
--     (every test row below gets its own Email: the UNIQUE constraint allows only one NULL, see file 02)
BEGIN TRY
    INSERT INTO dbo.L03_Employees (EmployeeID, EmployeeName, Email, DepartmentID, Salary)
    VALUES (201, 'Test', 'test@example.com', 99, 50000);        -- there is no department 99
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO

-- 2c. NULL in an FK column is allowed: the FK only checks non-NULL values (Anjali = contractor)
SELECT EmployeeID, EmployeeName, DepartmentID
FROM dbo.L03_Employees WHERE DepartmentID IS NULL;   -- 1 row: 110 Anjali
GO

-- 2d. Default action = NO ACTION: a parent that is in use cannot be deleted or re-keyed
BEGIN TRY
    DELETE FROM dbo.L03_Departments WHERE DepartmentID = 1;   -- IT has 3 employees
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO
BEGIN TRY
    UPDATE dbo.L03_Departments SET DepartmentID = 10 WHERE DepartmentID = 1;
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO
-- A parent WITHOUT children can go: Legal (6) has no employees
DELETE FROM dbo.L03_Departments WHERE DepartmentID = 6;
SELECT COUNT(*) AS DepartmentCount FROM dbo.L03_Departments;   -- 5
INSERT INTO dbo.L03_Departments (DepartmentID, DepartmentName, Location) VALUES (6, 'Legal', 'Delhi');  -- put it back
GO

-- 2e. SELF-REFERENCING FK: ManagerID -> EmployeeID of the SAME table
BEGIN TRY
    INSERT INTO dbo.L03_Employees (EmployeeID, EmployeeName, Email, Salary, ManagerID)
    VALUES (202, 'Ghost', 'ghost@example.com', 40000, 999);      -- manager 999 does not exist
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO
-- A manager who still has reports cannot be deleted (Rahul 101 manages Amit 102 and Pooja 108)
BEGIN TRY
    DELETE FROM dbo.L03_Employees WHERE EmployeeID = 101;
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO
-- A self-referencing FK can NOT use CASCADE: SQL Server refuses
-- (real message, Msg 1785: "Introducing FOREIGN KEY constraint ... may cause cycles or multiple cascade paths")
ALTER TABLE dbo.L03_Employees DROP CONSTRAINT FK_L03_Employees_Manager;
GO
BEGIN TRY
    EXEC ('ALTER TABLE dbo.L03_Employees ADD CONSTRAINT FK_L03_Employees_Manager
           FOREIGN KEY (ManagerID) REFERENCES dbo.L03_Employees (EmployeeID) ON DELETE CASCADE;');
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO
ALTER TABLE dbo.L03_Employees ADD CONSTRAINT FK_L03_Employees_Manager       -- plain version back
    FOREIGN KEY (ManagerID) REFERENCES dbo.L03_Employees (EmployeeID);
GO

-- 2f. REFERENTIAL ACTIONS: what happens to the CHILD when the PARENT row is deleted / re-keyed.
--     One child table (assets given to employees); the FK is re-created with a different action each time.
CREATE TABLE dbo.L03_Assets
(
    AssetID    INT          NOT NULL CONSTRAINT PK_L03_Assets PRIMARY KEY,
    AssetName  VARCHAR(100) NOT NULL,
    EmployeeID INT          NULL CONSTRAINT DF_L03_Assets_EmployeeID DEFAULT (101),   -- needed for SET DEFAULT
    CONSTRAINT FK_L03_Assets_Employees FOREIGN KEY (EmployeeID)
        REFERENCES dbo.L03_Employees (EmployeeID)          -- no clause = ON DELETE NO ACTION ON UPDATE NO ACTION
);
INSERT INTO dbo.L03_Assets (AssetID, AssetName, EmployeeID) VALUES
(1, 'Laptop',  112),    -- Meera
(2, 'Phone',   112),    -- Meera
(3, 'Laptop',  111),    -- Deepak
(4, 'Monitor', 109);    -- Vikram
GO

-- NO ACTION (the default): delete is blocked while a child exists
BEGIN TRY
    DELETE FROM dbo.L03_Employees WHERE EmployeeID = 112;
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO

-- ON DELETE CASCADE / ON UPDATE CASCADE: the change flows down into the child rows
ALTER TABLE dbo.L03_Assets DROP CONSTRAINT FK_L03_Assets_Employees;
ALTER TABLE dbo.L03_Assets ADD CONSTRAINT FK_L03_Assets_Employees FOREIGN KEY (EmployeeID)
    REFERENCES dbo.L03_Employees (EmployeeID) ON DELETE CASCADE ON UPDATE CASCADE;
GO
DELETE FROM dbo.L03_Employees WHERE EmployeeID = 112;         -- Meera gone ...
SELECT * FROM dbo.L03_Assets;                                  -- ... and her 2 assets gone: 2 rows left (3, 4)
UPDATE dbo.L03_Employees SET EmployeeID = 211 WHERE EmployeeID = 111;   -- Deepak renumbered
SELECT AssetID, EmployeeID FROM dbo.L03_Assets WHERE AssetID = 3;       -- EmployeeID followed: 211
UPDATE dbo.L03_Employees SET EmployeeID = 111 WHERE EmployeeID = 211;   -- and back
GO

-- ON DELETE SET NULL: child row stays, its FK column becomes NULL (column must be nullable)
ALTER TABLE dbo.L03_Assets DROP CONSTRAINT FK_L03_Assets_Employees;
ALTER TABLE dbo.L03_Assets ADD CONSTRAINT FK_L03_Assets_Employees FOREIGN KEY (EmployeeID)
    REFERENCES dbo.L03_Employees (EmployeeID) ON DELETE SET NULL;
GO
DELETE FROM dbo.L03_Employees WHERE EmployeeID = 111;         -- Deepak
SELECT * FROM dbo.L03_Assets;                                  -- asset 3: EmployeeID NULL, asset 4: 109
GO

-- ON DELETE SET DEFAULT: FK column gets its DEFAULT (101 = Rahul). The default MUST exist in the parent.
ALTER TABLE dbo.L03_Assets DROP CONSTRAINT FK_L03_Assets_Employees;
ALTER TABLE dbo.L03_Assets ADD CONSTRAINT FK_L03_Assets_Employees FOREIGN KEY (EmployeeID)
    REFERENCES dbo.L03_Employees (EmployeeID) ON DELETE SET DEFAULT;
GO
DELETE FROM dbo.L03_Employees WHERE EmployeeID = 109;         -- Vikram
SELECT * FROM dbo.L03_Assets;                                  -- asset 4: EmployeeID 101
SELECT COUNT(*) AS EmployeesLeft FROM dbo.L03_Employees;      -- 9
GO

-- Which action is set? sys.foreign_keys tells you.
SELECT name, delete_referential_action_desc, update_referential_action_desc
FROM sys.foreign_keys
WHERE parent_object_id = OBJECT_ID('dbo.L03_Assets');         -- SET_DEFAULT / NO_ACTION
GO

-- 2g. An FK may only point at a PRIMARY KEY or UNIQUE column of the parent (same data type)
--     (real message, Msg 1776: "There are no primary or candidate keys in the referenced table ...")
BEGIN TRY
    EXEC ('ALTER TABLE dbo.L03_Assets ADD CONSTRAINT FK_L03_Assets_BadTarget
           FOREIGN KEY (AssetName) REFERENCES dbo.L03_Employees (EmployeeName);');   -- EmployeeName is not a key
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO


/* ============================================================
   3. CLEANUP
   ============================================================ */
DROP TABLE IF EXISTS dbo.L03_ProjectAssignments;
DROP TABLE IF EXISTS dbo.L03_Projects;
DROP TABLE IF EXISTS dbo.L03_Assets;
DROP TABLE IF EXISTS dbo.L03_Employees;
DROP TABLE IF EXISTS dbo.L03_Departments;
DROP TABLE IF EXISTS dbo.L03_NullablePK;
GO
/* DONE. Next: 02_Practice_Rules.sql */
