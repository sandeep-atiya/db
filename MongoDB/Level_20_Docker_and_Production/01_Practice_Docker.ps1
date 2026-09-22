<#
============================================================
 LEVEL 20 - DOCKER  |  01_Practice_Docker.ps1
------------------------------------------------------------
 Topics : pull, run (name / port / volume / env / limits / flags),
          init scripts, logs, exec, stats, inspect, stop/start
          (persistence), rm, volumes, compose reminders

 Runs a THROWAWAY container "mongo-l20" on port 27019 with auth
 and a seeded database; nothing touches the main practice server.
 Run whole:  powershell -ExecutionPolicy Bypass -File .\01_Practice_Docker.ps1
============================================================
#>
$ErrorActionPreference = "Continue"
$here = if ($PSScriptRoot) { $PSScriptRoot } else { Get-Location }
$c = "mongo-l20"; $vol = "mongo-l20-data"
function Step($t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }
function MongoAdmin($js) { docker exec $c mongosh --quiet -u admin -p "S3cret#1" --authenticationDatabase admin --eval $js }
# The image starts a TEMPORARY mongod (no network) to run the init scripts, stops it, then starts the real one.
# So "Waiting for connections" appears twice - wait for an authenticated ping to succeed instead.
function Wait-Mongo() { for ($i = 0; $i -lt 40; $i++) { $ok = docker exec $c mongosh --quiet -u admin -p "S3cret#1" --authenticationDatabase admin --eval "db.adminCommand('ping').ok" 2>$null; if ("$ok" -match "^1") { return $true }; Start-Sleep -Seconds 2 }; return $false }

Step "0. Clean start"
docker rm -f $c 2>$null | Out-Null; docker volume rm $vol 2>$null | Out-Null

Step "1. Images: pull and inspect"
docker pull mongo:8 2>&1 | Select-Object -Last 1
docker image ls mongo --format "{{.Repository}}:{{.Tag}}  {{.Size}}"

Step "2. Run: name, port, NAMED VOLUME, root user (=> --auth), init database + init scripts, resource limits, mongod flags"
docker run -d --name $c -p 27019:27017 `
    -e MONGO_INITDB_ROOT_USERNAME=admin -e MONGO_INITDB_ROOT_PASSWORD="S3cret#1" `
    -e MONGO_INITDB_DATABASE=appdb `
    -v "${vol}:/data/db" `
    -v "${here}\init:/docker-entrypoint-initdb.d:ro" `
    --memory 1g --cpus 1 `
    mongo:8 mongod --wiredTigerCacheSizeGB 0.25 --auth --bind_ip_all | Out-Null
docker ps --filter "name=$c" --format "{{.Names}}  {{.Status}}  {{.Ports}}"

Step "3. Logs: the init scripts ran once; mongod logs JSON lines"
"ready (authenticated ping ok): $(Wait-Mongo)"
docker logs $c 2>&1 | Select-String -Pattern 'seed done|01_seed.js|Waiting for connections' | Select-Object -First 4
# "Waiting for connections" twice = temporary init mongod, then the real one; "seed done" printed by our init script in between
# JSON log lines: "t" time, "s" severity, "c" component (ACCESS, NETWORK, COMMAND, REPL...), "msg", "attr"
docker logs $c 2>&1 | Select-String -Pattern '"msg":"Slow query"' | Measure-Object | ForEach-Object { "slow queries logged so far: $($_.Count)" }

Step "4. Exec: the seed data and user exist; without credentials nothing works"
MongoAdmin "printjson(db.getSiblingDB('appdb').items.find().toArray()); print('users:', db.getSiblingDB('appdb').getUsers().users.map(u => u.user))"
docker exec $c mongosh --quiet --eval "try { db.getSiblingDB('appdb').items.findOne() } catch (e) { print('EXPECTED ERROR:', e.message) }"
docker exec $c mongosh --quiet -u appUser -p "AppPass#1" --authenticationDatabase appdb --eval "print('appUser count:', db.getSiblingDB('appdb').items.countDocuments())"
# From the host (mongosh installed on Windows):
mongosh --quiet "mongodb://appUser:AppPass%231@localhost:27019/appdb?authSource=appdb" --eval "print('from host:', db.items.countDocuments())"

Step "5. Resources: limits and live usage"
docker inspect --format "memory limit: {{.HostConfig.Memory}} bytes, cpus: {{.HostConfig.NanoCpus}} nano" $c
docker stats --no-stream --format "{{.Name}}  CPU {{.CPUPerc}}  MEM {{.MemUsage}}" $c
MongoAdmin "const c = db.serverStatus().wiredTiger.cache; print('cache max MB:', Math.round(c['maximum bytes configured'] / 1048576), ' used MB:', Math.round(c['bytes currently in the cache'] / 1048576))"
# cache max = 256 MB (--wiredTigerCacheSizeGB 0.25) < 1 GB container limit: leaves room for connections, sorting, OS

Step "6. Persistence: stop, start - data survives; rm + rm volume - data is gone"
MongoAdmin "db.getSiblingDB('appdb').items.insertOne({ _id: 4, sku: 'SCREW', qty: 1, price: 0.05 }); print('items now:', db.getSiblingDB('appdb').items.countDocuments())"
docker stop $c | Out-Null; docker start $c | Out-Null; Wait-Mongo | Out-Null
MongoAdmin "print('after restart:', db.getSiblingDB('appdb').items.countDocuments())"          # 4 - the volume kept it
docker rm -f $c | Out-Null
docker volume inspect $vol --format "volume still exists: {{.Name}} at {{.Mountpoint}}"
# A NEW container on the SAME volume: init scripts do NOT run again (volume not empty), data and users are there
docker run -d --name $c -p 27019:27017 -e MONGO_INITDB_ROOT_USERNAME=admin -e MONGO_INITDB_ROOT_PASSWORD="S3cret#1" -v "${vol}:/data/db" mongo:8 --auth | Out-Null
Wait-Mongo | Out-Null
MongoAdmin "print('new container, same volume:', db.getSiblingDB('appdb').items.countDocuments())"   # 4
docker logs $c 2>&1 | Select-String -Pattern "seed done" | Measure-Object | ForEach-Object { "seed ran again? count=$($_.Count) (0 = correct)" }

Step "7. Health check and inspect"
docker inspect --format "state: {{.State.Status}}  restart policy: {{.HostConfig.RestartPolicy.Name}}  image: {{.Config.Image}}" $c
# The compose files in 00_Setup / Level 15 / 17 / 18 add a healthcheck (mongosh ping) so dependants wait for readiness.

Step "8. Cleanup: container + volume"
docker rm -f $c | Out-Null; docker volume rm $vol | Out-Null
docker ps -a --filter "name=$c" --format "{{.Names}}"; docker volume ls --filter "name=$vol" --format "{{.Name}}"
Write-Host "removed (nothing printed above = gone)" -ForegroundColor Yellow

<#
------------------------------------------------------------
 DONE. Next: 02_Practice_Monitoring.js (main server), then Exercises.ps1
 Compose reminders:  docker compose up -d | ps | logs -f mongo | stop | down -v
------------------------------------------------------------
#>
