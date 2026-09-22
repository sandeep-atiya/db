/* ============================================================
   LEVEL 07 - DELETE & BULK WRITE  |  Exercises.js
   ------------------------------------------------------------
   Try each question in the "YOUR ANSWER" area FIRST.
   Then scroll down to SOLUTIONS and compare.
   Work on the copies created below (dropped at the end).
   ============================================================ */

use("companyDB");
db.employees.aggregate([{ $out: "l07_ex_employees" }]);
db.orders.aggregate([{ $out: "l07_ex_orders" }]);
db.products.aggregate([{ $out: "l07_ex_products" }]);

/* ------------------------------------------------------------
   QUESTIONS
   ------------------------------------------------------------
   Q1.  Delete employee 110 (Anjali). Confirm with the count.
   Q2.  Delete all Cancelled orders and all orders below 3000. How many in total?
   Q3.  Delete the MOST RECENT Pending order and print its _id (one call).
   Q4.  Delete employee 103 (Priya) together with the orders she sold
        (employeeId 103). How many orders went?
   Q5.  Soft-delete product 9 (Headphones): set discontinued: true and
        show the products that are still available for sale.
   Q6.  Empty l07_ex_products but keep the collection and its indexes.
        Prove the _id index is still there.
   Q7.  With ONE bulkWrite on l07_ex_employees:
          - insert employee 113 { name: "Isha", departmentId: 3, salary: 52000 }
          - give department 2 a 5 % raise
          - set active: false for employee 112
          - delete employee 104
        Read insertedCount / matchedCount / modifiedCount / deletedCount.
   Q8.  Run an UNORDERED bulkWrite that inserts _id 200, 200 (dup) and 201.
        Show that 201 exists and print how many write errors occurred.
   Q9.  Upsert these three departments into l07_ex_departments in one
        bulkWrite: {_id:7,name:"R&D"}, {_id:8,name:"Support"}, {_id:1,name:"IT"}.
        Which counts do you expect (upserted vs matched)?
   Q10. (Think) A colleague runs db.orders.deleteMany({ status: "pending" })
        in production and nothing is deleted. Why? Then they run
        deleteMany({}) "to retry". What happened, and what would you have
        done differently?
   ------------------------------------------------------------ */

// YOUR ANSWERS HERE (write below, run, compare)










/* ============================================================
   SOLUTIONS
   ============================================================ */

// Q1
db.l07_ex_employees.deleteOne({ _id: 110 });                           // deletedCount 1
db.l07_ex_employees.countDocuments();                                  // 11

// Q2
db.l07_ex_orders.deleteMany({ $or: [ { status: "Cancelled" }, { totalAmount: { $lt: 3000 } } ] });   // 1006, 1010, 1019 -> 3

// Q3
db.l07_ex_orders.findOneAndDelete({ status: "Pending" }, { sort: { orderDate: -1 }, projection: { _id: 1 } });   // 1017

// Q4
db.l07_ex_orders.deleteMany({ employeeId: 103 });                      // 1001, 1003, 1005, 1009, 1012, 1015, 1018 -> 7
db.l07_ex_employees.deleteOne({ _id: 103 });

// Q5
db.l07_ex_products.updateOne({ _id: 9 }, { $set: { discontinued: true } });
db.l07_ex_products.find({ discontinued: { $ne: true } }, { _id: 0, name: 1 }).count();   // 10

// Q6
db.l07_ex_products.deleteMany({});                                     // deletedCount 11
db.l07_ex_products.getIndexes();                                       // [ { key: { _id: 1 }, name: '_id_' } ]
db.l07_ex_products.countDocuments();                                   // 0

// Q7
db.l07_ex_employees.bulkWrite([
    { insertOne:  { document: { _id: 113, name: "Isha", departmentId: 3, salary: 52000 } } },
    { updateMany: { filter: { departmentId: 2 }, update: { $mul: { salary: 1.05 } } } },
    { updateOne:  { filter: { _id: 112 }, update: { $set: { active: false } } } },
    { deleteOne:  { filter: { _id: 104 } } }
]);
// insertedCount 1, matchedCount 3 (Neha, Vikram + Meera), modifiedCount 2 (Meera was already inactive -> not modified), deletedCount 1

// Q8
try {
    db.l07_ex_employees.bulkWrite([
        { insertOne: { document: { _id: 200, name: "a" } } },
        { insertOne: { document: { _id: 200, name: "dup" } } },
        { insertOne: { document: { _id: 201, name: "b" } } }
    ], { ordered: false });
} catch (e) {
    print("EXPECTED ERROR:", e.message);
    print("write errors:", e.writeErrors.length);                      // 1
}
db.l07_ex_employees.findOne({ _id: 201 });                             // exists

// Q9
db.l07_ex_departments.drop();
db.l07_ex_departments.insertOne({ _id: 1, name: "IT" });
db.l07_ex_departments.bulkWrite([
    { updateOne: { filter: { _id: 7 }, update: { $set: { name: "R&D" } },     upsert: true } },
    { updateOne: { filter: { _id: 8 }, update: { $set: { name: "Support" } }, upsert: true } },
    { updateOne: { filter: { _id: 1 }, update: { $set: { name: "IT" } },      upsert: true } }
]);
// upsertedCount 2, matchedCount 1, modifiedCount 0 (IT already had that name)

// Q10
// 1) "pending" != "Pending": MongoDB string matching is case-sensitive -> deletedCount 0, no error.
// 2) deleteMany({}) deleted EVERY order. There is no rollback outside a transaction; only a backup helps now.
//    Better: check the filter with find()/countDocuments() first, use the exact value (or /^pending$/i),
//    and never run an empty filter in production without a backup and a second pair of eyes.

db.l07_ex_employees.drop(); db.l07_ex_orders.drop(); db.l07_ex_products.drop(); db.l07_ex_departments.drop();
