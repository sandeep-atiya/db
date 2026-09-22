/* ============================================================
   LEVEL 17 - CHANGE STREAMS  |  02_Practice_Change_Streams.js
   ------------------------------------------------------------
   Topics : watch() on a collection / database / deployment,
            event anatomy, tryNext (non-blocking) vs next,
            pipelines on the stream, fullDocument: updateLookup,
            pre-images (fullDocumentBeforeChange), resume tokens
            (resumeAfter / startAfter), invalidate, use cases

   HOW TO PRACTICE: block by block, predict first.
   Uses a copy l17_orders (dropped at the end). Single window:
   we open a stream, make changes on the SAME connection, then
   read the events with tryNext(). A two-window version is at
   the bottom.
   ============================================================ */

use("companyDB");
db.orders.aggregate([ { $out: "l17_orders" } ]);


/* ============================================================
   1. OPEN A STREAM, MAKE CHANGES, READ THE EVENTS
   ============================================================ */

const cs = db.l17_orders.watch();                          // a cursor of future changes (needs a replica set)
cs.tryNext();                                              // null - nothing happened yet (tryNext never blocks; next() would wait)

db.l17_orders.insertOne({ _id: 3001, customerId: 1, status: "Pending", totalAmount: 100, items: [] });
db.l17_orders.updateOne({ _id: 3001 }, { $set: { status: "Completed" }, $inc: { totalAmount: 50 } });
db.l17_orders.deleteOne({ _id: 3001 });

const e1 = cs.tryNext();
({ operationType: e1.operationType, ns: e1.ns, documentKey: e1.documentKey, fullDocument: e1.fullDocument, clusterTime: e1.clusterTime, token: e1._id });
// insert: fullDocument = the inserted document, _id = the RESUME TOKEN
const e2 = cs.tryNext();
({ operationType: e2.operationType, updateDescription: e2.updateDescription, fullDocument: e2.fullDocument });
// update: updateDescription { updatedFields: { status, totalAmount: 150 }, removedFields: [], truncatedArrays: [] } - NO fullDocument by default
const e3 = cs.tryNext();
({ operationType: e3.operationType, documentKey: e3.documentKey });
// delete: only the documentKey
cs.tryNext();                                              // null again
cs.close();


/* ============================================================
   2. fullDocument: "updateLookup"  and  a PIPELINE on the stream
   ============================================================ */

// Only Completed-status changes on high-value orders, with the current full document attached to updates
const cs2 = db.l17_orders.watch([
    { $match: { operationType: { $in: ["insert", "update"] }, "fullDocument.status": "Completed", "fullDocument.totalAmount": { $gte: 1000 } } },
    { $project: { operationType: 1, "fullDocument._id": 1, "fullDocument.status": 1, "fullDocument.totalAmount": 1, updateDescription: 1 } }
], { fullDocument: "updateLookup" });

db.l17_orders.updateOne({ _id: 1015 }, { $set: { status: "Completed" } });       // 32000 Completed -> matches
db.l17_orders.updateOne({ _id: 1017 }, { $set: { note: "still pending" } });      // Pending -> filtered out
db.l17_orders.insertOne({ _id: 3002, status: "Completed", totalAmount: 50 });      // too small -> filtered out
db.l17_orders.insertOne({ _id: 3003, status: "Completed", totalAmount: 9000 });    // matches

let ev; const seen = [];
while ((ev = cs2.tryNext()) !== null) seen.push({ op: ev.operationType, id: ev.fullDocument._id, total: ev.fullDocument.totalAmount, updated: ev.updateDescription && ev.updateDescription.updatedFields });
seen;                                                      // [ update 1015 32000 {status: Completed}, insert 3003 9000 ]
cs2.close();
// CAUTION: updateLookup fetches the document when the event is READ - it may already contain later changes.


/* ============================================================
   3. PRE- AND POST-IMAGES  (6.0+): the exact before / after documents
   ============================================================ */

db.runCommand({ collMod: "l17_orders", changeStreamPreAndPostImages: { enabled: true } });   // the server stores pre-images in config.system.preimages
const cs3 = db.l17_orders.watch([ { $match: { operationType: "update" } } ], { fullDocument: "whenAvailable", fullDocumentBeforeChange: "whenAvailable" });
db.l17_orders.updateOne({ _id: 1001 }, { $set: { status: "Shipped" } });
const e4 = cs3.tryNext();
({ before: e4.fullDocumentBeforeChange.status, after: e4.fullDocument.status });   // Completed -> Shipped (exact versions, not a lookup)
cs3.close();
// "required" instead of "whenAvailable" errors if the image is missing (e.g. pre-images expired: expireAfterSeconds on the preimages collection).


/* ============================================================
   4. RESUME TOKENS: continue where you stopped
   ============================================================ */

const cs4 = db.l17_orders.watch();
db.l17_orders.insertOne({ _id: 3004, status: "Pending", totalAmount: 1 });
const ev4 = cs4.tryNext();
const token = ev4._id;                                     // persist THIS in your consumer after processing the event
cs4.close();                                               // consumer crashes / restarts ...

db.l17_orders.insertOne({ _id: 3005, status: "Pending", totalAmount: 2 });   // ... changes happen while it is down ...
db.l17_orders.insertOne({ _id: 3006, status: "Pending", totalAmount: 3 });

const cs5 = db.l17_orders.watch([], { resumeAfter: token });                   // ... and it resumes AFTER the last processed event
const missed = []; while ((ev = cs5.tryNext()) !== null) missed.push(ev.fullDocument._id);
missed;                                                    // [ 3005, 3006 ] - nothing lost
cs5.getResumeToken();                                      // the token of the last event returned (also available before any event: postBatchResumeToken)
cs5.close();
// startAfter: like resumeAfter but also works after an "invalidate" event. startAtOperationTime: resume from a cluster time (Timestamp).
// Tokens are only valid while the oplog still contains that entry -> size the oplog for your consumer's maximum downtime.


/* ============================================================
   5. DATABASE- AND DEPLOYMENT-LEVEL STREAMS, DDL EVENTS, INVALIDATE
   ============================================================ */

const csDb = db.watch([ { $match: { "ns.coll": /^l17_/ } } ]);   // every l17_* collection in companyDB
db.l17_other.insertOne({ x: 1 });
db.l17_other.renameCollection("l17_renamed");
db.l17_renamed.drop();
const dbEvents = []; while ((ev = csDb.tryNext()) !== null) dbEvents.push(ev.operationType + " " + (ev.ns.coll || "") + (ev.to ? " -> " + ev.to.coll : ""));
dbEvents;                                                  // [ 'insert l17_other', 'rename l17_other -> l17_renamed', 'drop l17_renamed' ]
csDb.close();

// A COLLECTION stream is INVALIDATED when its collection is dropped / renamed
db.l17_temp.insertOne({ a: 1 });
const csInv = db.l17_temp.watch();
db.l17_temp.drop();
const invEvents = [];
do { ev = csInv.tryNext(); if (ev) invEvents.push(ev.operationType); } while (ev && ev.operationType !== "invalidate");   // stop AT the invalidate event
invEvents;                                                 // [ 'drop', 'invalidate' ] - the cursor is closed by the server afterwards
try { csInv.tryNext(); } catch (e) { print("EXPECTED ERROR: stream is closed -", e.message.substring(0, 50)); }
// To continue after invalidate: open a new stream with startAfter: <the invalidate event's _id>.

// Whole deployment (all databases): db.getMongo().watch([...]) - needs privileges on all databases.


/* ============================================================
   6. TYPICAL CONSUMER LOOP  (blocking) - the shape you write in Node.js
   ============================================================ */

// mongosh, run in a SECOND window while the first window writes:
//   const stream = db.l17_orders.watch([], { fullDocument: "updateLookup" });
//   while (stream.hasNext()) { const e = stream.next(); printjson({ op: e.operationType, id: e.documentKey._id }); /* save e._id as the checkpoint */ }
//
// Node.js driver:
//   const stream = coll.watch([], { fullDocument: "updateLookup", startAfter: savedToken });
//   for await (const event of stream) { await handle(event); await saveToken(event._id); }
//   stream.on("error", ...)   // reconnect with the saved token; handle "invalidate" -> startAfter
//
// Use cases: invalidate a cache / update a search index (Elasticsearch, Atlas Search does it for you), push notifications,
// keep denormalised copies in sync (Level 13 extended references), event sourcing / Kafka connector (the official MongoDB Kafka Source Connector is a change stream).


/* ============================================================
   CLEANUP
   ============================================================ */
db.l17_orders.drop(); db.l17_other.drop(); db.l17_renamed.drop(); db.l17_temp.drop();

/* ------------------------------------------------------------
   DONE. Next: the 3-node lab (docker-compose.replset.yml + 03_Failover_Lab.js), then Exercises.js
   ------------------------------------------------------------ */
