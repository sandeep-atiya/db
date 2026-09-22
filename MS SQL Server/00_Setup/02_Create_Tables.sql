/* ============================================================
   00_SETUP  |  02_Create_Tables.sql
   ------------------------------------------------------------
   Creates the 6 tables used by EVERY level.
   Safe to re-run: existing tables are dropped in FK-safe order
   (children first, then parents).

   DATA MODEL  (one Company / Sales dataset)

     Departments 1 ---< Employees >--- (self) Employees.ManagerID
                              |
                              | (Orders.EmployeeID = salesperson)
                              v
     Customers   1 ---< Orders 1 ---< OrderDetails >--- 1 Products
   ============================================================ */

USE SQLPractice;
GO

/* ---------- Drop in dependency order (children -> parents) ---------- */
DROP TABLE IF EXISTS dbo.OrderDetails;
DROP TABLE IF EXISTS dbo.Orders;
DROP TABLE IF EXISTS dbo.Employees;
DROP TABLE IF EXISTS dbo.Departments;
DROP TABLE IF EXISTS dbo.Customers;
DROP TABLE IF EXISTS dbo.Products;
GO

/* ---------- 1. Departments (parent of Employees) ---------- */
CREATE TABLE dbo.Departments
(
    DepartmentID   INT          NOT NULL,
    DepartmentName VARCHAR(100) NOT NULL,
    Location       VARCHAR(100) NULL,

    CONSTRAINT PK_Departments PRIMARY KEY (DepartmentID),
    CONSTRAINT UQ_Departments_Name UNIQUE (DepartmentName)
);
GO

/* ---------- 2. Employees (child of Departments, self-referencing via ManagerID) ---------- */
CREATE TABLE dbo.Employees
(
    EmployeeID   INT           NOT NULL,
    EmployeeName VARCHAR(100)  NOT NULL,
    Email        VARCHAR(150)  NULL,
    DepartmentID INT           NULL,          -- NULL = contractor / not assigned
    Salary       DECIMAL(12,2) NULL,
    HireDate     DATE          NULL,
    ManagerID    INT           NULL,          -- NULL = top-level (no manager)

    CONSTRAINT PK_Employees            PRIMARY KEY (EmployeeID),
    CONSTRAINT UQ_Employees_Email      UNIQUE (Email),
    CONSTRAINT CK_Employees_Salary     CHECK (Salary > 0),
    CONSTRAINT FK_Employees_Departments FOREIGN KEY (DepartmentID)
        REFERENCES dbo.Departments (DepartmentID),
    CONSTRAINT FK_Employees_Manager    FOREIGN KEY (ManagerID)
        REFERENCES dbo.Employees (EmployeeID)      -- self join key
);
GO

/* ---------- 3. Customers ---------- */
CREATE TABLE dbo.Customers
(
    CustomerID   INT          NOT NULL,
    CustomerName VARCHAR(100) NOT NULL,
    Email        VARCHAR(150) NULL,            -- some NULLs on purpose (IS NULL practice)
    City         VARCHAR(100) NULL,
    CreatedDate  DATE         NULL,

    CONSTRAINT PK_Customers PRIMARY KEY (CustomerID)
);
GO

/* ---------- 4. Products ---------- */
CREATE TABLE dbo.Products
(
    ProductID   INT           NOT NULL,
    ProductName VARCHAR(100)  NOT NULL,
    Category    VARCHAR(100)  NULL,
    Price       DECIMAL(12,2) NULL,
    Stock       INT           NULL,

    CONSTRAINT PK_Products      PRIMARY KEY (ProductID),
    CONSTRAINT CK_Products_Price CHECK (Price >= 0),
    CONSTRAINT CK_Products_Stock CHECK (Stock >= 0)
);
GO

/* ---------- 5. Orders (child of Customers and Employees) ---------- */
CREATE TABLE dbo.Orders
(
    OrderID     INT           NOT NULL,
    CustomerID  INT           NOT NULL,
    EmployeeID  INT           NULL,            -- NULL = online order, no salesperson
    OrderDate   DATE          NULL,
    TotalAmount DECIMAL(12,2) NULL,
    Status      VARCHAR(20)   NOT NULL
        CONSTRAINT DF_Orders_Status DEFAULT ('Completed'),

    CONSTRAINT PK_Orders           PRIMARY KEY (OrderID),
    CONSTRAINT CK_Orders_Status    CHECK (Status IN ('Pending', 'Completed', 'Cancelled')),
    CONSTRAINT FK_Orders_Customers FOREIGN KEY (CustomerID)
        REFERENCES dbo.Customers (CustomerID),
    CONSTRAINT FK_Orders_Employees FOREIGN KEY (EmployeeID)
        REFERENCES dbo.Employees (EmployeeID)
);
GO

/* ---------- 6. OrderDetails (child of Orders and Products) ---------- */
CREATE TABLE dbo.OrderDetails
(
    OrderDetailID INT           NOT NULL IDENTITY(1,1),   -- auto number
    OrderID       INT           NOT NULL,
    ProductID     INT           NOT NULL,
    Quantity      INT           NOT NULL,
    UnitPrice     DECIMAL(12,2) NOT NULL,                 -- price at time of sale

    CONSTRAINT PK_OrderDetails          PRIMARY KEY (OrderDetailID),
    CONSTRAINT CK_OrderDetails_Quantity CHECK (Quantity > 0),
    CONSTRAINT FK_OrderDetails_Orders   FOREIGN KEY (OrderID)
        REFERENCES dbo.Orders (OrderID),
    CONSTRAINT FK_OrderDetails_Products FOREIGN KEY (ProductID)
        REFERENCES dbo.Products (ProductID)
);
GO

/* ---------- Verify ---------- */
SELECT s.name AS SchemaName, t.name AS TableName, t.create_date
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id = t.schema_id
ORDER BY t.name;
GO
