/* ============================================================
   LEVEL 01 - MONGODB BASICS  |  01_Practice.js
   ------------------------------------------------------------
   Topics : mongosh, show/use/db, databases & collections,
            documents & _id / ObjectId, implicit vs explicit
            creation, capped collections, rename, drop, stats,
            system databases, naming rules, help

   HOW TO PRACTICE
     * Run block by block: paste a block into mongosh (or select the
       lines in a VS Code MongoDB Playground -> "Run Selected Lines").
       Predict the output before running.
     * This level works in its OWN throwaway database (practiceDB_L01)
       so nothing in companyDB is touched. The last block drops it.
     * Whole file with every result shown:
         PowerShell:  Get-Content 01_Practice.js -Raw | mongosh --quiet
         bash:        mongosh --quiet < 01_Practice.js
   ============================================================ */


/* ============================================================
   1. LOOK AROUND THE SERVER
   ============================================================ */

// Which server / version am I talking to?
db.version();                                   // 8.x
db.hello().isWritablePrimary;                   // true  (this node accepts writes)
db.hello().setName;                             // "rs0" (a replica set - needed for Levels 14 & 17)

// Every database on this server that CONTAINS data. Empty databases are invisible.
show("dbs");                                    // admin, companyDB, config, local

// In the interactive shell you can simply type:  show dbs
// The function form show("dbs") also works in scripts and playgrounds.

// Where am I?   (mongosh starts in "test")
db;                                             // test
db.getName();

// Bytes on disk per database (a database command instead of a shell helper)
db.adminCommand({ listDatabases: 1 }).databases.map(d => d.name + " " + d.sizeOnDisk);


/* ============================================================
   2. use  =  SWITCH (AND LAZILY CREATE) A DATABASE
   ============================================================ */

use("practiceDB_L01");                          // "switched to db practiceDB_L01"
db.getName();                                   // practiceDB_L01

// Still NOT in the list - nothing has been written yet
show("dbs");

// A database and a collection are created by the FIRST WRITE:
db.employees.insertOne({ name: "Rahul", age: 28, department: "IT", salary: 75000 });
// -> { acknowledged: true, insertedId: ObjectId("...") }

show("dbs");                                    // now practiceDB_L01 is listed
show("collections");                            // employees
db.getCollectionNames();                        // [ 'employees' ]   (same thing, as an array)


/* ============================================================
   3. DOCUMENTS, _id AND ObjectId
   ============================================================ */

db.employees.find();                            // the document got an _id: ObjectId("...")
db.employees.findOne();                         // first document only (a document, not a cursor)

// Anatomy of an ObjectId: 12 bytes = 4 timestamp + 5 random + 3 counter
const oid = db.employees.findOne()._id;
oid;                                            // ObjectId('66...')
oid.toString();                                 // 24 hex characters
oid.getTimestamp();                             // creation time -> ISODate("...")  (seconds precision)

// You can make your own ObjectIds; each new one is bigger than the last (roughly time-sorted)
ObjectId();
ObjectId() > oid;                               // true (compared as strings of hex - same ordering)

// _id can be ANY unique value you choose: number, string, even an embedded document
db.employees.insertOne({ _id: 102, name: "Amit", age: 30, department: "Sales", salary: 65000 });
db.employees.insertOne({ _id: "EMP-103", name: "Priya", department: "HR" });
db.employees.find({}, { name: 1 });             // 3 docs with 3 kinds of _id

// _id must be UNIQUE - the only constraint MongoDB enforces out of the box
try {
    db.employees.insertOne({ _id: 102, name: "Duplicate" });
} catch (e) {
    print("EXPECTED ERROR:", e.message);        // E11000 duplicate key error ... dup key: { _id: 102 }
}

// _id is IMMUTABLE - you cannot change it with an update
try {
    db.employees.updateOne({ _id: 102 }, { $set: { _id: 999 } });
} catch (e) {
    print("EXPECTED ERROR:", e.message);        // Performing an update on the path '_id' would modify the immutable field '_id'
}


/* ============================================================
   4. FLEXIBLE SCHEMA - documents in ONE collection may differ
   ============================================================ */

// No ALTER TABLE needed: just insert a document with different fields.
db.employees.insertOne({
    name: "Neha", department: "Finance",
    skills: ["Excel", "SQL"],                                  // an array
    address: { city: "Mumbai", pincode: 400001 },              // an embedded document
    joined: new Date("2024-02-12"),                            // a Date
    active: true, manager: null                                // boolean, null
});
db.employees.find();

// Note: Priya has no age, Neha has no salary, Rahul has no skills. All valid.
// The APPLICATION decides what a valid employee looks like (or Level 13 validation).


/* ============================================================
   5. EXPLICIT COLLECTION CREATION (for options)
   ============================================================ */

// Plain explicit creation (same as implicit, but exists even while empty)
db.createCollection("departments");             // { ok: 1 }
show("collections");                            // departments, employees

// Trying to create it twice -> error
try {
    db.createCollection("departments");
} catch (e) {
    print("EXPECTED ERROR:", e.message);        // Collection practiceDB_L01.departments already exists.
}

// CAPPED collection: fixed size, keeps insertion order, oldest documents are overwritten
db.createCollection("recent_logs", { capped: true, size: 4096, max: 3 });   // max 3 documents
for (let i = 1; i <= 5; i++) db.recent_logs.insertOne({ n: i, msg: "log " + i });
db.recent_logs.find();                          // only n: 3, 4, 5 remain (1 and 2 were pushed out)
db.recent_logs.isCapped();                      // true

// Naming rules: '$' is not allowed in collection names, and names are case-sensitive
try {
    db.createCollection("bad$name");
} catch (e) {
    print("EXPECTED ERROR:", e.message);
}
db.Employees.find();                            // [] - a DIFFERENT (non-existent) collection, no error!


/* ============================================================
   6. STATISTICS AND METADATA
   ============================================================ */

db.stats();                                     // collections, objects, dataSize, storageSize, indexes ...
db.employees.stats().count;                     // 4
db.employees.stats().nindexes;                  // 1  (the automatic _id index)
db.employees.getIndexes();                      // [ { v: 2, key: { _id: 1 }, name: '_id_' } ]

// Collection list with details (type: collection / view, options such as capped)
db.getCollectionInfos();
db.getCollectionInfos({ name: "recent_logs" })[0].options;    // { capped: true, size: 4096, max: 3 }


/* ============================================================
   7. RENAME AND DROP
   ============================================================ */

db.employees.renameCollection("staff");         // { ok: 1 }
show("collections");                            // departments, recent_logs, staff
db.staff.countDocuments();                      // 4

db.staff.drop();                                // true  - collection, its documents AND its indexes are gone
db.staff.drop();                                // false - already gone, no error
show("collections");


/* ============================================================
   8. SYSTEM DATABASES AND OTHER DATABASES WITHOUT SWITCHING
   ============================================================ */

// getSiblingDB lets you talk to another database without "use"
db.getSiblingDB("companyDB").employees.countDocuments();      // 12
db.getSiblingDB("admin").runCommand({ buildInfo: 1 }).version;
db.getSiblingDB("local").getCollectionNames();                // includes "oplog.rs" (Level 17)

// Any command can be run "raw"
db.runCommand({ ping: 1 });                     // { ok: 1 }
db.runCommand({ collStats: "recent_logs" }).capped;   // true


/* ============================================================
   9. HELP
   ============================================================ */

// help                     (shell help)
// db.help()                (database methods)
// db.employees.help()      (collection methods)
// db.employees.find().help()  (cursor methods)
typeof db.help;                                 // function


/* ============================================================
   10. DROP THE DATABASE  (no need to "leave" it first, unlike SQL Server)
   ============================================================ */

db.getName();                                   // practiceDB_L01
db.dropDatabase();                              // { ok: 1, dropped: 'practiceDB_L01' }
show("dbs");                                    // practiceDB_L01 is gone (on a replica set it can linger for a second with no size)
db.getName();                                   // still "practiceDB_L01" - the shell keeps the name; nothing exists until you write again

/* ------------------------------------------------------------
   DONE. Next: Exercises.js
   ------------------------------------------------------------ */
