#!/bin/bash
# --------------------------------------------------------------------------------------------------
# AkamaiList.sh - program to generate and submit a list of files for expiration.
#
# Revision History:
# 03/10/2011 - Tim Arnold - Initial.
#
# 10/13/2014 - Tim Arnold - Update for new web site. Change name to AkamaiExpire.sh
#
# 11/18/2014 - Tim Arnold - Add retry on failed Akamai communication.
#
# 12/19/2014 - Tim Arnold - Add JobChecker function to check expiration on Akamai servers.
#
# 01/20/2015 - Tim Arnold - Add LOGFILE parameter.
#
# 02/04/2015 - Tim Arnold - Integrate xml mail config.
# --------------------------------------------------------------------------------------------------

SEND_STATUS_EMAILS=true

# Grab Parameters.
while getopts "ml:" OPTION; do
   case $OPTION in
      l) LOGFILE=$OPTARG;;
      m) SEND_STATUS_EMAILS=false;;
      *) IGNORE=T;;  # Ignore other parameters.
   esac
done

# --------------------------------------------------------------------------------------------------
InitVar() {

   LINETHRESHHOLD=333
   THISRUN=$(date +%s.$$)
   MAILLIST='Alfresco_Content_Status@papajohns.com'
   FILESPRESENT=0

# For testing.
#   MAILLIST='tim_arnold@papajohns.com'

   if [ "tim$LOGFILE" == "tim" ]; then
      LOGFILE='/var/log/syncmaster/syncmaster.log'
   fi

   HOSTNAME=$(hostname)
   QA=`echo $HOSTNAME | grep -c q0[1-4]`
   PROD=`echo $HOSTNAME | grep -c p0[1-4]`
   DEV=`echo $HOSTNAME | grep -c d0[1-4]`

   if [ $DEV -gt 0 ]; then
      LOCATION='Development'
      PREPEND='http://dev1.papajohns.com/'
   elif [ $QA -gt 0 ]; then
      LOCATION='QA'
      PREPEND='http://orderqa.papajohns.com/'
   elif [ $PROD -gt 0 ]; then
      LOCATION='Production'
      PREPEND='http://order.papajohns.com/'
   else
      LOCATION=$HOSTNAME
   fi

   TMPLIST="/tmp/tmplist.$THISRUN.txt"
   FILELIST="/tmp/filelist.$THISRUN.txt"
   CCUOUT="/tmp/ccuout.$THISRUN.txt"
   NOTICE="/tmp/notice.$THISRUN.txt"

   USER='alfresco_automation@papajohns.com'
   PASSWD='8rJBcfP0dcvLabsFyA1W4Expiring' 
   AKAMAIDOMAIN='production'

}

# --------------------------------------------------------------------------------------------------
GetFileList() {

   
   cat $LOGFILE | grep '^content/static-assets' | sed 's;^content/;;g' | grep -v \/$ | sort -u > $TMPLIST

   cat $TMPLIST | sed "s|^|$PREPEND|" | grep -v \/$ > $FILELIST

   # Split the list into $LINETHRESHHOLD line files, if necessary.
   FILESPRESENT=$(wc -l $FILELIST | awk '{print $1}')
   if [ $FILESPRESENT -gt $LINETHRESHHOLD ]; then
      /usr/bin/split -d -l $LINETHRESHHOLD $FILELIST $FILELIST.
   fi

   # For testing:
   # echo 'http://order.papajohns.com/assets/images/layout/TestFile.jpg' >> $FILELIST

}

# --------------------------------------------------------------------------------------------------
JobChecker() {

   echo "
   NOTICE=/tmp/NOTICE.$REQID
   SUCCESSSUBJECT=\"SUCCESS!  Files Expired on Akamai ($LOCATION) request ($REQID) on \`date\`\"
   FAILSUBJECT=\"FAILURE!  Files NOT Expired on Akamai ($LOCATION) request ($REQID) on \`date\`\"
   TIMEOUTVAL=30 # Timeout value for wget connection.
   SLEEPTIME=30  # Sleep time between wget attempts.
   TOTATTEMPTS=120  # This should equal one hour.

   cd /tmp

   ATTEMPT=0
   while true
   do
      rm /tmp/$REQID*
      wget --user=\"$USER\" --password=\"$PASSWD\" --timeout=\$TIMEOUTVAL https://api.ccu.akamai.com/ccu/v2/purges/$REQID
      cat /tmp/$REQID* | grep '\\\"purgeStatus\\\"\:\ \\\"Done\\\"'
      RETURNCODE=\$?

      if [ \$RETURNCODE -eq 0 ]; then
         cat /tmp/$REQID* | sed 's/,/\n/g' | sed 's/[{}]/ /g' | sed 's/\"//g' >> \$NOTICE
         SUBJECT=\$SUCCESSSUBJECT
         break
      fi

      sleep \$SLEEPTIME
      let ATTEMPT=\$ATTEMPT+1
      if [ \$ATTEMPT -ge \$TOTATTEMPTS ]; then
         echo -e \"\nFiles failed to expire on Akamai in the allotted time.\nPlease follow up immediately.\n\" >> \$NOTICE
         cat /tmp/$REQID* | sed 's/,/\n/g' | sed 's/[{}]/ /g' | sed 's/\"//g' >> \$NOTICE
         SUBJECT=\$FAILSUBJECT
         break
      fi
   done

   if [ "$SEND_STATUS_EMAILS" == "true" ]; then
      cat \$NOTICE | mail -r Alfresco_$LOCATION -s \"\$SUBJECT\" $MAILLIST
   fi

   rm /tmp/$REQID* \$NOTICE

" > /tmp/$REQID.sh

   chmod 755 /tmp/$REQID.sh
   sync

   cd /tmp
   nohup ./$REQID.sh &

}

# --------------------------------------------------------------------------------------------------
HandleAkamaiRequest() {

      if [ "$SEND_STATUS_EMAILS" == "true" ]; then
         echo "/usr/local/bin/CCURequest.pl --user $USER --pwd $PASSWD --file $THISFILELIST --domain $AKAMAIDOMAIN --email $MAILLIST" >> $LOGFILE
         /usr/local/bin/CCURequest.pl --user $USER --pwd $PASSWD --file $THISFILELIST --domain $AKAMAIDOMAIN --email $MAILLIST > $THISCCUOUT
      else
         echo "/usr/local/bin/CCURequest.pl --user $USER --pwd $PASSWD --file $THISFILELIST --domain $AKAMAIDOMAIN" >> $LOGFILE
         /usr/local/bin/CCURequest.pl --user $USER --pwd $PASSWD --file $THISFILELIST --domain $AKAMAIDOMAIN > $THISCCUOUT
      fi
      RETCODE=$?

      # Try again if we get an error the first time.
      if [ $RETCODE -ne 0 ]; then
         echo "Trouble with Akamai expiration -- trying again..."
         sleep 1
         if [ "$SEND_STATUS_EMAILS" == "true" ]; then
            echo "/usr/local/bin/CCURequest.pl --user $USER --pwd $PASSWD --file $THISFILELIST --domain $AKAMAIDOMAIN --email $MAILLIST" >> $LOGFILE
            /usr/local/bin/CCURequest.pl --user $USER --pwd $PASSWD --file $THISFILELIST --domain $AKAMAIDOMAIN --email $MAILLIST > $THISCCUOUT
         else
            echo "/usr/local/bin/CCURequest.pl --user $USER --pwd $PASSWD --file $THISFILELIST --domain $AKAMAIDOMAIN" >> $LOGFILE
            /usr/local/bin/CCURequest.pl --user $USER --pwd $PASSWD --file $THISFILELIST --domain $AKAMAIDOMAIN > $THISCCUOUT
         fi
         RETCODE=$?
      fi

      if [ $RETCODE -ne 0 ]; then
         echo -e "Automated Akamai expiration FAILED!\n\nThe following files need to be manually submitted to Akamai for expiration.\n" > $NOTICE
         SUBJECT="ATTENTION: Files need to be manually expired on Akamai ($LOCATION) on `date`"
      else
         echo -e "The following files are being submitted to Akamai for expiration.\nYou should be receiving a confirmation e-mail shortly.\n" > $NOTICE
         REQID=$(cat $THISCCUOUT | grep -i ^sessionID | awk -F: '{print $2}')
         REQID=$(echo $REQID)
         SUBJECT="Files to expire on Akamai ($LOCATION) request ($REQID) on `date`"
         
         JobChecker

      fi

      if [ "$SEND_STATUS_EMAILS" == "true" ]; then
         cat $NOTICE $THISCCUOUT | mail -r Alfresco_$LOCATION -s "$SUBJECT" -a $THISFILELIST $MAILLIST
      fi
      cat $NOTICE $THISCCUOUT >> $LOGFILE

}

# --------------------------------------------------------------------------------------------------
DetermineAction() {

   if [ $FILESPRESENT -eq 0 ]; then
      if [ "$SEND_STATUS_EMAILS" == "true" ]; then
         echo "No files to expire on `date`" | mail -r Alfresco_$LOCATION -s "Files to expire on Akamai ($LOCATION) on `date`" -a $FILELIST $MAILLIST
      fi
      echo "No files to expire on `date`" >> $LOGFILE
   else
      SPLITFILELISTS=$(ls $FILELIST.[0-9][0-9] 2>/dev/null)
      [ "tim$SPLITFILELISTS" == "tim" ] && SPLITFILELISTS=$FILELIST
      for THISFILELIST in $SPLITFILELISTS
      do
         THISCCUOUT=$THISFILELIST.$(basename $CCUOUT)
         HandleAkamaiRequest
      done
   fi

}

# --------------------------------------------------------------------------------------------------
InitVar
GetFileList
DetermineAction

rm -f $TMPLIST $FILELIST $CCUOUT $NOTICE

exit $RETCODE
