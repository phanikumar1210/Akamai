#!/bin/bash
# --------------------------------------------------------------------------------
#
# Initial - Tim Arnold - 03/10/2015
#
# --------------------------------------------------------------------------------

# --------------------------------------------------------------------------------
InitVar() {

   TMPFILE="/tmp/catalina.rotate.$$"
   CRONLINE="33 03 * * * /usr/local/bin/ArchiveWebLogs.sh > /dev/null 2>&1"
   CATALINALOGFILES=$(locate catalina.out | grep out$ | egrep -iv "back|bak")

}

# --------------------------------------------------------------------------------
AddCronLine() {

   TMPCRON="/tmp/tmp.cron.$$"

   # If already there, return.
   crontab -l | grep ArchiveWebLogs.sh > /dev/null
   if [ $? -eq 0 ]; then
      return
   fi

   crontab -l > $TMPCRON
   echo "$CRONLINE" >> $TMPCRON

   crontab $TMPCRON
   sync

   rm $TMPCRON

}

# --------------------------------------------------------------------------------
RotateCatalinaLogs() {

   for LOGFILE in $CATALINALOGFILES
   do
      OWNERNAME=$(ls -l  $LOGFILE | awk '{print $3}')
      GROUPNAME=$(ls -l  $LOGFILE | awk '{print $4}')
      echo "$LOGFILE {

   daily
   copytruncate
   compress
   dateext
   dateformat .%Y-%m-%d:%s
   create 664 $OWNERNAME $GROUPNAME

}" > $TMPFILE

      /usr/sbin/logrotate $TMPFILE
      sync

      rm -f $TMPFILE
   done

}

# --------------------------------------------------------------------------------
ArchiveCatalinaLogs() {

   for LOGFILE in $CATALINALOGFILES
   do

      CATDIRNAME=$(dirname $LOGFILE)
      ARCHIVEDIR=$CATDIRNAME/archive

      # Create the archive directory for our gzipped files if it doesn't exist.
      if [ ! -e $ARCHIVEDIR ]; then 
         mkdir $ARCHIVEDIR
      fi

      # gzip any file that was created the previous midnight or before.
      # This will actually handle all the log files in the same directory as catalina.out.
      find $CATDIRNAME/*.[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].log ! -newermt "$(date +%Y-%m-%d) 00:00:01" | xargs gzip -9 > /dev/null

      # Move our gzipped files to the archive.
      FILESTOMOVE=$(find $CATDIRNAME/*.gz -mtime +1)
      for THISFILE in $FILESTOMOVE
      do
         mv $THISFILE $ARCHIVEDIR
      done

      # Keep files in archive for 90 days.
      /usr/sbin/tmpwatch -m 90d $ARCHIVEDIR

   done

}

# --------------------------------------------------------------------------------

InitVar
AddCronLine
RotateCatalinaLogs
ArchiveCatalinaLogs

exit 0
