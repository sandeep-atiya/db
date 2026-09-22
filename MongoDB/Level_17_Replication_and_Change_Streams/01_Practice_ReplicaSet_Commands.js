/* ============================================================
   LEVEL 17 - REPLICATION  |  01_Practice_ReplicaSet_Commands.js
   ------------------------------------------------------------
   Topics : rs.status / rs.conf / db.hello, the oplog (format,
            idempotency, window), write concern, read concern,
            read preference, reconfig, stepDown / freeze,
            replication metrics

   HOW TO PRACTICE: block by block, predict first.
   Runs on the ONE-member replica set rs0 of the Docker setup:
   everything works, but some operations answer "there is nobody
   else" - those are shown as EXPECTED errors. The 3-node lab
   (docker-compose.replset.yml + 03_Failover_Lab.js) shows real
   failover.
   ============================================================ */

use("companyDB");


/* ============================================================
   1. WHO IS WHO
   ============================================================ */

const h = db.hello();
({ setName: h.setName, isWritablePrimary: h.isWritablePrimary, primary: h.primary, hosts: h.hosts, me: h.me });

const st = rs.status();
({ set: st.set, myState: st.myState, term: st.term, members: st.members.map(m => ({ name: m.name, state: m.stateStr, health: m.health, optime: m.optimeDate, uptime: m.uptime })) });
// myState 1 = PRIMARY, 2 = SECONDARY, 7 = ARBITER, 0 STARTUP, 5 STARTUP2, 3 RECOVERING, 9 ROLLBACK

const cfg = rs.conf();
({ _id: cfg._id, version: cfg.version, members: cfg.members.map(m => ({ _id: m._id, host: m.host, priority: m.priority, votes: m.votes, hidden: m.hidden, arbiterOnly: m.arbiterOnly, delay: m.secondaryDelaySecs })),
   electionTimeoutMillis: cfg.settings.electionTimeoutMillis, heartbeatIntervalMillis: cfg.settings.heartbeatIntervalMillis });
// One member with priority 1, 1 vote -> it is always primary. electionTimeout 10000 ms, heartbeat 2000 ms.


/* ============================================================
   2. THE OPLOG
   ============================================================ */

rs.printReplicationInfo();                                 // configured oplog size, log length (window) start -> end
const oplog = db.getSiblingDB("local").oplog.rs;
oplog.stats().capped;                                      // true
Math.round(oplog.stats().maxSize / 1048576) + " MB";       // configured size (default ~5 % of disk, min 990 MB, max 50 GB)

// Make three different writes and look at how they were recorded
db.l17_demo.drop();
db.l17_demo.insertOne({ _id: 1, qty: 1, tags: ["a"] });
db.l17_demo.updateOne({ _id: 1 }, { $inc: { qty: 5 }, $push: { tags: "b" } });
db.l17_demo.deleteOne({ _id: 1 });
oplog.find({ ns: "companyDB.l17_demo" }).sort({ $natural: -1 }).limit(3).toArray().reverse().map(e => ({ op: e.op, ns: e.ns, o: e.o, o2: e.o2, ts: e.ts, wall: e.wall }));
// op: 'i' insert (o = full document) ; 'u' update (o = { $v: 2, diff: { u: { qty: 6 }, ... } } = the RESULTING values, NOT "$inc 5") ; 'd' delete (o = { _id })
// -> oplog entries are IDEMPOTENT: replaying them twice gives the same result. That is why $inc becomes "set qty to 6".

// Commands are logged too (op: 'c'): the drop above
oplog.find({ op: "c", "o.drop": "l17_demo" }).sort({ $natural: -1 }).limit(1).toArray().map(e => e.o);

// How much oplog time do we have? (last - first entry)
const first = oplog.find().sort({ $natural: 1 }).limit(1).next().ts, last = oplog.find().sort({ $natural: -1 }).limit(1).next().ts;
"oplog window: " + Math.round((last.getHighBits() - first.getHighBits()) / 3600) + " hours";
// On a busy production system this window is what decides whether a secondary that was down for N hours can catch up.


/* ============================================================
   3. WRITE CONCERN
   ============================================================ */

db.l17_demo.insertOne({ _id: 2, w: "1" }, { writeConcern: { w: 1 } });                                   // ack by the primary only
db.l17_demo.insertOne({ _id: 3, w: "majority" }, { writeConcern: { w: "majority", j: true, wtimeout: 5000 } });   // ack after a majority (here: 1 of 1)
try {
    db.l17_demo.insertOne({ _id: 4, w: "2" }, { writeConcern: { w: 2, wtimeout: 2000 } });               // there is no second member
} catch (e) {
    print("EXPECTED ERROR:", e.codeName, "-", e.message.substring(0, 60));                                // UnsatisfiableWriteConcern / WriteConcernTimeout
}
db.l17_demo.countDocuments({ _id: 4 });                    // note: with a TIMEOUT the write itself may still be applied (1) - the error is about the acknowledgement
// Cluster-wide defaults (5.0+: majority unless arbiters make it unsafe)
db.adminCommand({ getDefaultRWConcern: 1 }).defaultWriteConcern;


/* ============================================================
   4. READ CONCERN and READ PREFERENCE
   ============================================================ */

db.l17_demo.find({ _id: 3 }).readConcern("local").toArray().length;        // 1 - latest data of this node
db.l17_demo.find({ _id: 3 }).readConcern("majority").toArray().length;     // 1 - only majority-committed data (cannot be rolled back)
db.l17_demo.find({ _id: 3 }).readConcern("linearizable").toArray().length; // 1 - primary, waits for prior majority writes (single document reads)

// Read preference: with one member, secondary reads simply have no candidate
db.getMongo().setReadPref("secondaryPreferred");
db.l17_demo.countDocuments();                              // works - falls back to the primary
db.getMongo().setReadPref("primary");
try {
    db.l17_demo.find().readPref("secondary").toArray();    // strict "secondary": nobody can serve it
} catch (e) {
    print("EXPECTED ERROR:", e.message.substring(0, 70));
}
// In a connection string:  ?readPreference=secondaryPreferred&maxStalenessSeconds=90&readPreferenceTags=region:eu


/* ============================================================
   5. RECONFIG  (change priority / election timeout, then restore)
   ============================================================ */

const c1 = rs.conf();
c1.members[0].priority = 2;                                // higher priority -> preferred primary (no effect with one member)
c1.settings.electionTimeoutMillis = 8000;
rs.reconfig(c1);                                           // { ok: 1 } - needs majority; can trigger an election on multi-member sets
rs.conf().members[0].priority;                             // 2
rs.conf().settings.electionTimeoutMillis;                  // 8000
const c2 = rs.conf(); c2.members[0].priority = 1; c2.settings.electionTimeoutMillis = 10000; rs.reconfig(c2);   // restore
rs.conf().version;                                         // version increases with every reconfig

// Adding a member (do NOT run here - the host does not exist):   rs.add({ host: "host.docker.internal:27022", priority: 0, hidden: true })


/* ============================================================
   6. stepDown / freeze  (nobody else can take over here)
   ============================================================ */

try {
    rs.stepDown(30);                                       // asks the primary to step down for 30 s
} catch (e) {
    print("EXPECTED ERROR:", e.codeName, "-", e.message.substring(0, 60));   // No electable secondaries caught up
}
try {
    rs.freeze(30);                                         // "do not become primary for 30 s" - only meaningful on a SECONDARY
} catch (e) {
    print("EXPECTED ERROR:", e.codeName, "-", e.message.substring(0, 60));   // NotSecondary: Cannot freeze node when primary
}
// (rs.freeze(0) on a secondary unfreezes it.)


/* ============================================================
   7. REPLICATION METRICS TO WATCH
   ============================================================ */

rs.printSecondaryReplicationInfo();                        // per secondary: "0 secs behind the primary" - none here
const repl = db.serverStatus().repl;
({ setName: repl.setName, isWritablePrimary: repl.isWritablePrimary, hosts: repl.hosts, primary: repl.primary, electionId: repl.electionId });
const m = db.serverStatus().metrics.repl;
({ applyBatches: m.apply && m.apply.batches, bufferCount: m.buffer && m.buffer.count, networkOps: m.network && m.network.ops });
db.serverStatus().opcounters;                              // insert/query/update/delete/command counters
db.serverStatus().opcountersRepl;                          // the same counters for operations APPLIED FROM THE OPLOG (0 on a primary)
db.adminCommand({ replSetGetStatus: 1 }).members[0].optimeDate;   // the same thing rs.status() shows


/* ============================================================
   CLEANUP
   ============================================================ */
db.l17_demo.drop();

/* ------------------------------------------------------------
   DONE. Next: 02_Practice_Change_Streams.js, then the 3-node lab.
   ------------------------------------------------------------ */
