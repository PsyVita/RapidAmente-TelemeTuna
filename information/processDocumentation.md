This file is for the author to document her process of recreating the project, simply for learning and traceback purposes :3

Prototype Approach Details:

    Radio/serial source → Node-RED (ingestion) → PostgreSQL (storage) + Prisma (manage schema) → Grafana (visualization)

Initial Approach [later changed: see stage 4]:

    Radio/serial source -> Plain JavaScript (ingestion) -> Plain SQL (storage) + Flyway extension (manage schema) -> Grafana (visualization)

    1. Use TimescaleDB extension to PostGreSQL. This was suggested in hopes to support a larger, continuous database. TimescaleDB is a PostgreSQL extension optimized for time-series data; it automatically partitions data by time, making queries over large date ranges significantly faster than plain PostgreSQL. (decision later changed in stage 4)
    2. At first, plain JavaScript was suggested over NodeRED because it offers more control over the ingestion logic with no visual abstraction layer. A custom Node.js script using the serialport library could read from the ESP32, convert raw values, and insert into PostgreSQL directly without depending on a third-party tool. (decision later changed in stage 4)
    3. Use SQL + Flyway instead of Prisma; Flyway is a lightweight migration tool that tracks migration history. No local installation is needed; it runs as a Docker container. Prisma offers the same history tracking but requires a local install and adds unnecessary complexity for this project's scale. (decision maintained)

Stage 1 (Storage)
1. Created the skeleton and files.
2. Added timescaledb section into docker-compose.yaml.
3. Added .env file information.
4. Added table creation process in 001_init.sql.
5. Try composing docker and running this line to test that the 001_init.sql works: 
    docker exec -it telemetry-timescaledb psql -U <POSTGRES_USER> -d <POSTGRES_DB> -c "\d telemetry_records"

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
Change in Approach: 
    
    Radio/serial source -> Node-RED (ingestion) -> PostgreSQL (storage) + Flyway extension (manage schema) -> Grafana (visualization)

    1. Normal PostGreSQL instead of TimescaleDB extension because the project will only be run in uncontinuous periods. No need to be ready for large scale database yet. 
    2. NodeRED instead of building our own ingestion. NodeRED already specialises in IoT communications. To replace it would not be wise. 
    3. Confirmation in using plain SQL + Flyway instead of Prisma; Flyway is a lightweight migration tool that tracks migration history. No local installation is needed; it runs as a Docker container. Prisma offers the same history tracking but requires a local install and adds unnecessary complexity for this project's scale.

1. Deleted initialization folder and 001_init.sql.
2. Deleted ingestion folder and all contents inside.
3. Updated all files, especially docker-compose.yaml, to make sure all TimescaleDB is changed to PostgreSQL.

Stage 5 (Flyway)
1. Created Flyway Migration 'V1__init.sql' under database/migrations.
2. Added Flyway section into docker-compose.yaml
3. Test run the docker. Flyway should only appear for migration check then exit.  
    docker compose logs flyway
    docker exec -it telemetry-postgresdb psql -U <POSTGRES_USER> -d <POSTGRES_DB> -c "\dt"
    **telemetry_records = our table **flyway_schema_history = flyway's migration history

Stage 6 (Node-RED)
1. Added Node-RED section into docker-compose.yaml. 
2. Code on Node-RED. (parsing, converting raw to real data, and postgresql node.) !! Make sure username, password, and database fields are linked to .env so that they dont appear in flows.json.
3. Change directory of Node-RED so the file is saved in the repo.

Stage 7 (Connecting the Whole System Together)
1. Run docker exec -it <your_container_name> psql -U <your_username> -d <your_database_name> to type SELECT count(*) FROM telemetry_records; and SELECT * FROM telemetry_records ORDER BY time DESC LIMIT 5; (check that it works)
2. Open Grafana to start building dashboard.

Stage 8 (Logging Error)
1. Adjust the Node-RED flow so that it catches errors + use data of previous timestamp in presence of corrupted data. 
2. Add new database table to log events. (Flyway version 2 + Node-RED modification)
3. Add new column to telemetry_records (Flyway version 3 + Node-RED modification)

Levels of event_log.
*** If data is only out-of-bounds, that field will be discarded and healed. (warning)
*** If data is incorrect and we don't use the healing system for that point of data, the value is dropped. (error)
*** If data is totally corrupted (wrong length or type) -> whole frame dropped. (error)
*** If unknown error occurred (try-catch), then it's probably something to do with the code. (critical)

Stage 9 (Bitmasks)
1. I went back to merge v3 into v1.
2. Created a new V3 to store bitmask definitions in order to process err and warns.
3. Flow in Node-RED was heavily edited. The continuous values are self-validating, then passed onto the heal node. Other values are behind the heal node and contains its own progress. Err and warn data are passed through Node-RED as integers and will be processed in Grafana using the newly created V3 migration bitmask definition. 

Stage 10 (Other adjustments)
1. Healthcheck system in docker services.
2. Add Dockerfile under nodered folder.
3. Add test datas under the node-red data folder for CSV input path.
4. Move docker_compose.yaml to infrastructure folder. 

Stage 11 (MQTT)
1. Add Mosquitto folder and its config.

Stage 12 (Grafana Customization)
1. Export Grafana to the project. 

Stage 13 (Bridge) - not used
1. Add serial-bridge folder. Keep in mind, Docker cannot read the actual ports on your computer. We need a bridge for Python read and write to serial ports and let it connect to a Mosquitto broker and publish the info gained from the port. 