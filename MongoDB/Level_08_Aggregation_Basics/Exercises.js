/* ============================================================
   LEVEL 08 - AGGREGATION BASICS  |  Exercises.js
   ------------------------------------------------------------
   Try each question in the "YOUR ANSWER" area FIRST.
   Then scroll down to SOLUTIONS and compare.
   All questions use companyDB (read-only).
   ============================================================ */

use("companyDB");

/* ------------------------------------------------------------
   QUESTIONS
   ------------------------------------------------------------
   Q1.  Number of employees and total payroll per department, sorted by payroll desc.
   Q2.  Average price per product category, rounded to 2 decimals, highest first.
   Q3.  Number of orders and revenue per customer, only customers with 2+ orders.
   Q4.  The 3 most expensive orders (id, totalAmount) using a pipeline.
   Q5.  Revenue per payment method for Completed orders only.
   Q6.  For each employee: name, city and annual salary (salary * 12) - no _id.
   Q7.  How many distinct skills exist across all employees? (Hint: arrays group
        as a whole - for now use $addToSet on "$skills" then think about it;
        the real answer needs $unwind - Level 09. Give the count of distinct
        skill ARRAYS instead, then the correct number by another route.)
   Q8.  Employees hired per year (year, count), oldest year first.
   Q9.  Per department: the highest-paid employee's name and salary.
   Q10. Per customer: count of Completed vs Pending vs Cancelled orders in ONE
        document each (conditional aggregation).
   Q11. Highest, lowest and average totalAmount over all orders in one document.
   Q12. Products grouped by category with the list of product names and the
        total stock, only categories whose total stock is above 100.
   Q13. The second highest DISTINCT product price.
   Q14. Count how many orders each status has using $sortByCount, then the same
        with $group + $sort.
   Q15. Percentage of employees per city (city, n, pct) - pct rounded to 1 decimal.
   ------------------------------------------------------------ */

// YOUR ANSWERS HERE (write below, run, compare)










/* ============================================================
   SOLUTIONS
   ============================================================ */

// Q1
db.employees.aggregate([
    { $group: { _id: "$departmentId", employees: { $sum: 1 }, payroll: { $sum: "$salary" } } },
    { $sort: { payroll: -1 } }
]);                                                       // 1: 215000, 2: 192000, 4: 162000, 5: 128000, 3: 60000, null: 48000

// Q2
db.products.aggregate([
    { $group: { _id: "$category", avgPrice: { $avg: "$price" } } },
    { $project: { avgPrice: { $round: ["$avgPrice", 2] } } },
    { $sort: { avgPrice: -1 } }
]);                                                       // Electronics 18500, Furniture 11666.67, Stationery 30

// Q3
db.orders.aggregate([
    { $group: { _id: "$customerId", orders: { $sum: 1 }, revenue: { $sum: "$totalAmount" } } },
    { $match: { orders: { $gte: 2 } } },
    { $sort: { _id: 1 } }
]);                                                       // all 7 ordering customers (each has >= 2)

// Q4
db.orders.aggregate([ { $sort: { totalAmount: -1 } }, { $limit: 3 }, { $project: { totalAmount: 1 } } ]);   // 1014, 1008, 1001/1018 (tie 75000)

// Q5
db.orders.aggregate([
    { $match: { status: "Completed" } },
    { $group: { _id: "$payment.method", revenue: { $sum: "$totalAmount" } } },
    { $sort: { revenue: -1 } }
]);                                                       // Card 495500, UPI 57500, COD 21000

// Q6
db.employees.aggregate([ { $project: { _id: 0, name: 1, city: "$address.city", annual: { $multiply: ["$salary", 12] } } } ]);

// Q7
db.employees.aggregate([ { $group: { _id: null, arrays: { $addToSet: "$skills" } } }, { $project: { n: { $size: "$arrays" } } } ]);   // 11 distinct arrays (not what we want)
db.employees.distinct("skills").length;                   // 16 - the real number (distinct flattens arrays); Level 09: $unwind + $group
db.employees.aggregate([ { $group: { _id: null, all: { $push: "$skills" } } },
    { $project: { n: { $size: { $setUnion: { $reduce: { input: "$all", initialValue: [], in: { $concatArrays: ["$$value", { $ifNull: ["$$this", []] }] } } } } } } } ]);   // 16

// Q8
db.employees.aggregate([ { $group: { _id: { $year: "$hireDate" }, hired: { $sum: 1 } } }, { $sort: { _id: 1 } } ]);

// Q9
db.employees.aggregate([
    { $sort: { salary: -1 } },
    { $group: { _id: "$departmentId", name: { $first: "$name" }, salary: { $first: "$salary" } } },
    { $sort: { _id: 1 } }
]);

// Q10
db.orders.aggregate([
    { $group: { _id: "$customerId",
        completed: { $sum: { $cond: [ { $eq: ["$status", "Completed"] }, 1, 0 ] } },
        pending:   { $sum: { $cond: [ { $eq: ["$status", "Pending"] }, 1, 0 ] } },
        cancelled: { $sum: { $cond: [ { $eq: ["$status", "Cancelled"] }, 1, 0 ] } } } },
    { $sort: { _id: 1 } }
]);

// Q11
db.orders.aggregate([ { $group: { _id: null, max: { $max: "$totalAmount" }, min: { $min: "$totalAmount" }, avg: { $avg: "$totalAmount" } } } ]);   // 150000, 1500, 32526.32

// Q12
db.products.aggregate([
    { $group: { _id: "$category", names: { $push: "$name" }, stock: { $sum: "$stock" } } },
    { $match: { stock: { $gt: 100 } } }
]);                                                       // Electronics 215, Stationery 1500

// Q13
db.products.aggregate([ { $group: { _id: "$price" } }, { $sort: { _id: -1 } }, { $skip: 1 }, { $limit: 1 } ]);   // 25000

// Q14
db.orders.aggregate([ { $sortByCount: "$status" } ]);
db.orders.aggregate([ { $group: { _id: "$status", count: { $sum: 1 } } }, { $sort: { count: -1 } } ]);

// Q15
db.employees.aggregate([
    { $group: { _id: "$address.city", n: { $sum: 1 } } },
    { $group: { _id: null, total: { $sum: "$n" }, rows: { $push: { city: "$_id", n: "$n" } } } },
    { $unwind: "$rows" },
    { $project: { _id: 0, city: "$rows.city", n: "$rows.n", pct: { $round: [ { $multiply: [ { $divide: ["$rows.n", "$total"] }, 100 ] }, 1 ] } } },
    { $sort: { n: -1, city: 1 } }
]);                                                       // Delhi 4 33.3, Mumbai 3 25, Bangalore 2 16.7, Pune 2 16.7, Noida 1 8.3
