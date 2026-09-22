/* ============================================================
   LEVEL 14 - TRANSACTIONS  |  02_Two_Sessions_Demo.js
   ------------------------------------------------------------
   A COMMENTED TUTORIAL for TWO mongosh windows (A and B).
   Do NOT run this file top to bottom - copy the blocks into the
   window named in each step, in order. Watch what the other
   window sees.

   Setup (either window):
       use("companyDB")
       db.products.aggregate([ { $out: "l14_demo" } ])
   ============================================================ */


/* ------------------------------------------------------------
   DEMO 1 - VISIBILITY: uncommitted writes are invisible
   ------------------------------------------------------------ */

// [A] open a transaction and change a document
//     const s = db.getMongo().startSession();
//     s.startTransaction({ readConcern: { level: "snapshot" }, writeConcern: { w: "majority" } });
//     const p = s.getDatabase("companyDB").l14_demo;
//     p.updateOne({ _id: 1 }, { $set: { price: 70000 } });
//     p.findOne({ _id: 1 }, { price: 1 })                  // 70000 inside A

// [B] read the same document (no transaction)
//     db.l14_demo.findOne({ _id: 1 }, { price: 1 })         // 75000 - B cannot see A's uncommitted write (no dirty reads)

// [A] commit
//     s.commitTransaction()

// [B] read again
//     db.l14_demo.findOne({ _id: 1 }, { price: 1 })         // 70000 now


/* ------------------------------------------------------------
   DEMO 2 - A PLAIN WRITE BLOCKS BEHIND AN OPEN TRANSACTION
   ------------------------------------------------------------ */

// [A] (reuse s, or start a new session) modify product 2 inside a transaction and DO NOT commit yet
//     s.startTransaction();
//     s.getDatabase("companyDB").l14_demo.updateOne({ _id: 2 }, { $inc: { stock: -1 } })

// [B] try a normal update on the SAME document
//     db.l14_demo.updateOne({ _id: 2 }, { $inc: { stock: -1 } })
//     -> B HANGS. It is waiting for A's transaction to finish (a plain write retries the write conflict internally).

// [A] commit (or abort) - B's prompt returns immediately afterwards
//     s.commitTransaction()

// [B] check the result: both decrements applied in order (A first, then B)
//     db.l14_demo.findOne({ _id: 2 }, { stock: 1 })         // 98

// Variation: in [B] use a second TRANSACTION instead of a plain write:
//     const s2 = db.getMongo().startSession(); s2.startTransaction();
//     s2.getDatabase("companyDB").l14_demo.updateOne({ _id: 2 }, { $inc: { stock: -1 } })
//     -> does NOT hang: immediate "WriteConflict" error (label TransientTransactionError) -> s2.abortTransaction() and retry later.


/* ------------------------------------------------------------
   DEMO 3 - THE 60-SECOND LIFETIME
   ------------------------------------------------------------ */

// [A] start a transaction, write, then WAIT more than 60 seconds
//     s.startTransaction();
//     s.getDatabase("companyDB").l14_demo.updateOne({ _id: 3 }, { $set: { note: "slow" } })
//     ... wait 61+ seconds (get a coffee) ...
//     s.commitTransaction()
//     -> MongoServerError: Transaction with { txnNumber: N } has been aborted (NoSuchTransaction) - the server aborted it
//        after transactionLifetimeLimitSeconds (60). The write never happened:
//     db.l14_demo.findOne({ _id: 3 }, { note: 1 })          // no note

// [B] meanwhile you can watch it:
//     db.currentOp({ "transaction.parameters.txnNumber": { $exists: true } }).inprog.map(o => ({ txn: o.transaction.parameters.txnNumber, timeOpen: o.transaction.timeOpenMicros }))
//     db.serverStatus().transactions.currentOpen


/* ------------------------------------------------------------
   DEMO 4 - SNAPSHOT: repeatable reads inside, phantoms impossible
   ------------------------------------------------------------ */

// [A] start with readConcern snapshot, count Furniture products
//     s.startTransaction({ readConcern: { level: "snapshot" } });
//     s.getDatabase("companyDB").l14_demo.countDocuments({ category: "Furniture" })   // 3

// [B] insert a new Furniture product (normal write, committed)
//     db.l14_demo.insertOne({ _id: 99, name: "Stool", category: "Furniture", price: 900, stock: 4 })

// [A] count again inside the SAME transaction
//     s.getDatabase("companyDB").l14_demo.countDocuments({ category: "Furniture" })   // still 3 - no phantom read
//     s.commitTransaction()
//     s.getDatabase("companyDB").l14_demo.countDocuments({ category: "Furniture" })   // 4 after the transaction


/* ------------------------------------------------------------
   DEMO 5 - withTransaction retries a conflict for you
   ------------------------------------------------------------ */

// [A] hold a transaction open on product 4 (do not commit yet)
//     s.startTransaction();
//     s.getDatabase("companyDB").l14_demo.updateOne({ _id: 4 }, { $inc: { stock: -1 } })

// [B] run a withTransaction on the same document with a visible retry counter
//     let attempts = 0;
//     const sb = db.getMongo().startSession();
//     sb.withTransaction(() => { attempts++; sb.getDatabase("companyDB").l14_demo.updateOne({ _id: 4 }, { $inc: { stock: -1 } }); });
//     -> B keeps retrying (WriteConflict = transient) ...

// [A] commit within a few seconds
//     s.commitTransaction()

// [B] ... and completes. Check:
//     attempts                                              // > 1
//     db.l14_demo.findOne({ _id: 4 }, { stock: 1 })         // 18


/* ------------------------------------------------------------
   Cleanup (either window):   db.l14_demo.drop();  s.endSession()
   ------------------------------------------------------------ */
