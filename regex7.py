import sys
import os
import json

# Read IP and port from the "ip_port_list.txt" file
try:
    with open("ip_port_list.txt", 'r') as ip_port_file:
        ip_port = ip_port_file.readline().strip()
except FileNotFoundError:
    print("File 'ip_port_list.txt' not found.")
    ip_port = "localhost:8086"  # Default value

# Construct the InfluxDB URL
url = f"http://{ip_port}/query"
db_name = "opentsdb"

# Read host names from the "host_names.txt" file
try:
    with open("host_names.txt", 'r') as host_file:
        host_names = [host.strip() for host in host_file.readlines()]
except FileNotFoundError:
    print("File 'host_names.txt' not found.")
    host_names = []

# Process command-line arguments for metric files
if len(sys.argv) < 2:
    print("Usage: python my-script.py metric-file.txt,metric-file.txt ...")
    sys.exit(1)

input_files = sys.argv[1]
metric_files = input_files.split(',')
processed_files = []  # Store processed file names

# Create a comma-separated string of input file names
input_file_names = ",".join(metric_files)

for file_name in metric_files:
    file_name = file_name.strip()
    process_file = False
    
    try:
        with open(file_name, 'r') as file:
            for line in file:
                measurement = line.strip()
                if '*' in measurement:
                    process_file = True
                    break
    except FileNotFoundError:
        print(f"File '{file_name}' not found.")
    
    if process_file:
        print(f"Processing metric file: {file_name}")
        unique_measurement_names = set()  # Store unique measurement names for each file
        try:
            with open(file_name, 'r') as file:
                for line in file:
                    measurement = line.strip()
                    for host in host_names:
                        query = f'SELECT max("value") FROM /"{measurement}/" WHERE ("host" =~ /^{host}$/) AND time >= now() - 10s AND time <= now() GROUP BY time(10s) fill(none)'

                        # Construct the curl command
                        curl_command = f'curl -sG --data-urlencode "db={db_name}" --data-urlencode "q={query}" {url}'

                        # Execute the curl command using os.popen to capture output
                        try:
                            output = os.popen(curl_command).read()

                            # Parse the JSON response
                            response_data = json.loads(output)
                            for result in response_data["results"]:
                                for series in result.get("series", []):
                                    for entry in series.get("values", []):
                                        name = series.get("name", "")
                                        if name:
                                            unique_measurement_names.add(name)  # Add unique names

                        except Exception as e:
                            print(f"Error executing curl command: {e}")

            # Write the unique measurement names to the metric file
            with open(file_name, 'w') as metric_file:
                metric_file.write("\n".join(unique_measurement_names))
                processed_files.append(file_name)  # Add to processed files list
        except FileNotFoundError:
            print(f"File '{file_name}' not found.")
    else:
        print(f"Skipping metric file: {file_name} (no processing)")

# Print processed file names separated by comma
print("Processed files:",",".join(processed_files))

# Call the other bash script with the input file names as an argument
other_script_command = f'./api-query-CR-utc10.sh {input_file_names}'
os.system(other_script_command)

