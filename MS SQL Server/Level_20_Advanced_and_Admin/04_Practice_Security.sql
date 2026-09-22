/* ============================================================
   LEVEL 20 - ADVANCED AND ADMIN  |  04_Practice_Security.sql
   ------------------------------------------------------------
   Topics : logins (server) vs users (database) vs roles, authentication
            modes, CREATE LOGIN / CREATE USER, fixed server roles and fixed
            database roles (catalog views), custom database roles, GRANT /
            DENY / REVOKE on table, schema and column, testing with
            EXECUTE AS USER ... REVERT, DENY beats GRANT, ownership chaining
            (view / proc without table rights), fn_my_permissions /
            HAS_PERMS_BY_NAME, schema as a security boundary, least
            privilege, orphaned users (sp_change_users_login / ALTER USER
            WITH LOGIN), contained users.

   HOW TO PRACTICE: run block by block, predict the output first.
   Creates ONE server login (L20_TestLogin) - dropped in CLEANUP.
   ============================================================ */

USE SQLPractice;
GO
SET NOCOUNT ON;
GO


/* ============================================================
   1. THE THREE LAYERS: LOGIN (server door) -> USER (database door) -> ROLE / PERMISSION (what you may do)
   ============================================================
   LOGIN  = a server principal (master DB): can connect to the INSTANCE. Windows login or SQL login (password).
   USER   = a database principal: the login's identity INSIDE one database (mapped by SID).
   ROLE   = a group of users (or logins) that carries permissions. Fixed roles are built in; custom roles are yours.
   ============================================================ */
-- 1a. Authentication mode: 1 = Windows only, 0 = Mixed (Windows + SQL logins)
SELECT SERVERPROPERTY('IsIntegratedSecurityOnly') AS WindowsOnly,        -- 0 on this box (mixed); a SQL login can connect
       SUSER_SNAME() AS MyLogin, USER_NAME() AS MyDatabaseUser, IS_SRVROLEMEMBER('sysadmin') AS AmISysadmin;   -- ... dbo, 1
GO
-- 1b. CREATE LOGIN (server level). In Windows-only mode the CREATE still works, the login just cannot connect.
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'L20_TestLogin') DROP LOGIN L20_TestLogin;
CREATE LOGIN L20_TestLogin WITH PASSWORD = 'L20_Str0ng!Pass', CHECK_POLICY = OFF;   -- CHECK_POLICY OFF only for this demo
-- Windows login syntax (comment): CREATE LOGIN [MYDOMAIN\ravi] FROM WINDOWS;
SELECT name, type_desc, is_disabled, create_date FROM sys.server_principals WHERE name = 'L20_TestLogin';   -- SQL_LOGIN
GO
-- 1c. FIXED SERVER ROLES (sysadmin, serveradmin, securityadmin, dbcreator, bulkadmin, processadmin, ...)
SELECT name FROM sys.server_principals WHERE type = 'R' AND is_fixed_role = 1 AND name NOT LIKE '##%' ORDER BY name;   -- 8 rows
ALTER SERVER ROLE dbcreator ADD MEMBER L20_TestLogin;       -- may create databases
SELECT r.name AS ServerRole, m.name AS Member
FROM sys.server_role_members rm
JOIN sys.server_principals r ON r.principal_id = rm.role_principal_id
JOIN sys.server_principals m ON m.principal_id = rm.member_principal_id
WHERE m.name = 'L20_TestLogin';                              -- dbcreator / L20_TestLogin
ALTER SERVER ROLE dbcreator DROP MEMBER L20_TestLogin;       -- least privilege: take it away again
GO


/* ============================================================
   2. USERS AND FIXED DATABASE ROLES
   ============================================================ */
-- 2a. A login can enter this database only through a USER mapped to it
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'L20_TestUser') DROP USER L20_TestUser;
CREATE USER L20_TestUser FOR LOGIN L20_TestLogin;            -- default schema dbo
SELECT dp.name, dp.type_desc, dp.default_schema_name, sp.name AS MappedLogin
FROM sys.database_principals dp
LEFT JOIN sys.server_principals sp ON sp.sid = dp.sid       -- SID links user <-> login
WHERE dp.name = 'L20_TestUser';                              -- SQL_USER, dbo, L20_TestLogin
GO
-- 2b. FIXED DATABASE ROLES: db_owner (everything), db_datareader (SELECT all), db_datawriter (INSERT/UPDATE/DELETE all),
--     db_ddladmin (CREATE/ALTER/DROP objects), db_securityadmin, db_accessadmin, db_backupoperator, db_denydatareader/writer
SELECT name FROM sys.database_principals WHERE type = 'R' AND is_fixed_role = 1 ORDER BY name;   -- 9 rows
ALTER ROLE db_datareader ADD MEMBER L20_TestUser;            -- read everything...
SELECT r.name AS RoleName, m.name AS MemberName
FROM sys.database_role_members rm
JOIN sys.database_principals r ON r.principal_id = rm.role_principal_id
JOIN sys.database_principals m ON m.principal_id = rm.member_principal_id
WHERE m.name = 'L20_TestUser';                               -- db_datareader / L20_TestUser
ALTER ROLE db_datareader DROP MEMBER L20_TestUser;           -- ... but that is more than a report user needs
GO


/* ============================================================
   3. CUSTOM ROLE + GRANT on a SCHEMA (the normal way to give access)
   ============================================================ */
DROP ROLE IF EXISTS L20_ReportReaders;
CREATE ROLE L20_ReportReaders;                               -- roles are cheap: grant to the role, add/remove people
ALTER ROLE L20_ReportReaders ADD MEMBER L20_TestUser;
GRANT SELECT ON SCHEMA::dbo TO L20_ReportReaders;            -- every current AND future table/view in dbo
GO
-- 3a. Test as that user: EXECUTE AS USER switches the security context of the session; REVERT switches back.
EXECUTE AS USER = 'L20_TestUser';
SELECT USER_NAME() AS WhoAmI, IS_MEMBER('L20_ReportReaders') AS InRole;    -- L20_TestUser, 1
SELECT COUNT(*) AS CanReadEmployees FROM dbo.Employees;                    -- 12
BEGIN TRY
    UPDATE dbo.Departments SET Location = 'Goa' WHERE DepartmentID = 6;    -- no UPDATE permission
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();                            -- The UPDATE permission was denied on the object 'Departments'
END CATCH
REVERT;
SELECT USER_NAME() AS BackTo;                                              -- dbo
GO


/* ============================================================
   4. DENY on a COLUMN, fn_my_permissions, HAS_PERMS_BY_NAME
   ============================================================ */
-- 4a. Before the DENY: the user has SELECT on the table and on every column
EXECUTE AS USER = 'L20_TestUser';
SELECT entity_name, subentity_name, permission_name FROM fn_my_permissions('dbo.Employees', 'OBJECT') ORDER BY subentity_name;   -- SELECT on '' (table) + 7 columns
SELECT HAS_PERMS_BY_NAME('dbo.Employees', 'OBJECT', 'SELECT') AS CanSelectTable;                                                -- 1
REVERT;
GO
-- 4b. Hide the salary column from this user
DENY SELECT ON dbo.Employees (Salary) TO L20_TestUser;
GO
EXECUTE AS USER = 'L20_TestUser';
SELECT TOP (2) EmployeeID, EmployeeName FROM dbo.Employees ORDER BY EmployeeID;   -- works: 101 Rahul, 102 Amit
BEGIN TRY
    SELECT TOP (1) EmployeeName, Salary FROM dbo.Employees;                       -- includes Salary -> denied
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();                                   -- The SELECT permission was denied on the column 'Salary' ...
END CATCH
BEGIN TRY
    SELECT TOP (1) * FROM dbo.Employees;                                          -- SELECT * also touches Salary -> denied
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
SELECT entity_name, subentity_name, permission_name FROM fn_my_permissions('dbo.Employees', 'OBJECT') ORDER BY subentity_name;   -- 6 column rows, no table row, no Salary
SELECT HAS_PERMS_BY_NAME('dbo.Employees', 'OBJECT', 'SELECT')                          AS CanSelectTable,   -- 0 (one column denied = no table-level SELECT)
       HAS_PERMS_BY_NAME('dbo.Employees', 'OBJECT', 'SELECT', 'EmployeeName', 'COLUMN') AS CanSelectName,    -- 1
       HAS_PERMS_BY_NAME('dbo.Employees', 'OBJECT', 'SELECT', 'Salary', 'COLUMN')       AS CanSelectSalary;  -- 0
REVERT;
GO


/* ============================================================
   5. GRANT vs DENY vs REVOKE - DENY always wins
   ============================================================ */
-- The user gets an explicit GRANT on Products, but the ROLE he belongs to gets a DENY -> denied.
GRANT SELECT ON dbo.Products TO L20_TestUser;
DENY  SELECT ON dbo.Products TO L20_ReportReaders;
GO
EXECUTE AS USER = 'L20_TestUser';
BEGIN TRY
    SELECT TOP (1) ProductName FROM dbo.Products;
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();                -- denied: a DENY anywhere in the chain beats every GRANT
END CATCH
REVERT;
GO
-- REVOKE removes an entry (a GRANT or a DENY) - it is not "deny". After both revokes the schema GRANT applies again.
REVOKE SELECT ON dbo.Products FROM L20_ReportReaders;
REVOKE SELECT ON dbo.Products FROM L20_TestUser;
GO
EXECUTE AS USER = 'L20_TestUser';
SELECT COUNT(*) AS ProductsVisibleAgain FROM dbo.Products;     -- 11 (through GRANT SELECT ON SCHEMA::dbo)
REVERT;
GO
-- What is granted to whom in this database:
SELECT pr.name AS Principal, pe.state_desc, pe.permission_name, pe.class_desc,
       COALESCE(OBJECT_NAME(pe.major_id), SCHEMA_NAME(pe.major_id)) AS OnObjectOrSchema,
       COL_NAME(pe.major_id, pe.minor_id) AS OnColumn
FROM sys.database_permissions pe
JOIN sys.database_principals pr ON pr.principal_id = pe.grantee_principal_id
WHERE pr.name LIKE 'L20_%';                                    -- GRANT SELECT SCHEMA dbo (role), DENY SELECT Employees.Salary (user), CONNECT (user)
GO


/* ============================================================
   6. OWNERSHIP CHAINING - run a proc / view without rights on the table
   ============================================================ */
-- When a proc/view and the tables it uses have the SAME owner (dbo), SQL Server checks permission
-- only on the proc/view, not on the tables. This is how you give "run this report" without "read the table".
DROP USER IF EXISTS L20_ProcUser;
CREATE USER L20_ProcUser WITHOUT LOGIN;                        -- a user with no login: handy for tests and for EXECUTE AS in procs
GO
CREATE OR ALTER PROCEDURE dbo.usp_L20_TopSalaries
AS
    SELECT TOP (3) EmployeeName, Salary FROM dbo.Employees ORDER BY Salary DESC;
GO
GRANT EXECUTE ON dbo.usp_L20_TopSalaries TO L20_ProcUser;       -- ONLY execute on the proc, nothing on Employees
GO
EXECUTE AS USER = 'L20_ProcUser';
BEGIN TRY
    SELECT TOP (1) EmployeeName FROM dbo.Employees;            -- denied: no rights on the table
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
EXEC dbo.usp_L20_TopSalaries;                                  -- works: Sneha 90000, Rahul 85000, Priya 75000
REVERT;
GO
-- 6b. GOTCHA: the chain skips DENY too. L20_TestUser is denied Salary on the table, yet a dbo-owned VIEW
--     that selects Salary works, because the table is never checked. Secure the view/proc layer itself.
CREATE OR ALTER VIEW dbo.vw_L20_SalaryReport AS SELECT EmployeeName, Salary FROM dbo.Employees;
GO
EXECUTE AS USER = 'L20_TestUser';
SELECT TOP (1) EmployeeName, Salary FROM dbo.vw_L20_SalaryReport ORDER BY Salary DESC;   -- Sneha 90000 - despite the column DENY
REVERT;
GO
-- (Chaining breaks when owners differ, e.g. a view in a schema owned by another user -> then the table IS checked.)


/* ============================================================
   7. SCHEMA AS A SECURITY BOUNDARY + LEAST PRIVILEGE
   ============================================================ */
-- Put report objects in their own schema, grant the schema to the report role, nothing else.
IF SCHEMA_ID('L20_Reports') IS NULL EXEC ('CREATE SCHEMA L20_Reports;');   -- CREATE SCHEMA must be alone in a batch -> EXEC
GO
CREATE OR ALTER VIEW L20_Reports.vw_OrdersPerCity AS
SELECT c.City, COUNT(o.OrderID) AS Orders FROM dbo.Customers c LEFT JOIN dbo.Orders o ON o.CustomerID = c.CustomerID GROUP BY c.City;
GO
GRANT SELECT ON SCHEMA::L20_Reports TO L20_ProcUser;           -- one statement covers every current and future report view
GO
EXECUTE AS USER = 'L20_ProcUser';
SELECT * FROM L20_Reports.vw_OrdersPerCity ORDER BY City;      -- 5 rows (Bangalore 2, Chennai 2, Delhi 7, Mumbai 6, Pune 2)
BEGIN TRY
    SELECT * FROM dbo.Customers;                               -- still no access to dbo
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
REVERT;
GO
/* PRINCIPLE OF LEAST PRIVILEGE (interview answer)
   Give each login/user/application the MINIMUM it needs: a role per job function, grants on schemas
   or procs (not db_owner / sysadmin), separate logins for apps and people, no shared sa password,
   DENY sensitive columns, review with sys.database_permissions and fn_my_permissions.                */


/* ============================================================
   8. ORPHANED USERS - the login is gone (or has a different SID after a restore on another server)
   ============================================================ */
-- 8a. Create the problem: drop and re-create the login -> new SID -> the user's SID no longer matches
DROP LOGIN L20_TestLogin;
CREATE LOGIN L20_TestLogin WITH PASSWORD = 'L20_Str0ng!Pass', CHECK_POLICY = OFF;
GO
-- 8b. Find orphans (modern query) and the legacy report
SELECT dp.name AS OrphanUser, dp.sid
FROM sys.database_principals dp
LEFT JOIN sys.server_principals sp ON sp.sid = dp.sid
WHERE dp.type IN ('S', 'U') AND dp.authentication_type_desc = 'INSTANCE' AND sp.sid IS NULL;   -- L20_TestUser
EXEC sp_change_users_login 'Report';                            -- deprecated but still asked: lists UserName + UserSID
GO
-- 8c. Fix: re-map the user to the login (sp_change_users_login 'Update_One' is the old way)
ALTER USER L20_TestUser WITH LOGIN = L20_TestLogin;
SELECT dp.name, sp.name AS LoginName FROM sys.database_principals dp JOIN sys.server_principals sp ON sp.sid = dp.sid
WHERE dp.name = 'L20_TestUser';                                 -- mapped again
GO
-- 8d. CONTAINED DATABASE USERS (mention): with CONTAINMENT = PARTIAL a user can have its OWN password
--     (CREATE USER app_user WITH PASSWORD = '...') and needs no login at all -> no orphan problem after a restore.
--     Azure SQL Database works this way by default.


/* ============================================================
   9. CLEANUP - user, role, schema objects, proc, login (server-level!)
   ============================================================ */
REVERT;                                                         -- safety: make sure we are dbo again
DROP VIEW IF EXISTS dbo.vw_L20_SalaryReport;
DROP VIEW IF EXISTS L20_Reports.vw_OrdersPerCity;
IF SCHEMA_ID('L20_Reports') IS NOT NULL EXEC ('DROP SCHEMA L20_Reports;');
DROP PROCEDURE IF EXISTS dbo.usp_L20_TopSalaries;
DROP USER IF EXISTS L20_ProcUser;
DROP USER IF EXISTS L20_TestUser;
DROP ROLE IF EXISTS L20_ReportReaders;
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'L20_TestLogin') DROP LOGIN L20_TestLogin;
GO
SELECT COUNT(*) AS LeftoverPrincipals FROM sys.database_principals WHERE name LIKE 'L20_%';   -- 0
SELECT COUNT(*) AS LeftoverLogins FROM sys.server_principals WHERE name LIKE 'L20_%';         -- 0
GO
/* DONE. Next: 05_Practice_Backup_Restore_Agent.sql */
