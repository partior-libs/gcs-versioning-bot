helm_package__enabled=true
ARTIFACT_LAST_DEV_VERSION_FILE=artifact_last_dev_version.txt
ARTIFACT_LAST_RC_VERSION_FILE=artifact_last_rc_version.txt
ARTIFACT_LAST_REL_VERSION_FILE=artifact_last_release_version.txt
ARTIFACT_LAST_BASE_VERSION_FILE=artifact_last_base_version.txt
ARTIFACT_UPDATED_REL_VERSION_FILE=artifact_updated_release_version.txt
ARTIFACT_NEXT_VERSION_FILE=artifact_next_version.txt
MAJOR_POSITION=0
MINOR_POSITION=1
PATCH_POSITION=2
MAJOR_SCOPE=MAJOR
MINOR_SCOPE=MINOR
PATCH_SCOPE=PATCH
RC_SCOPE=RC
REL_SCOPE=RELEASE
DEV_SCOPE=DEV
BUILD_SCOPE=BUILD
REPLACEMENT_SCOPE=REPLACE
MOCK_DEV_VERSION_KEYNAME=DEV_VERSION
MOCK_REL_VERSION_KEYNAME=REL_VERSION
INCREMENT_CORE_VERSION=INCREMENT_CORE
SKIP_CORE_VERSION=SKIP_INCREMENT_CORE
FLAG_FILE_IS_INITIAL_VERSION=is_initial_version.tmp
VBOT_NIL=NIL
TRUNK_CORE_NEED_INCREMENT_FILE=trunk-version-flag.tmp
CORE_VERSION_UPDATED_FILE=core.updated
ARTIFACT_BASE_NAME=goquorum-node
VERSIONING_BOT_ENABLED=true
MAJOR_V_RULES_ENABLED=true
MAJOR_V_RULE_BRANCH_ENABLED=true
MAJOR_V_CONFIG_BRANCHES=release,feature,main
MAJOR_V_RULE_LABEL_ENABLED=false
MAJOR_V_CONFIG_LABELS=MAJOR-VERSION
MAJOR_V_RULE_TAG_ENABLED=false
MAJOR_V_CONFIG_TAGS=MAJOR-VERSION
MAJOR_V_RULE_MSGTAG_ENABLED=false
MAJOR_V_CONFIG_MSGTAGS=MAJOR-VERSION
MAJOR_V_RULE_VFILE_ENABLED=true
MAJOR_V_CONFIG_VFILE_NAME=./app-version.cfg
MAJOR_V_CONFIG_VFILE_KEY=MAJOR-VERSION
MINOR_V_RULES_ENABLED=true
MINOR_V_RULE_BRANCH_ENABLED=true
MINOR_V_CONFIG_BRANCHES=release,feature,main
MINOR_V_RULE_LABEL_ENABLED=false
MINOR_V_CONFIG_LABELS=MINOR-VERSION
MINOR_V_RULE_TAG_ENABLED=false
MINOR_V_CONFIG_TAGS=MINOR-VERSION
MINOR_V_RULE_MSGTAG_ENABLED=false
MINOR_V_CONFIG_MSGTAGS=MINOR-VERSION
MINOR_V_RULE_VFILE_ENABLED=true
MINOR_V_CONFIG_VFILE_NAME=./app-version.cfg
MINOR_V_CONFIG_VFILE_KEY=MINOR-VERSION
PATCH_V_RULES_ENABLED=true
PATCH_V_RULE_BRANCH_ENABLED=true
PATCH_V_CONFIG_BRANCHES=main
PATCH_V_RULE_LABEL_ENABLED=false
PATCH_V_CONFIG_LABELS=PATCH-VERSION
PATCH_V_RULE_TAG_ENABLED=false
PATCH_V_CONFIG_TAGS=PATCH-VERSION
PATCH_V_RULE_MSGTAG_ENABLED=false
PATCH_V_CONFIG_MSGTAGS=PATCH-VERSION
PATCH_V_RULE_VFILE_ENABLED=false
PATCH_V_CONFIG_VFILE_NAME=./app-version.cfg
PATCH_V_CONFIG_VFILE_KEY=PATCH-VERSION
RC_V_RULES_ENABLED=true
RC_V_IDENTIFIER=rc
RC_V_RULE_BRANCH_ENABLED=true
RC_V_CONFIG_BRANCHES=release
RC_V_RULE_TAG_ENABLED=false
RC_V_CONFIG_TAGS=RC-VERSION
RC_V_RULE_VFILE_ENABLED=false
RC_V_CONFIG_VFILE_NAME=./app-version.cfg
RC_V_CONFIG_VFILE_KEY=RC-VERSION
DEV_V_RULES_ENABLED=true
DEV_V_IDENTIFIER=dev
DEV_V_RULE_BRANCH_ENABLED=true
DEV_V_CONFIG_BRANCHES=develop,feature
DEV_V_RULE_TAG_ENABLED=false
DEV_V_CONFIG_TAGS=DEV-VERSION
DEV_V_RULE_VFILE_ENABLED=false
DEV_V_CONFIG_VFILE_NAME=./app-version.cfg
DEV_V_CONFIG_VFILE_KEY=DEV-VERSION
BUILD_V_RULES_ENABLED=false
BUILD_V_IDENTIFIER=bld
BUILD_V_RULE_BRANCH_ENABLED=true
BUILD_V_CONFIG_BRANCHES=develop,feature
REPLACE_V_RULES_ENABLED=true
REPLACE_V_RULE_FILETOKEN_ENABLED=true
REPLACE_V_CONFIG_FILETOKEN_FILE=helm/goquorum-node/Chart.yaml
REPLACE_V_CONFIG_FILETOKEN_NAME=@@VERSION_BOT_TOKEN@@
REPLACE_V_RULE_MAVEN_ENABLED=false
REPLACE_V_CONFIG_MAVEN_POMFILE=pom.xml
REPLACE_V_RULE_YAMLPATH_ENABLED=false
REPLACE_V_CONFIG_YAMLPATH_FILE=helm/goquorum-node/Chart.yaml
REPLACE_V_CONFIG_YAMLPATH_QUERYPATH=.version
REBASE_V_RULES_ENABLED=true
REBASE_V_IDENTIFIER=hf
REBASE_V_VALIDATION_FAIL_NONEXISTENT_ENABLED=true
REBASE_V_RULE_BRANCH_ENABLED=true
REBASE_V_CONFIG_BRANCHES=hotfix-base,rebase
BUILD_GH_RUN_NUMBER=103
BUILD_GH_RUN_ATTEMPT=1
BUILD_GH_BRANCH_NAME=feature
MAJOR_GH_CURRENT_BRANCH=$BUILD_GH_BRANCH_NAME
MINOR_GH_CURRENT_BRANCH=$BUILD_GH_BRANCH_NAME
PATCH_GH_CURRENT_BRANCH=$BUILD_GH_BRANCH_NAME
RC_GH_CURRENT_BRANCH=$BUILD_GH_BRANCH_NAME
DEV_GH_CURRENT_BRANCH=$BUILD_GH_BRANCH_NAME
DEV_GH_CURRENT_BRANCH=$BUILD_GH_BRANCH_NAME