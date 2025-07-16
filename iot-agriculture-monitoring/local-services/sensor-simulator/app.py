# local-services/sensor-simulator/app.py
import random
import time
import json
import requests
import redis
from datetime import datetime
import logging
import os

class IoTSensorSimulator:
    def __init__(self):
        self.setup_logging()
        self.setup_redis()
        self.api_gateway_url = os.getenv('API_GATEWAY_URL', 'http://api-gateway:3000')
        self.sensors = self.initialize_sensors()
        
    def setup_logging(self):
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
        )
        self.logger = logging.getLogger('IoTSensorSimulator')
        
    def setup_redis(self):
        try:
            redis_host = os.getenv('REDIS_HOST', 'redis')
            self.logger.info(f"Connecting to Redis at {redis_host}")
            self.redis_client = redis.Redis(
                host=redis_host,
                port=6379,
                db=0,
                decode_responses=True,
                socket_timeout=5,
                retry_on_timeout=True
            )
            self.redis_client.ping()
            self.logger.info("Successfully connected to Redis")
        except redis.ConnectionError as e:
            self.logger.error(f"Failed to connect to Redis: {e}")
            raise
    
    def initialize_sensors(self):
        sensors = [
            {"id": f"temperature_sensor_{i}", "type": "temperature", "location": f"field_{i//10}"} 
            for i in range(1, 21)
        ] + [
            {"id": f"humidity_sensor_{i}", "type": "humidity", "location": f"field_{i//10}"} 
            for i in range(1, 21)
        ] + [
            {"id": f"ph_sensor_{i}", "type": "ph", "location": f"field_{i//10}"} 
            for i in range(1, 11)
        ]
        self.logger.info(f"Initialized {len(sensors)} sensors")
        return sensors
    
    def generate_sensor_data(self, sensor):
        base_values = {
            "temperature": random.uniform(18, 35),
            "humidity": random.uniform(40, 80),
            "ph": random.uniform(6.0, 8.0)
        }
        
        data = {
            "sensor_id": sensor["id"],
            "sensor_type": sensor["type"],
            "location": sensor["location"],
            "value": base_values[sensor["type"]],
            "timestamp": datetime.now().isoformat(),
            "quality": random.choice(["good", "fair", "poor"]),
            "battery_level": random.uniform(20, 100)
        }
        self.logger.info(f"Generated data for {sensor['id']}: value={data['value']:.2f}")
        return data
    
    def send_to_cache(self, data):
        try:
            self.redis_client.lpush("sensor_data", json.dumps(data))
            self.redis_client.expire("sensor_data", 3600)
            self.logger.info(f"Cached data for sensor {data['sensor_id']}")
        except Exception as e:
            self.logger.error(f"Error caching data: {e}", exc_info=True)
    
    def send_to_api_gateway(self, data):
        try:
            self.logger.info(f"Sending data to API Gateway at {self.api_gateway_url}")
            response = requests.post(
                f"{self.api_gateway_url}/api/sensor-data",
                json=data,
                timeout=5,
                headers={'Content-Type': 'application/json'}
            )
            response.raise_for_status()
            self.logger.info(f"Successfully sent data to API Gateway for sensor {data['sensor_id']}")
        except requests.RequestException as e:
            self.logger.error(f"Error sending to API Gateway: {e}", exc_info=True)
    
    def run(self):
        self.logger.info("Starting IoT Sensor Simulator...")
        while True:
            try:
                sensors_by_location = {}
                for sensor in self.sensors:
                    location = sensor['location']
                    if location not in sensors_by_location:
                        sensors_by_location[location] = []
                    sensors_by_location[location].append(sensor)

                for location, location_sensors in sensors_by_location.items():
                    timestamp = datetime.now().isoformat()
                    
                    location_data = []
                    for sensor in location_sensors:
                        data = self.generate_sensor_data(sensor)
                        data['timestamp'] = timestamp
                        location_data.append(data)
                    
                    for data in location_data:
                        self.send_to_api_gateway(data)
                    
                    time.sleep(0.1)
                
                self.logger.info("Completed one cycle of sensor data generation")
                time.sleep(5)
                
            except Exception as e:
                self.logger.error(f"Error in main loop: {e}", exc_info=True)
                time.sleep(5)

if __name__ == "__main__":
    simulator = IoTSensorSimulator()
    simulator.run()