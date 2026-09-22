<#
============================================================
 LEVEL 16 - BACKUP & RESTORE  |  01_Practice_Backup_Restore.ps1
------------------------------------------------------------
 Topics : mongodump / mongorestore (full db, rename, single
          collection, --drop, --gzip --archive, --query), oplog
          point-in-time dump + replay, mongoexport (JSON / CSV),
          mongoimport (CSV untyped vs typed, JSON, upsert mode)

 HOW TO PRACTICE
   * The Database Tools run INSIDE the Docker container
     (docker exec mongo-practice <tool> ...). Files land in /dump
     inside the container and are copied to .\backups on the host.
   * Run the whole file:   powershell -ExecutionPolicy Bypass -File .\01_Practice_Backup_Restore.ps1
     or select a STEP and run it in the PowerShell ISE / VS Code.
   * Every step prints what it does. Nothing in companyDB is lost:
     the "accident" in step 4 is restored in the same step.
============================================================
#>

$ErrorActionPreference = "Continue"
$c = "mongo-practice"
$here = if ($PSScriptRoot) { $PSScriptRoot } else { Get-Location }
function Step($t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }
function Mongo($js) { mongosh --quiet --eval $js }

Step "0. Clean start: remove old dump folders inside the container and old restored databases"
docker exec $c sh -c "rm -rf /dump && mkdir -p /dump" | Out-Null
# bench_orders (200k documents from Levels 11-12) would make every dump 50 MB - drop it; those levels rebuild it on demand
Mongo "['companyDB_restored','companyDB_fromarchive'].forEach(d => db.getSiblingDB(d).dropDatabase()); use('companyDB'); ['l16_customers_csv','l16_customers_typed','l16_products_json','l16_pending','bench_orders'].forEach(x => db[x].drop()); print('clean')"


Step "1. FULL DUMP of companyDB  (BSON + metadata per collection)"
docker exec $c mongodump --db companyDB --out /dump/full --quiet
docker exec $c sh -c "ls -la /dump/full/companyDB"
# customers.bson (the documents) + customers.metadata.json (indexes, options) for every collection
docker exec $c sh -c "cat /dump/full/companyDB/customers.metadata.json"
# -> the partial unique index on email is in the metadata and will be rebuilt on restore


Step "2. COPY THE DUMP TO THE HOST  (docker cp)  -> .\backups\full"
New-Item -ItemType Directory -Force -Path "$here\backups" | Out-Null
if (Test-Path "$here\backups\full") { Remove-Item -Recurse -Force "$here\backups\full" }
docker cp "${c}:/dump/full" "$here\backups\full"
Get-ChildItem "$here\backups\full\companyDB" | ForEach-Object { "{0,-28} {1,8:N0} bytes" -f $_.Name, $_.Length }
# In production the backup goes off-site (object storage), encrypted, with retention.


Step "3. RESTORE INTO A DIFFERENT DATABASE  (--nsFrom / --nsTo)  -> companyDB_restored"
docker exec $c mongorestore --nsFrom "companyDB.*" --nsTo "companyDB_restored.*" --quiet /dump/full
Mongo "const r = db.getSiblingDB('companyDB_restored'); print(r.getCollectionNames().sort().join(', ')); print('employees:', r.employees.countDocuments(), ' orders:', r.orders.countDocuments()); printjson(r.customers.getIndexes().map(i => i.name))"
# -> same 5 collections, same counts, indexes rebuilt (uq_customers_email is there)


Step "4. THE ACCIDENT: someone drops customers. Restore ONLY that collection (--drop)"
Mongo "use('companyDB'); print('before drop:', db.customers.countDocuments()); db.customers.drop(); print('after drop :', db.customers.countDocuments())"
docker exec $c mongorestore --db companyDB --collection customers --drop --quiet /dump/full/companyDB/customers.bson
Mongo "use('companyDB'); print('restored   :', db.customers.countDocuments(), ' index names:', db.customers.getIndexes().map(i => i.name).join(', '))"
# -> 8 documents and the partial unique index are back. (--drop matters when the collection still exists with stale data.)


Step "5. SINGLE-FILE COMPRESSED BACKUP  (--gzip --archive)"
docker exec $c mongodump --db companyDB --gzip --archive=/dump/companyDB.archive.gz --quiet
docker exec $c sh -c "ls -la /dump/companyDB.archive.gz"
docker exec $c mongorestore --gzip --archive=/dump/companyDB.archive.gz --nsFrom "companyDB.*" --nsTo "companyDB_fromarchive.*" --quiet
Mongo "print('fromarchive orders:', db.getSiblingDB('companyDB_fromarchive').orders.countDocuments())"
# One file is easy to ship / pipe: mongodump --archive | ssh backup-host 'cat > x.gz'


Step "6. PARTIAL DUMP WITH A QUERY  (--queryFile: no quoting pain on Windows)"
# Write the JSON query file on the host (UTF-8 WITHOUT a byte-order mark - PowerShell's default pipe encoding adds one that mongodump rejects)
# and copy it into the container: no shell quoting involved at all.
[IO.File]::WriteAllText("$here\backups\pending-query.json", '{ "status": "Pending" }', (New-Object System.Text.UTF8Encoding($false)))
docker cp "$here\backups\pending-query.json" "${c}:/dump/pending-query.json"
docker exec $c cat /dump/pending-query.json
docker exec $c mongodump --db companyDB --collection orders --queryFile /dump/pending-query.json --out /dump/pending --quiet
docker exec $c mongorestore --nsFrom "companyDB.orders" --nsTo "companyDB.l16_pending" --quiet /dump/pending
Mongo "use('companyDB'); print('pending orders restored into l16_pending:', db.l16_pending.countDocuments())"   # 2


Step "7. POINT-IN-TIME DUMP WITH THE OPLOG  (replica set only, whole instance)"
# --oplog cannot be combined with --db: it dumps every database and records oplog entries written DURING the dump
docker exec $c mongodump --oplog --out /dump/pit --quiet
docker exec $c sh -c "ls /dump/pit; ls -la /dump/pit/oplog.bson"
# Restore replays those entries so the data is consistent as of the END of the dump:
#   docker exec $c mongorestore --oplogReplay --drop /dump/pit      (replays into the live instance - not run here)
# Tip: bsondump makes any .bson readable:
docker exec $c sh -c "bsondump --quiet /dump/full/companyDB/departments.bson | head -n 2"


Step "8. EXPORT: JSON (types preserved as Extended JSON) and CSV (everything is text)"
docker exec $c mongoexport --db companyDB --collection orders --jsonArray --pretty --limit 1 --out /dump/orders.json --quiet
docker exec $c sh -c "head -n 12 /dump/orders.json"
# -> orderDate is { "$date": "..." } - Extended JSON keeps the type
docker exec $c mongoexport --db companyDB --collection customers --type csv --fields "_id,name,email,city,createdDate,tags" --out /dump/customers.csv --quiet
docker exec $c sh -c "cat /dump/customers.csv"
# -> no types, arrays flattened to text, missing fields empty


Step "9. IMPORT CSV: untyped vs --columnsHaveTypes"
docker cp "$here\data\customers_extra.csv" "${c}:/dump/customers_extra.csv"
docker cp "$here\data\customers_typed.csv" "${c}:/dump/customers_typed.csv"
docker exec $c mongoimport --db companyDB --collection l16_customers_csv --type csv --headerline --file /dump/customers_extra.csv --quiet
Mongo "use('companyDB'); const d = db.l16_customers_csv.findOne({ name: 'Ishaan Verma' }); printjson(d); print('type of _id:', typeof d._id, ' createdDate:', typeof d.createdDate)"
# -> mongoimport guessed: _id number, createdDate STRING; Kabir's empty email became '' (use --ignoreBlanks to skip)
docker exec $c mongoimport --db companyDB --collection l16_customers_typed --type csv --headerline --columnsHaveTypes --ignoreBlanks --file /dump/customers_typed.csv --quiet
Mongo "use('companyDB'); const t = db.l16_customers_typed.findOne({ name: 'Ishaan Verma' }); printjson(t); print('createdDate is a Date:', t.createdDate instanceof Date); print('Kabir has email field:', db.l16_customers_typed.findOne({ name: 'Kabir Das' }).hasOwnProperty('email'))"


Step "10. IMPORT JSON with --mode upsert  (insert new, update existing by _id)"
docker cp "$here\data\products_extra.json" "${c}:/dump/products_extra.json"
docker exec $c mongoimport --db companyDB --collection l16_products_json --jsonArray --file /dump/products_extra.json --quiet
Mongo "use('companyDB'); print('imported:', db.l16_products_json.countDocuments()); printjson(db.l16_products_json.findOne({ _id: 2 }, { name: 1, launched: 1 }))"
# Now upsert the same file INTO A COPY of products: 12 and 13 are inserted, 2 (Mouse) is updated (price 1100, stock 90)
Mongo "use('companyDB'); db.products.aggregate([{ `$out: 'l16_products_upsert' }]); print('before:', db.l16_products_upsert.countDocuments(), 'mouse price', db.l16_products_upsert.findOne({ _id: 2 }).price)"
docker exec $c mongoimport --db companyDB --collection l16_products_upsert --jsonArray --mode upsert --upsertFields _id --file /dump/products_extra.json --quiet
Mongo "use('companyDB'); print('after :', db.l16_products_upsert.countDocuments(), 'mouse price', db.l16_products_upsert.findOne({ _id: 2 }).price); db.l16_products_upsert.drop()"
# --mode merge would keep fields not present in the file; --mode delete removes matching documents.


Step "11. VERIFY A RESTORE PROPERLY  (counts per collection, source vs restored)"
Mongo "const a = db.getSiblingDB('companyDB'), b = db.getSiblingDB('companyDB_restored'); ['departments','employees','customers','products','orders'].forEach(n => print(n.padEnd(12), a[n].countDocuments(), b[n].countDocuments(), a[n].countDocuments() === b[n].countDocuments() ? 'OK' : 'MISMATCH'))"
# Also compare index lists and, for critical data, a checksum (e.g. `$group` with `$sum` of a hash field or dbHash command).


Step "12. CLEANUP"
Mongo "['companyDB_restored','companyDB_fromarchive'].forEach(d => db.getSiblingDB(d).dropDatabase()); use('companyDB'); ['l16_customers_csv','l16_customers_typed','l16_products_json','l16_pending'].forEach(x => db[x].drop()); print('cleaned')"
docker exec $c sh -c "rm -rf /dump"
Write-Host "`nHost copy of the dump kept in $here\backups\full (delete it when you are done)." -ForegroundColor Yellow

<#
------------------------------------------------------------
 DONE. Next: Exercises.ps1
------------------------------------------------------------
#>
