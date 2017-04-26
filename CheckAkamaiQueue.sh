#!/bin/bash

USER='alfresco_automation@papajohns.com'
PASSWD='8rJBcfP0dcvLabsFyA1W4Expiring' 
TIMEOUTVAL=30

cd /tmp

wget --user="$USER" --password="$PASSWD" --timeout=$TIMEOUTVAL https://api.ccu.akamai.com/ccu/v2/queues/default

cat /tmp/default |sed 's/[{,}]/\\\n/g'  |sed 's/\\//g' | sed 's/"//g' | sed 's/^\ //g'

rm /tmp/default

echo 

exit
