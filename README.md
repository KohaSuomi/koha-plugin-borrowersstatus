# Koha-Suomi plugin BorrowersStatus
This is the plugin description
# Downloading
From the release page you can download the latest \*.kpz file
# Installing
Koha's Plugin System allows for you to add additional tools and reports to Koha that are specific to your library. Plugins are installed by uploading KPZ ( Koha Plugin Zip ) packages. A KPZ file is just a zip file containing the perl files, template files, and any other files necessary to make the plugin work.
The plugin system needs to be turned on by a system administrator.
To set up the Koha plugin system you must first make some changes to your install.
    Change <enable_plugins>0<enable_plugins> to <enable_plugins>1</enable_plugins> in your koha-conf.xml file
    Confirm that the path to <pluginsdir> exists, is correct, and is writable by the web server
    Remember to allow access to plugin directory from Apache
    <Directory <pluginsdir>>
        Options Indexes FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>
    Restart your webserver
Once set up is complete you will need to alter your UseKohaPlugins system preference. On the Tools page you will see the Tools Plugins and on the Reports page you will see the Reports Plugins.
# Logging

Add settings to log4perl.conf and create the file to desired `<path>`

```
log4perl.logger.auth = ERROR, AUTH
log4perl.appender.AUTH=Log::Log4perl::Appender::File
log4perl.appender.AUTH.filename=<path>/auth-failures.log
log4perl.appender.AUTH.mode=append
log4perl.appender.AUTH.create_at_logtime=true
log4perl.appender.AUTH.layout=PatternLayout
log4perl.appender.AUTH.layout.ConversionPattern=[%d] [%p] %m
log4perl.appender.AUTH.utf8=1
log4perl.appender.AUTH.umask=0007
log4perl.appender.AUTH.owner=www-data
log4perl.appender.AUTH.group=www-data
```
