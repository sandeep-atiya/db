/* ============================================================
   LEVEL 01 - DATABASE BASICS  |  Exercises.sql
   ------------------------------------------------------------
   Try each question in the "YOUR ANSWER" area FIRST.
   Then scroll down to SOLUTIONS and compare.
   Uses SQLPractice (Q1-Q10) and a throwaway DB (Q11).
   ============================================================ */

USE SQLPractice;
GO

/* ------------------------------------------------------------
   QUESTIONS
   ------------------------------------------------------------
   Q1.  Show all databases on the server (name + creation date).
   Q2.  Show the name of the current database.
   Q3.  Show all tables in SQLPractice with their schema name.
   Q4.  Show the columns of dbo.Employees (name, type, nullable).
   Q5.  Show all employees.
   Q6.  Show only EmployeeName, Salary, HireDate.
   Q7.  Show employees whose salary is greater than 70000.
   Q8.  Show employees from the IT department (DepartmentID = 1).
   Q9.  Sort employees by salary, highest first.
   Q10. Find the total number of employees.

   Q11. (DDL drill) Create a database MyFirstDB, switch to it,
        create a schema Inventory, create a table Inventory.Items
        (ItemID INT PK, ItemName VARCHAR(50) NOT NULL),
        add a column Qty INT, change ItemName to VARCHAR(100),
        rename Qty to Quantity, then drop the table, the schema
        and finally the database.
   ------------------------------------------------------------ */

-- YOUR ANSWERS HERE (write below, run, compare)










/* ============================================================
   SOLUTIONS
   ============================================================ */

-- Q1
SELECT name, create_date FROM sys.databases ORDER BY name;

-- Q2
SELECT DB_NAME() AS CurrentDatabase;

-- Q3
SELECT s.name AS SchemaName, t.name AS TableName
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id = t.schema_id
ORDER BY t.name;
-- alternative: SELECT TABLE_SCHEMA, TABLE_NAME FROM INFORMATION_SCHEMA.TABLES;

-- Q4
SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'Employees'
ORDER BY ORDINAL_POSITION;
-- alternative: EXEC sp_help 'dbo.Employees';

-- Q5
SELECT * FROM dbo.Employees;

-- Q6
SELECT EmployeeName, Salary, HireDate FROM dbo.Employees;

-- Q7
SELECT EmployeeName, Salary FROM dbo.Employees WHERE Salary > 70000;

-- Q8
SELECT EmployeeName, DepartmentID FROM dbo.Employees WHERE DepartmentID = 1;
-- (After Level 08 you will write this with a JOIN on DepartmentName = 'IT')

-- Q9
SELECT EmployeeName, Salary FROM dbo.Employees ORDER BY Salary DESC;

-- Q10
SELECT COUNT(*) AS TotalEmployees FROM dbo.Employees;
GO

-- Q11
USE master;
GO
DROP DATABASE IF EXISTS MyFirstDB;
GO
CREATE DATABASE MyFirstDB;
GO
USE MyFirstDB;
GO
CREATE SCHEMA Inventory;
GO
CREATE TABLE Inventory.Items
(
    ItemID   INT         NOT NULL PRIMARY KEY,
    ItemName VARCHAR(50) NOT NULL
);
GO
ALTER TABLE Inventory.Items ADD Qty INT NULL;
GO
ALTER TABLE Inventory.Items ALTER COLUMN ItemName VARCHAR(100) NOT NULL;
GO
EXEC sp_rename 'Inventory.Items.Qty', 'Quantity', 'COLUMN';
GO
SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH
FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'Items';
GO
DROP TABLE Inventory.Items;
GO
DROP SCHEMA Inventory;
GO
USE master;
GO
DROP DATABASE MyFirstDB;
GO
