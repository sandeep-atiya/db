/* ============================================================
   LEVEL 06 - FUNCTIONS  |  02_Practice_Date.sql
   ------------------------------------------------------------
   Topics : GETDATE / SYSDATETIME / SYSUTCDATETIME, DATEADD,
            DATEDIFF / DATEDIFF_BIG, DATEPART / DATENAME,
            YEAR / MONTH / DAY, EOMONTH, DATEFROMPARTS, DATETRUNC,
            ISDATE, first/last day recipes, correct age calculation,
            business days, group orders by month, FORMAT for dates,
            @@DATEFIRST / SET DATEFIRST, SARGable date ranges.
   HOW TO PRACTICE: run block by block, predict the output first.
   Results that depend on "today" are marked (varies).
   Safe date literals used everywhere: 'yyyymmdd' or 'yyyy-mm-dd' on DATE.
   ============================================================ */

USE SQLPractice;
GO


/* ==== 1. WHAT TIME IS IT?  GETDATE / SYSDATETIME / SYSUTCDATETIME ==== */

-- 1a. GETDATE() returns DATETIME (3.33 ms). SYSDATETIME() returns DATETIME2(7) (100 ns).
--     The *UTC* versions return the server clock in UTC (no time zone offset applied).
SELECT GETDATE()          AS Now_Datetime,        -- (varies)
       SYSDATETIME()      AS Now_Datetime2,
       GETUTCDATE()       AS Utc_Datetime,
       SYSUTCDATETIME()   AS Utc_Datetime2,
       SYSDATETIMEOFFSET() AS Now_WithOffset;     -- shows the server time zone (+05:30 in India)
GO

-- 1b. Proof of the return types
SELECT SQL_VARIANT_PROPERTY(GETDATE(), 'BaseType')     AS GetDate_Type,      -- datetime
       SQL_VARIANT_PROPERTY(SYSDATETIME(), 'BaseType') AS SysDateTime_Type;  -- datetime2
GO

-- 1c. Today as a DATE (strip the time) and the current time only
SELECT CAST(GETDATE() AS DATE) AS Today, CAST(GETDATE() AS TIME(0)) AS TimeNow;   -- (varies)
GO


/* ==== 2. DATEADD  (move a date forward / backward) ==== */

-- 2a. DATEADD(part, number, date). Negative number = go back.
--     (A string literal is treated as DATETIME, so every result below shows 00:00:00.000.)
SELECT DATEADD(day,   30, '20250105') AS Plus30Days,     -- 2025-02-04
       DATEADD(month,  1, '20250105') AS Plus1Month,     -- 2025-02-05
       DATEADD(year,  -1, '20250105') AS Minus1Year,     -- 2024-01-05
       DATEADD(hour,   5, '20250105') AS Plus5Hours,     -- 2025-01-05 05:00:00.000
       DATEADD(week,   2, '20250105') AS Plus2Weeks;     -- 2025-01-19
GO

-- 2b. Month arithmetic is CLAMPED to the last valid day (no overflow into the next month).
SELECT DATEADD(month, 1, CAST('20250131' AS DATE)) AS Jan31_Plus1M,   -- 2025-02-28
       DATEADD(month, 1, CAST('20240131' AS DATE)) AS LeapYear,       -- 2024-02-29
       DATEADD(year,  1, CAST('20240229' AS DATE)) AS Feb29_Plus1Y;   -- 2025-02-28
GO

-- 2c. Real data: expected delivery = order date + 7 days; payment due = end of next month
SELECT OrderID, OrderDate,
       DATEADD(day, 7, OrderDate)   AS DeliveryDate,   -- 1001 -> 2025-01-12
       DATEADD(month, 1, OrderDate) AS NextMonth       -- 1001 -> 2025-02-05
FROM dbo.Orders
WHERE OrderID <= 1003;
GO


/* ==== 3. DATEDIFF and DATEDIFF_BIG ==== */

-- 3a. DATEDIFF(part, start, end) counts how many PART BOUNDARIES are crossed.
--     It is NOT "full units elapsed". This is the source of every DATEDIFF bug.
SELECT DATEDIFF(day,   '20250105', '20250203') AS Days,           -- 29
       DATEDIFF(month, '20250131', '20250201') AS MonthsTrap,     -- 1  (only 1 day apart, but a month boundary was crossed!)
       DATEDIFF(year,  '20241231', '20250101') AS YearsTrap,      -- 1  (same trap)
       DATEDIFF(week,  '20250101', '20250131') AS Weeks,          -- 4  (Sunday boundaries crossed)
       DATEDIFF(day,   '20250203', '20250105') AS NegativeOK;     -- -29 (end before start = negative)
GO

-- 3b. Real data: how many days between order and today (varies), and days between two orders
SELECT OrderID, OrderDate,
       DATEDIFF(day, OrderDate, CAST('20251231' AS DATE)) AS DaysToYearEnd    -- 1001 -> 360
FROM dbo.Orders
WHERE OrderID IN (1001, 1019);   -- 1019 -> 117
GO

-- 3c. DATEDIFF returns INT. Big spans in small units overflow -> use DATEDIFF_BIG (2016+).
BEGIN TRY
    SELECT DATEDIFF(second, '20000101', '21000101') AS SecondsIn100Years;   -- > 2.1 billion -> overflow
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO
SELECT DATEDIFF_BIG(second, '20000101', '21000101')      AS SecondsIn100Years,   -- 3155760000
       DATEDIFF_BIG(millisecond, '19000101', '20250101') AS MsSince1900;         -- 3944678400000
GO


/* ==== 4. DATEPART / DATENAME / YEAR / MONTH / DAY  (take a date apart) ==== */

-- 4a. DATEPART returns a NUMBER, DATENAME returns a STRING (month / weekday names).
DECLARE @d DATE = '20250830';   -- order 1018, a Saturday
SELECT DATEPART(year, @d)      AS Yr,        -- 2025
       DATEPART(quarter, @d)   AS Qtr,       -- 3
       DATEPART(month, @d)     AS Mth,       -- 8
       DATEPART(day, @d)       AS Dy,        -- 30
       DATEPART(dayofyear, @d) AS DayOfYear, -- 242
       DATEPART(week, @d)      AS WeekNo,    -- 35
       DATEPART(iso_week, @d)  AS IsoWeek,   -- 35
       DATEPART(weekday, @d)   AS WeekdayNo, -- 7 with default DATEFIRST 7 (Sunday=1 ... Saturday=7)
       DATENAME(month, @d)     AS MonthName, -- August
       DATENAME(weekday, @d)   AS DayName;   -- Saturday
GO

-- 4b. YEAR(), MONTH(), DAY() are short forms of DATEPART.
SELECT OrderID, OrderDate, YEAR(OrderDate) AS Yr, MONTH(OrderDate) AS Mth, DAY(OrderDate) AS Dy,
       DATENAME(month, OrderDate) AS MonthName, DATENAME(weekday, OrderDate) AS DayName
FROM dbo.Orders
WHERE OrderID <= 1003;   -- 1001 = January, Sunday ; 1003 = January, Monday
GO

-- 4c. Time parts work on DATETIME / DATETIME2
SELECT DATEPART(hour, '2025-01-05T14:35:59') AS Hr, DATEPART(minute, '2025-01-05T14:35:59') AS Mi;   -- 14, 35
GO


/* ==== 5. EOMONTH and DATEFROMPARTS  (build dates) ==== */

-- 5a. EOMONTH(date [, months_to_add]) = last day of that month. Leap years handled.
SELECT EOMONTH('20250214')      AS EndFeb2025,     -- 2025-02-28
       EOMONTH('20240214')      AS EndFeb2024,     -- 2024-02-29 (leap)
       EOMONTH('20250214', 1)   AS EndNextMonth,   -- 2025-03-31
       EOMONTH('20250214', -1)  AS EndPrevMonth;   -- 2025-01-31
GO

-- 5b. DATEFROMPARTS(y, m, d) builds a DATE from numbers - no string conversion, no DATEFORMAT risk.
SELECT DATEFROMPARTS(2025, 1, 5)                      AS Built,      -- 2025-01-05
       DATETIMEFROMPARTS(2025, 1, 5, 14, 30, 0, 0)    AS BuiltDT,    -- 2025-01-05 14:30:00.000
       DATEFROMPARTS(YEAR(GETDATE()), 12, 31)         AS ThisYearEnd; -- (varies) 31 Dec of current year
GO
-- Invalid parts are an ERROR (not NULL):
BEGIN TRY
    SELECT DATEFROMPARTS(2025, 2, 30) AS NoSuchDay;
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO


/* ==== 6. DATETRUNC  (2022+)  - cut a date down to a boundary ==== */

-- DATETRUNC(part, date) keeps the data type and zeroes everything smaller than PART.
SELECT DATETRUNC(year,    CAST('20250830' AS DATE)) AS YearStart,     -- 2025-01-01
       DATETRUNC(quarter, CAST('20250830' AS DATE)) AS QuarterStart,  -- 2025-07-01
       DATETRUNC(month,   CAST('20250830' AS DATE)) AS MonthStart,    -- 2025-08-01
       DATETRUNC(week,    CAST('20250830' AS DATE)) AS WeekStart,     -- 2025-08-24 (Sunday, because DATEFIRST = 7)
       DATETRUNC(hour, CAST('2025-08-30T14:35:59' AS DATETIME2(0))) AS HourStart;   -- 2025-08-30 14:00:00
GO


/* ==== 7. ISDATE  (is this string a date?) ==== */

-- ISDATE returns 1/0. It depends on SET DATEFORMAT / language, so prefer TRY_CAST / TRY_CONVERT (Level 02).
SELECT ISDATE('20250105')   AS Iso,       -- 1
       ISDATE('2025-02-30') AS Feb30,     -- 0
       ISDATE('hello')      AS Text,      -- 0
       ISDATE('13/01/2025') AS Ambiguous, -- 0 under mdy (month 13 does not exist)
       TRY_CAST('2025-02-30' AS DATE) AS TryCastGivesNull;   -- NULL
GO


/* ==== 8. FIRST / LAST DAY RECIPES  (memorise these) ==== */

DECLARE @d DATE = '20250814';
SELECT @d                                            AS AnyDate,
       DATEFROMPARTS(YEAR(@d), MONTH(@d), 1)         AS FirstOfMonth_A,  -- 2025-08-01
       DATEADD(day, 1, EOMONTH(@d, -1))              AS FirstOfMonth_B,  -- 2025-08-01
       DATETRUNC(month, @d)                          AS FirstOfMonth_C,  -- 2025-08-01 (2022+)
       DATEADD(month, DATEDIFF(month, 0, @d), 0)     AS FirstOfMonth_Old,-- 2025-08-01 00:00:00.000 (classic pre-2012 trick, returns DATETIME)
       EOMONTH(@d)                                   AS LastOfMonth,     -- 2025-08-31
       DATEADD(day, 1, EOMONTH(@d))                  AS FirstOfNextMonth,-- 2025-09-01
       DATEFROMPARTS(YEAR(@d), 1, 1)                 AS FirstOfYear,     -- 2025-01-01
       DATEFROMPARTS(YEAR(@d), 12, 31)               AS LastOfYear,      -- 2025-12-31
       DATETRUNC(year, @d)                           AS FirstOfYear_C;   -- 2025-01-01
GO


/* ==== 9. AGE / YEARS OF SERVICE - the DATEDIFF(year) trap ==== */

-- 9a. THE TRAP: born 31 Dec 2000, "today" 1 Jan 2025 -> DATEDIFF says 25, the person is 24.
DECLARE @dob DATE = '20001231', @today DATE = '20250101';
SELECT DATEDIFF(year, @dob, @today) AS WrongAge,   -- 25
       -- Correct: subtract 1 if this year's birthday has not happened yet
       DATEDIFF(year, @dob, @today)
         - CASE WHEN DATEADD(year, DATEDIFF(year, @dob, @today), @dob) > @today THEN 1 ELSE 0 END AS CorrectAge,   -- 24
       -- Alternative "yyyymmdd integer" trick: (20250101 - 20001231) / 10000
       (CAST(CONVERT(CHAR(8), @today, 112) AS INT) - CAST(CONVERT(CHAR(8), @dob, 112) AS INT)) / 10000 AS CorrectAge2;   -- 24
GO

-- 9b. Real data: completed years of service as of 30 Jun 2025. Compare the two columns.
DECLARE @asof DATE = '20250630';
SELECT EmployeeName, HireDate,
       DATEDIFF(year, HireDate, @asof) AS NaiveYears,
       DATEDIFF(year, HireDate, @asof)
         - CASE WHEN DATEADD(year, DATEDIFF(year, HireDate, @asof), HireDate) > @asof THEN 1 ELSE 0 END AS CompletedYears
FROM dbo.Employees
WHERE EmployeeID IN (101, 103, 105, 106)
ORDER BY EmployeeID;
-- Rahul  2022-01-10 -> 3 / 3      Priya 2021-07-20 -> 4 / 3 (anniversary not yet reached)
-- Ravi   2022-11-01 -> 3 / 2      Sneha 2020-05-18 -> 5 / 5
GO


/* ==== 10. BUSINESS DAYS (Mon-Fri) BETWEEN TWO DATES ==== */

-- 10a. Formula: all days - 2 per full week - fix-ups if the range starts on Sunday / ends on Saturday.
--      DATEDIFF(week) always counts Sunday boundaries (SET DATEFIRST does not affect it).
DECLARE @s DATE = '20250101', @e DATE = '20250131';   -- Wed .. Fri
SELECT DATEDIFF(day, @s, @e) + 1 AS CalendarDays,     -- 31
       (DATEDIFF(day, @s, @e) + 1)
       - (DATEDIFF(week, @s, @e) * 2)
       - CASE WHEN DATENAME(weekday, @s) = 'Sunday'   THEN 1 ELSE 0 END
       - CASE WHEN DATENAME(weekday, @e) = 'Saturday' THEN 1 ELSE 0 END AS BusinessDays;   -- 23
GO

-- 10b. Cross-check by listing the days with GENERATE_SERIES (2022+) and counting weekdays.
--      (Holidays would need a holiday table - not covered here.)
DECLARE @s DATE = '20250101', @e DATE = '20250131';
SELECT COUNT(*) AS BusinessDays   -- 23
FROM GENERATE_SERIES(0, DATEDIFF(day, @s, @e)) AS g
CROSS APPLY (SELECT DATEADD(day, g.value, @s) AS D) AS x
WHERE DATENAME(weekday, x.D) NOT IN ('Saturday', 'Sunday');
GO


/* ==== 11. GROUP ORDERS BY MONTH  (YYYY-MM) ==== */

-- 11a. Three ways to get a 'yyyy-MM' bucket. CONVERT(CHAR(7), d, 120) is the fastest; FORMAT is the slowest.
SELECT CONVERT(CHAR(7), OrderDate, 120) AS YearMonth,
       COUNT(*)                         AS Orders,
       SUM(TotalAmount)                 AS Revenue
FROM dbo.Orders
GROUP BY CONVERT(CHAR(7), OrderDate, 120)
ORDER BY YearMonth;
-- 2025-01 3 110000 | 2025-02 3 73000 | 2025-03 2 84500 | 2025-04 2 7500 | 2025-05 2 42000
-- 2025-06 2 177500 | 2025-07 2 42000 | 2025-08 2 79000 | 2025-09 1 2500        (9 rows)
GO

-- 11b. Same with DATETRUNC (keeps a real DATE -> sorts correctly, can be used in DATEADD later)
SELECT DATETRUNC(month, OrderDate) AS MonthStart, COUNT(*) AS Orders, SUM(TotalAmount) AS Revenue
FROM dbo.Orders
GROUP BY DATETRUNC(month, OrderDate)
ORDER BY MonthStart;   -- same 9 rows, first column 2025-01-01, 2025-02-01, ...
GO

-- 11c. Same with FORMAT (pretty label, e.g. 'Jan 2025') - fine for small result sets
SELECT FORMAT(OrderDate, 'MMM yyyy') AS MonthLabel, MIN(OrderDate) AS SortKey, COUNT(*) AS Orders
FROM dbo.Orders
GROUP BY FORMAT(OrderDate, 'MMM yyyy')
ORDER BY SortKey;   -- Jan 2025 3, Feb 2025 3, ... (note: you must sort by a real date, not by the label)
GO


/* ==== 12. FORMAT FOR DATES  (display only!) ==== */

-- FORMAT uses .NET patterns: d=day, M=month, y=year, H/h=hour, m=minute, s=second, tt=AM/PM.
-- Case matters: MM = month, mm = minute.
DECLARE @dt DATETIME2(0) = '2025-01-05T14:05:09';
SELECT FORMAT(@dt, 'dd-MMM-yyyy')          AS Style1,   -- 05-Jan-2025
       FORMAT(@dt, 'dddd, dd MMMM yyyy')   AS Style2,   -- Sunday, 05 January 2025
       FORMAT(@dt, 'yyyy-MM-dd HH:mm')     AS Style3,   -- 2025-01-05 14:05
       FORMAT(@dt, 'hh:mm tt')             AS Style4,   -- 02:05 PM
       FORMAT(@dt, 'd', 'en-IN')           AS ShortIN,  -- 05-01-2025 (India: day first)
       FORMAT(@dt, 'd', 'en-US')           AS ShortUS,  -- 1/5/2025   (US: month first)
       CONVERT(VARCHAR(10), @dt, 103)      AS Convert103;   -- 05/01/2025  (faster alternative to FORMAT)
GO


/* ==== 13. @@DATEFIRST / SET DATEFIRST and weekday names ==== */

-- 13a. @@DATEFIRST = which day is "1" for DATEPART(weekday). Default for us_english = 7 (Sunday).
SELECT @@DATEFIRST AS DateFirst, @@LANGUAGE AS Lang;   -- 7, us_english
GO

-- 13b. Sunday 5 Jan 2025 is weekday 1 under DATEFIRST 7 but weekday 7 under DATEFIRST 1 (Monday first).
SELECT DATEPART(weekday, '20250105') AS Sunday_Default7;   -- 1
SET DATEFIRST 1;   -- Monday = 1 (ISO style, common in India / Europe)
SELECT DATEPART(weekday, '20250105') AS Sunday_DateFirst1, @@DATEFIRST AS NowDateFirst;   -- 7, 1
SET DATEFIRST 7;   -- back to default
GO

-- 13c. DATEFIRST-independent weekday number (Monday = 1 ... Sunday = 7) - safe for production code:
SELECT DATENAME(weekday, '20250105') AS DayName,
       (DATEPART(weekday, '20250105') + @@DATEFIRST - 2) % 7 + 1 AS IsoWeekday;   -- Sunday, 7
GO

-- 13d. Real data: which weekday gets the most orders?
SELECT DATENAME(weekday, OrderDate) AS DayName, COUNT(*) AS Orders
FROM dbo.Orders
GROUP BY DATENAME(weekday, OrderDate), (DATEPART(weekday, OrderDate) + @@DATEFIRST - 2) % 7 + 1
ORDER BY (DATEPART(weekday, OrderDate) + @@DATEFIRST - 2) % 7 + 1;
-- Monday 4, Tuesday 3, Wednesday 2, Thursday 1, Friday 4, Saturday 2, Sunday 3
GO


/* ==== 14. DATE RANGES THE SARGABLE WAY ==== */
-- SARGable = "Search ARGument able" = the WHERE can use an index seek.
-- RULE: never wrap the COLUMN in a function. Put functions on the other side (the constant).

-- 14a. BAD (works, but forces a scan of every row): function on the column
SELECT OrderID, OrderDate FROM dbo.Orders
WHERE YEAR(OrderDate) = 2025 AND MONTH(OrderDate) = 2;   -- 3 rows: 1004, 1005, 1006
GO

-- 14b. GOOD: half-open range  >= start  AND  < next start. Works for DATE, DATETIME, DATETIME2 alike.
SELECT OrderID, OrderDate FROM dbo.Orders
WHERE OrderDate >= '20250201' AND OrderDate < '20250301';   -- same 3 rows, index-friendly
GO

-- 14c. Parameterised: "orders in the same month as @d" without touching the column
DECLARE @d DATE = '20250214';
SELECT OrderID, OrderDate FROM dbo.Orders
WHERE OrderDate >= DATETRUNC(month, @d) AND OrderDate < DATEADD(month, 1, DATETRUNC(month, @d));   -- 3 rows
GO

-- 14d. "Last 90 days before @asof": move the arithmetic to the variable, not the column
DECLARE @asof DATE = '20250905';
SELECT OrderID, OrderDate FROM dbo.Orders
WHERE OrderDate >= DATEADD(day, -90, @asof) AND OrderDate <= @asof;   -- 6 rows: 1014 .. 1019 (from 2025-06-07 on)
GO
-- (DATEDIFF(day, OrderDate, @asof) <= 90 gives the same rows but is NOT SARGable.)

-- 14e. BETWEEN is fine on a DATE column, dangerous on DATETIME (23:59:59.999 rounds to next day - Level 02).
SELECT COUNT(*) AS Q1Orders FROM dbo.Orders
WHERE OrderDate BETWEEN '20250101' AND '20250331';   -- 8  (Jan 3 + Feb 3 + Mar 2)
GO

/* ------------------------------------------------------------
   DONE. Next: 03_Practice_Numeric_Conditional.sql
   (No CLEANUP needed: this file created nothing. DATEFIRST was reset to 7.)
   ------------------------------------------------------------ */
