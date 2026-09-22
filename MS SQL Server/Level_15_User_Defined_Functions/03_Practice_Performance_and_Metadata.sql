/* ============================================================
   LEVEL 15 - USER DEFINED FUNCTIONS  |  03_Practice_Performance_and_Metadata.sql
   ------------------------------------------------------------
   Topics : performance of scalar UDFs (row-by-row, no parallelism)
            measured with SET STATISTICS TIME, scalar UDF inlining
            (2019+: sys.sql_modules.is_inlineable, WITH INLINE),
            inline TVF vs multi-statement TVF and why, function vs
            stored procedure, metadata (sys.objects FN/IF/TF,
            sys.sql_modules, sys.parameters), built-in functions vs UDF.
   HOW TO PRACTICE: run block by block, predict the output first.
   Creates a 200,000 row helper table dbo.L15_Big (dropped at the end).
   ============================================================ */

USE SQLPractice;
GO
DROP FUNCTION IF EXISTS dbo.fn_L15_Discount, dbo.fn_L15_DaysSince, dbo.fn_L15_Square,
                        dbo.fn_L15_BigOrders_Inline, dbo.fn_L15_BigOrders_Multi;
DROP PROCEDURE IF EXISTS dbo.usp_L15_Hello;
DROP TABLE IF EXISTS dbo.L15_Big;
GO
SELECT ISNULL(CAST(s.value AS INT), 0)                       AS RowID,
       s.value % 1000 + 1                                     AS CustomerID,
       CAST((s.value * 37) % 100000 + 100 AS DECIMAL(12,2))   AS Amount
INTO dbo.L15_Big
FROM GENERATE_SERIES(1, 200000) AS s;                         -- SQL 2022+
ALTER TABLE dbo.L15_Big ADD CONSTRAINT PK_L15_Big PRIMARY KEY (RowID);
CREATE INDEX IX_L15_Big_CustomerID ON dbo.L15_Big (CustomerID);
SELECT COUNT(*) AS Rows FROM dbo.L15_Big;    -- 200000
GO
-- Small helpers reused below
CREATE FUNCTION dbo.fn_L15_DaysSince (@Date DATE) RETURNS INT
AS BEGIN RETURN DATEDIFF(DAY, @Date, GETDATE()); END
GO
CREATE FUNCTION dbo.fn_L15_Square (@x INT) RETURNS INT
AS BEGIN RETURN @x * @x; END
GO
CREATE PROCEDURE dbo.usp_L15_Hello AS SELECT 'hello' AS Msg;
GO


/* ============================================================
   1. PERFORMANCE: scalar UDF = row-by-row, and no parallelism
   ============================================================
   Before SQL 2019 a scalar UDF in SELECT / WHERE was executed ONCE
   PER ROW as a separate mini-program, and the whole query plan was
   forced SERIAL. SQL 2019+ can "inline" simple UDFs (rewrite them
   into the query), which removes both problems.
   WITH INLINE = OFF reproduces the old behaviour for the demo.
   Watch the "CPU time / elapsed time" lines printed by STATISTICS TIME.
   ============================================================ */
CREATE FUNCTION dbo.fn_L15_Discount (@Amount DECIMAL(12,2)) RETURNS DECIMAL(12,2)
WITH INLINE = OFF                                   -- 2019+: do NOT inline this one
AS BEGIN RETURN CASE WHEN @Amount >= 50000 THEN @Amount * 0.90 ELSE @Amount END; END
GO

SET STATISTICS TIME ON;
GO
PRINT '=== 1a. plain expression in the SELECT (baseline) ===';
SELECT SUM(CASE WHEN Amount >= 50000 THEN Amount * 0.90 ELSE Amount END) AS Total
FROM dbo.L15_Big;
-- expect roughly 20-60 ms CPU
GO
PRINT '=== 1b. same logic as a scalar UDF, INLINE = OFF (old behaviour) ===';
SELECT SUM(dbo.fn_L15_Discount(Amount)) AS Total
FROM dbo.L15_Big;
-- expect 10-30x slower (hundreds of ms): 200,000 separate function calls
GO
PRINT '=== 1c. scalar UDF in WHERE, INLINE = OFF ===';
SELECT COUNT(*) AS Rows
FROM dbo.L15_Big
WHERE dbo.fn_L15_Discount(Amount) > 40000;
-- expect 120198 rows, again hundreds of ms; the UDF also stops index usage on Amount
GO
SET STATISTICS TIME OFF;
GO

-- 1d. Scalar UDF inlining (SQL 2019+, compatibility level 150+).
--     sys.sql_modules.is_inlineable = the function CAN be inlined (simple enough).
--     inline_type = 1 means inlining is switched on for it.
SELECT o.name, m.is_inlineable, m.inline_type
FROM sys.sql_modules m
JOIN sys.objects o ON o.object_id = m.object_id
WHERE o.name IN ('fn_L15_Discount', 'fn_L15_DaysSince', 'fn_L15_Square')
ORDER BY o.name;
-- expect: fn_L15_DaysSince 0/0 (uses GETDATE -> not inlineable)
--         fn_L15_Discount  1/0 (inlineable, but switched OFF by WITH INLINE = OFF)
--         fn_L15_Square    1/1 (inlineable and on - the default)
GO

-- Switch inlining ON and repeat the slow query
CREATE OR ALTER FUNCTION dbo.fn_L15_Discount (@Amount DECIMAL(12,2)) RETURNS DECIMAL(12,2)
WITH INLINE = ON
AS BEGIN RETURN CASE WHEN @Amount >= 50000 THEN @Amount * 0.90 ELSE @Amount END; END
GO
SET STATISTICS TIME ON;
GO
PRINT '=== 1e. same UDF, INLINE = ON (2019+): back near the baseline speed ===';
SELECT SUM(dbo.fn_L15_Discount(Amount)) AS Total
FROM dbo.L15_Big;
-- expect tens of ms, not hundreds
GO
PRINT '=== 1f. inlining disabled per query with a hint ===';
SELECT SUM(dbo.fn_L15_Discount(Amount)) AS Total
FROM dbo.L15_Big
OPTION (USE HINT('DISABLE_TSQL_SCALAR_UDF_INLINING'));
-- expect slow again
GO
SET STATISTICS TIME OFF;
GO
-- Database-wide switch (do not run here):
--   ALTER DATABASE SCOPED CONFIGURATION SET TSQL_SCALAR_UDF_INLINING = OFF;
-- Not inlineable: functions using GETDATE/@@ROWCOUNT etc., functions that are too
-- complex (loops, many statements), functions used in computed columns / CHECK
-- constraints, and any call with OPTION (USE HINT('DISABLE_TSQL_SCALAR_UDF_INLINING')).


/* ============================================================
   2. PREFER INLINE TVF OVER MULTI-STATEMENT TVF - and why
   ============================================================
   iTVF  : expanded into the query -> real statistics, indexes,
           predicates pushed INTO the function, parallel plans.
   MSTVF : fills a table variable -> no statistics, fixed row
           estimate (1 row before 2014, 100 rows 2014-2016, real
           count only with "interleaved execution" 2017+), the WHOLE
           result is built first and filtered afterwards, serial.
   ============================================================ */
-- Both functions return ALL 200,000 rows; the filter is applied OUTSIDE the function.
CREATE FUNCTION dbo.fn_L15_BigOrders_Inline ()
RETURNS TABLE
AS RETURN (SELECT RowID, CustomerID, Amount FROM dbo.L15_Big);
GO
CREATE FUNCTION dbo.fn_L15_BigOrders_Multi ()
RETURNS @t TABLE (RowID INT, CustomerID INT, Amount DECIMAL(12,2))
AS
BEGIN
    INSERT INTO @t SELECT RowID, CustomerID, Amount FROM dbo.L15_Big;
    RETURN;
END
GO

SET STATISTICS TIME ON;
GO
PRINT '=== 2a. inline TVF: WHERE is pushed inside -> Index Seek on CustomerID ===';
SELECT COUNT(*) AS Rows, SUM(Amount) AS Total
FROM dbo.fn_L15_BigOrders_Inline()
WHERE CustomerID = 5;
-- expect 200 rows, a few ms
GO
PRINT '=== 2b. multi-statement TVF: all 200,000 rows copied into @t, THEN filtered ===';
SELECT COUNT(*) AS Rows, SUM(Amount) AS Total
FROM dbo.fn_L15_BigOrders_Multi()
WHERE CustomerID = 5;
-- expect the same 200 rows but 50-100x more CPU time
GO
SET STATISTICS TIME OFF;
GO
-- In SSMS (Ctrl+M) look at the plan: the MSTVF shows a "Table Valued Function"
-- operator with a fixed estimate, the iTVF shows the real Index Seek.
-- RULE: write the function as an iTVF whenever the body can be ONE SELECT
-- (use CASE, CTEs, APPLY, window functions inside it if needed).


/* ============================================================
   3. FUNCTION vs STORED PROCEDURE  (interview classic)
   ============================================================
   Feature                     Function                 Stored procedure
   --------------------------  -----------------------  -------------------------
   Must return a value         yes (scalar or table)    no (optional RETURN int, OUTPUT params)
   Usable inside SELECT/WHERE  yes                      no (EXEC only)
   Can modify tables           no                       yes
   Transactions / TRY-CATCH    no                       yes
   Call a procedure            no                       yes (and can call functions)
   Dynamic SQL                 no                       yes
   Temp tables                 no (table variables ok)  yes
   Result sets                 exactly one table        0..many
   Compiled plan reuse         yes                      yes
   ============================================================ */

-- 3a. A procedure cannot be used in a SELECT ...
BEGIN TRY
    EXEC sp_executesql N'SELECT * FROM dbo.usp_L15_Hello';
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();    -- "Invalid object name" - a proc is not a table
END CATCH
GO
-- ... to reuse a procedure's result set you need INSERT ... EXEC into a table
DECLARE @r TABLE (Msg VARCHAR(20));
INSERT INTO @r EXEC dbo.usp_L15_Hello;
SELECT * FROM @r;                                   -- hello
GO

-- 3b. Little-known: a SCALAR function can also be called with EXEC (like a proc)
DECLARE @sq INT;
EXEC @sq = dbo.fn_L15_Square 12;
SELECT @sq AS SquareViaExec;                        -- 144
GO


/* ============================================================
   4. METADATA: where SQL Server stores your functions
   ============================================================ */

-- 4a. sys.objects: type FN = scalar, IF = inline TVF, TF = multi-statement TVF
SELECT name, type, type_desc, create_date
FROM sys.objects
WHERE name LIKE 'fn_L15%'
ORDER BY type, name;
-- expect 5 rows: 3 x FN (DaysSince, Discount, Square), 1 x IF (BigOrders_Inline), 1 x TF (BigOrders_Multi)
GO

-- 4b. sys.sql_modules holds the source text and the options
SELECT o.name, m.is_schema_bound, m.is_inlineable, m.inline_type, LEFT(m.definition, 60) AS DefinitionStart
FROM sys.sql_modules m
JOIN sys.objects o ON o.object_id = m.object_id
WHERE o.name LIKE 'fn_L15%'
ORDER BY o.name;
-- Note: some definitions start with a comment. EVERYTHING in the batch before
-- CREATE FUNCTION is stored as part of the definition. Put GO directly before
-- CREATE if you want a clean definition.
GO

-- 4c. Other ways to read the definition and the parameters
SELECT OBJECT_DEFINITION(OBJECT_ID('dbo.fn_L15_Square')) AS Source;
EXEC sp_helptext 'dbo.fn_L15_Square';
SELECT p.parameter_id, p.name, TYPE_NAME(p.user_type_id) AS DataType, p.max_length, p.is_output
FROM sys.parameters p
WHERE p.object_id = OBJECT_ID('dbo.fn_L15_Discount');
-- expect 2 rows: parameter_id 0 = the unnamed RETURN value (is_output = 1), then @Amount
GO

-- 4d. Which tables/objects does a function depend on?
SELECT referenced_schema_name, referenced_entity_name, referenced_minor_name
FROM sys.dm_sql_referenced_entities('dbo.fn_L15_BigOrders_Inline', 'OBJECT');
-- expect 4 rows: dbo.L15_Big (the table) + its 3 used columns
GO


/* ============================================================
   5. SYSTEM BUILT-IN FUNCTIONS vs USER DEFINED FUNCTIONS
   ============================================================
   Built-in "intrinsic" functions (GETDATE, LEN, SUM, ISNULL ...) are
   part of the engine: no schema, no object_id, no dbo. prefix, fastest.
   Microsoft-shipped T-SQL functions (sys.fn_*, sys.dm_*) ARE objects
   in every database. Your UDFs live in a schema, need the prefix, and
   are the slowest of the three (unless inlined / iTVF).
   ============================================================ */
SELECT OBJECT_ID('GETDATE') AS Intrinsic_NoObjectId,             -- NULL: not an object
       OBJECT_ID('sys.fn_helpcollations') AS SystemTvf_ObjectId,  -- a number
       OBJECT_ID('dbo.fn_L15_Square') AS Udf_ObjectId;            -- a number
GO
SELECT type, type_desc, COUNT(*) AS BuiltInFunctions
FROM sys.all_objects
WHERE is_ms_shipped = 1 AND type IN ('FN', 'IF', 'TF')
GROUP BY type, type_desc
ORDER BY type;
-- expect 3 rows with dozens of functions each (sys.dm_exec_sql_text is an IF, for example)
GO
SELECT TOP (5) name, type_desc FROM sys.all_objects
WHERE is_ms_shipped = 1 AND type = 'IF' AND name LIKE 'dm_exec%' ORDER BY name;
GO


/* ============================================================
   6. CLEANUP
   ============================================================ */
DROP FUNCTION IF EXISTS dbo.fn_L15_Discount, dbo.fn_L15_DaysSince, dbo.fn_L15_Square,
                        dbo.fn_L15_BigOrders_Inline, dbo.fn_L15_BigOrders_Multi;
DROP PROCEDURE IF EXISTS dbo.usp_L15_Hello;
DROP TABLE IF EXISTS dbo.L15_Big;
GO
SELECT name FROM sys.objects WHERE name LIKE '%L15%';   -- expect 0 rows
GO
/* DONE. Next: Exercises.sql */
