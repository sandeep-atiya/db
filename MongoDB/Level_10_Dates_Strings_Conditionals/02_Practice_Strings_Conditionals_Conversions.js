/* ============================================================
   LEVEL 10  |  02_Practice_Strings_Conditionals_Conversions.js
   ------------------------------------------------------------
   Topics : string operators, regex extraction, null-safe concat,
            $cond / $switch / $ifNull, comparisons & logic,
            $let, $convert / $toX (TRY_CAST), math & rounding,
            divide-by-zero guard, cleaning dirty data with a
            pipeline update

   HOW TO PRACTICE: block by block, predict first.
   Creates l10_dirty (dropped in CLEANUP).
   ============================================================ */

use("companyDB");


/* ============================================================
   1. STRING BASICS
   ============================================================ */

db.customers.aggregate([ { $match: { _id: 1 } }, { $project: { _id: 0, name: 1,
    upper: { $toUpper: "$name" }, lower: { $toLower: "$name" },
    len: { $strLenCP: "$name" },                                                 // 12
    first5: { $substrCP: ["$name", 0, 5] },                                      // Aarav
    firstName: { $first: { $split: ["$name", " "] } },
    lastName:  { $last:  { $split: ["$name", " "] } },
    initials: { $concat: [ { $substrCP: ["$name", 0, 1] }, { $substrCP: [ { $last: { $split: ["$name", " "] } }, 0, 1 ] } ] },   // AS
    posOfSpace: { $indexOfCP: ["$name", " "] },                                  // 5
    posMissing: { $indexOfCP: ["$name", "zzz"] },                                // -1
    label: { $concat: ["$name", " <", "$email", ">"] } } } ]);

// Trim
db.l10_dirty.drop();
db.l10_dirty.insertMany([
    { _id: 1, name: "  Rahul  ", price: "1200",  qty: 5,    email: "RAHUL@Example.com", phone: "98450-000-00", flag: "true" },
    { _id: 2, name: "--Amit--", price: "1,250",  qty: "7",  email: "amit@example.com",  phone: "080 2222 0000", flag: "false" },
    { _id: 3, name: "Priya",    price: 999.5,    qty: null, email: null,                phone: null,            flag: "yes" },
    { _id: 4, name: "Neha",     price: "abc",    qty: "x",  email: "neha@example.com",  phone: "",              flag: 0 },
    { _id: 5, name: "Ravi",     price: null }
]);
db.l10_dirty.aggregate([ { $project: { name: 1,
    trimmed: { $trim: { input: "$name" } },                                       // "Rahul"
    dashes:  { $trim: { input: "$name", chars: "-" } },                           // "Amit"
    left:    { $ltrim: { input: "$name" } }, right: { $rtrim: { input: "$name" } } } } ]);

// Title case (first letter upper, rest lower) and padding a number to 5 digits
db.employees.aggregate([ { $match: { _id: { $in: [101, 106] } } }, { $project: { _id: 1,
    shout: { $toUpper: "$name" },
    title: { $concat: [ { $toUpper: { $substrCP: ["$name", 0, 1] } }, { $toLower: { $substrCP: ["$name", 1, { $strLenCP: "$name" }] } } ] },
    code:  { $concat: [ "EMP-", { $substrCP: [ "00000", 0, { $subtract: [5, { $strLenCP: { $toString: "$_id" } }] } ] }, { $toString: "$_id" } ] } } } ]);
// code EMP-00101, EMP-00106


/* ============================================================
   2. $concat AND NULL  (the trap)
   ============================================================ */

db.customers.aggregate([ { $match: { _id: { $in: [1, 6, 8] } } }, { $project: { _id: 0, name: 1,
    naive: { $concat: ["$name", " <", "$email", ">"] },                          // null for Farhan (email null) AND Hina (missing)
    safe:  { $concat: ["$name", " <", { $ifNull: ["$email", "no email"] }, ">"] } } } ]);


/* ============================================================
   3. REPLACE, SPLIT, REGEX
   ============================================================ */

db.l10_dirty.aggregate([ { $match: { phone: { $type: "string" } } }, { $project: { phone: 1,
    digitsOnly: { $replaceAll: { input: { $replaceAll: { input: "$phone", find: "-", replacement: "" } }, find: " ", replacement: "" } },
    firstDash:  { $replaceOne: { input: "$phone", find: "-", replacement: "/" } },
    parts: { $split: ["$phone", "-"] } } } ]);

// Regex: match / extract / extract all
db.customers.aggregate([ { $match: { email: { $type: "string" } } }, { $project: { _id: 0, email: 1,
    isExample: { $regexMatch: { input: "$email", regex: /@example\.com$/ } },
    domain:    { $let: { vars: { m: { $regexFind: { input: "$email", regex: /@(.+)$/ } } }, in: { $arrayElemAt: ["$$m.captures", 0] } } },
    domain2:   { $arrayElemAt: [ { $split: ["$email", "@"] }, 1 ] },
    vowels:    { $size: { $regexFindAll: { input: "$email", regex: /[aeiou]/ } } } } }, { $limit: 3 } ]);

// Case-insensitive comparison / search in expressions
db.l10_dirty.aggregate([ { $match: { email: { $type: "string" } } }, { $project: { email: 1,
    sameAsRahul: { $eq: [ { $strcasecmp: ["$email", "rahul@example.com"] }, 0 ] },
    hasExample:  { $regexMatch: { input: "$email", regex: "example", options: "i" } } } } ]);

// Mask an email: r****@example.com
db.customers.aggregate([ { $match: { email: { $type: "string" } } }, { $project: { _id: 0,
    masked: { $concat: [ { $substrCP: ["$email", 0, 1] }, "****", { $substrCP: [ "$email", { $indexOfCP: ["$email", "@"] }, 100 ] } ] } } }, { $limit: 2 } ]);


/* ============================================================
   4. CONDITIONALS: $cond, $switch, $ifNull
   ============================================================ */

db.employees.aggregate([ { $project: { _id: 0, name: 1, salary: 1,
    band2: { $cond: [ { $gte: ["$salary", 70000] }, "HIGH", "NORMAL" ] },                        // array form
    band2b: { $cond: { if: { $gte: ["$salary", 70000] }, then: "HIGH", else: "NORMAL" } },       // object form
    band3: { $switch: { branches: [
                { case: { $gte: ["$salary", 80000] }, then: "A" },
                { case: { $gte: ["$salary", 60000] }, then: "B" } ], default: "C" } },
    contact: { $ifNull: ["$email", "$phone", "(no contact)"] },                                  // multi-arg (5.0+)
    dept: { $ifNull: ["$departmentId", "unassigned"] },                                          // Anjali: null -> unassigned
    nSkills: { $size: { $ifNull: ["$skills", []] } } } }, { $limit: 4 } ]);

// Nested $cond and comparisons on several fields
db.products.aggregate([ { $project: { _id: 0, name: 1, stock: 1, price: 1,
    availability: { $switch: { branches: [
        { case: { $eq: ["$stock", 0] }, then: "out of stock" },
        { case: { $lte: ["$stock", 10] }, then: "low" },
        { case: { $and: [ { $gt: ["$stock", 10] }, { $lt: ["$price", 5000] } ] }, then: "plenty & cheap" } ], default: "ok" } } } } ]);

// $cond inside $group (conditional aggregation) and inside $sum for weighted counts
db.orders.aggregate([ { $group: { _id: null,
    paidCount: { $sum: { $cond: ["$payment.paid", 1, 0] } },                                    // a boolean field is a valid condition
    unpaidAmount: { $sum: { $cond: [ { $not: "$payment.paid" }, "$totalAmount", 0 ] } } } } ]);   // 16, 44000

// Missing vs null in EXPRESSIONS (different from query filters, where { email: null } matches both!)
db.employees.aggregate([ { $match: { _id: { $in: [101, 110] } } }, { $project: { _id: 0, name: 1,
    eqNull: { $eq: ["$email", null] },                   // Anjali (missing) -> FALSE  (only an explicit null is $eq null)
    lteNull: { $lte: ["$email", null] },                 // Anjali -> true  (missing sorts BELOW null: $cmp gives -1)
    viaIfNull: { $eq: [ { $ifNull: ["$email", null] }, null ] },   // true - $ifNull turns missing into null
    emailType: { $type: "$email" },                       // "string" / "missing"
    hasEmail: { $ne: [ { $type: "$email" }, "missing" ] } } } ]);
db.customers.aggregate([ { $match: { _id: 6 } }, { $project: { _id: 0, name: 1, eqNull: { $eq: ["$email", null] }, type: { $type: "$email" } } } ]);   // Farhan: explicit null -> true


/* ============================================================
   5. $let  -  local variables to avoid repeating expressions
   ============================================================ */

db.orders.aggregate([ { $match: { _id: 1008 } }, { $project: { _id: 1,
    summary: { $let: {
        vars: { lines: { $size: "$items" }, units: { $sum: "$items.qty" } },
        in: { $concat: [ { $toString: "$$lines" }, " lines, ", { $toString: "$$units" }, " units, avg ", { $toString: { $round: [ { $divide: ["$totalAmount", "$$units"] }, 0 ] } } ] } } } } } ]);
// "3 lines, 3 units, avg 26167"


/* ============================================================
   6. CONVERSIONS: $convert (TRY_CAST) vs $toX (CAST)
   ============================================================ */

db.l10_dirty.aggregate([ { $project: { price: 1, qty: 1, flag: 1,
    priceNum: { $convert: { input: "$price", to: "double", onError: "ERR", onNull: "NULL" } },   // 1200, ERR ("1,250"), 999.5, ERR ("abc"), NULL
    qtyInt:   { $convert: { input: "$qty", to: "int", onError: -1, onNull: 0 } },              // 5, 7, 0, -1, 0
    flagBool: { $convert: { input: "$flag", to: "bool", onNull: false } } } } ]);              // "false" -> TRUE (!), 0 -> false
// $toBool: any non-empty string is true. Compare explicitly: { $in: [{ $toLower: "$flag" }, ["true", "yes", "1"]] }

// Strict $toX throws on the first bad value
try {
    db.l10_dirty.aggregate([ { $project: { p: { $toDouble: "$price" } } } ]).toArray();
} catch (e) {
    print("EXPECTED ERROR:", e.message.substring(0, 60));
}

// Fix "1,250" before converting; $toInt of a double truncates; $toInt of "12.5" fails
db.l10_dirty.aggregate([ { $match: { _id: 2 } }, { $project: { _id: 0,
    fixed: { $toDouble: { $replaceAll: { input: "$price", find: ",", replacement: "" } } } } } ]);   // 1250
db.l10_dirty.aggregate([ { $limit: 1 }, { $project: { _id: 0,
    truncated: { $toInt: 12.9 }, rounded: { $round: [12.9, 0] },
    str: { $toString: 12.5 }, dec: { $toDecimal: "19.99" }, long: { $toLong: "9007199254740993" },
    oid: { $toObjectId: "65a0000000000000abcdef12" },
    bad: { $convert: { input: "12.5", to: "int", onError: "not an int string" } } } } ]);

// The type of each value ($type expression) - schema exploration of the dirty collection
db.l10_dirty.aggregate([ { $project: { price: { $type: "$price" }, qty: { $type: "$qty" }, email: { $type: "$email" } } } ]);


/* ============================================================
   7. MATH AND ROUNDING
   ============================================================ */

db.products.aggregate([ { $match: { _id: { $in: [1, 7, 9] } } }, { $project: { _id: 0, name: 1, price: 1, stock: 1,
    withTax: { $round: [ { $multiply: ["$price", 1.18] }, 2 ] },
    perUnitOfStock: { $cond: [ { $eq: ["$stock", 0] }, null, { $round: [ { $divide: ["$price", "$stock"] }, 2 ] } ] },   // divide-by-zero guard
    mod: { $mod: ["$price", 1000] }, pow: { $pow: [2, 10] }, sqrt: { $sqrt: 144 },
    abs: { $abs: -5 }, ceil: { $ceil: 4.1 }, floor: { $floor: 4.9 }, trunc: { $trunc: [4.987, 2] } } } ]);

// Division by zero is an ERROR without the guard
try {
    db.products.aggregate([ { $match: { _id: 9 } }, { $project: { x: { $divide: ["$price", "$stock"] } } } ]).toArray();
} catch (e) {
    print("EXPECTED ERROR:", e.message.substring(0, 50));
}

// $round on doubles = "round half to even"
db.products.aggregate([ { $limit: 1 }, { $project: { _id: 0, a: { $round: [2.5, 0] }, b: { $round: [3.5, 0] }, c: { $round: [2.567, 2] }, d: { $round: [NumberDecimal("2.5"), 0] } } } ]);   // 2, 4, 2.57, 2

// Percent with 1 decimal: share of payroll
db.employees.aggregate([
    { $group: { _id: null, total: { $sum: "$salary" }, rows: { $push: { name: "$name", salary: "$salary" } } } },
    { $unwind: "$rows" },
    { $project: { _id: 0, name: "$rows.name", pct: { $round: [ { $multiply: [ { $divide: ["$rows.salary", "$total"] }, 100 ] }, 1 ] } } },
    { $sort: { pct: -1 } }, { $limit: 3 }
]);                                                       // Sneha 11.2, Rahul 10.6, Priya 9.3


/* ============================================================
   8. CLEANING DIRTY DATA WITH A PIPELINE UPDATE  (fix types in place)
   ============================================================ */

db.l10_dirty.updateMany({}, [ { $set: {
    name:  { $trim: { input: { $trim: { input: "$name" } }, chars: "-" } },
    price: { $convert: { input: { $cond: [ { $eq: [ { $type: "$price" }, "string" ] }, { $replaceAll: { input: "$price", find: ",", replacement: "" } }, "$price" ] }, to: "double", onError: null, onNull: null } },
    qty:   { $convert: { input: "$qty", to: "int", onError: null, onNull: null } },
    email: { $cond: [ { $eq: [ { $type: "$email" }, "string" ] }, { $toLower: "$email" }, null ] },
    flag:  { $in: [ { $toLower: { $toString: { $ifNull: ["$flag", ""] } } }, ["true", "yes", "1"] ] }
} } ]);
db.l10_dirty.find();
// name trimmed, price: 1200 / 1250 / 999.5 / null / null, qty: 5 / 7 / null / null / null, email lower-cased, flag true/false/true/false/false

// Now numeric comparisons work
db.l10_dirty.find({ price: { $gte: 1000 } }, { name: 1, price: 1 });   // Rahul, Amit


/* ============================================================
   CLEANUP
   ============================================================ */
db.l10_dirty.drop();

/* ------------------------------------------------------------
   DONE. Next: Exercises.js
   ------------------------------------------------------------ */
