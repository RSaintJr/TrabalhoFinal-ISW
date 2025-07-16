# local-services/data-processor/app.py
import redis
import json
import pymongo
import os
import mysql.connector
from datetime import datetime
import logging
import threading
import time
from typing import Dict, Any, Optional
import backoff

class DataProcessor:
    def __init__(self):
        self.setup_logging()
        self.setup_database_connections()
        
    def setup_logging(self):
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
        )
        self.logger = logging.getLogger('DataProcessor')
        
    @backoff.on_exception(backoff.expo, 
                         (redis.ConnectionError, pymongo.errors.ConnectionFailure, mysql.connector.Error),
                         max_tries=5)
    def setup_database_connections(self):
        """Setup database connections with retries"""
        try:
            # Redis connection
            redis_host = os.getenv('REDIS_HOST', 'redis')
            self.logger.info(f"Connecting to Redis at {redis_host}")
            self.redis_client = redis.Redis(
                host=redis_host,
                port=6379,
                db=0,
                decode_responses=True,
                socket_timeout=5
            )
            self.redis_client.ping()
            self.logger.info("Successfully connected to Redis")
            
            # MySQL connection
            self.mysql_config = {
                'host': os.getenv('MYSQL_HOST', 'mysql'),
                'user': os.getenv('MYSQL_USER', 'root'),
                'password': os.getenv('MYSQL_PASSWORD', 'example'),
                'database': 'iot_agriculture',
                'connect_timeout': 10
            }
            self.test_mysql_connection()
            self.logger.info("Successfully connected to MySQL")
            
            # MongoDB connection
            mongo_uri = os.getenv('MONGODB_URI')
            if mongo_uri:
                self.mongo_client = pymongo.MongoClient(mongo_uri, serverSelectionTimeoutMS=5000)
            else:
                self.mongo_client = pymongo.MongoClient(
                    os.getenv('MONGODB_HOST', 'mongodb'),
                    username=os.getenv('MONGODB_USER', 'mongoadmin'),
                    password=os.getenv('MONGODB_PASSWORD', 'secret'),
                    authSource='admin',
                    serverSelectionTimeoutMS=5000
                )
            self.mongo_client.admin.command('ping')
            self.logger.info("Successfully connected to MongoDB")
            
            self.mongo_db = self.mongo_client.iot_agriculture
            self.mongo_collection = self.mongo_db.sensor_logs
            
        except Exception as e:
            self.logger.error(f"Failed to setup database connections: {e}")
            raise
            
    def test_mysql_connection(self) -> None:
        """Test MySQL connection and create table if not exists"""
        try:
            conn = mysql.connector.connect(**self.mysql_config)
            cursor = conn.cursor()
            
            # Create table if not exists
            create_table_query = """
            CREATE TABLE IF NOT EXISTS sensor_readings (
                id INT AUTO_INCREMENT PRIMARY KEY,
                sensor_id VARCHAR(50) NOT NULL,
                sensor_type VARCHAR(50) NOT NULL,
                location VARCHAR(50) NOT NULL,
                value FLOAT NOT NULL,
                timestamp VARCHAR(50) NOT NULL,
                quality VARCHAR(20),
                battery_level FLOAT,
                INDEX(sensor_id),
                INDEX(sensor_type)
            )
            """
            cursor.execute(create_table_query)
            conn.commit()
            cursor.close()
            conn.close()
            
        except mysql.connector.Error as e:
            self.logger.error(f"MySQL Error: {e}")
            raise
            
    def validate_sensor_data(self, data: Dict[str, Any]) -> Optional[str]:
        """Validate sensor data format and values"""
        required_fields = ['sensor_id', 'sensor_type', 'location', 'value', 'timestamp']
        for field in required_fields:
            if field not in data:
                return f"Missing required field: {field}"
                
        if not isinstance(data['value'], (int, float)):
            return "Value must be a number"
            
        valid_types = {'temperature', 'humidity', 'ph'}
        if data['sensor_type'] not in valid_types:
            return f"Invalid sensor type. Must be one of: {valid_types}"
            
        try:
            datetime.fromisoformat(data['timestamp'].replace('Z', '+00:00'))
        except ValueError:
            return "Invalid timestamp format"
            
        return None
        
    def process_sensor_data(self, data: Dict[str, Any]) -> bool:
        """Process and validate sensor data"""
        try:
            # Data validation
            validation_error = self.validate_sensor_data(data)
            if validation_error:
                self.logger.error(f"Invalid sensor data: {validation_error}")
                return False
                
            # Data enrichment
            enriched_data = self.enrich_data(data)
            
            # Store in MySQL
            self.store_in_mysql(enriched_data)
            
            # Store in MongoDB
            self.store_in_mongodb(enriched_data)
            
            # Generate alerts if needed
            self.check_alerts(enriched_data)
            
            return True
            
        except Exception as e:
            self.logger.error(f"Error processing sensor data: {e}", exc_info=True)
            return False
    
    def enrich_data(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Enrich data with additional information"""
        enriched = data.copy()
        enriched['processed_at'] = datetime.now().isoformat()
        enriched['status'] = 'processed'
        
        # Add weather correlation (mock)
        enriched['weather_condition'] = self.get_weather_condition()
        
        return enriched
    
    def get_weather_condition(self) -> str:
        """Mock weather condition"""
        import random
        return random.choice(['sunny', 'cloudy', 'rainy'])
    
    @backoff.on_exception(backoff.expo, mysql.connector.Error, max_tries=3)
    def store_in_mysql(self, data: Dict[str, Any]) -> None:
        """Store structured data in MySQL with retry"""
        try:
            conn = mysql.connector.connect(**self.mysql_config)
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
                data.get('quality'),
                data.get('battery_level')
            ))
            
            conn.commit()
            cursor.close()
            conn.close()
            
        except mysql.connector.Error as e:
            self.logger.error(f"Error storing in MySQL: {e}")
            raise
    
    @backoff.on_exception(backoff.expo, pymongo.errors.PyMongoError, max_tries=3)
    def store_in_mongodb(self, data: Dict[str, Any]) -> None:
        """Store logs and metadata in MongoDB with retry"""
        try:
            self.mongo_collection.insert_one(data)
        except pymongo.errors.PyMongoError as e:
            self.logger.error(f"Error storing in MongoDB: {e}")
            raise
    
    def check_alerts(self, data: Dict[str, Any]) -> None:
        """Check for alert conditions"""
        alerts = []
        
        # Temperature alerts
        if data['sensor_type'] == 'temperature':
            if data['value'] > 35:
                alerts.append({'type': 'high_temperature', 'value': data['value']})
            elif data['value'] < 5:
                alerts.append({'type': 'low_temperature', 'value': data['value']})
        
        # Humidity alerts
        if data['sensor_type'] == 'humidity':
            if data['value'] < 30:
                alerts.append({'type': 'low_humidity', 'value': data['value']})
        
        # pH alerts
        if data['sensor_type'] == 'ph':
            if data['value'] < 6.0 or data['value'] > 8.0:
                alerts.append({'type': 'ph_out_of_range', 'value': data['value']})
        
        # Process alerts
        for alert in alerts:
            self.process_alert(alert, data)
    
    def process_alert(self, alert: Dict[str, Any], data: Dict[str, Any]) -> None:
        """Process generated alerts"""
        try:
            alert_data = {
                'alert_type': alert['type'],
                'sensor_id': data['sensor_id'],
                'value': alert['value'],
                'timestamp': datetime.now().isoformat(),
                'severity': self.get_alert_severity(alert['type'])
            }
            
            # Store alert in MongoDB
            self.mongo_db.alerts.insert_one(alert_data)
            
            self.logger.warning(f"Alert generated: {alert_data}")
        except Exception as e:
            self.logger.error(f"Error processing alert: {e}", exc_info=True)
    
    def get_alert_severity(self, alert_type: str) -> str:
        """Determine alert severity"""
        high_severity = ['high_temperature', 'ph_out_of_range']
        return 'high' if alert_type in high_severity else 'medium'
    
    def run(self):
        """Main processing loop"""
        self.logger.info("Data Processor is running and waiting for sensor data...")
        
        while True:
            try:
                # Use BRPOP with timeout to avoid busy waiting
                # This blocks for 1 second waiting for data
                result = self.redis_client.brpop('sensor_data', timeout=1)
                
                if result:
                    _, data_json = result  # BRPOP returns (key, value)
                    self.logger.info(f"Retrieved data from Redis: {data_json[:100]}...") # Log snippet
                    
                    try:
                        data = json.loads(data_json)
                        self.logger.info(f"Processing data from sensor {data.get('sensor_id')}")
                        
                        if self.process_sensor_data(data):
                            self.logger.info(f"Successfully processed data from sensor {data.get('sensor_id')}")
                        else:
                            self.logger.error(f"Failed to process data from sensor {data.get('sensor_id')}")
                            # Store failed data in a separate list for manual review
                            self.redis_client.rpush('failed_sensor_data', data_json)
                    except json.JSONDecodeError as e:
                        self.logger.error(f"Invalid JSON data received: {e}")
                        self.redis_client.rpush('failed_sensor_data', data_json)
                        
            except redis.ConnectionError as e:
                self.logger.error(f"Redis connection lost: {e}. Attempting to reconnect...")
                time.sleep(5)
                self.setup_database_connections() # Re-establish connections
                
            except Exception as e:
                self.logger.error(f"An unexpected error occurred in the main loop: {e}", exc_info=True)
                time.sleep(5) # Wait before retrying

if __name__ == "__main__":
    processor = DataProcessor()
    processor.run()