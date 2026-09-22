/* ============================================================
   LEVEL 19  |  02_mongoose_models.js  -  Mongoose ODM
   ------------------------------------------------------------
   Run:  cd app && npm run mongoose
   Topics : connect, Schema (types, validation, defaults, enum,
            sub-documents, arrays, refs, indexes, timestamps),
            Model CRUD, lean, query builder, validation errors,
            casting, strict mode, virtuals, methods/statics,
            middleware, populate vs $lookup, transactions,
            syncIndexes
   Uses collections l19m_* (dropped at the end).
   ============================================================ */

import mongoose from "mongoose";
const { Schema, model, Types } = mongoose;
const step = (t) => console.log("\n=== " + t + " ===");

await mongoose.connect(process.env.MONGODB_URI || "mongodb://localhost:27017/companyDB", { appName: "level19-mongoose", maxPoolSize: 10, serverSelectionTimeoutMS: 5000 });
console.log("mongoose connected:", mongoose.connection.readyState === 1, "| version", mongoose.version);


step("1. Schemas and models");
const departmentSchema = new Schema({
    name: { type: String, required: true, unique: true, trim: true },
    location: String
}, { collection: "l19m_departments" });

const addressSchema = new Schema({ city: { type: String, required: true }, state: String, pincode: { type: Number, min: 100000, max: 999999 } }, { _id: false });

const employeeSchema = new Schema({
    name:       { type: String, required: [true, "name is required"], trim: true, minlength: 2, maxlength: 50 },
    email:      { type: String, lowercase: true, trim: true, match: [/^[^@\s]+@[^@\s]+\.[a-z]{2,}$/, "invalid email"], index: true, sparse: true },
    salary:     { type: Number, required: true, min: [1, "salary must be positive"] },
    status:     { type: String, enum: ["active", "on-leave", "left"], default: "active" },
    hireDate:   { type: Date, default: Date.now },
    skills:     { type: [String], validate: { validator: (v) => v.length <= 20, message: "too many skills" } },
    address:    addressSchema,                                                     // embedded sub-document
    department: { type: Schema.Types.ObjectId, ref: "Department" },              // REFERENCE (for populate)
    managerId:  { type: Number, default: null },
    secret:     { type: String, select: false }                                    // never returned unless .select("+secret")
}, {
    timestamps: true, collection: "l19m_employees",                                 // createdAt / updatedAt maintained automatically
    toJSON: { virtuals: true, versionKey: false, transform: (_doc, ret) => { delete ret.secret; delete ret.id; return ret; } }   // shape API output (set at schema creation!)
});

employeeSchema.index({ salary: -1 });
employeeSchema.index({ "address.city": 1, salary: -1 });

// virtuals (computed, not stored), instance methods, statics
employeeSchema.virtual("annualSalary").get(function () { return this.salary * 12; });
employeeSchema.methods.giveRaise = function (pct) { this.salary = Math.round(this.salary * (1 + pct / 100)); return this.save(); };
employeeSchema.statics.findByCity = function (city) { return this.find({ "address.city": city }); };

// middleware (hooks)
employeeSchema.pre("save", function (next) { if (this.isModified("name")) this.name = this.name.replace(/\s+/g, " "); next(); });
employeeSchema.post("save", function (doc) { console.log("   [post save]", doc.name, "saved (isNew was handled)"); });
employeeSchema.pre(/^find/, function () { this.where({ status: { $ne: "left" } }); });   // query middleware: soft-delete filter on every find*

const Department = model("Department", departmentSchema);
const Employee = model("Employee", employeeSchema);
await Department.deleteMany({}); await Employee.deleteMany({});
await Employee.syncIndexes();                              // create/drop indexes to match the schema (do this in a migration, not on every boot)
console.log("indexes:", (await Employee.collection.indexes()).map(i => i.name));


step("2. create / save / validation errors / casting");
const it = await Department.create({ name: "IT", location: "Delhi" });
const sales = await Department.create({ name: "Sales", location: "Mumbai" });
const rahul = await Employee.create({ name: "  Rahul   Sharma ", email: "RAHUL@Example.com", salary: 85000, skills: ["Java"], address: { city: "Delhi", pincode: 110001 }, department: it._id, secret: "s3cr3t" });
console.log("created:", { name: rahul.name, email: rahul.email, status: rahul.status, annual: rahul.annualSalary, createdAt: !!rahul.createdAt, id: rahul._id instanceof Types.ObjectId });

try {
    await Employee.create({ name: "X", salary: -5, status: "fired", email: "nope" });
} catch (e) {
    console.log("EXPECTED ValidationError:", Object.keys(e.errors).map(k => k + ": " + e.errors[k].message));
}
try {
    await Employee.create({ name: "Cast", salary: "abc" });
} catch (e) {
    console.log("EXPECTED CastError:", e.errors.salary.name, "-", e.errors.salary.message.substring(0, 50));
}
const casted = await Employee.create({ name: "Casted", salary: "60000", unknownField: 1 });   // "60000" -> 60000 ; unknownField DROPPED (strict mode)
console.log("casting:", typeof casted.salary, "| unknown field kept?", casted.toObject().unknownField !== undefined);
try {
    await Employee.create({ name: "Dup mail", salary: 1, email: "rahul@example.com" });
} catch (e) {
    console.log("EXPECTED duplicate (index, not validator):", e.code);   // 11000
}


step("3. queries: builder, select, lean, sort, pagination");
await Employee.insertMany([
    { name: "Amit", salary: 65000, address: { city: "Noida" }, department: it._id, managerId: 101 },
    { name: "Priya", salary: 75000, address: { city: "Mumbai" }, department: sales._id },
    { name: "Neha", salary: 55000, address: { city: "Mumbai" }, department: sales._id, status: "left" }
]);
const highPaid = await Employee.find({ salary: { $gte: 65000 } }).select("name salary -_id").sort("-salary").limit(5).lean();
console.log("lean:", highPaid, "| plain objects:", !(highPaid[0] instanceof mongoose.Document));
console.log("find() hides 'left' via query middleware:", (await Employee.find().lean()).map(e => e.name));
console.log("statics:", (await Employee.findByCity("Mumbai")).map(e => e.name));   // Priya only (Neha left)
console.log("select +secret:", (await Employee.findOne({ name: "Rahul Sharma" }).select("+secret")).secret);
console.log("page 2 (size 2):", (await Employee.find().sort({ salary: -1, _id: 1 }).skip(2).limit(2).select("name -_id").lean()).map(e => e.name));
console.log("countDocuments:", await Employee.countDocuments(), "| exists:", !!(await Employee.exists({ name: "Amit" })));


step("4. updates: save() vs findOneAndUpdate (runValidators!)");
await rahul.giveRaise(10);                                 // instance method -> save() -> pre/post save hooks, validators
console.log("after raise:", (await Employee.findById(rahul._id).lean()).salary);   // 93500
const upd = await Employee.findOneAndUpdate({ name: "Amit" }, { $inc: { salary: 1000 }, $set: { status: "on-leave" } }, { new: true, runValidators: true }).lean();
console.log("findOneAndUpdate new:", upd.salary, upd.status);
try {
    await Employee.findOneAndUpdate({ name: "Amit" }, { salary: -1 }, { runValidators: true });
} catch (e) {
    console.log("EXPECTED (runValidators):", e.errors.salary.message);
}
await Employee.findOneAndUpdate({ name: "Amit" }, { salary: -1 });   // WITHOUT runValidators: silently accepted!
console.log("without runValidators the bad value is stored:", (await Employee.findOne({ name: "Amit" }).lean()).salary);
await Employee.updateOne({ name: "Amit" }, { $set: { salary: 66000 } });
console.log("updateMany:", (await Employee.updateMany({ "address.city": "Mumbai" }, { $addToSet: { skills: "Sales" } })).modifiedCount);


step("5. populate (client-side join) vs aggregate $lookup");
const withDept = await Employee.findOne({ name: "Rahul Sharma" }).populate("department", "name location").lean();
console.log("populate:", withDept.department);             // { _id, name: 'IT', location: 'Delhi' }  (a second query under the hood)
const viaLookup = await Employee.aggregate([
    { $match: { status: { $ne: "left" } } },
    { $lookup: { from: "l19m_departments", localField: "department", foreignField: "_id", as: "d" } },
    { $group: { _id: { $first: "$d.name" }, n: { $sum: 1 }, avg: { $avg: "$salary" } } },
    { $sort: { _id: 1 } }
]);
console.log("$lookup report:", viaLookup);                 // aggregate() bypasses middleware and casting - filter explicitly


step("6. transactions with mongoose");
const session = await mongoose.startSession();
try {
    await session.withTransaction(async () => {
        const [emp] = await Employee.create([{ name: "Txn Person", salary: 1, department: it._id }], { session });   // create() with array + session
        await Department.updateOne({ _id: it._id }, { $inc: { headcount: 1 } }, { session });
        throw new Error("simulate failure after 2 writes");
    });
} catch (e) {
    console.log("aborted:", e.message, "| Txn Person exists?", await Employee.exists({ name: "Txn Person" }));   // null
} finally {
    await session.endSession();
}


step("7. documents vs plain objects, toObject vs toJSON");
const doc = await Employee.findOne({ name: "Rahul Sharma" }).select("+secret");
const asObject = doc.toObject(), asJson = doc.toJSON();      // toObject: raw fields (incl. __v, secret); toJSON: the schema's toJSON options applied
console.log({ isDocument: doc instanceof mongoose.Document, versionKeyInObject: asObject.__v, secretInObject: asObject.secret,
              jsonHasVirtual: asJson.annualSalary, jsonHasVersionKey: "__v" in asJson, jsonHasSecret: "secret" in asJson });
// -> JSON.stringify(doc) / res.json(doc) use toJSON: virtuals included, __v and secret removed. Set these options when you define the schema.


step("cleanup");
await Employee.collection.drop(); await Department.collection.drop();
await mongoose.disconnect();
console.log("disconnected");
