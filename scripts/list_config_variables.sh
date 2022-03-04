#!/bin/bash +e

## Reading action's global setting
# if [[ ! -z $BASH_SOURCE ]]; then
#     ACTION_BASE_DIR=$(dirname $BASH_SOURCE)
#     echo find $ACTION_BASE_DIR/.. -type f 
#     source $(find $ACTION_BASE_DIR/.. -type f | grep general.ini)
# elif [[ $(find . -type f -name general.ini | wc -l) > 0 ]]; then
#     source $(find . -type f | grep general.ini)
# elif [[ $(find .. -type f -name general.ini | wc -l) > 0 ]]; then
#     source $(find .. -type f | grep general.ini)
# else
#     echo "[ERROR] $BASH_SOURCE (line:$LINENO): Unable to find and source general.ini"
#     exit 1
# fi


iniFile=$1

tempRunFile=run-$(date +%s).sh

if [[ ! -f "$iniFile" ]]; then
    echo "[ERROR] $BASH_SOURCE (line:$LINENO): Unable to locate INI file: [$iniFile]"
    exit 1
fi
source $iniFile
echo "source $iniFile" > $tempRunFile
# cat $iniFile | grep -v "^#" | grep "=" | awk -F'=' '{print "export "$1"="$2 }' > $tempRunFile
# source ./$tempRunFile

cat $iniFile | grep -v "^#" | grep "=" | awk -F'=' '{print "echo " $1"=${"$1"}" }' >> $tempRunFile
chmod 755 $tempRunFile

echo "[INFO] Listing variables..."
 ./$tempRunFile
# rm -f $tempRunFile
