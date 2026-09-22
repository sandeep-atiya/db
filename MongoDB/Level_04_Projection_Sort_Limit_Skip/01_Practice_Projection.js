/* ============================================================
   LEVEL 04 - PROJECTION, SORT, LIMIT, SKIP  |  01_Practice_Projection.js
   ------------------------------------------------------------
   Topics : inclusion / exclusion, _id, nested fields, array
            projection ($slice, $elemMatch, $), computed fields
            with aggregation expressions, projection in findOne

   HOW TO PRACTICE: block by block, predict first. Read-only.
   ============================================================ */

use("companyDB");


/* ============================================================
   1. INCLUSION  { field: 1 }
   ============================================================ */

db.employees.find({}, { name: 1, salary: 1 });                   // _id comes along automatically
db.employees.find({}, { _id: 0, name: 1, salary: 1 });           // without _id
db.employees.find({ departmentId: 2 }, { name: 1 });             // filter + projection

// true / 1 are the same; any truthy value includes
db.employees.find({ _id: 101 }, { name: true, email: true });


/* ============================================================
   2. EXCLUSION  { field: 0 }
   ============================================================ */

db.employees.find({ _id: 101 }, { address: 0, skills: 0, email: 0 });   // everything except these

// Mixing include and exclude is an ERROR ...
try {
    db.employees.find({}, { name: 1, salary: 0 }).toArray();
} catch (e) {
    print("EXPECTED ERROR:", e.message);        // Cannot do exclusion on field salary in inclusion projection
}
// ... except _id: 0
db.employees.find({ _id: 101 }, { _id: 0, name: 1 });


/* ============================================================
   3. NESTED FIELDS
   ============================================================ */

db.employees.find({ _id: 101 }, { _id: 0, name: 1, "address.city": 1 });       // address: { city: 'Delhi' }
db.employees.find({ _id: 101 }, { _id: 0, name: 1, address: { city: 1, state: 1 } });   // same, nested-object form
db.employees.find({ _id: 101 }, { "address.pincode": 0 });                    // exclude one nested field
db.orders.find({ _id: 1002 }, { _id: 0, "items.productId": 1, "items.qty": 1 });   // projection applies to EVERY array element


/* ============================================================
   4. ARRAY PROJECTION: $slice
   ============================================================ */

db.employees.find({ _id: 101 }, { _id: 0, name: 1, skills: { $slice: 2 } });        // first 2: Java, MongoDB
db.employees.find({ _id: 101 }, { _id: 0, name: 1, skills: { $slice: -1 } });       // last 1: NodeJS
db.employees.find({ _id: 101 }, { _id: 0, name: 1, skills: { $slice: [1, 1] } });   // skip 1, take 1: MongoDB
db.orders.find({ _id: 1008 }, { _id: 0, items: { $slice: 2 } });                    // first 2 of 3 items

// $slice keeps the OTHER fields (it is treated like an exclusion of the rest of the array)
db.employees.find({ _id: 101 }, { skills: { $slice: 1 } });                          // full document, skills cut to 1


/* ============================================================
   5. ARRAY PROJECTION: $ and $elemMatch  (FIRST matching element only)
   ============================================================ */

// $ = the first array element that satisfied the QUERY condition on that array
db.orders.find({ "items.qty": { $gte: 2 } }, { _id: 1, "items.$": 1 });
// 1002 -> Mouse qty 2, 1005 -> Monitor qty 2, 1007 -> Keyboard qty 2, ...

// $elemMatch in the PROJECTION = first element matching THIS condition (independent of the query)
db.orders.find({ _id: { $in: [1002, 1008, 1019] } }, { _id: 1, items: { $elemMatch: { productId: 2 } } });
// 1002 and 1008 show the Mouse line; 1019 has no such item -> "items" is simply absent

// Only the FIRST match is returned. All matches -> aggregation $filter (Level 09):
db.orders.aggregate([
    { $match: { _id: 1008 } },
    { $project: { items: { $filter: { input: "$items", as: "i", cond: { $lte: ["$$i.unitPrice", 2500] } } } } }
]);                                                                                  // Mouse AND Keyboard


/* ============================================================
   6. COMPUTED FIELDS IN A PROJECTION  (aggregation expressions, 4.4+)
   ============================================================ */

db.employees.find({ departmentId: 1 }, {
    _id: 0,
    name: 1,
    annualSalary: { $multiply: ["$salary", 12] },
    city: "$address.city",                                        // rename / flatten a nested field
    skillCount: { $size: "$skills" },
    label: { $concat: ["$name", " (", "$address.city", ")"] },
    band: { $cond: [ { $gte: ["$salary", 70000] }, "HIGH", "NORMAL" ] },
    fixed: { $literal: 1 }                                        // a constant (plain 1 would mean "include")
});

// Missing arrays break $size -> guard with $ifNull
db.employees.find({ _id: { $in: [101, 112] } }, { _id: 0, name: 1, skillCount: { $size: { $ifNull: ["$skills", []] } } });   // Rahul 3, Meera 0

// Expressions in projection + exclusion cannot be mixed either (it is an inclusion projection)


/* ============================================================
   7. PROJECTION WITH findOne AND WITH OPTIONS
   ============================================================ */

db.employees.findOne({ _id: 106 }, { _id: 0, name: 1, salary: 1 });
db.employees.findOne({}, { _id: 0, name: 1, salary: 1 }, { sort: { salary: -1 } });   // highest paid (Sneha) - options form
db.employees.find({}, { _id: 0, name: 1 }).limit(2);                                  // projection + cursor methods


/* ============================================================
   8. WHAT PROJECTION DOES NOT DO
   ============================================================ */

// It does not FILTER documents: every matching document is returned, only its shape changes.
db.orders.find({}, { items: { $elemMatch: { productId: 11 } } }).count();            // 19 - all orders, none has a Webcam item

// It does not rename fields in place (use "$field" expression or $project in aggregation - see section 6)

/* ------------------------------------------------------------
   DONE. Next: 02_Practice_Sort_Limit_Skip_Count.js
   ------------------------------------------------------------ */
