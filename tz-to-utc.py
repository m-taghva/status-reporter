from datetime import datetime
import pytz

class bcolors:
              YELLOW = '\033[1;33m'
              END = '\033[0m'
    
def convert_to_utc(time_str):
    tz_tehran = pytz.timezone('Asia/Tehran')
    local_time = datetime.strptime(time_str, "%Y-%m-%d %H:%M:%S")
    local_time = tz_tehran.localize(local_time)
    utc_time = local_time.astimezone(pytz.utc)
    return utc_time.strftime("%Y-%m-%dT%H:%M:%SZ")

# Read the input file
input_file_path = 'time_ranges_timestamp.txt'
output_file_path = 'time_ranges_utc.txt'

with open(input_file_path, 'r') as input_file:
    with open(output_file_path, 'w') as output_file:
        for line in input_file:
            start_time_str, end_time_str = line.strip().split(',')
            start_time_str = start_time_str.replace(' ', '  ')  
            end_time_str = end_time_str.replace(' ', '  ')      
            start_time_utc = convert_to_utc(start_time_str)
            end_time_utc = convert_to_utc(end_time_str)
            output_file.write(f"{start_time_utc},{end_time_utc}\n")

print(f"{bcolors.YELLOW}your Time Zone converted to UTC, now sending queries !{bcolors.END}")
print("======================================================")
