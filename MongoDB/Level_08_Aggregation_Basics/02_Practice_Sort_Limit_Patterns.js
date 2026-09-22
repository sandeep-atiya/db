/* ============================================================
   LEVEL 08 - AGGREGATION BASICS  |  02_Practice_Sort_Limit_Patterns.js
   ------------------------------------------------------------
   Topics : $sort, $limit, $skip (order matters!), top-N,
            Nth highest, top-N per group, percentages of total,
            pipeline pagination, $sample, allowDiskUse, explain,
            common reporting patterns

   HOW TO PRACTICE: block by block, predict first. Read-only.
   ============================================================ */

use("companyDB");


/* ============================================================
   1. $sort + $limit + $skip  -  ORDER MATTERS
   ============================================================ */

// Top 3 earners
db.employees.aggregate([ { $sort: { salary: -1 } }, { $limit: 3 }, { $project: { _id: 0, name: 1, salary: 1 } } ]);
// Sneha, Rahul, Priya

// Reverse the stages: first 3 documents in natural order, THEN sorted -> a different answer!
db.employees.aggregate([ { $limit: 3 }, { $sort: { salary: -1 } }, { $project: { _id: 0, name: 1, salary: 1 } } ]);
// Rahul, Priya, Amit  (only 101-103 were considered)

// Ranks 4-6: sort -> skip -> limit
db.employees.aggregate([ { $sort: { salary: -1 } }, { $skip: 3 }, { $limit: 3 }, { $project: { _id: 0, name: 1, salary: 1 } } ]);
// Deepak, Karan, Amit/Pooja

// Ties again: add _id to the sort for a deterministic order
db.employees.aggregate([ { $sort: { salary: -1, _id: 1 } }, { $skip: 5 }, { $limit: 2 }, { $project: { _id: 1, name: 1, salary: 1 } } ]);   // Amit 102, Pooja 108


/* ============================================================
   2. Nth HIGHEST SALARY  (with and without ties)
   ============================================================ */

// 2nd highest DISTINCT salary: group by salary -> sort -> skip 1 -> limit 1
db.employees.aggregate([
    { $group: { _id: "$salary" } },
    { $sort: { _id: -1 } },
    { $skip: 1 }, { $limit: 1 },
    { $project: { _id: 0, secondHighest: "$_id" } }
]);                                                       // 85000

// 6th highest distinct salary = 65000 (Amit AND Pooja) -> who has it?
db.employees.aggregate([
    { $group: { _id: "$salary", names: { $push: "$name" } } },
    { $sort: { _id: -1 } },
    { $skip: 5 }, { $limit: 1 }
]);                                                       // { _id: 65000, names: [ 'Amit', 'Pooja' ] }
// (Level 09: $setWindowFields with $denseRank does this the SQL way.)


/* ============================================================
   3. TOP-N PER GROUP  (3 ways)
   ============================================================ */

// a) sort + group + $first  (top 1)
db.employees.aggregate([
    { $sort: { salary: -1 } },
    { $group: { _id: "$departmentId", name: { $first: "$name" }, salary: { $first: "$salary" } } },
    { $sort: { _id: 1 } }
]);

// b) sort + group + $push + $slice  (top 2, keeps documents)
db.employees.aggregate([
    { $sort: { salary: -1 } },
    { $group: { _id: "$departmentId", people: { $push: { name: "$name", salary: "$salary" } } } },
    { $project: { top2: { $slice: ["$people", 2] } } },
    { $sort: { _id: 1 } }
]);

// c) $topN accumulator (5.2+) - shortest
db.orders.aggregate([
    { $group: { _id: "$customerId", biggest2: { $topN: { n: 2, sortBy: { totalAmount: -1 }, output: { order: "$_id", amount: "$totalAmount" } } } } },
    { $sort: { _id: 1 } }
]);


/* ============================================================
   4. PERCENT OF TOTAL  (share of revenue per status)
   ============================================================ */

db.orders.aggregate([
    { $group: { _id: "$status", revenue: { $sum: "$totalAmount" } } },
    { $group: { _id: null, total: { $sum: "$revenue" }, rows: { $push: "$$ROOT" } } },     // grand total + keep the rows
    { $unwind: "$rows" },                                                                    // (Level 09) one doc per row again
    { $project: { _id: 0, status: "$rows._id", revenue: "$rows.revenue",
                  pct: { $round: [ { $multiply: [ { $divide: ["$rows.revenue", "$total"] }, 100 ] }, 1 ] } } },
    { $sort: { revenue: -1 } }
]);                                                       // Completed 92.9 %, Pending 5.8 %, Cancelled 1.3 %


/* ============================================================
   5. MONTHLY REVENUE  (preview of Level 10 date operators)
   ============================================================ */

db.orders.aggregate([
    { $match: { status: "Completed" } },
    { $group: { _id: { y: { $year: "$orderDate" }, m: { $month: "$orderDate" } }, orders: { $sum: 1 }, revenue: { $sum: "$totalAmount" } } },
    { $sort: { "_id.y": 1, "_id.m": 1 } }
]);
// Jan 110000, Feb 65000, Mar 84500, Apr 7500, May 42000, Jun 177500, Jul 10000, Aug 75000, Sep 2500


/* ============================================================
   6. SALESPERSON REPORT  (null employeeId = online orders)
   ============================================================ */

db.orders.aggregate([
    { $group: { _id: "$employeeId", orders: { $sum: 1 }, revenue: { $sum: "$totalAmount" }, avgOrder: { $avg: "$totalAmount" }, biggest: { $max: "$totalAmount" } } },
    { $set: { salesperson: { $ifNull: ["$_id", "(online)"] } } },
    { $sort: { revenue: -1 } }
]);                                                       // 103: 7 / 293000, 109: 5 / 250500, 104: 6 / 72000, (online): 1 / 2500


/* ============================================================
   7. PAGINATION INSIDE A PIPELINE  and  $sample
   ============================================================ */

// Page 2 (size 4) of customers by total spent
db.orders.aggregate([
    { $group: { _id: "$customerId", spent: { $sum: "$totalAmount" } } },
    { $sort: { spent: -1, _id: 1 } },
    { $skip: 4 }, { $limit: 4 }
]);                                                       // 4: 77500, 2: 48500, 3: 30500 (only 7 customers have orders -> page 2 has 3)

// $sample: N random documents
db.products.aggregate([ { $sample: { size: 2 } }, { $project: { _id: 0, name: 1 } } ]);


/* ============================================================
   8. allowDiskUse and explain
   ============================================================ */

// Big sorts/groups need > 100 MB? Spill to disk:
db.orders.aggregate([ { $sort: { totalAmount: -1 } }, { $limit: 1 }, { $project: { _id: 1, totalAmount: 1 } } ], { allowDiskUse: true });

// See what the planner did (Level 12): $match first? index used? $sort + $limit merged?
const ex = db.orders.aggregate([ { $match: { status: "Completed" } }, { $sort: { totalAmount: -1 } }, { $limit: 3 } ]).explain("executionStats");
if (ex.stages) {
    ex.stages.map(s => Object.keys(s)[0]);                              // older servers: [ '$cursor', '$sort' ] - $match pushed into the query, $limit merged into $sort
} else {
    const wp = ex.queryPlanner.winningPlan;
    print(wp.stage, "limitAmount:", wp.limitAmount, "<-", wp.inputStage.stage);   // 8.x: SORT limitAmount: 3 <- COLLSCAN
    // The whole pipeline was handed to the query engine: the $match became the scan filter and $sort + $limit a "top-k" sort.
}


/* ============================================================
   9. PUTTING IT TOGETHER: a small "department dashboard"
   ============================================================ */

db.employees.aggregate([
    { $match: { active: true } },
    { $group: { _id: "$departmentId",
                headcount: { $sum: 1 },
                payroll: { $sum: "$salary" },
                avgSalary: { $avg: "$salary" },
                seniors: { $sum: { $cond: [ { $lt: ["$hireDate", ISODate("2023-01-01")] }, 1, 0 ] } },
                skills: { $addToSet: "$skills" } } },      // array of arrays - fixed in Level 09 with $unwind / $reduce
    { $match: { headcount: { $gte: 2 } } },
    { $project: { _id: 0, departmentId: "$_id", headcount: 1, payroll: 1, avgSalary: { $round: ["$avgSalary", 0] }, seniors: 1 } },
    { $sort: { payroll: -1 } }
]);

/* ------------------------------------------------------------
   DONE. Next: Exercises.js
   ------------------------------------------------------------ */
