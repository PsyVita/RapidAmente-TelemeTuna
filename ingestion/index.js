

// Bring in Node's built-in "path" helper, used to build file paths safely.
const path = require('path');

// Load the root .env file's values into process.env so the code can read them.
// path.join(__dirname, '..', '.env') = "from this file's folder (ingestion), go up one level, then .env".
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

// Pull the "Client" tool out of the pg (PostgreSQL) library.
const { Client } = require('pg');

// Create a new client instance with the connection parameters from the environment variables
const client = new Client({
  host: process.env.DB_HOST || 'localhost',
  port: process.env.DB_PORT || 5433,
  user: process.env.POSTGRES_USER,
  password: process.env.POSTGRES_PASSWORD,
  database: process.env.POSTGRES_DB,
});

// A simple function to connect to the database, print a message, and then disconnect
async function main() {
  await client.connect();
  console.log('Connected to the database!');
  await client.end();
  console.log('Connection closed.');
}

// Run the main function and catch any errors
main().catch((err) => console.error('Error:', err));