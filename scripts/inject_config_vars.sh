#!/bin/bash +e

importerFile=$1

if [[ ! -f "$importerFile" ]]; then
    echo "[ERROR] $BASH_SOURCE (line:$LINENO): Unable to locate importer file: [$importerFile]"
    exit 1
fi

cat $importerFile | sed -r "s/echo ::set-output name=//g" | sed -r "s/::/=\"/g" | sed -r "s/$/\"/g" | grep "=\"" >> $GITHUB_ENV
cat $importerFile | sed -r "s/echo ::set-output name=//g" | sed -r "s/::/=\"/g" | sed -r "s/$/\"/g" | grep "=\"" > antz.tmp
