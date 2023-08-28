# status-reporter
<h4>influxdb API tool for sending query automatically and save some documents for monitoring.</h4>
<h4># This program has an integrated structure and its modules are interdependent and work together #</h4>
workload schema:
<img src="reporter-pic.png" width="1288" height="439"/>

related to these projects: https://github.com/m-taghva/influxdb.git
<br>step by step usage:</br>
   
    - Install dependencies: # apt install jq / # yum install jq - # pip install pytz datetime matplotlib tqdm  
    ======================================================
    - put your time range in time_rangs_taimestamp.txt like this format: 2023-07-31 09:30:00,2023-07-31 10:30:00
    - put your monitored host or VM name in host_names.txt like this: name (line by line)
    - write ip and port of influxdb in ip_port_list.txt like this: localhost:8086
    - write your metric file like this: netdata.system.cpu.system (measurment line by line - you can use regex * in names)
    - your metric file prefix can use as expressions
    - you can change DB name on top of the scripts.
    ======================================================
    - after complete all files start app with this command
        # python3 regex.py mean_metric_list,sum_metric_list, ... 
      
