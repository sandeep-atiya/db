/* ============================================================
   LEVEL 20 - ADVANCED AND ADMIN  |  03_Practice_JSON_XML.sql
   ------------------------------------------------------------
   Topics : JSON - FOR JSON AUTO / PATH (ROOT, INCLUDE_NULL_VALUES,
            WITHOUT_ARRAY_WRAPPER), nested order + lines, ISJSON,
            JSON_VALUE, JSON_QUERY, JSON_MODIFY, OPENJSON (default and
            WITH schema, nested arrays via CROSS APPLY), storing JSON with
            a CHECK constraint, indexing JSON through a computed column,
            JSON_OBJECT / JSON_ARRAY (2022+), the native json type (2025);
            XML - FOR XML RAW / AUTO / PATH (EXPLICIT mentioned), ROOT,
            ELEMENTS, the FOR XML PATH('') + STUFF trick, the XML type,
            .value() / .query() / .nodes() / .exist(), OPENXML,
            XML vs JSON.

   HOW TO PRACTICE: run block by block, predict the output first.
   ============================================================ */

USE SQLPractice;
GO
SET QUOTED_IDENTIFIER ON;      -- XML methods need it (sqlcmd default is OFF)
SET NOCOUNT ON;
GO


/* ============================================================
   1. FOR JSON - rows -> JSON text
   ============================================================ */
-- 1a. AUTO: nesting follows the joins; column names become keys
SELECT TOP (2) c.CustomerID, c.CustomerName, o.OrderID, o.TotalAmount
FROM dbo.Customers c JOIN dbo.Orders o ON o.CustomerID = c.CustomerID
WHERE c.CustomerID = 1
ORDER BY o.OrderID
FOR JSON AUTO;                                  -- [{"CustomerID":1,"CustomerName":"Aarav Sharma","o":[{"OrderID":1001,...},{...}]}]
GO
-- 1b. PATH: you control the shape with dotted aliases; ROOT wraps everything; NULLs are skipped unless INCLUDE_NULL_VALUES
SELECT CustomerID AS 'id', CustomerName AS 'name', Email AS 'contact.email', City AS 'contact.city'
FROM dbo.Customers WHERE CustomerID IN (1, 6)
FOR JSON PATH, ROOT('customers'), INCLUDE_NULL_VALUES;   -- {"customers":[{"id":1,"name":"Aarav Sharma","contact":{"email":"aarav@example.com","city":"Delhi"}},{"id":6,...,"contact":{"email":null,"city":"Mumbai"}}]}
GO
-- 1c. WITHOUT_ARRAY_WRAPPER: a single object instead of [ ... ] (for exactly one row)
SELECT ProductID, ProductName, Price FROM dbo.Products WHERE ProductID = 1
FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;           -- {"ProductID":1,"ProductName":"Laptop","Price":75000.00}
GO
-- 1d. NESTED: an order with its lines as an array (a correlated subquery with FOR JSON PATH)
SELECT o.OrderID, o.OrderDate, o.TotalAmount,
       (SELECT od.ProductID, p.ProductName, od.Quantity, od.UnitPrice
        FROM dbo.OrderDetails od JOIN dbo.Products p ON p.ProductID = od.ProductID
        WHERE od.OrderID = o.OrderID
        FOR JSON PATH) AS Lines
FROM dbo.Orders o
WHERE o.OrderID = 1002
FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;           -- {"OrderID":1002,"OrderDate":"2025-01-12","TotalAmount":10000.00,"Lines":[{"ProductID":4,"ProductName":"Chair",...},{"ProductID":2,...}]}
GO


/* ============================================================
   2. READING JSON: ISJSON, JSON_VALUE, JSON_QUERY, JSON_MODIFY
   ============================================================ */
DECLARE @j NVARCHAR(MAX) = N'{
  "orderId": 1002, "customer": {"id": 2, "name": "Bhavna Mehta"},
  "lines": [ {"productId": 4, "qty": 1, "price": 8000}, {"productId": 2, "qty": 2, "price": 1000} ],
  "tags": ["priority", "gift"] }';

SELECT ISJSON(@j) AS IsValid, ISJSON('{oops') AS IsNotValid;                              -- 1, 0
SELECT JSON_VALUE(@j, '$.orderId')            AS OrderId,                                 -- 1002   (scalar -> JSON_VALUE)
       JSON_VALUE(@j, '$.customer.name')      AS CustomerName,                            -- Bhavna Mehta
       JSON_VALUE(@j, '$.lines[1].qty')       AS SecondLineQty,                           -- 2      (arrays are 0-based)
       JSON_QUERY(@j, '$.customer')           AS CustomerObject,                          -- {"id": 2, "name": "Bhavna Mehta"}  (object/array -> JSON_QUERY)
       JSON_QUERY(@j, '$.tags')               AS TagsArray,                               -- ["priority", "gift"]
       JSON_VALUE(@j, '$.customer')           AS WrongFunction;                           -- NULL: JSON_VALUE cannot return an object
-- JSON_MODIFY: change / add / append / delete (returns the new text)
SELECT JSON_VALUE(JSON_MODIFY(@j, '$.customer.name', 'B. Mehta'), '$.customer.name') AS Renamed,      -- B. Mehta
       JSON_QUERY(JSON_MODIFY(@j, 'append $.tags', 'fragile'), '$.tags') AS TagAdded,                  -- ["priority", "gift","fragile"]
       JSON_MODIFY(N'{"a":1,"b":2}', '$.b', NULL) AS KeyDeleted,                                        -- {"a":1}
       JSON_MODIFY(N'{"a":1}', '$.c', JSON_QUERY(N'{"x":1}')) AS ObjectAdded;                           -- {"a":1,"c":{"x":1}} (JSON_QUERY avoids quoting)
GO


/* ============================================================
   3. OPENJSON - JSON text -> rows
   ============================================================ */
DECLARE @j NVARCHAR(MAX) = N'{"orderId": 1002, "lines": [ {"productId": 4, "qty": 1, "price": 8000}, {"productId": 2, "qty": 2, "price": 1000} ]}';
-- 3a. Default schema: key / value / type for the top level (type: 1 string, 2 number, 3 bool, 4 array, 5 object)
SELECT [key], value, type FROM OPENJSON(@j);                        -- orderId 1002 2 ; lines [...] 4
-- 3b. WITH schema: typed columns; "AS JSON" keeps a nested array as text for the next level
SELECT o.orderId, l.productId, l.qty, l.price, l.qty * l.price AS LineTotal
FROM OPENJSON(@j) WITH (orderId INT '$.orderId', lines NVARCHAR(MAX) '$.lines' AS JSON) o
CROSS APPLY OPENJSON(o.lines) WITH (productId INT '$.productId', qty INT '$.qty', price DECIMAL(12,2) '$.price') l;   -- 2 rows: 4/1/8000, 2/2/1000
GO
-- 3c. Real use: an app posts an order as JSON -> insert the lines with one INSERT ... SELECT
DROP TABLE IF EXISTS dbo.L20_IncomingLines;
CREATE TABLE dbo.L20_IncomingLines (ProductID INT, Qty INT, ProductName VARCHAR(100));
DECLARE @post NVARCHAR(MAX) = N'[{"productId": 1, "qty": 1}, {"productId": 11, "qty": 3}]';
INSERT INTO dbo.L20_IncomingLines (ProductID, Qty, ProductName)
SELECT j.productId, j.qty, p.ProductName
FROM OPENJSON(@post) WITH (productId INT, qty INT) j                 -- when the key name equals the column name, no path needed
JOIN dbo.Products p ON p.ProductID = j.productId;
SELECT * FROM dbo.L20_IncomingLines;                                  -- Laptop 1, Webcam 3
DROP TABLE dbo.L20_IncomingLines;
GO


/* ============================================================
   4. STORING JSON: NVARCHAR(MAX) + CHECK(ISJSON), and an index through a computed column
   ============================================================ */
DROP TABLE IF EXISTS dbo.L20_Events;
CREATE TABLE dbo.L20_Events
(
    EventID  INT IDENTITY PRIMARY KEY,
    Payload  NVARCHAR(MAX) NOT NULL CONSTRAINT CK_L20_Events_Json CHECK (ISJSON(Payload) = 1),   -- refuse invalid JSON
    -- a computed column that extracts one key; PERSISTED not required for indexing JSON_VALUE (deterministic)
    CustomerID AS CAST(JSON_VALUE(Payload, '$.customerId') AS INT)
);
CREATE INDEX IX_L20_Events_CustomerID ON dbo.L20_Events (CustomerID);   -- now WHERE CustomerID = 2 is a SEEK, not a JSON parse of every row
INSERT INTO dbo.L20_Events (Payload) VALUES
(N'{"customerId": 1, "type": "login"}'),
(N'{"customerId": 2, "type": "order", "amount": 2500}'),
(N'{"customerId": 2, "type": "logout"}');
GO
BEGIN TRY
    INSERT INTO dbo.L20_Events (Payload) VALUES (N'{"customerId": 3, "type": ');   -- broken JSON
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();                        -- CHECK constraint CK_L20_Events_Json
END CATCH
GO
SELECT EventID, CustomerID, JSON_VALUE(Payload, '$.type') AS EventType FROM dbo.L20_Events WHERE CustomerID = 2;   -- 2 rows (order, logout)
GO


/* ============================================================
   5. JSON_OBJECT / JSON_ARRAY (2022+) and the native json TYPE (2025)
   ============================================================ */
-- 5a. Build JSON per row without FOR JSON (handy inside expressions)
SELECT ProductID,
       JSON_OBJECT('id': ProductID, 'name': ProductName, 'price': Price, 'tags': JSON_ARRAY(Category, 'new')) AS Doc
FROM dbo.Products WHERE ProductID <= 2;         -- {"id":1,"name":"Laptop","price":75000.00,"tags":["Electronics","new"]} ...
GO
-- 5b. SQL Server 2025 has a real json DATA TYPE (binary storage, validated, indexable). Older versions
--     do not know the type, so the demo runs as dynamic SQL inside TRY/CATCH and simply reports.
BEGIN TRY
    EXEC (N'DECLARE @doc JSON = N''{"a": 1, "b": [1, 2, 3]}'';
            SELECT @doc AS NativeJson, JSON_VALUE(@doc, ''$.b[2]'') AS ThirdOfB;');   -- 3
    PRINT 'native json type: supported on this server';
END TRY
BEGIN CATCH
    PRINT 'native json type not available here (needs SQL Server 2025 / Azure SQL): ' + ERROR_MESSAGE();
END CATCH
GO


/* ============================================================
   6. FOR XML - rows -> XML
   ============================================================ */
-- 6a. RAW: one <row> element per row, columns as attributes. ROOT adds a top element.
SELECT DepartmentID, DepartmentName FROM dbo.Departments WHERE DepartmentID <= 2 ORDER BY DepartmentID
FOR XML RAW, ROOT('departments');               -- <departments><row DepartmentID="1" DepartmentName="IT"/><row .../></departments>
GO
-- 6b. AUTO: element names = table aliases, nesting follows the joins; ELEMENTS turns attributes into child elements
SELECT d.DepartmentName, e.EmployeeName
FROM dbo.Departments d JOIN dbo.Employees e ON e.DepartmentID = d.DepartmentID
WHERE d.DepartmentID = 3
FOR XML AUTO, ELEMENTS;                         -- <d><DepartmentName>HR</DepartmentName><e><EmployeeName>Ravi</EmployeeName></e></d>
GO
-- 6c. PATH: full control - '@x' = attribute, 'a/b' = nested element, ROOT
SELECT DepartmentID AS '@id', DepartmentName AS 'name', Location AS 'address/city'
FROM dbo.Departments WHERE DepartmentID <= 2 ORDER BY DepartmentID
FOR XML PATH('department'), ROOT('departments');   -- <departments><department id="1"><name>IT</name><address><city>Delhi</city></address></department>...</departments>
GO
-- 6d. EXPLICIT (mention only): the oldest mode, you build a Tag/Parent "universal table" by hand. Use PATH instead.

-- 6e. THE INTERVIEW CLASSIC: string aggregation before STRING_AGG (2017) = FOR XML PATH('') + STUFF
--     FOR XML PATH('') with no element name glues the values into one string; STUFF removes the leading ', '.
--     TYPE + .value() avoids XML-escaping of characters like & < >.
SELECT d.DepartmentName,
       STUFF((SELECT ', ' + e.EmployeeName
              FROM dbo.Employees e
              WHERE e.DepartmentID = d.DepartmentID
              ORDER BY e.EmployeeName
              FOR XML PATH(''), TYPE).value('.', 'VARCHAR(MAX)'), 1, 2, '') AS Members
FROM dbo.Departments d
ORDER BY d.DepartmentName;                      -- Finance: Deepak, Sneha ; IT: Amit, Pooja, Rahul ; Legal: NULL ; ...
GO


/* ============================================================
   7. THE XML TYPE and its methods: .value() .query() .nodes() .exist()  (+ OPENXML)
   ============================================================ */
DECLARE @x XML = N'
<employees>
  <employee id="101"><name>Rahul</name><dept>IT</dept></employee>
  <employee id="103"><name>Priya</name><dept>Sales</dept></employee>
</employees>';

-- .value(XPath, type): ONE scalar; [1] is mandatory because XPath could match many nodes
SELECT @x.value('(/employees/employee/name)[1]', 'VARCHAR(50)') AS FirstName,               -- Rahul
       @x.value('(/employees/employee[@id=103]/dept)[1]', 'VARCHAR(50)') AS DeptOf103,        -- Sales
       @x.value('count(/employees/employee)', 'INT') AS EmployeeCount;                        -- 2
-- .exist(XPath): 1 / 0
SELECT @x.exist('/employees/employee[@id=103]') AS Has103, @x.exist('/employees/employee[@id=999]') AS Has999;   -- 1, 0
-- .query(XQuery): an XML fragment
SELECT @x.query('/employees/employee[dept="IT"]') AS ItFragment;                             -- <employee id="101">...</employee>
-- .nodes(XPath) + CROSS APPLY: SHRED the XML into rows (one row per matching node)
SELECT n.value('@id', 'INT') AS EmployeeID,
       n.value('(name)[1]', 'VARCHAR(50)') AS EmployeeName,
       n.value('(dept)[1]', 'VARCHAR(50)') AS Dept
FROM @x.nodes('/employees/employee') AS t(n);                                                 -- 2 rows

-- OPENXML (legacy, needs a handle; still seen in old code): same shredding
DECLARE @h INT;
EXEC sp_xml_preparedocument @h OUTPUT, @x;
SELECT * FROM OPENXML(@h, '/employees/employee', 2) WITH (id INT '@id', name VARCHAR(50) 'name', dept VARCHAR(50) 'dept');   -- 2 rows
EXEC sp_xml_removedocument @h;                                                                -- always release the handle
GO
-- 7b. XML columns in tables: CHECK is built in (invalid XML is rejected on insert), XML indexes exist (PRIMARY XML INDEX).
DROP TABLE IF EXISTS dbo.L20_XmlDocs;
CREATE TABLE dbo.L20_XmlDocs (DocID INT PRIMARY KEY, Doc XML NOT NULL);
INSERT INTO dbo.L20_XmlDocs VALUES (1, N'<order id="1001"><line product="1" qty="1"/></order>');
BEGIN TRY
    INSERT INTO dbo.L20_XmlDocs VALUES (2, N'<order id="1002"><line product="4"></order>');   -- not well-formed
END TRY
BEGIN CATCH
    PRINT 'EXPECTED ERROR: ' + ERROR_MESSAGE();
END CATCH
SELECT DocID, Doc.value('(/order/@id)[1]', 'INT') AS OrderID, Doc.value('(/order/line/@qty)[1]', 'INT') AS FirstQty FROM dbo.L20_XmlDocs;   -- 1001, 1
DROP TABLE dbo.L20_XmlDocs;
GO

/* XML vs JSON - WHEN TO USE WHICH
   JSON : modern APIs / web / mobile, lighter text, functions since 2016, native type in 2025. Default choice today.
   XML  : has a real data type + XML indexes + schema validation (XSD) + XQuery since 2005; still the format of SOAP,
          config files, invoices (e-invoicing), SSRS/SSIS internals, execution plans, EVENTDATA(), deadlock graphs.
   Both : store documents whose shape changes per row; extract hot keys into computed columns and index those;
          never use them to avoid designing proper tables for data you query and join all day.                        */


/* ============================================================
   8. CLEANUP
   ============================================================ */
DROP TABLE IF EXISTS dbo.L20_Events;
DROP TABLE IF EXISTS dbo.L20_IncomingLines;
DROP TABLE IF EXISTS dbo.L20_XmlDocs;
GO
/* DONE. Next: 04_Practice_Security.sql */
