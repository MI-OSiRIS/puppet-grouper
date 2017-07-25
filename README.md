# puppet-grouper
A puppet module to manage Internet2 Grouper configuration and related Tomcat setup.

https://www.internet2.edu/products-services/trust-identity/grouper/
https://spaces.internet2.edu/display/Grouper/Grouper+Wiki+Home


1. [Overview](#overview)
2. [Class 'grouper'](#class-grouper)
3. [Resource 'grouper::instance'](#resource-grouperinstance)
4. [Usage Example](#usage-example)
5. [Dependencies](#dependencies)

## Overview

This module will manage grouper configurations but does not do everything that the grouperInstaller does.
You still will need to manually download and extract + patch the grouper archives.
You can setup grouperInstaller to do this non-interactively:
https://spaces.internet2.edu/display/Grouper/Grouper+installer+non+interactive+auto+apply+patches+example


This module does not initialize the grouper database.
Sample schema are here:  https://spaces.internet2.edu/display/Grouper/Grouper+Installer

You can run the grouperInstaller to take care of download, patching, database and then use this module to finish the configuration and manage the installation on an ongoing basis.

It may also be useful to copy your installation and manage different test configs with additional grouper::instance resources.

The module configures these items:
 - subject API adapter in sources.xml  (only a single LDAP adapter is supported)
 - grouper.properties wheel group autocreate config
 - log4j config to choose logfile location
 - grouper database configuration (does not initialize database)
 - Adds config for mysql/mariadb in my.cnf.d to set database default encoding to UTF-8 (database restart required)

Taken from steps at:
https://spaces.internet2.edu/display/COmanage/Grouper+Provisioning+Plugin
https://spaces.internet2.edu/download/attachments/93651000/TI.25.1-TIERGrouperDeploymentGuide.pdf

The module does not configure any kind of reverse proxy to the tomcat instance (default port 8080).

It also does not include any means to restrict the listen address of the tomcat instance.  For example you might have apache reverse-proxy to localhost:8080 and thus there is no need for tomcat to listen on any public IP.  If this is a requirement then consider setting manage_tomcat => false and/or tomcat_resource => absent in grouper::instance and configure tomcat with the puppet-tomcat module used internally by this module.  There are tomcat configurations in both the grouper class and grouper::instance resource to reference.

The above features may be added at some point.  Pull requests are welcome.

## Class: grouper

##### `manage_groovy`

Install groovy package.  The distribution packages with RHEL7 don't work with groovy grouper shell
TODO:  Also setup groovysh4grouper: https://github.com/wgthom/groovysh4grouper

##### `groovy_install`

'download' will grab binary archive from dl.bintray.com.  Requires example42-puppi module.
'package' will install with dist package from pre-existing repo

##### `groovy_version`

Which version to download if groovy_install is set to 'download'

##### `manage_tomcat`

Install and configure tomcat.  Requires puppetlabs-tomcat module.  RHEL7 only.  You can set tomcat_context = ensure on grouper::instance resources and they will configure contexts referencing the grouper web ui and web services.  You can also build .war files from the installation(s) managed in grouper::instance resources and place in /usr/share/tomcat/webapps.

##### `grouper_system_password`

If manage_tomcat is true configure grouper_system role and GrouperSystem user in tomcat-users.xml

## Resource: grouper::instance

Resource to define instance of grouper. Must first be installed by some means such as grouperInstaller
or by unpacking tarballs and initializing DB manually.

Params:

##### `grouper_topdir`

Top level directory where grouper.apiBinary-version, grouper.ui-version, etc live.
GROUPER_HOME and various paths will be constructed from topdir and version

##### `grouper_version`

Version installed under grouper_topdir, used in constructing GROUPER_HOME.
Default 2.3.0 (current release at this time)

##### `ui_host`

http(s)://hostname:port for grouper web ui and web API (path specified separately).
Default: 'fqdn:8080'

##### `ui_path`

Path component of URL for grouper web ui without / prefix.  Default 'grouper'.

##### `ws_path`

Path component of URL for grouper web services API without / prefix.  Default 'grouper-ws'.

##### `tomcat_context`

Values:  present, absent.  Default present.

Create tomcat server context referencing ws/ui paths in grouper_topdir. Only relevant if grouper::manage_tomcat was set true.  You may choose not to set this and instead build .war files for ws and ui to install in your tomcat webapps directory. See https://spaces.internet2.edu/display/Grouper/Grouper+UI+Installation

##### `environment_name`

Sets grouper.env.name to distinguish instances.  Defaults to name of resource.

##### `grouper_user`

What user tomcat runs as.  Also sets permissions on logdir.  Default 'tomcat'.

##### `grouper_group`

Group that tomcat runs as.  Also sets permissions on logdir. Default 'tomcat'.

##### `logdir`

Where grouper components log.  Sets appropriate setting in log4j.properties for each component.

##### `db_host`

Host to connect to for database access.  Default 'localhost'.

##### `db_name`

Name of grouper database.  Default 'grouper'.

##### `db_type`

Type of database.  Determines driver settings.  Currently 'mariadb' and 'mysql' supported.
Default 'mariadb'.

If using mariadb driver you will need to install mariadb jarfile, steps 4-8 here (other config steps are in this module):
https://spaces.internet2.edu/display/COmanage/Grouper+Provisioning+Plugin%3A+Post+Grouper+Install+Configuration

The Mysql driver that comes with grouper is likely adequate with either mysql or mariadb if you prefer to specify 'mysql' and take no further action.  However, we are using most current mariadb driver and thus have no experience to verify.

TODO:  Module should install correct jar if 'mariadb' is specified

##### `db_user`

Username to authenticate to database.

##### `db_password`

Password to authenticate to database.

##### `detect_utf8_problems`

Set configuration.detect.utf8.file.problems in grouper.properties. Should generally be false.

##### `log_driver_mismatch`

Should be false if using mariadb driver.  Default false.

##### `adapter_config`

A hash defining ldap subject id source adapter configuration.  Only 'ldap' type is supported.
More information on the meaning of these configuration items is available from the Grouper wiki:

https://spaces.internet2.edu/display/Grouper/Subject+API
https://spaces.internet2.edu/display/Grouper/LDAP+Subject+API+example

Example:

       $adapter_config = {
           'adapter_type'     => 'ldap',
           'adapter_id'       => 'name',
           'adapter_name'     => 'name',
           'provider_url'     => 'ldaps://ldap.example.org:636/dc=example,dc=org',
           'subject_id_type'  => 'eduPersonPrincipalName',
           'subject_ou'       => 'People',
           'name_type'        => 'cn',
           'description_type' => 'gecos'
       }

##### `default`

If this is true then a GROUPER_HOME environment variable will be set in /etc/profile.d/grouper-${name}.sh


## Usage example

1. You should setup the module and run puppet one time to configure database defaults.  
2. Restart MariaDB (or MySQL).  
3. Run grouperInstaller.jar.  The most up-to-date details at PDF linked below.
4. During installation be sure to put in your database info and initialize the database. 
5. Optional:  Install latest mariadb JDBC driver (required if you specify 'mariadb' driver to grouper::instance).  Instructions:  https://spaces.internet2.edu/display/COmanage/Grouper+Provisioning+Plugin%3A+Post+Grouper+Install+Configuration
6. Run puppet module again, it will detect that grouper is installed and complete configuration.

https://spaces.internet2.edu/download/attachments/93651000/TI.25.1-TIERGrouperDeploymentGuide.pdf


    class { 'grouper':
        grouper_system_password => $grouper_system_password
    }

    $adapter_config = {
        'adapter_type'     => 'ldap',
        'adapter_id'       => 'name',
        'adapter_name'     => 'name',
        'provider_url'     => 'ldaps://ldap.example.org:636/dc=example,dc=org',
        'subject_id_type'  => 'eduPersonPrincipalName',
        'subject_ou'       => 'People',
        'name_type'        => 'cn',
        'description_type' => 'gecos'
    }

    grouper::instance { 'production':
        adapter_config          => $adapter_config,
        grouper_topdir          => '/opt/grouper-2.3',
        grouper_version         => '2.3.0',
        ui_host                 => 'http://grouper.example.org',
        ui_path                 => 'grouper',
        ws_path                 => 'grouper-ws',
        grouper_user            => 'tomcat',
        grouper_group           => 'tomcat',
        detect_utf8_problems    => false,
        log_driver_mismatch     => false,
        db_password             => $db_password
    }


## Dependencies

If default => true then grouper::instance will create GROUPER_HOME env var.  Requires module https://forge.puppet.com/marcgascon/profile_d

If manage_tomcat => true then grouper and grouper::instance will manage tomcat configs.  Requires module https://forge.puppet.com/puppetlabs/tomcat
