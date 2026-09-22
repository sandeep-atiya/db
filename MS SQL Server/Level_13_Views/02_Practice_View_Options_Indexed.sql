/* ============================================================
   LEVEL 13 - VIEWS  |  02_Practice_View_Options_Indexed.sql
   ------------------------------------------------------------
   Topics : WITH SCHEMABINDING, WITH ENCRYPTION, the SELECT *
            trap (sp_refreshview), indexed views (requirements,
            unique clustered index, NOEXPAND, when they help /
            hurt), view metadata (sys.views, sys.sql_modules,
            sp_helptext, OBJECT_DEFINITION, INFORMATION_SCHEMA.VIEWS,
            sys.dm_sql_referenced_entities), nested views,
            views vs CTE vs temp table vs table.
   HOW TO PRACTICE: run block by block, predict the output first.
   ============================================================ */

USE SQLPractice;
GO
-- Schema-bound and indexed views need these ON. SSMS has them ON by default;
-- sqlcmd starts with QUOTED_IDENTIFIER OFF, so we set them explicitly.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
DROP VIEW IF EXISTS dbo.vw_L13_HighPaidDetails, dbo.vw_L13_RevenueByCategory, dbo.vw_L13_ProductPrices,
                    dbo.vw_L13_Secret, dbo.vw_L13_AllProducts, dbo.vw_L13_EmployeeDetails,
                    dbo.vw_L13_Bad1, dbo.vw_L13_Bad2;
DROP TABLE IF EXISTS dbo.L13_Products;
GO
-- Setup: the copy table and the join view from file 01
SELECT * INTO dbo.L13_Products FROM dbo.Products;
ALTER TABLE dbo.L13_Products ADD CONSTRAINT PK_L13_Products PRIMARY KEY (ProductID);
GO
CREATE VIEW dbo.vw_L13_EmployeeDetails
AS
SELECT e.EmployeeID, e.EmployeeName, e.Email, e.Salary, e.HireDate,
       d.DepartmentName, d.Location
FROM dbo.Employees e
JOIN dbo.Departments d ON d.DepartmentID = e.DepartmentID;
GO


/* ==== 1. WITH SCHEMABINDING: protect the view from base-table changes ==== */
-- Without it, anyone can drop or rename a column the view uses; the view silently
-- breaks and you find out at SELECT time. With it, SQL Server REFUSES such changes.
-- Rules: two-part names (dbo.Table), no SELECT *, all objects in the same database.
CREATE VIEW dbo.vw_L13_ProductPrices
WITH SCHEMABINDING
AS
SELECT p.ProductID, p.ProductName, p.Price
FROM dbo.L13_Products p;
GO
-- 1a. Dropping a referenced column -> error
BEGIN TRY
    ALTER TABLE dbo.L13_Products DROP COLUMN Price;
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();   -- ALTER TABLE DROP COLUMN Price failed because one or more objects access this column.
    -- (SSMS shows two messages; the first one names the view: "The object 'vw_L13_ProductPrices' is dependent on column 'Price'.")
END CATCH
GO
-- 1b. Changing its type -> error
BEGIN TRY
    ALTER TABLE dbo.L13_Products ALTER COLUMN Price DECIMAL(14,2);
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
GO
-- 1c. Dropping the whole table -> error
BEGIN TRY
    DROP TABLE dbo.L13_Products;
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();   -- Cannot DROP TABLE 'dbo.L13_Products' because it is being referenced by object ...
END CATCH
GO
-- 1d. Columns the view does NOT use may still change
ALTER TABLE dbo.L13_Products DROP COLUMN Stock;   -- OK: not referenced by the view
ALTER TABLE dbo.L13_Products ADD Stock INT NULL;  -- put it back
GO
-- 1e. SELECT * and one-part names are refused with SCHEMABINDING
BEGIN TRY
    EXEC (N'CREATE VIEW dbo.vw_L13_Bad1 WITH SCHEMABINDING AS SELECT * FROM dbo.L13_Products;');
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();   -- Syntax '*' is not allowed in schema-bound objects.
END CATCH
BEGIN TRY
    EXEC (N'CREATE VIEW dbo.vw_L13_Bad2 WITH SCHEMABINDING AS SELECT ProductID FROM L13_Products;');
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();   -- ... Names must be in two-part format ...
END CATCH
GO


/* ==== 2. WITH ENCRYPTION: hide the definition ==== */
-- Obfuscates the view text in the catalog. Rarely used: weak (tools decrypt it), you
-- lose the source if it is not in version control, blocks replication and some tooling.
CREATE VIEW dbo.vw_L13_Secret
WITH ENCRYPTION
AS
SELECT e.EmployeeID, e.EmployeeName
FROM dbo.Employees e;
GO
SELECT * FROM dbo.vw_L13_Secret WHERE EmployeeID = 101;                              -- works normally: Rahul
SELECT OBJECT_DEFINITION(OBJECT_ID('dbo.vw_L13_Secret')) AS Definition;              -- NULL
SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID('dbo.vw_L13_Secret');   -- NULL
EXEC sp_helptext 'dbo.vw_L13_Secret';   -- prints: The text for object 'dbo.vw_L13_Secret' is encrypted.
GO


/* ==== 3. SELECT * IN A VIEW IS A TRAP ==== */
-- The column list is FIXED when the view is created. Add a column to the table later
-- and the view does not show it until you refresh the view's metadata.
CREATE VIEW dbo.vw_L13_AllProducts
AS
SELECT * FROM dbo.L13_Products;
GO
SELECT COUNT(*) AS ViewColumns FROM sys.columns WHERE object_id = OBJECT_ID('dbo.vw_L13_AllProducts');   -- 5
ALTER TABLE dbo.L13_Products ADD Supplier VARCHAR(50) NULL;
SELECT COUNT(*) AS ViewColumnsAfterAdd FROM sys.columns WHERE object_id = OBJECT_ID('dbo.vw_L13_AllProducts');   -- still 5
SELECT TOP (1) * FROM dbo.vw_L13_AllProducts;   -- no Supplier column
GO
EXEC sp_refreshview 'dbo.vw_L13_AllProducts';   -- re-reads the base table (sys.sp_refreshsqlmodule does the same)
SELECT COUNT(*) AS ViewColumnsAfterRefresh FROM sys.columns WHERE object_id = OBJECT_ID('dbo.vw_L13_AllProducts');   -- 6
SELECT TOP (1) * FROM dbo.vw_L13_AllProducts;   -- Supplier is there now
GO
-- Worse: drop a column and add another in its place and the view can return the WRONG
-- data under the old column name (columns are matched by position). Always list columns.


/* ==== 4. INDEXED VIEWS: a view that DOES store data ==== */
-- Put a UNIQUE CLUSTERED index on a view and SQL Server materialises the result on disk
-- and keeps it up to date automatically on every INSERT / UPDATE / DELETE of the base tables.
-- Requirements (the big ones):
--   * WITH SCHEMABINDING, two-part names, no SELECT *
--   * deterministic only: no GETDATE(), no non-schema-bound functions
--   * with GROUP BY: COUNT_BIG(*) is mandatory; SUM only over NOT NULL expressions; no AVG / MIN / MAX
--   * no OUTER JOIN, no subquery, no UNION, no DISTINCT, no TOP, no CTE
--   * the FIRST index must be UNIQUE CLUSTERED
--   * these SET options must be ON when you create it AND when anyone modifies the base tables:
SET ANSI_NULLS ON; SET ANSI_PADDING ON; SET ANSI_WARNINGS ON; SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON; SET QUOTED_IDENTIFIER ON; SET NUMERIC_ROUNDABORT OFF;
GO
CREATE VIEW dbo.vw_L13_RevenueByCategory
WITH SCHEMABINDING
AS
SELECT p.Category,
       SUM(od.Quantity * od.UnitPrice) AS Revenue,
       SUM(od.Quantity)                AS UnitsSold,
       COUNT_BIG(*)                    AS LineCount     -- mandatory with GROUP BY
FROM dbo.OrderDetails od
JOIN dbo.Products p ON p.ProductID = od.ProductID
GROUP BY p.Category;
GO
-- 4a. Before the index it is an ordinary view (the SELECT runs every time)
SELECT * FROM dbo.vw_L13_RevenueByCategory ORDER BY Revenue DESC;
-- Electronics 510500 / 33 / 17,  Furniture 105000 / 10 / 6,  Stationery 2500 / 170 / 3
GO
-- 4b. The unique clustered index materialises it
CREATE UNIQUE CLUSTERED INDEX IX_vw_L13_RevenueByCategory ON dbo.vw_L13_RevenueByCategory (Category);
GO
SELECT i.name, i.type_desc, i.is_unique
FROM sys.indexes i
WHERE i.object_id = OBJECT_ID('dbo.vw_L13_RevenueByCategory');   -- IX_vw_L13_RevenueByCategory, CLUSTERED, 1
-- It now has rows on disk, like a table:
SELECT OBJECT_NAME(p.object_id) AS ObjName, p.rows
FROM sys.partitions p
WHERE p.object_id = OBJECT_ID('dbo.vw_L13_RevenueByCategory');   -- 3 rows
GO
-- 4c. Querying it. NOEXPAND = "use the stored rows, do not expand the view's SELECT".
--     Enterprise / Developer edition use the index automatically (even for queries that
--     never mention the view!); Standard / Express need NOEXPAND to use it.
SELECT Category, Revenue, UnitsSold, LineCount
FROM dbo.vw_L13_RevenueByCategory WITH (NOEXPAND)
ORDER BY Revenue DESC;
GO
-- 4d. HELP: heavy aggregates / joins read thousands of times (dashboards, reports) on
--     tables that change rarely -> reads become a tiny index seek.
--     HURT: every INSERT / UPDATE / DELETE on OrderDetails or Products now also maintains
--     the view (extra locks, slower writes); the strict SET options apply to every writer;
--     base-table schema changes are blocked (SCHEMABINDING). Never on hot OLTP tables.


/* ==== 5. METADATA: find and read your views ==== */
-- 5a. sys.views = one row per view; sys.sql_modules = the definition + options
SELECT v.name, v.with_check_option, m.is_schema_bound, m.uses_quoted_identifier,
       CASE WHEN m.definition IS NULL THEN 'encrypted' ELSE 'readable' END AS DefinitionState
FROM sys.views v
JOIN sys.sql_modules m ON m.object_id = v.object_id
WHERE v.name LIKE 'vw[_]L13%'
ORDER BY v.name;   -- 5 rows: AllProducts, EmployeeDetails, ProductPrices (schema-bound), RevenueByCategory (schema-bound), Secret (encrypted)
GO
-- 5b. Read a definition: 3 ways
EXEC sp_helptext 'dbo.vw_L13_EmployeeDetails';
SELECT OBJECT_DEFINITION(OBJECT_ID('dbo.vw_L13_EmployeeDetails')) AS Definition;
SELECT TABLE_NAME, CHECK_OPTION, IS_UPDATABLE, LEFT(VIEW_DEFINITION, 45) AS DefinitionStart
FROM INFORMATION_SCHEMA.VIEWS
WHERE TABLE_NAME LIKE 'vw[_]L13%';
-- ANSI view. Quirks: IS_UPDATABLE is ALWAYS 'NO' in SQL Server; VIEW_DEFINITION is cut at 4000 chars.
GO
-- 5c. What does a view depend on? (one row per table + one per column used)
SELECT referenced_schema_name, referenced_entity_name, referenced_minor_name AS ColumnName
FROM sys.dm_sql_referenced_entities('dbo.vw_L13_EmployeeDetails', 'OBJECT');   -- Departments + 3 columns, Employees + 6 columns
GO
-- 5d. The other direction: which objects use dbo.Employees?
SELECT referencing_schema_name, referencing_entity_name
FROM sys.dm_sql_referencing_entities('dbo.Employees', 'OBJECT');
-- CK_Employees_Salary (a CHECK constraint counts too), vw_L13_EmployeeDetails, vw_L13_Secret (+ any other objects of yours)
GO


/* ==== 6. NESTED VIEWS: a view on a view ==== */
CREATE VIEW dbo.vw_L13_HighPaidDetails
AS
SELECT v.EmployeeID, v.EmployeeName, v.DepartmentName, v.Salary
FROM dbo.vw_L13_EmployeeDetails v          -- a view, not a table
WHERE v.Salary > 70000;
GO
SELECT * FROM dbo.vw_L13_HighPaidDetails ORDER BY Salary DESC;   -- 4 rows: Sneha 90000, Rahul 85000, Priya 75000, Deepak 72000
GO
-- Allowed (up to 32 levels) but DISCOURAGED: each layer hides joins and filters, the
-- optimizer must expand all of them, nobody knows the real cost, and a change in the
-- bottom view breaks the top one at runtime. Prefer one flat view (or inline TVF) per purpose.


/* ==== 7. VIEW vs CTE vs TEMP TABLE vs TABLE ==== */
/*
   --------------+-------------------+------------------+--------------------+------------------
                 | VIEW              | CTE              | #TEMP TABLE        | TABLE
   --------------+-------------------+------------------+--------------------+------------------
   Stores data   | no (indexed: yes) | no               | yes, in tempdb     | yes
   Lifetime      | permanent object  | one statement    | session            | permanent
   Reusable by   | every query/user  | next line only   | my session         | everyone
   Parameters    | no (use TVF)      | no               | n/a                | n/a
   Indexes       | only indexed view | no               | yes                | yes
   Security      | GRANT on the view | none             | none               | GRANT on table
   Cost          | re-runs SELECT    | re-runs per ref. | write once, read n | read
   Use for       | reuse + security  | readability,     | staging, multi-    | real data
                 | + hide joins      | recursion        | step, big joins    |
   --------------+-------------------+------------------+--------------------+------------------
*/


/* ==== 8. CLEANUP ==== */
DROP VIEW IF EXISTS dbo.vw_L13_HighPaidDetails;        -- nested view first
DROP VIEW IF EXISTS dbo.vw_L13_RevenueByCategory;      -- dropping the view drops its index too
DROP VIEW IF EXISTS dbo.vw_L13_ProductPrices, dbo.vw_L13_Secret, dbo.vw_L13_AllProducts,
                    dbo.vw_L13_EmployeeDetails, dbo.vw_L13_Bad1, dbo.vw_L13_Bad2;
DROP TABLE IF EXISTS dbo.L13_Products;                 -- only possible after the schema-bound view is gone
GO
SELECT COUNT(*) AS LeftoverL13Views FROM sys.views WHERE name LIKE 'vw[_]L13%';   -- 0
GO
/* DONE. Next: Exercises.sql */
