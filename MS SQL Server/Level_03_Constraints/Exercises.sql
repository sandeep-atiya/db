/* ============================================================
   LEVEL 03 - CONSTRAINTS  |  Exercises.sql
   ------------------------------------------------------------
   Try each question in the "YOUR ANSWERS" area FIRST.
   Then scroll down to SOLUTIONS and compare.
   Q1-Q3 only READ the SQLPractice tables. Q4-Q12 build their own
   tables (dbo.L03_Ex_*) and drop them at the end.
   ============================================================ */

USE SQLPractice;
GO

/* ------------------------------------------------------------
   QUESTIONS
   ------------------------------------------------------------
   Q1.  List every constraint on dbo.Orders with its type, using
        INFORMATION_SCHEMA.TABLE_CONSTRAINTS. How many rows? Which
        constraint of Orders is missing from this view, and why?

   Q2.  Build an FK map of SQLPractice: constraint name, child table,
        child column, parent table, parent column, ON DELETE action.
        Use sys.foreign_keys + sys.foreign_key_columns + sys.columns.

   Q3.  Which of the 6 base tables can NOT be TRUNCATEd because another
        table has a foreign key pointing at them? (Only query metadata.)

   Q4.  Create dbo.L03_Ex_Categories:
          CategoryID   INT IDENTITY(1,1)  primary key
          CategoryName VARCHAR(50) NOT NULL, unique
        Name both constraints properly. Insert Electronics, Furniture,
        Stationery. Then try to insert 'Furniture' again inside TRY/CATCH.

   Q5.  Create dbo.L03_Ex_Items with ALL constraints named:
          ItemID     INT IDENTITY(1,1) PK
          ItemName   VARCHAR(100) NOT NULL
          CategoryID INT NOT NULL, FK -> L03_Ex_Categories ON DELETE CASCADE
          Price      DECIMAL(10,2) NOT NULL, CHECK (Price >= 0)
          Stock      INT NOT NULL, DEFAULT 0
          CreatedAt  DATETIME2(0) NOT NULL, DEFAULT SYSDATETIME()
        Insert 3 items giving only ItemName, CategoryID, Price. Show the table.

   Q6.  Inside TRY/CATCH, try: (a) an item with Price -5, (b) an item with
        CategoryID 99, (c) an item with ItemName NULL. Print each error.

   Q7.  Insert one more item and capture its new ItemID with SCOPE_IDENTITY()
        into a variable; print it. Then show IDENT_CURRENT('dbo.L03_Ex_Items').

   Q8.  Delete the 'Furniture' category. Show that its items disappeared
        (cascade) while the other items stayed.

   Q9.  Insert an item inside BEGIN TRAN ... ROLLBACK, then insert another
        item normally. Show the gap in ItemID. Then reseed the identity so
        the next id continues from MAX(ItemID).

   Q10. Add a CHECK constraint Stock <= 1000 WITH NOCHECK while one row
        has Stock = 5000. Show is_not_trusted. Try WITH CHECK CHECK CONSTRAINT
        inside TRY/CATCH (fails), fix the row, run it again (succeeds).

   Q11. Create dbo.L03_Ex_ItemTags (ItemID INT FK -> Items, Tag VARCHAR(20))
        with a COMPOSITE primary key (ItemID, Tag). Insert 3 rows and prove
        the same (ItemID, Tag) pair cannot be inserted twice.

   Q12. (Interview) Show the definition text of every CHECK constraint in the
        database whose table name starts with 'L03_Ex_'. Then drop all your
        L03_Ex_ tables in the right order.
   ------------------------------------------------------------ */

-- YOUR ANSWERS HERE (write below, run, compare)










/* ============================================================
   SOLUTIONS
   ============================================================ */

-- Q1
SELECT CONSTRAINT_NAME, CONSTRAINT_TYPE
FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS
WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'Orders'
ORDER BY CONSTRAINT_TYPE, CONSTRAINT_NAME;
-- 4 rows: CK_Orders_Status, FK_Orders_Customers, FK_Orders_Employees, PK_Orders.
-- DF_Orders_Status is missing: a DEFAULT is not a constraint in the ANSI sense
-- (it lives in sys.default_constraints / INFORMATION_SCHEMA.COLUMNS.COLUMN_DEFAULT).
GO

-- Q2
SELECT fk.name AS ConstraintName,
       OBJECT_NAME(fk.parent_object_id)     AS ChildTable,  cp.name AS ChildColumn,
       OBJECT_NAME(fk.referenced_object_id) AS ParentTable, cr.name AS ParentColumn,
       fk.delete_referential_action_desc    AS OnDelete
FROM sys.foreign_keys fk
JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
JOIN sys.columns cp ON cp.object_id = fkc.parent_object_id     AND cp.column_id = fkc.parent_column_id
JOIN sys.columns cr ON cr.object_id = fkc.referenced_object_id AND cr.column_id = fkc.referenced_column_id
WHERE fk.parent_object_id IN (OBJECT_ID('dbo.Employees'), OBJECT_ID('dbo.Orders'), OBJECT_ID('dbo.OrderDetails'))
ORDER BY ChildTable, fk.name;
-- 6 rows, all NO_ACTION
GO

-- Q3
SELECT DISTINCT OBJECT_NAME(fk.referenced_object_id) AS CannotTruncate
FROM sys.foreign_keys fk
WHERE fk.referenced_object_id IN (OBJECT_ID('dbo.Departments'), OBJECT_ID('dbo.Employees'),
                                  OBJECT_ID('dbo.Customers'),   OBJECT_ID('dbo.Products'),
                                  OBJECT_ID('dbo.Orders'),      OBJECT_ID('dbo.OrderDetails'))
ORDER BY CannotTruncate;
-- 5 rows: Customers, Departments, Employees, Orders, Products. Only OrderDetails could be truncated.
GO

-- Q4
DROP TABLE IF EXISTS dbo.L03_Ex_ItemTags;
DROP TABLE IF EXISTS dbo.L03_Ex_Items;
DROP TABLE IF EXISTS dbo.L03_Ex_Categories;
GO
CREATE TABLE dbo.L03_Ex_Categories
(
    CategoryID   INT         NOT NULL IDENTITY(1,1),
    CategoryName VARCHAR(50) NOT NULL,
    CONSTRAINT PK_L03_Ex_Categories      PRIMARY KEY (CategoryID),
    CONSTRAINT UQ_L03_Ex_Categories_Name UNIQUE (CategoryName)
);
INSERT INTO dbo.L03_Ex_Categories (CategoryName) VALUES ('Electronics'), ('Furniture'), ('Stationery');
GO
BEGIN TRY
    INSERT INTO dbo.L03_Ex_Categories (CategoryName) VALUES ('Furniture');
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();   -- Violation of UNIQUE KEY constraint 'UQ_L03_Ex_Categories_Name'
END CATCH
GO

-- Q5
CREATE TABLE dbo.L03_Ex_Items
(
    ItemID     INT           NOT NULL IDENTITY(1,1),
    ItemName   VARCHAR(100)  NOT NULL,
    CategoryID INT           NOT NULL,
    Price      DECIMAL(10,2) NOT NULL,
    Stock      INT           NOT NULL CONSTRAINT DF_L03_Ex_Items_Stock     DEFAULT (0),
    CreatedAt  DATETIME2(0)  NOT NULL CONSTRAINT DF_L03_Ex_Items_CreatedAt DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_L03_Ex_Items            PRIMARY KEY (ItemID),
    CONSTRAINT FK_L03_Ex_Items_Categories FOREIGN KEY (CategoryID)
        REFERENCES dbo.L03_Ex_Categories (CategoryID) ON DELETE CASCADE,
    CONSTRAINT CK_L03_Ex_Items_Price      CHECK (Price >= 0)
);
INSERT INTO dbo.L03_Ex_Items (ItemName, CategoryID, Price)
VALUES ('Laptop', 1, 75000), ('Chair', 2, 8000), ('Pen', 3, 10);
SELECT * FROM dbo.L03_Ex_Items;   -- 3 rows, Stock 0, CreatedAt = now
GO

-- Q6
BEGIN TRY
    INSERT INTO dbo.L03_Ex_Items (ItemName, CategoryID, Price) VALUES ('Bad price', 1, -5);
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();   -- CHECK constraint CK_L03_Ex_Items_Price
END CATCH
GO
BEGIN TRY
    INSERT INTO dbo.L03_Ex_Items (ItemName, CategoryID, Price) VALUES ('Bad category', 99, 5);
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();   -- FOREIGN KEY constraint FK_L03_Ex_Items_Categories
END CATCH
GO
BEGIN TRY
    INSERT INTO dbo.L03_Ex_Items (ItemName, CategoryID, Price) VALUES (NULL, 1, 5);
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();   -- Cannot insert the value NULL into column 'ItemName'
END CATCH
GO

-- Q7
DECLARE @NewId INT;
INSERT INTO dbo.L03_Ex_Items (ItemName, CategoryID, Price) VALUES ('Desk', 2, 15000);
SET @NewId = SCOPE_IDENTITY();
PRINT 'New ItemID = ' + CAST(@NewId AS VARCHAR(10));                 -- 7 (ids 4, 5, 6 were burnt by the 3 failed inserts in Q6)
SELECT IDENT_CURRENT('dbo.L03_Ex_Items') AS LastIdOfTable;           -- 7
GO
-- Note: even FAILED inserts consume identity values. Gaps are normal.

-- Q8
DELETE FROM dbo.L03_Ex_Categories WHERE CategoryName = 'Furniture';
SELECT ItemID, ItemName, CategoryID FROM dbo.L03_Ex_Items;   -- 2 rows left: Laptop, Pen (Chair and Desk cascaded away)
GO

-- Q9
BEGIN TRAN;
    INSERT INTO dbo.L03_Ex_Items (ItemName, CategoryID, Price) VALUES ('Rolled back', 1, 1);   -- takes id 8
ROLLBACK;
INSERT INTO dbo.L03_Ex_Items (ItemName, CategoryID, Price) VALUES ('Mouse', 1, 1000);          -- gets id 9
SELECT ItemID, ItemName FROM dbo.L03_Ex_Items;   -- 1, 3, 9  -> gap at 8
GO
DECLARE @max INT = (SELECT MAX(ItemID) FROM dbo.L03_Ex_Items);
DBCC CHECKIDENT ('dbo.L03_Ex_Items', RESEED, @max) WITH NO_INFOMSGS;   -- next id = 10
GO

-- Q10
UPDATE dbo.L03_Ex_Items SET Stock = 5000 WHERE ItemName = 'Pen';
ALTER TABLE dbo.L03_Ex_Items WITH NOCHECK ADD CONSTRAINT CK_L03_Ex_Items_StockMax CHECK (Stock <= 1000);
SELECT name, is_not_trusted FROM sys.check_constraints WHERE name = 'CK_L03_Ex_Items_StockMax';   -- 1
GO
BEGIN TRY
    ALTER TABLE dbo.L03_Ex_Items WITH CHECK CHECK CONSTRAINT CK_L03_Ex_Items_StockMax;
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();   -- conflicted with the CHECK constraint
END CATCH
GO
UPDATE dbo.L03_Ex_Items SET Stock = 1000 WHERE ItemName = 'Pen';
ALTER TABLE dbo.L03_Ex_Items WITH CHECK CHECK CONSTRAINT CK_L03_Ex_Items_StockMax;
SELECT name, is_not_trusted FROM sys.check_constraints WHERE name = 'CK_L03_Ex_Items_StockMax';   -- 0
GO

-- Q11
CREATE TABLE dbo.L03_Ex_ItemTags
(
    ItemID INT         NOT NULL,
    Tag    VARCHAR(20) NOT NULL,
    CONSTRAINT PK_L03_Ex_ItemTags       PRIMARY KEY (ItemID, Tag),
    CONSTRAINT FK_L03_Ex_ItemTags_Items FOREIGN KEY (ItemID) REFERENCES dbo.L03_Ex_Items (ItemID)
);
INSERT INTO dbo.L03_Ex_ItemTags (ItemID, Tag) VALUES (1, 'premium'), (1, 'portable'), (9, 'portable');
GO
BEGIN TRY
    INSERT INTO dbo.L03_Ex_ItemTags (ItemID, Tag) VALUES (1, 'premium');
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();   -- Violation of PRIMARY KEY constraint ... (1, premium)
END CATCH
GO

-- Q12
SELECT OBJECT_NAME(parent_object_id) AS TableName, name, definition
FROM sys.check_constraints
WHERE OBJECT_NAME(parent_object_id) LIKE 'L03[_]Ex[_]%'
ORDER BY TableName, name;   -- 2 rows: CK_L03_Ex_Items_Price, CK_L03_Ex_Items_StockMax
GO
DROP TABLE IF EXISTS dbo.L03_Ex_ItemTags;     -- children first
DROP TABLE IF EXISTS dbo.L03_Ex_Items;
DROP TABLE IF EXISTS dbo.L03_Ex_Categories;
GO
