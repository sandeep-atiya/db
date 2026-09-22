/* ============================================================
   LEVEL 02 - DATA TYPES  |  01_Practice.sql
   ------------------------------------------------------------
   Topics : INT/BIGINT/DECIMAL/NUMERIC/FLOAT, CHAR/VARCHAR/NVARCHAR,
            DATE/DATETIME/DATETIME2/TIME, BIT, UNIQUEIDENTIFIER,
            CAST / CONVERT / TRY_CAST, implicit conversion.

   HOW TO PRACTICE: run block by block, predict the output first.
   This level creates ONE demo table (dbo.DataTypeDemo) in
   SQLPractice and drops it at the end.
   ============================================================ */

USE SQLPractice;
GO
DROP TABLE IF EXISTS dbo.DataTypeDemo;
GO


/* ============================================================
   1. ONE TABLE WITH (ALMOST) EVERY TYPE
   ============================================================ */
CREATE TABLE dbo.DataTypeDemo
(
    RecordID     INT IDENTITY(1,1) PRIMARY KEY,

    -- exact integers                    range                     bytes
    TinyVal      TINYINT,           -- 0 .. 255                     1
    SmallVal     SMALLINT,          -- -32,768 .. 32,767            2
    IntVal       INT,               -- +/- 2.1 billion              4
    BigVal       BIGINT,            -- +/- 9.2 quintillion          8

    -- exact decimals
    ExactPrice   DECIMAL(10,2),     -- 10 digits total, 2 after point (max 99,999,999.99)
    MoneyVal     MONEY,             -- 4 decimal places, 8 bytes

    -- approximate
    ApproxVal    FLOAT,             -- 8 bytes, ~15 significant digits, NOT exact

    -- boolean-ish
    IsActive     BIT,               -- 0 / 1 / NULL

    -- strings (1 byte per char)
    CountryCode  CHAR(2),           -- fixed length, padded with spaces
    UserName     VARCHAR(50),       -- variable length
    Notes        VARCHAR(MAX),      -- up to 2 GB

    -- unicode strings (2 bytes per char)
    LocalName    NVARCHAR(100),     -- Hindi / Chinese / emoji safe

    -- date & time
    BirthDate    DATE,              -- 3 bytes, date only
    ShiftStart   TIME(0),           -- time only, 0 fractional digits
    LegacyStamp  DATETIME,          -- 8 bytes, precision 3.33 ms (legacy)
    ModernStamp  DATETIME2(3),      -- 7 bytes, precision 1 ms (preferred)
    GlobalStamp  DATETIMEOFFSET(0), -- with time-zone offset

    -- other
    RowGuid      UNIQUEIDENTIFIER DEFAULT NEWID(),   -- 16-byte GUID
    FileData     VARBINARY(MAX)     -- raw bytes (files, images)
);
GO

INSERT INTO dbo.DataTypeDemo
    (TinyVal, SmallVal, IntVal, BigVal, ExactPrice, MoneyVal, ApproxVal, IsActive,
     CountryCode, UserName, Notes, LocalName,
     BirthDate, ShiftStart, LegacyStamp, ModernStamp, GlobalStamp, FileData)
VALUES
    (255, 32767, 2147483647, 9223372036854775807, 99999999.99, 1234.5678, 3.14159265358979, 1,
     'IN', 'arsalan', 'Any length text...', N'नमस्ते दुनिया',
     '1995-06-15', '08:30:00', '2025-01-01 23:59:59.999', '2025-01-01 23:59:59.999', '2025-01-01 10:00:00 +05:30',
     0x48656C6C6F);   -- "Hello" in hex

SELECT * FROM dbo.DataTypeDemo;
GO
-- LOOK CAREFULLY at LegacyStamp vs ModernStamp in the result: DATETIME rounded .999 to the NEXT DAY!


/* ============================================================
   2. INTEGERS
   ============================================================ */

-- 2a. Integer division truncates!  (classic interview trap)
SELECT 7 / 2          AS IntDivision,        -- 3
       7 / 2.0        AS DecimalDivision,    -- 3.500000
       7 % 2          AS Remainder,          -- 1
       CAST(7 AS DECIMAL(5,2)) / 2 AS CastFirst;   -- 3.50
GO

-- 2b. Overflow: a value bigger than the type can hold -> error
BEGIN TRY
    DECLARE @t TINYINT = 300;    -- max is 255
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO

BEGIN TRY
    SELECT 2147483647 + 1;       -- INT max + 1 -> overflow
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO
SELECT CAST(2147483647 AS BIGINT) + 1 AS FixedWithBigint;
GO


/* ============================================================
   3. DECIMAL vs FLOAT
   ============================================================ */

-- 3a. FLOAT is approximate: 0.1 + 0.2 is NOT 0.3
SELECT CASE WHEN CAST(0.1 AS FLOAT) + CAST(0.2 AS FLOAT) = CAST(0.3 AS FLOAT)
            THEN 'Equal' ELSE 'NOT equal' END AS FloatCompare,
       CONVERT(VARCHAR(30), CAST(0.1 AS FLOAT) + CAST(0.2 AS FLOAT), 3) AS Float17Digits;  -- shows the error digits
GO
-- 3b. DECIMAL is exact
SELECT CASE WHEN CAST(0.1 AS DECIMAL(5,2)) + CAST(0.2 AS DECIMAL(5,2)) = CAST(0.3 AS DECIMAL(5,2))
            THEN 'Equal' ELSE 'NOT equal' END AS DecimalCompare;
GO

-- 3c. Precision / scale: DECIMAL(p,s)  p = total digits, s = after the point
SELECT CAST(123.456 AS DECIMAL(6,2)) AS Rounded,     -- 123.46  (rounds)
       CAST(123.456 AS INT)          AS Truncated;   -- 123     (truncates)
GO

-- 3d. Too many digits before the point -> overflow
BEGIN TRY
    SELECT CAST(1000.00 AS DECIMAL(5,2));   -- 5 digits total, 2 after point -> max 999.99
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO

-- 3e. MONEY keeps 4 decimals and accepts currency symbols / commas
SELECT CAST('$1,234.5678' AS MONEY) AS MoneyVal;
GO


/* ============================================================
   4. STRINGS: CHAR vs VARCHAR vs NVARCHAR
   ============================================================ */

-- 4a. Storage: DATALENGTH = bytes on disk, LEN = characters without trailing spaces
SELECT DATALENGTH(CAST('abc' AS CHAR(10)))      AS Char10_Bytes,      -- 10 (padded)
       DATALENGTH(CAST('abc' AS VARCHAR(10)))   AS Varchar10_Bytes,   -- 3
       DATALENGTH(CAST(N'abc' AS NVARCHAR(10))) AS Nvarchar10_Bytes,  -- 6 (2 bytes/char)
       LEN(CAST('abc' AS CHAR(10)))             AS Char10_Len;        -- 3 (LEN ignores trailing spaces)
GO

-- 4b. CHAR padding is visible when you concatenate
SELECT '[' + CAST('abc' AS CHAR(10)) + ']' AS PaddedChar,
       '[' + CAST('abc' AS VARCHAR(10)) + ']' AS Varchar;
GO

-- 4c. The N prefix. Without it, non-Latin text is destroyed.
SELECT 'नमस्ते'  AS WithoutN,   -- ?????? (converted through the code page)
       N'नमस्ते' AS WithN;      -- correct
GO
-- (If both look wrong in your editor, the .sql file was opened as ANSI - re-open as UTF-8.)

-- 4d. Unicode code points: NCHAR(code) and UNICODE(char)
SELECT NCHAR(0x0928) + NCHAR(0x092E) AS BuiltFromCodes,   -- "नम"
       UNICODE(N'न') AS CodeOfNa,
       NCHAR(9731)   AS Snowman;
GO

-- 4e. VARCHAR without length = 1 in CAST/DECLARE, 30 in CONVERT.  ALWAYS write the length!
DECLARE @s VARCHAR = 'Hello World';
SELECT @s AS LostData, CAST('Hello World' AS VARCHAR) AS AlsoOne, CONVERT(VARCHAR, 'Hello World, this is a long text > 30') AS Thirty;
GO


/* ============================================================
   5. DATE AND TIME
   ============================================================ */

-- 5a. Current date/time functions
SELECT GETDATE()            AS Now_DATETIME,
       SYSDATETIME()        AS Now_DATETIME2,
       SYSDATETIMEOFFSET()  AS Now_WithOffset,
       GETUTCDATE()         AS Now_UTC,
       CAST(GETDATE() AS DATE) AS Today_DateOnly,
       CAST(GETDATE() AS TIME(0)) AS Now_TimeOnly;
GO

-- 5b. DATETIME rounds to 0 / 3 / 7 milliseconds  -> the .999 trap
SELECT CAST('2025-01-01 23:59:59.999' AS DATETIME)     AS Datetime_NextDay,   -- 2025-01-02 00:00:00.000 !
       CAST('2025-01-01 23:59:59.999' AS DATETIME2(3)) AS Datetime2_Exact,    -- 2025-01-01 23:59:59.999
       CAST('2025-01-01 23:59:59.998' AS DATETIME)     AS Datetime_998;       -- 23:59:59.997
GO
-- Lesson: filter dates with  >= '20250101' AND < '20250102'   (never BETWEEN ... '23:59:59.999')

-- 5c. Safe vs unsafe date literals.  DATEFORMAT / language change how strings are read.
SET DATEFORMAT dmy;
SELECT CAST('02/03/2025' AS DATE) AS dmy_Reads_2March;
SET DATEFORMAT mdy;   -- default for us_english
SELECT CAST('02/03/2025' AS DATE) AS mdy_Reads_3Feb;
GO
-- Even 'yyyy-mm-dd' is unsafe for DATETIME (not for DATE / DATETIME2):
SET DATEFORMAT ydm;
SELECT CAST('2025-03-02' AS DATETIME) AS Datetime_Reads_3Feb,
       CAST('2025-03-02' AS DATE)     AS Date_Reads_2March;
SET DATEFORMAT mdy;
GO
-- ALWAYS SAFE:  'yyyymmdd'   and   'yyyy-mm-ddThh:mi:ss'
SELECT CAST('20250302' AS DATETIME) AS Safe1, CAST('2025-03-02T14:30:00' AS DATETIME) AS Safe2;
GO

-- 5d. Time zones with DATETIMEOFFSET
SELECT SYSDATETIMEOFFSET()                                  AS ServerLocal,
       SWITCHOFFSET(SYSDATETIMEOFFSET(), '+05:30')          AS India,
       SWITCHOFFSET(SYSDATETIMEOFFSET(), '+00:00')          AS UTC,
       CAST('2025-01-01 10:00:00 +05:30' AS DATETIMEOFFSET) AT TIME ZONE 'UTC' AS ConvertedToUTC;
GO


/* ============================================================
   6. BIT, UNIQUEIDENTIFIER, VARBINARY
   ============================================================ */

-- 6a. BIT accepts 0/1, the strings 'true'/'false', and any non-zero number becomes 1
SELECT CAST(1 AS BIT) AS One, CAST(0 AS BIT) AS Zero, CAST('true' AS BIT) AS StrTrue,
       CAST('false' AS BIT) AS StrFalse, CAST(5 AS BIT) AS Five_Becomes_1;
GO

-- 6b. GUIDs: NEWID() is random, NEWSEQUENTIALID() (only as a column DEFAULT) is increasing
SELECT NEWID() AS RandomGuid1, NEWID() AS RandomGuid2;
SELECT RowGuid FROM dbo.DataTypeDemo;
GO

-- 6c. VARBINARY <-> text
SELECT FileData                              AS RawBytes,
       CAST(FileData AS VARCHAR(20))         AS AsText,          -- Hello
       CAST('Hello' AS VARBINARY(20))        AS TextToBytes
FROM dbo.DataTypeDemo;
GO


/* ============================================================
   7. CONVERSION: CAST, CONVERT, TRY_CAST, FORMAT, implicit
   ============================================================ */

-- 7a. CAST (ANSI) vs CONVERT (SQL Server, has a STYLE for dates)
SELECT CAST(GETDATE() AS VARCHAR(30))            AS Cast_Default,
       CONVERT(VARCHAR(10), GETDATE(), 103)      AS Style103_ddMMyyyy,
       CONVERT(VARCHAR(10), GETDATE(), 101)      AS Style101_MMddyyyy,
       CONVERT(VARCHAR(10), GETDATE(), 23)       AS Style23_ISO,
       CONVERT(VARCHAR(8),  GETDATE(), 112)      AS Style112_yyyyMMdd,
       CONVERT(VARCHAR(19), GETDATE(), 120)      AS Style120_ODBC,
       CONVERT(VARCHAR(11), GETDATE(), 106)      AS Style106_ddMonyyyy;
GO

-- 7b. FORMAT: .NET format strings, very flexible, but SLOW on large result sets
SELECT FORMAT(GETDATE(), 'dd-MMM-yyyy')      AS Pretty,
       FORMAT(GETDATE(), 'dddd, dd MMMM yyyy') AS Long,
       FORMAT(1234567.891, 'N2')             AS Number,      -- 1,234,567.89
       FORMAT(0.256, 'P1')                   AS Pct,         -- 25.6%  (alias "Percent" is a reserved word!)
       FORMAT(1234567.891, 'C', 'en-IN')     AS IndianCurrency;
GO

-- 7c. String -> number/date. TRY_CAST returns NULL instead of failing.
SELECT CAST('123' AS INT)              AS Ok,
       TRY_CAST('12abc' AS INT)        AS Bad_ReturnsNull,
       TRY_CAST('2025-13-01' AS DATE)  AS BadDate_Null,
       TRY_CONVERT(DATE, '15/06/1995', 103) AS WithStyle;
GO
BEGIN TRY
    SELECT CAST('12abc' AS INT);       -- plain CAST fails
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO

-- 7d. Implicit conversion & data type precedence (INT beats VARCHAR)
SELECT 1 + '1'      AS IntPlusString,   -- 2   ('1' converted to INT)
       '1' + '1'    AS StringPlusString, -- 11  (concatenation)
       CONCAT(1, '1') AS Concat;         -- 11  (CONCAT converts everything to string)
GO
BEGIN TRY
    SELECT 1 + 'a';                     -- 'a' cannot become INT -> error
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO
-- Mixed numeric types: result takes the "bigger" type
SELECT 1 + 1.5 AS IntPlusDecimal, 10 / 4 AS IntInt, 10 / 4.0 AS IntDecimal, 10.0 / 4 AS DecimalInt;
GO

-- 7e. Numbers -> strings for display
SELECT STR(3.14159, 6, 2) AS Str, CAST(3.14159 AS VARCHAR(10)) AS Cast, FORMAT(3.14159, '0.00') AS Fmt;
GO


/* ============================================================
   8. METADATA: what types does my table use?
   ============================================================ */
SELECT c.name AS ColumnName, t.name AS DataType, c.max_length AS MaxBytes, c.precision, c.scale, c.is_nullable
FROM sys.columns c
JOIN sys.types   t ON t.user_type_id = c.user_type_id
WHERE c.object_id = OBJECT_ID('dbo.DataTypeDemo')
ORDER BY c.column_id;
GO
-- max_length = -1 means MAX;  NVARCHAR(100) shows 200 bytes.

-- All built-in types available on this server
SELECT name, max_length, precision, scale FROM sys.types WHERE is_user_defined = 0 ORDER BY name;
GO


/* ============================================================
   9. CLEANUP
   ============================================================ */
DROP TABLE IF EXISTS dbo.DataTypeDemo;
GO
/* DONE. Next: Exercises.sql */
