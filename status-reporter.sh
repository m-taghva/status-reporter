#!/bin/bash

# Increase or reduce time (use second)
START_TIME_SUM="60"
END_TIME_SUBTRACT="60"

# For font
BOLD="\e[1m"
RESET="\e[0m"
YELLOW="\033[1;33m"
END="\033[0m"

CONFIG_FILE="status.conf" # Change this to your file path of config file

# Define arrays for the extracted values
IP_PORTS=()
DATABASES=()
HOSTS=()
ALIASES=()

# Read the configuration file
while IFS= read -r line; do
    # Skip lines starting with #
    if [[ $line != \#* ]]; then
        IFS=',' read -r IP_PORT DATABASE HOSTS_ALIASES <<< "$line"
        
        # Split the HOSTS_ALIASES into an array based on ","
        IFS=',' read -r -a HOSTS_ARRAY <<< "$HOSTS_ALIASES"

        # Loop through the hosts and aliases within a line
        for host_info in "${HOSTS_ARRAY[@]}"; do
            IFS='=' read -r -a host_parts <<< "$host_info"        
            # The first part is the host, and the second part is the alias
            host="${host_parts[0]}"
            alias="${host_parts[1]}"
            IP_PORTS+=("$IP_PORT")
            DATABASES+=("$DATABASE")
            HOSTS+=("$host")
            ALIASES+=("$alias")
        done
    fi
done < "$CONFIG_FILE"

# Remove duplicates from the arrays
IP_PORTS=($(echo "${IP_PORTS[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
DATABASES=($(echo "${DATABASES[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
HOSTS=($(echo "${HOSTS[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
ALIASES=($(echo "${ALIASES[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

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

# If PARENT_DIR is not provided, use the current working directory
if [ -z "$PARENT_DIR" ]; then
    PARENT_DIR="."
fi

# Function to convert Tehran timestamp to UTC
convert_tehran_to_utc_start() {
    local tehran_timestamp_st="$1"
    local tehran_timestamp_seconds_st=$(date -d "${tehran_timestamp_st}" "+%s")
    local utc_timestamp_seconds_st=$((tehran_timestamp_seconds_st + "$START_TIME_SUM")) 
    local utc_timestamp_st=$(date -u -d "@${utc_timestamp_seconds_st}" "+%Y-%m-%dT%H:%M:%SZ")
    echo "$utc_timestamp_st"
}

convert_tehran_to_utc_end() {
    local tehran_timestamp_ed="$1"
    local tehran_timestamp_seconds_ed=$(date -d "${tehran_timestamp_ed}" "+%s")
    local utc_timestamp_seconds_ed=$((tehran_timestamp_seconds_ed - "$END_TIME_SUBTRACT")) 
    local utc_timestamp_ed=$(date -u -d "@${utc_timestamp_seconds_ed}" "+%Y-%m-%dT%H:%M:%SZ")
    echo "$utc_timestamp_ed"
}

# Function to convert UTC to Tehran timestamp for csv output
tehran_time_csv_st() {
    local tehran_timestamp_csv_st="$1"
    local tehran_timestamp_seconds_csv_st=$(date -d "${tehran_timestamp_csv_st}" "+%s")
    local new_tehran_timestamp_seconds_csv_st=$((tehran_timestamp_seconds_csv_st + "$START_TIME_SUM"))
    local new_tehran_timestamp_csv_st=$(date -d "@${new_tehran_timestamp_seconds_csv_st}" "+%Y-%m-%d %H:%M:%S") 
    echo "$new_tehran_timestamp_csv_st"
}

tehran_time_csv_ed() {
    local tehran_timestamp_csv_ed="$1"
    local tehran_timestamp_seconds_csv_ed=$(date -d "${tehran_timestamp_csv_ed}" "+%s")
    local new_tehran_timestamp_seconds_csv_ed=$((tehran_timestamp_seconds_csv_ed - "$END_TIME_SUBTRACT")) 
    local new_tehran_timestamp_csv_ed=$(date -d "@${new_tehran_timestamp_seconds_csv_ed}" "+%Y-%m-%d %H:%M:%S") 
    echo "$new_tehran_timestamp_csv_ed"
}

# Create the output parent directory if it doesn't exist
OUTPUT_PARENT_DIR="${PARENT_DIR}/query_results"
mkdir -p "$OUTPUT_PARENT_DIR"

# Create a single CSV file for all hosts in the 'query_results' directory
output_csv_all="${OUTPUT_PARENT_DIR}/all_hosts_output.csv"

# Initialize the CSV file with the header
header="Host_alias,Start_Time,End_Time"

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
echo "$header" > "$output_csv_all"

# Loop through each combination of time range, host, IP, PORT, and execute the curl command
for ((i=0; i<${#HOSTS[@]}; i++)); do
    alias="${ALIASES[i]}"
    host="${HOSTS[i]}"
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
                start_time_utc=$(convert_tehran_to_utc_start "$start_time_tehran")
                end_time_utc=$(convert_tehran_to_utc_end "$end_time_tehran")

                for database in "${DATABASES[@]}"; do
                    for ip_port in "${IP_PORTS[@]}"; do
                        # Split IP and PORT from the IP:PORT pair
                        ip_address="${ip_port%:*}"
                        port="${ip_port#*:}"

                        line_values="${alias},$(tehran_time_csv_st "$start_time_tehran"),$(tehran_time_csv_ed "$end_time_tehran")"

                        for metric_file in "${METRIC_FILES_ARRAY[@]}"; do
                            if [[ -f "$metric_file" ]]; then
                                while IFS= read -r metric_name; do
                                    # Extract the prefix from the metric filename
                                    metric_prefix=$(basename "$metric_file" _metric_list.txt)

                                    # Construct the curl command with the current metric_name, start time, end time, host, IP address, and port
                                    curl_command="curl -sG 'http://${ip_address}:${port}/query' --data-urlencode \"db=${database}\" --data-urlencode \"q=SELECT ${metric_prefix}(\\\"value\\\") FROM \\\"${metric_name}\\\" WHERE (\\\"host\\\" =~ /^${host}$/) AND time >= '${start_time_utc}' AND time <= '${end_time_utc}' fill(none)\""

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
                        echo "$line_values" >> "$output_csv_all"

                        echo -e "${BOLD}Add metrics to CSV, please wait ...${RESET}"
                    
                        # Loop through each metric file for the second query
                        for metric_file in "${METRIC_FILES_ARRAY[@]}"; do
                            if [[ -f "$metric_file" ]]; then
                                while IFS= read -r metric_name; do
                                    # Extract the prefix from the metric filename
                                    metric_prefix=$(basename "$metric_file" _metric_list.txt)

                                    # Construct the curl command for query 2 with the current metric_name, start time, end time, host, IP address, and port
                                    query2_curl_command="curl -sG 'http://${ip_address}:${port}/query' --data-urlencode \"db=${database}\" --data-urlencode \"q=SELECT ${metric_prefix}(\\\"value\\\") FROM /"${metric_name}/" WHERE (\\\"host\\\" =~ /^${host}$/) AND time >= '${start_time_utc}' AND time <= '${end_time_utc}' GROUP BY time(10s) fill(none)\""

                                    # Get the query2 output and store it in a variable
                                    query2_output=$(eval "$query2_curl_command")

                                    python3 image-renderer.py "$query2_output" "$host" "$PARENT_DIR"
                                done < "$metric_file"
                            else
                                echo "Metric file not found: $metric_file"
                            fi
                        done
                    done
                done
            fi
        done < <(grep -v '^[[:space:]]*$' "$time_file")
    done
done

echo ""
echo -ne "Progress: ${YELLOW}|||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||${END} 100% \n"
echo ""
echo -e "${BOLD}CSV and Images are saved in the ${RESET}${YELLOW}'${PARENT_DIR}'${END}${BOLD} directory${RESET}"
echo ""
echo "========================================"
