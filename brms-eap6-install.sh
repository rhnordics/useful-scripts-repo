#!/bin/bash

## Settings
INSTALL_DIR=$HOME/brmsdemo
NAME=brms_server
PIDFILE=$INSTALL_DIR/var/run/$NAME.pid

INSTALL_DIR=$HOME/brmsdemo
LOCAL_SW_REPO=$INSTALL_DIR/swrepo
TMPDIR=$INSTALL_DIR/tmp
JBOSS_HOME=$INSTALL_DIR/brms-server

DOWNLOAD_EAP=true
DOWNLOAD_EAP_URL=http://download.devel.redhat.com/released/JBEAP-6/6.0.0/zip/jboss-eap-6.0.0.zip
EAP_ZIP_FILE=$LOCAL_SW_REPO/jboss-eap-6.0.0.zip
DOWNLOAD_BRMS=true
DOWNLOAD_BRMS_URL=http://jawa05.englab.brq.redhat.com/candidate/BRMS-5.3.1-ER3/brms-p-5.3.1.ER3-deployable-ee6.zip
BRMS_ZIP_FILE=$LOCAL_SW_REPO/jboss-brms-5.3.1-deployable-ee6.zip

USERS_PROP_FILE=$JBOSS_HOME/standalone/configuration/brms-users.properties
ROLES_PROP_FILE=$JBOSS_HOME/standalone/configuration/brms-roles.properties

SCRIPT_ERROR_MSG_FILE=`mktemp`

create_if_not_exists() {
	if [ ! -d $1 ]
	then 
		mkdir -p $1
		if [ "$?" -ne "0" ]; then
			echo "Failed to create dir $1, exiting"
			exit 99
		fi
	fi
}

delete_if_exists() {
	if [ -d $1 ]
	then 
		rm -rf $1
		if [ "$?" -ne "0" ]; then
			echo "Failed to delete dir $1, exiting"
			exit 98
		fi
	fi
}

setup_dir() {
	delete_if_exists $TMPDIR
	delete_if_exists $JBOSS_HOME
	create_if_not_exists $INSTALL_DIR/var/run
	create_if_not_exists $INSTALL_DIR
	create_if_not_exists $LOCAL_SW_REPO
	create_if_not_exists $TMPDIR
	create_if_not_exists $INSTALL_DIR/brms-repo
	
}

download_subprocess() {
	wget --quiet --output-document=$2 $1 > /dev/null 2>&1
	if [ "$?" -ne "0" ]; then
		echo "Failed to download $1, aborting"
		exit 97
	fi	
}	 


download_software() {
	if [ -e $2 ]
	then
		echo "$2 is allready in the software repo, skipping...."
	else
		echo -n "Downloading $1 ..."
		download_subprocess $1 $2 > /dev/null 2>&1 &
		local procid=$!
		local delay=0.75
    		local spinstr='|/-\'
    		while [ "$(ps a | awk '{print $1}' | grep $procid)" ]; do
        		local temp=${spinstr#?}
        		printf " [%c]  " "$spinstr"
        		local spinstr=$temp${spinstr%"$temp"}
        		sleep $delay
        		printf "\b\b\b\b\b\b"
    		done
    		printf "    \b\b\b\b"
	fi
	echo "Done"	
}

download_eap() {
	if [ "$DOWNLOAD_EAP" == "true" ]; then
		if [ -e $EAP_ZIP_FILE ]
		then
			return 2
		else
			download_software $DOWNLOAD_EAP_URL $EAP_ZIP_FILE
		fi
	fi
}

download_brms() {
	if [ "$DOWNLOAD_BRMS" == "true" ]; then
		if [ -e $BRMS_ZIP_FILE ]
		then
			return 2
		else
			download_software $DOWNLOAD_EAP_URL $BRMS_ZIP_FILE
		fi
	fi
}

user_abort() {
	echo "Aborted by user. Cleaning up subprocesses"
	pkill wget
	cleanup
}

cleanup() {
	rm -rf $TMPDIR
	rm -rf $JBOSS_HOME
}

create_authentication_files() {
	echo "admin=admin" > $USERS_PROP_FILE
	echo "krisv=krisv" >> $USERS_PROP_FILE
	echo "john=john" >> $USERS_PROP_FILE
	echo "mary=mary" >> $USERS_PROP_FILE
	echo "sales-rep=sales-rep" >> $USERS_PROP_FILE


	echo "admin=admin,manager,user,webdesigner,functionalanalyst" > $ROLES_PROP_FILE
	echo "krisv=admin,manager,user" >> $ROLES_PROP_FILE
	echo "john=admin,manager,user,PM" >> $ROLES_PROP_FILE
	echo "mary=admin,manager,user,HR" >> $ROLES_PROP_FILE
	echo "sales-rep=admin,manager,user,sales" >> $ROLES_PROP_FILE
}

start_brmsserver() {
	if check_stopped
	then 
		pushd $JBOSS_HOME/bin > /dev/null 
		PID=`./standalone.sh > /dev/null & echo $!`
		if [ -z $PID ]; then
		    store_error_msg "The Server didn't seam to start correctly, no process id was returned"
	            return 1
	        else
	            echo $PID > $PIDFILE
	        fi
		sleep 5
		popd > /dev/null
	 	if check_started
	 	then
	 		return 0
	 	else
	 		store_error_msg "The Server didn't seam to start correctly please, verify by checking the boot.log"
	 		return 1
	 	fi
	 else
	 	return 1 #server already started, this is a error scenario
	 fi
}

check_stopped() {
	if [ -f $PIDFILE ]; then
		PID=`cat $PIDFILE`
		if [ -z "`ps axf | grep ${PID} | grep -v grep`" ]; then
			rm -f $PIDFILE
			return 0
		else
			return 1
		fi
	else
		return 0
	fi
}

check_started() {
	if [ -f $PIDFILE ]; then
		PID=`cat $PIDFILE`
		if [ -z "`ps axf | grep ${PID} | grep -v grep`" ]; then
			store_error_msg "The process is dead but a pidfile exists"
			return 1
		else
			return 0
		fi
	else
		return 1
	fi
		
}

store_error_msg() {
	echo $@ > $SCRIPT_ERROR_MSG_FILE
}

print_error_msg() {
	cat $SCRIPT_ERROR_MSG_FILE
}

cli_command() {
	$JBOSS_HOME/bin/jboss-cli.sh -c --command="$1" > /dev/null 2>&1
	if [ "$?" -ne "0" ]; then
		echo "Failed to execute CLI command $1, aborting"
		exit 80
	fi
}	

stop_brmsserver() {
	cli_command ":shutdown(restart=false)"
}

restart_brmsserver() {
	cli_command ":shutdown(restart=true)"
}


configure_globalmodules() {
	cli_command "/subsystem=ee/:write-attribute(name=global-modules,value=[{\"name\"=>\"org.jboss.netty\",\"slot\"=>\"main\"}])"
	
}

configure_authentication() {
	create_authentication_files
	cli_command "/subsystem=security/security-domain=brms/:add(cache-type=default)"
	cli_command "/subsystem=security/security-domain=brms/authentication=classic:add(login-modules=[{\"code\"=>\"UsersRoles\",\"flag\"=>\"required\",\"module-options\"=>[(\"usersProperties\"=>\"\${jboss.server.config.dir}/brms-users.properties\"),(\"rolesProperties\"=>\"\${jboss.server.config.dir}/brms-roles.properties\")]}]"
	
}

configure_jbpm_datasource() {
	cli_command "/subsystem=datasources/data-source=jbpmDS/:add(connection-url=\"jdbc:h2:mem:jbpm;DB_CLOSE_DELAY=-1\",jndi-name=\"java:jboss/datasources/jbpmDS\",driver-name=\"h2\",use-java-context=\"true\",user-name=\"sa\",password=\"sa\")"
	cli_command ":reload"
}


unzip_applications() {
	pushd $TMPDIR > /dev/null
	unzip $BRMS_ZIP_FILE > $SCRIPT_ERROR_MSG_FILE 2>&1
	if [ "$?" -ne "0" ]; then
		return 1
	else
		rm -f $SCRIPT_ERROR_MSG_FILE
	fi
	mkdir apps > /dev/null
	pushd apps > /dev/null
	unzip ../jboss-brms-manager-ee6.zip > $SCRIPT_ERROR_MSG_FILE 2>&1
	if [ "$?" -ne "0" ]; then
		return 1
	else
		rm -f $SCRIPT_ERROR_MSG_FILE
	fi
	unzip ../jboss-jbpm-console-ee6.zip > $SCRIPT_ERROR_MSG_FILE 2>&1
	if [ "$?" -ne "0" ]; then
		return 1
	else
		rm -f $SCRIPT_ERROR_MSG_FILE
	fi
	
	popd > /dev/null
	popd > /dev/null
	return 0
	

}

configure_guvnor() {
	if [ -d $TMPDIR/apps/jboss-brms.war ]; then
		pushd $TMPDIR/apps/jboss-brms.war > /dev/null
		sed -i "s/jaas-config-name=\"jmx-console\"/jaas-config-name=\"brms\"/g" WEB-INF/components.xml > /dev/null 2>&1
		#sed -i "s/<!--  <key>repository.root.directory<\/key><value>\/opt\/yourpath<\/value>  -->/<key>repository.root.directory<\/key><value>$INSTALL_DIR\/brms-repo<\/value>/g" WEB-INF/components.xml > /dev/null 2>&1
		popd > /dev/null
	else
		store_error_msg "Can't find jboss-brms.war directory. Aborting!"
		return 1
	fi
}


package_war() {
	if [ -d $1 ]; then
		local warfilename=`basename $1`
		local tmpdir=`mktemp -d`
		local warfile="$tmpdir/$warfilename"
	
		pushd $1 > /dev/null
		jar -cf $warfile * > $SCRIPT_ERROR_MSG_FILE 2>&1
		if [ "$?" -ne "0" ]; then
		 	return 1
		else
		 	rm -f $SCRIPT_ERROR_MSG_FILE
		fi
		popd > /dev/null
		echo $warfile
	else
		store_error_msg "Can't find $1 directory. Aborting!"
		return 1
	fi
}

deploy_war() {
	if [ -f $1 ]; then
		cli_command "deploy $1" > /dev/null
		if [ "$?" -ne "0" ]; then
		 	store_error_msg "Failed to deploy $war. Aborting!"
		 	return 1
		fi
	else
		store_error_msg "Failed to deploy $1, Aborting!"
		return 1
	fi
}


package_and_deploy_exploded_war() {
	local warfile=`package_war $1`
	if [ "$?" -ne "0" ]; then
		return $?
	fi
	cli_command "deploy $warfile" > /dev/null
	if [ "$?" -ne "0" ]; then
		return $?
	fi
	
}

	

run() {
	blue=$(tput setaf 4)
	red=$(tput setaf 1)
	normal=$(tput sgr0)

	local text="$1"
	shift
	printf "%-50s" "$text"
	retval=`$@`
	case $? in
		0)      
			printf "%s\n" "[${blue}OK${normal}]"
			;;
		1)	
			printf "%s\n" "[${red}FAILURE${normal}]"
			print_error_msg
			exit 50
			;;	
		2)	
			printf "%s\n" "[${blue}SKIPPED${normal}]" 
			;;
		*)
		    	printf "%s\n" "[${red}UNKNOWN${normal}]" 
            		exit 1
	esac
	
	store_error_msg ""
}

install_eap6() {
	pushd $TMPDIR > /dev/null
	unzip -qq $EAP_ZIP_FILE
	if [ "$?" -ne "0" ]; then
		return 1
	fi	
	mv jboss-eap-6.* $JBOSS_HOME
	if [ "$?" -ne "0" ]; then
		return 1
	fi
	popd > /dev/null
	return 0
	
}




main() {
	setup_dir
	run "Downloading EAP 6" "download_eap"
	run "Downloading BRMS 5.3.1" "download_brms"
	run "Installing EAP 6" "install_eap6"
	run "Starting EAP6" "start_brmsserver"
	run "Configure Netty as global module" "configure_globalmodules"
	run "Creating JAAS module for Guvnor" "configure_authentication"
	run "Setup datasource for jBPM5 " "configure_jbpm_datasource"
	run "Unzipping applications" "unzip_applications"
	run "Configure Guvnor to use JAAS module" "configure_guvnor"
	run "Package and deploy Guvnor" "package_and_deploy_exploded_war $TMPDIR/apps/jboss-brms.war"
	run "Package and deploy Designer" "package_and_deploy_exploded_war $TMPDIR/apps/designer.war"
#	run "Deploying Guvnor to the server" "deploy_guvnor"		
	#run "Stop BRMS Server" "stop_brmsserver"
}

trap user_abort INT


main
exit 0




## Setup driver 
## $JBOSS_HOME/bin/jboss-cli.sh -c --command="/subsystem=datasources/jdbc-driver=postgresql-jdbc4/:add(driver-module-name=org.postgresql,jdbc-compliant=false)"

## Setup datasource BRMSDS
#$JBOSS_HOME/bin/jboss-cli.sh -c --command="/subsystem=datasources/data-source=brmsDS/:add(connection-url=jdbc:postgresql://localhost:5432/brmseap6,jndi-name=java:jboss/datasources/brmsDS,driver-name=postgresql-jdbc4,driver-class=org.postgresql.Driver,use-java-context=true,jta=true,max-pool-size=20,min-pool-size=2,pool-prefill=true,user-name=brmseap6,password=brmseap6,allow-multiple-users=false,share-prepared-statements=false,set-tx-query-timeout=false,check-valid-connection-sql=SELECT 1,background-validation=false,use-fast-fail=false,validate-on-match=false,use-ccm=false)"

## Setup datasource jbpmDS
#$JBOSS_HOME/bin/jboss-cli.sh -c --command="/subsystem=datasources/data-source=jbpmDS/:add(connection-url=jdbc:postgresql://localhost:5432/brmseap6,jndi-name=java:jboss/datasources/jbpmDS,driver-name=postgresql-jdbc4,driver-class=org.postgresql.Driver,use-java-context=true,jta=true,max-pool-size=20,min-pool-size=2,pool-prefill=true,user-name=brmseap6,password=brmseap6,allow-multiple-users=false,share-prepared-statements=false,set-tx-query-timeout=false,check-valid-connection-sql=SELECT 1,background-validation=false,use-fast-fail=false,validate-on-match=false,use-ccm=false)"



