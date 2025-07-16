// local-services/api-gateway/app.js
const express = require('express');
const redis = require('redis');
const axios = require('axios');
const cors = require('cors');
const { MongoClient } = require('mongodb');

const app = express();
const port = process.env.PORT || 3000;

// MongoDB setup
const mongoUri = process.env.MONGODB_URI || 'mongodb://mongoadmin:secret@mongodb:27017/iot_agriculture?authSource=admin';
let mongoClient;

async function connectToMongo() {
    try {
        mongoClient = new MongoClient(mongoUri);
        await mongoClient.connect();
        console.log('Connected to MongoDB successfully');
    } catch (err) {
        console.error('Failed to connect to MongoDB:', err);
        throw err;
    }
}

// Connect to MongoDB on startup
connectToMongo().catch(console.error);

// Simplified Redis client setup
const redisClient = redis.createClient({
    url: `redis://${process.env.REDIS_HOST || 'redis'}:6379`,
    socket: {
        reconnectStrategy: (retries) => {
            console.log(`Redis reconnection attempt ${retries}`);
            return Math.min(retries * 100, 3000);
        }
    }
});

redisClient.on('error', err => {
    console.error('Redis Client Error:', err);
});

redisClient.on('connect', () => {
    console.log('Redis Client Connected');
});

redisClient.on('ready', () => {
    console.log('Redis Client Ready');
});

redisClient.on('end', () => {
    console.log('Redis Client Connection Closed');
});

// Connect to Redis
(async () => {
    try {
        await redisClient.connect();
        console.log('Connected to Redis successfully');
        
        // Test the connection
        const testResult = await redisClient.ping();
        console.log('Redis PING result:', testResult);
    } catch (err) {
        console.error('Failed to connect to Redis:', err);
    }
})();

// Middleware
app.use(cors());
app.use(express.json());

// Request logging middleware
app.use((req, res, next) => {
    console.log(`${new Date().toISOString()} - ${req.method} ${req.url}`);
    next();
});

// Validate sensor data
function validateSensorData(data) {
    const required = ['sensor_id', 'sensor_type', 'location', 'value', 'timestamp'];
    const missing = required.filter(field => !data[field]);
    
    if (missing.length > 0) {
        return { valid: false, error: `Missing required fields: ${missing.join(', ')}` };
    }
    
    if (typeof data.value !== 'number') {
        return { valid: false, error: 'Value must be a number' };
    }
    
    return { valid: true };
}

// Health check
app.get('/health', async (req, res) => {
    try {
        // Test Redis connection
        await redisClient.ping();
        res.json({ 
            status: 'healthy',
            redis: 'connected',
            timestamp: new Date().toISOString()
        });
    } catch (error) {
        res.status(503).json({
            status: 'degraded',
            redis: 'disconnected',
            timestamp: new Date().toISOString()
        });
    }
});

// Get all sensor data (with /api prefix)
app.get('/api/sensor-data/all', getAllSensorData);

// Get all sensor data (without /api prefix)
app.get('/sensor-data/all', getAllSensorData);

// Handler function for getting all sensor data
async function getAllSensorData(req, res) {
    try {
        console.log('Received request for sensor data');
        
        if (!mongoClient) {
            console.error('MongoDB client not ready');
            return res.status(503).json({ 
                error: 'Service temporarily unavailable',
                details: 'MongoDB client not initialized'
            });
        }

        if (!mongoClient.topology || !mongoClient.topology.isConnected()) {
            console.error('MongoDB connection lost, attempting to reconnect...');
            await connectToMongo();
        }

        console.log('Fetching all sensor data...');
        const limit = parseInt(req.query.limit) || 50;
        
        const db = mongoClient.db('iot_agriculture');
        const collection = db.collection('sensor_logs');
        
        // Get the total count first
        const totalCount = await collection.countDocuments();
        console.log(`Total documents in collection: ${totalCount}`);
        
        const allData = await collection
            .find({})
            .sort({ timestamp: -1 })
            .limit(limit)
            .toArray();

        console.log(`Retrieved ${allData.length} records from MongoDB`);
        
        if (allData.length === 0) {
            console.log('No sensor data found in MongoDB');
            return res.json([]);  // Return empty array instead of 404
        }
        
        // Log a sample of the data
        if (allData.length > 0) {
            console.log('Sample data:', JSON.stringify(allData[0], null, 2));
        }
        
        res.json(allData);
    } catch (error) {
        console.error('Error retrieving all sensor data:', error);
        res.status(500).json({ 
            error: 'Internal server error',
            details: error.message,
            stack: process.env.NODE_ENV === 'development' ? error.stack : undefined
        });
    }
}

// Receive sensor data (with /api prefix)
app.post('/api/sensor-data', handleSensorData);

// Receive sensor data (without /api prefix)
app.post('/sensor-data', handleSensorData);

// Handler function for receiving sensor data
async function handleSensorData(req, res) {
    try {
        if (!redisClient.isReady) {
            console.error('Redis client not ready');
            return res.status(503).json({ error: 'Service temporarily unavailable' });
        }

        const sensorData = req.body;
        const validation = validateSensorData(sensorData);
        
        if (!validation.valid) {
            return res.status(400).json({ error: validation.error });
        }

        // Send directly to data processing queue
        await redisClient.rPush('sensor_data', JSON.stringify(sensorData));

        forwardToCloud(sensorData).catch(err => {
            console.error('Background cloud forwarding failed:', err);
        });

        res.json({
            success: true,
            message: 'Data received and queued for processing',
            sensor_id: sensorData.sensor_id
        });

    } catch (error) {
        console.error('Error processing sensor data:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
}

// Get sensor data by ID
app.get('/api/sensor-data/:sensorId', async (req, res) => {
    try {
        const { sensorId } = req.params;
        
        // Prevent conflict with /all endpoint
        if (sensorId === 'all') {
            return res.status(400).json({ 
                error: 'Invalid sensor ID. Use /api/sensor-data/all for all sensors'
            });
        }
        
        if (!mongoClient) {
            console.error('MongoDB client not ready for /api/sensor-data/:sensorId');
            return res.status(503).json({ error: 'Service temporarily unavailable' });
        }

        const limit = parseInt(req.query.limit) || 100;
        const collection = mongoClient.db('iot_agriculture').collection('sensor_logs');
        
        const sensorData = await collection
            .find({ sensor_id: sensorId })
            .sort({ timestamp: -1 })
            .limit(limit)
            .toArray();

        if (sensorData.length === 0) {
            return res.status(404).json({ 
                error: 'No data found for sensor',
                sensor_id: sensorId
            });
        }

        res.json(sensorData);

    } catch (error) {
        console.error('Error retrieving sensor data:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// Forward to cloud service
async function forwardToCloud(data) {
    const cloudEndpoint = process.env.CLOUD_ENDPOINT;
    const vaultSecret = process.env.OCI_VAULT_SECRET;

    if (!cloudEndpoint || !vaultSecret) {
        // This is expected in local setup, so just log it lightly
        // console.warn('Cloud forwarding disabled - missing configuration');
        return;
    }

    try {
        await axios.post(`${cloudEndpoint}/api/ingest`, data, {
            timeout: 5000,
            headers: {
                'Authorization': `Bearer ${vaultSecret}`,
                'Content-Type': 'application/json'
            }
        });
        console.log('Data forwarded to cloud successfully');
    } catch (error) {
        console.error('Error forwarding to cloud:', error.message);
    }
}

// Add diagnostic endpoint
app.get('/api/diagnostic', async (req, res) => {
    try {
        const status = {
            mongodb: {
                connected: false,
                collections: [],
                sensorDataCount: 0
            }
        };

        // Check MongoDB connection
        if (mongoClient && mongoClient.topology && mongoClient.topology.isConnected()) {
            status.mongodb.connected = true;
            
            // Get database info
            const db = mongoClient.db('iot_agriculture');
            const collections = await db.listCollections().toArray();
            status.mongodb.collections = collections.map(c => c.name);
            
            // Get sensor data count
            const collection = db.collection('sensor_logs');
            status.mongodb.sensorDataCount = await collection.countDocuments();
        }

        res.json(status);
    } catch (error) {
        console.error('Diagnostic error:', error);
        res.status(500).json({ 
            error: 'Diagnostic failed',
            details: error.message
        });
    }
});

// Start server
const server = app.listen(port, () => {
    console.log(`API Gateway running on port ${port}`);
});

// Graceful shutdown
process.on('SIGTERM', async () => {
    console.log('SIGTERM received. Starting graceful shutdown...');
    server.close(() => {
        console.log('HTTP server closed.');
    });
    
    try {
        await redisClient.quit();
    } catch (err) {
        console.error('Error closing Redis connection:', err);
    }
    
    process.exit(0);
});