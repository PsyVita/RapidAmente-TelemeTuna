This file is for the author to document her process of recreating the project, simply for learning and traceback purposes :3

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