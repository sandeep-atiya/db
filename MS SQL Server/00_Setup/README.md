# 00_Setup — Practice Database (`SQLPractice`)

One small **Company / Sales** dataset is used by **every level**, so you never have to
re-learn a new schema. Rows are few enough to predict results by hand.

## Files

| File | What it does | When to run |
|------|--------------|-------------|
| `00_Reset_All.sql` | Drop + create DB, tables, data (= 01 + 02 + 03) | **First time**, and any time you want clean data |
| `01_Create_Database.sql` | Creates `SQLPractice` | Read to learn `CREATE DATABASE` |
| `02_Create_Tables.sql` | 6 tables with PK / FK / UNIQUE / CHECK / DEFAULT / IDENTITY | Read to learn table design |
| `03_Insert_Sample_Data.sql` | Loads the rows + sanity check | Read to see the data |

> Run from SSMS: open file → **F5**.
> Run from terminal: `sqlcmd -S localhost -E -C -i "00_Reset_All.sql"`

## Data model

```
 Departments (6)                       Customers (8)
 ─────────────                         ─────────────
 DepartmentID  PK                      CustomerID   PK
 DepartmentName UNIQUE                 CustomerName
 Location                              Email        (NULL for 2)
      │ 1                              City
      │                                CreatedDate
      │ *                                   │ 1
 Employees (12)                             │
 ─────────────                              │ *
 EmployeeID   PK                       Orders (19)
 EmployeeName                          ─────────────
 Email        UNIQUE (NULL for 1)      OrderID      PK
 DepartmentID FK → Departments (NULL for 1)   CustomerID   FK → Customers
 Salary       CHECK > 0                EmployeeID   FK → Employees (NULL for 1)
 HireDate                              OrderDate    (Jan–Sep 2025)
 ManagerID    FK → Employees (self)    TotalAmount
      │ 1                              Status       CHECK IN (Pending, Completed, Cancelled)
      │                                     │ 1
      │ *  (salesperson)                    │
      └──────────────────────────────►      │ *
                                       OrderDetails (26)
 Products (11)                         ─────────────
 ─────────────                         OrderDetailID PK IDENTITY
 ProductID    PK        1 ────────── * OrderID       FK → Orders
 ProductName                           ProductID     FK → Products
 Category  (Electronics/Furniture/Stationery)   Quantity  CHECK > 0
 Price        CHECK >= 0               UnitPrice
 Stock        CHECK >= 0
```

## Built-in "tricky" cases (interview favourites)

| Case | Where | Used in |
|------|-------|---------|
| Employee with **no department** (Anjali, 110) | `Employees.DepartmentID IS NULL` | LEFT JOIN, NOT IN vs NOT EXISTS |
| Department with **no employees** (Legal, 6) | `Departments` | RIGHT / FULL JOIN, anti-join |
| **Duplicate salaries** (Amit & Pooja = 65000) | `Employees.Salary` | RANK vs DENSE_RANK vs ROW_NUMBER |
| Self reference (ManagerID) | `Employees` | SELF JOIN, recursive CTE |
| Customer with **no orders** (Hina, 8) | `Customers` | NOT EXISTS, LEFT JOIN … IS NULL |
| Customers with **NULL email** (6, 8) | `Customers.Email` | IS NULL, ISNULL / COALESCE |
| Product **never ordered** (Webcam, 11) | `Products` | anti-join |
| Product with **0 stock** (Headphones, 9) | `Products.Stock` | NULLIF divide-by-zero |
| Order with **no salesperson** (1019) | `Orders.EmployeeID IS NULL` | outer joins |
| Order **Status** Pending / Cancelled | `Orders.Status` | CASE, filtered index, conditional aggregation |
| Orders spread over 9 months | `Orders.OrderDate` | GROUP BY month, running totals, LAG/LEAD |

## Quick look queries

```sql
USE SQLPractice;
SELECT * FROM dbo.Departments;
SELECT * FROM dbo.Employees;
SELECT * FROM dbo.Customers;
SELECT * FROM dbo.Products;
SELECT * FROM dbo.Orders;
SELECT * FROM dbo.OrderDetails;
```
