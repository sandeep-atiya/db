/* ============================================================
   LEVEL 20 - ADVANCED AND ADMIN  |  Exercises.sql
   ------------------------------------------------------------
   Try each question in the "YOUR ANSWERS" area FIRST, then compare
   with SOLUTIONS. Everything runs on SQLPractice; helper objects are
   prefixed L20x_ and removed in CLEANUP (including the login and the
   backup file of Q12).
   ============================================================ */

USE SQLPractice;
GO
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

/* ------------------------------------------------------------
   QUESTIONS
   ------------------------------------------------------------
   Q1.  Write dbo.usp_L20x_TopN (@Table SYSNAME, @N INT) that returns the first @N rows of any
        table safely (no injection possible). Run it for 'dbo.Products', 3.
   Q2.  An app sends the employee list '101,103,106'. Return EmployeeName and Salary of exactly
        those employees without dynamic SQL.
   Q3.  PIVOT: one row per DepartmentName, one column per hire year 2020..2024 with the number
        of employees hired that year (employees without a department are excluded).
   Q4.  Copy dbo.Products to dbo.L20x_Products. Create an AFTER UPDATE trigger that writes
        ProductID, OldPrice, NewPrice into dbo.L20x_PriceLog only when Price changed.
        Update two products in ONE statement and show the log (2 rows).
   Q5.  DDL trigger: log every CREATE TABLE in this database into dbo.L20x_DdlLog
        (EventType, ObjectName, LoginName, At). Create a table, show the log row, drop the trigger.
   Q6.  Cursor: PRINT one line per department "IT: 3 employees". Then write the same as ONE query.
   Q7.  Create a sequence dbo.seq_L20x starting at 1 and use it as the DEFAULT of two tables
        (L20x_Tickets, L20x_Refunds). Insert 2 tickets, 1 refund, 1 ticket; show all numbers in order.
   Q8.  Return employee 101 as one JSON object with a nested department object:
        {"id":101,"name":"Rahul","department":{"id":1,"name":"IT"}}
   Q9.  The app posts '[{"id":101,"bonus":5000},{"id":106,"bonus":8000}]'. Return EmployeeName,
        Salary and the bonus for those employees using OPENJSON.
   Q10. XML: (a) one row per Category with a comma-separated, alphabetical product list, using the
        FOR XML PATH('') + STUFF trick; (b) shred
        '<products><product id="1" name="Laptop"/><product id="2" name="Mouse"/></products>' into rows.
   Q11. Security: create login L20x_Login, user L20x_User and role L20x_Readers that may SELECT
        only dbo.Departments. Prove with EXECUTE AS that Departments works and Employees is denied.
   Q12. Take a COPY_ONLY full backup of this database (with CHECKSUM) into the default backup
        folder, verify it, show it in msdb history, then delete the file and the history row.
   Q13. (Theory, write as comments) Which recovery model for: a reporting DB reloaded every night;
        a banking OLTP DB; a DB during a bulk load window? What is the weekly maintenance order?
   ------------------------------------------------------------ */

-- YOUR ANSWERS HERE (write below, run, compare)










/* ============================================================
   SOLUTIONS
   ============================================================ */

-- Q1
CREATE OR ALTER PROCEDURE dbo.usp_L20x_TopN @Table SYSNAME, @N INT
AS
BEGIN
    SET NOCOUNT ON;
    IF OBJECT_ID(@Table, 'U') IS NULL BEGIN RAISERROR ('Unknown table %s', 16, 1, @Table); RETURN; END;
    DECLARE @sql NVARCHAR(MAX) = N'SELECT TOP (@n) * FROM '
        + QUOTENAME(OBJECT_SCHEMA_NAME(OBJECT_ID(@Table))) + N'.' + QUOTENAME(OBJECT_NAME(OBJECT_ID(@Table))) + N';';
    EXEC sp_executesql @sql, N'@n INT', @n = @N;   -- identifiers quoted, the number is a parameter -> nothing to inject
END
GO
EXEC dbo.usp_L20x_TopN @Table = 'dbo.Products', @N = 3;                  -- Laptop, Mouse, Keyboard
GO

-- Q2
DECLARE @list VARCHAR(100) = '101,103,106';
SELECT e.EmployeeName, e.Salary
FROM dbo.Employees e
JOIN STRING_SPLIT(@list, ',') s ON s.value = e.EmployeeID
ORDER BY e.EmployeeID;                                                    -- Rahul 85000, Priya 75000, Sneha 90000
GO

-- Q3
SELECT DepartmentName, ISNULL([2020], 0) AS [2020], ISNULL([2021], 0) AS [2021], ISNULL([2022], 0) AS [2022],
       ISNULL([2023], 0) AS [2023], ISNULL([2024], 0) AS [2024]
FROM (SELECT d.DepartmentName, YEAR(e.HireDate) AS HireYear, e.EmployeeID
      FROM dbo.Employees e JOIN dbo.Departments d ON d.DepartmentID = e.DepartmentID) src
PIVOT (COUNT(EmployeeID) FOR HireYear IN ([2020], [2021], [2022], [2023], [2024])) p
ORDER BY DepartmentName;                                                  -- 5 rows; IT: 0,0,1,2,0 ; Sales: 0,1,1,0,1
GO

-- Q4
DROP TABLE IF EXISTS dbo.L20x_PriceLog;
DROP TABLE IF EXISTS dbo.L20x_Products;
SELECT * INTO dbo.L20x_Products FROM dbo.Products;
CREATE TABLE dbo.L20x_PriceLog (LogID INT IDENTITY PRIMARY KEY, ProductID INT, OldPrice DECIMAL(12,2), NewPrice DECIMAL(12,2), At DATETIME2(0) DEFAULT SYSDATETIME());
GO
CREATE OR ALTER TRIGGER dbo.trg_L20x_Products_Price ON dbo.L20x_Products AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT UPDATE(Price) RETURN;                                          -- Price not in the SET list -> nothing to do
    INSERT INTO dbo.L20x_PriceLog (ProductID, OldPrice, NewPrice)
    SELECT i.ProductID, d.Price, i.Price
    FROM inserted i JOIN deleted d ON d.ProductID = i.ProductID
    WHERE i.Price <> d.Price;                                             -- only real changes (multi-row safe)
END
GO
UPDATE dbo.L20x_Products SET Price = Price * 1.10 WHERE ProductID IN (2, 3);   -- one statement, two rows
UPDATE dbo.L20x_Products SET Stock = Stock WHERE ProductID = 1;               -- Price untouched -> no log
SELECT ProductID, OldPrice, NewPrice FROM dbo.L20x_PriceLog ORDER BY ProductID;   -- 2 rows: 2 (1000 -> 1100), 3 (2500 -> 2750)
GO

-- Q5
DROP TABLE IF EXISTS dbo.L20x_DdlLog;
CREATE TABLE dbo.L20x_DdlLog (Id INT IDENTITY PRIMARY KEY, EventType SYSNAME, ObjectName SYSNAME, LoginName SYSNAME, At DATETIME2(0) DEFAULT SYSDATETIME());
GO
CREATE OR ALTER TRIGGER trg_L20x_LogCreateTable ON DATABASE FOR CREATE_TABLE
AS
BEGIN
    DECLARE @e XML = EVENTDATA();
    INSERT INTO dbo.L20x_DdlLog (EventType, ObjectName, LoginName)
    VALUES (@e.value('(/EVENT_INSTANCE/EventType)[1]', 'sysname'),
            @e.value('(/EVENT_INSTANCE/ObjectName)[1]', 'sysname'),
            @e.value('(/EVENT_INSTANCE/LoginName)[1]', 'sysname'));
END
GO
CREATE TABLE dbo.L20x_Temp (Id INT);
GO
SELECT EventType, ObjectName, LoginName FROM dbo.L20x_DdlLog;            -- CREATE_TABLE, L20x_Temp, <your login>
GO
DROP TRIGGER trg_L20x_LogCreateTable ON DATABASE;
DROP TABLE dbo.L20x_Temp;
GO

-- Q6
DECLARE @name VARCHAR(100), @cnt INT;
DECLARE c CURSOR LOCAL FAST_FORWARD FOR
    SELECT d.DepartmentName, COUNT(e.EmployeeID) FROM dbo.Departments d LEFT JOIN dbo.Employees e ON e.DepartmentID = d.DepartmentID
    GROUP BY d.DepartmentName ORDER BY d.DepartmentName;
OPEN c;
FETCH NEXT FROM c INTO @name, @cnt;
WHILE @@FETCH_STATUS = 0
BEGIN
    PRINT @name + ': ' + CAST(@cnt AS VARCHAR(10)) + ' employees';         -- Finance: 2 ... Legal: 0 ... Sales: 3
    FETCH NEXT FROM c INTO @name, @cnt;
END
CLOSE c; DEALLOCATE c;
GO
-- set-based: the cursor's SELECT already IS the answer
SELECT d.DepartmentName + ': ' + CAST(COUNT(e.EmployeeID) AS VARCHAR(10)) + ' employees' AS Line
FROM dbo.Departments d LEFT JOIN dbo.Employees e ON e.DepartmentID = d.DepartmentID
GROUP BY d.DepartmentName ORDER BY d.DepartmentName;                     -- 6 rows
GO

-- Q7
DROP TABLE IF EXISTS dbo.L20x_Tickets, dbo.L20x_Refunds;
DROP SEQUENCE IF EXISTS dbo.seq_L20x;
CREATE SEQUENCE dbo.seq_L20x AS INT START WITH 1 INCREMENT BY 1;
CREATE TABLE dbo.L20x_Tickets (TicketNo INT NOT NULL DEFAULT (NEXT VALUE FOR dbo.seq_L20x) PRIMARY KEY, Note VARCHAR(20));
CREATE TABLE dbo.L20x_Refunds (RefundNo INT NOT NULL DEFAULT (NEXT VALUE FOR dbo.seq_L20x) PRIMARY KEY, Note VARCHAR(20));
INSERT INTO dbo.L20x_Tickets (Note) VALUES ('t1'), ('t2');
INSERT INTO dbo.L20x_Refunds (Note) VALUES ('r1');
INSERT INTO dbo.L20x_Tickets (Note) VALUES ('t3');
SELECT 'Ticket' AS Kind, TicketNo AS No, Note FROM dbo.L20x_Tickets
UNION ALL SELECT 'Refund', RefundNo, Note FROM dbo.L20x_Refunds
ORDER BY No;                                                              -- 1 t1, 2 t2, 3 r1, 4 t3
GO

-- Q8
SELECT e.EmployeeID AS 'id', e.EmployeeName AS 'name', d.DepartmentID AS 'department.id', d.DepartmentName AS 'department.name'
FROM dbo.Employees e JOIN dbo.Departments d ON d.DepartmentID = e.DepartmentID
WHERE e.EmployeeID = 101
FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;                                     -- {"id":101,"name":"Rahul","department":{"id":1,"name":"IT"}}
GO

-- Q9
DECLARE @post NVARCHAR(MAX) = N'[{"id":101,"bonus":5000},{"id":106,"bonus":8000}]';
SELECT e.EmployeeName, e.Salary, j.bonus
FROM OPENJSON(@post) WITH (id INT, bonus DECIMAL(12,2)) j
JOIN dbo.Employees e ON e.EmployeeID = j.id;                              -- Rahul 85000 5000, Sneha 90000 8000
GO

-- Q10 (a)
SELECT p.Category,
       STUFF((SELECT ', ' + p2.ProductName FROM dbo.Products p2 WHERE p2.Category = p.Category ORDER BY p2.ProductName
              FOR XML PATH(''), TYPE).value('.', 'VARCHAR(MAX)'), 1, 2, '') AS ProductList
FROM dbo.Products p
GROUP BY p.Category
ORDER BY p.Category;                       -- Electronics: Headphones, Keyboard, Laptop, Monitor, Mouse, Webcam ; Furniture: Bookshelf, Chair, Desk ; Stationery: Notebook, Pen
GO
-- Q10 (b)
DECLARE @x XML = N'<products><product id="1" name="Laptop"/><product id="2" name="Mouse"/></products>';
SELECT n.value('@id', 'INT') AS ProductID, n.value('@name', 'VARCHAR(50)') AS ProductName
FROM @x.nodes('/products/product') AS t(n);                               -- 1 Laptop, 2 Mouse
GO

-- Q11
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'L20x_Login') DROP LOGIN L20x_Login;
CREATE LOGIN L20x_Login WITH PASSWORD = 'L20x_Str0ng!Pass', CHECK_POLICY = OFF;
DROP USER IF EXISTS L20x_User;
CREATE USER L20x_User FOR LOGIN L20x_Login;
DROP ROLE IF EXISTS L20x_Readers;
CREATE ROLE L20x_Readers;
ALTER ROLE L20x_Readers ADD MEMBER L20x_User;
GRANT SELECT ON dbo.Departments TO L20x_Readers;
GO
EXECUTE AS USER = 'L20x_User';
SELECT COUNT(*) AS Departments FROM dbo.Departments;                     -- 6
BEGIN TRY
    SELECT COUNT(*) FROM dbo.Employees;
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();                          -- SELECT permission denied on Employees
END CATCH
REVERT;
GO

-- Q12
DECLARE @dir NVARCHAR(400) = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS NVARCHAR(400));
IF RIGHT(@dir, 1) <> '\' SET @dir += '\';
DECLARE @file NVARCHAR(500) = @dir + DB_NAME() + N'_L20x_CopyOnly.bak';
DECLARE @sql NVARCHAR(MAX) = N'BACKUP DATABASE ' + QUOTENAME(DB_NAME()) + N' TO DISK = ''' + @file + N''' WITH COPY_ONLY, INIT, COMPRESSION, CHECKSUM;';
EXEC (@sql);                                                             -- EXEC() accepts only literals/variables, so build the text first
SET @sql = N'RESTORE VERIFYONLY FROM DISK = ''' + @file + N''' WITH CHECKSUM;';
EXEC (@sql);                                                             -- The backup set on file 1 is valid.
SELECT bs.database_name, bs.type, bs.is_copy_only, bs.backup_finish_date, bmf.physical_device_name
FROM msdb.dbo.backupset bs JOIN msdb.dbo.backupmediafamily bmf ON bmf.media_set_id = bs.media_set_id
WHERE bs.database_name = DB_NAME() AND bs.is_copy_only = 1;                                      -- 1 row, type D
BEGIN TRY
    EXEC master.dbo.xp_delete_file 0, @file;                                                    -- remove the file
    PRINT 'backup file deleted';
END TRY
BEGIN CATCH
    PRINT 'could not delete the file, remove it by hand: ' + @file;
END CATCH
DECLARE @db SYSNAME = DB_NAME();
EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = @db;                             -- remove the history rows
GO

-- Q13 (theory)
/* Reporting DB reloaded every night  -> SIMPLE  (nothing to recover point-in-time; reload instead).
   Banking OLTP                       -> FULL    (log backups every few minutes, point-in-time restore, no data loss).
   Bulk load window                   -> switch FULL -> BULK_LOGGED for the load, back to FULL after, then a log backup
                                         (minimal logging speeds up the load; no STOPAT inside that log backup).
   Weekly order: CHECKDB -> index maintenance -> update statistics -> full backup; log backups all day;
   differential daily; cleanup of old files/history; and practise a RESTORE regularly.                        */

/* ---------- CLEANUP ---------- */
REVERT;
DROP PROCEDURE IF EXISTS dbo.usp_L20x_TopN;
DROP TABLE IF EXISTS dbo.L20x_PriceLog;
DROP TABLE IF EXISTS dbo.L20x_Products;
IF EXISTS (SELECT 1 FROM sys.triggers WHERE name = 'trg_L20x_LogCreateTable' AND parent_class_desc = 'DATABASE')
    DROP TRIGGER trg_L20x_LogCreateTable ON DATABASE;
DROP TABLE IF EXISTS dbo.L20x_Temp;
DROP TABLE IF EXISTS dbo.L20x_DdlLog;
DROP TABLE IF EXISTS dbo.L20x_Tickets, dbo.L20x_Refunds;
DROP SEQUENCE IF EXISTS dbo.seq_L20x;
DROP USER IF EXISTS L20x_User;
DROP ROLE IF EXISTS L20x_Readers;
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'L20x_Login') DROP LOGIN L20x_Login;
GO
