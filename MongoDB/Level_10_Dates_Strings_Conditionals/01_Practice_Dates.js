/* ============================================================
   LEVEL 10 - DATES, STRINGS, CONDITIONALS  |  01_Practice_Dates.js
   ------------------------------------------------------------
   Topics : date parts, $dateToString (formats, timezone),
            $dateFromString, $dateAdd / $dateSubtract / $dateDiff,
            $dateTrunc, $dateToParts / $dateFromParts, $$NOW,
            $toDate, month / weekday names, grouping by period,
            date arithmetic, comparisons

   HOW TO PRACTICE: block by block, predict first. Read-only.
   A fixed reference date (asOf = 2025-12-31) keeps results stable.
   ============================================================ */

use("companyDB");
const asOf = ISODate("2025-12-31T00:00:00Z");


/* ============================================================
   1. DATE PARTS
   ============================================================ */

db.orders.aggregate([ { $match: { _id: 1008 } }, { $project: { _id: 0, orderDate: 1,
    year: { $year: "$orderDate" }, month: { $month: "$orderDate" }, day: { $dayOfMonth: "$orderDate" },
    dow: { $dayOfWeek: "$orderDate" },                     // 1 = Sunday ... 7 = Saturday  -> 3 (Tuesday, 18 Mar 2025)
    isoDow: { $isoDayOfWeek: "$orderDate" },               // 1 = Monday ... 7 = Sunday    -> 2
    doy: { $dayOfYear: "$orderDate" },                     // 77
    week: { $week: "$orderDate" }, isoWeek: { $isoWeek: "$orderDate" }, isoYear: { $isoWeekYear: "$orderDate" },
    hour: { $hour: "$orderDate" } } } ]);

// All parts at once
db.orders.aggregate([ { $match: { _id: 1008 } }, { $project: { _id: 0, parts: { $dateToParts: { date: "$orderDate" } } } } ]);
// { year: 2025, month: 3, day: 18, hour: 0, minute: 0, second: 0, millisecond: 0 }


/* ============================================================
   2. TIME ZONES  (stored UTC -> shown local)
   ============================================================ */

// 2025-01-31 20:00 UTC is already 1 Feb 01:30 in India
db.l10_tz.drop();
db.l10_tz.insertOne({ _id: 1, at: ISODate("2025-01-31T20:00:00Z") });
db.l10_tz.aggregate([ { $project: { _id: 0,
    utcMonth: { $month: "$at" },
    indiaMonth: { $month: { date: "$at", timezone: "Asia/Kolkata" } },                 // 2
    india: { $dateToString: { date: "$at", format: "%Y-%m-%d %H:%M", timezone: "Asia/Kolkata" } },   // 2025-02-01 01:30
    newYork: { $dateToString: { date: "$at", format: "%Y-%m-%d %H:%M %z", timezone: "America/New_York" } },
    offsetForm: { $dateToString: { date: "$at", format: "%H:%M", timezone: "+05:30" } } } } ]);


/* ============================================================
   3. FORMATTING: $dateToString
   ============================================================ */

db.orders.aggregate([ { $match: { _id: { $in: [1001, 1019] } } }, { $project: { _id: 1,
    iso:   { $dateToString: { date: "$orderDate", format: "%Y-%m-%d" } },
    dmy:   { $dateToString: { date: "$orderDate", format: "%d/%m/%Y" } },
    ym:    { $dateToString: { date: "$orderDate", format: "%Y-%m" } },
    full:  { $dateToString: { date: "$orderDate", format: "%Y-%m-%dT%H:%M:%S.%LZ" } },
    doyWk: { $dateToString: { date: "$orderDate", format: "day %j, ISO week %V of %G, weekday %u" } },
    pct:   { $dateToString: { date: "$orderDate", format: "100%%" } },
    missing: { $dateToString: { date: "$deliveredAt", format: "%Y-%m-%d", onNull: "not delivered" } } } } ]);

// Month / weekday NAMES are not built in -> look them up in an array
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
db.orders.aggregate([ { $match: { _id: { $in: [1001, 1008] } } }, { $project: { _id: 1,
    monthName: { $arrayElemAt: [ MONTHS, { $subtract: [ { $month: "$orderDate" }, 1 ] } ] },
    dayName:   { $arrayElemAt: [ DAYS,   { $subtract: [ { $dayOfWeek: "$orderDate" }, 1 ] } ] },
    quarter:   { $concat: [ "Q", { $toString: { $ceil: { $divide: [ { $month: "$orderDate" }, 3 ] } } } ] } } } ]);
// 1001: Jan, Sun, Q1 ; 1008: Mar, Tue, Q1


/* ============================================================
   4. PARSING: $dateFromString  (TRY_CONVERT)
   ============================================================ */

db.l10_tz.drop();
db.l10_tz.insertMany([
    { _id: 1, s: "2025-03-18" }, { _id: 2, s: "18/03/2025" }, { _id: 3, s: "2025-03-18T10:30:00+05:30" },
    { _id: 4, s: "not a date" }, { _id: 5, s: null }, { _id: 6 }
]);
db.l10_tz.aggregate([ { $project: { s: 1,
    parsed: { $dateFromString: { dateString: "$s", onError: "BAD", onNull: "NULL" } },                    // ISO strings parse; 18/03/2025 -> BAD
    dmy:    { $dateFromString: { dateString: "$s", format: "%d/%m/%Y", timezone: "Asia/Kolkata", onError: null, onNull: null } }   // only _id 2 parses (midnight IST = 18:30Z previous day)
} } ]);

// Without onError the pipeline FAILS on the first bad string
try {
    db.l10_tz.aggregate([ { $project: { d: { $dateFromString: { dateString: "$s" } } } } ]).toArray();
} catch (e) {
    print("EXPECTED ERROR:", e.message.substring(0, 70));
}

// $toDate: from string, from milliseconds, from an ObjectId (its embedded timestamp)
db.l10_tz.aggregate([ { $match: { _id: 1 } }, { $project: { _id: 0,
    fromString: { $toDate: "$s" }, fromMs: { $toDate: 1736035200000 }, fromOid: { $toDate: ObjectId("65a0000000000000abcdef12") } } } ]);
// fromMs 2025-01-05, fromOid 2024-01-11 (ObjectId's first 4 bytes = seconds since 1970)


/* ============================================================
   5. ARITHMETIC: $dateAdd, $dateSubtract, $dateDiff, $subtract
   ============================================================ */

db.orders.aggregate([ { $match: { _id: 1001 } }, { $project: { _id: 1, orderDate: 1,
    plus7d:    { $dateAdd: { startDate: "$orderDate", unit: "day", amount: 7 } },            // 2025-01-12
    plus1m:    { $dateAdd: { startDate: "$orderDate", unit: "month", amount: 1 } },          // 2025-02-05
    minus1q:   { $dateSubtract: { startDate: "$orderDate", unit: "quarter", amount: 1 } },   // 2024-10-05
    daysToRef: { $dateDiff: { startDate: "$orderDate", endDate: asOf, unit: "day" } },       // 360
    monthsToRef: { $dateDiff: { startDate: "$orderDate", endDate: asOf, unit: "month" } },   // 11
    msDiff:    { $subtract: [ asOf, "$orderDate" ] },                                        // milliseconds (a number)
    plus1hMs:  { $add: [ "$orderDate", 3600000 ] } } } ]);                                    // date + ms = date

// $dateDiff counts BOUNDARIES crossed, not full periods:
db.l10_tz.aggregate([ { $limit: 1 }, { $project: { _id: 0,
    yearsBoundary: { $dateDiff: { startDate: ISODate("2024-12-31"), endDate: ISODate("2025-01-01"), unit: "year" } },   // 1 (!)
    daysBoundary:  { $dateDiff: { startDate: ISODate("2024-12-31"), endDate: ISODate("2025-01-01"), unit: "day" } } } } ]);   // 1

// Tenure in FULL years as of the reference date (floor of days / 365.25)
db.employees.aggregate([ { $project: { _id: 0, name: 1, hireDate: 1,
    yearsBoundary: { $dateDiff: { startDate: "$hireDate", endDate: asOf, unit: "year" } },
    fullYears: { $floor: { $divide: [ { $dateDiff: { startDate: "$hireDate", endDate: asOf, unit: "day" } }, 365.25 ] } } } },
    { $sort: { hireDate: 1 } }, { $limit: 3 } ]);
// Sneha 2020-05-18: boundary 5, full 5 ; Deepak 2021-03-03: 4 / 4 ; Priya 2021-07-20: 4 / 4

// Weeks with a chosen start day
db.orders.aggregate([ { $match: { _id: 1001 } }, { $project: { _id: 0,
    weeksMon: { $dateDiff: { startDate: "$orderDate", endDate: asOf, unit: "week", startOfWeek: "monday" } } } } ]);


/* ============================================================
   6. $dateTrunc  -  start of period, bins
   ============================================================ */

db.orders.aggregate([ { $match: { _id: 1008 } }, { $project: { _id: 0, orderDate: 1,
    month: { $dateTrunc: { date: "$orderDate", unit: "month" } },                                 // 2025-03-01
    weekMon: { $dateTrunc: { date: "$orderDate", unit: "week", startOfWeek: "monday" } },        // 2025-03-17
    quarter: { $dateTrunc: { date: "$orderDate", unit: "quarter" } },                             // 2025-01-01
    tenDayBin: { $dateTrunc: { date: "$orderDate", unit: "day", binSize: 10 } } } } ]);

// Revenue per QUARTER (all statuses)
db.orders.aggregate([
    { $group: { _id: { $dateTrunc: { date: "$orderDate", unit: "quarter" } }, orders: { $sum: 1 }, revenue: { $sum: "$totalAmount" } } },
    { $sort: { _id: 1 } },
    { $project: { _id: 0, quarter: { $dateToString: { date: "$_id", format: "%Y-%m" } }, orders: 1, revenue: 1 } }
]);                                                       // Q1 267500 (8), Q2 227000 (6), Q3 123500 (5)

// Orders per ISO week number (which weeks were busy?)
db.orders.aggregate([ { $group: { _id: { $isoWeek: "$orderDate" }, n: { $sum: 1 } } }, { $match: { n: { $gt: 1 } } }, { $sort: { _id: 1 } } ]);


/* ============================================================
   7. $dateFromParts  and  building dates in queries
   ============================================================ */

db.l10_tz.aggregate([ { $limit: 1 }, { $project: { _id: 0,
    d1: { $dateFromParts: { year: 2025, month: 1, day: 5 } },                                     // 2025-01-05T00:00Z
    d2: { $dateFromParts: { year: 2025, month: 1, day: 5, hour: 9, minute: 30, timezone: "Asia/Kolkata" } },   // 04:00Z
    d3: { $dateFromParts: { year: 2025, month: 13, day: 1 } },                                    // overflow rolls over -> 2026-01-01
    iso: { $dateFromParts: { isoWeekYear: 2025, isoWeek: 12, isoDayOfWeek: 2 } } } } ]);         // Tue of ISO week 12 = 2025-03-18

// "First day of the month of each order" (two ways)
db.orders.aggregate([ { $match: { _id: 1008 } }, { $project: { _id: 0,
    a: { $dateTrunc: { date: "$orderDate", unit: "month" } },
    b: { $dateFromParts: { year: { $year: "$orderDate" }, month: { $month: "$orderDate" }, day: 1 } } } } ]);


/* ============================================================
   8. $$NOW and RELATIVE FILTERS
   ============================================================ */

// $$NOW is evaluated once per pipeline (same value for all documents)
db.orders.aggregate([ { $limit: 2 }, { $project: { _id: 1, now: "$$NOW", ageDays: { $dateDiff: { startDate: "$orderDate", endDate: "$$NOW", unit: "day" } } } } ]);

// "Orders in the 90 days before the reference date" - in find() compute the boundary in JS ...
const from = new Date(asOf.getTime() - 90 * 24 * 3600 * 1000);
db.orders.find({ orderDate: { $gte: from, $lt: asOf } }, { _id: 1, orderDate: 1 });     // nothing: 2025-12-31 minus 90 days = 2025-10-02 and the last order is 2025-09-05
// Use 150 days instead:
db.orders.find({ orderDate: { $gte: new Date(asOf.getTime() - 150 * 86400000), $lt: asOf } }, { _id: 1 });   // 1017, 1018, 1019

// ... or in an aggregation with $expr + $dateSubtract (relative to $$NOW in real life)
db.orders.aggregate([
    { $match: { $expr: { $gte: [ "$orderDate", { $dateSubtract: { startDate: asOf, unit: "day", amount: 150 } } ] } } },
    { $project: { _id: 1, orderDate: 1 } }
]);

// Employees hired in the same month (any year) as someone else -> group by month number
db.employees.aggregate([ { $group: { _id: { $month: "$hireDate" }, names: { $push: "$name" }, n: { $sum: 1 } } }, { $match: { n: { $gt: 1 } } }, { $sort: { _id: 1 } } ]);
// Jan: Rahul, Meera ; Mar: Amit, Deepak ; May: Sneha, Anjali


/* ============================================================
   9. DATES IN UPDATES (pipeline update with $$NOW and date math)
   ============================================================ */

db.orders.aggregate([ { $match: { status: "Pending" } }, { $out: "l10_pending" } ]);
db.l10_pending.updateMany({}, [ { $set: {
    dueDate: { $dateAdd: { startDate: "$orderDate", unit: "day", amount: 14 } },
    overdue: { $lt: [ { $dateAdd: { startDate: "$orderDate", unit: "day", amount: 14 } }, asOf ] },
    checkedAt: "$$NOW" } } ]);
db.l10_pending.find({}, { _id: 1, orderDate: 1, dueDate: 1, overdue: 1 });                 // both overdue: true


/* ============================================================
   CLEANUP
   ============================================================ */
db.l10_tz.drop(); db.l10_pending.drop();

/* ------------------------------------------------------------
   DONE. Next: 02_Practice_Strings_Conditionals_Conversions.js
   ------------------------------------------------------------ */
