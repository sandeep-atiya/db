/* ============================================================
   LEVEL 01 - MONGODB BASICS  |  Exercises.js
   ------------------------------------------------------------
   Try each question in the "YOUR ANSWER" area FIRST.
   Then scroll down to SOLUTIONS and compare.
   Uses companyDB (Q1-Q10) and a throwaway database (Q11).
   ============================================================ */

use("companyDB");

/* ------------------------------------------------------------
   QUESTIONS
   ------------------------------------------------------------
   Q1.  List all databases on the server.
   Q2.  Show the name of the current database and the server version.
   Q3.  List all collections in companyDB (as an array).
   Q4.  Show ONE employee document (any) to see the field names.
   Q5.  Show all employees.
   Q6.  Show only name, salary and hireDate of every employee (no _id).
   Q7.  Show employees whose salary is greater than 70000.
   Q8.  Show employees of the IT department (departmentId = 1).
   Q9.  Sort employees by salary, highest first.
   Q10. Count the employees.

   Q11. (DDL drill) Create a database myFirstDB, create a collection
        inventory.items ... wait - MongoDB has no schemas! So:
        create a collection "items" explicitly, insert one item
        { _id: 1, itemName: "Bolt", qty: 100 }, insert a second one
        WITHOUT _id and look at the generated ObjectId + its timestamp,
        list the collections, rename "items" to "stock", count its
        documents, drop the collection and finally drop the database.
   ------------------------------------------------------------ */

// YOUR ANSWERS HERE (write below, run, compare)










/* ============================================================
   SOLUTIONS
   ============================================================ */

// Q1
show("dbs");
// alternative: db.adminCommand({ listDatabases: 1 }).databases.map(d => d.name)

// Q2
db.getName();                                   // companyDB
db.version();

// Q3
db.getCollectionNames();                        // [ 'customers', 'departments', 'employees', 'orders', 'products' ]
// alternative: show("collections")

// Q4
db.employees.findOne();

// Q5
db.employees.find();

// Q6
db.employees.find({}, { _id: 0, name: 1, salary: 1, hireDate: 1 });

// Q7
db.employees.find({ salary: { $gt: 70000 } }, { name: 1, salary: 1 });   // Rahul, Priya, Sneha, Deepak (4)

// Q8
db.employees.find({ departmentId: 1 }, { name: 1, departmentId: 1 });    // Rahul, Amit, Pooja
// (After Level 09 you will do this with a $lookup on departments.name = "IT")

// Q9
db.employees.find({}, { name: 1, salary: 1 }).sort({ salary: -1 });

// Q10
db.employees.countDocuments();                  // 12

// Q11
use("myFirstDB");
db.createCollection("items");
db.items.insertOne({ _id: 1, itemName: "Bolt", qty: 100 });
const r = db.items.insertOne({ itemName: "Nut", qty: 250 });
r.insertedId;                                   // ObjectId("...")
r.insertedId.getTimestamp();                    // ISODate("...")  (now)
db.getCollectionNames();                        // [ 'items' ]
db.items.renameCollection("stock");
db.stock.countDocuments();                      // 2
db.stock.drop();                                // true
db.dropDatabase();                              // { ok: 1, dropped: 'myFirstDB' }
