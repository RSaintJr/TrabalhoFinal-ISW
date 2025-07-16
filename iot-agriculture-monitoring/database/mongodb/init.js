db = db.getSiblingDB('iot_agriculture');

// Sensor logs collection
if (!db.getCollectionNames().includes('sensor_logs')) {
    db.createCollection('sensor_logs');
}

db.sensor_logs.createIndex({ sensor_id: 1 });
db.sensor_logs.createIndex({ timestamp: -1 });

// Alerts collection
if (!db.getCollectionNames().includes('alerts')) {
    db.createCollection('alerts');
}

db.alerts.createIndex({ alert_type: 1 });
db.alerts.createIndex({ timestamp: -1 }); 