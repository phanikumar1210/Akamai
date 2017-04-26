#!/bin/bash
# Alfresco FSR called shell script
# ---------------------------------------------------------------------------------------------------------------------
# Revision History:
# 09/22/2014 - Tim Arnold - Initial
#
# 01/07/2015 - Tim Arnold - Add '-m' parameter to disable mail option.
#
# 01/20/2015 - Tim Arnold - Add unique LOGFILE name per run.  Pass to AkamaiExpire.sh script.
#
# 02/04/2015 - Tim Arnold - Integrate xml mail config.
#
# 04/01/2015 - Tim Arnold - Add servers 24-27 to Louisville.
#
# 04/15/2015 - Tim Arnold - Add the SYNC_TO_SERVERS flag.
#                           Values: true (default) - sync content to front end servers.
#                                   false          - don't sync content to front end servers.
#
# 05/21/2015 - Tim Arnold - Add servers 24-27 to Lexington.
#
# 09/01/2015 - B Deutl    - Updated for Nashville.
# ---------------------------------------------------------------------------------------------------------------------

TESTMODE="false"

echo "----Syncmaster start----"

## Grab Parameters.
#while getopts "m" OPTION; do
#   case $OPTION in
#      m) SEND_STATUS_EMAILS=false;;
#      *) IGNORE=T;;  # Ignore other parameters.
#   esac
#done

# ------------------------------------------------------------------------------
ReadXML() {

   local IFS=\>
   read -d \< THISVAR THISVAL

}

# --------------------------------------------------------------------------------------------------
InitVar() {

   [ ! -d /var/log/syncmaster ] && mkdir /var/log/syncmaster

   USERNAME=tomcat   # Username to run sync script on web server as.

   LOGFILE="/var/log/syncmaster/syncmaster.log.`date +%s`.$$"
   touch $LOGFILE
   chown tomcat.tomcat $LOGFILE
   DAILYLOGFILE='/var/log/syncmaster/syncmaster.log'
   LOCKFILE='/var/lock/subsys/syncmaster'

   THISINSTANCE=`hostname | tr [a-z] [A-Z]`
   THISINSTANCE=$THISINSTANCE-`date +%s | cut -b6-10`
   MAILFROMADDRESS=$THISINSTANCE-Content_Sync@papajohns.com


   # Time to sleep between the active server deployment and the standby server deployment.
   SLEEPTIME=30
}

# ------------------------------------------------------------------------------
SetSync() {

   # Get the sync variable.
   INPUTFILE='/var/tomcat/site-root/content/site/components/crafter-level-descriptor.level.xml'
   OUTPUTFILE='/tmp/tmp.out'
   VARNAME='sync-to-webapp'

   # Determine if we're sending notification e-mails.
   SYNC_TO_SERVERS=true
   while ReadXML; do
      if [ "$THISVAR" == "$VARNAME" ]; then
         SYNC_TO_SERVERS=$THISVAL
      fi
   done <  $INPUTFILE

   if [ "$SYNC_TO_SERVERS" == "false" ]; then
      echo -e "\nServer synchronization is disabled!" >> $LOGFILE
      echo -e "No content will be sent to the front end servers!\n" >> $LOGFILE
      if [ "$SEND_STATUS_EMAILS" == "true" ]; then
         echo -e "Content deployment activated with server synchronization disabled!\n\nNo content sent to the front end servers.\n\n" | mail -r Alfresco_$LOCATION -s "$THISINSTANCE: Server Content Deployment was not synced!" $MAILTOADDRESS
      fi
   fi

}

# ------------------------------------------------------------------------------
SetEmail() {

   # Get the e-mail variable.
   INPUTFILE='/var/tomcat/site-root/content/site/components/crafter-level-descriptor.level.xml'
   OUTPUTFILE='/tmp/tmp.out'
   VARNAME='send-deployment-email'

   # Determine if we're sending notification e-mails.
   SEND_STATUS_EMAILS=true
   while ReadXML; do
      if [ "$THISVAR" == "$VARNAME" ]; then
         SEND_STATUS_EMAILS=$THISVAL
      fi
   done <  $INPUTFILE

   if [ "$SEND_STATUS_EMAILS" == "false" ]; then
      echo -e "\nE-mail notifications are disabled!" >> $LOGFILE
      echo -e "No status e-mails will be sent!\n" >> $LOGFILE
      AFLAGS='-m'
   else
      AFLAGS=''
   fi

}
# Added SetSyncImages to handle new OMS images. - Brian Deutl 09/01/2015
# This is a hook to add new functionality later.
# ------------------------------------------------------------------------------
SetSyncImages() {

   # Get the image sync variable.
   INPUTFILE='/var/tomcat/site-root/content/site/components/crafter-level-descriptor.level.xml'
   OUTPUTFILE='/tmp/tmp.out'
   VARNAME='sync-images-to-oms'

   # Determine if we're synchronizing the images.
   SYNC_IMAGES=true
   while ReadXML; do
      if [ "$THISVAR" == "$VARNAME" ]; then
         SYNC_IMAGES=$THISVAL
      fi
   done <  $INPUTFILE

   if [ "$SYNC_IMAGES" == "false" ]; then
      echo -e "\nImage sync disabled!" >> $LOGFILE
      IMG_SYNC_FLAG='-i'
   else
      IMG_SYNC_FLAG=''
   fi
   
}
# ------------------------------------------------------------------------------
Exit() {

   EXITCODE=$1

   echo "" >> $LOGFILE
   echo "`date`: Script `basename $0` exiting with code: $EXITCODE" >> $LOGFILE
   echo -e "\n\n" >> $LOGFILE

   echo "----Syncmaster end----"

   cat $LOGFILE >> $DAILYLOGFILE
   mv $LOGFILE /tmp

   rm -f $LOCKFILE
   exit $EXITCODE

}

# ------------------------------------------------------------------------------
CheckLockFile() {

   if [ -e $LOCKFILE ]; then
      echo -e "\n-------------------------------------------------------------------------------" >> $LOGFILE
      echo "`date`: Script `basename $0` start failed." >> $LOGFILE
      echo -e "\n---Lock file prevented Content Syncronization program from running on `hostname`\nPlease wait $SLEEPTIME seconds and try again.---\n" >> $LOGFILE
      if [ "$SEND_STATUS_EMAILS" == "true" ]; then
         echo -e "Lock file prevented Content Syncronization program from running: `hostname`\nPlease wait $SLEEPTIME seconds and try again." | mail -r Alfresco_$LOCATION -s "$THISINSTANCE: Content Syncronization Aborted!" $MAILTOADDRESS
      fi
      exit 101
   fi

   echo -e "\n-------------------------------------------------------------------" >> $LOGFILE
   echo "`date`: Script `basename $0` started successfully." >> $LOGFILE

   touch $LOCKFILE

}

# ------------------------------------------------------------------------------
SetServers() {

   HOSTNAME=$(hostname)
   QA=`echo $HOSTNAME | grep -c q0[1-4]`
   PROD=`echo $HOSTNAME | grep -c p0[1-4]`
   DEV=`echo $HOSTNAME | grep -c d0[1-4]`

   LOUACTIVE=`hostname | grep -ic ^lou`
   LEXACTIVE=`hostname | grep -ic ^lex`
   NASHACTIVE=`hostname | grep -ic ^nsh`
   if [ $DEV -gt 0 ]; then
      LOCATION='Development'
      MAILTOADDRESS=Alfresco_Content_Status@papajohns.com
      LOCALSERVERS="172.17.17.111 172.17.17.112"
      LOUSERVERS=""
      LEXSERVERS=""
   elif [ $QA -gt 0 ]; then
      LOCATION='QA'
      MAILTOADDRESS=Alfresco_QA_Content_Status@papajohns.com
      LOCALSERVERS="172.25.25.13 172.25.25.14"
      LOUSERVERS=""
      LEXSERVERS=""
   elif [ $PROD -gt 0 ]; then
      LOCATION='Production'
      MAILTOADDRESS=Alfresco_Content_Status@papajohns.com
      # Put this here for now as we are adding servers to Louisville, but not Lex (04/01/15).
	  # Check if statement here.
      # Changed if statement to adjust for Nashville.
      if [ $LOUACTIVE -gt 0 -o $LEXACTIVE -gt 0 ]; then
         LOCALSERVERS="172.25.25.21 172.25.25.22 172.25.25.23 172.25.25.24 172.25.25.25 172.25.25.26 172.25.25.27"
      else 
         LOCALSERVERS="172.25.25.31 172.25.25.32 172.25.25.33 172.25.25.34 172.25.25.35 172.25.25.36 172.25.25.37"
      fi
      LOUSERVERS="10.110.125.21 10.110.125.22 10.110.125.23 10.110.125.24 10.110.125.25 10.110.125.26 10.110.125.27"
      LEXSERVERS="10.115.125.21 10.115.125.22 10.115.125.23 10.115.125.24 10.115.125.25 10.115.125.26 10.115.125.27"
	  # Added NASHSERVERS for Nashville. - B Deutl 09/01/2015
      NSHSERVERS="10.20.125.31 10.20.125.32 10.20.125.33 10.20.125.34 10.20.125.35 10.20.125.36 10.20.125.37"
   else
      LOCATION=$HOSTNAME
   fi

   if [ "$TESTMODE" == "true" ]; then
      MAILTOADDRESS="tim_arnold@papajohns.com"
   fi

   if [ $LOUACTIVE -gt 0 ]; then
      ACTIVESERVERS=$LOCALSERVERS
      STANDBYSERVERS="$LEXSERVERS $NSHSERVERS"
      ACTIVEPLACE="Louisville"
      STANDBYPLACE="Lexington Nashville"
   elif [ $LEXACTIVE -gt 0 ] ;then
      ACTIVESERVERS=$LOCALSERVERS
      STANDBYSERVERS="$LOUSERVERS $NSHSERVERS"
      ACTIVEPLACE="Lexington"
      STANDBYPLACE="Louisville Nashville"
   # Added elif for Nashville. - B Deutl 09/01/2015
   elif [ $NASHACTIVE -gt 0 ] ;then
      ACTIVESERVERS=$LOCALSERVERS
      STANDBYSERVERS="$LOUSERVERS $LEXSERVERS"
      ACTIVEPLACE="Nashville"
      STANDBYPLACE="Louisville Lexington"
   else
      echo "Could not determine active servers from host name: `hostname`" >> $LOGFILE
      if [ "$SEND_STATUS_EMAILS" == "true" ]; then
         echo -e "Could not determine active servers from host name: `hostname`" | mail -r Alfresco_$LOCATION -s "$THISINSTANCE: Content Validation Aborted!" $MAILTOADDRESS
      fi
      Exit 102
   fi

}

# ------------------------------------------------------------------------------
SyncActiveServers() {

   # Sync the directories
   RETCODE=0
   RETCODETOTAL=0
   STATUSLIST=""
   GOODSERVERSACTIVE1=""
   BADSERVERSACTIVE1=""

   for x in $ACTIVESERVERS
   do
      echo -e "\n-Kicking off websync.sh script on server: $x" >> $LOGFILE
      ssh -o StrictHostKeyChecking=no $USERNAME@$x sudo /usr/local/bin/websync.sh >> $LOGFILE 2>&1
      RETCODE=$?
      let RETCODETOTAL=$RETCODETOTAL+$RETCODE
      STATUSLIST="$STATUSLIST$x returned code: $RETCODE while syncing the data.\n"
      if [ $RETCODE -eq 0 ]; then
         GOODSERVERSACTIVE1="$GOODSERVERSACTIVE1 $x"
      else
         BADSERVERSACTIVE1="$BADSERVERSACTIVE1 $x"
      fi
   done

   if [ $RETCODETOTAL -eq 0 ]; then
      if [ "$SEND_STATUS_EMAILS" == "true" ]; then
         echo -e "Active ($ACTIVEPLACE) server content sync results:\n\nA returned 0 (zero) is indicative of a successful sync.\n\n$STATUSLIST" | mail -r Alfresco_$LOCATION -s "$THISINSTANCE: Active Server Content Sync was SUCCESSFUL!" $MAILTOADDRESS
      fi
      echo -e "\nActive ($ACTIVEPLACE) server content sync results:\n\nA returned 0 (zero) is indicative of a successful sync.\n\n$STATUSLIST\n$THISINSTANCE: Active Server Content Sync was SUCCESSFUL!\n" >> $LOGFILE
   else
      if [ "$SEND_STATUS_EMAILS" == "true" ]; then
         echo -e "Active ($ACTIVEPLACE) server content sync results:\n\nA returned 0 (zero) is indicative of a successful sync.\n\n$STATUSLIST" | mail -r Alfresco_$LOCATION -s "$THISINSTANCE: Active Server Content Sync FAILED!" $MAILTOADDRESS
      fi
      echo -e "\nActive ($ACTIVEPLACE) server content sync results:\n\nA returned 0 (zero) is indicative of a successful sync.\n\n$STATUSLIST\n$THISINSTANCE: Active Server Content Sync FAILED!\n" >> $LOGFILE
   fi

   echo "" >> $LOGFILE

   sync

}

# ------------------------------------------------------------------------------
ExpireCacheActiveServers() {

   # Expire the caches of the servers that got the files.
   RETCODE=0
   RETCODETOTAL=0
   STATUSLIST=""
   GOODSERVERSACTIVE2=""
   BADSERVERSACTIVE2="$BADSERVERSACTIVE1"

   for y in $GOODSERVERSACTIVE1
   do
      cd /tmp
      echo "Expiring cache on server: $y" >> $LOGFILE

      A=$(wget --timeout=5 http://$y:8080/api/1/cache/clear_all 2>&1)
      echo $A >> $LOGFILE
      echo "" >> $LOGFILE

      # Remove the file we just wgot since it's really just a useless empty file.
      rm /tmp/clear_all

      if [ ! -z "$A" ]; then
         echo $A | grep -ic '200 OK' > /dev/null 2>&1
         RETCODE=$?
      else
         RETCODE=111
      fi

      let RETCODETOTAL=$RETCODETOTAL+$RETCODE
      STATUSLIST="$STATUSLIST$y returned code: $RETCODE while expiring the cache.\n"
      if [ $RETCODE -eq 0 ]; then
         GOODSERVERSACTIVE2="$GOODSERVERSACTIVE2 $y"
      else
         BADSERVERSACTIVE2="$BADSERVERSACTIVE2 $y"
      fi
   done


   if [ $RETCODETOTAL -eq 0 ]; then
      if [ "$SEND_STATUS_EMAILS" == "true" ]; then
         echo -e "Active ($ACTIVEPLACE) server cache expiration results:\n\nA returned 0 (zero) is indicative of a successful cache expiration.\n\n$STATUSLIST" | mail -r Alfresco_$LOCATION -s "$THISINSTANCE: Active Server Content Cache expiration was SUCCESSFUL!" $MAILTOADDRESS
      fi
      echo -e "\nActive ($ACTIVEPLACE) server cache expiration results:\n\nA returned 0 (zero) is indicative of a successful cache expiration.\n\n$STATUSLIST\n$THISINSTANCE: Active Server Content Cache expiration was SUCCESSFUL!\n" >> $LOGFILE
   else
      if [ "$SEND_STATUS_EMAILS" == "true" ]; then
         echo -e "Active ($ACTIVEPLACE) server cache expiration results:\n\nA returned 0 (zero) is indicative of a successful cache expiration.\n\n$STATUSLIST" | mail -r Alfresco_$LOCATION -s "$THISINSTANCE: Active Server Content Cache expiration FAILED!" $MAILTOADDRESS
      fi
      echo -e "\nActive ($ACTIVEPLACE) server cache expiration results:\n\nA returned 0 (zero) is indicative of a successful cache expiration.\n\n$STATUSLIST\n$THISINSTANCE: Active Server Content Cache expiration FAILED!\n" >> $LOGFILE
#      Exit 106
   fi

   echo "" >> $LOGFILE

   sync

}

# ------------------------------------------------------------------------------
UpdateActiveIndexes() {

   # Update the solr indexes on the servers that got the files.
   RETCODE=0
   RETCODETOTAL=0
   STATUSLIST=""
   GOODSERVERSACTIVE3=""
   BADSERVERSACTIVE3="$BADSERVERSACTIVE1"

   for z in $GOODSERVERSACTIVE1
   do
      cd /tmp
      echo "Sending solr index update request to server: $z" >> $LOGFILE

#      curl --connect-timeout 5 --max-time 60 http://$z:8080/solr-crafter/replication?command=fetchindex 2>&1 | grep status\"\>OK > /dev/null 2>&1
      echo "curl --connect-timeout 5 --max-time 60 http://$z:8080/solr-crafter/replication?command=fetchindex" >> $LOGFILE
      curl --connect-timeout 5 --max-time 60 http://$z:8080/solr-crafter/replication?command=fetchindex 2>&1 > /tmp/solrcurl.out
      cat /tmp/solrcurl.out | grep status\"\>OK > /dev/null 2>&1
      RETCODE=$?

      cat /tmp/solrcurl.out >> $LOGFILE
      echo "" >> $LOGFILE

      let RETCODETOTAL=$RETCODETOTAL+$RETCODE
      STATUSLIST="$STATUSLIST$z returned code: $RETCODE while requesting solr index update.\n"
      if [ $RETCODE -eq 0 ]; then
         GOODSERVERSACTIVE3="$GOODSERVERSACTIVE3 $z"
      else
         BADSERVERSACTIVE3="$BADSERVERSACTIVE3 $z"
      fi
   done

   if [ $RETCODETOTAL -eq 0 ]; then
      if [ "$SEND_STATUS_EMAILS" == "true" ]; then
         echo -e "Active ($ACTIVEPLACE) solr index update request results:\n\nA returned 0 (zero) is indicative of a successful request.\n\n$STATUSLIST" | mail -r Alfresco_$LOCATION -s "$THISINSTANCE: Active Server solr index update was SUCCESSFUL!" $MAILTOADDRESS
      fi
      echo -e "\nActive ($ACTIVEPLACE) solr index update request results:\n\nA returned 0 (zero) is indicative of a successful request.\n\n$STATUSLIST\n$THISINSTANCE: Active Server solr index update was SUCCESSFUL!\n" >> $LOGFILE
   else
      if [ "$SEND_STATUS_EMAILS" == "true" ]; then
         echo -e "Active ($ACTIVEPLACE) solr index update request results:\n\nA returned 0 (zero) is indicative of a successful request.\n\n$STATUSLIST" | mail -r Alfresco_$LOCATION -s "$THISINSTANCE: Active Server solr index update FAILED!" $MAILTOADDRESS
      fi
      echo -e "\nActive ($ACTIVEPLACE) solr index update request results:\n\nA returned 0 (zero) is indicative of a successful request.\n\n$STATUSLIST\n$THISINSTANCE: Active Server solr index update FAILED!\n" >> $LOGFILE
   fi

   echo "" >> $LOGFILE

   sync

}

# ------------------------------------------------------------------------------
SyncStandbyServers() {

   # Sync the directories
   RETCODE=0
   RETCODETOTAL=0
   STATUSLIST=""
   GOODSERVERSSTANDBYSTANDBY1=""
   BADSERVERSSTANDBYSTANDBY1=""

   for x in $STANDBYSERVERS
   do
      echo -e "\n-Kicking off websync.sh script on server: $x" >> $LOGFILE
      ssh -o StrictHostKeyChecking=no $USERNAME@$x sudo /usr/local/bin/websync.sh >> $LOGFILE 2>&1
      RETCODE=$?
      let RETCODETOTAL=$RETCODETOTAL+$RETCODE
      STATUSLIST="$STATUSLIST$x returned code: $RETCODE while syncing the data.\n"
      if [ $RETCODE -eq 0 ]; then
         GOODSERVERSSTANDBY1="$GOODSERVERSSTANDBY1 $x"
      else
         BADSERVERSSTANDBY1="$BADSERVERSSTANDBY1 $x"
      fi
   done

   if [ $RETCODETOTAL -eq 0 ]; then
      if [ "$SEND_STATUS_EMAILS" == "true" ]; then
         echo -e "Stand-by ($STANDBYPLACE) server content sync results:\n\nA returned 0 (zero) is indicative of a successful sync.\n\n$STATUSLIST" | mail -r Alfresco_$LOCATION -s "$THISINSTANCE: Stand-by Server Content Sync was SUCCESSFUL!" $MAILTOADDRESS
      fi
      echo -e "\nStand-by ($STANDBYPLACE) server content sync results:\n\nA returned 0 (zero) is indicative of a successful sync.\n\n$STATUSLIST\n$THISINSTANCE: Stand-by Server Content Sync was SUCCESSFUL!\n" >> $LOGFILE
   else
      if [ "$SEND_STATUS_EMAILS" == "true" ]; then
         echo -e "Stand-by ($STANDBYPLACE) server content sync results:\n\nA returned 0 (zero) is indicative of a successful sync.\n\n$STATUSLIST" | mail -r Alfresco_$LOCATION -s "$THISINSTANCE: Stand-by Server Content Sync FAILED!" $MAILTOADDRESS
      fi
      echo -e "\nStand-by ($STANDBYPLACE) server content sync results:\n\nA returned 0 (zero) is indicative of a successful sync.\n\n$STATUSLIST\n$THISINSTANCE: Stand-by Server Content Sync FAILED!\n" >> $LOGFILE
   fi

   echo "" >> $LOGFILE

   sync

}

# ------------------------------------------------------------------------------
ExpireCacheStandbyServers() {

   # Expire the caches of the servers that got the files.
   RETCODE=0
   RETCODETOTAL=0
   STATUSLIST=""
   GOODSERVERSSTANDBY2=""
   BADSERVERSSTANDBY2="$BADSERVERSSTANDBY1"

   for y in $GOODSERVERSSTANDBY1
   do
      cd /tmp
      echo "Expiring cache on server: $y" >> $LOGFILE

      A=$(wget --timeout=5 http://$y:8080/api/1/cache/clear_all 2>&1)
      echo $A >> $LOGFILE
      echo "" >> $LOGFILE

      # Remove the file we just wgot since it's really just a useless empty file.
      rm /tmp/clear_all

      if [ ! -z "$A" ]; then
         echo $A | grep -ic '200 OK' > /dev/null 2>&1
         RETCODE=$?
      else
         RETCODE=111
      fi

      let RETCODETOTAL=$RETCODETOTAL+$RETCODE
      STATUSLIST="$STATUSLIST$y returned code: $RETCODE while expiring the cache.\n"
      if [ $RETCODE -eq 0 ]; then
         GOODSERVERSSTANDBY2="$GOODSERVERSSTANDBY2 $y"
      else
         BADSERVERSSTANDBY2="$BADSERVERSSTANDBY2 $y"
      fi
   done


   if [ $RETCODETOTAL -eq 0 ]; then
      if [ "$SEND_STATUS_EMAILS" == "true" ]; then
         echo -e "Stand-by ($STANDBYPLACE) server cache expiration results:\n\nA returned 0 (zero) is indicative of a successful cache expiration.\n\n$STATUSLIST" | mail -r Alfresco_$LOCATION -s "$THISINSTANCE: Stand-by Server Content Cache expiration was SUCCESSFUL!" $MAILTOADDRESS
      fi
      echo -e "\nStand-by ($STANDBYPLACE) server cache expiration results:\n\nA returned 0 (zero) is indicative of a successful cache expiration.\n\n$STATUSLIST\n$THISINSTANCE: Stand-by Server Content Cache expiration was SUCCESSFUL!\n" >> $LOGFILE
   else
      if [ "$SEND_STATUS_EMAILS" == "true" ]; then
         echo -e "Stand-by ($STANDBYPLACE) server cache expiration results:\n\nA returned 0 (zero) is indicative of a successful cache expiration.\n\n$STATUSLIST" | mail -r Alfresco_$LOCATION -s "$THISINSTANCE: Stand-by Server Content Cache expiration FAILED!" $MAILTOADDRESS
      fi
      echo -e "\nStand-by ($STANDBYPLACE) server cache expiration results:\n\nA returned 0 (zero) is indicative of a successful cache expiration.\n\n$STATUSLIST\n$THISINSTANCE: Stand-by Server Content Cache expiration FAILED!\n" >> $LOGFILE
#      Exit 107
   fi

   echo "" >> $LOGFILE

   sync

}

# ------------------------------------------------------------------------------
UpdateStandbyIndexes() {

   # Update the solr indexes on the servers that got the files.
   RETCODE=0
   RETCODETOTAL=0
   STATUSLIST=""
   GOODSERVERSSTANDBY3=""
   BADSERVERSSTANDBY3="$BADSERVERSSTANDBY1"

   for z in $GOODSERVERSSTANDBY1
   do
      cd /tmp
      echo "Sending solr index update request to server: $z" >> $LOGFILE

      echo "curl --connect-timeout 5 --max-time 60 http://$z:8081/solr-crafter/replication?command=fetchindex" >> $LOGFILE
      curl --connect-timeout 5 --max-time 60 http://$z:8081/solr-crafter/replication?command=fetchindex 2>&1 > /tmp/solrcurl.out
      cat /tmp/solrcurl.out | grep status\"\>OK > /dev/null 2>&1
      RETCODE=$?

      cat /tmp/solrcurl.out >> $LOGFILE
      echo "" >> $LOGFILE

      let RETCODETOTAL=$RETCODETOTAL+$RETCODE
      STATUSLIST="$STATUSLIST$z returned code: $RETCODE while requesting solr index update.\n"
      if [ $RETCODE -eq 0 ]; then
         GOODSERVERSSTANDBY3="$GOODSERVERSSTANDBY3 $z"
      else
         BADSERVERSSTANDBY3="$BADSERVERSSTANDBY3 $z"
      fi
   done

   if [ $RETCODETOTAL -eq 0 ]; then
      if [ "$SEND_STATUS_EMAILS" == "true" ]; then
         echo -e "Stand-by ($STANDBYPLACE) solr index update request results:\n\nA returned 0 (zero) is indicative of a successful request.\n\n$STATUSLIST" | mail -r Alfresco_$LOCATION -s "$THISINSTANCE: Stand-by Server solr index update was SUCCESSFUL!" $MAILTOADDRESS
      fi
      echo -e "\nStand-by ($STANDBYPLACE) solr index update request results:\n\nA returned 0 (zero) is indicative of a successful request.\n\n$STATUSLIST\n$THISINSTANCE: Stand-by Server solr index update was SUCCESSFUL!\n" >> $LOGFILE
   else
      if [ "$SEND_STATUS_EMAILS" == "true" ]; then
         echo -e "Stand-by ($STANDBYPLACE) solr index update request results:\n\nA returned 0 (zero) is indicative of a successful request.\n\n$STATUSLIST" | mail -r Alfresco_$LOCATION -s "$THISINSTANCE: Stand-by Server solr index update FAILED!" $MAILTOADDRESS
      fi
      echo -e "\nStand-by ($STANDBYPLACE) solr index update request results:\n\nA returned 0 (zero) is indicative of a successful request.\n\n$STATUSLIST\n$THISINSTANCE: Stand-by Server solr index update FAILED!\n" >> $LOGFILE
   fi

   echo "" >> $LOGFILE

   sync

}

# ------------------------------------------------------------------------------
SetLogRotation() {

   echo -e '/var/log/syncmaster/syncmaster.log {

   daily
   dateext
   notifempty
   rotate 90
   create 600 tomcat tomcat\n\n}' > /etc/logrotate.d/syncmaster

   chown root.root /etc/logrotate.d/syncmaster
   chmod 644 /etc/logrotate.d/syncmaster

}

# ------------------------------------------------------------------------------
AkamaiExpire() {

   sync
   sleep 3
   echo -e "Attempting to send file list to Akamai for expiration." >> $LOGFILE
   echo "/usr/local/bin/AkamaiExpire.sh -l $LOGFILE $AFLAGS" >> $LOGFILE 2>&1
   /usr/local/bin/AkamaiExpire.sh -l $LOGFILE $AFLAGS >> $LOGFILE 2>&1

}
#! If FSR is migrated to Nashville make sure routes exist and keys are set up. !#
# ------------------------------------------------------------------------------
CopyAlfDataToDevServer() {

   cd /var/tomcat

   ZIPFILE=/tmp/Crafter$LOCATION\Content.zip
   REMOTEUSER=alfrescocontent
   REMOTEIP=10.30.24.69
   REMOTEDIR=/var/www/html/files

   rm $ZIPFILE > /dev/null 2>&1

   zip -r $ZIPFILE site-root > /dev/null

   echo -e "Copying Alfresco Data $ZIPFILE to $REMOTEIP" >> $LOGFILE
   echo -e "scp $ZIPFILE $REMOTEUSER@$REMOTEIP:$REMOTEDIR\n" >> $LOGFILE

   scp $ZIPFILE $REMOTEUSER@$REMOTEIP:$REMOTEDIR >> $LOGFILE 2>&1

   rm $ZIPFILE > /dev/null 2>&1

}

# ------------------------------------------------------------------------------

InitVar
CheckLockFile
SetEmail
# Added SetSyncImages call to handle syncing OMS images. - Brian Deutl 09/01/2015
# This will be enabled later.
#SetSyncImages
SetServers
SetSync

if [ "$SYNC_TO_SERVERS" == "true" ]; then
   SyncActiveServers
   UpdateActiveIndexes
   ExpireCacheActiveServers
   SyncStandbyServers
   UpdateStandbyIndexes
   ExpireCacheStandbyServers
   AkamaiExpire
fi

SetLogRotation
CopyAlfDataToDevServer

Exit 0
