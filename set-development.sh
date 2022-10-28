#!/bin/bash

kohaplugindir="$(grep -Po '(?<=<pluginsdir>).*?(?=</pluginsdir>)' $KOHA_CONF)"
kohadir="$(grep -Po '(?<=<intranetdir>).*?(?=</intranetdir>)' $KOHA_CONF)"

rm -r $kohaplugindir/Koha/Plugin/Fi/KohaSuomi/OverdueTool
rm $kohaplugindir/Koha/Plugin/Fi/KohaSuomi/OverdueTool.pm

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

ln -s "$SCRIPT_DIR/Koha/Plugin/Fi/KohaSuomi/OverdueTool" $kohaplugindir/Koha/Plugin/Fi/KohaSuomi/OverdueTool
ln -s "$SCRIPT_DIR/Koha/Plugin/Fi/KohaSuomi/OverdueTool.pm" $kohaplugindir/Koha/Plugin/Fi/KohaSuomi/OverdueTool.pm
<<<<<<< Updated upstream

perl $kohadir/misc/devel/install_plugins.pl
=======
>>>>>>> Stashed changes

perl $kohadir/misc/devel/install_plugins.pl