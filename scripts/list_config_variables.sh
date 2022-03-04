#!/bin/bash +e

iniFile=$1

tempRunFile=run-$(date +%s).sh

if [[ ! -f "$iniFile" ]]; then
    echo "[ERROR] $BASH_SOURCE (line:$LINENO): Unable to locate INI file: [$iniFile]"
    exit 1
fi
source $iniFile
echo "source $iniFile" > $tempRunFile

cat $iniFile | grep -v "^#" | grep "=" | awk -F'=' '{print "echo " $1"=${"$1"}" }' >> $tempRunFile
chmod 755 $tempRunFile

echo "[INFO] Listing variables..."
 ./$tempRunFile
 echo "[INFO] Listing env variables..."
 set
rm -f $tempRunFile