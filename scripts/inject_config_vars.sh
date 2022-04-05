#!/bin/bash +e

importerFile=$1

if [[ ! -f "$importerFile" ]]; then
    echo "[ERROR] $BASH_SOURCE (line:$LINENO): Unable to locate importer file: [$importerFile]"
    exit 1
fi

cat $importerFile | sed -r "s/echo ::set-output name=//g" | sed -r "s/::/=/g" |  grep "=" | grep -v '$GITHUB_ENV' > $importerFile.tmp

while read eachLine; do
    keyname=$(echo $eachLine | cut -d"=" -f1 | sed -r "s/-/_/g")
    keyvalue=$(echo $eachLine | cut -d"=" -f1 --complement)
    echo "$keyname=$keyvalue" >> $GITHUB_ENV
done <$importerFile.tmp

rm -f $importerFile.tmp



