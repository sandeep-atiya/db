<#
============================================================
 LEVEL 20 - DOCKER & PRODUCTION  |  Exercises.ps1
------------------------------------------------------------
 Try each question FIRST (write your commands in the YOUR ANSWER
 area), then compare with the SOLUTIONS. Everything created here
 is removed at the end.

 QUESTIONS
   Q1. Start a container "mongo-ex" on port 27025 with a named volume
       "mongo-ex-data", root user root/RootPass#1, a 768 MB memory limit and
       the SMALLEST allowed WiredTiger cache (0.25 GB). Prove the cache limit
       from inside. (What happens with 0.125? Try it and read the log.)
   Q2. Show the last 5 log lines of the container and only the lines whose
       component ("c") is NETWORK.
   Q3. Create a user "reader" (read on testdb) in it and connect from the HOST
       with a connection string.
   Q4. Insert 3 documents, stop and remove the container (keep the volume),
       start a new container on the same volume and prove the documents exist.
   Q5. On the MAIN practice server: print current connections, cache used %,
       and the number of documents scanned per document returned since start.
   Q6. Show the startup warnings of the main server. Which ones would you fix
       in production?
   Q7. (Think) A production node shows: cache used 95 %, "pages evicted by
       application threads" climbing, queued readers > 50, disk 40 % used.
       Diagnose and list actions in order.
   Q8. (Think) Plan the upgrade of a 3-member 7.0 replica set to 8.0 with zero
       downtime, including FCV.
============================================================
#>
$c = "mongo-ex"; $vol = "mongo-ex-data"
function Admin($js) { docker exec $c mongosh --quiet -u root -p "RootPass#1" --authenticationDatabase admin --eval $js }
function Wait-Mongo() { for ($i = 0; $i -lt 40; $i++) { $ok = docker exec $c mongosh --quiet -u root -p "RootPass#1" --authenticationDatabase admin --eval "db.adminCommand('ping').ok" 2>$null; if ("$ok" -match "^1") { return $true }; Start-Sleep -Seconds 2 }; return $false }

# YOUR ANSWERS HERE (write below, run, compare)










# ============================================================
#  SOLUTIONS
# ============================================================
docker rm -f $c 2>$null | Out-Null; docker volume rm $vol 2>$null | Out-Null

# Q1
docker run -d --name $c -p 27025:27017 -e MONGO_INITDB_ROOT_USERNAME=root -e MONGO_INITDB_ROOT_PASSWORD="RootPass#1" -v "${vol}:/data/db" --memory 768m mongo:8 mongod --wiredTigerCacheSizeGB 0.25 --auth --bind_ip_all | Out-Null
"ready: $(Wait-Mongo)"
Admin "print('cache max MB:', Math.round(db.serverStatus().wiredTiger.cache['maximum bytes configured'] / 1048576))"   # 256
docker inspect --format "memory limit bytes: {{.HostConfig.Memory}}" $c
# With --wiredTigerCacheSizeGB 0.125 mongod refuses to start: "cacheSizeGB must be greater than or equal to 0.25" (docker logs shows it)

# Q2
docker logs --tail 5 $c 2>&1
docker logs $c 2>&1 | Select-String -Pattern '"c":"NETWORK"' | Select-Object -First 3

# Q3
Admin "db.getSiblingDB('testdb').createUser({ user: 'reader', pwd: 'ReadPass#1', roles: [ { role: 'read', db: 'testdb' } ] }); print('reader created')"
mongosh --quiet "mongodb://reader:ReadPass%231@localhost:27025/testdb?authSource=testdb" --eval "print('connected as:', db.runCommand({ connectionStatus: 1 }).authInfo.authenticatedUsers[0].user)"

# Q4
Admin "db.getSiblingDB('testdb').things.insertMany([{ a: 1 }, { a: 2 }, { a: 3 }]); print('inserted 3')"
docker rm -f $c | Out-Null
docker run -d --name $c -p 27025:27017 -e MONGO_INITDB_ROOT_USERNAME=root -e MONGO_INITDB_ROOT_PASSWORD="RootPass#1" -v "${vol}:/data/db" mongo:8 --auth | Out-Null
Wait-Mongo | Out-Null
Admin "print('after new container on the same volume:', db.getSiblingDB('testdb').things.countDocuments())"   # 3

# Q5  (main server, port 27017)
mongosh --quiet --eval "const s = db.serverStatus(); const c = s.wiredTiger.cache; print('connections:', s.connections.current, '| cache used %:', Math.round(c['bytes currently in the cache'] / c['maximum bytes configured'] * 100), '| scanned docs per returned:', Math.round(s.metrics.queryExecutor.scannedObjects / Math.max(1, s.metrics.document.returned) * 100) / 100)"

# Q6
mongosh --quiet --eval "db.adminCommand({ getLog: 'startupWarnings' }).log.forEach(l => print(JSON.parse(l).msg))"
# Typical: access control not enabled (fix: auth), THP enabled / vm.max_map_count low (fix: OS tuning), running as root, XFS recommended.

# Q7
# The working set no longer fits the cache: evictions are done by application threads (= your queries wait), so readers queue up.
# Actions: 1) find the offending queries (profiler/currentOp: COLLSCANs, big sorts) and fix indexes / projections;
#          2) reduce the working set (archive/TTL old data, drop unused indexes, project fields);
#          3) add RAM (raise cache) or scale reads to secondaries; 4) if growth is structural: shard.
# Disk at 40 % is not the problem - do not chase it.

# Q8
# Backup + test restore; check driver/tool compatibility with 8.0; verify FCV is "7.0" on all members; upgrade secondaries one by
# one (stop, replace binary/image, start, wait for SECONDARY + no lag); rs.stepDown() the primary, upgrade it; run on 8.0 binaries
# with FCV 7.0 for a soak period (downgrade still possible); then db.adminCommand({ setFeatureCompatibilityVersion: "8.0", confirm: true }).

# cleanup
docker rm -f $c | Out-Null; docker volume rm $vol | Out-Null
"cleaned"
