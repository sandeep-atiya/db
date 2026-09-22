/* ============================================================
   LEVEL 02 - INSERT & DATA TYPES  |  Exercises.js
   ------------------------------------------------------------
   Try each question in the "YOUR ANSWER" area FIRST.
   Then scroll down to SOLUTIONS and compare.
   Work in the collection l02_ex (dropped in the solutions).
   ============================================================ */

use("companyDB");
db.l02_ex.drop();

/* ------------------------------------------------------------
   QUESTIONS
   ------------------------------------------------------------
   Q1.  Insert one product { name: "Tablet", price: 30000, stock: 12 } into
        l02_ex and print the generated _id and its creation time.
   Q2.  Insert three products in one call with custom numeric _id 1, 2, 3
        (Tablet, Printer, Scanner) and read insertedIds from the result.
   Q3.  Try to insert _id 2 again inside a try/catch and print the error.
   Q4.  Insert [ {_id: 10}, {_id: 10}, {_id: 11} ] UNORDERED and prove that
        _id 11 was inserted.
   Q5.  Insert a product with price as NumberDecimal("199.99"), stock as
        NumberInt(5), a launch date of 2025-03-01 (UTC), tags ["new","sale"]
        and an embedded dimensions document { w: 10, h: 20, unit: "cm" }.
   Q6.  Query l02_ex for products whose price is stored as a decimal.
   Q7.  Query companyDB.employees for documents where managerId is
        explicitly null (not missing) and count them.
   Q8.  Query companyDB.products for documents that have NO ratings field.
   Q9.  Find employees living in Mumbai using dot notation, names only.
   Q10. Insert a product whose stock is the STRING "7", then run
        find({ stock: { $lt: 10 } }) and explain why it is not returned.
   Q11. (Think) What BSON type is stored when you write price: 1000 in
        mongosh? And price: 1000.50? And price: 3000000000? How would you
        store 1000 as a double on purpose?
   ------------------------------------------------------------ */

// YOUR ANSWERS HERE (write below, run, compare)










/* ============================================================
   SOLUTIONS
   ============================================================ */

// Q1
const q1 = db.l02_ex.insertOne({ name: "Tablet", price: 30000, stock: 12 });
q1.insertedId;
q1.insertedId.getTimestamp();

// Q2
const q2 = db.l02_ex.insertMany([
    { _id: 1, name: "Tablet",  price: 30000, stock: 12 },
    { _id: 2, name: "Printer", price: 12000, stock: 4 },
    { _id: 3, name: "Scanner", price: 9000,  stock: 6 }
]);
q2.insertedIds;                                 // { '0': 1, '1': 2, '2': 3 }

// Q3
try {
    db.l02_ex.insertOne({ _id: 2, name: "Printer again" });
} catch (e) {
    print("EXPECTED ERROR:", e.message);        // E11000 duplicate key error ... { _id: 2 }
}

// Q4
try {
    db.l02_ex.insertMany([{ _id: 10 }, { _id: 10 }, { _id: 11 }], { ordered: false });
} catch (e) {
    print("EXPECTED ERROR:", e.message);
}
db.l02_ex.find({ _id: { $in: [10, 11] } });     // both 10 and 11 exist

// Q5
db.l02_ex.insertOne({
    _id: 20, name: "Deluxe Tablet",
    price: NumberDecimal("199.99"), stock: NumberInt(5),
    launchDate: ISODate("2025-03-01"),
    tags: ["new", "sale"],
    dimensions: { w: 10, h: 20, unit: "cm" }
});

// Q6
db.l02_ex.find({ price: { $type: "decimal" } }, { name: 1, price: 1 });    // Deluxe Tablet

// Q7
db.employees.find({ managerId: { $type: "null" } }, { name: 1 });           // Rahul, Priya, Ravi, Sneha, Karan, Anjali
db.employees.countDocuments({ managerId: { $type: "null" } });              // 6

// Q8
db.products.find({ ratings: { $exists: false } }, { name: 1 });             // Notebook

// Q9
db.employees.find({ "address.city": "Mumbai" }, { _id: 0, name: 1 });      // Priya, Neha, Meera

// Q10
db.l02_ex.insertOne({ _id: 30, name: "Odd stock", stock: "7" });
db.l02_ex.find({ stock: { $lt: 10 } }, { name: 1, stock: 1 });             // Printer (4), Scanner (6), Deluxe (5) - NOT "Odd stock"
// "7" is a string; $lt: 10 only compares numbers (type bracketing).

// Q11
// 1000 -> int (whole number that fits in 32 bits). 1000.50 -> double. 3000000000 -> double (too big for int32).
// To force a double: Double(1000). To force 64-bit: NumberLong("3000000000"). Money: NumberDecimal("1000.50").
db.l02_ex.insertOne({ _id: 40, p1: 1000, p2: 1000.50, p3: 3000000000, p4: Double(1000), p5: NumberLong("3000000000") });
db.l02_ex.aggregate([{ $match: { _id: 40 } }, { $project: { _id: 0,
    p1: { $type: "$p1" }, p2: { $type: "$p2" }, p3: { $type: "$p3" }, p4: { $type: "$p4" }, p5: { $type: "$p5" } } }]);
// -> { p1: 'int', p2: 'double', p3: 'double', p4: 'double', p5: 'long' }

db.l02_ex.drop();
