/* ============================================================
   LEVEL 01 - DATABASE BASICS  |  01_Practice.sql
   ------------------------------------------------------------
   Topics : CREATE/ALTER/DROP DATABASE, USE, GO,
            CREATE/DROP SCHEMA, CREATE/ALTER/DROP TABLE,
            catalog views (sys.*, INFORMATION_SCHEMA)

   HOW TO PRACTICE
     * Read the comment above each block, then run ONLY that block
       (select the lines -> F5). Predict the output first.
     * This level works in its OWN throwaway database (PracticeDB_L01)
       so nothing in SQLPractice is touched. The last block drops it.
     * The whole file can also be run top-to-bottom without errors.
   ============================================================ */


/* ============================================================
   1. LOOK AROUND THE SERVER
   ============================================================ */

-- Every database on this server. database_id 1-4 are the system databases.
SELECT database_id, name, create_date, state_desc, recovery_model_desc
FROM sys.databases
ORDER BY database_id;
GO

-- Which database am I in right now?   (also try: SELECT DB_NAME(1))
SELECT DB_NAME() AS CurrentDatabase, @@SERVERNAME AS ServerName, SUSER_SNAME() AS LoginName;
GO


/* ============================================================
   2. CREATE DATABASE
   ============================================================ */

USE master;
GO

-- Clean start (DROP DATABASE IF EXISTS works from SQL Server 2016)
IF DB_ID('PracticeDB_L01') IS NOT NULL
BEGIN
    ALTER DATABASE PracticeDB_L01 SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE PracticeDB_L01;
END
GO

-- Simplest form: SQL Server picks file names, sizes and locations from the "model" DB.
CREATE DATABASE PracticeDB_L01;
GO

/* Full form (for information only - do not run, paths differ per machine):
CREATE DATABASE PracticeDB_L01
ON PRIMARY ( NAME = PracticeDB_L01_Data, FILENAME = 'D:\SQLData\PracticeDB_L01.mdf', SIZE = 64MB, FILEGROWTH = 64MB )
LOG ON     ( NAME = PracticeDB_L01_Log,  FILENAME = 'D:\SQLLog\PracticeDB_L01.ldf',  SIZE = 32MB, FILEGROWTH = 32MB );
*/

-- Where did the files go?
SELECT name AS LogicalName, physical_name, type_desc, size * 8 / 1024 AS SizeMB
FROM sys.master_files
WHERE database_id = DB_ID('PracticeDB_L01');
GO


/* ============================================================
   3. USE  and  GO
   ============================================================ */

USE PracticeDB_L01;
GO
SELECT DB_NAME() AS NowInsideThisDatabase;
GO

-- GO ends a batch. A variable declared before GO does NOT exist after it.
DECLARE @msg VARCHAR(50) = 'I live in this batch only';
PRINT @msg;                      -- works
GO
-- PRINT @msg;                   -- would fail: "Must declare the scalar variable @msg"

-- GO 3  = run the batch 3 times (handy for generating test data)
PRINT 'Hello from batch';
GO 3


/* ============================================================
   4. ALTER DATABASE
   ============================================================ */

-- 4a. Make the database read-only, check, then back to read-write
ALTER DATABASE PracticeDB_L01 SET READ_ONLY;
GO
SELECT name, is_read_only FROM sys.databases WHERE name = 'PracticeDB_L01';
GO
ALTER DATABASE PracticeDB_L01 SET READ_WRITE;
GO

-- 4b. Rename a database
ALTER DATABASE PracticeDB_L01 MODIFY NAME = PracticeDB_L01_Renamed;
GO
SELECT name FROM sys.databases WHERE name LIKE 'PracticeDB_L01%';
GO
ALTER DATABASE PracticeDB_L01_Renamed MODIFY NAME = PracticeDB_L01;   -- rename back
GO

-- 4c. Change the recovery model (SIMPLE is fine for practice DBs - smaller log)
ALTER DATABASE PracticeDB_L01 SET RECOVERY SIMPLE;
GO
SELECT name, recovery_model_desc FROM sys.databases WHERE name = 'PracticeDB_L01';
GO


/* ============================================================
   5. SCHEMAS
   ============================================================ */

USE PracticeDB_L01;
GO

-- Built-in schemas: dbo (default), sys, INFORMATION_SCHEMA, guest ...
SELECT schema_id, name FROM sys.schemas ORDER BY schema_id;
GO

-- CREATE SCHEMA must be the ONLY statement in its batch -> GO before and after
CREATE SCHEMA Sales;
GO
CREATE SCHEMA HR;
GO

SELECT name FROM sys.schemas WHERE name IN ('Sales', 'HR');
GO

-- A schema can be dropped only when EMPTY
DROP SCHEMA HR;
GO


/* ============================================================
   6. CREATE TABLE
   ============================================================ */

-- 6a. Table in the default schema (dbo)
CREATE TABLE dbo.Employees
(
    EmployeeID INT           NOT NULL IDENTITY(1,1) PRIMARY KEY,   -- auto number 1,2,3...
    FirstName  NVARCHAR(50)  NOT NULL,
    LastName   NVARCHAR(50)  NOT NULL,
    HireDate   DATE          NOT NULL DEFAULT (GETDATE())
);
GO

-- 6b. Table in a custom schema.  Always write schema.table!
CREATE TABLE Sales.Customers
(
    CustomerID   INT          NOT NULL IDENTITY(100,1) PRIMARY KEY,   -- starts at 100
    CustomerName NVARCHAR(100) NOT NULL,
    Email        VARCHAR(100) NULL UNIQUE
);
GO

-- 6c. Look at what we created (3 different ways)
SELECT s.name AS SchemaName, t.name AS TableName
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id = t.schema_id;

SELECT TABLE_SCHEMA, TABLE_NAME, TABLE_TYPE
FROM INFORMATION_SCHEMA.TABLES;

EXEC sp_help 'Sales.Customers';        -- columns, identity, indexes, constraints
GO


/* ============================================================
   7. ALTER TABLE
   ============================================================ */

-- 7a. Add a column
ALTER TABLE dbo.Employees ADD Salary DECIMAL(10,2) NULL;
GO

-- 7b. Change a column's type / size (data must fit in the new type)
ALTER TABLE dbo.Employees ALTER COLUMN FirstName NVARCHAR(100) NOT NULL;
GO

-- 7c. Rename a column (sp_rename, NOT ALTER TABLE)
EXEC sp_rename 'dbo.Employees.LastName', 'Surname', 'COLUMN';
GO

-- 7d. Drop a column
ALTER TABLE dbo.Employees DROP COLUMN Salary;
GO

-- 7e. Trying to drop a column that has a DEFAULT constraint -> error (constraint first!)
BEGIN TRY
    ALTER TABLE dbo.Employees DROP COLUMN HireDate;
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO

-- Fix: find the auto-named default constraint, drop it, then drop the column
DECLARE @sql NVARCHAR(200);
SELECT @sql = 'ALTER TABLE dbo.Employees DROP CONSTRAINT ' + dc.name
FROM sys.default_constraints dc
JOIN sys.columns c ON c.object_id = dc.parent_object_id AND c.column_id = dc.parent_column_id
WHERE dc.parent_object_id = OBJECT_ID('dbo.Employees') AND c.name = 'HireDate';
EXEC (@sql);
ALTER TABLE dbo.Employees DROP COLUMN HireDate;
GO
-- Lesson: NAME your constraints (CONSTRAINT DF_Employees_HireDate DEFAULT ...) so this is easy.

-- Final structure
SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'Employees'
ORDER BY ORDINAL_POSITION;
GO


/* ============================================================
   8. DROP TABLE / DROP SCHEMA
   ============================================================ */

-- Dropping a NON-empty schema fails
BEGIN TRY
    DROP SCHEMA Sales;
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO

DROP TABLE IF EXISTS Sales.Customers;   -- IF EXISTS: no error when it is already gone
DROP TABLE IF EXISTS dbo.Employees;
GO
DROP SCHEMA Sales;                      -- now it is empty -> OK
GO


/* ============================================================
   9. DROP DATABASE  (must leave the database first!)
   ============================================================ */

-- Being inside the database you drop -> error
BEGIN TRY
    DROP DATABASE PracticeDB_L01;
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO

USE master;
GO
DROP DATABASE IF EXISTS PracticeDB_L01;
GO

SELECT name FROM sys.databases WHERE name = 'PracticeDB_L01';   -- 0 rows = gone
GO

/* ------------------------------------------------------------
   DONE. Next: Exercises.sql
   ------------------------------------------------------------ */
