/* ============================================================
   LEVEL 15 - USER DEFINED FUNCTIONS  |  02_Practice_Rules_and_Schemabinding.sql
   ------------------------------------------------------------
   Topics : rules & limitations of functions (no side effects:
            no INSERT into permanent tables, no TRY/CATCH, no
            THROW, no dynamic SQL, no temp tables, no NEWID/RAND,
            no EXEC of procedures; GETDATE is allowed),
            deterministic vs non-deterministic functions,
            WITH SCHEMABINDING.
   HOW TO PRACTICE: run block by block, predict the output first.
   Uses a 200,000 row helper table dbo.L15_Big (dropped at the end).
   Next file: 03_Practice_Performance_and_Metadata.sql
   ============================================================ */

USE SQLPractice;
GO
-- sqlcmd connects with QUOTED_IDENTIFIER OFF (SSMS uses ON). Persisted computed
-- columns, filtered indexes and indexed views REQUIRE it ON, so set it explicitly.
SET QUOTED_IDENTIFIER ON;
GO
DROP FUNCTION IF EXISTS dbo.fn_L15_SafeDivide, dbo.fn_L15_CallsProc, dbo.fn_L15_DaysSince,
                        dbo.fn_L15_Square, dbo.fn_L15_SquareSB, dbo.fn_L15_Discount,
                        dbo.fn_L15_DiscountSB, dbo.fn_L15_BigCountSB;
DROP PROCEDURE IF EXISTS dbo.usp_L15_Hello;
DROP TABLE IF EXISTS dbo.L15_Big;
GO

-- Helper: 200,000 rows. GENERATE_SERIES is SQL 2022+ (older: a ROW_NUMBER numbers CTE).
-- ISNULL(...) makes the column NOT NULL so it can be a PRIMARY KEY.
SELECT ISNULL(CAST(s.value AS INT), 0)                       AS RowID,
       s.value % 1000 + 1                                     AS CustomerID,     -- 1..1000
       CAST((s.value * 37) % 100000 + 100 AS DECIMAL(12,2))   AS Amount,         -- 100 .. 100099
       DATEADD(DAY, s.value % 1096, '2023-01-01')             AS OrderDate       -- 3 years
INTO dbo.L15_Big
FROM GENERATE_SERIES(1, 200000) AS s;
ALTER TABLE dbo.L15_Big ADD CONSTRAINT PK_L15_Big PRIMARY KEY (RowID);
SELECT COUNT(*) AS Rows FROM dbo.L15_Big;    -- 200000
GO


/* ============================================================
   1. RULES & LIMITATIONS: a function must have NO SIDE EFFECTS
   ============================================================
   A function may be called once per row, in any order, any number
   of times, so SQL Server forbids anything that changes state.
   The errors below are COMPILE errors of CREATE FUNCTION, so each
   CREATE is sent as dynamic SQL inside TRY/CATCH to show the message.
   ============================================================ */

-- 1a. No INSERT / UPDATE / DELETE on permanent tables  (error 443)
BEGIN TRY
    EXEC('CREATE FUNCTION dbo.fn_L15_Bad() RETURNS INT AS
          BEGIN
              INSERT INTO dbo.Departments (DepartmentID, DepartmentName) VALUES (99, ''X'');
              RETURN 1;
          END');
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO

-- 1b. No TRY / CATCH inside a function
BEGIN TRY
    EXEC('CREATE FUNCTION dbo.fn_L15_Bad() RETURNS INT AS
          BEGIN
              DECLARE @x INT;
              BEGIN TRY SET @x = 1 / 0; END TRY BEGIN CATCH SET @x = -1; END CATCH
              RETURN @x;
          END');
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO

-- 1c. No non-deterministic "side-effecting" built-ins: NEWID(), RAND()
BEGIN TRY
    EXEC('CREATE FUNCTION dbo.fn_L15_Bad() RETURNS UNIQUEIDENTIFIER AS
          BEGIN RETURN NEWID(); END');
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO
BEGIN TRY
    EXEC('CREATE FUNCTION dbo.fn_L15_Bad() RETURNS FLOAT AS
          BEGIN RETURN RAND(); END');
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO
-- Workaround: generate the random value OUTSIDE and pass it in as a parameter
-- (or read it from a view: CREATE VIEW dbo.vw_NewID AS SELECT NEWID() AS ID  - the view is allowed).

-- 1d. No dynamic SQL, no THROW / RAISERROR inside a function
BEGIN TRY
    EXEC('CREATE FUNCTION dbo.fn_L15_Bad() RETURNS INT AS
          BEGIN EXEC(''SELECT 1''); RETURN 1; END');
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO
BEGIN TRY
    EXEC('CREATE FUNCTION dbo.fn_L15_Bad(@x INT) RETURNS INT AS
          BEGIN IF @x < 0 THROW 50000, ''negative'', 1; RETURN @x; END');
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO
-- Trick used in practice to "raise" an error from a function: force a conversion failure
-- whose message contains your text.
CREATE FUNCTION dbo.fn_L15_SafeDivide (@a DECIMAL(12,2), @b DECIMAL(12,2))
RETURNS DECIMAL(12,2)
AS
BEGIN
    IF @b = 0
        RETURN CAST('fn_L15_SafeDivide: divisor is zero' AS INT);   -- never a valid INT -> error
    RETURN @a / @b;
END
GO
SELECT dbo.fn_L15_SafeDivide(10, 4) AS Ok;      -- 2.50
BEGIN TRY
    SELECT dbo.fn_L15_SafeDivide(10, 0) AS Boom;
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();   -- ... converting 'fn_L15_SafeDivide: divisor is zero' ...
END CATCH
GO

-- 1e. No temporary tables (#t) - but TABLE VARIABLES are fine
BEGIN TRY
    EXEC('CREATE FUNCTION dbo.fn_L15_Bad() RETURNS INT AS
          BEGIN CREATE TABLE #t (x INT); RETURN 1; END');
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO

-- 1f. EXEC of a stored procedure: CREATE succeeds (not checked at compile time) ...
CREATE PROCEDURE dbo.usp_L15_Hello AS SELECT 'hello' AS Msg;
GO
CREATE FUNCTION dbo.fn_L15_CallsProc () RETURNS INT
AS
BEGIN
    EXEC dbo.usp_L15_Hello;      -- compiles ...
    RETURN 1;
END
GO
-- ... but it FAILS AT RUNTIME (error 557). Only functions / some extended procs may be executed.
BEGIN TRY
    SELECT dbo.fn_L15_CallsProc() AS Result;
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO

-- 1g. GETDATE() / SYSDATETIME() ARE allowed (since SQL 2005)
CREATE FUNCTION dbo.fn_L15_DaysSince (@Date DATE) RETURNS INT
AS
BEGIN
    RETURN DATEDIFF(DAY, @Date, GETDATE());
END
GO
SELECT OrderID, OrderDate, dbo.fn_L15_DaysSince(OrderDate) AS DaysAgo
FROM dbo.Orders WHERE OrderID IN (1001, 1019);
-- expect 2 rows; DaysAgo grows every day (1001 is 2025-01-05, 1019 is 2025-09-05)
GO


/* ============================================================
   2. DETERMINISTIC vs NON-DETERMINISTIC, WITH SCHEMABINDING
   ============================================================
   Deterministic  = same input -> ALWAYS same output (LEN, ABS, @x*@x)
   Non-determ.    = may differ per call (GETDATE, NEWID, anything reading a table)
   SQL Server only TRUSTS a UDF to be deterministic when it is
   created WITH SCHEMABINDING (it then knows the body cannot change).
   Needed for: persisted computed columns, indexed views, and it also
   lets the optimizer skip the "this UDF might read data" spool.
   ============================================================ */

-- 2a. Same body, with and without SCHEMABINDING
CREATE FUNCTION dbo.fn_L15_Square (@x INT) RETURNS INT
AS BEGIN RETURN @x * @x; END
GO
CREATE FUNCTION dbo.fn_L15_SquareSB (@x INT) RETURNS INT
WITH SCHEMABINDING
AS BEGIN RETURN @x * @x; END
GO
SELECT o.name,
       OBJECTPROPERTY(o.object_id, 'IsDeterministic')     AS IsDeterministic,
       OBJECTPROPERTY(o.object_id, 'IsSchemaBound')       AS IsSchemaBound,
       OBJECTPROPERTYEX(o.object_id, 'UserDataAccess')    AS UserDataAccess,   -- 1 = "might read tables"
       OBJECTPROPERTYEX(o.object_id, 'SystemDataAccess')  AS SystemDataAccess
FROM sys.objects o
WHERE o.name IN ('fn_L15_Square', 'fn_L15_SquareSB', 'fn_L15_DaysSince')
ORDER BY o.name;
-- expect: fn_L15_DaysSince 0/0/1/1 (GETDATE -> never deterministic)
--         fn_L15_Square    0/0/1/1 (same body, but NOT trusted without SCHEMABINDING!)
--         fn_L15_SquareSB  1/1/0/0
GO

-- 2b. Why it matters: a PERSISTED computed column needs a deterministic expression
CREATE FUNCTION dbo.fn_L15_Discount (@Amount DECIMAL(12,2)) RETURNS DECIMAL(12,2)
AS BEGIN RETURN CASE WHEN @Amount >= 50000 THEN @Amount * 0.90 ELSE @Amount END; END
GO
CREATE FUNCTION dbo.fn_L15_DiscountSB (@Amount DECIMAL(12,2)) RETURNS DECIMAL(12,2)
WITH SCHEMABINDING
AS BEGIN RETURN CASE WHEN @Amount >= 50000 THEN @Amount * 0.90 ELSE @Amount END; END
GO
BEGIN TRY
    ALTER TABLE dbo.L15_Big ADD DiscountAmt AS dbo.fn_L15_Discount(Amount) PERSISTED;
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();     -- non-deterministic -> cannot be persisted
END CATCH
GO
ALTER TABLE dbo.L15_Big ADD DiscountAmt AS dbo.fn_L15_DiscountSB(Amount) PERSISTED;   -- OK
GO   -- (new column must exist before the next batch is compiled)
SELECT TOP (3) RowID, Amount, DiscountAmt FROM dbo.L15_Big ORDER BY Amount DESC;
-- expect Amount 100099.00 -> 90089.10 (10% off), etc.
ALTER TABLE dbo.L15_Big DROP COLUMN DiscountAmt;
GO

-- 2c. SCHEMABINDING also LOCKS the objects the function reads: names must be two-part,
--     and the referenced table cannot be altered/dropped while the function exists.
BEGIN TRY
    EXEC('CREATE FUNCTION dbo.fn_L15_BigCountSB () RETURNS INT WITH SCHEMABINDING AS
          BEGIN RETURN (SELECT COUNT(*) FROM L15_Big); END');       -- one-part name
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO
CREATE FUNCTION dbo.fn_L15_BigCountSB () RETURNS INT
WITH SCHEMABINDING
AS BEGIN RETURN (SELECT COUNT(*) FROM dbo.L15_Big); END               -- two-part name: OK
GO
BEGIN TRY
    ALTER TABLE dbo.L15_Big DROP COLUMN OrderDate;    -- blocked by the schemabound function
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO
SELECT dbo.fn_L15_BigCountSB() AS BigRows;    -- 200000
DROP FUNCTION dbo.fn_L15_BigCountSB;          -- now the table is free again
GO
-- Summary: write WITH SCHEMABINDING on every function that does not need to change often -
-- it is "free" correctness information for the optimizer.


/* ============================================================
   3. CLEANUP
   ============================================================ */
DROP FUNCTION IF EXISTS dbo.fn_L15_SafeDivide, dbo.fn_L15_CallsProc, dbo.fn_L15_DaysSince,
                        dbo.fn_L15_Square, dbo.fn_L15_SquareSB, dbo.fn_L15_Discount,
                        dbo.fn_L15_DiscountSB, dbo.fn_L15_BigCountSB;
DROP PROCEDURE IF EXISTS dbo.usp_L15_Hello;
DROP TABLE IF EXISTS dbo.L15_Big;
GO
SELECT name FROM sys.objects WHERE name LIKE '%L15%';   -- expect 0 rows
GO
/* DONE. Next: 03_Practice_Performance_and_Metadata.sql */
