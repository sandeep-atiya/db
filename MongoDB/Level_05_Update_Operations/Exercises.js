/* ============================================================
   LEVEL 05 - UPDATE OPERATIONS  |  Exercises.js
   ------------------------------------------------------------
   Try each question in the "YOUR ANSWER" area FIRST.
   Then scroll down to SOLUTIONS and compare.
   Work on the copies l05_ex_employees / l05_ex_products
   (created below, dropped at the end of the solutions).
   ============================================================ */

use("companyDB");
db.employees.aggregate([{ $out: "l05_ex_employees" }]);
db.products.aggregate([{ $out: "l05_ex_products" }]);

/* ------------------------------------------------------------
   QUESTIONS  (all on the l05_ex_* copies)
   ------------------------------------------------------------
   Q1.  Give Neha (104) a salary of 58000 and a new field level: "L2".
   Q2.  Increase every Finance (4) salary by 3000. How many documents changed?
   Q3.  Reduce the price of every Stationery product by 10 % ($mul).
   Q4.  Remove the field ratings from ALL products.
   Q5.  Rename tags to labels in all products.
   Q6.  Move Amit (102) to Pune, Maharashtra, pincode 411001 WITHOUT losing
        the other address fields (use dot notation).
   Q7.  Set stock of Headphones (9) to 15 only if the current value is lower ($max).
   Q8.  Record lastReviewed = now on every employee whose manager is 101.
   Q9.  Upsert a product { _id: 12, name: "Docking Station", category: "Electronics",
        price: 6500, stock: 8 } and add createdAt only on insert. Run it twice; the
        second time change the price to 6000 and confirm createdAt did not change.
   Q10. Using findOneAndUpdate, give the LOWEST-paid employee a 5000 raise and
        return the updated name + salary in one call.
   Q11. Pipeline update: add inventoryValue = price * stock to every product.
   Q12. Pipeline update: add priceBand = "premium" if price >= 10000 else "standard".
   Q13. Replace employee 110 with { name: "Anjali", status: "left" } - which
        fields remain?
   Q14. What is wrong with: db.l05_ex_employees.updateOne({ _id: 101 }, { salary: 1 }) ?
   ------------------------------------------------------------ */

// YOUR ANSWERS HERE (write below, run, compare)










/* ============================================================
   SOLUTIONS
   ============================================================ */

// Q1
db.l05_ex_employees.updateOne({ _id: 104 }, { $set: { salary: 58000, level: "L2" } });
db.l05_ex_employees.findOne({ _id: 104 }, { _id: 0, name: 1, salary: 1, level: 1 });

// Q2
db.l05_ex_employees.updateMany({ departmentId: 4 }, { $inc: { salary: 3000 } });   // modifiedCount 2 (Sneha, Deepak)

// Q3
db.l05_ex_products.updateMany({ category: "Stationery" }, { $mul: { price: 0.9 } });
db.l05_ex_products.find({ category: "Stationery" }, { _id: 0, name: 1, price: 1 });   // 45, 9

// Q4
db.l05_ex_products.updateMany({}, { $unset: { ratings: "" } });
db.l05_ex_products.countDocuments({ ratings: { $exists: true } });                    // 0

// Q5
db.l05_ex_products.updateMany({}, { $rename: { tags: "labels" } });
db.l05_ex_products.findOne({ _id: 1 }, { _id: 0, labels: 1, tags: 1 });

// Q6
db.l05_ex_employees.updateOne({ _id: 102 }, { $set: { "address.city": "Pune", "address.state": "Maharashtra", "address.pincode": 411001 } });
db.l05_ex_employees.findOne({ _id: 102 }, { _id: 0, address: 1 });

// Q7
db.l05_ex_products.updateOne({ _id: 9 }, { $max: { stock: 15 } });                   // 0 -> 15
db.l05_ex_products.findOne({ _id: 9 }, { _id: 0, stock: 1 });

// Q8
db.l05_ex_employees.updateMany({ managerId: 101 }, { $currentDate: { lastReviewed: true } });   // Amit, Pooja -> 2
db.l05_ex_employees.find({ managerId: 101 }, { _id: 0, name: 1, lastReviewed: 1 });

// Q9
db.l05_ex_products.updateOne({ _id: 12 },
    { $set: { name: "Docking Station", category: "Electronics", price: 6500, stock: 8 }, $setOnInsert: { createdAt: new Date() } },
    { upsert: true });                                                                 // upsertedCount 1
const created = db.l05_ex_products.findOne({ _id: 12 }).createdAt;
db.l05_ex_products.updateOne({ _id: 12 },
    { $set: { name: "Docking Station", category: "Electronics", price: 6000, stock: 8 }, $setOnInsert: { createdAt: new Date() } },
    { upsert: true });                                                                 // matchedCount 1
db.l05_ex_products.findOne({ _id: 12 }).createdAt.getTime() === created.getTime();     // true - unchanged

// Q10
db.l05_ex_employees.findOneAndUpdate({}, { $inc: { salary: 5000 } },
    { sort: { salary: 1 }, returnDocument: "after", projection: { _id: 0, name: 1, salary: 1 } });   // Anjali 53000

// Q11
db.l05_ex_products.updateMany({}, [ { $set: { inventoryValue: { $multiply: ["$price", "$stock"] } } } ]);
db.l05_ex_products.find({}, { _id: 0, name: 1, inventoryValue: 1 }).limit(3);

// Q12
db.l05_ex_products.updateMany({}, [ { $set: { priceBand: { $cond: [ { $gte: ["$price", 10000] }, "premium", "standard" ] } } } ]);
db.l05_ex_products.find({ priceBand: "premium" }, { _id: 0, name: 1, price: 1 });    // Laptop, Desk, Monitor, Bookshelf

// Q13
db.l05_ex_employees.replaceOne({ _id: 110 }, { name: "Anjali", status: "left" });
db.l05_ex_employees.findOne({ _id: 110 });                                             // only _id, name, status

// Q14
// The update document has no operator -> error "Update document requires atomic operators".
// Either { $set: { salary: 1 } } or replaceOne(...) was intended.
try { db.l05_ex_employees.updateOne({ _id: 101 }, { salary: 1 }); } catch (e) { print("EXPECTED ERROR:", e.message); }

db.l05_ex_employees.drop();
db.l05_ex_products.drop();
