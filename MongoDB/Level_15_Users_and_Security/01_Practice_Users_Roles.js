/* ============================================================
   LEVEL 15 - USERS & SECURITY  |  01_Practice_Users_Roles.js
   ------------------------------------------------------------
   Topics : where users live, createUser with built-in roles,
            custom roles (privileges), getUsers / getRole,
            grant / revoke / update / changePassword, db.auth and
            connectionStatus, dropping users & roles

   HOW TO PRACTICE: block by block, predict first.
   Runs on the MAIN practice server, which has access control
   DISABLED: users can be created and authenticated, but
   permissions are NOT enforced. Enforcement is shown in
   02_Practice_Auth_Enabled.js on the auth-enabled server.
   ============================================================ */

use("companyDB");


/* ============================================================
   1. WHERE USERS LIVE
   ============================================================ */

db.getUsers();                                             // users whose authentication database is companyDB (none yet)
db.getSiblingDB("admin").system.users.countDocuments();    // ALL users of the server live here (0 on a fresh setup)
db.runCommand({ connectionStatus: 1 }).authInfo;           // { authenticatedUsers: [], authenticatedUserRoles: [] } - access control is off
db.adminCommand({ getCmdLineOpts: 1 }).parsed.security;    // undefined -> authorization not enabled (compose file: no --auth)


/* ============================================================
   2. CREATE USERS WITH BUILT-IN ROLES
   ============================================================ */

// Application user: read/write on companyDB only. (In real life: pwd: passwordPrompt(), never a literal.)
db.createUser({ user: "appUser", pwd: "AppPass#1", roles: [ { role: "readWrite", db: "companyDB" } ], customData: { owner: "orders-service" } });

// Reporting user: read-only. A bare string role means "in the current database".
db.createUser({ user: "reportUser", pwd: "ReportPass#1", roles: [ "read" ] });

// DBA user in the admin database with server-wide roles
db.getSiblingDB("admin").createUser({ user: "dba", pwd: "DbaPass#1", roles: [ "userAdminAnyDatabase", "dbAdminAnyDatabase", "readWriteAnyDatabase", "clusterMonitor" ] });

db.getUsers().users.map(u => ({ user: u.user, db: u.db, roles: u.roles }));
db.getSiblingDB("admin").getUsers().users.map(u => u.user);            // [ 'dba' ]
db.getSiblingDB("admin").system.users.find({}, { _id: 1, user: 1, db: 1, "roles.role": 1, "credentials.SCRAM-SHA-256.iterationCount": 1 });
// _id = "companyDB.appUser": the authentication database is part of the identity

// Duplicate user in the same authentication database -> error
try {
    db.createUser({ user: "appUser", pwd: "x", roles: [] });
} catch (e) {
    print("EXPECTED ERROR:", e.message);                    // User "appUser@companyDB" already exists
}


/* ============================================================
   3. A CUSTOM ROLE: least privilege
   ============================================================ */

// "orderManager": may read/insert/update orders, read products - but never delete anything, never touch employees
db.createRole({
    role: "orderManager",
    privileges: [
        { resource: { db: "companyDB", collection: "orders" },   actions: [ "find", "insert", "update" ] },
        { resource: { db: "companyDB", collection: "products" }, actions: [ "find" ] },
        { resource: { db: "companyDB", collection: "customers" }, actions: [ "find" ] }
    ],
    roles: []                                              // could inherit e.g. [ { role: "read", db: "reporting" } ]
});
db.createUser({ user: "orderApp", pwd: "OrderPass#1", roles: [ "orderManager" ] });

db.getRole("orderManager", { showPrivileges: true }).privileges;
db.getRoles({ showBuiltinRoles: false }).roles.map(r => r.role);      // [ 'orderManager' ]   (mongosh returns { roles: [...], ok: 1 })
db.getRoles({ showBuiltinRoles: true }).roles.map(r => r.role);       // + read, readWrite, dbAdmin, dbOwner, userAdmin ...

// Add a privilege later
db.grantPrivilegesToRole("orderManager", [ { resource: { db: "companyDB", collection: "orders" }, actions: [ "createIndex" ] } ]);
db.getRole("orderManager", { showPrivileges: true }).privileges.find(p => p.resource.collection === "orders").actions;   // find, insert, update, createIndex

// Effective privileges of a user (roles expanded)
db.getUser("orderApp", { showPrivileges: true }).inheritedPrivileges;


/* ============================================================
   4. MANAGING USERS: grant, revoke, update, password
   ============================================================ */

db.grantRolesToUser("reportUser", [ { role: "read", db: "reporting" } ]);       // roles may point to other databases
db.getUser("reportUser").roles;                                                 // read@companyDB, read@reporting
db.revokeRolesFromUser("reportUser", [ { role: "read", db: "reporting" } ]);
db.getUser("reportUser").roles;

db.updateUser("appUser", { customData: { owner: "orders-service", rotated: new Date() } });   // updateUser REPLACES the given fields (roles: [] would remove all roles!)
db.changeUserPassword("appUser", "AppPass#2");
db.getUser("appUser").customData;

// Authentication mechanisms stored for the user
db.getUser("appUser", { showCredentials: true }).credentials ? Object.keys(db.getUser("appUser", { showCredentials: true }).credentials) : "hidden";   // [ 'SCRAM-SHA-1', 'SCRAM-SHA-256' ] or hidden


/* ============================================================
   5. db.auth AND connectionStatus  (authentication works even when authorization is off)
   ============================================================ */

db.auth("reportUser", "ReportPass#1");                     // { ok: 1 }
db.runCommand({ connectionStatus: 1 }).authInfo;           // authenticatedUsers: [ { user: 'reportUser', db: 'companyDB' } ], roles: read@companyDB

// ... but because the SERVER runs without --auth, nothing is enforced: a read-only user can still write
db.employees.updateOne({ _id: 101 }, { $set: { touchedBy: "reportUser" } }).modifiedCount;   // 1  (!)
db.employees.updateOne({ _id: 101 }, { $unset: { touchedBy: "" } });
// -> 02_Practice_Auth_Enabled.js shows the same thing on a server WITH access control: "not authorized on companyDB"

db.auth("appUser", "AppPass#2");                           // authenticating again REPLACES the user on this connection
db.runCommand({ connectionStatus: 1 }).authInfo.authenticatedUsers;   // appUser only
try {
    db.auth("appUser", "wrong-password");
} catch (e) {
    print("EXPECTED ERROR:", e.message);                    // Authentication failed
}
db.logout();
db.runCommand({ connectionStatus: 1 }).authInfo.authenticatedUsers;   // []

// Connection strings you would use on an auth-enabled server:
//   mongosh "mongodb://appUser:AppPass%232@localhost:27017/companyDB?authSource=companyDB"      (# is URL-encoded as %23)
//   mongosh "mongodb://dba:DbaPass%231@localhost:27017/?authSource=admin"


/* ============================================================
   6. CLEANUP: drop users and the role
   ============================================================ */

db.dropUser("orderApp");
db.dropUser("reportUser");
db.dropUser("appUser");
db.dropRole("orderManager");
db.getSiblingDB("admin").dropUser("dba");
db.getUsers().users.length;                                // 0
db.getSiblingDB("admin").system.users.countDocuments();    // 0
// (db.dropAllUsers() removes every user of the current database - handle with care.)

/* ------------------------------------------------------------
   DONE. Next: start the auth-enabled server (docker compose -f docker-compose.auth.yml up -d)
              and run 02_Practice_Auth_Enabled.js against port 27018.
   ------------------------------------------------------------ */
