/* ============================================================
   LEVEL 15 - USERS & SECURITY  |  02_Practice_Auth_Enabled.js
   ------------------------------------------------------------
   Topics : a server WITH access control, "requires authentication",
            "not authorized" errors, least privilege in action,
            custom role enforcement, authSource, switching users

   HOW TO RUN
     1. Start the auth-enabled server (in this folder):
            docker compose -f docker-compose.auth.yml up -d
     2. Connect AS ADMIN and run this file block by block:
            mongosh "mongodb://admin:Admin%23123@localhost:27018/?authSource=admin"
        or whole file with echoed results (PowerShell):
            Get-Content 02_Practice_Auth_Enabled.js -Raw | mongosh --quiet "mongodb://admin:Admin%23123@localhost:27018/?authSource=admin"
   ============================================================ */

use("companyDB");


/* ============================================================
   1. WHO AM I, AND IS AUTH ENFORCED?
   ============================================================ */

db.runCommand({ connectionStatus: 1 }).authInfo;           // authenticatedUsers: [ { user: 'admin', db: 'admin' } ], roles: root@admin
db.adminCommand({ getCmdLineOpts: 1 }).argv.includes("--auth");   // true - the image added --auth because a root user was configured
db.getSiblingDB("admin").getUsers().users.map(u => ({ user: u.user, roles: u.roles.map(r => r.role) }));   // admin: root

// Without credentials you can CONNECT but not DO anything. Try in another terminal:
//   mongosh --port 27018 --eval "db.getSiblingDB('companyDB').employees.findOne()"
//   -> MongoServerError: Command find requires authentication


/* ============================================================
   2. SEED A LITTLE DATA AS ADMIN AND CREATE LEAST-PRIVILEGE USERS
   ============================================================ */

db.employees.drop(); db.orders.drop(); db.products.drop();
db.employees.insertMany([ { _id: 101, name: "Rahul", salary: 85000 }, { _id: 102, name: "Amit", salary: 65000 } ]);
db.products.insertMany([ { _id: 1, name: "Laptop", price: 75000, stock: 10 }, { _id: 2, name: "Mouse", price: 1000, stock: 100 } ]);
db.orders.insertOne({ _id: 1001, customerId: 1, items: [ { productId: 1, qty: 1 } ], status: "Pending" });

[ "appUser", "reportUser", "orderApp" ].forEach(u => { try { db.dropUser(u); } catch (e) {} });
try { db.dropRole("orderManager"); } catch (e) {}

db.createUser({ user: "appUser",    pwd: "AppPass#1",    roles: [ { role: "readWrite", db: "companyDB" } ] });
db.createUser({ user: "reportUser", pwd: "ReportPass#1", roles: [ { role: "read", db: "companyDB" } ] });
db.createRole({ role: "orderManager", privileges: [
    { resource: { db: "companyDB", collection: "orders" },   actions: [ "find", "insert", "update" ] },
    { resource: { db: "companyDB", collection: "products" }, actions: [ "find" ] } ], roles: [] });
db.createUser({ user: "orderApp", pwd: "OrderPass#1", roles: [ "orderManager" ] });
db.getUsers().users.map(u => u.user);                      // appUser, orderApp, reportUser


/* ============================================================
   3. reportUser: READ ONLY  (authorization is now ENFORCED)
   ============================================================ */

db.auth("reportUser", "ReportPass#1");                     // replaces admin on this connection
db.runCommand({ connectionStatus: 1 }).authInfo.authenticatedUsers;   // reportUser
db.employees.find({}, { _id: 0, name: 1 }).toArray();      // allowed
try {
    db.employees.updateOne({ _id: 101 }, { $set: { salary: 1 } });
} catch (e) {
    print("EXPECTED ERROR:", e.codeName, "-", e.message);   // Unauthorized - not authorized on companyDB to execute command { update: ... }
}
try {
    db.employees.createIndex({ name: 1 });
} catch (e) {
    print("EXPECTED ERROR:", e.codeName);                   // Unauthorized (createIndex is a dbAdmin action)
}
try {
    db.getSiblingDB("otherDB").things.find().toArray();     // no role there at all
} catch (e) {
    print("EXPECTED ERROR:", e.codeName, "-", e.message.substring(0, 60));
}
try {
    db.adminCommand({ listDatabases: 1 });
} catch (e) {
    print("EXPECTED ERROR (show dbs needs listDatabases):", e.codeName);
}
db.adminCommand({ listDatabases: 1, authorizedDatabases: true }).databases.map(d => d.name);   // only the dbs this user may see: [ 'companyDB' ]


/* ============================================================
   4. orderApp: THE CUSTOM ROLE IN ACTION
   ============================================================ */

db.auth("orderApp", "OrderPass#1");
db.orders.insertOne({ _id: 1002, customerId: 2, items: [ { productId: 2, qty: 3 } ], status: "Pending" });   // insert on orders: allowed
db.orders.updateOne({ _id: 1002 }, { $set: { status: "Completed" } }).modifiedCount;                          // update: allowed
db.products.find({}, { _id: 0, name: 1 }).toArray();                                                          // read products: allowed
try {
    db.orders.deleteOne({ _id: 1002 });                                                                        // remove: NOT granted
} catch (e) { print("EXPECTED ERROR (delete):", e.codeName); }
try {
    db.products.updateOne({ _id: 1 }, { $inc: { stock: -1 } });                                                // products are read-only for this role
} catch (e) { print("EXPECTED ERROR (update products):", e.codeName); }
try {
    db.employees.findOne();                                                                                    // employees: no privilege at all
} catch (e) { print("EXPECTED ERROR (employees):", e.codeName); }
try {
    db.orders.aggregate([ { $lookup: { from: "employees", localField: "customerId", foreignField: "_id", as: "e" } } ]).toArray();   // $lookup needs find on the joined collection
} catch (e) { print("EXPECTED ERROR ($lookup into employees):", e.codeName); }


/* ============================================================
   5. appUser: readWrite, but no admin actions
   ============================================================ */

db.auth("appUser", "AppPass#1");
db.employees.updateOne({ _id: 101 }, { $inc: { salary: 1000 } }).modifiedCount;   // 1
db.employees.createIndex({ name: 1 });                     // readWrite INCLUDES createIndex / dropIndex on its collections
try {
    db.createUser({ user: "hacker", pwd: "x", roles: [ "root" ] });               // createUser needs userAdmin
} catch (e) { print("EXPECTED ERROR (createUser):", e.codeName); }
try {
    db.getSiblingDB("admin").runCommand({ shutdown: 1 });    // cluster actions: no
} catch (e) { print("EXPECTED ERROR (shutdown):", e.codeName); }
try {
    db.dropDatabase();                                       // dropDatabase is a dbAdmin action
} catch (e) { print("EXPECTED ERROR (dropDatabase):", e.codeName); }


/* ============================================================
   6. WRONG PASSWORD, WRONG authSource
   ============================================================ */

try { db.auth("appUser", "nope"); } catch (e) { print("EXPECTED ERROR:", e.message); }                 // Authentication failed
try { db.getSiblingDB("admin").auth("appUser", "AppPass#1"); } catch (e) { print("EXPECTED ERROR (wrong authSource):", e.message); }
// appUser lives in companyDB -> authenticate against companyDB (authSource=companyDB), not admin.


/* ============================================================
   7. BACK TO ADMIN, CLEANUP
   ============================================================ */

db.getSiblingDB("admin").auth("admin", "Admin#123");
db.runCommand({ connectionStatus: 1 }).authInfo.authenticatedUsers;   // admin
db.dropUser("appUser"); db.dropUser("reportUser"); db.dropUser("orderApp"); db.dropRole("orderManager");
db.dropDatabase();
// Stop the server when done:  docker compose -f docker-compose.auth.yml down -v

/* ------------------------------------------------------------
   DONE. Next: Exercises.js
   ------------------------------------------------------------ */
