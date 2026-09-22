/* ============================================================
   LEVEL 18 - SHARDING  |  Exercises.js   (run on mongos: --port 27030)
   ------------------------------------------------------------
   Try each question in the "YOUR ANSWER" area FIRST.
   Then scroll down to SOLUTIONS and compare.
   Uses database shardEx (dropped at the end).
   ============================================================ */

use("shardEx");
db.getSiblingDB("shardEx").dropDatabase();
sh.enableSharding("shardEx");

/* ------------------------------------------------------------
   QUESTIONS
   ------------------------------------------------------------
   Q1.  Shard shardEx.users on { email: "hashed" }, insert 20 000 users
        (email "u<i>@x.com", country cycling IN/US/DE), and show the
        distribution per shard.
   Q2.  Which of these is targeted? Prove it with explain:
          a) find({ email: "u77@x.com" })   b) find({ country: "IN" })
          c) find({ email: { $gt: "u1" } })
   Q3.  Shard shardEx.logs on { app: 1, ts: 1 } (ranged). Split at
        { app: "billing", ts: MinKey } and { app: "web", ts: MinKey }, move the
        "web" chunk to the other shard, insert logs for apps auth/billing/web
        and show getShardDistribution().
   Q4.  Try to create a unique index on shardEx.users { username: 1 }. What
        happens? Create one that is allowed.
   Q5.  Stop the balancer, verify, start it again.
   Q6.  Which shard holds shardEx's unsharded collections? Insert into
        shardEx.config_flags and find out from config.databases.
   Q7.  (Think) You shard "clicks" on { ts: 1 } (a timestamp). What happens to
        writes and why? Propose two better keys and their trade-offs.
   Q8.  (Think) A query hits all shards although it contains the shard key
        field. Give two possible reasons.
   ------------------------------------------------------------ */

// YOUR ANSWERS HERE (write below, run, compare)










/* ============================================================
   SOLUTIONS
   ============================================================ */
function route(x) { const wp = x.queryPlanner.winningPlan; return wp.stage + " " + JSON.stringify(wp.shards ? wp.shards.map(s => s.shardName) : (wp.inputStage && wp.inputStage.shards ? wp.inputStage.shards.map(s => s.shardName) : [])); }
const cfg = db.getSiblingDB("config");

// Q1
sh.shardCollection("shardEx.users", { email: "hashed" });
db.users.insertMany(Array.from({ length: 20000 }, (_, i) => ({ email: "u" + i + "@x.com", username: "user" + i, country: ["IN", "US", "DE"][i % 3] })), { ordered: false });
db.users.getShardDistribution();                           // ~10000 per shard

// Q2
route(db.users.find({ email: "u77@x.com" }).explain());            // SINGLE_SHARD - equality on the hashed key
route(db.users.find({ country: "IN" }).explain());                 // SHARD_MERGE  - not the shard key
route(db.users.find({ email: { $gt: "u1" } }).explain());          // SHARD_MERGE  - range on a hashed key cannot be targeted

// Q3
sh.shardCollection("shardEx.logs", { app: 1, ts: 1 });
sh.splitAt("shardEx.logs", { app: "billing", ts: MinKey });
sh.splitAt("shardEx.logs", { app: "web", ts: MinKey });
const prim = cfg.databases.findOne({ _id: "shardEx" }).primary, other = prim === "shard1rs" ? "shard2rs" : "shard1rs";
sh.moveChunk("shardEx.logs", { app: "web", ts: MinKey }, other);
db.logs.insertMany(Array.from({ length: 3000 }, (_, i) => ({ app: ["auth", "billing", "web"][i % 3], ts: new Date(Date.now() + i * 1000), msg: "m" + i })));
db.logs.getShardDistribution();                            // web (1000 docs) on the other shard, auth + billing (2000) on the primary shard

// Q4
try { db.users.createIndex({ username: 1 }, { unique: true }); } catch (e) { print("EXPECTED ERROR:", e.message.substring(0, 80)); }   // must be prefixed by the shard key
db.users.createIndex({ email: 1, username: 1 }, { unique: true });   // allowed: shard key first (uniqueness per email is enforced anyway)

// Q5
sh.stopBalancer(); sh.getBalancerState();                  // false
sh.startBalancer(); sh.getBalancerState();                 // true

// Q6
db.config_flags.insertOne({ _id: "beta", on: true });
cfg.databases.findOne({ _id: "shardEx" }).primary;         // the primary shard holds every unsharded collection of shardEx

// Q7
// All inserts have increasing ts -> they land in the LAST chunk on ONE shard (hot shard); the balancer keeps moving that chunk
// away while new writes hit the new last chunk. Better: { ts: "hashed" } (even writes, but time-range queries broadcast) or a
// compound key { userId: 1, ts: 1 } / { region: 1, ts: 1 } (writes spread over users/regions, time ranges targeted per user/region).

// Q8
// (1) The predicate is a RANGE (or $ne/$nin/regex) on a HASHED key, or a range on a non-prefix field of a compound key;
// (2) the shard key field is used inside $or with other conditions / in an $expr, or the query has an inequality that spans
//     all chunks - mongos can only target when it can compute the chunk ranges from the filter.

db.getSiblingDB("shardEx").dropDatabase();
