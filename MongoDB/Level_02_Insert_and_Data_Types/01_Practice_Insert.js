/* ============================================================
   LEVEL 02 - INSERT & DATA TYPES  |  01_Practice_Insert.js
   ------------------------------------------------------------
   Topics : insertOne, insertMany (ordered / unordered), result
            objects, custom _id, duplicate keys, nested documents,
            arrays, flexible schema, write concern, 16 MB limit

   HOW TO PRACTICE
     * Run block by block, predict the output first.
     * Works in companyDB but only in collections prefixed l02_
       (dropped in the CLEANUP block). Base collections are untouched.
   ============================================================ */

use("companyDB");
db.l02_employees.drop();   // clean start (false if it did not exist - fine)


/* ============================================================
   1. insertOne - the result object
   ============================================================ */

const r1 = db.l02_employees.insertOne({ name: "Rahul", age: 28, department: "IT", salary: 75000 });
r1;                                             // { acknowledged: true, insertedId: ObjectId('...') }
r1.insertedId;                                  // the generated ObjectId
r1.acknowledged;                                // true (the server confirmed the write - write concern w:1)

db.l02_employees.findOne({ name: "Rahul" });    // the stored document, _id first


/* ============================================================
   2. insertMany - several documents in one round trip
   ============================================================ */

const r2 = db.l02_employees.insertMany([
    { name: "Amit",  age: 30, department: "Sales",   salary: 65000 },
    { name: "Priya", age: 27, department: "HR",      salary: 60000 },
    { name: "Neha",  age: 32, department: "Finance", salary: 85000 }
]);
r2;                                             // { acknowledged: true, insertedIds: { '0': ObjectId, '1': ObjectId, '2': ObjectId } }
Object.keys(r2.insertedIds).length;             // 3
db.l02_employees.countDocuments();              // 4


/* ============================================================
   3. CUSTOM _id  and  DUPLICATE KEY
   ============================================================ */

// Any unique value works as _id: numbers, strings, even an embedded document
db.l02_employees.insertOne({ _id: 201, name: "Ravi",   department: "HR" });
db.l02_employees.insertOne({ _id: "EMP-202", name: "Sneha", department: "Finance" });
db.l02_employees.insertOne({ _id: { region: "N", seq: 1 }, name: "Karan" });
db.l02_employees.find({}, { name: 1 });         // look at the different _id shapes

// _id must be unique -> E11000
try {
    db.l02_employees.insertOne({ _id: 201, name: "Another Ravi" });
} catch (e) {
    print("EXPECTED ERROR:", e.message);
}

// _id cannot be an array
try {
    db.l02_employees.insertOne({ _id: [1, 2], name: "Bad" });
} catch (e) {
    print("EXPECTED ERROR:", e.message);        // can't use an array for _id
}


/* ============================================================
   4. insertMany: ORDERED (default) vs UNORDERED
   ============================================================ */

// ordered: true (default) -> stops at the FIRST error; documents before it ARE inserted
try {
    db.l02_employees.insertMany([
        { _id: 301, name: "ok-1" },
        { _id: 301, name: "DUPLICATE" },         // fails
        { _id: 302, name: "never-tried" }
    ]);
} catch (e) {
    print("EXPECTED ERROR:", e.message);
    print("inserted before the error:", e.result.insertedCount);   // 1
}
db.l02_employees.find({ _id: { $in: [301, 302] } });               // only 301

// ordered: false -> tries EVERY document, reports all errors at the end
try {
    db.l02_employees.insertMany([
        { _id: 401, name: "ok-1" },
        { _id: 401, name: "DUPLICATE" },         // fails
        { _id: 402, name: "still-inserted" }     // inserted anyway
    ], { ordered: false });
} catch (e) {
    print("EXPECTED ERROR:", e.message);
    print("inserted:", e.result.insertedCount, " errors:", e.writeErrors.length);   // 2, 1
}
db.l02_employees.find({ _id: { $in: [401, 402] } });               // 401 AND 402

// Lesson: insertMany is NOT atomic. All-or-nothing needs a transaction (Level 14).
// ordered:false is also faster for big loads (the server can parallelise).


/* ============================================================
   5. NESTED DOCUMENTS AND ARRAYS - the document model
   ============================================================ */

db.l02_employees.insertOne({
    _id: 501,
    name: "Deepak",
    email: "deepak@example.com",
    salary: NumberDecimal("72000.00"),           // exact money type (see 02_Practice_Data_Types.js)
    hireDate: ISODate("2021-03-03"),
    active: true,
    managerId: null,                             // explicitly "no manager"
    skills: ["Accounting", "SQL", "Excel"],      // array of strings
    address: {                                   // embedded document
        street: "12 MG Road", city: "Bangalore", state: "Karnataka", pincode: 560034
    },
    phones: [                                    // array of embedded documents
        { type: "mobile", number: "98450-00000" },
        { type: "office", number: "080-2222-0000" }
    ],
    projects: []                                 // empty array (exists, has no elements)
});
db.l02_employees.findOne({ _id: 501 });

// Reading nested values in JS
const d = db.l02_employees.findOne({ _id: 501 });
d.address.city;                                 // Bangalore
d.skills[0];                                    // Accounting
d.phones[1].number;                             // 080-2222-0000
d.skills.length;                                // 3


/* ============================================================
   6. FLEXIBLE SCHEMA - same collection, different shapes
   ============================================================ */

db.l02_employees.insertMany([
    { _id: 601, name: "Only a name" },
    { _id: 602, name: "Meera", salary: "58000" },        // salary stored as a STRING (a bug waiting to happen)
    { _id: 603, name: "Vikram", Salary: 62000 }          // typo: capital S -> a different field!
]);
db.l02_employees.find({ salary: { $gt: 50000 } }, { name: 1, salary: 1 });   // 602 and 603 are NOT found - why?
// 602: "58000" is a string - $gt: 50000 only compares numbers (type bracketing).
// 603: the field is "Salary", not "salary".
// Flexible schema = freedom + responsibility. Level 13 shows how to add validation.


/* ============================================================
   7. THE 16 MB LIMIT
   ============================================================ */

bsonsize(db.l02_employees.findOne({ _id: 501 }));          // a few hundred bytes (mongosh helper)
// A document above 16 MB (16777216 bytes) is rejected with "object to insert too large".
// Design for it: do not embed unbounded arrays (e.g. every click of a user) - Level 13.


/* ============================================================
   8. WRITE CONCERN (preview of Level 17)
   ============================================================ */

// w: "majority" -> acknowledged only after a majority of replica-set members wrote it
db.l02_employees.insertOne({ _id: 701, name: "Safe write" }, { writeConcern: { w: "majority", j: true } });
// On this 1-node set "majority" = 1, so it is immediate. On a 3-node set it waits for 2 nodes.


/* ============================================================
   CLEANUP
   ============================================================ */
db.l02_employees.drop();

/* ------------------------------------------------------------
   DONE. Next: 02_Practice_Data_Types.js
   ------------------------------------------------------------ */
