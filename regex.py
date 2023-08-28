import sys
import os
import json
import re

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

metric_files = sys.argv[1].split(',')
processed_files = []  # Store processed file names

for file_name in metric_files:
    file_name = file_name.strip()
    process_file = False
    
    try:
        with open(file_name, 'r') as file:
            for line in file:
                measurement = line.strip()
                if re.search(r'\\w\*', measurement):
                    process_file = True
                    break
    except FileNotFoundError:
        print(f"File '{file_name}' not found.")
    
    if process_file:
        print(f"Processing metric file: {file_name}")
        unique_measurement_names = set()  # Store unique measurement names for each file
        try:
            with open(file_name, 'r') as file:
                lines = file.readlines()  # Read all lines
                new_lines = []  # Store lines to overwrite the file
                
                for line in lines:
                    measurement = line.strip()
                    if re.search(r'\\w\*', measurement):
                        for host in host_names:
                            query = f'SELECT max("value") FROM /"{measurement}/" WHERE ("host" =~ /^{host}$/) AND time >= now() - 10s AND time <= now() GROUP BY time(10s) fill(none)'

                            # Construct the curl command
                            curl_command = f'curl -sG --data-urlencode "db={db_name}" --data-urlencode "q={query}" {url}'

                            # Execute the curl command using os.popen to capture output
                            try:
                                output = os.popen(curl_command).read()
                                response_data = json.loads(output)
                                for result in response_data["results"]:
                                    for series in result.get("series", []):
                                        for entry in series.get("values", []):
                                            name = series.get("name", "")
                                            if name:
                                                unique_measurement_names.add(name)

                            except Exception as e:
                                print(f"Error executing curl command: {e}")
                        
                        new_lines.append(line.strip())  # Keep the line with \w* measurement
                        
                    else:
                        new_lines.append(line.strip())  # Remove extra whitespace

                new_lines.extend(unique_measurement_names)  # Append unique names

                # Write the updated lines back to the file
                with open(file_name, 'w') as metric_file:
                    metric_file.write("\n".join(filter(None, new_lines)))

                processed_files.append(file_name)  # Add to processed files list
        
        except FileNotFoundError:
            print(f"File '{file_name}' not found.")
        
    else:
        print("======================================================")
        print(f"Skipping metric file: {file_name} (no processing)")

# Print processed file names separated by comma
print("======================================================")
print("Processed files:",",".join(processed_files))
print("======================================================")
# Read files, remove repeated names, and write back
for file_name in processed_files:
    try:
        with open(file_name, 'r') as file:
            lines = file.readlines()
            unique_lines = list(set(line.strip() for line in lines if not re.search(r'\\w\*', line)))
        
        with open(file_name, 'w') as file:
            file.write("\n".join(filter(None, unique_lines)))
    except FileNotFoundError:
        print(f"File '{file_name}' not found.")

# Create a comma-separated string of processed file names
processed_file_names = ",".join(processed_files)

# Call the other bash script with the processed file names as an argument
other_script_command = f'./status-reporter.sh {sys.argv[1]}'
os.system(other_script_command)
