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
