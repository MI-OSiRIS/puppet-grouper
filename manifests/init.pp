# This module will manage grouper configurations but does not do everything that the grouperInstaller does.
# You still will need to manually download and extract + patch the grouper archives.
# You can setup grouperInstaller to do this non-interactively:
# https://spaces.internet2.edu/display/Grouper/Grouper+installer+non+interactive+auto+apply+patches+example
#
# This module does not initialize the grouper database.
# Sample schema are here:  https://spaces.internet2.edu/display/Grouper/Grouper+Installer

# You can optionally run the grouperInstaller to take care of download, patching, database and then use this module to
# finish the configuration and manage the installation on an ongoing basis.
# It may also be useful to copy your installation and manage different test configs with additional grouper::instance resources.

# Configs defined as grouper::instance so multiple grouper instances can be managed on same host
#
# configures:
#  - subject API adapter in sources.xml  (only a single LDAP adapter is supported)
#  - grouper.properties wheel group autocreate config
#  - log4j config to choose logfile location
#  - grouper database configuration (does not initialize database)
#
# Taken from steps at https://spaces.internet2.edu/display/COmanage/Grouper+Provisioning+Plugin
# Also from https://spaces.internet2.edu/download/attachments/93651000/TI.25.1-TIERGrouperDeploymentGuide.pdf
#
# If you choose to follow instructions from Comanage plugin installation to replace jdbc clients
# then set detect_utf8_problems and log_driver_mismatch false.
#
# It is probably not strictly necessary, the TIER deployment guide does not have that step and is more recent
# My test installation was fine with the packaged database drivers but I did later update
# Jarfile: https://downloads.mariadb.com/Connectors/java/connector-java-2.0.3/mariadb-java-client-2.0.3.jar
#
# also requires margascon::profile_d
#
# Class Params:
#
# manage_groovy
# 	install groovy package (does not setup groovysh4grouper: https://github.com/wgthom/groovysh4grouper)
#
# groovy_install
#		'download' will grab binary archive from dl.bintray.com.  Requires example42-puppi module.
#		'package' will install with dist package from pre-existing repo
#
# groovy_version
#	which version to download if groovy_install is set to 'download'
#
# manage_tomcat
#	install and configure tomcat.  Requires puppetlabs-tomcat module.  RHEL7 only.  Build .war file from the installation(s) managed
#   in grouper::instance resources and place in /usr/share/tomcat/webapps.
#
# grouper_system_password
#    if manage_tomcat is true configure grouper_system role and GrouperSystem user in tomcat-users.xml
#
# ldap_auth_realm_config
#     If defined, should be a hash which is then passed to 'additional_attributes' param of tomcat::config::server::realm resource
#	  If not defined no realm is created
#     If you configure this make sure that whatever lookup you configure in LDAP returns grouper_user for users (including GrouperSystem if using it for ws access)


class grouper(
	$manage_groovy = true,
	$manage_tomcat = true,
	$groovy_version = '2.4.12',
	$groovy_install = 'download',
	$mail_smtp_server = 'localhost',
	$grouper_system_password = undef,
	$ajp_tomcat_authentication = true,
	$http_tomcat_authentication = true,
	$ldap_auth_realm_config = undef
) {

	if $manage_tomcat {

		File <| tag == 'grouper-propfile' |> ~> Service['tomcat']
		Augeas <| tag == 'grouper-propfile' |> ~> Service['tomcat']

		class { 'tomcat':
			catalina_home       => '/usr/share/tomcat'
		}

		# Just using a few basic resources from mdule
		tomcat::install { 'grouper_tomcat':
			install_from_source => false,
			package_name        => 'tomcat',
		}

		tomcat::config::server::connector { 'grouper-http':
			protocol              => 'HTTP/1.1',
			port                  => '8080',
			additional_attributes => {
				'URIEncoding' => 'UTF-8',
				 'tomcatAuthentication' => $http_tomcat_authentication
			}
		}

		tomcat::config::server::connector { 'grouper-ajp':
			protocol              => 'AJP/1.3',
			port                  => '8009',
			additional_attributes => {
				'URIEncoding' => 'UTF-8',
				'tomcatAuthentication' => $ajp_tomcat_authentication
			}
		}

		if $ldap_auth_realm_config {
			tomcat::config::server::realm { 'auth-realm':
				class_name => "org.apache.catalina.realm.JNDIRealm",
				additional_attributes =>  $ldap_auth_realm_config
			}
		}

		# tomcat::service could be used here but would need non-default params (and also defaults to using service instead of systemctl)
		service { 'tomcat':
			ensure => running,
			enable => true,
		}

		file_line { 'sysconfig_tomcat':
			path   => '/etc/sysconfig/tomcat',
			line   => 'JAVA_OPTS="-server -Xmx512M -XX:MaxPermSize=256M"',
			match  => '^JAVA_OPTS\=',
			notify => Service['tomcat']
		}

		# Define user GrouperSystem for use by tomcat auth.  Not referenced if using external auth from webserver

		if $password {
			tomcat::config::server::tomcat_users { 'grouper_system':
				element => 'role'
			}

			tomcat::config::server::tomcat_users { 'GrouperSystem':
				element  => 'user',
				password => $password,
				roles    => [ 'grouper_user' ]
			}
		}

	}

	package {
		[
			'java-1.8.0-openjdk',
			'java-1.8.0-openjdk-devel',
			'mariadb-server',
		]: ensure => present
	}

	if $manage_groovy {
		if $groovy_install == 'download' {
		    puppi::netinstall { 'groovysh':
		        url                 => "https://dl.bintray.com/groovy/maven/apache-groovy-binary-${groovy_version}.zip",
		        work_dir            => '/tmp',
		        extracted_dir       => "groovy-${groovy_version}",
		        destination_dir     => '/opt',
		        postextract_command => "ln -s /opt/groovy-${groovy_version} /opt/groovy ; ln -s /opt/groovy/bin/groovysh /usr/bin/groovysh"
		    }
		} else {
			package { 'groovy': ensure => present }
		}
	}

	# this should be part of a managed mariadb instance which also does these things:
	# create database grouper;
	# create user 'grouper'@'localhost' identified by 'somepass';
	# grant all privileges on grouper.* to 'grouper'@'localhost';

	# do not use utf8mb4, requires changes to database column definitions because of character limit of 191 in utf8mb4 (more bits per character means less max characters)

	# leave to user to restart
	file  { '/etc/my.cnf.d/charset.cnf':
		content =>  "[mysqld] \ncharacter-set-server = utf8 \ncollation-server = utf8_bin"
	}

}







