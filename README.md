# pmm-batch-jobs




Sample nginx configuration:
```
location /api/v1/ {
			proxy_pass		http://127.0.0.1:3141;
}
```

# Applying changes to PMM (tested on 1.17)


```
# docker create    -v /opt/prometheus/data    -v /opt/consul-data    -v /var/lib/mysql    -v /var/lib/grafana    --name pmm-data    percona pmm-server:latest /bin/true
# docker run -d    -p 80:80    --volumes-from pmm-data    --name pmm-server    --restart always    percona/pmm-server:latest
# batch.sh CONTAINER-ID
```


After that, a new DataSource in Grafana needs to be added with credentials: `metrics/bei3kuuF5i`.

# Sample generic batch-job instrumentation

```
#!/bin/bash
 
if [ -z "$PMM" ]; then
    echo "PMM address needs to be specified"
    exit 1;
fi;
 
instr() {
    echo "{\"value\": \"$2\", \"uuid\": \"$3\"}" | curl -XPUT -s -q --data-binary @- ${PMM}/api/v1/metric/$1 2>&1 > /dev/null
}
 
sleep_time=0.2
for i in $(seq 1 3000); do
    no=$RANDOM
    echo $no
    instr "random_numbers" "$no"
    sleep $sleep_time
done;
```

# Sample PXB run

```
# export PMM="http://127.0.0.1:8080"
# bash wrapper.sh --backup --stream=xbstream --parallel=8 > /dev/null

```