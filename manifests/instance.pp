#
# Resource to define instance of grouper.
# Must first be installed by some means such as grouperInstaller
# or by unpacking tarballs and initializing DB manually
#
#  Params:
#
#  grouper_topdir
#       Top level directory where grouper.apiBinary-<version>, grouper.ui-<version>, etc live.
#        GROUPER_HOME and various paths will be constructed from topdir and version
#
#    grouper_version
#        Version installed under grouper_topdir, used in constructing GROUPER_HOME.
#        Default 2.3.0 (current release at this time)
#
#    ui_host
#        http(s)://hostname:port for grouper web ui and web API (path specified separately).
#        Default fqdn:8080
#
#    ui_path
#        Path component of URL for grouper web ui without / prefix.  Default 'grouper'.
#
#    ws_path
#        Path component of URL for grouper web services API without / prefix.  Default 'grouper-ws'.
#
#    tomcat_context
#        Values:  present, absent.  Default present.
#        Create tomcat server context referencing ws/ui paths in grouper_topdir.
#        Only relevant if grouper::manage_tomcat was set true.  You may choose not to set this
#        and instead build .war files for ws and ui to install in your tomcat webapps directory.
#        See https://spaces.internet2.edu/display/Grouper/Grouper+UI+Installation
#
#    environment_name
#        Sets grouper.env.name to distinguish instances.  Defaults to name of resource.
#
#    grouper_user
#        What user tomcat runs as.  Also sets permissions on logdir.  Default 'tomcat'.
#
#    grouper_group
#        Group that tomcat runs as.  Also sets permissions on logdir. Default 'tomcat'.
#
#    logdir
#        Where grouper components log.  Sets appropriate setting in log4j.properties for each component.
#
#    db_host
#        Host to connect to for database access.  Default 'localhost'.
#
#    db_name
#        Name of grouper database.  Default 'grouper'.
#
#    db_type
#        Type of database.  Determines driver settings.  Currently 'mariadb' and 'mysql' supported.
#        Default 'mariadb'.  You will need to install mariadb jarfile, steps 4-8 here (other config steps are in this module):
#        https://spaces.internet2.edu/display/COmanage/Grouper+Provisioning+Plugin%3A+Post+Grouper+Install+Configuration
#        (TODO:  Module should install it)
#
#    db_user
#        Username to authenticate to database.
#
#    db_password
#        Password to authenticate to database.
#
#    detect_utf8_problems
#        Set configuration.detect.utf8.file.problems in grouper.properties.
#        Should generally be false.
#
#    log_driver_mismatch
#        Should be false if using mariadb driver.  Default false.
#
#    adapter_config
#        A hash defining ldap subject id source adapter configuration.  Only 'ldap' type is supported.
#        More information on the meaning of these configuration items is available from the Grouper wiki:
#        https://spaces.internet2.edu/display/Grouper/Subject+API
#        https://spaces.internet2.edu/display/Grouper/LDAP+Subject+API+example
#
#        Example:
#
#        $adapter_config = {
#            'adapter_type'     => 'ldap',
#            'adapter_id'       => 'name',
#            'adapter_name'     => 'name',
#            'provider_url'     => 'ldaps://ldap.example.org:636/dc=example,dc=org',
#            'subject_id_type'  => 'eduPersonPrincipalName',
#            'subject_ou'       => 'People',
#            'name_type'        => 'cn',
#            'description_type' => 'gecos'
#        }
#
#    default
#        If this is true then a GROUPER_HOME environment variable will be set in /etc/profile.d/grouper-${name}.sh

define grouper::instance (
    $grouper_topdir        = '/opt/grouper',
    $grouper_version       = '2.3.0',
    $ui_host               = '${fqdn}:8080',
    $ws_path               = 'grouper-ws',
    $ui_path               = 'grouper',
    $tomcat_context        = 'present',
    $environment_name      = "${name}",
    $grouper_user          = 'tomcat',
    $grouper_group         = 'tomcat',
    $logdir                = '/var/log/grouper',
    $db_host               = 'localhost',
    $db_name               = 'grouper',
    $db_type               = 'mariadb',
    $db_user               = 'grouper',
    $db_password           = undef,
    $detect_utf8_problems  = false,
    $log_driver_mismatch   = false,
    $adapter_config        = undef,
    $psp_config            = undef,
    $default               = true
) {

    $grouper_home = "${grouper_topdir}/grouper.apiBinary-${grouper_version}"
    $ui_url = "${ui_host}/${ui_path}"

    exec { "grouper-installed-${name}":
            command => '/bin/false',
            unless => "/bin/test -e $grouper_home"
    }

    file { "$logdir":
        ensure => directory,
        owner  => $grouper_user,
        group  => $grouper_group
    }

    if $::grouper::manage_tomcat {
        tomcat::config::server::context { "grouper-ws-context-${name}":
            context_ensure => $tomcat_context,
            doc_base => "${grouper_topdir}/grouper.ws-${grouper_version}/grouper-ws/build/dist/grouper-ws",
            additional_attributes => {
                'path' => "/${ws_path}",
                'reloadable' => 'false',
                'mapperContextRootRedirectEnabled' => 'true',
                'mapperDirectoryRedirectEnabled' => 'true'
            }
        }
        tomcat::config::server::context { "grouper-ui-context-${name}":
            context_ensure => $tomcat_context,
            doc_base => "${grouper_topdir}/grouper.ui-${grouper_version}/dist/grouper",
            additional_attributes => {
                'path' => "/${ui_path}",
                'reloadable' => 'false',
                'mapperContextRootRedirectEnabled' => 'true',
                'mapperDirectoryRedirectEnabled' => 'true'
            }
        }

    }

    case $db_type {
        'mariadb','mysql': {
            $hibernate_connection_url = "jdbc:mysql://${db_host}:3306/${db_name}?autoReconnect=true&CharSet=utf8&useUnicode=true&characterEncoding=utf8"
            $hibernate_driver_dialect  = 'org.hibernate.dialect.MySQL5Dialect'
            if $db_type == 'mariadb' {
                $hibernate_driver_class = 'org.mariadb.jdbc.Driver'
            } else {
                $hibernate_driver_class = 'org.mysql.jdbc.Driver'
            }
        }
    }

    $grouper_properties = [
        "grouper.apiBinary-${grouper_version}/conf",
        "grouper.ui-${grouper_version}/dist/grouper/WEB-INF/classes",
        "grouper.ws-${grouper_version}/grouper-ws-scim/targetBuiltin/grouper-ws-scim/WEB-INF/classes",
        "grouper.ws-${grouper_version}/grouper-ws/build/dist/grouper-ws/WEB-INF/classes"
    ]

     $grouper_propfiles_c = [ 'grouper.properties','log4j.properties', 'grouper.hibernate.properties' ]

    if $adapter_config {
        $grouper_propfiles_a = 'sources.xml'
    }

    if $psp_config {
        $grouper_propfiles_p = 'grouper-loader.properties'
    }

    $grouper_propfiles = concat($grouper_propfiles_c,$grouper_propfiles_a,$grouper_propfiles_p)

    $grouper_properties.each | $propdir | {
        $grouper_propfiles.each | $propfile | {
            file { "${grouper_topdir}/${propdir}/${propfile}":
                content => template("grouper/${propfile}.erb"),
                owner => $grouper_user,
                group => $grouper_group,
                require => Exec["grouper-installed-${name}"],
                tag    => [ 'grouper-propfile' ]
            }
        }


        # There were too many attributes to insert for this to be a very appealing approach
        # it might be nice to preserve the distributed sources.xml - the file we copy in place
        # was copied from the original in full and has our ldap source inserted
        # augeas{ "${name}-adapter-config-${propdir}":
                #   incl => "${grouper_topdir}/${propdir}/sources.xml",
                #   lens => "Xml.lns",
                #   context => "/files/${grouper_topdir}/${propdir}/sources.xml/sources",
                #   changes => []
        # }

    }

    if $default {
        # resources defined here will have a (desired) side effect of causing an error
        # if multiple default grouper instances are defined

        include ::profile_d
        profile_d::script { "grouper.sh":
            content => "export GROUPER_HOME=$grouper_home"
        }
        if $::service_provider == 'systemd' {

            file { '/etc/systemd/system/grouper-loader.service':
                content => file("grouper/grouper-loader.service"),
                notify => Service['grouper-loader']
            } ->

            file { '/etc/systemd/system/grouper-loader.service.d':
                ensure => directory
            } ->

            file { '/etc/systemd/system/grouper-loader.service.d/local.conf':
                content => "[Service]\nEnvironment=GROUPER_HOME=$grouper_home"
            } ~>

             exec { 'grouper-loader-restart-systemd':
                command => '/bin/systemctl daemon-reload',
                refreshonly => true
            } ~>

            service { 'grouper-loader':
                ensure => running,
                enable => true
            }

            File <| tag == 'grouper-propfile' |> ~> Service['grouper-loader']

        }

    }
#


}

