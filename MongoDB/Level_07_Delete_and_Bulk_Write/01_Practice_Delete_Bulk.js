/* ============================================================
   LEVEL 07 - DELETE & BULK WRITE  |  01_Practice_Delete_Bulk.js
   ------------------------------------------------------------
   Topics : deleteOne / deleteMany / findOneAndDelete, deletedCount,
            deleteMany({}) vs drop(), manual cascade, soft delete,
            batched mass delete, bulkWrite (ordered / unordered,
            mixed operations, errors), write concern

   HOW TO PRACTICE: block by block, predict first.
   Works on copies l07_customers / l07_orders / l07_products.
   ============================================================ */

use("companyDB");
db.customers.aggregate([{ $out: "l07_customers" }]);
db.orders.aggregate([{ $out: "l07_orders" }]);
db.products.aggregate([{ $out: "l07_products" }]);


/* ============================================================
   1. deleteOne / deleteMany - the result object
   ============================================================ */

db.l07_orders.deleteOne({ _id: 1006 });                              // { acknowledged: true, deletedCount: 1 }
db.l07_orders.deleteOne({ _id: 1006 });                              // deletedCount: 0 - already gone, no error
db.l07_orders.countDocuments();                                      // 18

// deleteOne with a broad filter deletes SOME matching document (natural order) - be precise!
db.l07_orders.deleteOne({ status: "Pending" });                      // removed 1015 (first in storage order) - but do not rely on it
db.l07_orders.find({ status: "Pending" }, { _id: 1 });               // 1017 left

// deleteMany with a filter  (SQL DELETE ... WHERE)
db.l07_orders.deleteMany({ customerId: 1 });                         // deletedCount: 3 (1001, 1004, 1009 - 1015 was already deleted)
db.l07_orders.countDocuments();                                      // 14

// deleteMany with no match
db.l07_orders.deleteMany({ status: "Refunded" });                    // deletedCount: 0


/* ============================================================
   2. findOneAndDelete - delete AND return (with sort = "DELETE TOP 1 ORDER BY")
   ============================================================ */

db.l07_orders.findOneAndDelete({ status: "Completed" }, { sort: { orderDate: 1 }, projection: { _id: 1, orderDate: 1 } });   // 1002 (oldest completed)
db.l07_orders.findOneAndDelete({ status: "Refunded" });              // null


/* ============================================================
   3. NO CASCADE: delete a customer AND their orders yourself
   ============================================================ */

db.l07_orders.countDocuments({ customerId: 2 });                     // 3 (1007, 1012, 1019)
db.l07_orders.deleteMany({ customerId: 2 });                         // children first ...
db.l07_customers.deleteOne({ _id: 2 });                              // ... then the parent
db.l07_orders.countDocuments({ customerId: 2 });                     // 0
// Two statements = not atomic. If the app crashes in between you have orphans. Level 14: wrap them in a transaction.


/* ============================================================
   4. SOFT DELETE  (keep the document, mark it)
   ============================================================ */

db.l07_customers.updateOne({ _id: 8 }, { $set: { deletedAt: new Date() } });
db.l07_customers.find({ deletedAt: { $exists: false } }).count();    // 6 "alive" (8 - Bhavna deleted - Hina soft-deleted)
db.l07_customers.find({ deletedAt: { $exists: true } }, { _id: 0, name: 1, deletedAt: 1 });   // Hina
// Undo is trivial:
db.l07_customers.updateOne({ _id: 8 }, { $unset: { deletedAt: "" } });


/* ============================================================
   5. deleteMany({}) vs drop()
   ============================================================ */

db.l07_products.createIndex({ category: 1 });
db.l07_products.deleteMany({});                                      // deletedCount: 11 - documents gone, collection + indexes remain
db.l07_products.getIndexes().length;                                 // 2 (_id + category)
db.getCollectionNames().includes("l07_products");                    // true

db.l07_products.drop();                                              // true - collection AND indexes gone, instantly
db.getCollectionNames().includes("l07_products");                    // false
db.l07_products.drop();                                              // false - nothing to drop, no error


/* ============================================================
   6. MASS DELETE IN BATCHES  (production pattern)
   ============================================================ */

// Build 5000 log documents
db.l07_logs.drop();
const loaded = db.l07_logs.insertMany(Array.from({ length: 5000 }, (_, i) => ({ n: i, level: i % 10 === 0 ? "ERROR" : "INFO" })));
Object.keys(loaded.insertedIds).length;                              // 5000 (not printing the result itself - 5000 ObjectIds)
db.l07_logs.countDocuments();                                        // 5000

// Delete all INFO logs 1000 at a time (small oplog entries, short locks, replication keeps up)
let rounds = 0, total = 0;
while (true) {
    // NOTE: cursor.map() returns another CURSOR in mongosh - call .toArray() to get a real array for $in
    const ids = db.l07_logs.find({ level: "INFO" }, { _id: 1 }).limit(1000).toArray().map(d => d._id);
    if (ids.length === 0) break;
    total += db.l07_logs.deleteMany({ _id: { $in: ids } }).deletedCount;
    rounds++;
}
print("deleted", total, "in", rounds, "rounds");                      // deleted 4500 in 5 rounds
db.l07_logs.countDocuments();                                        // 500 (ERROR)
// Alternative for time-based data: a TTL index (Level 11) deletes expired documents for you.


/* ============================================================
   7. bulkWrite - many operations, one round trip
   ============================================================ */

db.products.aggregate([{ $out: "l07_products" }]);                   // fresh copy

const bulk = db.l07_products.bulkWrite([
    { insertOne:  { document: { _id: 12, name: "Docking Station", category: "Electronics", price: 6500, stock: 8 } } },
    { updateOne:  { filter: { _id: 9 }, update: { $set: { stock: 15 } } } },                                    // Headphones back in stock
    { updateOne:  { filter: { _id: 13 }, update: { $set: { name: "USB Hub", category: "Electronics", price: 1200, stock: 40 } }, upsert: true } },
    { updateMany: { filter: { category: "Stationery" }, update: { $mul: { price: 1.05 } } } },                 // 2 docs
    { replaceOne: { filter: { _id: 11 }, replacement: { name: "Webcam HD", category: "Electronics", price: 5000, stock: 30 } } },
    { deleteOne:  { filter: { _id: 8 } } },                                                                    // Pen
    { deleteMany: { filter: { category: "Furniture", stock: { $lt: 10 } } } }                                  // Bookshelf (5)
]);
bulk;
// insertedCount 1, matchedCount 4 (9, Stationery x2, 11), modifiedCount 4, upsertedCount 1 (13), deletedCount 2, upsertedIds { '2': 13 }, insertedIds { '0': 12 }
db.l07_products.find({}, { _id: 1, name: 1, price: 1, stock: 1 }).sort({ _id: 1 });


/* ============================================================
   8. bulkWrite: ORDERED (default) vs UNORDERED on errors
   ============================================================ */

// ordered: stops at the first error; ops BEFORE it are applied, ops AFTER it are skipped
try {
    db.l07_products.bulkWrite([
        { insertOne: { document: { _id: 20, name: "ok-before" } } },
        { insertOne: { document: { _id: 20, name: "DUPLICATE" } } },        // fails
        { insertOne: { document: { _id: 21, name: "skipped" } } }
    ]);                                                                     // ordered: true is the default
} catch (e) {
    print("EXPECTED ERROR:", e.message);
    print("inserted:", e.result.insertedCount, " writeErrors:", e.writeErrors.length, " at index", e.writeErrors[0].index);   // 1, 1, 1
}
db.l07_products.find({ _id: { $in: [20, 21] } }, { name: 1 });          // only 20

// unordered: everything that CAN be applied is applied; all errors reported
try {
    db.l07_products.bulkWrite([
        { insertOne: { document: { _id: 30, name: "ok" } } },
        { insertOne: { document: { _id: 30, name: "DUPLICATE" } } },        // fails
        { insertOne: { document: { _id: 31, name: "still-inserted" } } },
        { updateOne: { filter: { _id: 1 }, update: { $inc: { name: 1 } } } }   // fails ($inc on string)
    ], { ordered: false });
} catch (e) {
    print("EXPECTED ERROR:", e.message);
    print("inserted:", e.result.insertedCount, " writeErrors:", e.writeErrors.length);   // 2, 2
    e.writeErrors.forEach(w => print("  op", w.index, "->", w.errmsg.substring(0, 60)));
}
db.l07_products.find({ _id: { $in: [30, 31] } }, { name: 1 });          // 30 and 31


/* ============================================================
   9. bulkWrite AS "UPSERT MANY" (sync a list from an external system)
   ============================================================ */

const feed = [ { sku: "A1", price: 10 }, { sku: "B2", price: 20 }, { sku: "C3", price: 30 } ];
db.l07_feed.drop();
db.l07_feed.bulkWrite(feed.map(p => ({ updateOne: { filter: { sku: p.sku }, update: { $set: { price: p.price }, $setOnInsert: { createdAt: new Date() } }, upsert: true } })));
// upsertedCount 3
db.l07_feed.bulkWrite(feed.map(p => ({ updateOne: { filter: { sku: p.sku }, update: { $set: { price: p.price * 2 } }, upsert: true } })));
// matchedCount 3, modifiedCount 3, upsertedCount 0
db.l07_feed.find({}, { _id: 0 });


/* ============================================================
   10. WRITE CONCERN ON DELETES (preview of Level 17)
   ============================================================ */

db.l07_feed.deleteMany({}, { writeConcern: { w: "majority", wtimeout: 5000 } });   // deletedCount: 3
// w:"majority" waits until most replica-set members have the delete; wtimeout stops the wait (the write itself is not undone).


/* ============================================================
   CLEANUP
   ============================================================ */
db.l07_customers.drop(); db.l07_orders.drop(); db.l07_products.drop(); db.l07_logs.drop(); db.l07_feed.drop();

/* ------------------------------------------------------------
   DONE. Next: Exercises.js
   ------------------------------------------------------------ */
