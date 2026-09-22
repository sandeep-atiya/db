/* ============================================================
   00_SETUP  |  01_Create_Database.sql
   ------------------------------------------------------------
   Creates the practice database "SQLPractice".
   Safe to re-run: if the database already exists it is dropped
   and created again (all practice data is rebuilt by 03_*.sql).

   HOW TO RUN (SSMS): open file -> press F5 (runs whole file)
   HOW TO RUN (sqlcmd): sqlcmd -S localhost -E -C -i "01_Create_Database.sql"
   ============================================================ */

USE master;
GO

-- 1) If the database exists, kick everyone out and drop it.
--    SINGLE_USER + ROLLBACK IMMEDIATE closes open connections so DROP cannot be blocked.
IF DB_ID('SQLPractice') IS NOT NULL
BEGIN
    ALTER DATABASE SQLPractice SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE SQLPractice;
    PRINT 'Old SQLPractice database dropped.';
END
GO

-- 2) Create a fresh database (default file locations & settings).
CREATE DATABASE SQLPractice;
GO

-- 3) Switch context. Every practice script starts with this line.
USE SQLPractice;
GO

-- 4) Verify
SELECT DB_NAME()   AS CurrentDatabase,
       @@VERSION   AS SqlServerVersion;
GO
