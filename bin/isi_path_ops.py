#!/usr/local/venv/bin/python3
"""Get events per directory quota from InsightIQ. 
"""
__author__ = "midenney.aBiz.com"
__version__ = "1.2.4"

import sys
import os
import pprint
import logging
import io
import copy 
import re
import shutil
import time
import datetime
import csv
import mysql.connector

os.chdir(os.path.dirname(os.path.realpath(__file__)))
sys.path.append("../pylib")
import hosts
import rpt
import util
###########################################################################
def history():
     """
        1.0.0 initial skel
        1.1.0 using iiq_export
        1.2.0 using ssh psql
        1.2.1 po = int(i['piops'] * 288) - Changed to 288 from 300
        1.2.2 mycur.close() bug, moved to main. Added some try: except:
        1.2.3 added multiple exception: try-catch for when psql returns unexpected data
        1.2.4 #!/usr/local/venv/bin/python3
     """
     pass
###########################################################################
## GLOBALS
###########################################################################
iops = {}     ##Dictionary for gather info
iqhost = ''   ##The remote host object
mydb = ''
mycur = ''
###########################################################################
def update_db():
    """Update QtreeStats table with iops{} data."""
    log.info("update_db()")
    connect_mysql()
    for isilon,paths in iops.items():
        for path,i in paths.items():
            try:
               po = int(i['piops'] * 288)
            except Exception as err:
               log.error("{}:{} {}".format(isilon,path,err))
               continue
            fi = i['fsid']
            isql = ("INSERT INTO QtreeStats (nfs_ops, cifs_ops, fs_id) "
                    "VALUES ({}, 0, {})".format(po,fi)
                   )
            log.info("Dataservices sql->{}".format(isql))
            if argo.dry:
                print(isql)
            else:
                mycur.execute(isql)
    mycur.close()
###########################################################################
def connect_mysql():
    """Open DB conenction""
       Set global mycur = mysql.cursor"""
    global mydb
    global mycur
    log.info("connect_mysql()")
    log.info("host->{} user->{} database->{}"
             .format(opts.mysql_host,opts.mysql_user,opts.mysql_db))
    try:
        mydb = mysql.connector.connect(
            host = opts.mysql_host,
            user = opts.mysql_user,
            passwd = opts.mysql_pw,
            database = opts.mysql_db
        )
        mycur = mydb.cursor(buffered=True)
        return(True)
    except Exception as err:
        log.error('Error connect to DB')
        log.error(err)
        return(False)
###########################################################################
def getPaths(isilon=None):
    """Get the quota paths from DataServices db, put into iops{}"""
    if not isilon:
        return
    log.info("getPaths(isilon)")
    sql = ("SELECT qtree,indx FROM DataServices.FileSystems " 
           "WHERE (FileServer = '{}' and active = 1)".format(isilon)
          )
    log.info("sql->{}".format(sql))
    try:
       mycur.execute(sql)
    except Exception as e:
       log.error(e)
       return 
    for path,fsid in mycur.fetchall():
        #print(path,fsid)
        iops.setdefault(isilon,{})[path] = {}
        iops[isilon][path]['fsid'] = fsid
###########################################################################
def getDbName(isilon=None):
    """Get insightIQ database name for given Isilon"""
    if not isilon:
        return
    log.info("getOps(isilon)")
    sql = 'SELECT datname FROM pg_database WHERE datname like $${}%$$'.format(isilon)
    sshsql = """psql insightiq -t -c '{}'""".format(sql)
    iqhost.cmd(sshsql)
    return(iqhost.stdout[0])
###########################################################################
def isfloat(str):
    try: 
        return float(str)
    except ValueError: 
        return 0
    return str
###########################################################################
def get_cotime():
    """cotime = cut off time. Current epoch minus 86400"""
    etime = int(time.time())
    cotime = etime - 86400 #24 hours ago cut off time
    hcotime = (time.strftime("%a %b %d %H:%M:%S %Y",time.localtime(cotime)))
    log.info("24 hours ago cut off epoch time -> {}".format(cotime))
    log.info("24 hours ago cut off human time -> {}".format(hcotime))
    return cotime
###########################################################################
def getOps(isilon=None):
    """Get the heat iops per path from InsightIQ DB.
       First need to get the DB name per isilon name.
       Note, ssh connect to InsightIQ DB server because seems like a firewall 
       blocks remote sql."""
    if not isilon:
        return
    log.info("getOps({})".format(isilon))
    cotime = get_cotime()
    dbname = getDbName(isilon)
    for path in iops[isilon]:
        sql = 'SELECT SUM(op_rate) FROM ifs_file_heat_raw WHERE (path '
        sql = sql + 'LIKE $${}%$$ AND time > {})'.format(path,cotime)
        sshsql = """psql -t -d {} -c '{}'""".format(dbname,sql)
        iqhost.cmd(sshsql)
        try:
           piops = isfloat(iqhost.stdout[0])
        except Exception as err:
           log.error("{}:{} {}".format(isilon,path,err))
           continue
        iops[isilon][path]['piops'] = piops
###########################################################################
def fetch_db_info(jfile):
    """Get the isilon names from DataServices into iops{}.
       Then call the getPaths function to get the qtree->fsid paths from 
       Dataservices into iops{}.
       Then call getOps function to get iops from InsightIQ DB into iops{}.
    """
    log.info("fetch_db_info(jfile)")
    sql = ("SELECT name FROM DataServices.FilerData "
           "WHERE (type = 'isilon' and active = 1 and model != 'isiZone')"
          )
    log.info("Dataservices sql->{}".format(sql))
    mycur.execute(sql)
    for isilon in mycur.fetchall():
        log.info("Processing " + isilon[0])
        getPaths(isilon[0])
    for isilon in iops:
        getOps(isilon)
    if iops:
        iqhost.put_json_file(ifile=jfile,icontent=iops)
###########################################################################
def main():
    log.info("START")
    global opts
    global iqhost
    global iops
    opts=hosts.SetOpts(opts=argo,main='hosts',script=True)
    log.debug(pprint.pformat(opts.__dict__))
    lop=hosts.SetOpts(opts=opts,flavor='linux')
    iqhost = hosts.Host(opts.iqhost)
    iqhost.ruser = opts.iquser
    if not connect_mysql():
        log.error("unable to connect to mysql")
        hosts.errors_check(host='NA')
        hosts.errors_alert(opts)
        sys.exit()
    jfile = 'iops'
    iops = iqhost.fresh_json(jfile)
    if not iops:
        iops = {}
        fetch_db_info(jfile)
    update_db()
    mycur.close()
    hosts.errors_check(host='NA')
    hosts.errors_alert(opts)
    log.info("END")
##########################################################################
"""options hash/objects used in script:
     argo = command line args.
     opts = main options from argo and hosts.conf file.
     op   = options from flavor (vnx.conf, netapp.conf, script.conf) 
            combined with opts.
"""
###########################################################################
if __name__ == "__main__":
   d = ("Get qtree-IOPS from InsightIQ DB and INSERT into Dataservices DB.")
   argo=hosts.ArgParseLight(description = d)
   h = ("Print to STDOUT all SQL INSERT statements,"
        " but do not execute the SQL INSERT.")
   argo.add_argument('--dry',action='store_true',help=h)
   argo=argo.parse_args()
   if argo.version : print (argo.script + " Version " + __version__) 
   if argo.history : print (history.__doc__)
   if argo.version or argo.history: sys.exit()
   log = logging.getLogger()
   hosts.config_logging(opt=argo)
   log.debug(pprint.pformat(argo.__dict__))
   main()
   sys.exit(0)
