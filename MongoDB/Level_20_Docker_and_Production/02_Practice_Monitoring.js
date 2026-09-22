/* ============================================================
   LEVEL 20 - PRODUCTION  |  02_Practice_Monitoring.js
   ------------------------------------------------------------
   Topics : serverStatus (connections, opcounters, memory, cache,
            queues, network, asserts), db/collection stats, logs,
            slow-op threshold, FCV, host / build info, currentOp,
            mongostat / mongotop, capacity numbers, the checklist

   HOW TO PRACTICE: block by block on the main practice server.
   ============================================================ */

use("companyDB");
const ss = db.serverStatus();
const MB = (b) => Math.round(b / 1048576);


/* ============================================================
   1. THE BIG PICTURE
   ============================================================ */

({ host: ss.host, version: ss.version, process: ss.process, uptimeHours: Math.round(ss.uptime / 3600 * 10) / 10, localTime: ss.localTime });
db.serverBuildInfo().version;
db.hostInfo().system;                                      // cpuArch, numCores, memSizeMB, hostname (the CONTAINER's view)
db.hostInfo().os;
db.adminCommand({ getParameter: 1, featureCompatibilityVersion: 1 }).featureCompatibilityVersion;   // { version: '8.0' } - raise it after upgrading binaries
db.adminCommand({ getCmdLineOpts: 1 }).argv;               // how mongod was started (replSet, bind_ip ...)


/* ============================================================
   2. CONNECTIONS  (each costs ~1 MB of server RAM)
   ============================================================ */

ss.connections;                                            // current, available, totalCreated, active, threaded ...
// Who is connected? appName / driver per connection (that is why appName in the URI matters)
db.getSiblingDB("admin").aggregate([
    { $currentOp: { allUsers: true, idleConnections: true, idleSessions: true } },
    { $group: { _id: { app: "$appName", driver: "$clientMetadata.driver.name" }, n: { $sum: 1 } } },
    { $sort: { n: -1 } }
]);
db.adminCommand({ getCmdLineOpts: 1 }).parsed.net;        // net.maxIncomingConnections (default 65536) is a CONFIG option, not a runtime parameter


/* ============================================================
   3. THROUGHPUT AND QUEUES
   ============================================================ */

ss.opcounters;                                             // since start: insert, query, update, delete, getmore, command
ss.opcountersRepl;                                         // applied from the oplog (secondaries)
ss.globalLock.currentQueue;                                // readers / writers WAITING for a ticket - should be ~0; sustained queues = saturation
ss.globalLock.activeClients;
ss.network ? { bytesInMB: MB(ss.network.bytesIn), bytesOutMB: MB(ss.network.bytesOut), requests: ss.network.numRequests } : null;
ss.metrics.document;                                       // documents deleted/inserted/returned/updated
ss.metrics.queryExecutor;                                  // scanned (index keys) vs scannedObjects (documents): a high ratio of scannedObjects/returned = missing indexes
({ docsReturned: ss.metrics.document.returned, scannedKeys: ss.metrics.queryExecutor.scanned, scannedDocs: ss.metrics.queryExecutor.scannedObjects,
   ratioScannedPerReturned: Math.round(ss.metrics.queryExecutor.scannedObjects / Math.max(1, ss.metrics.document.returned) * 10) / 10 });
// A quick "rate" sample: two readings 3 seconds apart (what mongostat does every second)
const a = db.serverStatus().opcounters; sleep(3000); const b = db.serverStatus().opcounters;
({ queriesPerSec: (b.query - a.query) / 3, commandsPerSec: (b.command - a.command) / 3 });


/* ============================================================
   4. MEMORY AND THE WIREDTIGER CACHE
   ============================================================ */

ss.mem;                                                    // resident / virtual MB of the process
const cache = ss.wiredTiger.cache;
({ maxMB: MB(cache["maximum bytes configured"]), usedMB: MB(cache["bytes currently in the cache"]), dirtyMB: MB(cache["tracked dirty bytes in the cache"]),
   usedPct: Math.round(cache["bytes currently in the cache"] / cache["maximum bytes configured"] * 100),
   readIntoCacheMB: MB(cache["bytes read into cache"]), writtenFromCacheMB: MB(cache["bytes written from cache"]),
   pagesEvictedByAppThreads: cache["pages evicted by application threads"] });
// Healthy: used < 80 % of max, dirty < 5 %, "pages evicted by application threads" not growing fast (= cache pressure, working set > RAM).
db.hostInfo().system.memSizeMB;                            // RAM the server sees: the cache max should be ~50 % of it minus 1 GB (or what you configured)
ss.tcmalloc ? { heapMB: MB(ss.tcmalloc.generic.heap_size), freeMB: MB(ss.tcmalloc.tcmalloc.pageheap_free_bytes) } : "no tcmalloc section";


/* ============================================================
   5. STORAGE: database and collection sizes
   ============================================================ */

db.stats({ scale: 1024 * 1024 });                          // collections, objects, dataSize / storageSize / indexSize / totalSize in MB, fsUsedSize / fsTotalSize
db.getCollectionNames().map(c => { const s = db[c].stats({ scale: 1024 }); return { coll: c, docs: s.count, dataKB: s.size, storageKB: s.storageSize, indexKB: s.totalIndexSize, avgObjBytes: Math.round(s.avgObjSize || 0) }; });
// Compression: dataSize vs storageSize (WiredTiger snappy/zstd); free space inside files:
db.orders.stats().wiredTiger["block-manager"]["file bytes available for reuse"];
// Disk: alert at 70-80 % of fsTotalSize
const s = db.stats(); ({ fsUsedPct: Math.round(s.fsUsedSize / s.fsTotalSize * 100), fsTotalGB: Math.round(s.fsTotalSize / 1073741824) });


/* ============================================================
   6. LOGS AND SLOW OPERATIONS
   ============================================================ */

db.adminCommand({ getLog: "global" }).log.slice(-3).map(l => { const j = JSON.parse(l); return { t: j.t.$date, c: j.c, msg: j.msg }; });   // last 3 lines, JSON log format
db.adminCommand({ getLog: "*" }).names;                    // available logs: global, startupWarnings
db.adminCommand({ getLog: "startupWarnings" }).log.length; // warnings at startup (THP, ulimits, no auth ...) - read them on every new server!
db.getProfilingStatus().slowms;                            // 100 ms default: slower ops are logged ("Slow query") even with profiling off
db.setProfilingLevel(0, { slowms: 100 });                  // slowms / sampleRate are SERVER-wide (config: operationProfiling.slowOpThresholdMs); runtime changes are lost on restart
db.getProfilingStatus();                                   // { was: 0, slowms: 100, sampleRate: 1 } - Level 12
// db.adminCommand({ logRotate: 1 })                       // rotate the log file (file logging; Docker logs go to stdout)


/* ============================================================
   7. WHAT IS RUNNING NOW
   ============================================================ */

db.currentOp({ active: true }).inprog.filter(o => o.ns && !o.ns.startsWith("admin") && !o.ns.startsWith("local")).map(o => ({ opid: o.opid, op: o.op, ns: o.ns, secs: o.secs_running, plan: o.planSummary }));
db.currentOp({ active: true, secs_running: { $gt: 5 } }).inprog.length;   // long runners: candidates for db.killOp(opid)
db.currentOp({ waitingForLock: true }).inprog.length;                      // lock waits
db.adminCommand({ connPoolStats: 1 }).totalInUse;                          // outgoing connections (replication, sharding)


/* ============================================================
   8. mongostat / mongotop  (run from PowerShell, inside the container)
   ============================================================ */

// docker exec mongo-practice mongostat --rowcount 5 1        -> per-second insert query update delete getmore command | dirty used (cache %) | qrw arw (queues) | conn
// docker exec mongo-practice mongotop 2 --rowcount 3         -> read/write time per collection
// Both accept --uri "mongodb://user:pw@host:27017/?authSource=admin" on secured servers.


/* ============================================================
   9. REPLICATION HEALTH IN ONE LINE  (Level 17)
   ============================================================ */

rs.status().members.map(m => ({ name: m.name, state: m.stateStr, health: m.health, lagSecs: m.optimeDate ? Math.round((rs.status().members[0].optimeDate - m.optimeDate) / 1000) : null }));
ss.repl ? { primary: ss.repl.primary, isWritablePrimary: ss.repl.isWritablePrimary } : "standalone";


/* ============================================================
   10. THE PRODUCTION CHECKLIST  (recite it)
   ============================================================ */

print(`
ARCHITECTURE  3-member replica set across AZs; shard only with a good key; mongos next to apps; config servers separate
SECURITY      auth + least privilege, keyFile/x509, TLS, private network + firewall, encryption at rest, audit, secrets mgmt
SCHEMA/INDEX  model for queries, ESR indexes, no unbounded arrays, validation, $indexStats reviews
PERFORMANCE   working set in RAM (cache ~50% RAM - 1GB), SSD/IOPS, pooled connections, maxTimeMS, chosen read/write concerns
DURABILITY    w:majority, journaling, automated backups + restore drills, oplog window, RPO/RTO documented
OPERATIONS    monitoring + alerts (lag, queues, connections, cache, disk, elections, slow queries), capacity planning,
              rolling upgrades + FCV, rolling index builds, log rotation, runbooks
OS            XFS, THP off, ulimits, NUMA interleave, NTP, no swap pressure, separate disks
`);

/* ------------------------------------------------------------
   DONE. Next: Exercises.ps1
   ------------------------------------------------------------ */
