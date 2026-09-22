/* ============================================================
   LEVEL 09  |  03_Practice_Array_Expressions_Out_Merge_Views.js
   ------------------------------------------------------------
   Topics : array expressions ($size $first $last $slice $filter
            $map $reduce $concatArrays set operators $indexOfArray
            $range $zip $sortArray $objectToArray $arrayToObject),
            STRING_AGG, PIVOT, relational division, $out, $merge,
            views (createView)

   HOW TO PRACTICE: block by block, predict first.
   Creates l09_* collections and a view; dropped in CLEANUP.
   ============================================================ */

use("companyDB");


/* ============================================================
   1. READING ARRAYS: $size, $first, $last, $arrayElemAt, $slice, $in
   ============================================================ */

db.employees.aggregate([ { $match: { _id: 101 } }, { $project: { _id: 0, name: 1,
    n: { $size: "$skills" },
    first: { $first: "$skills" }, last: { $last: "$skills" }, second: { $arrayElemAt: ["$skills", 1] },
    firstTwo: { $slice: ["$skills", 2] }, lastOne: { $slice: ["$skills", -1] },
    knowsMongo: { $in: ["MongoDB", "$skills"] },          // $in as an EXPRESSION: [value, array]
    pos: { $indexOfArray: ["$skills", "NodeJS"] } } } ]);
// n 3, first Java, last NodeJS, second MongoDB, firstTwo [Java, MongoDB], lastOne [NodeJS], knowsMongo true, pos 2

// Missing arrays: $size errors, so guard with $ifNull
db.employees.aggregate([ { $project: { _id: 0, name: 1, n: { $size: { $ifNull: ["$skills", []] } } } }, { $match: { n: 0 } } ]);   // Anjali, Meera


/* ============================================================
   2. $filter, $map, $reduce  (per-document array processing)
   ============================================================ */

// $filter: keep only lines with qty >= 2 (ALL matches - unlike the $elemMatch projection)
db.orders.aggregate([ { $match: { _id: 1008 } }, { $project: { bigLines: { $filter: { input: "$items", as: "i", cond: { $gte: ["$$i.unitPrice", 2500] } } } } } ]);   // Laptop, Keyboard

// $map: compute a line total per item
db.orders.aggregate([ { $match: { _id: 1008 } }, { $project: { lineTotals: { $map: { input: "$items", as: "i", in: { p: "$$i.productId", total: { $multiply: ["$$i.qty", "$$i.unitPrice"] } } } } } } ]);

// $reduce: sum the line totals (order total recomputed, no $unwind needed)
db.orders.aggregate([ { $project: { totalAmount: 1, recomputed: { $reduce: {
    input: "$items", initialValue: 0, in: { $add: ["$$value", { $multiply: ["$$this.qty", "$$this.unitPrice"] }] } } } } },
    { $match: { $expr: { $ne: ["$totalAmount", "$recomputed"] } } }, { $count: "mismatches" } ]);   // [] -> nothing printed = 0 mismatches

// $reduce for STRING_AGG: skills joined with ", "
db.employees.aggregate([ { $match: { departmentId: 1 } }, { $project: { _id: 0, name: 1, skillList: { $reduce: {
    input: "$skills", initialValue: "", in: { $concat: ["$$value", { $cond: [ { $eq: ["$$value", ""] }, "", ", " ] }, "$$this"] } } } } } ]);
// Rahul: "Java, MongoDB, NodeJS"

// STRING_AGG per group: $group + $push, then $reduce (names per department)
db.employees.aggregate([
    { $sort: { name: 1 } },
    { $group: { _id: "$departmentId", names: { $push: "$name" } } },
    { $project: { members: { $reduce: { input: "$names", initialValue: "", in: { $concat: ["$$value", { $cond: [ { $eq: ["$$value", ""] }, "", ", " ] }, "$$this"] } } } } },
    { $sort: { _id: 1 } }
]);                                                       // 1: "Amit, Pooja, Rahul" ...


/* ============================================================
   3. SET OPERATORS and relational division
   ============================================================ */

db.employees.aggregate([ { $match: { _id: { $in: [106, 108] } } }, { $group: { _id: null, a: { $first: "$skills" }, b: { $last: "$skills" } } },
    { $project: { _id: 0, a: 1, b: 1,
        union: { $setUnion: ["$a", "$b"] }, common: { $setIntersection: ["$a", "$b"] },
        onlyA: { $setDifference: ["$a", "$b"] }, sameSet: { $setEquals: ["$a", "$b"] }, subset: { $setIsSubset: [["SQL"], "$a"] } } } ]);
// a Sneha [Accounting, Excel, SQL], b Pooja [Python, MongoDB, SQL] -> common [SQL], onlyA [Accounting, Excel], subset true

// "Customers who bought from EVERY category" (relational division)
db.orders.aggregate([
    { $unwind: "$items" },
    { $lookup: { from: "products", localField: "items.productId", foreignField: "_id", as: "p" } },
    { $group: { _id: "$customerId", categories: { $addToSet: { $first: "$p.category" } } } },
    { $lookup: { from: "products", pipeline: [ { $group: { _id: "$category" } } ], as: "allCats" } },
    { $project: { categories: 1, missing: { $setDifference: ["$allCats._id", "$categories"] } } },
    { $match: { missing: [] } }
]);                                                       // [] -> nobody bought all 3 categories
// Relaxed: at least 2 categories
db.orders.aggregate([
    { $unwind: "$items" },
    { $lookup: { from: "products", localField: "items.productId", foreignField: "_id", as: "p" } },
    { $group: { _id: "$customerId", categories: { $addToSet: { $first: "$p.category" } } } },
    { $match: { $expr: { $gte: [ { $size: "$categories" }, 2 ] } } },
    { $sort: { _id: 1 } }
]);                                                       // 1, 2, 3, 5, 7


/* ============================================================
   4. $concatArrays, $range, $zip, $reverseArray, $sortArray
   ============================================================ */

db.employees.aggregate([ { $match: { _id: 101 } }, { $project: { _id: 0,
    more:     { $concatArrays: ["$skills", ["Go"]] },
    numbers:  { $range: [1, 6] },                          // [1,2,3,4,5]
    zipped:   { $zip: { inputs: [ "$skills", { $range: [0, 3] } ] } },   // [[Java,0],[MongoDB,1],[NodeJS,2]]
    reversed: { $reverseArray: "$skills" },
    sorted:   { $sortArray: { input: "$skills", sortBy: -1 } } } } ]);

// $sortArray on embedded documents (5.2+): order lines by qty desc
db.orders.aggregate([ { $match: { _id: 1008 } }, { $project: { items: { $sortArray: { input: "$items", sortBy: { unitPrice: -1 } } } } } ]);


/* ============================================================
   5. $objectToArray / $arrayToObject  -  PIVOT and dynamic keys
   ============================================================ */

// PIVOT: one row per customer, one column per status (SQL PIVOT)
db.orders.aggregate([
    { $group: { _id: { c: "$customerId", s: "$status" }, n: { $sum: 1 } } },
    { $group: { _id: "$_id.c", kv: { $push: { k: "$_id.s", v: "$n" } } } },
    { $replaceWith: { $mergeObjects: [ { customerId: "$_id", Completed: 0, Pending: 0, Cancelled: 0 }, { $arrayToObject: "$kv" } ] } },
    { $sort: { customerId: 1 } }
]);                                                       // { customerId: 1, Completed: 3, Pending: 1, Cancelled: 0 } ...

// UNPIVOT: turn a document's fields into rows
db.employees.aggregate([ { $match: { _id: 101 } }, { $project: { pairs: { $objectToArray: "$address" } } }, { $unwind: "$pairs" }, { $project: { _id: 0, field: "$pairs.k", value: "$pairs.v" } } ]);
// city Delhi / state Delhi / pincode 110001

// Count fields per document (schema exploration)
db.employees.aggregate([ { $project: { _id: 0, name: 1, fieldCount: { $size: { $objectToArray: "$$ROOT" } } } }, { $sort: { fieldCount: 1 } }, { $limit: 3 } ]);   // Meera 9, Anjali 9 ...


/* ============================================================
   6. $out  -  materialise into a NEW collection (SELECT INTO)
   ============================================================ */

db.orders.aggregate([
    { $lookup: { from: "customers", localField: "customerId", foreignField: "_id", as: "c" } },
    { $project: { orderDate: 1, status: 1, totalAmount: 1, customerName: { $first: "$c.name" }, city: { $first: "$c.city" } } },
    { $out: "l09_orders_flat" }
]);                                                       // no output - the result went into the collection
db.l09_orders_flat.countDocuments();                       // 19
db.l09_orders_flat.findOne();

// $out REPLACES the target completely (and drops its indexes) each time
db.l09_orders_flat.createIndex({ city: 1 });
db.orders.aggregate([ { $match: { status: "Pending" } }, { $out: "l09_orders_flat" } ]);
db.l09_orders_flat.countDocuments();                       // 2
db.l09_orders_flat.getIndexes().length;                    // 1 - the city index is gone


/* ============================================================
   7. $merge  -  upsert into an existing collection (incremental materialised view)
   ============================================================ */

// First run: build a per-customer summary
db.orders.aggregate([
    { $group: { _id: "$customerId", orders: { $sum: 1 }, revenue: { $sum: "$totalAmount" } } },
    { $merge: { into: "l09_customer_stats", on: "_id", whenMatched: "replace", whenNotMatched: "insert" } }
]);
db.l09_customer_stats.find().sort({ _id: 1 });

// Someone adds an extra field by hand ...
db.l09_customer_stats.updateOne({ _id: 1 }, { $set: { segment: "gold" } });

// ... "merge" keeps fields the pipeline does not produce; "replace" would drop them
db.orders.aggregate([
    { $group: { _id: "$customerId", orders: { $sum: 1 }, revenue: { $sum: "$totalAmount" } } },
    { $merge: { into: "l09_customer_stats", on: "_id", whenMatched: "merge", whenNotMatched: "insert" } }
]);
db.l09_customer_stats.findOne({ _id: 1 });                 // still has segment: 'gold'

// whenMatched as a pipeline: keep a "lastRefreshed" timestamp and only overwrite the numbers
db.orders.aggregate([
    { $group: { _id: "$customerId", orders: { $sum: 1 }, revenue: { $sum: "$totalAmount" } } },
    { $merge: { into: "l09_customer_stats", on: "_id",
                whenMatched: [ { $set: { orders: "$$new.orders", revenue: "$$new.revenue", lastRefreshed: "$$NOW" } } ],
                whenNotMatched: "insert" } }
]);
db.l09_customer_stats.findOne({ _id: 1 }, { _id: 0, orders: 1, revenue: 1, segment: 1, lastRefreshed: 1 });

// whenMatched: "fail" -> error if a match exists (safe insert-only merges)
try {
    db.orders.aggregate([ { $group: { _id: "$customerId" } }, { $merge: { into: "l09_customer_stats", whenMatched: "fail" } } ]);
} catch (e) {
    print("EXPECTED ERROR:", e.message.substring(0, 80));
}


/* ============================================================
   8. VIEWS  -  a saved, read-only pipeline
   ============================================================ */

db.createView("vw_l09_orders_full", "orders", [
    { $lookup: { from: "customers", localField: "customerId", foreignField: "_id", as: "c" } },
    { $lookup: { from: "employees", localField: "employeeId", foreignField: "_id", as: "e" } },
    { $project: { orderDate: 1, status: 1, totalAmount: 1, customer: { $first: "$c.name" }, salesperson: { $ifNull: [ { $first: "$e.name" }, "(online)" ] } } }
]);
db.vw_l09_orders_full.find({ status: "Pending" });          // query it like a collection (the pipeline runs every time)
db.vw_l09_orders_full.countDocuments({ salesperson: "Priya" });   // 7
db.vw_l09_orders_full.aggregate([ { $group: { _id: "$salesperson", revenue: { $sum: "$totalAmount" } } }, { $sort: { revenue: -1 } } ]);

db.getCollectionInfos({ type: "view" }).map(v => v.name);   // [ 'vw_l09_orders_full' ]
db.getCollectionInfos({ name: "vw_l09_orders_full" })[0].options.viewOn;   // orders

// Views are READ-ONLY
try {
    db.vw_l09_orders_full.insertOne({ x: 1 });
} catch (e) {
    print("EXPECTED ERROR:", e.message);                    // Namespace ... is a view, not a collection
}


/* ============================================================
   CLEANUP
   ============================================================ */
db.l09_orders_flat.drop(); db.l09_customer_stats.drop(); db.vw_l09_orders_full.drop();

/* ------------------------------------------------------------
   DONE. Next: Exercises.js
   ------------------------------------------------------------ */
