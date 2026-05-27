This file is for the author to document her process of recreating the project, simply for learning and traceback purposes :3

(Prototype Approach Details:

    Radio/serial source → Node-RED (ingestion) → PostgreSQL (storage) + Prisma (manage schema) → Grafana (visualization)

)

(Initial Approach [later changed: see stage 4]:

    Radio/serial source -> Plain JavaScript (ingestion) -> Plain SQL (storage) + Flyway extension (manage schema) -> Grafana (visualization)

    1. Use TimescaleDB extension to PostGreSQL. This was suggested in hopes to support a larger, continuous database. TimescaleDB is a PostgreSQL extension optimized for time-series data; it automatically partitions data by time, making queries over large date ranges significantly faster than plain PostgreSQL. (decision later changed in stage 4)
    2. At first, plain JavaScript was suggested over NodeRED because it offers more control over the ingestion logic with no visual abstraction layer. A custom Node.js script using the serialport library could read from the ESP32, convert raw values, and insert into PostgreSQL directly without depending on a third-party tool. (decision later changed in stage 4)
    3. Use SQL + Flyway instead of Prisma; Flyway is a lightweight migration tool that tracks migration history. No local installation is needed; it runs as a Docker container. Prisma offers the same history tracking but requires a local install and adds unnecessary complexity for this project's scale. (decision maintained)

)

Stage 1 (Storage)
1. Created the skeleton and files.
2. Added timescaledb section into docker-compose.yaml.
3. Added .env file information.
4. Added table creation process in 001_init.sql.
5. Try composing docker and running this line to test that the 001_init.sql works: 
    docker exec -it telemetry-timescaledb psql -U yippaa -d telemetry -c "\d telemetry_records"

Stage 2 (Grafana)
1. Added grafana section into docker-compose.yaml.
2. Created datasource.yaml for Grafana to access and utilize TimescaleDB. 

Stage 3 (Ingestion)
1. Created ingestion folder and check availability of node and npm.
2. Run 'npm init -y', which created package.json. It records the project's name and, importantly, which libraries this project depends on. 
3. Added necessary tools: 'npm install pg dotenv' to download pg (code for talking to PG) and dotenv (code that reads your .env file and loads those values (username, password) into your program).
4. Added .env file inside ingestion folder. 
5. Added index.js to connects the JavaScript to the database and reports success.

Stage 4 
(Change in Approach: 
    
    Radio/serial source -> Node-RED (ingestion) -> PostgreSQL (storage) + Flyway extension (manage schema) -> Grafana (visualization)

    1. Normal PostGreSQL instead of TimescaleDB extension because the project will only be run in uncontinuous periods. No need to be ready for large scale database yet. 
    2. NodeRED instead of building our own ingestion. NodeRED already specialises in IoT communications. To replace it would not be wise. 
    3. Confirmation in using plain SQL + Flyway instead of Prisma; Flyway is a lightweight migration tool that tracks migration history. No local installation is needed; it runs as a Docker container. Prisma offers the same history tracking but requires a local install and adds unnecessary complexity for this project's scale.

)
1. 
