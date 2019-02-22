#!/bin/sh

cID=$1

if [ -z "$cID" ]; then

	echo "container-id is needed" 
	exit 1;

fi;


IFS='' read -r -d '' variable <<"EOF"
#!/usr/bin/python

from bottle import request, response, route, run
from bottle import post, get, put, delete
from sys import exit
import urllib
import mysql.connector
from mysql.connector import Error
from mysql.connector import pooling
import uuid
import json
import gzip
import sys
import shutil


try:
    connection_pool = mysql.connector.pooling.MySQLConnectionPool(pool_name="pynative_pool",
                                                                  pool_size=5,
                                                                  pool_reset_session=True,
                                                                  host='localhost',
                                                                  database='metrics',
                                                                  user='metrics',
                                                                  password='bei3kuuF5i')
except Error as e :
    print ("Error while connecting to MySQL using Connection pool ", e)
    exit(1)


def doInsert(pool, query, v):
    try:
        cnx = pool.get_connection()
        cursor = cnx.cursor()
        cursor.execute(query, v)
        cnx.commit()
    finally:
        cnx.close()

def createTable(pool, table):
    schema = """
        CREATE TABLE `{0}` (
        `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
        `u1` varchar(100) DEFAULT NULL,
        `u2` varchar(100) DEFAULT NULL,
        `value` decimal(20,4) DEFAULT NULL,
        `b` text DEFAULT NULL,
        `timestamp` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`)
        ) ENGINE=InnoDB;
    """.format(table)

    doInsert(pool, schema, None)

@put('/api/v1/metric/<name>')
@put('/api/v1/metric/<name>/<u1>')
@put('/api/v1/metric/<name>/<u1>/<u2>')
def put_metric(name, u1=None, u2=None):
    try:
        #print request.body.read()
        data = json.loads(request.body.read())
        #print data

        query = "INSERT INTO "+ name +" (u1, u2, value, b) VALUES (%s, %s, %s, %s)"
        params = (u1, u2, data['value'], json.dumps(data))
        try:
            doInsert(connection_pool, query, params)
        except mysql.connector.ProgrammingError:
            createTable(connection_pool, name)
            doInsert(connection_pool, query, params)

        response.content_type = 'application/json'

        return json.dumps({'state': 'OK'})
    except ValueError:
       print sys.exc_info()[0]
       print sys.exc_info()[1]
       response.status = 503
       return json.dumps({'state': 'ERROR'})


PATH = "/tmp/"

@post('/api/v1/blob')
@post('/api/v1/blob/<parent>')
def post_blob(parent=None):
    try:
        uuid_=uuid.uuid4()

        print request.body.readlines()
        with open ('/'.join([PATH, str(uuid_)]), 'wb') as fd:
            request.body.seek (0)
            shutil.copyfileobj (request.body, fd)

        doInsert(connection_pool, "INSERT INTO logs(id, parent) VALUES (%s, %s)", (uuid_.bytes, parent))
    except:
        response.status = 503
        return

def get_File(id):
    uuid_ = uuid.UUID(id, version=4)

    bufsize = 1*1024*1024
    buf = ""
    with open('/'.join([PATH, str(uuid_)]), 'r') as file_: 
        while True:
            lines = file_.readlines(bufsize)
            if not lines:
                break
            for line in lines:
                buf += line

    return buf

@get('/api/v1/blob/<id>')
def get_blob(id):
    try:
        response.content_type = 'application/octet-stream'
        return get_File(id) 

    except:
        response.status = 503
        return



@get('/api/v1/blob/p/<p>')
def get_blob_by_parent(p):
    cnx = connection_pool.get_connection()
    cursor = cnx.cursor()
    cursor.execute("SELECT id FROM logs WHERE parent = %s", (p,))
    ids=[]
    for(id) in cursor:
        ids.append(id)
    cursor.close()
    cnx.close()

    response.content_type = 'application/octet-stream'

    return get_File(str(uuid.UUID(bytes=str(ids[0][0]))))


run(host='0.0.0.0', port=3141, debug=True)
EOF

tmpFile=$(mktemp)

echo "$variable" > $tmpFile

docker cp $tmpFile $cID:/usr/local/cm.py
docker exec -ti  $cID chmod +x /usr/local/cm.py

rm $tmpFile
tmpFile=$(mktemp)
echo "
[program:cm]
priority = 15
command =
    /usr/bin/python /usr/local/cm.py
stdout_logfile = /var/log/cm.log
stderr_logfile = /var/log/cm.log
autorestart = true
" > $tmpFile

docker cp $tmpFile $cID:/etc/supervisord.d/cm.ini

echo "echo \"CREATE DATABASE metrics; GRANT ALL PRIVILEGES ON metrics.* TO 'metrics'@'localhost' IDENTIFIED BY 'bei3kuuF5i';\" | mysql " | docker exec -i  $cID /bin/bash -
echo 'echo "CREATE TABLE logs (id binary(16) NOT NULL,b text,parent varchar(100) DEFAULT NULL,PRIMARY KEY (id)) ENGINE=InnoDB;" | mysql metrics' | docker exec -i  $cID /bin/bash -

echo "sed -i '\$ d' /etc/nginx/conf.d/pmm.conf" | docker exec -i  $cID /bin/bash -

echo  " echo 'location /api/v1/ { proxy_pass		http://127.0.0.1:3141; }}' >> /etc/nginx/conf.d/pmm.conf"  | docker exec -i  $cID /bin/bash -

echo 'yum install python-pip -y' | docker exec -i  $cID /bin/bash -
echo 'pip install --upgrade pip' | docker exec -i  $cID /bin/bash -
echo 'pip install mysql.connector bottle' | docker exec -i  $cID /bin/bash -

echo 'supervisorctl reload' | docker exec -i  $cID /bin/bash -
echo 'supervisorctl restart cm' | docker exec -i  $cID /bin/bash -  > /dev/null 2>&1