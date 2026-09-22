/* ============================================================
   LEVEL 10 - DATES, STRINGS, CONDITIONALS  |  Exercises.js
   ------------------------------------------------------------
   Try each question in the "YOUR ANSWER" area FIRST.
   Then scroll down to SOLUTIONS and compare.
   Read-only except Q14 (l10_ex_dirty, dropped).
   Use asOf = 2025-12-31 as "today" where a reference date is needed.
   ============================================================ */

use("companyDB");
const asOf = ISODate("2025-12-31T00:00:00Z");

/* ------------------------------------------------------------
   QUESTIONS
   ------------------------------------------------------------
   Q1.  For each order: id and orderDate formatted as "DD-MM-YYYY".
   Q2.  Orders per weekday NAME (Mon..Sun), most orders first.
   Q3.  For every employee: name, hireDate and full years of service as of asOf.
   Q4.  Orders placed in the last 120 days before asOf (id, orderDate) - aggregation with $dateSubtract.
   Q5.  Revenue per month as "2025-01" strings (all statuses), chronological.
   Q6.  For each Pending order: a dueDate 10 days after the order and whether it
        is overdue as of asOf.
   Q7.  Customers: first name, last name, and initials (e.g. "A.S.").
   Q8.  Employees: email domain (text after @) - "(none)" when there is no email.
   Q9.  Products: name in upper case and a "priceTag" like "Rs 75,000" (thousands
        separator for values >= 1000 only - hint: $substrCP + $strLenCP on $toString).
   Q10. Employees: salaryBand "Senior" (>= 80000), "Mid" (60000-79999), "Junior".
   Q11. Orders: paymentLabel = "Paid by Card" / "Paid by UPI" / "COD - unpaid" etc.
        using $switch on payment.method and payment.paid.
   Q12. Products: price per unit of stock, rounded to 2 decimals, null when stock is 0.
   Q13. For customers 1, 6, 8: "Name <email>" where a missing/null email becomes
        "-" (must not return null).
   Q14. Create l10_ex_dirty with { v: "42" }, { v: "4.2" }, { v: "x" }, { v: null },
        { v: 7 }; convert v to double safely (bad -> null) and sum the valid ones.
   Q15. Employees hired on a weekend? (hireDate's ISO weekday 6 or 7) - names.
   ------------------------------------------------------------ */

// YOUR ANSWERS HERE (write below, run, compare)










/* ============================================================
   SOLUTIONS
   ============================================================ */

// Q1
db.orders.aggregate([ { $project: { d: { $dateToString: { date: "$orderDate", format: "%d-%m-%Y" } } } }, { $limit: 3 } ]);

// Q2
const DAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
db.orders.aggregate([
    { $group: { _id: { $isoDayOfWeek: "$orderDate" }, n: { $sum: 1 } } },
    { $project: { _id: 0, day: { $arrayElemAt: [ DAYS, { $subtract: ["$_id", 1] } ] }, n: 1 } },
    { $sort: { n: -1, day: 1 } }
]);

// Q3
db.employees.aggregate([ { $project: { _id: 0, name: 1, hireDate: 1,
    years: { $floor: { $divide: [ { $dateDiff: { startDate: "$hireDate", endDate: asOf, unit: "day" } }, 365.25 ] } } } }, { $limit: 4 } ]);
// Rahul 3, Amit 2, Priya 4, Neha 1

// Q4
db.orders.aggregate([
    { $match: { $expr: { $gte: ["$orderDate", { $dateSubtract: { startDate: asOf, unit: "day", amount: 120 } }] } } },
    { $project: { orderDate: 1 } }
]);                                                       // 1019 only (from 2025-09-02)

// Q5
db.orders.aggregate([
    { $group: { _id: { $dateToString: { date: "$orderDate", format: "%Y-%m" } }, revenue: { $sum: "$totalAmount" } } },
    { $sort: { _id: 1 } }
]);                                                       // 2025-01 110000 ... 2025-09 2500

// Q6
db.orders.aggregate([
    { $match: { status: "Pending" } },
    { $project: { orderDate: 1, dueDate: { $dateAdd: { startDate: "$orderDate", unit: "day", amount: 10 } } } },
    { $set: { overdue: { $lt: ["$dueDate", asOf] } } }
]);                                                       // both true

// Q7
db.customers.aggregate([ { $project: { _id: 0,
    firstName: { $first: { $split: ["$name", " "] } }, lastName: { $last: { $split: ["$name", " "] } },
    initials: { $concat: [ { $substrCP: ["$name", 0, 1] }, ".", { $substrCP: [ { $last: { $split: ["$name", " "] } }, 0, 1 ] }, "." ] } } }, { $limit: 3 } ]);

// Q8
db.employees.aggregate([ { $project: { _id: 0, name: 1,
    domain: { $cond: [ { $eq: [ { $type: "$email" }, "string" ] }, { $arrayElemAt: [ { $split: ["$email", "@"] }, 1 ] }, "(none)" ] } } }, { $match: { name: { $in: ["Rahul", "Anjali"] } } } ]);

// Q9
db.products.aggregate([ { $project: { _id: 0, NAME: { $toUpper: "$name" },
    priceTag: { $let: { vars: { s: { $toString: "$price" } }, in: { $cond: [
        { $gte: ["$price", 1000] },
        { $concat: [ "Rs ", { $substrCP: ["$$s", 0, { $subtract: [ { $strLenCP: "$$s" }, 3 ] }] }, ",", { $substrCP: ["$$s", { $subtract: [ { $strLenCP: "$$s" }, 3 ] }, 3] } ] },
        { $concat: [ "Rs ", "$$s" ] } ] } } } } }, { $limit: 3 } ]);
// Rs 75,000 / Rs 1,000 / Rs 2,500

// Q10
db.employees.aggregate([ { $project: { _id: 0, name: 1, salary: 1,
    salaryBand: { $switch: { branches: [ { case: { $gte: ["$salary", 80000] }, then: "Senior" }, { case: { $gte: ["$salary", 60000] }, then: "Mid" } ], default: "Junior" } } } }, { $limit: 4 } ]);

// Q11
db.orders.aggregate([ { $project: { paymentLabel: { $switch: { branches: [
    { case: { $and: [ { $eq: ["$payment.method", "COD"] }, { $not: "$payment.paid" } ] }, then: "COD - unpaid" },
    { case: "$payment.paid", then: { $concat: ["Paid by ", "$payment.method"] } } ], default: "Unpaid" } } } }, { $limit: 5 } ]);

// Q12
db.products.aggregate([ { $project: { _id: 0, name: 1,
    perUnit: { $cond: [ { $eq: ["$stock", 0] }, null, { $round: [ { $divide: ["$price", "$stock"] }, 2 ] } ] } } }, { $match: { name: { $in: ["Laptop", "Headphones"] } } } ]);   // 7500, null

// Q13
db.customers.aggregate([ { $match: { _id: { $in: [1, 6, 8] } } }, { $project: { _id: 0, label: { $concat: ["$name", " <", { $ifNull: ["$email", "-"] }, ">"] } } } ]);

// Q14
db.l10_ex_dirty.drop();
db.l10_ex_dirty.insertMany([ { v: "42" }, { v: "4.2" }, { v: "x" }, { v: null }, { v: 7 } ]);
db.l10_ex_dirty.aggregate([
    { $project: { n: { $convert: { input: "$v", to: "double", onError: null, onNull: null } } } },
    { $group: { _id: null, sum: { $sum: "$n" }, valid: { $sum: { $cond: [ { $eq: ["$n", null] }, 0, 1 ] } } } }
]);                                                       // sum 53.2, valid 3
db.l10_ex_dirty.drop();

// Q15
db.employees.aggregate([ { $match: { $expr: { $gte: [ { $isoDayOfWeek: "$hireDate" }, 6 ] } } }, { $project: { _id: 0, name: 1, hireDate: 1 } } ]);
// [] - nobody in this dataset was hired on a weekend (e.g. Sneha's 2020-05-18 was a Monday). Change 6 to 5 to see the Friday hires.
