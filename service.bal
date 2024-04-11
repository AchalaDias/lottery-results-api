import ballerina/http;
import ballerina/sql;
import ballerinax/mongodb;
import ballerinax/mysql;
import ballerinax/mysql.driver as _;

configurable string host = ?;
configurable string database = ?;
const string slotMachineRecordsCollection = "slot_machine_records";

configurable string mysqlHost = ?;
configurable string mysqlUser = ?;
configurable string mysqlPassword = ?;
configurable int mysqlPort = ?;

configurable string dbType = ?;

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

    resource function get health() returns string {
        return "Lotty results API is Running";
    }

    resource function get slotmachineresults/[string email]() returns SlotMachineReport[]|error {
        if dbType == "mysql" {
            mysql:Client mysqlDb = check getMysqlConnection();
            SlotMachineReport[] records = [];
            stream<SlotMachineReport, error?> resultStream = mysqlDb->query(`SELECT CAST(sum(amount) AS UNSIGNED) as amount, date FROM lotty.SlotMachineRecords WHERE email = ${email} group by date order by date`);
            check from SlotMachineReport rw in resultStream
                do {
                    records.push(rw);
                };
            check resultStream.close();
            return records;
        } else {
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
}

isolated function getMysqlConnection() returns mysql:Client|sql:Error {
    final mysql:Client|sql:Error dbClient = new (
        host = mysqlHost, user = mysqlUser, password = mysqlPassword, port = mysqlPort, database = database
    );
    return dbClient;
}

public type SlotMachineReport record {|
    int amount;
    string date;
|};
