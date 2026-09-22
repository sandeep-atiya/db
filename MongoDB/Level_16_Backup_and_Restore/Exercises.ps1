<#
============================================================
 LEVEL 16 - BACKUP & RESTORE  |  Exercises.ps1
------------------------------------------------------------
 Try each question in the "YOUR ANSWER" area FIRST, then compare
 with the SOLUTIONS. All commands use the Docker container
 mongo-practice; everything created is removed at the end.

 QUESTIONS
   Q1. Dump only the employees collection of companyDB to /dump/emp.
   Q2. Restore it into companyDB as l16_ex_employees (rename with --nsFrom/--nsTo)
       and prove the count is 12.
   Q3. Dump companyDB into a gzipped archive file, copy it to the host folder
       .\backups and print its size in KB.
   Q4. From that archive restore ONLY the products collection into a database
       called scratch (hint: --nsInclude with --nsFrom/--nsTo).
   Q5. Export all Completed orders (query!) as a JSON array sorted by orderDate to
       /dump/completed.json and count the lines containing "Completed".
   Q6. Export employees as CSV with the columns name, salary, address.city and
       show the first 3 lines.
   Q7. Import data\customers_typed.csv into l16_ex_import with proper types and
       run a query that only works if createdDate is a real Date
       (documents created after 2025-07-10 -> 2).
   Q8. (Think) Your replica set dump takes 40 minutes on a busy system. Why might
       the restored data be inconsistent, and which two options fix that?
   Q9. (Think) Restoring last night's dump onto the live server "to fix a few
       deleted documents" - what goes wrong, and what should you do instead?
============================================================
#>

$c = "mongo-practice"
$here = if ($PSScriptRoot) { $PSScriptRoot } else { Get-Location }
function Mongo($js) { mongosh --quiet --eval $js }

# YOUR ANSWERS HERE (write below, run, compare)










# ============================================================
#  SOLUTIONS
# ============================================================
docker exec $c sh -c "rm -rf /dump && mkdir -p /dump" | Out-Null

# Q1
docker exec $c mongodump --db companyDB --collection employees --out /dump/emp --quiet
docker exec $c sh -c "ls /dump/emp/companyDB"

# Q2
docker exec $c mongorestore --nsFrom "companyDB.employees" --nsTo "companyDB.l16_ex_employees" --quiet /dump/emp
Mongo "print('l16_ex_employees:', db.getSiblingDB('companyDB').l16_ex_employees.countDocuments())"     # 12

# Q3
docker exec $c mongodump --db companyDB --gzip --archive=/dump/companyDB.gz --quiet
New-Item -ItemType Directory -Force -Path "$here\backups" | Out-Null
docker cp "${c}:/dump/companyDB.gz" "$here\backups\companyDB.gz"
"{0:N1} KB" -f ((Get-Item "$here\backups\companyDB.gz").Length / 1KB)

# Q4
docker exec $c mongorestore --gzip --archive=/dump/companyDB.gz --nsInclude "companyDB.products" --nsFrom "companyDB.*" --nsTo "scratch.*" --quiet
Mongo "print('scratch collections:', db.getSiblingDB('scratch').getCollectionNames().join(','), ' products:', db.getSiblingDB('scratch').products.countDocuments())"   # products, 11

# Q5
[IO.File]::WriteAllText("$here\backups\q.json", '{ "status": "Completed" }', (New-Object System.Text.UTF8Encoding($false)))   # UTF-8 without BOM
docker cp "$here\backups\q.json" "${c}:/dump/q.json"
docker exec $c mongoexport --db companyDB --collection orders --queryFile /dump/q.json --sort "{ orderDate: 1 }" --jsonArray --out /dump/completed.json --quiet
docker exec $c sh -c "grep -o Completed /dump/completed.json | wc -l"                                   # 16

# Q6
docker exec $c mongoexport --db companyDB --collection employees --type csv --fields "name,salary,address.city" --out /dump/emp.csv --quiet
docker exec $c sh -c "head -n 3 /dump/emp.csv"

# Q7
docker cp "$here\data\customers_typed.csv" "${c}:/dump/customers_typed.csv"
docker exec $c mongoimport --db companyDB --collection l16_ex_import --type csv --headerline --columnsHaveTypes --ignoreBlanks --file /dump/customers_typed.csv --quiet
Mongo "print('after 2025-07-10:', db.getSiblingDB('companyDB').l16_ex_import.countDocuments({ createdDate: { `$gt: new Date('2025-07-10') } }))"   # 2

# Q8
# mongodump reads collections one after another; writes that happen meanwhile make the dump a mix of moments (order without its
# stock change, etc.). Fix: (1) dump with --oplog and restore with --oplogReplay (consistent as of the end of the dump);
# (2) take a filesystem/volume snapshot of a (locked or paused) secondary, or use Atlas/Ops Manager continuous backup.

# Q9
# mongorestore does not overwrite existing documents, so most of it errors on duplicate _id; with --drop it REPLACES today's data
# with last night's -> you lose a day of writes. Instead: restore the dump into a staging database (--nsTo), extract the deleted
# documents there, and insert them back into production (or use a point-in-time restore from Atlas/oplog to a scratch cluster).

# cleanup
Mongo "db.getSiblingDB('scratch').dropDatabase(); use('companyDB'); db.l16_ex_employees.drop(); db.l16_ex_import.drop(); print('cleaned')"
docker exec $c sh -c "rm -rf /dump"
