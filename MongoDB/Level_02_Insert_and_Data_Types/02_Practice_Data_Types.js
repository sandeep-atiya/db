/* ============================================================
   LEVEL 02 - INSERT & DATA TYPES  |  02_Practice_Data_Types.js
   ------------------------------------------------------------
   Topics : every BSON type, $type, number types (double / int /
            long / decimal), dates (UTC), null vs missing,
            embedded-document equality, type comparison order

   HOW TO PRACTICE: block by block, predict first.
   Works in companyDB.l02_types (dropped at the end).
   ============================================================ */

use("companyDB");
db.l02_types.drop();


/* ============================================================
   1. ONE DOCUMENT WITH EVERY COMMON TYPE
   ============================================================ */

db.l02_types.insertOne({
    _id: 1,
    aNumber:   85000,                            // whole JS number that fits in 32 bits -> BSON int
    aDouble:   85000.5,                          // fraction -> BSON double (so is 3000000000: too big for int32)
    anInt:     NumberInt(85000),                 // 32-bit integer, explicitly
    aLong:     NumberLong("9007199254740993"),   // 64-bit integer (pass a STRING for big values)
    aDecimal:  NumberDecimal("19.99"),           // Decimal128 - money
    aString:   "Rahul",
    aBool:     true,
    aNull:     null,
    aDate:     ISODate("2025-01-05T10:30:00Z"),  // UTC
    anArray:   [1, "two", { three: 3 }],
    anObject:  { city: "Delhi", pincode: 110001 },
    anObjectId: ObjectId(),
    aRegex:    /^ra/i,
    aBinary:   UUID(),                           // BinData subtype 4
    aTimestamp: Timestamp(),                     // internal type (oplog) - not for app dates
    aMinKey:   MinKey(),
    aMaxKey:   MaxKey()
});
db.l02_types.findOne();

// Ask the server for the type NAME of each field ($type as an aggregation operator)
db.l02_types.aggregate([{ $project: {
    aNumber: { $type: "$aNumber" }, aDouble: { $type: "$aDouble" }, anInt: { $type: "$anInt" }, aLong: { $type: "$aLong" },
    aDecimal: { $type: "$aDecimal" }, aString: { $type: "$aString" }, aBool: { $type: "$aBool" },
    aNull: { $type: "$aNull" }, aDate: { $type: "$aDate" }, anArray: { $type: "$anArray" },
    anObject: { $type: "$anObject" }, anObjectId: { $type: "$anObjectId" }, aRegex: { $type: "$aRegex" },
    aBinary: { $type: "$aBinary" }, aTimestamp: { $type: "$aTimestamp" }, missingField: { $type: "$nope" }
} }]);
// -> int, double, int, long, decimal, string, bool, null, date, array, object, objectId, regex, binData, timestamp, missing


/* ============================================================
   2. $type IN A QUERY
   ============================================================ */

db.l02_types.find({ aNumber: { $type: "int" } }).count();      // 1  <- 85000 typed in mongosh is stored as INT (32-bit)
db.l02_types.find({ aNumber: { $type: "double" } }).count();   // 0
db.l02_types.find({ aDouble: { $type: "double" } }).count();   // 1  (85000.5 cannot be an int)
db.l02_types.find({ anInt:   { $type: 16 } }).count();         // 1  (numeric code for int)
db.l02_types.find({ aNumber: { $type: "number" } }).count();   // 1  ("number" = double + int + long + decimal)
db.l02_types.find({ aString: { $type: ["string", "null"] } }).count();   // 1 (any of the listed types)

// The real companyDB data: every salary is an int (whole numbers inserted from mongosh)
db.employees.find({ salary: { $type: "int" } }).count();       // 12
db.employees.find({ salary: { $type: "double" } }).count();    // 0
// Rule (mongosh & Node.js driver): whole number within +-2147483647 -> int, anything else -> double.
// The legacy "mongo" shell stored EVERY number as double - a classic interview question.
db.l02_types.insertOne({ _id: 9, big: 3000000000, neg: -5, frac: 2.0, forced: Double(5) });
db.l02_types.aggregate([{ $match: { _id: 9 } }, { $project: { _id: 0,
    big: { $type: "$big" }, neg: { $type: "$neg" }, frac: { $type: "$frac" }, forced: { $type: "$forced" } } }]);
// -> big: double, neg: int, frac: int (JS cannot tell 2.0 from 2), forced: double


/* ============================================================
   3. NUMBERS: double vs int vs long vs decimal
   ============================================================ */

// 3a. Floating point is not exact
0.1 + 0.2;                                      // 0.30000000000000004  (plain JS / double)
db.l02_types.insertOne({ _id: 2, d: 0.1, dec: NumberDecimal("0.1") });
db.l02_types.aggregate([
    { $match: { _id: 2 } },
    { $project: { doubleSum: { $add: ["$d", "$d", "$d"] }, decimalSum: { $add: ["$dec", "$dec", "$dec"] } } }
]);                                             // doubleSum: 0.30000000000000004, decimalSum: Decimal128('0.3')

// 3b. Big integers: JS numbers are exact only up to 2^53 (9007199254740992)
9007199254740993;                               // prints 9007199254740992 - already lost in JS!
NumberLong("9007199254740993");                 // Long('9007199254740993') - exact, because we passed a string
db.l02_types.findOne({ _id: 1 }).aLong;          // Long('9007199254740993')

// 3c. Numbers of different numeric types compare by VALUE
db.l02_types.find({ anInt: Double(85000) }).count();     // 1  (int 85000 == double 85000)
db.l02_types.find({ aDecimal: 19.99 }).count();          // 1  (decimal 19.99 == double 19.99)
db.l02_types.find({ aLong: { $gt: 1 } }).count();        // 1  (long vs int)

// 3d. Integer division does not exist - / always gives a double
db.l02_types.aggregate([{ $match: { _id: 1 } }, { $project: { q: { $divide: [7, 2] } } }]);   // 3.5
// (SQL Server would give 3)


/* ============================================================
   4. DATES
   ============================================================ */

new Date();                                     // now (UTC in the output: ISODate('...Z'))
ISODate("2025-01-05");                          // 2025-01-05T00:00:00.000Z  - midnight UTC, not local!
new Date("2025-01-05T10:30:00+05:30");          // converted to UTC: 05:00:00Z
ISODate("2025-01-05").getTime();                // milliseconds since 1970-01-01 (what is actually stored)

// Dates compare and sort correctly because they are numbers underneath
db.employees.find({ hireDate: { $gte: ISODate("2024-01-01") } }, { _id: 0, name: 1, hireDate: 1 });   // Neha, Anjali, Meera

// THE TRAP: a date stored as a string
db.l02_types.insertMany([
    { _id: 3, when: ISODate("2025-06-01"), label: "real date" },
    { _id: 4, when: "2025-06-01",          label: "string date" }
]);
db.l02_types.find({ when: { $gte: ISODate("2025-01-01") } }, { label: 1 });   // only "real date"
db.l02_types.find({ when: { $gte: "2025-01-01" } }, { label: 1 });            // only "string date"
// A Date and a string never match each other. Store dates as Date, always.

// Date parts in JS (shell side)
const hd = db.employees.findOne({ _id: 101 }).hireDate;
hd.getUTCFullYear();                            // 2022
hd.toISOString();                               // '2022-01-10T00:00:00.000Z'


/* ============================================================
   5. null vs MISSING vs $exists
   ============================================================ */

// Base data: Anjali (110) has NO email field; Meera (112) has NO skills field;
//            Farhan (customer 6) has email: null, Hina (8) has NO email field.
db.customers.find({ email: null }, { name: 1, email: 1 });                    // Farhan AND Hina (null matches missing too)
db.customers.find({ email: { $type: "null" } }, { name: 1 });                // Farhan only (explicit null)
db.customers.find({ email: { $exists: false } }, { name: 1 });               // Hina only (field missing)
db.customers.find({ email: { $exists: true, $ne: null } }, { name: 1 }).count();   // 6 (real values)

db.employees.find({ skills: { $exists: false } }, { name: 1 });              // Meera
db.employees.find({ skills: [] }, { name: 1 });                              // Anjali (empty array)
db.employees.find({ skills: { $size: 0 } }, { name: 1 });                    // Anjali (same)


/* ============================================================
   6. EMBEDDED DOCUMENT EQUALITY vs DOT NOTATION
   ============================================================ */

// Exact match: the WHOLE sub-document, all fields, SAME ORDER
db.employees.find({ address: { city: "Delhi", state: "Delhi", pincode: 110001 } }, { name: 1 });   // Rahul, Anjali
db.employees.find({ address: { state: "Delhi", city: "Delhi", pincode: 110001 } }, { name: 1 });   // [] - order differs!
db.employees.find({ address: { city: "Delhi" } }, { name: 1 });                                     // [] - missing fields!

// Dot notation: match ONE field inside
db.employees.find({ "address.city": "Delhi" }, { name: 1 });                 // Rahul, Ravi, Pooja, Anjali
db.employees.find({ "address.city": "Delhi", "address.pincode": 110001 }, { name: 1 });   // Rahul, Anjali


/* ============================================================
   7. TYPE COMPARISON ORDER (type bracketing)
   ============================================================ */

db.l02_mixed.drop();
db.l02_mixed.insertMany([
    { v: 10 }, { v: "10" }, { v: null }, { v: true }, { v: ISODate("2025-01-01") },
    { v: [1] }, { v: { a: 1 } }, { v: 2 }, { v: "apple" }, {}
]);
// Sort ascending: null/missing < numbers < strings < objects < booleans < dates
// Watch the ARRAY: for sorting, an array is represented by its smallest element (1),
// so [1] appears between null and 2 - not in an "array" bracket.
db.l02_mixed.find({}, { _id: 0 }).sort({ v: 1 });

// $gt / $lt only compare within the same type bracket
db.l02_mixed.find({ v: { $gt: 5 } }, { _id: 0 });       // 10 only  (not "10", not the date)
db.l02_mixed.find({ v: { $gt: "a" } }, { _id: 0 });     // "apple" only  (strings: byte order, "10" < "a")
db.l02_mixed.find({ v: { $lt: 5 } }, { _id: 0 });       // [1] and 2   (an array matches if ANY element matches; NOT null / missing)


/* ============================================================
   8. STRINGS ARE CASE-SENSITIVE AND BINARY-COMPARED (by default)
   ============================================================ */

db.employees.find({ name: "rahul" }).count();           // 0  (Rahul != rahul)
db.employees.find({ name: /^rahul$/i }).count();        // 1  (regex, case-insensitive) - Level 03
db.employees.find({ name: "rahul" }).collation({ locale: "en", strength: 2 }).count();   // 1 (collation, Level 04)
"Zebra" < "apple";                                      // true: uppercase letters sort before lowercase in binary order


/* ============================================================
   CLEANUP
   ============================================================ */
db.l02_types.drop();
db.l02_mixed.drop();

/* ------------------------------------------------------------
   DONE. Next: Exercises.js
   ------------------------------------------------------------ */
