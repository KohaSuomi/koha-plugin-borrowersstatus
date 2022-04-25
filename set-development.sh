#!/bin/bash
kohaplugindir="$(grep -Po '(?<=<pluginsdir>).*?(?=</pluginsdir>)' $KOHA_CONF)"
rm -r $kohaplugindir/Koha/Plugin/Fi/KohaSuomi/BorrowersStatus
rm $kohaplugindir/Koha/Plugin/Fi/KohaSuomi/BorrowersStatus.pm
ln -s "/home/lmstrand/borrowerstatus_plugin//koha-plugin-borrowers-status/Koha/Plugin/Fi/KohaSuomi/BorrowersStatus" $kohaplugindir/Koha/Plugin/Fi/KohaSuomi/BorrowersStatus
ln -s "/home/lmstrand/borrowerstatus_plugin//koha-plugin-borrowers-status/Koha/Plugin/Fi/KohaSuomi/BorrowersStatus.pm" $kohaplugindir/Koha/Plugin/Fi/KohaSuomi/BorrowersStatus.pm
DATABASE=`xmlstarlet sel -t -v 'yazgfs/config/database' $KOHA_CONF`
HOSTNAME=`xmlstarlet sel -t -v 'yazgfs/config/hostname' $KOHA_CONF`
PORT=`xmlstarlet sel -t -v 'yazgfs/config/port' $KOHA_CONF`
USER=`xmlstarlet sel -t -v 'yazgfs/config/user' $KOHA_CONF`
PASS=`xmlstarlet sel -t -v 'yazgfs/config/pass' $KOHA_CONF`
mysql --user=$USER --password="$PASS" --port=$PORT --host=$HOST $DATABASE << END
DELETE FROM plugin_data where plugin_class = 'Koha::Plugin::Fi::KohaSuomi::BorrowersStatus';
INSERT INTO plugin_data (plugin_class,plugin_key,plugin_value) VALUES ('Koha::Plugin::Fi::KohaSuomi::BorrowersStatus','__INSTALLED__','1');
END
