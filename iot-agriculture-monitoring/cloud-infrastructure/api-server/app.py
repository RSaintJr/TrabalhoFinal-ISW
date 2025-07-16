# cloud-infrastructure/api-server/app.py
from flask import Flask, request, jsonify
import redis
import pymongo
import mysql.connector
import json
import logging
from datetime import datetime, timedelta
import os
from flask_cors import CORS

app = Flask(__name__)
CORS(app)

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Database connections
def get_mysql_connection():
    return mysql.connector.connect(
        host='localhost',
        user='iot_user',
        password='iot_password_123',
        database='iot_agriculture'
    )

def get_mongodb_connection():
    client = pymongo.MongoClient('mongodb://localhost:27017/')
    return client.iot_agriculture

def get_redis_connection():
    return redis.Redis(host='localhost', port=6379, db=0)

@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({
        'status': 'healthy',
        'timestamp': datetime.now().isoformat(),
        'services': {
            'mysql': check_mysql_health(),
            'mongodb': check_mongodb_health(),
            'redis': check_redis_health()
        }
    })

def check_mysql_health():
    try:
        conn = get_mysql_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT 1")
        cursor.fetchone()
        cursor.close()
        conn.close()
        return 'healthy'
    except Exception as e:
        logger.error(f"MySQL health check failed: {e}")
        return 'unhealthy'

def check_mongodb_health():
    try:
        db = get_mongodb_connection()
        db.command('ping')
        return 'healthy'
    except Exception as e:
        logger.error(f"MongoDB health check failed: {e}")
        return 'unhealthy'

def check_redis_health():
    try:
        r = get_redis_connection()
        r.ping()
        return 'healthy'
    except Exception as e:
        logger.error(f"Redis health check failed: {e}")
        return 'unhealthy'

@app.route('/api/ingest', methods=['POST'])
def ingest_sensor_data():
    try:
        data = request.json
        
        # Validate required fields
        required_fields = ['sensor_id', 'sensor_type', 'location', 'value', 'timestamp']
        for field in required_fields:
            if field not in data:
                return jsonify({'error': f'Missing required field: {field}'}), 400
        
        # Store in MySQL
        store_in_mysql(data)
        
        # Store in MongoDB
        store_in_mongodb(data)
        
        # Cache in Redis
        cache_in_redis(data)
        
        # Process alerts
        alerts = process_alerts(data)
        
        return jsonify({
            'success': True,
            'message': 'Data ingested successfully',
            'alerts': alerts
        }), 200
        
    except Exception as e:
        logger.error(f"Error ingesting data: {e}")
        return jsonify({'error': 'Internal server error'}), 500

def store_in_mysql(data):
    conn = get_mysql_connection()
    cursor = conn.cursor()
    
    insert_query = """
    INSERT INTO sensor_readings 
    (sensor_id, sensor_type, location, value, timestamp, quality, battery_level)
    VALUES (%s, %s, %s, %s, %s, %s, %s)
    """
    
    cursor.execute(insert_query, (
        data['sensor_id'],
        data['sensor_type'],
        data['location'],
        data['value'],
        data['timestamp'],
        data.get('quality', 'unknown'),
        data.get('battery_level', 0)
    ))
    
    conn.commit()
    cursor.close()
    conn.close()

def store_in_mongodb(data):
    db = get_mongodb_connection()
    collection = db.sensor_logs
    
    document = data.copy()
    document['processed_at'] = datetime.now().isoformat()
    
    collection.insert_one(document)

def cache_in_redis(data):
    r = get_redis_connection()
    
    # Cache latest readings by sensor
    key = f"sensor:{data['sensor_id']}:latest"
    r.set(key, json.dumps(data), ex=3600)  # 1 hour expiration
    
    # Cache in time series
    ts_key = f"sensor:{data['sensor_id']}:timeseries"
    r.lpush(ts_key, json.dumps(data))
    r.ltrim(ts_key, 0, 1000)  # Keep only last 1000 readings

def process_alerts(data):
    alerts = []
    
    # Temperature alerts
    if data['sensor_type'] == 'temperature':
        if data['value'] > 35:
            alert = create_alert('high_temperature', data, 'high')
            alerts.append(alert)
        elif data['value'] < 5:
            alert = create_alert('low_temperature', data, 'high')
            alerts.append(alert)
    
    # Humidity alerts
    elif data['sensor_type'] == 'humidity':
        if data['value'] < 30:
            alert = create_alert('low_humidity', data, 'medium')
            alerts.append(alert)
        elif data['value'] > 90:
            alert = create_alert('high_humidity', data, 'medium')
            alerts.append(alert)
    
    # pH alerts
    elif data['sensor_type'] == 'ph':
        if data['value'] < 6.0 or data['value'] > 8.0:
            alert = create_alert('ph_out_of_range', data, 'high')
            alerts.append(alert)
    
    # Store alerts
    for alert in alerts:
        store_alert(alert)
    
    return alerts

def create_alert(alert_type, data, severity):
    return {
        'alert_type': alert_type,
        'sensor_id': data['sensor_id'],
        'value': data['value'],
        'severity': severity,
        'timestamp': datetime.now().isoformat(),
        'location': data['location']
    }

def store_alert(alert):
    # Store in MySQL
    conn = get_mysql_connection()
    cursor = conn.cursor()
    
    insert_query = """
    INSERT INTO alerts 
    (alert_type, sensor_id, value, severity, timestamp)
    VALUES (%s, %s, %s, %s, %s)
    """
    
    cursor.execute(insert_query, (
        alert['alert_type'],
        alert['sensor_id'],
        alert['value'],
        alert['severity'],
        alert['timestamp']
    ))
    
    conn.commit()
    cursor.close()
    conn.close()
    
    # Store in MongoDB
    db = get_mongodb_connection()
    collection = db.alerts
    collection.insert_one(alert)

@app.route('/api/sensors', methods=['GET'])
def get_sensors():
    try:
        conn = get_mysql_connection()
        cursor = conn.cursor(dictionary=True)
        
        query = """
        SELECT DISTINCT sensor_id, sensor_type, location,
               MAX(timestamp) as last_seen,
               COUNT(*) as reading_count
        FROM sensor_readings 
        WHERE timestamp > DATE_SUB(NOW(), INTERVAL 24 HOUR)
        GROUP BY sensor_id, sensor_type, location
        ORDER BY last_seen DESC
        """
        
        cursor.execute(query)
        sensors = cursor.fetchall()
        
        cursor.close()
        conn.close()
        
        return jsonify(sensors)
        
    except Exception as e:
        logger.error(f"Error fetching sensors: {e}")
        return jsonify({'error': 'Internal server error'}), 500

@app.route('/api/sensors/<sensor_id>/data', methods=['GET'])
def get_sensor_data(sensor_id):
    try:
        hours = request.args.get('hours', 24, type=int)
        
        conn = get_mysql_connection()
        cursor = conn.cursor(dictionary=True)
        
        query = """
        SELECT * FROM sensor_readings 
        WHERE sensor_id = %s 
        AND timestamp > DATE_SUB(NOW(), INTERVAL %s HOUR)
        ORDER BY timestamp DESC
        LIMIT 1000
        """
        
        cursor.execute(query, (sensor_id, hours))
        data = cursor.fetchall()
        
        cursor.close()
        conn.close()
        
        return jsonify(data)
        
    except Exception as e:
        logger.error(f"Error fetching sensor data: {e}")
        return jsonify({'error': 'Internal server error'}), 500

@app.route('/api/analytics/summary', methods=['GET'])
def get_analytics_summary():
    try:
        conn = get_mysql_connection()
        cursor = conn.cursor(dictionary=True)
        
        # Get summary statistics
        query = """
        SELECT 
            sensor_type,
            AVG(value) as avg_value,
            MIN(value) as min_value,
            MAX(value) as max_value,
            COUNT(*) as reading_count
        FROM sensor_readings 
        WHERE timestamp > DATE_SUB(NOW(), INTERVAL 24 HOUR)
        GROUP BY sensor_type
        """
        
        cursor.execute(query)
        summary = cursor.fetchall()
        
        # Get alert counts
        alert_query = """
        SELECT severity, COUNT(*) as count
        FROM alerts 
        WHERE timestamp > DATE_SUB(NOW(), INTERVAL 24 HOUR)
        GROUP BY severity
        """
        
        cursor.execute(alert_query)
        alerts = cursor.fetchall()
        
        cursor.close()
        conn.close()
        
        return jsonify({
            'summary': summary,
            'alerts': alerts,
            'timestamp': datetime.now().isoformat()
        })
        
    except Exception as e:
        logger.error(f"Error fetching analytics: {e}")
        return jsonify({'error': 'Internal server error'}), 500

@app.route('/api/alerts', methods=['GET'])
def get_alerts():
    try:
        severity = request.args.get('severity')
        acknowledged = request.args.get('acknowledged', type=bool)
        
        conn = get_mysql_connection()
        cursor = conn.cursor(dictionary=True)
        
        query = "SELECT * FROM alerts WHERE timestamp > DATE_SUB(NOW(), INTERVAL 7 DAY)"
        params = []
        
        if severity:
            query += " AND severity = %s"
            params.append(severity)
        
        if acknowledged is not None:
            query += " AND acknowledged = %s"
            params.append(acknowledged)
        
        query += " ORDER BY timestamp DESC LIMIT 100"
        
        cursor.execute(query, params)
        alerts = cursor.fetchall()
        
        cursor.close()
        conn.close()
        
        return jsonify(alerts)
        
    except Exception as e:
        logger.error(f"Error fetching alerts: {e}")
        return jsonify({'error': 'Internal server error'}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=3000, debug=False)