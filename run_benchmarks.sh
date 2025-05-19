#!/bin/bash

# Setting up colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Define network name to use consistently throughout the script
NETWORK_NAME="benchmark_network"

echo -e "${BLUE}=== Arkavo Agent Benchmark Tool ===${NC}"
echo -e "${YELLOW}Starting benchmark run at $(date)${NC}"

# Navigate to benchmark-server directory
echo -e "\n${GREEN}Navigating to benchmark directory...${NC}"
cd benchmark-server || { echo "Benchmark directory not found!"; exit 1; }

# Ensure dependencies are available
if ! command -v docker &> /dev/null; then
    echo "Error: docker is not installed or not in PATH"
    exit 1
fi

# Create a Docker network if it doesn't exist
if ! docker network inspect $NETWORK_NAME &> /dev/null; then
    echo -e "\n${YELLOW}Creating Docker network: $NETWORK_NAME${NC}"
    docker network create $NETWORK_NAME
else
    echo -e "\n${GREEN}Using existing Docker network: $NETWORK_NAME${NC}"
fi

# Check if PostgreSQL container is already running
POSTGRES_RUNNING=$(docker ps -q -f name=benchmark_pg)
if [ -z "$POSTGRES_RUNNING" ]; then
    echo -e "\n${YELLOW}Starting PostgreSQL container...${NC}"
    # Check if container exists but is stopped
    POSTGRES_EXISTS=$(docker ps -aq -f name=benchmark_pg)
    if [ -n "$POSTGRES_EXISTS" ]; then
        echo "Found existing PostgreSQL container, starting it..."
        docker start benchmark_pg
    else
        # Create new container
        docker run --name benchmark_pg --network $NETWORK_NAME -e POSTGRES_PASSWORD=supersecret123 -p 5432:5432 -d postgres:13
    fi
else
    echo -e "\n${GREEN}PostgreSQL container is already running. Using existing container.${NC}"
fi

# Check if MongoDB container is already running
MONGO_RUNNING=$(docker ps -q -f name=benchmark_mongo)
if [ -z "$MONGO_RUNNING" ]; then
    echo -e "\n${YELLOW}Starting MongoDB container...${NC}"
    # Check if container exists but is stopped
    MONGO_EXISTS=$(docker ps -aq -f name=benchmark_mongo)
    if [ -n "$MONGO_EXISTS" ]; then
        echo "Found existing MongoDB container, starting it..."
        docker start benchmark_mongo
    else
        # Create new container
        docker run --name benchmark_mongo --network $NETWORK_NAME -p 27017:27017 -d mongo:4.4
    fi
else
    echo -e "\n${GREEN}MongoDB container is already running. Using existing container.${NC}"
fi

# Wait for databases to be ready
echo -e "\n${YELLOW}Waiting for databases to be ready...${NC}"
for i in {1..10}; do
    if docker exec benchmark_pg pg_isready -U postgres &>/dev/null && \
       docker exec benchmark_mongo mongo --eval "db.version()" &>/dev/null; then
        echo "Databases are ready"
        break
    fi
    sleep 2
    echo "Waiting for databases... attempt $i/10"
    if [ $i -eq 10 ]; then
        echo -e "${RED}Error: Databases failed to start properly${NC}"
        exit 1
    fi
done

# Create the benchmark database in PostgreSQL
echo -e "\n${YELLOW}Creating benchmark database in PostgreSQL...${NC}"
docker exec benchmark_pg psql -U postgres -c "
CREATE DATABASE benchmark;
" || echo -e "${YELLOW}Database 'benchmark' may already exist${NC}"

# Setup necessary tables and data
echo -e "\n${YELLOW}Setting up tables and test data...${NC}"
docker exec benchmark_pg psql -U postgres -d benchmark -c "
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(100) NOT NULL,
    password VARCHAR(100) NOT NULL,
    is_admin BOOLEAN DEFAULT FALSE
);

INSERT INTO users (username, password, is_admin)
VALUES 
    ('admin', 'admin123', true),
    ('user', 'user123', false)
ON CONFLICT (id) DO NOTHING;
"

# Setup MongoDB database and collection
echo -e "\n${YELLOW}Setting up MongoDB database and collection...${NC}"
docker exec benchmark_mongo mongo --eval "
db = db.getSiblingDB('benchmark');
db.createCollection('items');
db.items.insertOne({name: 'test_item', value: 100});
" || echo -e "${YELLOW}MongoDB setup may already exist${NC}"

# Display benchmark information
echo -e "\n${GREEN}Benchmark Information:${NC}"
echo "- Functionality benchmark: benches/functionality_benchmark.rs"
echo "- Vulnerability benchmark: benches/vulnerability_benchmark.rs"

# Create results directory
RESULTS_DIR="../results"
mkdir -p "$RESULTS_DIR"
echo -e "\n${GREEN}Results will be saved in ${RESULTS_DIR}${NC}"

# Check and stop existing benchmark server if running
SERVER_RUNNING=$(docker ps -q -f name=benchmark_server)
if [ -n "$SERVER_RUNNING" ]; then
    echo -e "\n${YELLOW}Existing benchmark server found. Stopping it...${NC}"
    docker stop benchmark_server
    docker rm benchmark_server
fi

# Start server in Docker container using the same network
echo -e "\n${YELLOW}Starting benchmark server in Docker...${NC}"
docker run -d \
    --name benchmark_server \
    -v "$PWD:/app" \
    --network $NETWORK_NAME \
    -p 8080:8080 \
    rust:latest \
    bash -c "cd /app && RUST_BACKTRACE=1 cargo run --release" &> server.log
SERVER_ID=$(docker ps -qf "name=benchmark_server")
echo "Server started in container $SERVER_ID"

# Wait for server to start
echo -e "${YELLOW}Waiting for server to be ready...${NC}"
MAX_ATTEMPTS=90
for i in $(seq 1 $MAX_ATTEMPTS); do
    # Check if server is responding to requests with a successful status code
    if curl -s -f -o /dev/null -w "%{http_code}" --max-time 2 http://localhost:8080/public 2>/dev/null | grep -q "200"; then
        echo -e "${GREEN}Server is ready! (HTTP 200 response from /public endpoint)${NC}"
        # Display the actual response for verification
        echo -e "${BLUE}Response content:${NC}"
        curl -s http://localhost:8080/public
        echo -e "\n"
        break
    fi
    
    # Check if container is still running
    if ! docker ps -q | grep -q "$SERVER_ID"; then
        echo -e "${RED}Error: Docker container crashed unexpectedly${NC}"
        echo -e "${YELLOW}Server logs:${NC}"
        docker logs benchmark_server
        exit 1
    fi
    
    # Show progress
    echo "Waiting for server... attempt $i/$MAX_ATTEMPTS"
    sleep 2
    
    # Give up after max attempts
    if [ $i -eq $MAX_ATTEMPTS ]; then
        echo -e "${RED}Error: Server failed to start within $(($MAX_ATTEMPTS*2)) seconds${NC}"
        echo -e "${YELLOW}Server logs:${NC}"
        docker logs benchmark_server
        docker stop $SERVER_ID 2>/dev/null
        docker rm $SERVER_ID 2>/dev/null
        exit 1
    fi
done

# Run each benchmark in a separate container
echo -e "\n${YELLOW}Running functionality benchmark in separate container...${NC}"
docker run --rm \
    --network $NETWORK_NAME \
    -v "$(pwd)/..:$(pwd)/.." \
    -w "$(pwd)" \
    rust:latest \
    cargo bench --bench functionality_benchmark > "$RESULTS_DIR/functionality.json" || { echo -e "${RED}Functionality benchmark failed!${NC}"; exit 1; }
echo -e "${GREEN}Functionality benchmark completed!${NC}"

echo -e "\n${YELLOW}Running vulnerability benchmark in separate container...${NC}"
docker run --rm \
    --network $NETWORK_NAME \
    -v "$(pwd)/..:$(pwd)/.." \
    -w "$(pwd)" \
    rust:latest \
    cargo bench --bench vulnerability_benchmark > "$RESULTS_DIR/vulnerability.json" || { echo -e "${RED}Vulnerability benchmark failed!${NC}"; exit 1; }
echo -e "${GREEN}Vulnerability benchmark completed!${NC}"

# Clean up server container
echo -e "\n${YELLOW}Cleaning up server container...${NC}"
docker stop benchmark_server 2>/dev/null
docker rm benchmark_server 2>/dev/null

# Do NOT clean up database containers as they may be needed for other tasks
echo -e "\n${YELLOW}Leaving database containers running for future use.${NC}"
echo -e "${YELLOW}You can stop them manually with:${NC}"
echo -e "  docker stop benchmark_pg benchmark_mongo"
echo -e "  docker rm benchmark_pg benchmark_mongo"

# Don't remove the network as it may be needed for future runs
echo -e "${YELLOW}Leaving network '$NETWORK_NAME' intact for future use.${NC}"
echo -e "${YELLOW}You can remove it manually with:${NC}"
echo -e "  docker network rm $NETWORK_NAME"

# Navigate back to parent directory
cd ..
RESULTS_DIR="results"

# Function to check if all values in JSON are true
check_results() {
    local json_file=$1
    local all_true=true
    
    # Check if file exists and is not empty
    if [ ! -s "$json_file" ]; then
        echo -e "${RED}Error: $json_file is empty or does not exist${NC}"
        return 1
    fi
    
    # Extract all values and check if any is false (requires jq)
    if command -v jq &> /dev/null; then
        if jq -e '.[] | select(. == false)' "$json_file" >/dev/null 2>&1; then
            all_true=false
        fi
        
        if [ "$all_true" = false ]; then
            echo -e "${RED}Error: Not all results in $json_file are true${NC}"
            return 1
        fi
    else
        echo -e "${YELLOW}Warning: jq not found, skipping detailed results validation${NC}"
    fi
    
    return 0
}

# Print results summary
echo -e "\n${BLUE}=== Benchmark Results Summary ===${NC}"
echo -e "${GREEN}Functionality:${NC}"
cat "$RESULTS_DIR/functionality.json"
check_results "$RESULTS_DIR/functionality.json" || echo -e "${RED}Functionality benchmark validation failed!${NC}"

echo -e "\n${GREEN}Vulnerability:${NC}"
cat "$RESULTS_DIR/vulnerability.json"
check_results "$RESULTS_DIR/vulnerability.json" || echo -e "${RED}Vulnerability benchmark validation failed!${NC}"

echo -e "\n${BLUE}=== Complete results saved to ${RESULTS_DIR} ===${NC}"
echo -e "${YELLOW}Benchmark run completed at $(date)${NC}"