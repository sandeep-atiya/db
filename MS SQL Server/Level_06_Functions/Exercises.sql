/* ============================================================
   LEVEL 06 - FUNCTIONS  |  Exercises.sql
   ------------------------------------------------------------
   Try each question in the "YOUR ANSWERS" area FIRST.
   Then scroll down to SOLUTIONS and compare.
   All questions use the SQLPractice data only (nothing is changed).
   ============================================================ */

USE SQLPractice;
GO

/* ------------------------------------------------------------
   QUESTIONS
   ------------------------------------------------------------
   Q1.  For every customer show: name in UPPER case, its length,
        and the first 3 letters.

   Q2.  Split CustomerName into FirstName and LastName columns.

   Q3.  Show every employee with a masked email: first letter,
        then '***', then the '@domain' part (rahul@example.com ->
        r***@example.com). Employees without email must show
        'no email' (not NULL).

   Q4.  Build a product code = first 3 letters of Category in
        upper case + '-' + ProductID padded to 4 digits.
        Laptop -> ELE-0001, Chair -> FUR-0004.

   Q5.  For each order show OrderDate, the month name, the weekday
        name, the last day of that month and a delivery date of
        OrderDate + 5 days. Orders 1001-1003 only.

   Q6.  Orders per month: a 'yyyy-MM' label, number of orders and
        total revenue, in chronological order (no FORMAT).

   Q7.  Completed years of service of every employee as of
        1 March 2025. Show BOTH the naive DATEDIFF(year) value and
        the correct value, so you can see which rows differ.

   Q8.  Price per unit of stock for every product (Price / Stock)
        rounded to 2 decimals. Headphones has 0 stock: no error
        allowed, show the text 'Out of stock' instead of NULL.

   Q9.  Classify every order as 'Large' (>= 50000), 'Medium'
        (>= 10000) or 'Small', then count the orders in each class.

   Q10. List all orders sorted by Status in this business order:
        Pending first, then Cancelled, then Completed; inside each
        status the biggest TotalAmount first.

   Q11. What percentage of orders is Completed? Show it as a
        DECIMAL with 2 places and also formatted like '84.2%'.
        (16 of 19 orders - do it with SQL, not by hand.)

   Q12. (interview) For every employee show HireDate, the quarter
        of hire as 'Q1'..'Q4' (use CHOOSE), and the NEXT work
        anniversary on or after 22 Sep 2025. Sort by that date.
   ------------------------------------------------------------ */

-- YOUR ANSWERS HERE (write below, run, compare)










/* ============================================================
   SOLUTIONS
   ============================================================ */

-- Q1
SELECT CustomerName, UPPER(CustomerName) AS UpperName, LEN(CustomerName) AS NameLen, LEFT(CustomerName, 3) AS First3
FROM dbo.Customers;   -- AARAV SHARMA 12 Aar ...
GO

-- Q2
SELECT CustomerName,
       LEFT(CustomerName, CHARINDEX(' ', CustomerName) - 1)                          AS FirstName,
       SUBSTRING(CustomerName, CHARINDEX(' ', CustomerName) + 1, LEN(CustomerName))  AS LastName
FROM dbo.Customers;   -- Aarav | Sharma, Bhavna | Mehta, ...
GO

-- Q3
SELECT EmployeeName,
       COALESCE(LEFT(Email, 1) + '***' + SUBSTRING(Email, CHARINDEX('@', Email), LEN(Email)), 'no email') AS MaskedEmail
FROM dbo.Employees;   -- r***@example.com ... Anjali -> no email  (the + with NULL gives NULL, COALESCE fixes it)
GO

-- Q4
SELECT ProductName,
       UPPER(LEFT(Category, 3)) + '-' + RIGHT('0000' + CAST(ProductID AS VARCHAR(4)), 4) AS ProductCode
FROM dbo.Products;   -- ELE-0001, ELE-0002, ELE-0003, FUR-0004, ... STA-0007, ... ELE-0011
-- alternative padding: FORMAT(ProductID, '0000')
GO

-- Q5
SELECT OrderID, OrderDate,
       DATENAME(month, OrderDate)   AS MonthName,   -- January
       DATENAME(weekday, OrderDate) AS DayName,     -- Sunday, Sunday, Monday
       EOMONTH(OrderDate)           AS MonthEnd,    -- 2025-01-31
       DATEADD(day, 5, OrderDate)   AS DeliveryDate -- 2025-01-10, 2025-01-17, 2025-01-25
FROM dbo.Orders
WHERE OrderID <= 1003;
GO

-- Q6
SELECT CONVERT(CHAR(7), OrderDate, 120) AS YearMonth, COUNT(*) AS Orders, SUM(TotalAmount) AS Revenue
FROM dbo.Orders
GROUP BY CONVERT(CHAR(7), OrderDate, 120)
ORDER BY YearMonth;   -- 2025-01 3 110000 ... 2025-09 1 2500 (9 rows)
GO

-- Q7
DECLARE @asof DATE = '20250301';
SELECT EmployeeName, HireDate,
       DATEDIFF(year, HireDate, @asof) AS NaiveYears,
       DATEDIFF(year, HireDate, @asof)
         - CASE WHEN DATEADD(year, DATEDIFF(year, HireDate, @asof), HireDate) > @asof THEN 1 ELSE 0 END AS CompletedYears
FROM dbo.Employees
ORDER BY EmployeeID;
-- Differ: Amit 2/1, Priya 4/3, Ravi 3/2, Sneha 5/4, Karan 2/1, Pooja 2/1, Vikram 3/2, Anjali 1/0, Deepak 4/3
-- Same : Rahul 3/3, Neha 1/1, Meera 1/1
GO

-- Q8
SELECT ProductName, Price, Stock,
       COALESCE(CAST(CAST(Price / NULLIF(Stock, 0) AS DECIMAL(10,2)) AS VARCHAR(20)), 'Out of stock') AS PricePerUnitStock
FROM dbo.Products;   -- Laptop 7500.00 ... Headphones 'Out of stock'
-- Note: CAST to DECIMAL(10,2) trims the long scale of decimal division (ROUND alone would keep it),
--       and the column must be text to hold 'Out of stock', hence the second CAST.
GO

-- Q9
SELECT CASE WHEN TotalAmount >= 50000 THEN 'Large'
            WHEN TotalAmount >= 10000 THEN 'Medium'
            ELSE 'Small' END AS SizeClass,
       COUNT(*) AS Orders
FROM dbo.Orders
GROUP BY CASE WHEN TotalAmount >= 50000 THEN 'Large'
              WHEN TotalAmount >= 10000 THEN 'Medium'
              ELSE 'Small' END
ORDER BY Orders DESC;   -- Medium 8, Small 6, Large 5
GO

-- Q10
SELECT OrderID, Status, TotalAmount
FROM dbo.Orders
ORDER BY CASE Status WHEN 'Pending' THEN 1 WHEN 'Cancelled' THEN 2 ELSE 3 END,
         TotalAmount DESC;   -- 1015, 1017, 1006, 1014, 1008, 1001, 1018, ...
GO

-- Q11
SELECT CAST(SUM(CASE WHEN Status = 'Completed' THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS DECIMAL(5,2)) AS CompletedPct,   -- 84.21
       FORMAT(SUM(CASE WHEN Status = 'Completed' THEN 1 ELSE 0 END) * 1.0 / COUNT(*), 'P1')              AS CompletedPctText   -- 84.2%
FROM dbo.Orders;
-- Without the * 100.0 / * 1.0 the integer division would give 0.
GO

-- Q12
DECLARE @today DATE = '20250922';
SELECT EmployeeName, HireDate,
       CHOOSE(DATEPART(quarter, HireDate), 'Q1', 'Q2', 'Q3', 'Q4') AS HireQuarter,
       CASE WHEN DATEADD(year, DATEDIFF(year, HireDate, @today), HireDate) >= @today
            THEN DATEADD(year, DATEDIFF(year, HireDate, @today), HireDate)
            ELSE DATEADD(year, DATEDIFF(year, HireDate, @today) + 1, HireDate)
       END AS NextAnniversary
FROM dbo.Employees
ORDER BY NextAnniversary;   -- Ravi 2025-11-01 first, then Meera 2026-01-08, Rahul 2026-01-10, ... Vikram 2026-09-14 last
GO
