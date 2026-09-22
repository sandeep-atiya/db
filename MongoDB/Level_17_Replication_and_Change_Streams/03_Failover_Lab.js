/* ============================================================
   LEVEL 17  |  03_Failover_Lab.js  -  a REAL failover on the 3-node set
   ------------------------------------------------------------
   Prerequisite (in this folder):
       docker compose -f docker-compose.replset.yml up -d
   Connect to the SET (not to one node) so the shell follows elections:
       mongosh "mongodb://host.docker.internal:27021,host.docker.internal:27022,host.docker.internal:27023/?replicaSet=rs3"
   Then run the blocks below in that shell; the docker commands go
   in a PowerShell window. Steps marked [PS] are PowerShell.
   ============================================================ */

use("labdb");


/* ------------------------------------------------------------
   1. THE SET
   ------------------------------------------------------------ */
rs.status().members.map(m => ({ name: m.name, state: m.stateStr, health: m.health }));
// 27021 PRIMARY (priority 2), 27022 SECONDARY, 27023 SECONDARY
db.hello().primary;                                        // host.docker.internal:27021
rs.conf().members.map(m => ({ host: m.host, priority: m.priority, votes: m.votes }));


/* ------------------------------------------------------------
   2. WRITE WITH DIFFERENT WRITE CONCERNS, READ FROM A SECONDARY
   ------------------------------------------------------------ */
db.events.drop();
db.events.insertOne({ _id: 1, note: "w:1" }, { writeConcern: { w: 1 } });
db.events.insertOne({ _id: 2, note: "majority" }, { writeConcern: { w: "majority", wtimeout: 5000 } });   // 2 of 3 must ack
db.events.insertOne({ _id: 3, note: "all three" }, { writeConcern: { w: 3, wtimeout: 5000 } });          // all members
rs.printSecondaryReplicationInfo();                        // both secondaries "0 secs behind the primary"

db.events.find().readPref("secondary").toArray().length;   // 3 - served by a secondary (may be stale in general)
db.events.find().readPref("secondary").readConcern("majority").toArray().length;   // majority-committed view


/* ------------------------------------------------------------
   3. FAILOVER DRILL
   ------------------------------------------------------------ */
// [PS]  docker stop mongo-rs1            <- kill the primary
// Wait ~10-12 s (electionTimeoutMillis), then:
rs.status().members.map(m => ({ name: m.name, state: m.stateStr, health: m.health }));
// 27021 (not reachable/healthy) - one of 27022 / 27023 is PRIMARY now; the term increased:
rs.status().term;
db.hello().primary;                                        // the new primary - the shell reconnected by itself (that is what ?replicaSet= does)

// Writes work again (during the election they would have failed with NotWritablePrimary / retried by retryWrites)
db.events.insertOne({ _id: 4, note: "written on the new primary" }, { writeConcern: { w: "majority" } });
// w: 3 can no longer be satisfied (only 2 members up):
try { db.events.insertOne({ _id: 5, note: "w3" }, { writeConcern: { w: 3, wtimeout: 3000 } }); } catch (e) { print("EXPECTED ERROR:", e.codeName); }
db.events.countDocuments({ _id: 5 });                      // 1 - applied, just not acknowledged by 3 (wtimeout is about the ack)

// [PS]  docker start mongo-rs1           <- the old primary comes back
// After a few seconds it rejoins as a SECONDARY, catches up from the oplog, and because its priority (2) is the highest
// it will win an election ~10 s later and become primary again (priority takeover):
rs.status().members.map(m => ({ name: m.name, state: m.stateStr }));
db.hello().primary;                                        // back to host.docker.internal:27021 after the takeover
db.events.countDocuments();                                // 5 on every member - rs1 replayed what it missed


/* ------------------------------------------------------------
   4. WHAT HAPPENS WITHOUT A MAJORITY
   ------------------------------------------------------------ */
// [PS]  docker stop mongo-rs2 ; docker stop mongo-rs3      <- two of three down: no majority
rs.status().members.map(m => ({ name: m.name, state: m.stateStr }));
// 27021 steps down to SECONDARY on its own: a primary that cannot see a majority must not accept writes (split-brain protection)
try { db.events.insertOne({ _id: 6 }); } catch (e) { print("EXPECTED ERROR:", e.codeName); }   // NotWritablePrimary
db.events.find().readPref("secondaryPreferred").count();  // reads of existing data still work
// [PS]  docker start mongo-rs2 ; docker start mongo-rs3    <- majority is back -> election -> writes resume


/* ------------------------------------------------------------
   5. RECONFIGURE: hidden / priority-0 / delayed member
   ------------------------------------------------------------ */
const c = rs.conf();
c.members[2].priority = 0;                                 // 27023 can never become primary ...
c.members[2].hidden = true;                                // ... and is invisible to clients (reporting / backup node)
c.members[2].secondaryDelaySecs = 120;                     // ... and applies the oplog 2 minutes late (protects against fat-finger deletes)
rs.reconfig(c);
rs.conf().members[2];
db.hello().hosts;                                          // only 27021 and 27022 are advertised now
// restore
const c2 = rs.conf(); c2.members[2].priority = 1; c2.members[2].hidden = false; c2.members[2].secondaryDelaySecs = 0; rs.reconfig(c2);


/* ------------------------------------------------------------
   6. PLANNED MAINTENANCE: stepDown instead of kill
   ------------------------------------------------------------ */
rs.stepDown(60);                                           // the primary steps down gracefully; no re-election of it for 60 s
db.hello().primary;                                        // a secondary became primary within ~1-2 s (no 10 s timeout: the primary asked for it)
// ... patch / restart the old primary now ...
// after 60 s the priority-2 member takes over again.


/* ------------------------------------------------------------
   7. CHANGE STREAMS SURVIVE FAILOVER
   ------------------------------------------------------------ */
// In this shell:  const s = db.events.watch();   then in a second shell insert documents, stop the primary, insert more.
// s.tryNext() keeps delivering events (with resume tokens) after the election - the driver resumes the stream automatically.

/* ------------------------------------------------------------
   Cleanup:   db.dropDatabase()      [PS] docker compose -f docker-compose.replset.yml down -v
   ------------------------------------------------------------ */
