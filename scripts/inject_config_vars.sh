#!/bin/bash +e

importerFile=$1

if [[ ! -f "$importerFile" ]]; then
    echo "[ERROR] $BASH_SOURCE (line:$LINENO): Unable to locate importer file: [$importerFile]"
    exit 1
fi

if (grep -q "::set-output" importer.sh); then 
    cat $importerFile | sed -r "s/echo ::set-output name=//g" | sed -r "s/::/=/g" |  grep "=" | grep -v '$GITHUB_ENV' > $importerFile.tmp
elif (grep -q "GITHUB_OUTPUT" importer.sh); then 
    cat $importerFile | grep '$GITHUB_OUTPUT' | sed "s/\"*\s*>>\s*\$GITHUB_OUTPUT//g" | sed "s/echo\s*\"*//g" > $importerFile.tmp
fi

while read eachLine; do
    keyname=$(echo $eachLine | cut -d"=" -f1 | sed -r "s/-/_/g")
    keyvalue=$(echo $eachLine | cut -d"=" -f1 --complement)
    echo "$keyname=$keyvalue" >> $GITHUB_ENV
done <$importerFile.tmp

rm -f $importerFile.tmp



