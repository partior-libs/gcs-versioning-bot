#!/bin/bash -e
## Prerequisite:
## - yq from https://github.com/mikefarah/yq
## - jq

## Reading action's global setting
if [[ ! -z $BASH_SOURCE ]]; then
    ACTION_BASE_DIR=$(dirname $BASH_SOURCE)
    source $(find $ACTION_BASE_DIR/.. -type f | grep importer-general.ini)
elif [[ $(find . -type f -name importer-general.ini | wc -l) > 0 ]]; then
    source $(find . -type f | grep importer-general.ini)
elif [[ $(find .. -type f -name importer-general.ini | wc -l) > 0 ]]; then
    source $(find .. -type f | grep importer-general.ini)
else
    echo "[ERROR] $BASH_SOURCE (line:$LINENO): Unable to find and source importer-general.ini"
    exit 1
fi

inputYaml=$(echo "$1" |xargs)
pathFilter=$(echo "$2" |xargs)
importerFilename=$(echo "$3" |xargs)
subPathFilterList=$(echo "$4" | xargs | sed 's/ //g')
skipIfNotFound=$(if [[ -z "$5" ]]; then echo false;else echo true;fi)

if [[ ! -f "$inputYaml" ]]; then
  echo "[ERROR] $BASH_SOURCE (line:$LINENO): Unable to locate yaml file: $inputYaml"
  exit 1
fi

echo "subPathFilterList: $subPathFilterList"

# Default to initial start if no key path
if [[ "$pathFilter" == "" ]]; then
    pathFilter='.'
fi

## Initialize the temporary files
if [[ "$importerFilename" == "" ]]; then
    importerFilename=$FINAL_CONVERSION_FILE
fi

function getKeys()
{
    local currentKey=$1
    local outputimporterFilename=$2
    local createIsolateKVFile=${3:-false}

    keyValueListFile=current-kv.tmp
    rm -f $keyValueListFile

    if [[ ! "$createIsolateKVFile" == "true" ]]; then
        createIsolateKVFile=false
    fi

    # Default to initial start if no key path
    if [[ "$currentKey" == "" ]]; then
        currentKey='.'
    fi

    if (cat $inputYaml | yq -e "$currentKey" -o props 2>/dev/null >/dev/null); then
        cat $inputYaml | yq -o props "$currentKey" | grep -v '^$' | grep -v '^#' | sed "s/ = /=/g" > $keyValueListFile
        if [[ "$createIsolateKVFile" == "true" ]]; then
            isolateKVFile=$(echo $currentKey | sed "s/^$pathFilter\.//g")
            cat $keyValueListFile >> $isolateKVFile.kv-tmp
        fi
        # Init vars
        regex='^.*\.[0-9]+$'
        prevKeyWithList="NIL_KEY"
        currentValueWithList="["

        # Convert to map array
        mapfile -t keyValueList < <(cat $keyValueListFile) 
        for element in "${keyValueList[@]}"
        do
            currentKey=$(echo $element | cut -d"=" -f1)
            currentValue=$(echo $element |cut -d"=" -f1 --complement)
 
            ## Group list value into parent key, otherwise treat as single unique key
            if [[ "$currentKey" =~ $regex ]]; then
                currentParentKey="${currentKey%.*}"
                # echo [DEBUG] currentParentKey:::$currentParentKey
                # echo [DEBUG] currentValueWithList:::$currentValueWithList
                # echo [DEBUG] prevKeyWithList:::$prevKeyWithList
                if [[ "$prevKeyWithList" == "NIL_KEY" ]]; then
                    currentValueWithList="$currentValueWithList \"$currentValue\""
                    prevKeyWithList=$currentParentKey
                elif [[ "$prevKeyWithList" == "$currentParentKey" ]]; then
                    currentValueWithList="$currentValueWithList ,\"$currentValue\""
                    prevKeyWithList=$currentParentKey
                else
                    currentValueWithList="$currentValueWithList ]"
                    tmpCurrentKey=${currentParentKey//\./\_}
                    # echo "echo ::set-output name=$tmpCurrentKey::\"$currentValueWithList\"" >> $outputimporterFilename
                    storeForGitHubEnv "$tmpCurrentKey" "$currentValueWithList" "$outputimporterFilename"
                    currentValueWithList="["
                    prevKeyWithList="NIL_KEY"
                fi

            else
                if [[ "$prevKeyWithList" != "NIL_KEY" ]]; then
                    currentValueWithList="$currentValueWithList ]"
                    tmpCurrentKey=${prevKeyWithList//\./\_}
                    # echo "echo ::set-output name=$tmpCurrentKey::\"$currentValueWithList\"" >> $outputimporterFilename
                    storeForGitHubEnv "$tmpCurrentKey" "$currentValueWithList" "$outputimporterFilename"
                    currentValueWithList="["
                    prevKeyWithList="NIL_KEY"
                fi
            fi
            currentKey=${currentKey//\./\_}
            # echo "echo ::set-output name=$currentKey::\"$currentValue\"" >> $outputimporterFilename
            storeForGitHubEnv "$currentKey" "$currentValue" "$outputimporterFilename"
            if [[ "$element" == "${keyValueList[-1]}" ]] && [[ ! "$currentValueWithList" == "[" ]] ; then
                currentValueWithList="$currentValueWithList ]"
                tmpCurrentKey=${prevKeyWithList//\./\_}
                # echo "echo ::set-output name=$tmpCurrentKey::\"$currentValueWithList\"" >> $outputimporterFilename
                storeForGitHubEnv "$tmpCurrentKey" "$currentValueWithList" "$outputimporterFilename"
                currentValueWithList="["
                prevKeyWithList="NIL_KEY"
            fi
        done
    else
        if ("${skipIfNotFound}"); then
            echo "[WARNING] $BASH_SOURCE (line:$LINENO): Failed querying path: $currentKey"
            if [[ ! -f "$outputimporterFilename" ]]; then
                echo "[ERROR] $BASH_SOURCE (line:$LINENO): Importer file [$outputimporterFilename] not present. At least one yaml file or query path must be valid. Check yaml and query path for invalid parameters"
                exit 1
            else
                echo "[INFO] Skipping.. importer file present: $outputimporterFilename"
                return 0
            fi

        else
            echo "[ERROR] $BASH_SOURCE (line:$LINENO): Failed querying path: $currentKey"
            rm -f $keyValueListFile
            exit 1
        fi
    fi
    rm -f $keyValueListFile
}

## Store format based on the character in the value
function storeForGitHubEnv() {
    local storeKey=$1
    local storeValue=$2
    local storeFile=$3
    local tmpStoreKey=""
    if [[ "$storeValue" =~ [\|\>\<\&\\] ]]; then
        echo "echo $storeKey=\"$storeValue\" >> \$GITHUB_OUTPUT" >> $storeFile
        ## Must normalized to underscore before pushing into github_env
        tmpStoreKey=$(echo $storeKey | sed "s/_/__/g" | sed "s/-/_/g")
        echo "echo $tmpStoreKey=\"$storeValue\" >> \$GITHUB_ENV" >> $storeFile
    else
        echo "echo $storeKey=$storeValue >> \$GITHUB_OUTPUT" >> $storeFile
        ## Must normalized to underscore before pushing into github_env
        tmpStoreKey=$(echo $storeKey | sed "s/_/__/g" | sed "s/-/_/g")
        echo "echo $tmpStoreKey=$storeValue >> \$GITHUB_ENV" >> $storeFile
    fi
}

## Check if the string is a flatten string
function isList (){
    local inputString="$1"
    local pattern='^[ a-zA-Z0-9\_\-]+_[0-9]+[\=\_]+'

    if [[ $inputString =~ $pattern ]]; then
        echo "true"
    else
        echo "false"
    fi
    return 0
}

## Check if string of input line number has duplicate at lower section
function isDuplicateList() {

    local foundLineNumber="$1"
    local inputFile="$2"
    local currentSearchLine=0
    local foundSearchListKey=""
    local foundSearchNonList=false

    while IFS= read -r eachSearchLine
    do
        currentSearchLine=$((1+$currentSearchLine))
        if [[ $currentSearchLine -eq $foundLineNumber ]]; then
            foundSearchListKey=$(echo $eachSearchLine | grep -oP "^[a-zA-Z0-9\_\-]+_(?=[0-9]+(_|$)+)")
            # echo [DEBUG] foundSearchListKey=$foundSearchListKey
        elif [[ $currentSearchLine -gt $foundLineNumber ]]; then
            if [[ $eachSearchLine =~ $foundSearchListKey ]]; then
                # echo [DEBUG] matched. foundSearchNonList=$foundSearchNonList
                ## Still within the same list...Skip
                if [[ $foundSearchNonList == "true" ]]; then
                    echo "true"
                    foundSearchNonList=false
                    return 0
                fi
            else
                ## Found non list - mark as new section, so begin trimming after set to true
                foundSearchNonList=true
                # echo [DEBUG] NOT matched. foundSearchNonList=$foundSearchNonList   
            fi
        fi
    done < "$inputFile"
    echo "false"
    return 0
}

## Remove flatten list keys in importer files
function removeDuplicateListKeys() {
    local inputFile=$1
    local currentLine=0
    local foundList=false

    local inputCacheFile=$inputFile.cache

    ## Add newline to the end of the file - to prevent random issue
    echo >> $inputFile
    rm -f $inputCacheFile
    ## Create filtered cache for faster processing
    while read -r eachLine
    do
        if [[ $eachLine =~ GITHUB_OUTPUT ]]; then
            echo $eachLine | sed 's/_/__/g' | sed 's/-/_/g' >> $inputCacheFile
        else
            echo $eachLine >> $inputCacheFile
        fi
    done < "$inputFile"
    cat $inputCacheFile | cut -d" " -f2 | cut -d"=" -f1 > $inputCacheFile.2
    mv $inputCacheFile.2 $inputCacheFile

    ## Start processing each line
    while read -r eachLine
    do
        currentLine=$((1+$currentLine))
        # echo "[INFO] Checking duplicate for line [$currentLine]"
        if [[ $(isList "$eachLine") == "true" ]]; then
            echo "[INFO] Checking duplicate for [$eachLine]"
            ## if found for the first time
            # isDuplicateList "$currentLine" "$inputCacheFile"
            isDupListFlag=$(isDuplicateList "$currentLine" "$inputCacheFile")
            if [[ "$isDupListFlag" == "false" ]]; then 
                ## Store if no duplicate
                echo "$eachLine" >> $inputFile.2
            fi
        else
            if [[ ! -z "$eachLine" ]]; then
                ## Store if others
                echo "$eachLine" >> $inputFile.2
            fi
        fi

    done < "$inputFile"

    mv $inputFile.2 $inputFile
}

echo [INFO] Reading $inputYaml...
echo [INFO] Path filter: [$pathFilter]
echo [INFO] Target imported file: [$importerFilename]
echo [INFO] Sub default query path: [$subPathFilterList]
export keyValueListFile=list.tmp
## Process the sub keys
if [[ ! "$subPathFilterList" == "" ]]; then
    IFS=', ' read -r -a subPathFilterArray <<< "$subPathFilterList"
    for eachSubPath in "${subPathFilterArray[@]}"
    do
        ## Store into a file for subsequent run
        finalSubKeyChild=$(echo $eachSubPath | sed "s/$pathFilter\.//g")
    echo $finalSubKeyChild >> $SUB_DEFAULT_KEY_LIST_FILE
        getKeys "$eachSubPath" "$importerFilename" "true"
    done
fi

## Process the primary keys
# keyValueListFile=kv.tmp
# rm -f $keyValueListFile
getKeys "$pathFilter" "$importerFilename" "false"

## Escape special chars
sed -i "s/\\\\\\\\\\$/\\\\\\\\\\\\$/g" "$importerFilename"

## Removing duplicate KVs which are flat for list (ie: some_key__0)
if ("${skipIfNotFound}"); then
    echo [INFO] Removing duplicate list keys...
    removeDuplicateListKeys "$importerFilename"
fi

echo [INFO] Completed...

if [[ -f "$importerFilename" ]]; then
    chmod 755 $importerFilename
fi
