/* ============================================================
   LEVEL 05 - UPDATE OPERATIONS  |  01_Practice_Update_Operators.js
   ------------------------------------------------------------
   Topics : updateOne / updateMany / replaceOne, result object,
            $set $unset $inc $mul $rename $min $max $currentDate,
            nested fields, common errors

   HOW TO PRACTICE: block by block, predict first.
   Works on COPIES (l05_employees, l05_products) made with $out,
   so the base collections stay clean. Dropped in CLEANUP.
   ============================================================ */

use("companyDB");

// Make copies of the base collections (the aggregation $out stage = SELECT INTO)
db.employees.aggregate([{ $out: "l05_employees" }]);
db.products.aggregate([{ $out: "l05_products" }]);
db.l05_employees.countDocuments();                                  // 12


/* ============================================================
   1. updateOne + $set  -  the result object
   ============================================================ */

const r1 = db.l05_employees.updateOne({ _id: 101 }, { $set: { salary: 88000 } });
r1;                                                                 // { acknowledged: true, insertedId: null, matchedCount: 1, modifiedCount: 1, upsertedCount: 0 }
                                                                    // (insertedId is the upserted _id, if any - the Node driver calls it upsertedId)
db.l05_employees.findOne({ _id: 101 }, { _id: 0, name: 1, salary: 1 });   // 88000

// Same value again -> matched 1, MODIFIED 0 (nothing changed)
db.l05_employees.updateOne({ _id: 101 }, { $set: { salary: 88000 } });

// No match -> matched 0, modified 0 (no error!)
db.l05_employees.updateOne({ _id: 999 }, { $set: { salary: 1 } });

// Several fields at once, a NEW field, and a NESTED field via dot notation
db.l05_employees.updateOne({ _id: 101 }, { $set: { active: true, title: "Tech Lead", "address.city": "Gurgaon" } });
db.l05_employees.findOne({ _id: 101 }, { _id: 0, title: 1, address: 1 });

// $set with a whole sub-document REPLACES it (address.state / pincode gone!)
db.l05_employees.updateOne({ _id: 101 }, { $set: { address: { city: "Delhi" } } });
db.l05_employees.findOne({ _id: 101 }, { _id: 0, address: 1 });          // { city: 'Delhi' } only
db.l05_employees.updateOne({ _id: 101 }, { $set: { "address.state": "Delhi", "address.pincode": 110001 } });   // put them back

// Dot notation creates intermediate objects
db.l05_employees.updateOne({ _id: 101 }, { $set: { "contact.emergency.phone": "99999" } });
db.l05_employees.findOne({ _id: 101 }, { _id: 0, contact: 1 });          // { contact: { emergency: { phone: '99999' } } }


/* ============================================================
   2. updateMany  (SQL: UPDATE ... WHERE ...)
   ============================================================ */

// Everyone in IT gets a "team" field
db.l05_employees.updateMany({ departmentId: 1 }, { $set: { team: "Platform" } });     // matched 3, modified 3
db.l05_employees.find({ team: "Platform" }, { _id: 0, name: 1 });

// updateMany with {} = EVERY document (double-check before running such a thing in production)
db.l05_employees.updateMany({}, { $set: { reviewed: false } });                        // matched 12


/* ============================================================
   3. $inc and $mul  (relative changes, atomic)
   ============================================================ */

db.l05_employees.updateOne({ _id: 102 }, { $inc: { salary: 5000 } });                 // 65000 -> 70000
db.l05_employees.updateOne({ _id: 102 }, { $inc: { salary: -2000 } });                // 70000 -> 68000
db.l05_employees.findOne({ _id: 102 }, { _id: 0, salary: 1 });

// $inc on a MISSING field creates it (great for counters)
db.l05_employees.updateOne({ _id: 102 }, { $inc: { logins: 1 } });
db.l05_employees.updateOne({ _id: 102 }, { $inc: { logins: 1 } });
db.l05_employees.findOne({ _id: 102 }, { _id: 0, logins: 1 });                        // 2

// 10 % raise for Sales
db.l05_employees.updateMany({ departmentId: 2 }, { $mul: { salary: 1.1 } });
db.l05_employees.find({ departmentId: 2 }, { _id: 0, name: 1, salary: 1 });          // 82500, 60500.00000000001 (!), 68200
// $mul produced doubles and 55000 * 1.1 shows floating-point noise. For money use NumberDecimal, or $round in a pipeline update.

// $inc on a string -> error
try {
    db.l05_employees.updateOne({ _id: 102 }, { $inc: { name: 1 } });
} catch (e) {
    print("EXPECTED ERROR:", e.message);                                                // Cannot apply $inc to a value of non-numeric type
}


/* ============================================================
   4. $unset and $rename
   ============================================================ */

db.l05_employees.updateMany({}, { $unset: { reviewed: "" } });                          // value is ignored - "" by convention
db.l05_employees.findOne({ _id: 101 }, { _id: 0, reviewed: 1, name: 1 });              // no "reviewed"

db.l05_employees.updateMany({}, { $rename: { title: "jobTitle", "address.pincode": "address.zip" } });
db.l05_employees.findOne({ _id: 101 }, { _id: 0, jobTitle: 1, address: 1 });          // jobTitle, address.zip


/* ============================================================
   5. $min / $max  (set only if lower / higher)
   ============================================================ */

db.l05_products.updateOne({ _id: 1 }, { $min: { price: 80000 } });                     // 75000 stays (80000 is not lower) -> modified 0
db.l05_products.updateOne({ _id: 1 }, { $min: { price: 70000 } });                     // -> 70000
db.l05_products.updateOne({ _id: 1 }, { $max: { stock: 5 } });                         // 10 stays
db.l05_products.updateOne({ _id: 1 }, { $max: { stock: 50 } });                        // -> 50
db.l05_products.findOne({ _id: 1 }, { _id: 0, price: 1, stock: 1 });

// Typical use: "last seen" without reading first
db.l05_employees.updateOne({ _id: 101 }, { $max: { lastLogin: ISODate("2025-09-01") } });
db.l05_employees.updateOne({ _id: 101 }, { $max: { lastLogin: ISODate("2025-08-01") } });   // older -> ignored
db.l05_employees.findOne({ _id: 101 }, { _id: 0, lastLogin: 1 });                           // 2025-09-01


/* ============================================================
   6. $currentDate
   ============================================================ */

db.l05_employees.updateOne({ _id: 101 }, { $currentDate: { updatedAt: true, syncTs: { $type: "timestamp" } } });
db.l05_employees.findOne({ _id: 101 }, { _id: 0, updatedAt: 1, syncTs: 1 });   // Date + Timestamp


/* ============================================================
   7. SEVERAL OPERATORS IN ONE UPDATE (still one atomic operation)
   ============================================================ */

db.l05_employees.updateOne(
    { _id: 104 },
    { $set: { jobTitle: "Senior Sales" }, $inc: { salary: 2500 }, $unset: { team: "" }, $currentDate: { updatedAt: true } }
);
db.l05_employees.findOne({ _id: 104 }, { _id: 0, name: 1, jobTitle: 1, salary: 1, updatedAt: 1 });

// The SAME path in two operators -> conflict error
try {
    db.l05_employees.updateOne({ _id: 104 }, { $set: { salary: 1 }, $inc: { salary: 1 } });
} catch (e) {
    print("EXPECTED ERROR:", e.message);                                                // Updating the path 'salary' would create a conflict at 'salary'
}


/* ============================================================
   8. replaceOne  (whole-document overwrite, _id kept)
   ============================================================ */

db.l05_employees.replaceOne({ _id: 112 }, { name: "Meera", salary: 58000, note: "replaced" });
db.l05_employees.findOne({ _id: 112 });                                                  // ONLY _id, name, salary, note - everything else is gone

// A replacement document cannot contain operators
try {
    db.l05_employees.replaceOne({ _id: 112 }, { $set: { name: "x" } });
} catch (e) {
    print("EXPECTED ERROR:", e.message);                                                 // Replacement document must not contain atomic operators
}


/* ============================================================
   9. COMMON ERRORS
   ============================================================ */

// 9a. update without an operator
try {
    db.l05_employees.updateOne({ _id: 101 }, { salary: 1 });
} catch (e) {
    print("EXPECTED ERROR:", e.message);                                                 // Update document requires atomic operators
}

// 9b. changing _id
try {
    db.l05_employees.updateOne({ _id: 101 }, { $set: { _id: 1 } });
} catch (e) {
    print("EXPECTED ERROR:", e.message);
}

// 9c. $set on an array index beyond the end pads with null
db.l05_employees.updateOne({ _id: 101 }, { $set: { "skills.5": "Go" } });
db.l05_employees.findOne({ _id: 101 }, { _id: 0, skills: 1 });                           // [ 'Java', 'MongoDB', 'NodeJS', null, null, 'Go' ]


/* ============================================================
   CLEANUP
   ============================================================ */
db.l05_employees.drop();
db.l05_products.drop();

/* ------------------------------------------------------------
   DONE. Next: 02_Practice_Upsert_FindAndModify_Pipeline.js
   ------------------------------------------------------------ */
