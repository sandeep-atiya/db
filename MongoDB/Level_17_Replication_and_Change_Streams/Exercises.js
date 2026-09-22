/* ============================================================
   LEVEL 17 - REPLICATION & CHANGE STREAMS  |  Exercises.js
   ------------------------------------------------------------
   Try each question in the "YOUR ANSWER" area FIRST.
   Then scroll down to SOLUTIONS and compare.
   Q1-Q6 run on the main 1-node set; Q7-Q8 need the 3-node lab.
   ============================================================ */

use("companyDB");

/* ------------------------------------------------------------
   QUESTIONS
   ------------------------------------------------------------
   Q1.  Print, for every member of the current set: name, state, priority
        and votes (combine rs.status() and rs.conf()).
   Q2.  Find the LAST oplog entry for companyDB.employees after updating
        Rahul's salary by +1 (then restore it). Show op, ns and o.
   Q3.  Insert into l17_ex with w:"majority", j:true and a 3 s timeout, and
        then try w:5 - what error do you get?
   Q4.  Open a change stream on l17_ex that reports only deletes, delete two
        documents, read the events with tryNext and print their documentKeys.
   Q5.  Open a stream with fullDocument:"updateLookup", update a document twice
        in a row, then read the first event: what does fullDocument show, and why?
   Q6.  Simulate a consumer restart: read one event, save its token, close the
        stream, make 2 more changes, reopen with startAfter and count the events.
   Q7.  (3-node lab) Configure member 27023 as a hidden, priority-0 member and
        prove with db.hello().hosts that clients no longer see it. Restore.
   Q8.  (Think) A 3-member set loses its primary; the application uses w:1.
        Describe what the client experiences during the next 15 seconds and
        which writes might disappear.
   ------------------------------------------------------------ */

// YOUR ANSWERS HERE (write below, run, compare)










/* ============================================================
   SOLUTIONS
   ============================================================ */

// Q1
const st = rs.status(), cf = rs.conf();
st.members.map(m => { const c = cf.members.find(x => x.host === m.name); return { name: m.name, state: m.stateStr, priority: c.priority, votes: c.votes }; });

// Q2
db.employees.updateOne({ _id: 101 }, { $inc: { salary: 1 } });
db.getSiblingDB("local").oplog.rs.find({ ns: "companyDB.employees" }).sort({ $natural: -1 }).limit(1).toArray().map(e => ({ op: e.op, ns: e.ns, o: e.o }));
// op 'u', o: { $v: 2, diff: { u: { salary: 85001 } } } - the resulting value, idempotent
db.employees.updateOne({ _id: 101 }, { $inc: { salary: -1 } });

// Q3
db.l17_ex.drop();
db.l17_ex.insertMany([ { _id: 1 }, { _id: 2 }, { _id: 3 } ], { writeConcern: { w: "majority", j: true, wtimeout: 3000 } });
try { db.l17_ex.insertOne({ _id: 4 }, { writeConcern: { w: 5, wtimeout: 1000 } }); } catch (e) { print("EXPECTED ERROR:", e.codeName); }   // UnsatisfiableWriteConcern

// Q4
const q4 = db.l17_ex.watch([ { $match: { operationType: "delete" } } ]);
db.l17_ex.updateOne({ _id: 1 }, { $set: { touched: true } });    // filtered out
db.l17_ex.deleteOne({ _id: 2 }); db.l17_ex.deleteOne({ _id: 3 });
let ev, keys = []; while ((ev = q4.tryNext()) !== null) keys.push(ev.documentKey);
keys;                                                      // [ { _id: 2 }, { _id: 3 } ]
q4.close();

// Q5
const q5 = db.l17_ex.watch([], { fullDocument: "updateLookup" });
db.l17_ex.updateOne({ _id: 1 }, { $set: { v: 1 } });
db.l17_ex.updateOne({ _id: 1 }, { $set: { v: 2 } });
const first = q5.tryNext();
({ updatedFields: first.updateDescription.updatedFields, fullDocumentV: first.fullDocument.v });
// updatedFields says v: 1, but fullDocument shows v: 2 - updateLookup fetches the CURRENT document when the event is read.
q5.close();

// Q6
const q6 = db.l17_ex.watch();
db.l17_ex.insertOne({ _id: 10 });
const tok = q6.tryNext()._id; q6.close();
db.l17_ex.insertOne({ _id: 11 }); db.l17_ex.insertOne({ _id: 12 });
const q6b = db.l17_ex.watch([], { startAfter: tok });
let n = 0; while (q6b.tryNext() !== null) n++;
n;                                                         // 2
q6b.close();
db.l17_ex.drop();

// Q7  (in the lab shell)
// const c = rs.conf(); c.members[2].priority = 0; c.members[2].hidden = true; rs.reconfig(c);
// db.hello().hosts                                        // [ '...:27021', '...:27022' ] - 27023 is not advertised
// const c2 = rs.conf(); c2.members[2].priority = 1; c2.members[2].hidden = false; rs.reconfig(c2);

// Q8
// 0-10 s: heartbeats fail, no primary -> writes get NotWritablePrimary / network errors; drivers with retryWrites retry once,
// reads with primaryPreferred/secondary still work. ~10-12 s: election, new primary, driver topology updates, writes resume.
// Writes acknowledged by the OLD primary with w:1 in the last moments that were not yet replicated to the new primary are
// ROLLED BACK when the old primary rejoins (kept in rollback files, gone from the set). w:"majority" would have prevented that.
