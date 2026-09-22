/* ============================================================
   LEVEL 14 - TRANSACTIONS  |  Exercises.js
   ------------------------------------------------------------
   Try each question in the "YOUR ANSWER" area FIRST.
   Then scroll down to SOLUTIONS and compare.
   Works on copies l14_ex_accounts / l14_ex_orders / l14_ex_products
   (dropped at the end).
   ============================================================ */

use("companyDB");
db.l14_ex_accounts.drop();
db.l14_ex_accounts.insertMany([ { _id: "A", balance: 1000 }, { _id: "B", balance: 500 } ]);
db.orders.aggregate([ { $out: "l14_ex_orders" } ]);
db.products.aggregate([ { $out: "l14_ex_products" } ]);

/* ------------------------------------------------------------
   QUESTIONS
   ------------------------------------------------------------
   Q1.  Transfer 300 from account A to B with the CORE API. Show the balances
        inside the session before commit and from outside (plain db) before and
        after commit.
   Q2.  Write transfer(from, to, amount) with withTransaction that throws (and
        therefore aborts) when the source balance would go negative. Call it with
        200 (ok) and with 5000 (fails). Balances must stay consistent (sum 1500).
   Q3.  Cancel order 1015 AND restore its items' stock in one transaction
        (l14_ex_orders / l14_ex_products). Verify stock of Chair (4) went 20 -> 24.
   Q4.  Start a transaction that updates product 1, then in a SECOND session try
        to update product 1 in another transaction. Catch the error, print its
        code name and error labels, then abort/commit correctly.
   Q5.  Prove snapshot isolation: read product 2's price in a snapshot transaction,
        change it from outside, read it again inside (unchanged), commit, read
        outside (changed).
   Q6.  Inside a transaction, try db.l14_ex_orders.count() - what happens? Which
        method should you use instead?
   Q7.  (Think) You need to update 50 000 documents "all or nothing". Should you
        use one transaction? What are the alternatives?
   Q8.  (Think) Why does "read a document, decide in the application, then write
        it back" inside a transaction still need retry logic?
   ------------------------------------------------------------ */

// YOUR ANSWERS HERE (write below, run, compare)










/* ============================================================
   SOLUTIONS
   ============================================================ */

// Q1
const s1 = db.getMongo().startSession();
s1.startTransaction({ writeConcern: { w: "majority" } });
const acc = s1.getDatabase("companyDB").l14_ex_accounts;
acc.updateOne({ _id: "A" }, { $inc: { balance: -300 } });
acc.updateOne({ _id: "B" }, { $inc: { balance: 300 } });
acc.find({}, { balance: 1 }).toArray();                     // inside: A 700, B 800
db.l14_ex_accounts.find({}, { balance: 1 }).toArray();      // outside: A 1000, B 500
s1.commitTransaction(); s1.endSession();
db.l14_ex_accounts.find({}, { balance: 1 }).toArray();      // outside now: A 700, B 800

// Q2
function transfer(from, to, amount) {
    const s = db.getMongo().startSession();
    try {
        s.withTransaction(() => {
            const a = s.getDatabase("companyDB").l14_ex_accounts;
            const r = a.updateOne({ _id: from, balance: { $gte: amount } }, { $inc: { balance: -amount } });
            if (r.matchedCount === 0) throw new Error("insufficient funds in " + from);
            a.updateOne({ _id: to }, { $inc: { balance: amount } });
        });
        return "ok";
    } catch (e) { return "FAILED: " + e.message; } finally { s.endSession(); }
}
transfer("A", "B", 200);                                     // ok       -> A 500, B 1000
transfer("A", "B", 5000);                                    // FAILED   -> unchanged
db.l14_ex_accounts.aggregate([ { $group: { _id: null, total: { $sum: "$balance" } } } ]);   // 1500

// Q3
const s3 = db.getMongo().startSession();
s3.withTransaction(() => {
    const o = s3.getDatabase("companyDB").l14_ex_orders, p = s3.getDatabase("companyDB").l14_ex_products;
    const order = o.findOne({ _id: 1015, status: "Pending" });
    if (!order) throw new Error("order not pending");
    order.items.forEach(i => p.updateOne({ _id: i.productId }, { $inc: { stock: i.qty } }));
    o.updateOne({ _id: 1015 }, { $set: { status: "Cancelled" } });
});
s3.endSession();
db.l14_ex_products.findOne({ _id: 4 }, { _id: 0, stock: 1 });   // 24
db.l14_ex_orders.findOne({ _id: 1015 }, { _id: 0, status: 1 }); // Cancelled

// Q4
const sA = db.getMongo().startSession(), sB = db.getMongo().startSession();
sA.startTransaction(); sB.startTransaction();
sA.getDatabase("companyDB").l14_ex_products.updateOne({ _id: 1 }, { $inc: { stock: -1 } });
try {
    sB.getDatabase("companyDB").l14_ex_products.updateOne({ _id: 1 }, { $inc: { stock: -1 } });
} catch (e) {
    print("EXPECTED ERROR:", e.codeName, JSON.stringify(e.errorLabels));   // WriteConflict ["TransientTransactionError"]
}
sB.abortTransaction(); sA.commitTransaction(); sA.endSession(); sB.endSession();

// Q5
const s5 = db.getMongo().startSession();
s5.startTransaction({ readConcern: { level: "snapshot" } });
const p5 = s5.getDatabase("companyDB").l14_ex_products;
p5.findOne({ _id: 2 }, { _id: 0, price: 1 });               // 1000
db.l14_ex_products.updateOne({ _id: 2 }, { $set: { price: 1100 } });
p5.findOne({ _id: 2 }, { _id: 0, price: 1 });               // 1000 (snapshot)
s5.commitTransaction(); s5.endSession();
db.l14_ex_products.findOne({ _id: 2 }, { _id: 0, price: 1 });   // 1100

// Q6
const s6 = db.getMongo().startSession();
s6.startTransaction();
try { s6.getDatabase("companyDB").l14_ex_orders.count(); } catch (e) { print("EXPECTED ERROR:", e.message.substring(0, 60)); }
// The error ABORTED the transaction on the server -> start a fresh one for the correct call
try { s6.abortTransaction(); } catch (e) { print("(already aborted by the server:", e.codeName + ")"); }
s6.startTransaction();
s6.getDatabase("companyDB").l14_ex_orders.countDocuments();  // 19 - use countDocuments (an aggregation) instead of count()
s6.abortTransaction(); s6.endSession();

// Q7
// One huge transaction = long-held snapshot, cache pressure, 60 s limit, everything else blocked on those documents.
// Alternatives: batches of updateMany with an idempotent marker (re-runnable), a "pending -> applied" two-phase flag,
// $merge into a new collection then rename, or accept eventual consistency. Reserve transactions for small, hot, critical units.

// Q8
// Snapshot isolation reads the snapshot; another writer can commit a change to that document after your read. Your later
// write then fails with WriteConflict (transient) and the whole transaction must be re-run from the read - hence retry logic
// (withTransaction) and idempotent callbacks. Use conditional updates ({ _id, stock: { $gte: qty } }) to keep the check atomic.

db.l14_ex_accounts.drop(); db.l14_ex_orders.drop(); db.l14_ex_products.drop();
