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
                                                                  password='pwd')
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
        print request.body.read()
        data = json.loads(request.body.read())
        print data

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
    print type(ids[0])

    return get_File(str(uuid.UUID(bytes=str(ids[0][0]))))


run(host='0.0.0.0', port=3141, debug=True)