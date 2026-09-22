# 00_Setup — Practice Database (`companyDB`)

One small **Company / Sales** dataset is used by **every level**, so you never have to
re-learn a new schema. It is the **same data as the SQL Server course** (`SQLPractice`),
reshaped the MongoDB way — so you can ask the same question in T-SQL and in MongoDB and compare.

## 1. Get a MongoDB server running (pick ONE)

| Option | How | Notes |
|--------|-----|-------|
| **A. Docker (recommended)** | in this folder: `docker compose up -d` | MongoDB 8 as a **1-node replica set** (needed for transactions & change streams) + mongo-express UI on <http://localhost:8081>. Data survives restarts (volume). |
| B. Plain docker run | `docker run -d --name mongo-practice -p 27017:27017 -v mongo-practice-data:/data/db mongo:8 --replSet rs0` then `mongosh --eval "rs.initiate()"` | Same thing without compose. |
| C. Native install | [MongoDB Community Server](https://www.mongodb.com/try/download/community) (Windows service) | Add `replication: replSetName: rs0` to `mongod.cfg`, restart the service, run `rs.initiate()` once — otherwise Levels 14 and 17 will not work. |

Check it works:

```
mongosh --eval "db.version()"          -> 8.x
mongosh --eval "rs.status().ok"        -> 1   (replica set is initiated)
```

## 2. Tools you will use

| Tool | What for | Already on this machine |
|------|----------|--------------------------|
| **mongosh** | the shell — every script in this course runs here | yes (`mongosh --version`) |
| **MongoDB Compass** | GUI: browse documents, build aggregations visually, explain plans, embedded shell | yes |
| **VS Code + "MongoDB for VS Code" extension** | open any `*.js` file here as a **Playground**: select lines → *Run Selected Lines* (closest thing to SSMS "select + F5") | install from the Extensions panel |
| **mongo-express** | quick web UI (comes with the compose file) | <http://localhost:8081> |
| **MongoDB Database Tools** | `mongodump`, `mongorestore`, `mongoexport`, `mongoimport` (Level 16) | run them inside the container: `docker exec mongo-practice mongodump ...` |
| **Node.js 24** | Level 19 (driver + Mongoose + Express API) | yes |

## 3. Files

| File | What it does | When to run |
|------|--------------|-------------|
| `docker-compose.yml` | Starts MongoDB 8 (replica set `rs0`) + mongo-express | **First time**, then `docker compose start` after a reboot |
| `00_Reset_All.js` | Drop + create DB, collections, indexes, data (= 01 + 02) | **First time**, and any time you want clean data |
| `01_Create_Collections.js` | Creates `companyDB`, 5 collections, 3 unique indexes | Read to learn `createCollection` / unique & partial indexes |
| `02_Insert_Sample_Data.js` | Loads the documents + sanity check | Read to see the data |

Three ways to run any script in this course:

```
# 1. terminal (whole file; only print()/printjson() output is shown)
mongosh --file "E:\Practice\MongoDB\00_Setup\00_Reset_All.js"

# 2. inside mongosh
load("E:/Practice/MongoDB/00_Setup/00_Reset_All.js")

# 3. VS Code: open the file, "MongoDB: Run All" / "Run Selected Lines" from the playground toolbar
```

> Practice files are meant to be run **block by block** (paste a block into mongosh, or select it in a VS Code
> Playground) so you see every result. When a whole file is run with `--file`, bare expressions such as
> `db.employees.find()` are **not** printed — only `print()` / `printjson()` output is.
> To run a whole practice file and see everything, pipe it into the shell (results are then echoed like in the REPL):
> `Get-Content 01_Practice.js -Raw | mongosh --quiet` (PowerShell) · `mongosh --quiet < 01_Practice.js` (bash).

## 4. Data model

```
 departments (6)                        customers (8)
 ─────────────                          ─────────────
 _id        1..6  (custom, not ObjectId) _id          1..8
 name       UNIQUE index                 name
 location                                email        (null for #6, MISSING for #8)  partial unique index
      │ 1                                city
      │                                  createdDate  Date
      │ *                                tags         [ "vip", "newsletter", ... ]  ([] for #3, missing for #6, #8)
 employees (12)                               │ 1
 ─────────────                                │
 _id          101..112                        │ *
 name                                    orders (19)
 email        UNIQUE index (MISSING for 110)  ─────────────
 departmentId 1..5 | null (110)          _id          1001..1019
 salary       number (65000 twice!)      customerId   → customers._id
 hireDate     Date                       employeeId   → employees._id  (null for 1019 = online order)
 managerId    → employees._id | null     orderDate    Date  (Jan–Sep 2025)
 skills       [ "MongoDB", ... ]         status       "Pending" | "Completed" | "Cancelled"
              ([] for 110, MISSING 112)  totalAmount  number  = Σ items.qty * items.unitPrice
 address      { city, state, pincode }   payment      { method: "Card"|"UPI"|"COD", paid: bool }
 active       bool (false for 112)       items        [ { productId → products._id, qty, unitPrice }, ... ]   ← embedded order lines
      │                                        │
      └── salesperson of ──────────────────────┘
 products (11)
 ─────────────
 _id       1..11
 name
 category  "Electronics" | "Furniture" | "Stationery"
 price     number
 stock     number (0 for #9)
 tags      [ "computer", "accessory", ... ]
 ratings   [ 5, 4, 5 ]  ([] for #5, #11 · MISSING for #7)
```

**SQL → MongoDB mapping used here**

| SQL Server (`SQLPractice`) | MongoDB (`companyDB`) | Why |
|---|---|---|
| table `dbo.Employees` | collection `employees` | naming convention: lowerCamel / plural |
| column `EmployeeID` (PK) | field `_id` (custom number) | every document must have `_id`; we chose our own instead of `ObjectId` so results are easy to predict |
| `OrderDetails` table (26 rows) | `orders.items` array (26 elements) | lines belong to one order and are read with it → **embed** |
| FK `Orders.CustomerID` | `orders.customerId` | **reference** (a customer is shared by many orders) → joined with `$lookup` |
| `UNIQUE (Email)` | `createIndex({email:1},{unique:true})` | constraints = indexes |
| `CHECK (Salary > 0)` | none (Level 13: `$jsonSchema` validator) | MongoDB is schema-free unless you add validation |
| `NULL` | `null` **or the field is missing** | two different things in MongoDB — the dataset has both |

## 5. Built-in "tricky" cases (interview favourites)

| Case | Where | Used in |
|------|-------|---------|
| Employee with **no department** (Anjali 110, `departmentId: null`) | `employees` | `$lookup` with null, `$ifNull` |
| Employee with **no email field** (Anjali 110) vs customer with `email: null` (Farhan 6) | `employees`, `customers` | `{email: null}` matches both · `$exists` · `$type` |
| **Empty array** (Anjali `skills: []`) vs **missing array** (Meera, no `skills`) | `employees` | `$size: 0`, `$exists`, `$unwind` drops both unless `preserveNullAndEmptyArrays` |
| Department with **no employees** (Legal 6) | `departments` | `$lookup` → empty array, anti-join |
| **Duplicate salaries** (Amit & Pooja = 65000) | `employees.salary` | `$rank` vs `$denseRank` vs `$documentNumber` |
| Self reference (`managerId`) | `employees` | `$graphLookup`, self `$lookup` |
| **Inactive** employee (Meera `active: false`) | `employees` | partial index, boolean filters |
| Customer with **no orders** (Hina 8) | `customers` | `$lookup` + `$match: {orders: []}` |
| Product **never ordered** (Webcam 11) | `products` | anti-join with `$lookup` |
| Product with **0 stock** (Headphones 9) | `products.stock` | `$cond`, divide-by-zero guard |
| **Ratings** `[]` (Desk, Webcam) vs missing (Notebook) | `products.ratings` | `$avg` of an array → `null`, `$ifNull` |
| Order with **no salesperson** (1019, `employeeId: null`) | `orders` | `$lookup` with null, `$ifNull: "(online)"` |
| Order **status** Pending / Cancelled | `orders.status` | `$cond`, partial index, conditional aggregation |
| Orders spread over 9 months | `orders.orderDate` | `$group` by month, `$setWindowFields` running totals |
| **Embedded array** `items` with `qty * unitPrice` | `orders.items` | `$unwind`, `$map`, `$reduce`, positional updates `$`, `$[]`, `$[i]` |

## 6. Quick look queries

```js
use("companyDB")
show("collections")
db.departments.find()
db.employees.find()
db.customers.find()
db.products.find()
db.orders.find()
db.orders.findOne({ _id: 1008 })          // an order with 3 items
db.employees.countDocuments()             // 12
```
