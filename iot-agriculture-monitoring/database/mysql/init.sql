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
); 