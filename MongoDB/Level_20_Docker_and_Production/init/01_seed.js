// Runs ONCE when the container starts with an EMPTY data volume (docker-entrypoint-initdb.d),
// authenticated as the root user, against MONGO_INITDB_DATABASE (here: appdb).
db.createCollection("items");
db.items.insertMany([
    { _id: 1, sku: "BOLT-10", qty: 100, price: 2.5 },
    { _id: 2, sku: "NUT-10",  qty: 250, price: 1.1 },
    { _id: 3, sku: "WASHER",  qty: 500, price: 0.2 }
]);
db.items.createIndex({ sku: 1 }, { unique: true });
db.createUser({ user: "appUser", pwd: "AppPass#1", roles: [ { role: "readWrite", db: "appdb" } ] });
print("seed done: " + db.items.countDocuments() + " items, appUser created");
