/* ============================================================
   LEVEL 02 - DATA TYPES  |  Exercises.sql
   ------------------------------------------------------------
   Try each question FIRST, then compare with SOLUTIONS below.
   ============================================================ */

USE SQLPractice;
GO

/* ------------------------------------------------------------
   QUESTIONS
   ------------------------------------------------------------
   Q1.  Choose the best data type (write it as a comment) for:
        a) Aadhaar number (12 digits, never used in maths)
        b) Mobile number with country code (+91...)
        c) Product price in rupees with paise
        d) Is the account active?
        e) Customer name that may be in Hindi
        f) Person's age
        g) Exact time an order was placed (needs milliseconds)
        h) 2-letter ISO country code
        i) Very long product description (> 8000 chars)
        j) Auto-increment primary key

   Q2.  Predict, then run:  7/2,  7/2.0,  7%2,  -7/2,  CAST(7 AS DECIMAL(5,2))/2

   Q3.  Show DATALENGTH and LEN of 'SQL' stored as CHAR(8), VARCHAR(8), NVARCHAR(8).

   Q4.  Show today's date as  dd/MM/yyyy,  yyyy-MM-dd,  dd Mon yyyy  and  yyyyMMdd
        using CONVERT styles (no FORMAT).

   Q5.  Use TRY_CAST to convert '99', '99.5', 'abc' to INT in one SELECT.
        What do you get for each?

   Q6.  Prove that 0.1 + 0.2 = 0.3 is FALSE with FLOAT and TRUE with DECIMAL(3,1).

   Q7.  Declare a TINYINT variable and try to assign 300 inside TRY/CATCH.
        Print the error message. Then fix it with the right type.

   Q8.  List every column of every table in SQLPractice with its data type
        and max length, ordered by table then ordinal position.

   Q9.  Show what happens to '2025-12-31 23:59:59.999' when cast to
        DATETIME, DATETIME2(3) and SMALLDATETIME.

   Q10. Create a table dbo.GuidDemo (Id UNIQUEIDENTIFIER default NEWID() PK,
        Note VARCHAR(20)), insert 3 rows without giving the Id, select, drop it.

   Q11. Which is stored: 123.456 inserted into DECIMAL(6,2)?  And into INT?
        And 1e10 into INT (use TRY_CAST)?
   ------------------------------------------------------------ */

-- YOUR ANSWERS HERE










/* ============================================================
   SOLUTIONS
   ============================================================ */

-- Q1
/*
 a) CHAR(12)          - leading zeros matter, no arithmetic -> text, fixed length
 b) VARCHAR(15)       - '+' and variable length
 c) DECIMAL(10,2)     - exact money
 d) BIT
 e) NVARCHAR(100)     - Unicode
 f) TINYINT           - 0..255 is enough
 g) DATETIME2(3)      - millisecond precision, 7 bytes
 h) CHAR(2)
 i) NVARCHAR(MAX) / VARCHAR(MAX)
 j) INT IDENTITY(1,1) (BIGINT IDENTITY if > 2 billion rows expected)
*/

-- Q2
SELECT 7/2 AS A,          -- 3
       7/2.0 AS B,        -- 3.500000
       7%2 AS C,          -- 1
       -7/2 AS D,         -- -3  (truncates toward zero)
       CAST(7 AS DECIMAL(5,2))/2 AS E;   -- 3.500000
GO

-- Q3
SELECT DATALENGTH(CAST('SQL' AS CHAR(8)))      AS Char_Bytes,     -- 8
       LEN(CAST('SQL' AS CHAR(8)))             AS Char_Len,       -- 3
       DATALENGTH(CAST('SQL' AS VARCHAR(8)))   AS Varchar_Bytes,  -- 3
       DATALENGTH(CAST(N'SQL' AS NVARCHAR(8))) AS Nvarchar_Bytes; -- 6
GO

-- Q4
SELECT CONVERT(VARCHAR(10), GETDATE(), 103) AS ddMMyyyy,
       CONVERT(VARCHAR(10), GETDATE(), 23)  AS yyyyMMdd_dashes,
       CONVERT(VARCHAR(11), GETDATE(), 106) AS ddMonyyyy,
       CONVERT(VARCHAR(8),  GETDATE(), 112) AS yyyyMMdd;
GO

-- Q5
SELECT TRY_CAST('99' AS INT)   AS A,   -- 99
       TRY_CAST('99.5' AS INT) AS B,   -- NULL  ('99.5' is not an integer string)
       TRY_CAST('abc' AS INT)  AS C;   -- NULL
GO

-- Q6
SELECT CASE WHEN CAST(0.1 AS FLOAT) + CAST(0.2 AS FLOAT) = CAST(0.3 AS FLOAT) THEN 'TRUE' ELSE 'FALSE' END AS FloatTest,
       CASE WHEN CAST(0.1 AS DECIMAL(3,1)) + CAST(0.2 AS DECIMAL(3,1)) = CAST(0.3 AS DECIMAL(3,1)) THEN 'TRUE' ELSE 'FALSE' END AS DecimalTest;
GO

-- Q7
BEGIN TRY
    DECLARE @age TINYINT = 300;
END TRY
BEGIN CATCH
    PRINT 'Error: ' + ERROR_MESSAGE();
END CATCH
GO
DECLARE @age2 SMALLINT = 300;   -- fix
SELECT @age2 AS Fixed;
GO

-- Q8
SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, NUMERIC_PRECISION, NUMERIC_SCALE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'dbo'
ORDER BY TABLE_NAME, ORDINAL_POSITION;
GO

-- Q9
SELECT CAST('2025-12-31 23:59:59.999' AS DATETIME)      AS DT,    -- 2026-01-01 00:00:00.000
       CAST('2025-12-31 23:59:59.999' AS DATETIME2(3))  AS DT2,   -- 2025-12-31 23:59:59.999
       CAST('2025-12-31 23:59:59.999' AS SMALLDATETIME) AS SDT;   -- 2026-01-01 00:00:00 (rounds to minute)
GO

-- Q10
DROP TABLE IF EXISTS dbo.GuidDemo;
CREATE TABLE dbo.GuidDemo
(
    Id   UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    Note VARCHAR(20)
);
INSERT INTO dbo.GuidDemo (Note) VALUES ('one'), ('two'), ('three');
SELECT * FROM dbo.GuidDemo;
DROP TABLE dbo.GuidDemo;
GO

-- Q11
SELECT CAST(123.456 AS DECIMAL(6,2)) AS Dec_Rounds,     -- 123.46
       CAST(123.456 AS INT)          AS Int_Truncates,  -- 123
       TRY_CAST(1e10 AS INT)         AS TooBig_Null;    -- NULL (1e10 > INT max)
GO
