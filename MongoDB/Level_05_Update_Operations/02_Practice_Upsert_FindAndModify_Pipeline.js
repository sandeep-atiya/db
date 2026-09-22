/* ============================================================
   LEVEL 05  |  02_Practice_Upsert_FindAndModify_Pipeline.js
   ------------------------------------------------------------
   Topics : upsert + $setOnInsert, findOneAndUpdate / Replace /
            Delete (returnDocument, sort, projection), counters,
            job queue pattern, pipeline updates ($set with
            expressions, $cond, $$NOW, $unset, $replaceWith),
            sort option on updateOne (8.0+)

   HOW TO PRACTICE: block by block, predict first.
   Works on copies l05_employees / l05_orders. Dropped in CLEANUP.
   ============================================================ */

use("companyDB");
db.employees.aggregate([{ $out: "l05_employees" }]);
db.orders.aggregate([{ $out: "l05_orders" }]);
db.l05_counters.drop();


/* ============================================================
   1. UPSERT  =  update if found, insert if not  (SQL MERGE)
   ============================================================ */

// No employee 113 -> INSERTED. The new document = filter equality fields + $set fields
const u1 = db.l05_employees.updateOne(
    { _id: 113 },
    { $set: { name: "Isha", departmentId: 3, salary: 52000 } },
    { upsert: true }
);
u1;                                                                 // matchedCount 0, modifiedCount 0, upsertedCount 1, upsertedId 113
db.l05_employees.findOne({ _id: 113 });

// Run the SAME statement again -> now it is an UPDATE (matched 1)
db.l05_employees.updateOne({ _id: 113 }, { $set: { name: "Isha", departmentId: 3, salary: 52000 } }, { upsert: true });

// $setOnInsert: fields written ONLY when the upsert inserts (createdAt once, updatedAt always)
db.l05_employees.updateOne(
    { email: "omar@example.com" },                                  // filter on a non-_id field -> a new ObjectId _id is generated
    { $set: { name: "Omar", updatedAt: new Date() }, $setOnInsert: { createdAt: new Date(), salary: 50000 } },
    { upsert: true }
);
db.l05_employees.findOne({ email: "omar@example.com" });            // has createdAt, salary 50000
db.l05_employees.updateOne(
    { email: "omar@example.com" },
    { $set: { name: "Omar K.", updatedAt: new Date() }, $setOnInsert: { createdAt: new Date(), salary: 1 } },
    { upsert: true }
);
db.l05_employees.findOne({ email: "omar@example.com" }, { _id: 0, name: 1, salary: 1 });   // salary still 50000 ($setOnInsert ignored on update)

// Filter operators ($gt etc.) do NOT contribute to the inserted document
db.l05_employees.updateOne({ salary: { $gt: 999999 }, departmentId: 9 }, { $set: { name: "Ghost" } }, { upsert: true });
db.l05_employees.findOne({ name: "Ghost" });                        // has departmentId 9 (equality) but NO salary field

// Upsert with updateMany: inserts ONE document when nothing matches
db.l05_employees.updateMany({ departmentId: 42 }, { $set: { flag: true } }, { upsert: true });
db.l05_employees.countDocuments({ departmentId: 42 });              // 1


/* ============================================================
   2. findOneAndUpdate  -  update AND get the document, atomically
   ============================================================ */

// Default returns the document BEFORE the update
db.l05_employees.findOneAndUpdate({ _id: 101 }, { $inc: { salary: 1000 } });                              // salary 85000 (old)
// returnDocument: "after"  + projection
db.l05_employees.findOneAndUpdate({ _id: 101 }, { $inc: { salary: 1000 } }, { returnDocument: "after", projection: { _id: 0, name: 1, salary: 1 } });   // 87000

// With sort: "give the highest-paid Sales employee a bonus flag and show me who it was"
db.l05_employees.findOneAndUpdate(
    { departmentId: 2 },
    { $set: { bonus: true } },
    { sort: { salary: -1 }, returnDocument: "after", projection: { _id: 0, name: 1, salary: 1, bonus: 1 } }
);                                                                                                          // Priya

// No match -> null (or the upserted document with upsert: true)
db.l05_employees.findOneAndUpdate({ _id: 999 }, { $set: { x: 1 } });                                        // null


/* ============================================================
   3. COUNTER / SEQUENCE PATTERN  (auto-increment ids)
   ============================================================ */

function nextId(name) {
    return db.l05_counters.findOneAndUpdate(
        { _id: name },
        { $inc: { seq: 1 } },
        { upsert: true, returnDocument: "after" }
    ).seq;
}
nextId("orderId");                                                  // 1
nextId("orderId");                                                  // 2
nextId("invoiceId");                                                // 1
db.l05_counters.find();
// Atomic per document -> two clients never get the same number. (Prefer ObjectId when you can: no hot document.)


/* ============================================================
   4. JOB QUEUE PATTERN  (claim one pending item atomically)
   ============================================================ */

// Two workers calling this at the same time will get DIFFERENT orders - the update is atomic per document.
function claimOrder(worker) {
    return db.l05_orders.findOneAndUpdate(
        { status: "Pending", claimedBy: { $exists: false } },
        { $set: { claimedBy: worker, claimedAt: new Date() } },
        { sort: { orderDate: 1 }, returnDocument: "after", projection: { _id: 1, claimedBy: 1 } }
    );
}
claimOrder("worker-A");                                             // 1015 (oldest pending)
claimOrder("worker-B");                                             // 1017
claimOrder("worker-C");                                             // null - nothing left

// findOneAndDelete = pop from a queue
db.l05_orders.findOneAndDelete({ status: "Cancelled" }, { projection: { _id: 1, status: 1 } });   // 1006 returned and removed
db.l05_orders.countDocuments({ status: "Cancelled" });              // 0

// findOneAndReplace
db.l05_orders.findOneAndReplace({ _id: 1019 }, { note: "replaced" }, { returnDocument: "after" });   // { _id: 1019, note: 'replaced' }


/* ============================================================
   5. PIPELINE UPDATES  (reference other fields, conditional logic)
   ============================================================ */

// SQL: UPDATE employees SET annualSalary = salary * 12, updatedAt = GETDATE()
db.l05_employees.updateMany(
    { salary: { $type: "number" } },
    [ { $set: { annualSalary: { $multiply: ["$salary", 12] }, updatedAt: "$$NOW" } } ]
);
db.l05_employees.find({ _id: { $in: [101, 102] } }, { _id: 0, name: 1, salary: 1, annualSalary: 1, updatedAt: 1 });

// SQL: UPDATE ... SET band = CASE WHEN salary >= 70000 THEN 'A' WHEN salary >= 60000 THEN 'B' ELSE 'C' END
db.l05_employees.updateMany({}, [ { $set: { band: { $switch: {
    branches: [
        { case: { $gte: ["$salary", 70000] }, then: "A" },
        { case: { $gte: ["$salary", 60000] }, then: "B" }
    ],
    default: "C" } } } } ]);
db.l05_employees.find({ departmentId: 1 }, { _id: 0, name: 1, salary: 1, band: 1 });

// Derived string: fullLabel = name + " (" + city + ")"
db.l05_employees.updateMany({ "address.city": { $exists: true } },
    [ { $set: { label: { $concat: ["$name", " (", "$address.city", ")"] } } } ]);
db.l05_employees.findOne({ _id: 103 }, { _id: 0, label: 1 });      // Priya (Mumbai)

// $unset stage takes a list
db.l05_employees.updateMany({}, [ { $unset: ["annualSalary", "label"] } ]);
db.l05_employees.findOne({ _id: 103 }, { _id: 0, annualSalary: 1, label: 1, name: 1 });   // only name

// Pipeline update on ONE document computing from an array: order total from its items
db.l05_orders.updateOne({ _id: 1008 }, [ { $set: { totalAmount: 0 } } ]);                  // break it
db.l05_orders.updateOne({ _id: 1008 }, [ { $set: { totalAmount: { $sum: { $map: { input: "$items", as: "i", in: { $multiply: ["$$i.qty", "$$i.unitPrice"] } } } } } } ]);
db.l05_orders.findOne({ _id: 1008 }, { _id: 0, totalAmount: 1 });   // 78500 again

// Update operators like $push / $inc are NOT allowed inside a pipeline
try {
    db.l05_employees.updateOne({ _id: 101 }, [ { $inc: { salary: 1 } } ]);
} catch (e) {
    print("EXPECTED ERROR:", e.message);                             // Unrecognized pipeline stage name: '$inc'
}


/* ============================================================
   6. sort OPTION ON updateOne / replaceOne  (MongoDB 8.0+)
   ============================================================ */

// "Mark the OLDEST pending order as processing" - before 8.0 you needed findOneAndUpdate for this
db.l05_orders.updateMany({ _id: { $in: [1015, 1017] } }, { $set: { status: "Pending" }, $unset: { claimedBy: "", claimedAt: "" } });
db.l05_orders.updateOne({ status: "Pending" }, { $set: { status: "Processing" } }, { sort: { orderDate: 1 } });
db.l05_orders.find({ status: { $in: ["Pending", "Processing"] } }, { _id: 1, status: 1, orderDate: 1 });   // 1015 Processing, 1017 Pending


/* ============================================================
   CLEANUP
   ============================================================ */
db.l05_employees.drop();
db.l05_orders.drop();
db.l05_counters.drop();

/* ------------------------------------------------------------
   DONE. Next: Exercises.js
   ------------------------------------------------------------ */
