/* ============================================================
   LEVEL 06 - ARRAYS & NESTED DOCS  |  02_Practice_Update_Arrays.js
   ------------------------------------------------------------
   Topics : $push ($each $position $slice $sort), $addToSet, $pop,
            $pull, $pullAll, index updates, positional $, all
            positional $[], filtered positional $[id] + arrayFilters,
            nested arrays, removing by index, nested documents

   HOW TO PRACTICE: block by block, predict first.
   Works on copies l06_employees / l06_orders. Dropped in CLEANUP.
   ============================================================ */

use("companyDB");
db.employees.aggregate([{ $out: "l06_employees" }]);
db.orders.aggregate([{ $out: "l06_orders" }]);
const show = (id) => db.l06_employees.findOne({ _id: id }, { _id: 0, name: 1, skills: 1 });


/* ============================================================
   1. $push  (append)  and  $addToSet  (append if absent)
   ============================================================ */

db.l06_employees.updateOne({ _id: 101 }, { $push: { skills: "Go" } });
show(101);                                                          // [ 'Java', 'MongoDB', 'NodeJS', 'Go' ]

db.l06_employees.updateOne({ _id: 101 }, { $push: { skills: "Go" } });      // duplicates allowed
show(101);                                                          // ... 'Go', 'Go'

db.l06_employees.updateOne({ _id: 101 }, { $addToSet: { skills: "Go" } });  // already there -> modifiedCount 0
db.l06_employees.updateOne({ _id: 101 }, { $addToSet: { skills: "Rust" } });
show(101);                                                          // ... 'Go', 'Go', 'Rust'

// $push on a MISSING field creates the array (Meera has no skills)
db.l06_employees.updateOne({ _id: 112 }, { $push: { skills: "Marketing" } });
show(112);                                                          // [ 'Marketing' ]

// $push on a NON-array field -> error
try {
    db.l06_employees.updateOne({ _id: 101 }, { $push: { name: "x" } });
} catch (e) {
    print("EXPECTED ERROR:", e.message);                            // The field 'name' must be an array but is of type string
}


/* ============================================================
   2. $push MODIFIERS: $each, $position, $slice, $sort
   ============================================================ */

// several values at once
db.l06_employees.updateOne({ _id: 102 }, { $push: { skills: { $each: ["Node", "GraphQL"] } } });
show(102);                                                          // JavaScript, React, MongoDB, Node, GraphQL

// insert at the front
db.l06_employees.updateOne({ _id: 102 }, { $push: { skills: { $each: ["TypeScript"], $position: 0 } } });
show(102);                                                          // TypeScript, JavaScript, ...

// keep only the LAST 3 (capped array: "last N events" pattern)
db.l06_employees.updateOne({ _id: 102 }, { $push: { skills: { $each: [], $slice: -3 } } });
show(102);                                                          // MongoDB, Node, GraphQL

// push scores, keep the TOP 3 sorted descending
db.l06_employees.updateOne({ _id: 103 }, { $push: { scores: { $each: [88, 95, 70, 91], $sort: -1, $slice: 3 } } });
db.l06_employees.findOne({ _id: 103 }, { _id: 0, scores: 1 });     // [ 95, 91, 88 ]

// $sort by a field of embedded documents
db.l06_employees.updateOne({ _id: 103 }, { $push: { reviews: { $each: [ { y: 2024, r: 4 }, { y: 2022, r: 3 }, { y: 2023, r: 5 } ], $sort: { y: 1 } } } });
db.l06_employees.findOne({ _id: 103 }, { _id: 0, reviews: 1 });    // ordered by y: 2022, 2023, 2024

// $addToSet with $each (union)
db.l06_employees.updateOne({ _id: 108 }, { $addToSet: { skills: { $each: ["SQL", "Go", "Python"] } } });
show(108);                                                          // Python, MongoDB, SQL, Go  (SQL and Python not duplicated)


/* ============================================================
   3. REMOVING: $pop, $pull, $pullAll, by index
   ============================================================ */

db.l06_employees.updateOne({ _id: 101 }, { $pop: { skills: 1 } });          // remove LAST (Rust)
db.l06_employees.updateOne({ _id: 101 }, { $pop: { skills: -1 } });         // remove FIRST (Java)
show(101);                                                                   // MongoDB, NodeJS, Go, Go

db.l06_employees.updateOne({ _id: 101 }, { $pull: { skills: "Go" } });      // removes ALL "Go"
show(101);                                                                   // MongoDB, NodeJS

db.l06_employees.updateOne({ _id: 106 }, { $pullAll: { skills: ["Excel", "SQL"] } });
show(106);                                                                   // Accounting

// $pull with a CONDITION on scalar elements
db.l06_employees.updateOne({ _id: 103 }, { $pull: { scores: { $lt: 90 } } });
db.l06_employees.findOne({ _id: 103 }, { _id: 0, scores: 1 });              // [ 95, 91 ]

// $pull with a condition on embedded documents: remove every line with qty < 2 from order 1002
db.l06_orders.updateOne({ _id: 1002 }, { $pull: { items: { qty: { $lt: 2 } } } });
db.l06_orders.findOne({ _id: 1002 }, { _id: 0, items: 1 });                 // only the Mouse line (qty 2)

// Remove by INDEX: $unset leaves null, then $pull the null
db.l06_employees.updateOne({ _id: 107 }, { $unset: { "skills.1": "" } });
show(107);                                                                   // SEO, null, Analytics
db.l06_employees.updateOne({ _id: 107 }, { $pull: { skills: null } });
show(107);                                                                   // SEO, Analytics


/* ============================================================
   4. UPDATE BY INDEX and REPLACE THE WHOLE ARRAY
   ============================================================ */

db.l06_employees.updateOne({ _id: 104 }, { $set: { "skills.0": "B2B Sales" } });
show(104);                                                                   // B2B Sales, Excel
db.l06_employees.updateOne({ _id: 104 }, { $set: { skills: ["Sales", "Excel", "CRM"] } });   // full replacement
show(104);


/* ============================================================
   5. POSITIONAL $  -  the FIRST element matched by the query
   ============================================================ */

// Order 1008: Laptop(1), Mouse(2), Keyboard(3). Change the qty of the Mouse line.
db.l06_orders.updateOne({ _id: 1008, "items.productId": 2 }, { $set: { "items.$.qty": 3 } });
db.l06_orders.findOne({ _id: 1008 }, { _id: 0, items: 1 });                 // Mouse qty 3

// $inc through $
db.l06_orders.updateOne({ _id: 1008, "items.productId": 3 }, { $inc: { "items.$.qty": 1 } });
db.l06_orders.findOne({ _id: 1008 }, { _id: 0, "items.qty": 1 });           // [1, 3, 2]

// The query MUST contain the array field, otherwise $ has no position
try {
    db.l06_orders.updateOne({ _id: 1008 }, { $set: { "items.$.qty": 9 } });
} catch (e) {
    print("EXPECTED ERROR:", e.message);                                     // The positional operator did not find the match needed from the query
}

// Scalar arrays: rename a skill
db.l06_employees.updateOne({ _id: 109, skills: "CRM" }, { $set: { "skills.$": "Salesforce CRM" } });
show(109);                                                                   // Sales, Salesforce CRM


/* ============================================================
   6. ALL POSITIONAL $[]  -  every element
   ============================================================ */

// 10 % discount on every line of order 1008
db.l06_orders.updateOne({ _id: 1008 }, { $mul: { "items.$[].unitPrice": 0.9 } });
db.l06_orders.findOne({ _id: 1008 }, { _id: 0, "items.unitPrice": 1 });     // 67500, 900, 2250

// add a field to every element
db.l06_orders.updateOne({ _id: 1008 }, { $set: { "items.$[].shipped": false } });
db.l06_orders.findOne({ _id: 1008 }, { _id: 0, items: 1 });


/* ============================================================
   7. FILTERED POSITIONAL $[id] + arrayFilters  -  the elements you choose
   ============================================================ */

// Mark as "bulk" every line with qty >= 10, in ALL orders
db.l06_orders.updateMany(
    {},
    { $set: { "items.$[line].bulk": true } },
    { arrayFilters: [ { "line.qty": { $gte: 10 } } ] }
);
db.l06_orders.find({ "items.bulk": true }, { _id: 1, items: 1 });           // 1010 (Notebook 20, Pen 50), 1016 (Mouse 10), 1017 (Pen 100)

// Several conditions in one filter, and several filters
db.l06_orders.updateMany(
    { status: "Completed" },
    { $mul: { "items.$[cheap].unitPrice": 1.05 }, $set: { "items.$[laptop].warranty": "2y" } },
    { arrayFilters: [ { "cheap.unitPrice": { $lt: 100 } }, { "laptop.productId": 1 } ] }
);
db.l06_orders.findOne({ _id: 1010 }, { _id: 0, items: 1 });                 // 52.5 and 10.5
db.l06_orders.findOne({ _id: 1014 }, { _id: 0, items: 1 });                 // warranty 2y

// Every identifier in the update must have a filter (and vice versa)
try {
    db.l06_orders.updateOne({ _id: 1001 }, { $set: { "items.$[x].y": 1 } }, { arrayFilters: [ { "z.qty": 1 } ] });
} catch (e) {
    print("EXPECTED ERROR:", e.message);
}

// NESTED arrays: $[outer].inner.$[inner]
db.l06_employees.updateOne({ _id: 105 }, { $set: { projects: [
    { name: "Hiring 2025", tasks: [ { t: "JD", done: false }, { t: "Screening", done: false } ] },
    { name: "Onboarding",  tasks: [ { t: "Docs", done: false } ] }
] } });
db.l06_employees.updateOne(
    { _id: 105 },
    { $set: { "projects.$[p].tasks.$[t].done": true } },
    { arrayFilters: [ { "p.name": "Hiring 2025" }, { "t.t": "JD" } ] }
);
db.l06_employees.findOne({ _id: 105 }, { _id: 0, projects: 1 });            // only JD is done


/* ============================================================
   8. NESTED DOCUMENTS (not arrays)
   ============================================================ */

// One field inside: dot notation keeps the rest
db.l06_employees.updateOne({ _id: 101 }, { $set: { "address.city": "Gurgaon" } });
db.l06_employees.findOne({ _id: 101 }, { _id: 0, address: 1 });             // city changed, state & pincode kept

// Add a nested field, remove a nested field
db.l06_employees.updateOne({ _id: 101 }, { $set: { "address.landmark": "Cyber Hub" }, $unset: { "address.pincode": "" } });
db.l06_employees.findOne({ _id: 101 }, { _id: 0, address: 1 });

// Replace the whole sub-document
db.l06_employees.updateOne({ _id: 101 }, { $set: { address: { city: "Delhi", state: "Delhi", pincode: 110001 } } });

// $inc / $rename with dot paths
db.l06_employees.updateOne({ _id: 101 }, { $inc: { "address.pincode": 1 } });
db.l06_employees.updateOne({ _id: 101 }, { $rename: { "address.pincode": "address.zip" } });
db.l06_employees.findOne({ _id: 101 }, { _id: 0, address: 1 });             // zip: 110002

// $rename CANNOT target array elements
try {
    db.l06_orders.updateOne({ _id: 1001 }, { $rename: { "items.0.qty": "items.0.quantity" } });
} catch (e) {
    print("EXPECTED ERROR:", e.message);
}


/* ============================================================
   CLEANUP
   ============================================================ */
db.l06_employees.drop();
db.l06_orders.drop();

/* ------------------------------------------------------------
   DONE. Next: Exercises.js
   ------------------------------------------------------------ */
