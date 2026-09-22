# Level 15 — Users & Security

**Goal:** understand authentication vs authorization in MongoDB, create users and custom roles with least privilege, enable access control on a server (and see what "not authorized" looks like), connect with credentials, and know the rest of the security checklist: TLS, network, encryption, injection, auditing.

**Time:** ~2 hr · **Files:** `01_Practice_Users_Roles.js` (main server) → `docker-compose.auth.yml` + `02_Practice_Auth_Enabled.js` (auth-enabled server on port 27018) → `Exercises.js`

---

## 1. Concepts in plain words

| Term | Meaning |
|------|---------|
| **Authentication** | *Who are you?* Mechanisms: **SCRAM-SHA-256** (username/password, default), SCRAM-SHA-1 (legacy), **x.509** certificates, LDAP / Kerberos (Enterprise / Atlas), AWS IAM (Atlas). |
| **Authorization** | *What may you do?* **RBAC**: a user has roles; a role is a set of privileges; a privilege = resource (db / collection / cluster) + actions (`find`, `insert`, `update`, `remove`, `createIndex`, `dropCollection`, …). |
| **User** | Stored in `admin.system.users`, but *created in* an **authentication database** (`db.createUser` in `companyDB` → user `appUser@companyDB`). You log in against that database (`authSource`). A user can have roles in *other* databases. |
| **Built-in roles** | Database: `read`, `readWrite`, `dbAdmin` (indexes, stats, validation), `userAdmin` (manage users/roles), `dbOwner` (all three). Any-database: `readAnyDatabase`, `readWriteAnyDatabase`, `userAdminAnyDatabase`, `dbAdminAnyDatabase`. Cluster: `clusterMonitor`, `clusterManager`, `clusterAdmin`, `hostManager`. Backup: `backup`, `restore`. Superuser: `root`. |
| **Custom role** | `db.createRole({ role, privileges: [{ resource: { db, collection }, actions: [...] }], roles: [inherited] })` — e.g. "may insert and update orders but never delete". |
| **Access control off** (our main practice server) | Anyone who can reach the port can do anything. Fine on a laptop, **never** on a network. |
| **Enabling access control** | `mongod --auth` or `security.authorization: enabled` in `mongod.cfg`. First create an admin user through the **localhost exception** (the first user can be created from localhost while no users exist), then restart with auth. On a **replica set** members must also authenticate to each other: `--keyFile` (shared secret) or x.509 (`clusterAuthMode`). |
| **Docker image** | Setting `MONGO_INITDB_ROOT_USERNAME/PASSWORD` creates the root user and starts `mongod --auth` automatically — what `docker-compose.auth.yml` does. |
| **Connection string** | `mongodb://user:pass@host:27017/companyDB?authSource=companyDB&authMechanism=SCRAM-SHA-256` — `authSource` = the database the user was created in (often `admin`). URL-encode special characters in passwords. |
| **TLS** | `net.tls.mode: requireTLS`, certificate + key file, `tlsCAFile`; clients use `tls=true`. Always in production / over any network. |
| **Encryption at rest** | Enterprise / Atlas (WiredTiger encryption, KMIP); on Community use disk-level encryption. |
| **Client-side field level encryption / Queryable Encryption** | The driver encrypts specific fields before sending; the server never sees plaintext (even DBAs cannot). |
| **Auditing** | Enterprise / Atlas: log of authentication, DDL, user changes (`auditLog`). |
| **Network** | `net.bindIp` (default localhost only), firewall / security groups, VPC peering / private endpoints, never expose 27017 to the internet (ransomware wave of 2017 = open, auth-less instances). |
| **Injection** | No SQL strings, but: never pass user-supplied JSON straight into a filter (`{ username: req.body.user }` where `user = { $ne: null }` logs in as anyone) → validate types / use `mongo-sanitize` / schema validation of inputs; never use `$where` / `$function` with user input; `$expr` and `$regex` with user input need escaping / limits. |
| **Least privilege** | App user: `readWrite` on its database only (or a custom role); reporting: `read`; migrations/DBA: separate elevated user; monitoring: `clusterMonitor`; backup: `backup`. Rotate passwords, use secrets managers, one user per service. |

## 2. Syntax cheat-sheet

```js
// USERS (run in the authentication database)
use("companyDB")
db.createUser({ user: "appUser", pwd: passwordPrompt(), roles: [ { role: "readWrite", db: "companyDB" } ] })
db.createUser({ user: "reportUser", pwd: "...", roles: [ "read" ] })                 // role on the current db
db.getSiblingDB("admin").createUser({ user: "dba", pwd: "...", roles: [ "userAdminAnyDatabase", "dbAdminAnyDatabase", "readWriteAnyDatabase" ] })
db.getUsers()                          db.getUser("appUser", { showPrivileges: true })
db.updateUser("appUser", { customData: { team: "orders" }, roles: [ { role: "readWrite", db: "companyDB" } ] })
db.changeUserPassword("appUser", "newPass")
db.grantRolesToUser("appUser", [ { role: "read", db: "reporting" } ])
db.revokeRolesFromUser("appUser", [ { role: "read", db: "reporting" } ])
db.dropUser("appUser")
db.auth("appUser", "pass")             db.logout()          db.runCommand({ connectionStatus: 1 })

// ROLES
db.createRole({ role: "orderManager",
    privileges: [ { resource: { db: "companyDB", collection: "orders" }, actions: [ "find", "insert", "update" ] },
                  { resource: { db: "companyDB", collection: "products" }, actions: [ "find" ] } ],
    roles: [] })
db.getRoles({ showPrivileges: true, showBuiltinRoles: false })
db.getRole("orderManager", { showPrivileges: true })
db.grantPrivilegesToRole("orderManager", [ { resource: { db: "companyDB", collection: "customers" }, actions: [ "find" ] } ])
db.dropRole("orderManager")

// CONNECT
mongosh "mongodb://appUser:pass@localhost:27017/companyDB?authSource=companyDB"
mongosh --host localhost --port 27018 -u admin -p --authenticationDatabase admin
```

```yaml
# mongod.cfg (native install)
security:
  authorization: enabled
  keyFile: /etc/mongo-keyfile          # replica set internal auth (chmod 400, same file on every member)
net:
  bindIp: 127.0.0.1,10.0.0.5
  tls:
    mode: requireTLS
    certificateKeyFile: /etc/ssl/mongodb.pem
```

## 3. Gotchas

- **`authSource` must be the database where the user was created.** `mongodb://appUser:pw@host/companyDB` without `authSource` authenticates against `companyDB` (the URI's db) — fine if the user lives there; users created in `admin` need `?authSource=admin`.
- **Roles are granted per database.** `readWrite` in `companyDB` gives nothing in `reporting`; `*AnyDatabase` roles live in `admin`.
- **`show dbs` needs `listDatabases`** — a plain `read` user sees only databases it has roles on (7.x: `authorizedDatabases`).
- **The localhost exception closes after the first user exists.** Create an admin with `userAdminAnyDatabase` + more before restarting with auth, or you lock yourself out (recovery: restart without `--auth`).
- **A replica set with auth needs internal auth (keyFile / x.509)** — enabling `--auth` on one member without a keyFile breaks replication.
- **`root` ≠ everything**: it lacks a few actions (e.g. `applyOps`); `__system` is internal. Never use `root` for applications.
- **Passwords in connection strings** leak into logs, shell history and process lists — use `passwordPrompt()`, env variables or secret managers; URL-encode `@ : / ? #`.
- **SCRAM-SHA-1 vs 256**: users created on modern servers get both by default; drivers negotiate. Disable SHA-1 in hardened setups.
- **Auth is not encryption**: without TLS the SCRAM handshake is safe but the *data* travels in clear text.
- **`db.auth()` in mongosh replaces the current user on that connection** (one authenticated user per connection since 4.4).
- **Operator injection** works even in parameterised drivers: `{ user: req.body.user }` with `req.body.user = { "$gt": "" }`. Validate types.

## 4. Interview questions

**Q: Authentication vs authorization in MongoDB?**
Authentication verifies identity (SCRAM password, x.509 cert, LDAP/Kerberos). Authorization is RBAC: users get roles; roles bundle privileges (resource + actions) that decide which commands they may run on which databases/collections.

**Q: How do you enable security on a fresh server?**
Start without auth, create an admin user in `admin` (userAdminAnyDatabase + readWriteAnyDatabase/root) via the localhost exception, add `security.authorization: enabled` (+ keyFile for replica sets), restart, then create least-privilege application users. Bind to private IPs and enable TLS.

**Q: Where are users stored and what is the authentication database?**
All users live in `admin.system.users`, but each has a "database" — the one you ran `createUser` in — used with `authSource` to log in. Roles can point to any database.

**Q: What built-in roles would you give an application, a BI tool, a DBA, a backup job?**
App: `readWrite` on its db (or a custom role without `remove`). BI: `read` (maybe on a replica / Atlas Data Federation). DBA: `userAdminAnyDatabase` + `dbAdminAnyDatabase` + `clusterMonitor` (or `root` in emergencies). Backup: `backup` / `restore`.

**Q: How do you create a role that can insert and update orders but not delete?**
`createRole` with a privilege on `{ db: "companyDB", collection: "orders" }` with actions `find`, `insert`, `update` — and no `remove`.

**Q: How does a replica set authenticate its own members?**
Internal authentication: a shared keyFile (base64 secret, same on all members, restricted permissions) or x.509 member certificates (`clusterAuthMode: x509`). Required when `authorization` is enabled.

**Q: Is MongoDB vulnerable to injection?**
Not to SQL injection, but to **operator injection** when user input is placed directly into query documents (`{ $gt: "" }`, `{ $ne: null }`), and to JavaScript injection through `$where`/`mapReduce`. Fix: validate/cast inputs, strip `$` keys, never build queries from raw JSON, avoid server-side JS.

**Q: What is Client-Side Field Level Encryption?**
The driver encrypts chosen fields (e.g. SSN) with keys from a KMS before sending; the server stores ciphertext and cannot decrypt. Queryable Encryption (7.0+) allows equality / range queries on encrypted fields.

**Q: What are the main items of a production security checklist?**
Auth on + least-privilege users; TLS everywhere; bind to private network + firewall; encryption at rest; auditing; regular patching; backups tested; secrets management; monitoring of failed logins; no `$where`; input validation.

## 5. Checklist

- [ ] I can explain authentication vs authorization, users, roles, privileges and the authentication database
- [ ] I can create users with built-in roles and a custom least-privilege role, list / update / drop them
- [ ] I can enable access control (config, localhost exception, keyFile for replica sets) and connect with a URI
- [ ] I have seen "not authorized" errors and know how to read `connectionStatus`
- [ ] I can list the production security checklist and explain operator injection
