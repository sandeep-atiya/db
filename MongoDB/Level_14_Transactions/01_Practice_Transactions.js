/* ============================================================
   LEVEL 14 - TRANSACTIONS  |  01_Practice_Transactions.js
   ------------------------------------------------------------
   Topics : single-document atomicity, the problem without a
            transaction, core API (start / commit / abort), visibility
            (snapshot isolation), callback API (withTransaction),
            write conflicts + retry, blocking of plain writes,
            forbidden operations, transaction statistics

   HOW TO PRACTICE: block by block, predict first.
   Needs a REPLICA SET (the Docker setup is one). Works on copies
   l14_orders / l14_products (dropped in CLEANUP).
   ============================================================ */

use("companyDB");
db.orders.aggregate([ { $out: "l14_orders" } ]);
db.products.aggregate([ { $out: "l14_products" } ]);
db.hello().setName;                                        // "rs0" - transactions need a replica set


/* ============================================================
   1. SINGLE-DOCUMENT ATOMICITY  (no transaction needed)
   ============================================================ */

// All operators of ONE update are applied atomically - nobody can observe stock decremented but sold not incremented
db.l14_products.updateOne({ _id: 1 }, { $inc: { stock: -1, sold: 1 }, $set: { lastSaleAt: new Date() }, $push: { history: { qty: 1, at: new Date() } } });
db.l14_products.findOne({ _id: 1 }, { _id: 0, stock: 1, sold: 1, history: 1 });   // stock 9, sold 1
// A conditional update is an atomic "check-and-set": sell only if enough stock
db.l14_products.updateOne({ _id: 9, stock: { $gte: 1 } }, { $inc: { stock: -1 } }).matchedCount;   // 0 - Headphones out of stock, nothing changed
// -> With embedding (order lines inside the order) most business operations touch ONE document and need no transaction.


/* ============================================================
   2. THE PROBLEM: two documents, no transaction
   ============================================================ */

// "Place an order": insert the order AND decrement stock. Two statements = two atomic units, not one.
db.l14_orders.insertOne({ _id: 2001, customerId: 1, items: [ { productId: 2, qty: 5, unitPrice: 1000 } ], totalAmount: 5000, status: "Pending" });
// ... imagine the application crashes HERE ...
// db.l14_products.updateOne({ _id: 2 }, { $inc: { stock: -5 } });   // never runs -> order exists, stock still 100: inconsistent
db.l14_products.findOne({ _id: 2 }, { _id: 0, stock: 1 });          // 100
db.l14_orders.deleteOne({ _id: 2001 });                               // clean up the half-done work by hand


/* ============================================================
   3. CORE API: startTransaction / commit, and WHO SEES WHAT
   ============================================================ */

const s1 = db.getMongo().startSession();
s1.startTransaction({ readConcern: { level: "snapshot" }, writeConcern: { w: "majority" } });
const tOrders = s1.getDatabase("companyDB").l14_orders;     // collections BOUND to the session = inside the transaction
const tProducts = s1.getDatabase("companyDB").l14_products;

tOrders.insertOne({ _id: 2001, customerId: 1, items: [ { productId: 2, qty: 5, unitPrice: 1000 } ], totalAmount: 5000, status: "Pending" });
tProducts.updateOne({ _id: 2, stock: { $gte: 5 } }, { $inc: { stock: -5 } });

// INSIDE the transaction the writes are visible ...
tProducts.findOne({ _id: 2 }, { _id: 0, stock: 1 });                 // 95
tOrders.countDocuments({ _id: 2001 });                                // 1
// ... OUTSIDE (plain db = a different session) nothing has happened yet
db.l14_products.findOne({ _id: 2 }, { _id: 0, stock: 1 });          // 100
db.l14_orders.countDocuments({ _id: 2001 });                          // 0

s1.commitTransaction();
db.l14_products.findOne({ _id: 2 }, { _id: 0, stock: 1 });          // 95 - now everybody sees both changes at once
db.l14_orders.countDocuments({ _id: 2001 });                          // 1
s1.endSession();


/* ============================================================
   4. ABORT  (business rule fails -> nothing happens)
   ============================================================ */

const s2 = db.getMongo().startSession();
s2.startTransaction();
const t2o = s2.getDatabase("companyDB").l14_orders, t2p = s2.getDatabase("companyDB").l14_products;
try {
    t2o.insertOne({ _id: 2002, customerId: 5, items: [ { productId: 9, qty: 1, unitPrice: 3000 } ], totalAmount: 3000, status: "Pending" });
    const r = t2p.updateOne({ _id: 9, stock: { $gte: 1 } }, { $inc: { stock: -1 } });
    if (r.matchedCount === 0) throw new Error("Headphones out of stock");
    s2.commitTransaction();
    print("committed");
} catch (e) {
    s2.abortTransaction();
    print("ABORTED:", e.message);
} finally {
    s2.endSession();
}
db.l14_orders.countDocuments({ _id: 2002 });                          // 0 - the insert was rolled back


/* ============================================================
   5. CALLBACK API: withTransaction  (auto-retry on transient errors)
   ============================================================ */

function placeOrder(orderId, customerId, productId, qty) {
    const session = db.getMongo().startSession();
    try {
        session.withTransaction(() => {
            const o = session.getDatabase("companyDB").l14_orders;
            const p = session.getDatabase("companyDB").l14_products;
            const prod = p.findOne({ _id: productId });
            const r = p.updateOne({ _id: productId, stock: { $gte: qty } }, { $inc: { stock: -qty } });
            if (r.matchedCount === 0) throw new Error("insufficient stock for product " + productId);
            o.insertOne({ _id: orderId, customerId, items: [ { productId, qty, unitPrice: prod.price } ], totalAmount: qty * prod.price, status: "Pending" });
        }, { readConcern: { level: "snapshot" }, writeConcern: { w: "majority" } });
        return "order " + orderId + " placed";
    } catch (e) {
        return "order " + orderId + " FAILED: " + e.message;              // withTransaction aborted and re-threw
    } finally {
        session.endSession();
    }
}
placeOrder(2003, 2, 3, 2);                                            // placed  (Keyboard 50 -> 48)
placeOrder(2004, 3, 9, 1);                                            // FAILED: insufficient stock (Headphones)
placeOrder(2005, 4, 5, 20);                                           // FAILED: Desk has 15
db.l14_products.find({ _id: { $in: [3, 5, 9] } }, { _id: 1, stock: 1 });
db.l14_orders.find({ _id: { $gte: 2000 } }, { _id: 1, totalAmount: 1 });   // 2001, 2003 only


/* ============================================================
   6. WRITE CONFLICT between two transactions  (+ manual retry)
   ============================================================ */

const sA = db.getMongo().startSession(), sB = db.getMongo().startSession();
sA.startTransaction(); sB.startTransaction();
sA.getDatabase("companyDB").l14_products.updateOne({ _id: 4 }, { $inc: { stock: -1 } });   // A modifies Chair
try {
    sB.getDatabase("companyDB").l14_products.updateOne({ _id: 4 }, { $inc: { stock: -2 } });   // B modifies the SAME document -> immediate conflict
} catch (e) {
    print("EXPECTED ERROR:", e.codeName, "code", e.code, "labels", JSON.stringify(e.errorLabels));   // WriteConflict 112 ["TransientTransactionError"]
}
sB.abortTransaction();                                                // B must abort (and would retry from the start)
sA.commitTransaction();                                               // A wins
sA.endSession(); sB.endSession();
db.l14_products.findOne({ _id: 4 }, { _id: 0, stock: 1 });          // 19

// Manual retry loop for the core API (this is what withTransaction does for you)
function runTransactionWithRetry(fn, maxAttempts = 3) {
    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
        const session = db.getMongo().startSession();
        session.startTransaction();
        try {
            fn(session);
            session.commitTransaction();
            return "committed on attempt " + attempt;
        } catch (e) {
            session.abortTransaction();
            if (e.errorLabels && e.errorLabels.includes("TransientTransactionError") && attempt < maxAttempts) continue;   // retry
            throw e;
        } finally {
            session.endSession();
        }
    }
}
runTransactionWithRetry(s => s.getDatabase("companyDB").l14_products.updateOne({ _id: 4 }, { $inc: { stock: -1 } }));   // committed on attempt 1


/* ============================================================
   7. A PLAIN (non-transactional) WRITE WAITS for an open transaction
   ============================================================ */

const sLock = db.getMongo().startSession();
sLock.startTransaction();
sLock.getDatabase("companyDB").l14_products.updateOne({ _id: 6 }, { $set: { note: "held by open transaction" } });
// A normal update on the same document does NOT fail - it BLOCKS until the transaction ends (up to 60 s). Cap the wait with maxTimeMS:
try {
    db.runCommand({ update: "l14_products", updates: [ { q: { _id: 6 }, u: { $set: { note: "plain write" } } } ], maxTimeMS: 2000 });
} catch (e) {
    print("EXPECTED ERROR:", e.codeName);                   // MaxTimeMSExpired after 2 s of waiting for the transaction
}
sLock.commitTransaction(); sLock.endSession();
db.l14_products.findOne({ _id: 6 }, { _id: 0, note: 1 });           // 'held by open transaction' (the plain write timed out)
// Lesson: long transactions stall other writers. Keep them milliseconds long.


/* ============================================================
   8. SNAPSHOT ISOLATION: a transaction does not see later commits
   ============================================================ */

const sSnap = db.getMongo().startSession();
sSnap.startTransaction({ readConcern: { level: "snapshot" } });
const snapProducts = sSnap.getDatabase("companyDB").l14_products;
snapProducts.findOne({ _id: 7 }, { _id: 0, price: 1 });              // 50  (snapshot taken now)
db.l14_products.updateOne({ _id: 7 }, { $set: { price: 55 } });      // committed OUTSIDE, after the snapshot
snapProducts.findOne({ _id: 7 }, { _id: 0, price: 1 });              // still 50 inside the transaction
db.l14_products.findOne({ _id: 7 }, { _id: 0, price: 1 });          // 55 outside
sSnap.commitTransaction(); sSnap.endSession();                       // read-only transactions commit trivially
// SQL Server equivalent: SNAPSHOT isolation (no dirty / non-repeatable / phantom reads).


/* ============================================================
   9. WHAT IS NOT ALLOWED INSIDE A TRANSACTION
   ============================================================ */

// IMPORTANT: an error inside a transaction ABORTS it on the server. Every later operation on that transaction
// (even abortTransaction) fails with "NoSuchTransaction" -> each experiment below gets its own session/transaction.
function inTxn(label, fn) {
    const s = db.getMongo().startSession();
    s.startTransaction();
    try { fn(s.getDatabase("companyDB")); print(label, "-> allowed"); }
    catch (e) { print("EXPECTED ERROR (" + label + "):", e.message.substring(0, 90)); }
    finally { try { s.abortTransaction(); } catch (e) { /* already aborted by the server */ } s.endSession(); }
}
inTxn("createIndex (DDL)", d => d.l14_products.createIndex({ note: 1 }));                                          // Cannot create new indexes ... in a multi-document transaction
inTxn("drop collection (DDL)", d => d.l14_orders.drop());                                                          // not allowed
inTxn("count()", d => d.l14_orders.count());                                                                       // Cannot run 'count' in a multi-document transaction
inTxn("countDocuments()", d => d.l14_orders.countDocuments());                                                     // allowed (it is an aggregation)
inTxn("$out", d => d.l14_orders.aggregate([ { $match: { status: "Pending" } }, { $out: "l14_tmp" } ]).toArray()); // $out cannot be used in a transaction
inTxn("insert into a NEW collection", d => d.l14_new.insertOne({ a: 1 }));                                          // allowed since 4.4 (implicit creation)
db.l14_new.countDocuments();                                          // 0 - the transaction was aborted, so the collection is empty (it may exist)

// Using a NON-session collection inside a "transaction block" silently writes OUTSIDE the transaction:
const sOops = db.getMongo().startSession();
sOops.startTransaction();
db.l14_products.updateOne({ _id: 8 }, { $set: { oops: true } });     // plain db -> committed immediately, not part of sOops
sOops.abortTransaction(); sOops.endSession();
db.l14_products.findOne({ _id: 8 }, { _id: 0, oops: 1 });           // { oops: true } - the abort did not undo it


/* ============================================================
   10. STATISTICS AND SETTINGS
   ============================================================ */

const tx = db.serverStatus().transactions;
({ currentActive: tx.currentActive, currentOpen: tx.currentOpen, totalStarted: tx.totalStarted, totalCommitted: tx.totalCommitted, totalAborted: tx.totalAborted });
db.adminCommand({ getParameter: 1, transactionLifetimeLimitSeconds: 1 }).transactionLifetimeLimitSeconds;   // 60
db.adminCommand({ getParameter: 1, maxTransactionLockRequestTimeoutMillis: 1 }).maxTransactionLockRequestTimeoutMillis;   // 5
db.currentOp({ "transaction.parameters.txnNumber": { $exists: true } }).inprog.length;   // 0 open transactions now


/* ============================================================
   CLEANUP
   ============================================================ */
db.l14_orders.drop(); db.l14_products.drop(); db.l14_tmp.drop(); db.l14_new.drop();

/* ------------------------------------------------------------
   DONE. Next: 02_Two_Sessions_Demo.js (two shell windows), then Exercises.js
   ------------------------------------------------------------ */
