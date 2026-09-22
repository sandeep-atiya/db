/* ============================================================
   LEVEL 15 - USERS & SECURITY  |  Exercises.js
   ------------------------------------------------------------
   Try each question in the "YOUR ANSWER" area FIRST.
   Then scroll down to SOLUTIONS and compare.
   Q1-Q5 run on the MAIN server (no enforcement), Q6-Q8 on the
   auth-enabled server (port 27018) - see 02_Practice.
   All users/roles created here are dropped at the end.
   ============================================================ */

use("companyDB");

/* ------------------------------------------------------------
   QUESTIONS
   ------------------------------------------------------------
   Q1.  Create a user "hrApp" that can read and write companyDB and only READ a
        database called "payroll". Show its roles.
   Q2.  Create a role "readOnlyEmployees" that allows find on employees and
        departments only; create user "intern" with that role and show its
        effective (inherited) privileges.
   Q3.  Give "intern" the extra ability to create indexes on employees WITHOUT
        creating a new role (grantPrivilegesToRole) and verify.
   Q4.  Rotate hrApp's password and record the rotation date in customData
        (roles must stay unchanged - check!).
   Q5.  Authenticate as intern and print connectionStatus. Explain why an
        insert into employees still works on this server.
   Q6.  (auth server, port 27018, connected as admin) Create user "auditor" with
        role "read" on companyDB and role "clusterMonitor" on admin. Authenticate
        as auditor: run db.serverStatus().ok and try to insert - which works?
   Q7.  (auth server) Connect WITHOUT credentials from PowerShell and run a find.
        What is the exact error?
   Q8.  (Think) An API builds its login query as
        db.users.findOne({ username: req.body.username, password: req.body.password })
        and the client sends { "username": "admin", "password": { "$ne": "" } }.
        What happens and what are two fixes?
   ------------------------------------------------------------ */

// YOUR ANSWERS HERE (write below, run, compare)










/* ============================================================
   SOLUTIONS  (Q1-Q5: main server)
   ============================================================ */

[ "hrApp", "intern" ].forEach(u => { try { db.dropUser(u); } catch (e) {} });
try { db.dropRole("readOnlyEmployees"); } catch (e) {}

// Q1
db.createUser({ user: "hrApp", pwd: "HrPass#1", roles: [ { role: "readWrite", db: "companyDB" }, { role: "read", db: "payroll" } ] });
db.getUser("hrApp").roles;                                 // readWrite@companyDB, read@payroll

// Q2
db.createRole({ role: "readOnlyEmployees", privileges: [
    { resource: { db: "companyDB", collection: "employees" },   actions: [ "find" ] },
    { resource: { db: "companyDB", collection: "departments" }, actions: [ "find" ] } ], roles: [] });
db.createUser({ user: "intern", pwd: "InternPass#1", roles: [ "readOnlyEmployees" ] });
db.getUser("intern", { showPrivileges: true }).inheritedPrivileges;

// Q3
db.grantPrivilegesToRole("readOnlyEmployees", [ { resource: { db: "companyDB", collection: "employees" }, actions: [ "createIndex" ] } ]);
db.getRole("readOnlyEmployees", { showPrivileges: true }).privileges.find(p => p.resource.collection === "employees").actions;   // find, createIndex

// Q4
db.changeUserPassword("hrApp", "HrPass#2");
db.updateUser("hrApp", { customData: { passwordRotatedAt: new Date() } });   // only customData is replaced
db.getUser("hrApp").roles.length;                          // 2 - roles untouched

// Q5
db.auth("intern", "InternPass#1");
db.runCommand({ connectionStatus: 1 }).authInfo;
db.employees.insertOne({ _id: 999, name: "should not be allowed", email: "intern@example.com" }).acknowledged;   // true - the MAIN server runs WITHOUT --auth: authentication works, authorization is not enforced
// (the email is needed only because the unique index already holds one document without an email - Anjali - see Level 11)
db.employees.deleteOne({ _id: 999 });
db.logout();

// Q6  (run on the auth server as admin: mongosh "mongodb://admin:Admin%23123@localhost:27018/?authSource=admin")
// use("companyDB");
// db.createUser({ user: "auditor", pwd: "AuditPass#1", roles: [ { role: "read", db: "companyDB" }, { role: "clusterMonitor", db: "admin" } ] });
// db.auth("auditor", "AuditPass#1");
// db.serverStatus().ok                                    // 1  (clusterMonitor)
// db.employees.insertOne({ x: 1 })                        // MongoServerError: not authorized on companyDB to execute command { insert ... }
// db.getSiblingDB("admin").auth("admin", "Admin#123"); db.dropUser("auditor");

// Q7  (PowerShell)
// mongosh --port 27018 --quiet --eval "db.getSiblingDB('companyDB').employees.findOne()"
// -> MongoServerError: Command find requires authentication

// Q8
// The filter becomes { username: "admin", password: { $ne: "" } } -> matches the admin document without knowing the password
// (operator injection). Fixes: (1) validate/cast input types (password must be a string; reject objects / keys starting with "$",
// e.g. mongo-sanitize / express-mongo-sanitize); (2) never compare passwords in the query at all - fetch the user by username and
// verify a salted hash (bcrypt/argon2) in the application; also use schema validation and least-privilege DB users.

db.dropUser("hrApp"); db.dropUser("intern"); db.dropRole("readOnlyEmployees");
