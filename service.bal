import ballerina/http;
import ballerinax/mongodb;

configurable string host = ?;
configurable string database = ?;
configurable string resultHost = "localhost:9091";
const string creditCollection = "credits";
const string slotMachineRecordsCollection = "slot_machine_records";

final mongodb:Client mongoDb = check new ({
    connection: host
});

# A service representing a network-accessible API
# bound to port `9090`.
service / on new http:Listener(9092) {
    private final mongodb:Database Db;

    function init() returns error? {
        self.Db = check mongoDb->getDatabase(database);
    }

    resource function get slotmachineresults/[string email]() returns SlotMachineReport[]|error {
        mongodb:Collection smCollection = check self.Db->getCollection(slotMachineRecordsCollection);
        stream<SlotMachineReport, error?> resultStream = check smCollection->aggregate([
            {
                \$group: {
                    _id: null,
                    orig: {
                        \$push: "$$ROOT"
                    },
                    "total": {
                        \$sum: "$amount"
                    }
                }
            },
            {
                \$unwind: "$orig"
            },
            {
                \$project: {
                    date: "$orig.date",
                    amount: "$orig.amount",
                    email: "$orig.email",
                    total: "$total"
                }
            },
            {
                \$match: {email: email}
            },
            {
                \$group: {
                    _id: "$date",
                    amount: {
                        \$sum: "$amount"
                    },
                    orig: {
                        \$push: "$$ROOT.total"
                    }
                }
            },
            {
                "$unwind": "$orig"
            },
            {
                \$group: {
                    _id: {
                        _id: "$_id",
                        amount: "$amount"
                    }
                }
            },
            {
                \$project: {
                    date: "$_id._id",
                    "amount": "$_id.amount",
                    _id: 0
                }
            }
        ]);

        return from SlotMachineReport slms in resultStream
            select slms;
    }
}

public type SlotMachineReport record {|
    int amount;
    string date;
|};
