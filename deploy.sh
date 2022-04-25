#!/bin/bash
PM_FILE="Koha/Plugin/Fi/KohaSuomi/BorrowersStatus.pm"
VERSION=`grep -oE "\-?[0-9]+\.[0-9]+\.[0-9]" $PM_FILE | head -1`
RELEASE_FILE="koha-plugin-borrowers-status-v${VERSION}.kpz"
rm 
echo "Building release package ${RELEASE_FILE}"
zip -r $RELEASE_FILE ./Koha
