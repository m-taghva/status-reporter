#!/bin/bash

# Set the variables for the script
HOST_NAME_FILE="host_names.txt"
IP_PORT_FILE="ip_port_list.txt"
DATABASE="opentsdb"

# for font
BOLD="\e[1m"
RESET="\e[0m"
YELLOW="\033[1;33m"
END="\033[0m"

# Read metric and time file paths/names from the user
FILES_ARG="$1"

# Split the input files by commas
IFS=',' read -r -a INPUT_FILES_ARRAY <<< "$FILES_ARG"

METRIC_FILES_ARRAY=()
TIME_RANGE_FILES=()
PARENT_DIR=""

echo ""
echo "========================================"

for file in "${INPUT_FILES_ARRAY[@]}"; do
    # Check if the file name contains "metric" to identify metric files
    if [[ $file == *"metric"* ]]; then
        METRIC_FILES_ARRAY+=("$file")
    elif [[ $file == *"time"* ]]; then
        TIME_RANGE_FILES+=("$file")
    else
        # If it's not a metric or time file, assume it's the parent directory
        PARENT_DIR="$file"
    fi
done

# Read host names and IP:PORT pairs into separate arrays
IFS=$'\n' read -d '' -r -a HOST_NAMES < "${HOST_NAME_FILE}"
IFS=$'\n' read -d '' -r -a IP_PORTS < "${IP_PORT_FILE}"

# Function to convert Tehran timestamp to UTC
convert_tehran_to_utc() {
    local tehran_timestamp="$1"
    local tehran_timestamp_seconds=$(date -d "${tehran_timestamp}" "+%s")
    local utc_timestamp_seconds=$((tehran_timestamp_seconds + 120)) 
    local utc_timestamp=$(date -u -d "@${utc_timestamp_seconds}" "+%Y-%m-%dT%H:%M:%SZ")
    echo "$utc_timestamp"
}

# Create the output parent directory if it doesn't exist
OUTPUT_PARENT_DIR="${PARENT_DIR}/query_results"
mkdir -p "$OUTPUT_PARENT_DIR"

# Get the total number of queries to be executed
total_queries=$((${#HOST_NAMES[@]} * ${#TIME_RANGE_FILES[@]} * ${#IP_PORTS[@]}))
current_query=0

# Loop through each combination of time range, host, IP, PORT, and execute the curl command
for host_name in "${HOST_NAMES[@]}"; do
    # Create a new CSV file for each host in a directory named 'host_name_csv'
    output_dir="${OUTPUT_PARENT_DIR}/${host_name}-csv"
    mkdir -p "$output_dir"
    output_csv="${output_dir}/${host_name}.csv"

    # Initialize the CSV file with the header
    header="Start_Time,End_Time"

    for metric_file in "${METRIC_FILES_ARRAY[@]}"; do
        while IFS= read -r metric_name; do
            # Remove spaces from the metric name
            metric_name="${metric_name// /}"
            # Check if the metric name is not empty (removes blank lines)
            if [ -n "$metric_name" ]; then
            # Extract the prefix from the metric filename
            metric_prefix=$(basename "$metric_file" _metric_list.txt)
            header="${header},${metric_prefix}_${metric_name#netdata.}"
            fi
        done < <(grep -v '^[[:space:]]*$' "$metric_file")
    done
    echo "$header" > "$output_csv"

    for time_file in "${TIME_RANGE_FILES[@]}"; do
        # Read time ranges from the time file
        while IFS= read -r line; do
            # Remove extra spaces
            line="$(echo "$line" | tr -s ' ')"
            # Check if the line is not empty (removes blank lines)
            if [ -n "$line" ]; then
            # Split the start and end times from the line
            IFS=',' read -r start_time_tehran end_time_tehran <<< "$line"

            # Convert the timestamps to UTC for queries
            start_time_utc=$(convert_tehran_to_utc "$start_time_tehran")
            end_time_utc=$(convert_tehran_to_utc "$end_time_tehran")

            for ip_port in "${IP_PORTS[@]}"; do
                # Split IP and PORT from the IP:PORT pair
                ip_address="${ip_port%:*}"
                port="${ip_port#*:}"

                line_values=$(date -d "$start_time_tehran 2min" +"%Y-%m-%d %H:%M:%S"),$(date -d "$end_time_tehran 2min"  +"%Y-%m-%d %H:%M:%S")

                for metric_file in "${METRIC_FILES_ARRAY[@]}"; do
                    if [[ -f "$metric_file" ]]; then
                        while IFS= read -r metric_name; do
                            # Extract the prefix from the metric filename
                            metric_prefix=$(basename "$metric_file" _metric_list.txt)

                            # Construct the curl command with the current metric_name, start time, end time, host, IP address, and port
                            curl_command="curl -sG 'http://${ip_address}:${port}/query' --data-urlencode \"db=${DATABASE}\" --data-urlencode \"q=SELECT ${metric_prefix}(\\\"value\\\") FROM \\\"${metric_name}\\\" WHERE (\\\"host\\\" =~ /^${host_name}$/) AND time >= '${start_time_utc}' AND time <= '${end_time_utc}' fill(none)\""

                            # Execute the curl command and get the values
                            query_result=$(eval "${curl_command}")
                            values=$(echo "$query_result" | jq -r '.results[0].series[0].values[] | .[1]' 2>/dev/null)

                            # Append the values to the line_values string
                            line_values+=",$values"
                        done < "$metric_file"
                    else
                        echo "Metric file not found: $metric_file"
                    fi
                done

                # Append the line_values to the CSV file
                echo "$line_values" >> "$output_csv"

                echo -e "${BOLD}Add metrics to CSV, please wait ...${RESET}"
                
                # Loop through each metric file for the second query
                for metric_file in "${METRIC_FILES_ARRAY[@]}"; do
                    if [[ -f "$metric_file" ]]; then
                        while IFS= read -r metric_name; do
                            # Extract the prefix from the metric filename
                            metric_prefix=$(basename "$metric_file" _metric_list.txt)

                            # Construct the curl command for query 2 with the current metric_name, start time, end time, host, IP address, and port
                            query2_curl_command="curl -sG 'http://${ip_address}:${port}/query' --data-urlencode \"db=${DATABASE}\" --data-urlencode \"q=SELECT ${metric_prefix}(\\\"value\\\") FROM /"${metric_name}/" WHERE (\\\"host\\\" =~ /^${host_name}$/) AND time >= '${start_time_utc}' AND time <= '${end_time_utc}' GROUP BY time(10s) fill(none)\""

                            # Get the query2 output and store it in a variable
                            query2_output=$(eval "$query2_curl_command")

                            python3 image-renderer.py "$query2_output" "$host_name" "$PARENT_DIR"

                        done < "$metric_file"
                    else
                        echo "Metric file not found: $metric_file"
                    fi
                done
            done
        done < <(grep -v '^[[:space:]]*$' "$time_file")
    done
done
echo ""
echo -ne "Progress: ${YELLOW}|||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||${END} 100% \n"
echo ""
echo -e "${BOLD}CSV and Image are saved in the ${RESET}${YELLOW}'$OUTPUT_PARENT_DIR'${END}${BOLD} directory for each host ${RESET}"
echo ""
echo "========================================"
