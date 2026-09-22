/* ============================================================
   LEVEL 20 - ADVANCED AND ADMIN  |  05_Practice_Backup_Restore_Agent.sql
   ------------------------------------------------------------
   Topics : recovery models (SIMPLE / FULL / BULK_LOGGED), full /
            differential / log / COPY_ONLY backups (INIT, COMPRESSION,
            CHECKSUM, STATS), RESTORE VERIFYONLY / HEADERONLY / FILELISTONLY,
            restoring to a NEW database name WITH MOVE, the NORECOVERY /
            RECOVERY chain, point-in-time restore with STOPAT, backup
            history in msdb, SQL Server Agent (service state, job + step +
            schedule, sp_start_job, sysjobs / sysjobhistory / sysjobactivity),
            linked servers (loopback, four-part names, OPENQUERY),
            maintenance basics (DBCC CHECKDB, index maintenance, weekly plan).

   HOW TO PRACTICE: run block by block, predict the output first.
   Backups go to the instance's default backup folder and are deleted at
   the end; the restored database PracticeDB_L20_Restored, the Agent job
   and the linked server are all removed in CLEANUP. Takes about 15 s.
   ============================================================ */

USE SQLPractice;
GO
SET NOCOUNT ON;
GO


/* ============================================================
   0. SETUP - remember the recovery model, a small table to watch, the backup folder
   ============================================================ */
DROP TABLE IF EXISTS #L20_Settings;
SELECT recovery_model_desc AS OriginalRecoveryModel INTO #L20_Settings FROM sys.databases WHERE name = DB_NAME();
SELECT * FROM #L20_Settings;                                            -- FULL (inherited from model) or SIMPLE
GO
DROP TABLE IF EXISTS dbo.L20_BackupTest;
CREATE TABLE dbo.L20_BackupTest (Id INT IDENTITY PRIMARY KEY, Note VARCHAR(60) NOT NULL, At DATETIME2(3) NOT NULL DEFAULT SYSDATETIME());
GO
-- The default folders of this instance (chosen at install time). Every file name below is built from them.
SELECT SERVERPROPERTY('InstanceDefaultBackupPath') AS BackupFolder,
       SERVERPROPERTY('InstanceDefaultDataPath')   AS DataFolder,
       SERVERPROPERTY('InstanceDefaultLogPath')    AS LogFolder;
GO


/* ============================================================
   1. RECOVERY MODELS - what the transaction log keeps
   ============================================================
   SIMPLE      : log is truncated at every checkpoint -> no log backups possible, restore only to the
                 last full/differential backup. Dev, test, warehouses that are reloaded anyway.
   FULL        : log records are kept until a LOG BACKUP copies them -> point-in-time restore. You MUST
                 schedule log backups or the .ldf grows forever. The production OLTP default.
   BULK_LOGGED : like FULL, but bulk operations (BULK INSERT, SELECT INTO, index rebuild) are minimally
                 logged -> faster, but no point-in-time restore inside a log backup that contains them.
   ============================================================ */
SELECT name, recovery_model_desc, log_reuse_wait_desc FROM sys.databases WHERE name = DB_NAME();
ALTER DATABASE SQLPractice SET RECOVERY FULL;                            -- log backups need FULL (or BULK_LOGGED)
SELECT name, recovery_model_desc FROM sys.databases WHERE name = DB_NAME();   -- FULL
GO


/* ============================================================
   2. THE BACKUP CHAIN: full -> differential -> log, with data changes in between
   ============================================================ */
INSERT INTO dbo.L20_BackupTest (Note) VALUES ('row 1 - before the FULL backup');
GO
-- 2a. FULL backup: INIT overwrites the file, COMPRESSION shrinks it, CHECKSUM verifies every page on the way,
--     STATS = 25 prints progress every 25 %. (Paths differ per machine, so the statement is built dynamically.)
DECLARE @dir NVARCHAR(400) = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS NVARCHAR(400));
IF RIGHT(@dir, 1) <> '\' SET @dir += '\';
DECLARE @sql NVARCHAR(MAX) = N'BACKUP DATABASE ' + QUOTENAME(DB_NAME()) + N' TO DISK = ''' + @dir + DB_NAME() + N'_L20_Full.bak''
WITH INIT, COMPRESSION, CHECKSUM, STATS = 25;';
PRINT @sql;
EXEC (@sql);                                                             -- "BACKUP DATABASE successfully processed n pages ..."
GO
INSERT INTO dbo.L20_BackupTest (Note) VALUES ('row 2 - after FULL, before DIFFERENTIAL');
GO
-- 2b. DIFFERENTIAL = every extent changed since the LAST FULL (small and fast; each diff is independent of earlier diffs)
DECLARE @dir NVARCHAR(400) = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS NVARCHAR(400));
IF RIGHT(@dir, 1) <> '\' SET @dir += '\';
DECLARE @sql NVARCHAR(MAX) = N'BACKUP DATABASE ' + QUOTENAME(DB_NAME()) + N' TO DISK = ''' + @dir + DB_NAME() + N'_L20_Diff.bak''
WITH DIFFERENTIAL, INIT, COMPRESSION, CHECKSUM;';
EXEC (@sql);
GO
INSERT INTO dbo.L20_BackupTest (Note) VALUES ('row 3 - after DIFFERENTIAL, before the STOPAT time');
WAITFOR DELAY '00:00:02';                                                -- clear gap so the timestamps cannot overlap
GO
-- 2c. Remember a point in time (the moment "before the disaster"), then make one more change that we will
--     deliberately LOSE with the point-in-time restore in section 5.
DROP TABLE IF EXISTS #L20_Time;
CREATE TABLE #L20_Time (StopAt DATETIME2(0));
INSERT INTO #L20_Time VALUES (SYSDATETIME());
WAITFOR DELAY '00:00:02';
INSERT INTO dbo.L20_BackupTest (Note) VALUES ('row 4 - after the STOPAT time (the "disaster")');
GO
-- 2d. LOG backup (FULL model only): copies all log records since the previous log backup (or since the
--     full backup when it is the first one) and lets the log file space be reused.
DECLARE @dir NVARCHAR(400) = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS NVARCHAR(400));
IF RIGHT(@dir, 1) <> '\' SET @dir += '\';
DECLARE @sql NVARCHAR(MAX) = N'BACKUP LOG ' + QUOTENAME(DB_NAME()) + N' TO DISK = ''' + @dir + DB_NAME() + N'_L20_Log.trn''
WITH INIT, COMPRESSION, CHECKSUM;';
EXEC (@sql);
-- 2e. COPY_ONLY: an extra full backup that does NOT reset the differential base (for "give me a copy for dev")
SET @sql = N'BACKUP DATABASE ' + QUOTENAME(DB_NAME()) + N' TO DISK = ''' + @dir + DB_NAME() + N'_L20_CopyOnly.bak''
WITH COPY_ONLY, INIT, COMPRESSION, CHECKSUM;';
EXEC (@sql);
GO
SELECT Id, Note, At FROM dbo.L20_BackupTest;                             -- 4 rows in the live database
GO


/* ============================================================
   3. LOOK INSIDE A BACKUP FILE: VERIFYONLY, HEADERONLY, FILELISTONLY
   ============================================================ */
DECLARE @dir NVARCHAR(400) = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS NVARCHAR(400));
IF RIGHT(@dir, 1) <> '\' SET @dir += '\';
DECLARE @full NVARCHAR(500) = @dir + DB_NAME() + N'_L20_Full.bak';
-- 3a. Is the file readable and consistent? (does not restore anything)
EXEC (N'RESTORE VERIFYONLY FROM DISK = ''' + @full + N''' WITH CHECKSUM;');           -- "The backup set on file 1 is valid."
-- 3b. What is in it? BackupType 1 = full, 5 = differential, 2 = log; DatabaseName, BackupStartDate, LSNs, IsCopyOnly ... (wide!)
EXEC (N'RESTORE HEADERONLY FROM DISK = ''' + @full + N''';');
-- 3c. Which database files does it contain? LogicalName + PhysicalName -> needed for WITH MOVE below
EXEC (N'RESTORE FILELISTONLY FROM DISK = ''' + @full + N''';');           -- 2 rows: data file (Type D) and log file (Type L)
GO


/* ============================================================
   4. RESTORE TO A NEW NAME: full + differential + log  (NORECOVERY ... RECOVERY)
   ============================================================ */
IF DB_ID('PracticeDB_L20_Restored') IS NOT NULL
BEGIN
    ALTER DATABASE PracticeDB_L20_Restored SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE PracticeDB_L20_Restored;
END
GO
DECLARE @dir  NVARCHAR(400) = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS NVARCHAR(400));
DECLARE @data NVARCHAR(400) = CAST(SERVERPROPERTY('InstanceDefaultDataPath')   AS NVARCHAR(400));
DECLARE @log  NVARCHAR(400) = CAST(SERVERPROPERTY('InstanceDefaultLogPath')    AS NVARCHAR(400));
IF RIGHT(@dir, 1)  <> '\' SET @dir  += '\';
IF RIGHT(@data, 1) <> '\' SET @data += '\';
IF RIGHT(@log, 1)  <> '\' SET @log  += '\';
-- logical file names of the SOURCE database (same as RESTORE FILELISTONLY showed)
DECLARE @dataLogical SYSNAME = (SELECT name FROM sys.master_files WHERE database_id = DB_ID() AND type_desc = 'ROWS');
DECLARE @logLogical  SYSNAME = (SELECT name FROM sys.master_files WHERE database_id = DB_ID() AND type_desc = 'LOG');

-- 4a. FULL with NORECOVERY ("more to come") and MOVE (new physical files, or the restore would try to overwrite the live ones)
DECLARE @sql NVARCHAR(MAX) = N'RESTORE DATABASE PracticeDB_L20_Restored FROM DISK = ''' + @dir + DB_NAME() + N'_L20_Full.bak''
WITH NORECOVERY,
     MOVE ''' + @dataLogical + N''' TO ''' + @data + N'PracticeDB_L20_Restored.mdf'',
     MOVE ''' + @logLogical  + N''' TO ''' + @log  + N'PracticeDB_L20_Restored_log.ldf'';';
PRINT @sql;
EXEC (@sql);
-- 4b. DIFFERENTIAL with NORECOVERY
SET @sql = N'RESTORE DATABASE PracticeDB_L20_Restored FROM DISK = ''' + @dir + DB_NAME() + N'_L20_Diff.bak'' WITH NORECOVERY;';
EXEC (@sql);
-- 4c. LOG with RECOVERY ("finish: roll back open transactions and open the database")
SET @sql = N'RESTORE LOG PracticeDB_L20_Restored FROM DISK = ''' + @dir + DB_NAME() + N'_L20_Log.trn'' WITH RECOVERY;';
EXEC (@sql);
GO
SELECT name, state_desc, recovery_model_desc FROM sys.databases WHERE name = 'PracticeDB_L20_Restored';   -- ONLINE, FULL
SELECT Id, Note FROM PracticeDB_L20_Restored.dbo.L20_BackupTest;   -- all 4 rows: everything up to the log backup came back
GO
-- Forgot RECOVERY and the database is stuck in "Restoring..."?  RESTORE DATABASE PracticeDB_L20_Restored WITH RECOVERY;  (no FROM)


/* ============================================================
   5. POINT-IN-TIME RESTORE: STOPAT  (undo the "disaster" = row 4)
   ============================================================ */
-- Same chain, but the LOG restore stops at the remembered time. Requirements: FULL (or BULK_LOGGED) model,
-- an unbroken chain of log backups, and the time must fall inside the log backup you restore with STOPAT.
-- Earlier log backups are restored WITH NORECOVERY as usual; STOPATMARK / STOPBEFOREMARK work with named transactions.
ALTER DATABASE PracticeDB_L20_Restored SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE PracticeDB_L20_Restored;
GO
DECLARE @dir  NVARCHAR(400) = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS NVARCHAR(400));
DECLARE @data NVARCHAR(400) = CAST(SERVERPROPERTY('InstanceDefaultDataPath')   AS NVARCHAR(400));
DECLARE @log  NVARCHAR(400) = CAST(SERVERPROPERTY('InstanceDefaultLogPath')    AS NVARCHAR(400));
IF RIGHT(@dir, 1)  <> '\' SET @dir  += '\';
IF RIGHT(@data, 1) <> '\' SET @data += '\';
IF RIGHT(@log, 1)  <> '\' SET @log  += '\';
DECLARE @dataLogical SYSNAME = (SELECT name FROM sys.master_files WHERE database_id = DB_ID() AND type_desc = 'ROWS');
DECLARE @logLogical  SYSNAME = (SELECT name FROM sys.master_files WHERE database_id = DB_ID() AND type_desc = 'LOG');
DECLARE @stop DATETIME2(0) = (SELECT TOP (1) StopAt FROM #L20_Time);
DECLARE @sql NVARCHAR(MAX) = N'RESTORE DATABASE PracticeDB_L20_Restored FROM DISK = ''' + @dir + DB_NAME() + N'_L20_Full.bak''
WITH NORECOVERY, MOVE ''' + @dataLogical + N''' TO ''' + @data + N'PracticeDB_L20_Restored.mdf'',
                 MOVE ''' + @logLogical  + N''' TO ''' + @log  + N'PracticeDB_L20_Restored_log.ldf'';';
EXEC (@sql);
SET @sql = N'RESTORE DATABASE PracticeDB_L20_Restored FROM DISK = ''' + @dir + DB_NAME() + N'_L20_Diff.bak'' WITH NORECOVERY;';
EXEC (@sql);
SET @sql = N'RESTORE LOG PracticeDB_L20_Restored FROM DISK = ''' + @dir + DB_NAME() + N'_L20_Log.trn''
WITH STOPAT = ''' + CONVERT(NVARCHAR(30), @stop, 121) + N''', RECOVERY;';
PRINT @sql;
EXEC (@sql);
GO
SELECT Id, Note FROM PracticeDB_L20_Restored.dbo.L20_BackupTest;   -- 3 rows: row 4 is gone, the database is as it was at the STOPAT time
GO


/* ============================================================
   6. BACKUP HISTORY - msdb remembers every backup
   ============================================================ */
SELECT bs.database_name,
       CASE bs.type WHEN 'D' THEN 'Full' WHEN 'I' THEN 'Differential' WHEN 'L' THEN 'Log' END AS BackupType,
       bs.is_copy_only, bs.backup_start_date,
       bs.backup_size / 1024 AS SizeKB, bs.compressed_backup_size / 1024 AS CompressedKB,
       bmf.physical_device_name
FROM msdb.dbo.backupset bs
JOIN msdb.dbo.backupmediafamily bmf ON bmf.media_set_id = bs.media_set_id
WHERE bs.database_name = DB_NAME()
ORDER BY bs.backup_start_date;                                           -- 4 rows: Full, Differential, Log, Full (is_copy_only 1)
GO
-- Interview classic: "last full backup of every database"
SELECT d.name, MAX(bs.backup_finish_date) AS LastFullBackup
FROM sys.databases d
LEFT JOIN msdb.dbo.backupset bs ON bs.database_name = d.name AND bs.type = 'D'
WHERE d.database_id > 4                                                  -- skip system databases
GROUP BY d.name ORDER BY LastFullBackup;                                 -- NULL = never backed up!
GO


/* ============================================================
   7. SQL SERVER AGENT - the scheduler (jobs = steps + schedules)
   ============================================================ */
SELECT servicename, status_desc, startup_type_desc FROM sys.dm_server_services;   -- is "SQL Server Agent (...)" Running?
GO
DROP TABLE IF EXISTS dbo.L20_JobLog;
CREATE TABLE dbo.L20_JobLog (Id INT IDENTITY PRIMARY KEY, RunAt DATETIME2(0) NOT NULL DEFAULT SYSDATETIME(), Msg VARCHAR(100) NOT NULL);
GO
-- 7a. Create a job the way SSMS does it: sp_add_job -> sp_add_jobstep -> sp_add_jobschedule -> sp_add_jobserver (all in msdb)
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = 'L20_DemoJob') EXEC msdb.dbo.sp_delete_job @job_name = N'L20_DemoJob';
DECLARE @db SYSNAME = DB_NAME();
EXEC msdb.dbo.sp_add_job @job_name = N'L20_DemoJob', @enabled = 1, @description = N'Level 20 demo: writes one row into dbo.L20_JobLog';
EXEC msdb.dbo.sp_add_jobstep @job_name = N'L20_DemoJob', @step_name = N'Write log row',
     @subsystem = N'TSQL', @database_name = @db,                          -- other subsystems: PowerShell, CmdExec, SSIS
     @command = N'INSERT INTO dbo.L20_JobLog (Msg) VALUES (''Hello from SQL Agent'');',
     @retry_attempts = 0;
EXEC msdb.dbo.sp_add_jobschedule @job_name = N'L20_DemoJob', @name = N'Daily 01:00',
     @freq_type = 4, @freq_interval = 1, @active_start_time = 010000;     -- 4 = daily, every 1 day, at 01:00:00
EXEC msdb.dbo.sp_add_jobserver @job_name = N'L20_DemoJob', @server_name = N'(LOCAL)';   -- a job runs only on its target server
GO
-- 7b. Run it now. Works only when the Agent SERVICE is running (otherwise: error, caught here).
BEGIN TRY
    EXEC msdb.dbo.sp_start_job @job_name = N'L20_DemoJob';
    WAITFOR DELAY '00:00:03';                                            -- jobs run asynchronously - give it a moment
END TRY
BEGIN CATCH
    PRINT 'Agent could not start the job (service stopped?): ' + ERROR_MESSAGE();
END CATCH
GO
-- 7c. The catalog: definition, history, activity
SELECT j.name, j.enabled, s.step_id, s.step_name, s.subsystem, s.database_name, sch.name AS Schedule
FROM msdb.dbo.sysjobs j
JOIN msdb.dbo.sysjobsteps s        ON s.job_id = j.job_id
LEFT JOIN msdb.dbo.sysjobschedules js ON js.job_id = j.job_id
LEFT JOIN msdb.dbo.sysschedules sch   ON sch.schedule_id = js.schedule_id
WHERE j.name = 'L20_DemoJob';                                            -- 1 row
SELECT h.run_date, h.run_time, h.step_id,
       CASE h.run_status WHEN 1 THEN 'Succeeded' WHEN 0 THEN 'Failed' WHEN 3 THEN 'Cancelled' ELSE 'Other' END AS Outcome,
       LEFT(h.message, 90) AS Message
FROM msdb.dbo.sysjobhistory h JOIN msdb.dbo.sysjobs j ON j.job_id = h.job_id
WHERE j.name = 'L20_DemoJob' ORDER BY h.instance_id;                     -- 2 rows if it ran (step + job outcome), else 0
SELECT ja.start_execution_date, ja.stop_execution_date
FROM msdb.dbo.sysjobactivity ja JOIN msdb.dbo.sysjobs j ON j.job_id = ja.job_id
WHERE j.name = 'L20_DemoJob';
SELECT * FROM dbo.L20_JobLog;                                            -- 1 row 'Hello from SQL Agent' if the Agent is running, else 0
GO
-- Real jobs: backups, CHECKDB, index/statistics maintenance, ETL loads, cleanup - with alerts + operators (email) on failure.


/* ============================================================
   8. LINKED SERVERS - query another instance by name
   ============================================================ */
-- A loopback linked server (points at THIS instance) so the syntax can be practised on one machine.
-- Everything is in TRY/CATCH: providers, encryption and login mapping differ per machine.
BEGIN TRY
    IF EXISTS (SELECT 1 FROM sys.servers WHERE name = 'L20_LOOPBACK') EXEC sp_dropserver 'L20_LOOPBACK', 'droplogins';
    EXEC sp_addlinkedserver @server = N'L20_LOOPBACK', @srvproduct = N'', @provider = N'MSOLEDBSQL',
                            @datasrc = @@SERVERNAME, @provstr = N'Encrypt=Optional;TrustServerCertificate=Yes';
    EXEC sp_addlinkedsrvlogin @rmtsrvname = N'L20_LOOPBACK', @useself = N'TRUE';   -- self-mapped: connect as the same Windows login
    PRINT 'Linked server L20_LOOPBACK created';
END TRY
BEGIN CATCH
    PRINT 'Could not create the linked server: ' + ERROR_MESSAGE();
END CATCH
GO
SELECT name, provider, data_source, is_linked FROM sys.servers ORDER BY server_id;   -- row 0 = this server, then L20_LOOPBACK
GO
-- 8a. Four-part name: server.database.schema.object - the local optimizer may pull rows across and filter here
BEGIN TRY
    DECLARE @sql NVARCHAR(MAX) = N'SELECT TOP (3) DepartmentID, DepartmentName FROM L20_LOOPBACK.' + QUOTENAME(DB_NAME()) + N'.dbo.Departments ORDER BY DepartmentID;';
    EXEC sp_executesql @sql;                                             -- IT, Sales, HR
END TRY
BEGIN CATCH
    PRINT 'Four-part query failed: ' + ERROR_MESSAGE();
END CATCH
GO
-- 8b. OPENQUERY: the whole query text is sent to the remote server and runs THERE (pass-through) - usually faster
BEGIN TRY
    DECLARE @sql NVARCHAR(MAX) = N'SELECT * FROM OPENQUERY(L20_LOOPBACK, ''SELECT COUNT(*) AS Employees FROM ' + QUOTENAME(DB_NAME()) + N'.dbo.Employees'');';
    EXEC sp_executesql @sql;                                             -- 12
END TRY
BEGIN CATCH
    PRINT 'OPENQUERY failed: ' + ERROR_MESSAGE();
END CATCH
GO
/* Notes: sp_testlinkedserver 'name' checks connectivity; writes across a linked server inside a transaction need
   MSDTC (distributed transactions); security mapping = @useself TRUE (pass the caller) or a fixed remote login;
   for big data movement prefer SSIS / replication / ETL over linked-server joins.                              */


/* ============================================================
   9. MAINTENANCE BASICS
   ============================================================ */
-- 9a. Integrity check of the current database. No output = no corruption. Run BEFORE the full backup so you never
--     keep a backup of a corrupt database. (Options: PHYSICAL_ONLY for speed, TABLOCK, REPAIR_* as last resort.)
DBCC CHECKDB WITH NO_INFOMSGS;
GO
-- 9b. Index maintenance recap (Level 17): fragmentation -> REORGANIZE (5-30 %) or REBUILD (> 30 %, > 1000 pages)
SELECT OBJECT_NAME(ps.object_id) AS TableName, i.name AS IndexName,
       CAST(ps.avg_fragmentation_in_percent AS DECIMAL(5,1)) AS FragPct, ps.page_count
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ps
JOIN sys.indexes i ON i.object_id = ps.object_id AND i.index_id = ps.index_id
WHERE ps.index_id > 0 AND OBJECTPROPERTY(ps.object_id, 'IsUserTable') = 1
ORDER BY ps.page_count DESC, TableName;                                  -- tiny tables here: page_count 1-2, fragmentation irrelevant
-- ALTER INDEX ALL ON dbo.Orders REORGANIZE;   ALTER INDEX ALL ON dbo.Orders REBUILD WITH (ONLINE = ON);  -- Enterprise for ONLINE
GO
/* THE STANDARD WEEKLY PLAN (interview answer "what maintenance do you schedule?")
   Daily   : full backup (or weekly full + daily differential), LOG backups every 5-15 min in FULL model,
             cleanup of old backup files (xp_delete_file / maintenance plan / Ola Hallengren scripts).
   Weekly  : 1. DBCC CHECKDB  2. index REORGANIZE/REBUILD  3. UPDATE STATISTICS (sp_updatestats)  4. full backup
             -> integrity first, then maintenance, then the backup you would restore from.
   Monthly : msdb history cleanup (sp_delete_backuphistory), test a RESTORE (a backup you never restored is a hope, not a backup).
   Tools   : Maintenance Plans (wizard), Ola Hallengren's free scripts (industry standard), SQL Agent jobs + alerts.   */


/* ============================================================
   10. CLEANUP - restored database, backup files, history, job, linked server, recovery model, tables
   ============================================================ */
IF DB_ID('PracticeDB_L20_Restored') IS NOT NULL
BEGIN
    ALTER DATABASE PracticeDB_L20_Restored SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE PracticeDB_L20_Restored;
END
GO
-- backup files: xp_delete_file (undocumented but standard) removes one backup file per call
DECLARE @dir NVARCHAR(400) = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS NVARCHAR(400));
IF RIGHT(@dir, 1) <> '\' SET @dir += '\';
DECLARE @files TABLE (FileName NVARCHAR(300));
INSERT INTO @files VALUES (DB_NAME() + N'_L20_Full.bak'), (DB_NAME() + N'_L20_Diff.bak'), (DB_NAME() + N'_L20_Log.trn'), (DB_NAME() + N'_L20_CopyOnly.bak');
DECLARE @f NVARCHAR(500);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT @dir + FileName FROM @files;
OPEN c; FETCH NEXT FROM c INTO @f;
WHILE @@FETCH_STATUS = 0
BEGIN
    BEGIN TRY
        EXEC master.dbo.xp_delete_file 0, @f;
        PRINT 'deleted ' + @f;
    END TRY
    BEGIN CATCH
        PRINT 'could not delete ' + @f + ' (delete it by hand): ' + ERROR_MESSAGE();
    END CATCH
    FETCH NEXT FROM c INTO @f;
END
CLOSE c; DEALLOCATE c;
DECLARE @db SYSNAME = DB_NAME();
EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = @db;     -- forget this practice run in msdb
GO
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = 'L20_DemoJob') EXEC msdb.dbo.sp_delete_job @job_name = N'L20_DemoJob';
IF EXISTS (SELECT 1 FROM sys.servers WHERE name = 'L20_LOOPBACK') EXEC sp_dropserver 'L20_LOOPBACK', 'droplogins';
GO
-- Recovery model: SIMPLE first ends the log chain we started (so the practice database's log does not grow
-- forever waiting for log backups), then back to the original model.
DECLARE @orig NVARCHAR(60) = (SELECT OriginalRecoveryModel FROM #L20_Settings);
ALTER DATABASE SQLPractice SET RECOVERY SIMPLE;
IF @orig = 'FULL'        ALTER DATABASE SQLPractice SET RECOVERY FULL;
IF @orig = 'BULK_LOGGED' ALTER DATABASE SQLPractice SET RECOVERY BULK_LOGGED;
GO
DROP TABLE IF EXISTS dbo.L20_BackupTest;
DROP TABLE IF EXISTS dbo.L20_JobLog;
DROP TABLE IF EXISTS #L20_Settings;
DROP TABLE IF EXISTS #L20_Time;
GO
SELECT (SELECT COUNT(*) FROM sys.databases WHERE name = 'PracticeDB_L20_Restored') AS RestoredDbLeft,     -- 0
       (SELECT COUNT(*) FROM msdb.dbo.sysjobs WHERE name = 'L20_DemoJob')             AS JobLeft,           -- 0
       (SELECT COUNT(*) FROM sys.servers WHERE name = 'L20_LOOPBACK')                  AS LinkedServerLeft, -- 0
       (SELECT recovery_model_desc FROM sys.databases WHERE name = DB_NAME())          AS RecoveryModel;    -- as at the start
GO
/* DONE. Next: Exercises.sql */
