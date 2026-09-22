/* ============================================================
   00_SETUP  |  01_Create_Collections.js
   ------------------------------------------------------------
   Creates the practice database "companyDB" and its 5 collections.
   Safe to re-run: the whole database is dropped and created again
   (all practice data is rebuilt by 02_Insert_Sample_Data.js).

   HOW TO RUN (terminal):   mongosh --file 01_Create_Collections.js
   HOW TO RUN (mongosh):    load("E:/Practice/MongoDB/00_Setup/01_Create_Collections.js")
   HOW TO RUN (VS Code):    open as MongoDB Playground -> Run All

   DATA MODEL (one Company / Sales dataset - the SAME data as the
   SQL Server course, reshaped the MongoDB way)

     departments 1 ---< employees  (managerId = self reference)
                            |
                            | (orders.employeeId = salesperson)
                            v
     customers   1 ---< orders  { items: [ {productId, qty, unitPrice} ] }  >--- products
                                       ^ order lines are EMBEDDED, not a 6th collection
   ============================================================ */

// 1) Switch to the practice database. In MongoDB a database is created
//    lazily: it only appears in "show dbs" after the first document is stored.
use("companyDB");

// 2) Clean start: drop the whole database (all collections, indexes, data).
db.dropDatabase();
print("companyDB dropped (if it existed).");

// 3) Create the collections EXPLICITLY.
//    MongoDB would create them implicitly on the first insert, but explicit
//    creation lets you pass options (validator, capped, collation ...).
//    Schema validation is taught in Level 13 - the base collections stay
//    schema-free on purpose so every level can experiment freely.
db.createCollection("departments");
db.createCollection("employees");
db.createCollection("customers");
db.createCollection("products");
db.createCollection("orders");

// 4) The MongoDB equivalent of a UNIQUE constraint is a unique index.
//    employees.email : unique. One employee (Anjali) has NO email field at all;
//                      a unique index treats a missing field as null and
//                      allows that value only once -> fine here.
db.employees.createIndex({ email: 1 }, { unique: true, name: "uq_employees_email" });

//    customers.email : one customer has email: null and another has no email
//                      field -> BOTH count as null -> a plain unique index would
//                      FAIL with a duplicate key error. A PARTIAL unique index
//                      only indexes documents whose email is a string.
db.customers.createIndex(
    { email: 1 },
    { unique: true, name: "uq_customers_email",
      partialFilterExpression: { email: { $type: "string" } } }
);

//    departments.name : unique (like UQ_Departments_Name in SQL Server).
db.departments.createIndex({ name: 1 }, { unique: true, name: "uq_departments_name" });

// 5) Verify
print("Collections:");
printjson(db.getCollectionNames().sort());
print("Server version:", db.version());
