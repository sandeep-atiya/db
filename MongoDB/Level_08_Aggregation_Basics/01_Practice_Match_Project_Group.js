/* ============================================================
   LEVEL 08 - AGGREGATION BASICS  |  01_Practice_Match_Project_Group.js
   ------------------------------------------------------------
   Topics : pipeline anatomy, $match, $project, $set / $addFields,
            $unset, expressions & field paths, $group with every
            common accumulator, compound keys, HAVING, $count,
            $sortByCount, conditional aggregation

   HOW TO PRACTICE: block by block, predict first. Read-only.
   ============================================================ */

use("companyDB");


/* ============================================================
   1. THE SIMPLEST PIPELINES
   ============================================================ */

// An empty pipeline = find()
db.departments.aggregate([]);

// $match = find's filter, as a stage
db.employees.aggregate([ { $match: { departmentId: 1 } } ]);

// Stages run IN ORDER: match -> project
db.employees.aggregate([
    { $match: { departmentId: 1 } },
    { $project: { _id: 0, name: 1, salary: 1 } }
]);

// The result is a cursor (toArray / forEach / map work like on find)
db.employees.aggregate([ { $match: { departmentId: 1 } }, { $project: { _id: 0, name: 1 } } ]).map(d => d.name).toArray();   // [ 'Rahul', 'Amit', 'Pooja' ]


/* ============================================================
   2. $project - include, exclude, rename, compute
   ============================================================ */

db.employees.aggregate([ { $match: { _id: 101 } }, { $project: { name: 1, salary: 1 } } ]);          // include (+ _id)
db.employees.aggregate([ { $match: { _id: 101 } }, { $project: { skills: 0, address: 0 } } ]);       // exclude
db.employees.aggregate([ { $match: { _id: 101 } }, { $project: {
    _id: 0,
    employee: "$name",                                     // rename
    city: "$address.city",                                 // flatten a nested field
    annual: { $multiply: ["$salary", 12] },                // compute
    skillCount: { $size: "$skills" },
    isHighPaid: { $gte: ["$salary", 70000] },              // boolean expression
    tag: "employee",                                       // literal string (no $ -> literal)
    weird: { $literal: "$name" }                           // literal that starts with $
} } ]);

// "$field" reads the field; "field" is just text - the classic bug
db.employees.aggregate([ { $match: { _id: 101 } }, { $project: { _id: 0, a: "$name", b: "name" } } ]);   // a: 'Rahul', b: 'name'


/* ============================================================
   3. $set / $addFields (keep everything, add fields) and $unset
   ============================================================ */

db.products.aggregate([
    { $match: { category: "Furniture" } },
    { $set: { inventoryValue: { $multiply: ["$price", "$stock"] }, inStock: { $gt: ["$stock", 0] } } },   // all fields kept
    { $unset: ["tags", "ratings"] }
]);

// $set can overwrite an existing field, and can reference a field set in the SAME stage? No - use two stages:
db.products.aggregate([
    { $match: { _id: 1 } },
    { $set: { priceWithTax: { $multiply: ["$price", 1.18] } } },
    { $set: { priceWithTaxRounded: { $round: ["$priceWithTax", 0] } } },
    { $project: { _id: 0, name: 1, price: 1, priceWithTax: 1, priceWithTaxRounded: 1 } }
]);


/* ============================================================
   4. $group - one group (SQL aggregate without GROUP BY)
   ============================================================ */

db.employees.aggregate([ { $group: { _id: null, employees: { $sum: 1 }, payroll: { $sum: "$salary" }, avgSalary: { $avg: "$salary" },
                                     minSalary: { $min: "$salary" }, maxSalary: { $max: "$salary" } } } ]);
// employees 12, payroll 805000, avg 67083.33, min 48000, max 90000

// $count: {} is the modern way to count (5.0+)
db.orders.aggregate([ { $group: { _id: null, n: { $count: {} }, revenue: { $sum: "$totalAmount" } } } ]);   // 19, 618000

// $count STAGE: just a number in a document
db.orders.aggregate([ { $match: { status: "Completed" } }, { $count: "completedOrders" } ]);          // 16


/* ============================================================
   5. $group BY A FIELD  (GROUP BY)
   ============================================================ */

db.employees.aggregate([
    { $group: { _id: "$departmentId", n: { $sum: 1 }, total: { $sum: "$salary" }, avg: { $avg: "$salary" }, max: { $max: "$salary" } } },
    { $sort: { _id: 1 } }
]);
// null:1 (Anjali)  1:3 215000 71666.67  2:3 192000 64000  3:1 60000  4:2 162000 81000  5:2 128000 64000

// Rename _id for readable output
db.orders.aggregate([
    { $group: { _id: "$status", orders: { $sum: 1 }, revenue: { $sum: "$totalAmount" } } },
    { $project: { _id: 0, status: "$_id", orders: 1, revenue: 1 } },
    { $sort: { revenue: -1 } }
]);                                                       // Completed 16 / 574000, Pending 2 / 36000, Cancelled 1 / 8000

// $sum: 1 vs $sum: "$field" vs $avg with missing values
db.products.aggregate([ { $group: { _id: "$category", products: { $sum: 1 }, stock: { $sum: "$stock" }, avgPrice: { $avg: "$price" } } }, { $sort: { _id: 1 } } ]);
// Electronics 6 / 215 / 18500, Furniture 3 / 40 / 11666.67, Stationery 2 / 1500 / 30


/* ============================================================
   6. COMPOUND KEYS AND EXPRESSION KEYS
   ============================================================ */

// GROUP BY state, city
db.employees.aggregate([
    { $group: { _id: { state: "$address.state", city: "$address.city" }, n: { $sum: 1 } } },
    { $sort: { "_id.state": 1, "_id.city": 1 } }
]);

// GROUP BY YEAR(hireDate)
db.employees.aggregate([
    { $group: { _id: { $year: "$hireDate" }, hired: { $sum: 1 }, names: { $push: "$name" } } },
    { $sort: { _id: 1 } }
]);                                                       // 2020:1, 2021:2, 2022:3, 2023:3, 2024:3

// GROUP BY a computed band (CASE WHEN)
db.employees.aggregate([
    { $group: { _id: { $cond: [ { $gte: ["$salary", 70000] }, "70k+", "<70k" ] }, n: { $sum: 1 }, avg: { $avg: "$salary" } } }
]);                                                       // 70k+ : 5,  <70k : 7

// Grouping by an ARRAY field groups by the WHOLE array (per-element needs $unwind - Level 09)
db.customers.aggregate([ { $group: { _id: "$tags", n: { $sum: 1 } } } ]);


/* ============================================================
   7. $push, $addToSet, $first, $last, $mergeObjects, $topN
   ============================================================ */

// Names per department (STRING_AGG-like), distinct cities per department
db.employees.aggregate([
    { $group: { _id: "$departmentId", names: { $push: "$name" }, cities: { $addToSet: "$address.city" } } },
    { $sort: { _id: 1 } }
]);

// $first / $last take the first / last document IN PIPELINE ORDER -> $sort first!
db.employees.aggregate([
    { $sort: { salary: -1 } },
    { $group: { _id: "$departmentId", topEarner: { $first: "$name" }, topSalary: { $first: "$salary" }, lowest: { $last: "$name" } } },
    { $sort: { _id: 1 } }
]);                                                       // 1: Rahul 85000 / Amit or Pooja ... 4: Sneha / Deepak

// Keep the WHOLE top document with $$ROOT
db.employees.aggregate([
    { $sort: { salary: -1 } },
    { $group: { _id: "$departmentId", top: { $first: "$$ROOT" } } },
    { $replaceRoot: { newRoot: "$top" } },                // promote it back to the top level (Level 09)
    { $project: { _id: 0, name: 1, departmentId: 1, salary: 1 } },
    { $sort: { departmentId: 1 } }
]);

// $topN / $firstN (5.2+): top 2 salaries per department without a separate $sort
db.employees.aggregate([
    { $group: { _id: "$departmentId", top2: { $topN: { n: 2, sortBy: { salary: -1 }, output: { name: "$name", salary: "$salary" } } } } },
    { $sort: { _id: 1 } }
]);

// $mergeObjects: merge documents in a group (later ones win)
db.employees.aggregate([
    { $match: { departmentId: 1 } },
    { $group: { _id: "$departmentId", merged: { $mergeObjects: "$address" } } }
]);                                                       // the last address seen in the group


/* ============================================================
   8. HAVING  =  $match AFTER $group
   ============================================================ */

// Departments with more than 2 employees
db.employees.aggregate([
    { $group: { _id: "$departmentId", n: { $sum: 1 } } },
    { $match: { n: { $gt: 2 } } }
]);                                                       // 1 and 2

// Customers who spent more than 80000 in total
db.orders.aggregate([
    { $group: { _id: "$customerId", spent: { $sum: "$totalAmount" }, orders: { $sum: 1 } } },
    { $match: { spent: { $gt: 80000 } } },
    { $sort: { spent: -1 } }
]);                                                       // 5: 158000, 1: 128000, 6: 88500, 7: 87000

// WHERE and HAVING together: completed orders only, customers with >= 3 of them
db.orders.aggregate([
    { $match: { status: "Completed" } },                  // WHERE (before)
    { $group: { _id: "$customerId", completed: { $sum: 1 } } },
    { $match: { completed: { $gte: 3 } } }                // HAVING (after)
]);                                                       // 1: 3, 2: 4


/* ============================================================
   9. COUNT DISTINCT
   ============================================================ */

// How many different cities do employees live in?
db.employees.aggregate([ { $group: { _id: "$address.city" } }, { $count: "cities" } ]);                          // 5
db.employees.aggregate([ { $group: { _id: null, cities: { $addToSet: "$address.city" } } }, { $project: { _id: 0, n: { $size: "$cities" } } } ]);   // 5


/* ============================================================
   10. CONDITIONAL AGGREGATION  (SUM(CASE WHEN ...))
   ============================================================ */

db.orders.aggregate([
    { $group: {
        _id: "$customerId",
        orders:    { $sum: 1 },
        completed: { $sum: { $cond: [ { $eq: ["$status", "Completed"] }, 1, 0 ] } },
        pending:   { $sum: { $cond: [ { $eq: ["$status", "Pending"] }, 1, 0 ] } },
        cancelled: { $sum: { $cond: [ { $eq: ["$status", "Cancelled"] }, 1, 0 ] } },
        completedRevenue: { $sum: { $cond: [ { $eq: ["$status", "Completed"] }, "$totalAmount", 0 ] } }
    } },
    { $sort: { _id: 1 } }
]);
// customer 1: 4 orders, 3 completed, 1 pending -> 96000 ; customer 5: 2, 1, 0, 1 -> 150000


/* ============================================================
   11. $sortByCount  (group + count + sort desc in one stage)
   ============================================================ */

db.orders.aggregate([ { $sortByCount: "$status" } ]);                      // Completed 16, Pending 2, Cancelled 1
db.orders.aggregate([ { $sortByCount: "$payment.method" } ]);              // Card 8, UPI 7, COD 4
db.employees.aggregate([ { $sortByCount: "$address.city" } ]);

/* ------------------------------------------------------------
   DONE. Next: 02_Practice_Sort_Limit_Patterns.js
   ------------------------------------------------------------ */
