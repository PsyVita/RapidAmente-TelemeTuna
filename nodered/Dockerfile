# Build a custom Node-RED image that includes the necessary nodes for PostgreSQL and Serial Port communication instead of using the standard Node-RED image. This allows us to have all the required functionality in one container without needing to install nodes manually after the container is running.

# Use the official Node-RED image as the base
FROM nodered/node-red:latest

# Install additional Node-RED nodes for PostgreSQL and Serial Port
RUN npm install \
    node-red-contrib-postgresql \
    node-red-node-serialport 