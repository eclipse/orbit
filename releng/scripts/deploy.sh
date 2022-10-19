#!/bin/bash

set -x

# The default seems to be 0022
# We need user (genie.orbit) and group (tools.orbit) to match
umask 0002

contentFile=${repoDir}/content.xml

# Ensure repository generated by maven has proper permissions
# Remove this line when Hudson has global umask of 0002
chmod -R g+w ${repoDir}

unzip -d ${repoDir} ${repoDir}/content.jar

set -e
for f in `find . -name ip_log.xml`; do

  # Check if IP Information is from IPZilla or ClearlyDefined
  set +e
  test_ipzilla=`xmllint --xpath '/ip_log/project/legal/ipzilla/@bug_id' ${f}`
  set -e
  if [ -n "${test_ipzilla}" ]; then
    bug_id_xpath='/ip_log/project/legal/ipzilla/@bug_id'
  else
    bug_id_xpath='/ip_log/project/legal/clearlydefined/@url'
  fi

  xsltproc \
    --stringparam id \
    `xmllint --xpath '/ip_log/project/@id' ${f} | cut -d'"' -f2` \
    --stringparam version \
    `xmllint --xpath '/ip_log/project/@version' ${f} | cut -d'"' -f2` \
    --stringparam name \
    "`xmllint --xpath '/ip_log/project/contact/name/text()' ${f}`" \
    --stringparam email \
    `xmllint --xpath '/ip_log/project/contact/email/text()' ${f}` \
    --stringparam bug_id \
    `xmllint --xpath "${bug_id_xpath}" ${f} | head -1 | cut -d'"' -f2` \
    ${scriptDir}/add_iplog.xsl ${contentFile} > ${repoDir}/new-content.xml

  mv ${repoDir}/new-content.xml ${contentFile}
done
set +e

xsltproc ${scriptDir}/props_size.xsl ${contentFile} > ${repoDir}/new-content.xml
mv ${repoDir}/new-content.xml ${contentFile}

zip -j ${repoDir}/content.jar ${contentFile}
rm ${contentFile}

export BUILD_TIME=$(echo $(basename $(find releng/repository -name "orbit-*-repo.zip")) | grep -o "[0-9]*")
NEW_BUILD_LABEL=${BUILD_LABEL}${BUILD_TIME}

# Promote orbit-recipes build to download location
ORBIT_DOWNLOAD_LOC=/home/data/httpd/download.eclipse.org/tools/orbit/downloads
echo "1" > files.count
ssh genie.orbit@projects-storage.eclipse.org mkdir -p ${ORBIT_DOWNLOAD_LOC}/drops/${NEW_BUILD_LABEL}
scp -r ${repoDir} files.count genie.orbit@projects-storage.eclipse.org:${ORBIT_DOWNLOAD_LOC}/drops/${NEW_BUILD_LABEL}

# Copy the aggregated repository archive
buildRepoZipPath=`find releng/repository-all/target/ -name "orbit-buildrepo-*.zip"`
chmod g+w ${buildRepoZipPath}
buildRepoZipName=`basename ${buildRepoZipPath}`
buildRepoZipDir=`dirname ${buildRepoZipPath}`
zipFileSize='('`ls -sh ${buildRepoZipPath} | cut -d' ' -f1`')'
mkdir checksum
pushd releng/repository-all/target/
md5sum ${buildRepoZipName} > ../../../checksum/${buildRepoZipName}.md5
sha1sum ${buildRepoZipName} > ../../../checksum/${buildRepoZipName}.sha1
popd
scp -r ${buildRepoZipPath} checksum genie.orbit@projects-storage.eclipse.org:${ORBIT_DOWNLOAD_LOC}/drops/${NEW_BUILD_LABEL}

# Copy Repository Report
chmod -R g+w releng/repository-report/target/reporeports/
scp -r releng/repository-report/target/reporeports/ genie.orbit@projects-storage.eclipse.org:${ORBIT_DOWNLOAD_LOC}/drops/${NEW_BUILD_LABEL}

# Generate IPLog HTML Page
mkdir -p bug506001/${NEW_BUILD_LABEL}
pushd bug506001
curl -L -o ${NEW_BUILD_LABEL}/content.jar https://download.eclipse.org/tools/orbit/downloads/drops/${NEW_BUILD_LABEL}/repository/content.jar
unzip -d ${NEW_BUILD_LABEL} ${NEW_BUILD_LABEL}/content.jar
popd
scp -r bug506001 genie.orbit@projects-storage.eclipse.org:${ORBIT_DOWNLOAD_LOC}/../bug506001

### This line goes to www.eclipse.org and runs a php script to generate the index file. That php script relies on stuff uploaded to the bug506001 location above
### XXX: The iplog.php could just use repoPath instead of faking the location in like this.
curl -v -o index.html -d @- "https://www.eclipse.org/orbit/scripts/iplog.php?repoPath=tools/orbit/downloads/drops/${NEW_BUILD_LABEL}/repository&buildURL=${BUILD_URL}&zipFileSize=${zipFileSize}" << EOF
<?compositeArtifactRepository version='1.0.0'?>
<repository name="fake xml file, just enough to run iplog.php">
<child location="../../${NEW_BUILD_LABEL}/repository"/>
</repository>
EOF
## Until the index.html generation can be fixed, don't copy it to normal place
scp index.html genie.orbit@projects-storage.eclipse.org:${ORBIT_DOWNLOAD_LOC}/drops/${NEW_BUILD_LABEL}/index-broken.html

ssh genie.orbit@projects-storage.eclipse.org rm -r ${ORBIT_DOWNLOAD_LOC}/../bug506001

. ${scriptDir}/composite-functions.sh

# Update latest-X repository with this build
if [ "${UPDATE_LATEST_X}" = "true" ]; then
  upload_composite_repo_files ${NEW_BUILD_LABEL} ../drops/${NEW_BUILD_LABEL}/repository latest-${BUILD_LABEL}
fi

# Update static release repo with this build (this is normally done on all non-I builds)
if [ -n "${SIMREL_NAME}" ]; then
  upload_composite_repo_files ${NEW_BUILD_LABEL} ../drops/${NEW_BUILD_LABEL}/repository ${SIMREL_NAME}
fi

if [ -n "${DESCRIPTION}" ]; then
  scp genie.orbit@projects-storage.eclipse.org:${ORBIT_DOWNLOAD_LOC}/notes.php notes.php
  sed -i '/Intentionally not php-closed, since included from PHP section/ i $notes["'${NEW_BUILD_LABEL}'"]="'"${DESCRIPTION}"'";' notes.php
  scp notes.php genie.orbit@projects-storage.eclipse.org:${ORBIT_DOWNLOAD_LOC}/notes.php
fi


set +x
echo "####################################################################################################"
echo "####################################################################################################"
echo "####################################################################################################"
echo "### Build Page : https://download.eclipse.org/tools/orbit/downloads/drops/${NEW_BUILD_LABEL}     ###"
echo "### p2 Repository : https://download.eclipse.org/tools/orbit/$downloads/drops/${NEW_BUILD_LABEL} ###"
echo "####################################################################################################"
echo "####################################################################################################"
echo "####################################################################################################"
set -x
