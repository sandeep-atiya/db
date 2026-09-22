/* ============================================================
   LEVEL 11 - CTE AND WINDOW FUNCTIONS  |  04_Practice_Pivot_Unpivot.sql
   ------------------------------------------------------------
   Topics : PIVOT syntax (revenue per Category per month; order
            status count per customer), the three roles (grouping,
            spreading, aggregate), why PIVOT needs the derived-table
            trick, the same result with CASE (portable), dynamic
            PIVOT with STRING_AGG + sp_executesql, UNPIVOT,
            CROSS APPLY VALUES as the modern unpivot.

   HOW TO PRACTICE: run block by block, predict the output first.
   Creates dbo.L11_CategoryByMonth, dropped in CLEANUP.
   ============================================================ */

USE SQLPractice;
GO
DROP TABLE IF EXISTS dbo.L11_CategoryByMonth;
GO


/* ============================================================
   1. THE THREE ROLES  (know these and PIVOT stops being magic)
   ============================================================
   Start from a LONG result: one row per (Category, Month) with an amount.
     GROUPING  column : stays as rows          -> Category
     SPREADING column : its VALUES become columns -> Month (1..9)
     AGGREGATE column : the number in the cells -> SUM(Amount)
   ============================================================ */

-- 1a. The long format we will pivot (this is what GROUP BY gives).
SELECT p.Category, MONTH(o.OrderDate) AS Mth, SUM(od.Quantity * od.UnitPrice) AS Revenue
FROM dbo.OrderDetails od
JOIN dbo.Products p ON p.ProductID = od.ProductID
JOIN dbo.Orders   o ON o.OrderID   = od.OrderID
GROUP BY p.Category, MONTH(o.OrderDate)
ORDER BY p.Category, Mth;
GO
-- expect 14 rows (Electronics 8 months, Furniture 4, Stationery 2)


/* ============================================================
   2. PIVOT SYNTAX
   ============================================================
   SELECT <grouping cols>, [v1], [v2], ...        -- spreading VALUES as column names
   FROM ( SELECT grouping, spreading, aggregate-input FROM ... ) AS src
   PIVOT ( AGG(aggregate-input) FOR spreading IN ([v1], [v2], ...) ) AS pv;
   The values in the IN list must be written by hand (static PIVOT).
   ============================================================ */

-- 2a. Revenue per Category per month. Empty cells come back as NULL.
SELECT Category, [1] AS Jan, [2] AS Feb, [3] AS Mar, [4] AS Apr, [5] AS May,
                 [6] AS Jun, [7] AS Jul, [8] AS Aug, [9] AS Sep
FROM (SELECT p.Category, MONTH(o.OrderDate) AS Mth, od.Quantity * od.UnitPrice AS Amount
      FROM dbo.OrderDetails od
      JOIN dbo.Products p ON p.ProductID = od.ProductID
      JOIN dbo.Orders   o ON o.OrderID   = od.OrderID) AS src
PIVOT (SUM(Amount) FOR Mth IN ([1], [2], [3], [4], [5], [6], [7], [8], [9])) AS pv
ORDER BY Category;
GO
-- expect 3 rows: Electronics 102000, 50000, 84500, 6000, NULL, 177500, 10000, 78000, 2500
--                Furniture   8000, 23000, NULL, NULL, 42000, NULL, 32000, NULL, NULL
--                Stationery  NULL, NULL, NULL, 1500, NULL, NULL, NULL, 1000, NULL

-- 2b. Order STATUS count per customer (COUNT gives 0, not NULL, for empty cells).
--     LEFT JOIN keeps Hina (no orders): her Status is NULL, matches no column -> all zeros.
SELECT CustomerName, [Pending], [Completed], [Cancelled]
FROM (SELECT c.CustomerName, o.Status, o.OrderID
      FROM dbo.Customers c
      LEFT JOIN dbo.Orders o ON o.CustomerID = c.CustomerID) AS src
PIVOT (COUNT(OrderID) FOR Status IN ([Pending], [Completed], [Cancelled])) AS pv
ORDER BY CustomerName;
GO
-- expect 8 rows: Aarav 1/3/0, Bhavna 0/4/0, Chirag 1/2/0, Divya 0/2/0, Esha 0/1/1,
--                Farhan 0/2/0, Gaurav 0/2/0, Hina 0/0/0


/* ============================================================
   3. WHY THE DERIVED-TABLE TRICK
   ============================================================
   RULE: every column of the source that is NOT the spreading column
   and NOT the aggregate input becomes a GROUPING column. Extra
   columns = extra groups = the pivot "explodes" into many rows.
   So the source must contain EXACTLY the columns you need.
   ============================================================ */

-- 3a. Same pivot as 2a, but the source also carries OrderID -> one row per (Category, OrderID).
SELECT COUNT(*) AS RowsWithOrderIdInSource
FROM (SELECT p.Category, o.OrderID, MONTH(o.OrderDate) AS Mth, od.Quantity * od.UnitPrice AS Amount
      FROM dbo.OrderDetails od
      JOIN dbo.Products p ON p.ProductID = od.ProductID
      JOIN dbo.Orders   o ON o.OrderID   = od.OrderID) AS src
PIVOT (SUM(Amount) FOR Mth IN ([1], [2], [3], [4], [5], [6], [7], [8], [9])) AS pv;
GO
-- expect 21 (not 3!) - one row per distinct Category + OrderID pair.
-- You also cannot write PIVOT directly over a table with SELECT * for the same reason.


/* ============================================================
   4. THE SAME RESULT WITH CASE  (conditional aggregation - portable)
   ============================================================
   Works in every database, no special syntax, easy to add
   "Total" columns or different aggregates per column.
   ============================================================ */

-- 4a. Status count per customer with CASE.
SELECT c.CustomerName,
       SUM(CASE WHEN o.Status = 'Pending'   THEN 1 ELSE 0 END) AS Pending,
       SUM(CASE WHEN o.Status = 'Completed' THEN 1 ELSE 0 END) AS Completed,
       SUM(CASE WHEN o.Status = 'Cancelled' THEN 1 ELSE 0 END) AS Cancelled,
       COUNT(o.OrderID)                                        AS Total
FROM dbo.Customers c
LEFT JOIN dbo.Orders o ON o.CustomerID = c.CustomerID
GROUP BY c.CustomerName
ORDER BY c.CustomerName;
GO
-- expect the same 8 rows as 2b, plus a Total column (Aarav 4, Hina 0)

-- 4b. Revenue per category per QUARTER with CASE (grouping ranges of the spreading value
--     is easy here, awkward with PIVOT).
SELECT p.Category,
       SUM(CASE WHEN MONTH(o.OrderDate) BETWEEN 1 AND 3 THEN od.Quantity * od.UnitPrice ELSE 0 END) AS Q1,
       SUM(CASE WHEN MONTH(o.OrderDate) BETWEEN 4 AND 6 THEN od.Quantity * od.UnitPrice ELSE 0 END) AS Q2,
       SUM(CASE WHEN MONTH(o.OrderDate) BETWEEN 7 AND 9 THEN od.Quantity * od.UnitPrice ELSE 0 END) AS Q3,
       SUM(od.Quantity * od.UnitPrice) AS Total
FROM dbo.OrderDetails od
JOIN dbo.Products p ON p.ProductID = od.ProductID
JOIN dbo.Orders   o ON o.OrderID   = od.OrderID
GROUP BY p.Category
ORDER BY p.Category;
GO
-- expect 3 rows: Electronics 236500 / 183500 / 90500 / 510500,
--                Furniture 31000 / 42000 / 32000 / 105000, Stationery 0 / 1500 / 1000 / 2500


/* ============================================================
   5. DYNAMIC PIVOT  (column list built at run time)
   ============================================================
   Static PIVOT needs the values typed in. When they change
   (new category, new month) build the IN list with STRING_AGG,
   put the whole query in a string and run it with sp_executesql.
   ============================================================ */

-- 5a. Build the column list: [Electronics],[Furniture],[Stationery]
DECLARE @cols NVARCHAR(MAX), @sql NVARCHAR(MAX);

SELECT @cols = STRING_AGG(QUOTENAME(Category), ',') WITHIN GROUP (ORDER BY Category)
FROM (SELECT DISTINCT Category FROM dbo.Products) AS c;     -- DISTINCT first: STRING_AGG(DISTINCT) is not allowed

PRINT 'Columns: ' + @cols;

-- 5b. Build and run the pivot: months as rows, categories as columns.
SET @sql = N'
SELECT Mth, ' + @cols + N'
FROM (SELECT p.Category, MONTH(o.OrderDate) AS Mth, od.Quantity * od.UnitPrice AS Amount
      FROM dbo.OrderDetails od
      JOIN dbo.Products p ON p.ProductID = od.ProductID
      JOIN dbo.Orders   o ON o.OrderID   = od.OrderID) AS src
PIVOT (SUM(Amount) FOR Category IN (' + @cols + N')) AS pv
ORDER BY Mth;';

EXEC sp_executesql @sql;
GO
-- expect 9 rows: Mth 1 -> 102000 / 8000 / NULL, Mth 4 -> 6000 / NULL / 1500, Mth 9 -> 2500 / NULL / NULL
-- (QUOTENAME protects against odd characters and SQL injection in the value names)


/* ============================================================
   6. UNPIVOT  (columns back to rows)
   ============================================================ */

-- 6a. Store a wide table first (the pivot result from 2a).
SELECT Category, [1] AS Jan, [2] AS Feb, [3] AS Mar, [4] AS Apr, [5] AS May,
                 [6] AS Jun, [7] AS Jul, [8] AS Aug, [9] AS Sep
INTO dbo.L11_CategoryByMonth
FROM (SELECT p.Category, MONTH(o.OrderDate) AS Mth, od.Quantity * od.UnitPrice AS Amount
      FROM dbo.OrderDetails od
      JOIN dbo.Products p ON p.ProductID = od.ProductID
      JOIN dbo.Orders   o ON o.OrderID   = od.OrderID) AS src
PIVOT (SUM(Amount) FOR Mth IN ([1], [2], [3], [4], [5], [6], [7], [8], [9])) AS pv;
SELECT * FROM dbo.L11_CategoryByMonth ORDER BY Category;
GO
-- expect 3 wide rows

-- 6b. UNPIVOT: Revenue = the cell value, MonthName = the column it came from.
--     NULL cells are DROPPED (14 rows come back, not 27). All listed columns must
--     have the same data type.
SELECT Category, MonthName, Revenue
FROM dbo.L11_CategoryByMonth
UNPIVOT (Revenue FOR MonthName IN (Jan, Feb, Mar, Apr, May, Jun, Jul, Aug, Sep)) AS up
ORDER BY Category;
GO
-- expect 14 rows: Electronics x8, Furniture x4, Stationery x2


/* ============================================================
   7. CROSS APPLY VALUES  (the modern, flexible unpivot)
   ============================================================
   For each wide row, VALUES builds a tiny table of (month, value)
   pairs; CROSS APPLY joins it back. You control NULL handling,
   ordering, and can unpivot several column sets at once.
   ============================================================ */

-- 7a. Same 14 rows, in proper month order, with an explicit NULL filter.
SELECT c.Category, v.MthNo, v.MonthName, v.Revenue
FROM dbo.L11_CategoryByMonth c
CROSS APPLY (VALUES (1, 'Jan', c.Jan), (2, 'Feb', c.Feb), (3, 'Mar', c.Mar),
                    (4, 'Apr', c.Apr), (5, 'May', c.May), (6, 'Jun', c.Jun),
                    (7, 'Jul', c.Jul), (8, 'Aug', c.Aug), (9, 'Sep', c.Sep)) AS v (MthNo, MonthName, Revenue)
WHERE v.Revenue IS NOT NULL
ORDER BY c.Category, v.MthNo;
GO
-- expect 14 rows

-- 7b. Drop the WHERE and the NULL months are kept (27 rows) - UNPIVOT cannot do that.
SELECT COUNT(*) AS AllCells, COUNT(v.Revenue) AS NonNullCells
FROM dbo.L11_CategoryByMonth c
CROSS APPLY (VALUES (c.Jan), (c.Feb), (c.Mar), (c.Apr), (c.May), (c.Jun), (c.Jul), (c.Aug), (c.Sep)) AS v (Revenue);
GO
-- expect 27, 14


/* ============================================================
   8. CLEANUP
   ============================================================ */
DROP TABLE IF EXISTS dbo.L11_CategoryByMonth;
GO
/* DONE. Next: Exercises.sql */
