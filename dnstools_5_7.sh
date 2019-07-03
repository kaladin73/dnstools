#!/bin/bash
#############################################
#
# DNSTools
# kaladin73
#
#############################################
# sudo dos2unix dnstools.sh to remove Windows characters

VERSION="5.7"
RELEASE_DATE="07/03/19"
DEBUG=4
INFO=3
WARNING=2
ERROR=1
OUTPUT_LEVEL=$DEBUG
#export PGPASSWORD=$DBPWD
DNSToolsConfig="/etc/bind/dnstools.conf"
TMP_FILE=/tmp/.dnstools_$$
TMP_FILE2=/tmp/.dnstools_$$_2
TMP_SEARCH=/tmp/.dnstools_$$_3
TMP_MESSAGE=/tmp/.dnstools_$$_4
TMP_SESSION_HISTORY=/tmp/dnstools_$$_4
TMP_FUNCTION_HISTORY=/tmp/dnstools_$$_5
ColorRed="\e[1;31m"
ColorGreen="\e[1;32m"
ColorWhite="\e[0m"
ColorBlue="\e[1;34m"
ColorPurple="\e[0;35m"
ColorYellow="\e[1;33m"

UpdateRequired="\e[1;32mno\e[0m" #this will display no is green

# Check that user has correct permission level
if [[ $EUID -ne 0 ]]; then
	echo "************************************************"
	echo "*  WARNING - This program must be run as root  *"
	echo "*  Please re-run using sudo                    *"
  	echo "*  Program will now exit                       *"
  	echo "************************************************"
  	exit 1
fi

STATUS=(
	"issue"
	"issue"
	"issue"
	"issue"
	"issue"
	"issue"
	"issue"
	"issue"
	"issue"
	"issue"
	"issue"
	"issue"
)


#2) Functions
function displayhelp
{
	echo "***********************************  Help  **********************************"
	echo "* Written by kaladin73, October 2018                                        *"
	echo "* Version: $VERSION                                                              *"
	echo "* Released: $RELEASE_DATE                                                        *"
	echo "*                                                                           *"
	echo "* This tool will auto-generate /etc/bind/dnstools.conf                      *"
	echo "*   - Open the config file and setup the variables to match your setup      *"
	echo "*   - Order matters when setting up the arrays                              *"
	echo "*                                                                           *"
	echo "* To update registered zone files:                                          *"
	echo "*   - run sudo nano dnstools.sh and update the following:                   *"
	echo "*        DOMAINS, PATHS, and ZONES                                          *"
	echo "*                                                                           *"
	echo "* To resolve issues with registered zone files:                             *"
	echo "*   - ensure file names are correct                                         *"
	echo "*   - ensure replace strings have been placed in the files                  *"
	echo "*         add #OpenTrust to the trusted group within named.conf.options     *"
	echo "*         add ;PlaceHolder to the end of each zone file                     *"
	echo "*                                                                           *"
	echo "*********************************  End Help  ********************************"
	echo ""
    echo ""
    echo -n "Press ENTER to return to main menu"
    read -e TMP
	return 0;
}


function output
{
    OPT=""
    if [[ $1 == "-ne" ]]; then
            OPT="-ne"
            shift
    fi
    if (( $OUTPUT_LEVEL >= $1 )); then
            shift
            while (( $# > 0 )); do
                    echo $OPT "$1"
                    shift
            done
    fi
}



function abort
{
    echo $1
    rm -f $TMP_FILE
    rm -f $TMP_FILE2
    rm -f $TMP_SEARCH
    rm -f $TMP_MESSAGE
    rm -f $TMP_SESSION_HISTORY
    rm -f $TMP_FUNCTION_HISTORY
    exit 1
}



function refreshdns
{
	ContainsErrors=false
	echo "">> $TMP_MESSAGE
	rm $TMP_MESSAGE
	echo ""
	echo "************************** Begin DNS Service Refresh **************************"
	for ((i=0; i < $domainsCount; i++))
    do
        FILE=${PATHS[i]}
		DOMAIN=${DOMAINS[i]}
		ZONE=${ZONES[i]}
		echo "Running checkzone on $DOMAIN"
		if [ ! -f $FILE ]; then
	    	echo "$FILE does not exist"
		else
			#status of 0 means no errors, 1 means error
			{
			named-checkzone $DOMAIN $FILE; status=$? 
			} >&-
			if (($status == 1)); then
				ContainsErrors=true
				echo "FAILED - checkzone on $DOMAIN, see final report for details" | tee -a $TMP_SESSION_HISTORY
				echo "Error report for $DOMAIN" >> $TMP_MESSAGE
				echo "COPY THIS: sudo nano $FILE" >> $TMP_MESSAGE
				named-checkzone $ZONE $FILE >> $TMP_MESSAGE
				echo "" >> $TMP_MESSAGE
			elif (($status == 0)); then
				echo "SUCCESS - checkzone passed on $DOMAIN" | tee -a $TMP_SESSION_HISTORY
			fi
		fi
		echo ""
    done

    if [[ $domainsCount -eq 0 ]]; then
    	echo "There are no domains to refresh." >> $TMP_MESSAGE
    	ContainsErrors=true
    fi

	if [[ "$ContainsErrors" = true ]]; then
		echo "*****************************************************************************************************"
		echo "1 or more errors is preventing completion of the update. Correct the following errors then try again."
		echo "*****************************************************************************************************"
		echo ""
		cat $TMP_MESSAGE
		rm $TMP_MESSAGE
	else
		echo "Restarting network adapter..."
		/etc/init.d/networking restart
		echo "Network restart complete" | tee -a $TMP_SESSION_HISTORY
		echo ""

		echo "Flushing Remote Name Daemon Control RNDC..."
		rndc flush
		echo "RNDC flush complete" | tee -a $TMP_SESSION_HISTORY
		echo ""

		echo "Reloading Remote Name Daemon Control RNDC..."
		rndc reload
		echo "RNDC reload complete" | tee -a $TMP_SESSION_HISTORY
		echo ""
		echo "**********************************************"
		echo "*  DNS SERVER UPDATE SUCCESSFULLY COMPLETED  *"
		echo "**********************************************"
		UpdateRequired="\e[1;32mno\e[0m"
	fi
	return 1;
}



function getIPaddress
{
	NEWIPADDRESS="1"
	loopCounter=5
	while [[ $loopCounter > 0 ]];
	do
		ipInputValid=true
		echo -n "Enter IP Address: "
		read -e ipFromUser
		echo ""
		if [ ${#ipFromUser} -lt 7 ]; then
			echo "$ipFromUser is not a valid IP address; length is ${#ipFromUser}. No changes to file. Please try again."
			ipInputValid=false
		fi

		#Validate IP Address
		IFS='.' read -ra IPADD <<< "$ipFromUser"
		octetCount=${#IPADD[@]}
		if [[ octetCount -gt 4 ]]; then
			echo "FAILED - $ipFromUser contains too many octets"
		   	ipInputValid=false
		elif [[ octetCount -lt 4 ]]; then
			echo "FAILED - $ipFromUser contains too few octets"
		   	ipInputValid=false
		else
			#Validate IP Address
			if [ ${IPADD[0]} -lt 1 ] || [ ${IPADD[0]} -gt 255 ]; then
			   echo "FAILED - ${IPADD[0]} not in range 1-255. Function will now exit"
			   ipInputValid=false
			fi
			if [ ${IPADD[1]} -lt 1 ] || [ ${IPADD[1]} -gt 255 ]; then
			   echo "FAILED - ${IPADD[1]} not in range 1-255. Function will now exit"
			   ipInputValid=false
			fi
			if [ ${IPADD[2]} -lt 1 ] || [ ${IPADD[2]} -gt 255 ]; then
			   echo "FAILED - ${IPADD[2]} not in range 1-255. Function will now exit"
			   ipInputValid=false
			fi
			if [ ${IPADD[3]} -lt 1 ] || [ ${IPADD[3]} -gt 255 ]; then
			   echo "FAILED - ${IPADD[3]} not in range 1-255. Function will now exit"
			   ipInputValid=false
			fi
		fi
		
		if [ "$ipInputValid" = true ]; then
			echo "VALIDATED - IP Address ${IPADD[0]}.${IPADD[1]}.${IPADD[2]}.${IPADD[3]}"
			echo ""
			NEWIPADDRESS="${IPADD[0]}.${IPADD[1]}.${IPADD[2]}.${IPADD[3]}"
			loopCounter=0
		else
			#echo "FAILED - User Input: $ipFromUser, Parsed IP Address ${IPADD[0]}.${IPADD[1]}.${IPADD[2]}.${IPADD[3]}"
			echo -n "Would you like to try again? (yes/no/cancel): "
			read -e userResponse
			if [[ "$userResponse" == "yes" ]]; then
				loopCounter=$((loopCounter+1))
			elif [[ "$userResponse" == "no" ]]; then
				loopCounter=0
				NEWIPADDRESS="1"
			elif [[ "$userResponse" == "cancel" ]]; then
				loopCounter=0
				NEWIPADDRESS="1"
			else
				loopCounter=0
				NEWIPADDRESS="1"
			fi
		fi

	done
	return 0;
}



function addDnsEntry
{
	echo ""
	echo "What is the IP address for the new DNS entry?"
	#Use getIPaddress, return 1 if validation fails
	getIPaddress
	if [[ "$NEWIPADDRESS" == "1" ]]; then
		echo "IP address function returned bad value of [ $NEWIPADDRESS ]"
		echo "System will now return to main menu"
		echo ""
		return 1;
	fi
	
	echo "What is the FQDN for the new DNS entry?"
	echo -n "Enter FQDN: "
	read -e NEWFQDN
	if [ ${#NEWFQDN} -lt 4 ]; then
		echo "$NEWFQDN is not a valid FQDN. No changes to file. Please try again."
		return 1;
	else
		#Validate FQDN
		IFS='.' read -ra FQDNAR <<< "$NEWFQDN"
		domainFound=false
		for ((i=0; i < $domainsCount; i++))
		do
			if [[ "$NEWFQDN" == *"${DOMAINS[i]}"* ]]; then
				FORWARDFILE="${PATHS[i]}"
				domainFound=true
			fi
		done
		if [ "$domainFound" = false ]; then
			echo "FAILED - $NEWFQDN is not in any of the current forward dbs"
			echo "System will now return to the main menu"
			echo ""
			return 1;
		fi
		echo "VALIDATED - $NEWFQDN will be added to $FORWARDFILE"
	fi

	# Add new entry to database files
	# Search string within zone files is ;PlaceHolder
	domainFound=false
	for ((i=0; i < $domainsCount; i++))
	do
		if [[ "${IPADD[0]}.${IPADD[1]}.${IPADD[2]}" == "${DOMAINS[i]}" ]]; then
			REVERSEFILE="${PATHS[i]}"
			domainFound=true
		fi
	done
	if [ "$domainFound" = false ]; then
		echo "FAILED - $NEWIPADDRESS is not in any of the existing reverse dbs"
		echo "System will now return to the main menu"
		echo ""
		return 1;
	fi
	
	echo ""
	value=$(grep -c "$NEWIPADDRESS" "$REVERSEFILE")
	if [[ $value -gt 0 ]]; then
		addReverse=false
	else
		addReverse=true
		echo "IP Address [ $NEWIPADDRESS ] will be added to [ $REVERSEFILE ]"
	fi
	value=$(grep -c "$NEWFQDN" "$FORWARDFILE")
	if [[ $value -gt 0 ]]; then
		addForward=false
	else
		addForward=true
		echo "Host [ ${FQDNAR[0]} ] will be added to [ $FORWARDFILE ]"
	fi
	echo -n "Would you like to continue? (yes/no): "
	read -e userResponse
	echo ""
	if [[ "$userResponse" == "yes" ]]; then
		FINDWHAT=";PlaceHolder"
		REPLACEWITH="${IPADD[3]}  IN  PTR  $NEWFQDN.  ; ${IPADD[0]}.${IPADD[1]}.${IPADD[2]}.${IPADD[3]}\r\n$FINDWHAT"
		if [ "$addReverse" = false ]; then
			echo "SKIPPED - $NEWIPADDRESS was already in reverse db $REVERSEFILE" | tee -a $TMP_SESSION_HISTORY | tee -a $TMP_FUNCTION_HISTORY
		else
			sed -i "s/$FINDWHAT/$REPLACEWITH/" $REVERSEFILE
			value=$(grep -c "$NEWIPADDRESS" "$REVERSEFILE")
			if [[ $value -gt 0 ]]; then
				echo "SUCCESS - $NEWIPADDRESS was added to reverse db $REVERSEFILE" | tee -a $TMP_SESSION_HISTORY | tee -a $TMP_FUNCTION_HISTORY
				UpdateRequired="\e[1;31myes\e[0m"
			else
				echo "FAILED - $NEWIPADDRESS was NOT added to reverse db $REVERSEFILE" | tee -a $TMP_SESSION_HISTORY | tee -a $TMP_FUNCTION_HISTORY
				echo "System will now return to the main menu"
				echo ""
				return 1;
			fi
		fi
		
		FINDWHAT=";PlaceHolder"
		REPLACEWITH="${FQDNAR[0]}   IN  A  ${IPADD[0]}.${IPADD[1]}.${IPADD[2]}.${IPADD[3]}"
		REPLACEWITH="$REPLACEWITH    ; $NEWFQDN \r\n$FINDWHAT"
		if [ "$addForward" = false ]; then
			echo "SKIPPED - $NEWFQDN was already in forward db $FORWARDFILE"
		else
			sed -i "s/$FINDWHAT/$REPLACEWITH/" $FORWARDFILE
			value=$(grep -c "${FQDNAR[0]}" "$FORWARDFILE")
			if [[ $value -gt 0 ]]; then
				echo "SUCCESS - $NEWFQDN was added to forward db $FORWARDFILE" | tee -a $TMP_SESSION_HISTORY | tee -a $TMP_FUNCTION_HISTORY
				UpdateRequired="\e[1;31myes\e[0m"
			else
				echo "FAILED - $NEWFQDN was NOT added to forward db $FORWARDFILE" | tee -a $TMP_SESSION_HISTORY | tee -a $TMP_FUNCTION_HISTORY
				echo "System will now return to the main menu"
				echo ""
				return 1;
			fi
		fi	
	else
		return 1;
	fi
	# Add new DNS entry to trusted hosts group?
	echo -n "Would you like to add $NEWIPADDRESS to the trusted host group? (yes/no): "
	read -e userResponse
	echo ""
	if [[ "$userResponse" == "yes" ]]; then
		SkipFunctionDisplay="yes"
		addNewTrust $NEWIPADDRESS ${FQDNAR[0]} $SkipFunctionDisplay
	fi
	
	# Print function history then remove history file
	viewfunctionhistory
	rm -f $TMP_FUNCTION_HISTORY

	return 0;
}



function removeDnsEntry
{
	echo ""
	echo "Remove which DNS Entry? Enter an IP address OR an RQDN"
	echo -n "Enter IP or FQDN: "
	read -e FINDWHAT
	echo ""

	#Check all zone files for the user provided string
	for ((i=0; i < $domainsCount; i++))
    do
		CONFFILE="${PATHS[i]}"
		value=$(grep -c "$FINDWHAT" "$CONFFILE")
		if [[ $value -eq 1 ]]; then
			DeleteString=$(grep "$FINDWHAT" "$CONFFILE")
			echo "Confirm deletion of..............................."
			echo "$DeleteString"
			echo "from [ $CONFFILE ] ?"
			echo -n "User input (YES/NO/cancel): "
			read -e DeleteConfirmation
			if [[ $DeleteConfirmation == "YES" ]]; then
				sed -i "/$FINDWHAT/d" $CONFFILE
				value=$(grep -c "$FINDWHAT" "$CONFFILE")
				if [[ $value -eq 0 ]]; then
					echo "SUCCESS - $FINDWHAT was removed from $CONFFILE" | tee -a $TMP_SESSION_HISTORY | tee -a $TMP_FUNCTION_HISTORY
					UpdateRequired="\e[1;31myes\e[0m"
				else
					echo "FAILED - $FINDWHAT was NOT removed from $CONFFILE" | tee -a $TMP_SESSION_HISTORY | tee -a $TMP_FUNCTION_HISTORY
				fi
				echo ""
			elif [[ $DeleteConfirmation == "NO" ]]; then
				echo "This instance will NOT be deleted"
			elif [[ $DeleteConfirmation == "cancel" ]]; then
				echo "Process canceled. Function will now exit."
				return 1;
			else
				echo "Your response was not understood. Function will now exit."
				return 1;
			fi
		elif [[ $value -gt 1 ]]; then
			echo "WARNING - There is more than 1 occurance of $FINDWHAT in"
			echo "$CONFFILE"
			echo ""
			echo "Delete all $value occurances?"
			echo -n "User input (YES/NO/cancel): "
			read -e DeleteConfirmation
			if [[ $DeleteConfirmation == "YES" ]]; then
				sed -i "/$FINDWHAT/d" $CONFFILE
				value=$(grep -c "$FINDWHAT" "$CONFFILE")
				if [[ $value -eq 0 ]]; then
					echo "SUCCESS - $FINDWHAT was removed from $CONFFILE" | tee -a $TMP_SESSION_HISTORY | tee -a $TMP_FUNCTION_HISTORY
					UpdateRequired="\e[1;31myes\e[0m"
				else
					echo "FAILED - $FINDWHAT was NOT removed from $CONFFILE" | tee -a $TMP_SESSION_HISTORY | tee -a $TMP_FUNCTION_HISTORY
				fi
			elif [[ $DeleteConfirmation == "NO" ]]; then
				echo "This instance will NOT be deleted"
			elif [[ $DeleteConfirmation == "cancel" ]]; then
				echo "Process canceled. Function will now exit."
				return 1;
			else
				echo "Your response was not understood. Function will now exit."
				return 1;
			fi
		fi
	done

	# Print function history then remove history file
	viewfunctionhistory
	rm -f $TMP_FUNCTION_HISTORY
	
	return 0;
}



function addNewTrust
{
	# uses #OpenTrust as a placeholder in the named.conf.options file
	creationConfirmed=false
	passedIpAddress=$1
	passedHostName=$2
	CONFFILE=/etc/bind/named.conf.options
	FINDWHAT="#OpenTrust"
	value=$(grep -c "$FINDWHAT" "$CONFFILE")
	if [[ $value -gt 1 ]]; then
		echo "Your named.conf.options file is not yet configured."
		echo "Please add $FINDWHAT to the trusted group to enable this function"
		echo "System will now return to the main menu"
		echo ""
		return 1;
	fi
	if [ ${#passedIpAddress} -eq 0 ]; then
		echo ""
		echo "What IP address would you like to add to the trusted group?"
		#Use getIPaddress, return 1 if validation fails
		getIPaddress
		if [[ "$NEWIPADDRESS" == "1" ]]; then
			echo "IP address function returned bad value of [ $NEWIPADDRESS ]"
			echo "System will now return to main menu"
			echo ""
			return 1;
		fi
		echo "What is the name of the new host?"
		echo -n "Enter hostname: "
		read -e NEWHOST
	else
		NEWIPADDRESS=$passedIpAddress
		NEWHOST=$passedHostName
		creationConfirmed=true
	fi
	
	REPLACEWITH="$NEWIPADDRESS;  # $NEWHOST"
	
	echo "[ $REPLACEWITH ] will be added to trusted host group in $CONFFILE"
	echo -n "Would you like to continue? (yes/no): "
	read -e userResponse
	if [[ "$userResponse" == "yes" ]]; then
		REPLACEWITH="$REPLACEWITH\r\n        #OpenTrust"
		sed -i "s/$FINDWHAT/$REPLACEWITH/" $CONFFILE
		value=$(grep -c "$NEWIPADDRESS" "$CONFFILE")
		if [[ $value -gt 0 ]]; then
			echo "SUCCESS - $NEWIPADDRESS was added to trusted group in $CONFFILE" | tee -a $TMP_SESSION_HISTORY | tee -a $TMP_FUNCTION_HISTORY
		else
			echo "FAILED - $NEWIPADDRESS was NOT added to $CONFFILE" | tee -a $TMP_SESSION_HISTORY | tee -a $TMP_FUNCTION_HISTORY
		fi
		UpdateRequired="\e[1;31myes\e[0m"
	elif [[ "$userResponse" == "no" ]]; then
		echo ""
		return 1;
	else
		return 1;
	fi
	
	if [[ "$SkipFunctionDisplay" != "yes" ]]; then
		viewfunctionhistory
		rm -f $TMP_FUNCTION_HISTORY
	fi
	
	return 1;
}

	

function removeTrust
{
	# uses #OpenTrust as a placeholder in the named.conf.options file
	CONFFILE=/etc/bind/named.conf.options
	if [ ! -f $CONFFILE ]; then
	    echo "$CONFFILE does not exist. Nothing to do"
	    return 1;
	fi
	echo ""
	echo "Which IP address would you like to remove?"
	#Use getIPaddress, return 1 if validation fails
	getIPaddress
	if [[ "$NEWIPADDRESS" == "1" ]]; then
		echo "IP address parse function returned bad value of [ $NEWIPADDRESS ]"
		echo "System will now return to main menu"
		echo ""
		return 1;
	fi
	value=$(grep -c "$NEWIPADDRESS" "$CONFFILE")
	if [[ $value -lt 1 ]]; then
		echo "$NEWIPADDRESS was not found within your $CONFFILE file. Nothing to do."
		return 1;
	fi
	echo ""
	echo "[ $NEWIPADDRESS ] will be removed from the trusted host group in $CONFFILE"
	echo -n "Would you like to continue? (YES/no): "
	read -e userResponse
	if [[ "$userResponse" == "YES" ]]; then
		sed -i "/$NEWIPADDRESS/d" $CONFFILE
		value=$(grep -c "$NEWIPADDRESS" "$CONFFILE")
		if [[ $value -eq 0 ]]; then
			echo "SUCCESS - $NEWIPADDRESS was removed from $CONFFILE" | tee -a $TMP_SESSION_HISTORY | tee -a $TMP_FUNCTION_HISTORY
		else
			echo "FAILED - $NEWIPADDRESS was NOT removed from $CONFFILE" | tee -a $TMP_SESSION_HISTORY | tee -a $TMP_FUNCTION_HISTORY
		fi
		UpdateRequired="\e[1;31myes\e[0m"
	elif [[ "$userResponse" == "no" ]]; then
		echo ""
		return 1;
	else
		return 1;
	fi

	# Print function history then remove history file
	viewfunctionhistory
	rm -f $TMP_FUNCTION_HISTORY
	
	return 0;
}



function searchDnsEntry
{
	#TMP_SEARCH
	StringFound="no"
	echo ""
	echo "For what would you like to search?"
	echo -n "Enter IP address or keyphrase from FQDN: "
	read -e FINDWHAT
	echo ""
	echo "**************************** Search Results ****************************" >> $TMP_SEARCH

	#Check named.conf.options for user provided string
	CONFFILE="/etc/bind/named.conf.options"
	value=$(grep -c "$FINDWHAT" "$CONFFILE")
	if [[ $value -gt 0 ]]; then
		echo "$CONFFILE contains $value of [ $FINDWHAT ]" >> $TMP_SEARCH
		StringFound="yes"
		value=$(grep "$FINDWHAT" "$CONFFILE")
		coloredSearchString="\e[1;31m$FINDWHAT\e[0m"
		echo "${value//$FINDWHAT/$coloredSearchString}" >> $TMP_SEARCH
		#echo "$value" >> $TMP_SEARCH
		echo "" >> $TMP_SEARCH
	fi

	#Check all zone files for the user provided string
	for ((i=0; i < $domainsCount; i++))
    do
		CONFFILE="${PATHS[i]}"
		value=$(grep -c "$FINDWHAT" "$CONFFILE")
		if [[ $value -gt 0 ]]; then
			echo "$CONFFILE contains $value of [ $FINDWHAT ]" >> $TMP_SEARCH
			StringFound="yes"
			value=$(grep "$FINDWHAT" "$CONFFILE")
			coloredSearchString="\e[1;31m$FINDWHAT\e[0m"
			echo "${value//$FINDWHAT/$coloredSearchString}" >> $TMP_SEARCH
			#echo "$value" >> $TMP_SEARCH
			echo "" >> $TMP_SEARCH
		fi
	done
	echo "****************************** End Search  *****************************" >> $TMP_SEARCH

	if [[ $StringFound == "no" ]]; then
        echo "**************************** Search Result *****************************"
        echo "WARNING - $FINDWHAT was not found in any zone files"
        echo ""
        echo "***************************** End Search  ******************************"
		echo ""
    else
    	while IFS='' read -r line || [[ -n "$line" ]]; do
		    echo -e "$line"
		done < "$TMP_SEARCH"
    	#cat $TMP_SEARCH
		echo ""
    fi

    rm $TMP_SEARCH
	echo ""
    echo ""
    echo -n "Press ENTER to return to main menu"
    read -e TMP
	return 0;
}



function compareForwardToReverse
{
	# this function will make sure DNS entries appear on both a forward and reverse lookup
	echo "searchDnsEntry function not yet implemented"
	return 1;
}


function viewfunctionhistory
{
	echo ""
	echo "***************************** Function History  *****************************"
	if [ ! -f $TMP_FUNCTION_HISTORY ]; then
	    echo "$TMP_FUNCTION_HISTORY has nothing to show."
	else
		cat $TMP_FUNCTION_HISTORY
	fi
	echo "*************************** End Function History  ***************************"
	echo ""
	echo ""
    echo ""
    echo -n "Press ENTER to return to main menu"
    read -e TMP
	return 0;
}


function viewsessionhistory
{
	echo ""
	echo "****************************** Session History  *****************************"
	if [ ! -f $TMP_SESSION_HISTORY ]; then
	    echo "$TMP_SESSION_HISTORY not yet started. Nothing to show."
	else
		cat $TMP_SESSION_HISTORY
	fi
	echo "**************************** End Session History  ***************************"
	echo ""
	echo ""
    echo ""
    echo -n "Press ENTER to return to main menu"
    read -e TMP
	return 0;
}



function checknslookup
{
	echo ""
	echo -n "IP address or FQDN: "
	read -e NLlookUpOn
	if [ ${#NLlookUpOn} -lt 7 ]; then
		echo "Invalid entry. Function will now exit."
		return 1;
	fi
	nslookup NLlookUpOn
	echo ""
	return 0;
}



function togglebindservice
{
	bindStatus="inactive"
	systemctl is-active --quiet bind9
	bindStatus=$?
	# returns 3 if service is running
	if [[ "$bindStatus" == "0" ]]; then
		systemctl stop bind9
		echo "SUCCESS - toggled bind9 service to INACTIVE" | tee -a  $TMP_SESSION_HISTORY | tee -a $TMP_FUNCTION_HISTORY
	else
		systemctl start bind9
		echo "SUCCESS - toggled bind9 service to ACTIVE" | tee -a  $TMP_SESSION_HISTORY | tee -a $TMP_FUNCTION_HISTORY
	fi
	
	# Print function history then remove history file
	viewfunctionhistory
	rm -f $TMP_FUNCTION_HISTORY
	
	return 0;
}



function checkBindService
{
	bindStatus="inactive"
	systemctl is-active --quiet bind9
	bindStatus=$?
	if [[ "$bindStatus" == "0" ]]; then
		bindStatus="\e[1;32mactive\e[0m" #Display active in green
	else
		bindStatus="\e[1;31minactive\e[0m" #Display inactive in RED
	fi
	return 0;
}



function checkfilereadystatus
{
	#check named.conf.options file
	CONFFILE=/etc/bind/named.conf.options
	FINDWHAT="#OpenTrust"
	value=$(grep -c "$FINDWHAT" "$CONFFILE")
	if [[ $value -eq 0 ]]; then
		optionsFileStatus="\e[1;31missue\e[0m"
	else
		optionsFileStatus="\e[1;32mready\e[0m"
	fi

	#check zone files
	for ((i=0; i < $domainsCount; i++))
	do
		CONFFILE=${PATHS[i]}
		FINDWHAT=";PlaceHolder"
		value=$(grep -c "$FINDWHAT" "$CONFFILE")
		if [[ $value -eq 0 ]]; then
			STATUS[i]="\e[1;31missue\e[0m"
		else
			STATUS[i]="\e[1;32mready\e[0m"
		fi
	done
}



function creatDnstoolsconffile
{
	if [ ! -f $DNSToolsConfig ]; then
		echo "System will now create /etc/bind/dnstools.conf"
		echo "# Use this config file to initialize DNS Tools" >> $DNSToolsConfig
		echo "" >> $DNSToolsConfig
		echo "Domains=" >> $DNSToolsConfig
		echo "#Syntax: Domains=domain1.com,domain2.com,domain3.com" >> $DNSToolsConfig
		echo "#Example: Domains=eaton-nuc.com,lab1.com,home.com,192.168.1,192.168.2" >> $DNSToolsConfig
		echo "" >> $DNSToolsConfig
		echo "Paths=" >> $DNSToolsConfig
		echo "#Syntax: Paths=path1,path2,path3" >> $DNSToolsConfig
		echo "#Example: Paths=/etc/bind/zones/db.eaton-nuc.com,/etc/bind/zones/db.lab1.com,/etc/bind/zones/db.home.com,/etc/bind/zones/db.192.168.1,/etc/bind/zones/db.192.168.2" >> $DNSToolsConfig
		echo "" >> $DNSToolsConfig
		echo "Zones=" >> $DNSToolsConfig
		echo "#Syntax: Zones=zone1,zone2,zone3" >> $DNSToolsConfig
		echo "#Example: Zones=eaton-nuc.com,lab1.com,home.com,1.168.192.in-addr.arpa,2.168.192.in-addr.arpa" >> $DNSToolsConfig
		if [ -f $DNSToolsConfig ]; then
			echo "SUCCESS - Default $DNSToolsConfig was created" | tee -a $TMP_SESSION_HISTORY | tee -a $TMP_FUNCTION_HISTORY
			echo ""
			echo "$DNSToolsConfig exists but is not configured. Please configure"
		else
			echo "FAILED - Default $DNSToolsConfig could not be created" | tee -a $TMP_SESSION_HISTORY | tee -a $TMP_FUNCTION_HISTORY
			echo ""
			echo "Please create and configure $DNSToolsConfig"
		fi
	else
		echo "$DNSToolsConfig exists but is not fully configured. Please configure"
	fi
}


#3) Main Menu
# Future features:  Compare forward to reverse
MENUS=(
    "Refresh DNS Services"
    "Search for DNS Entry"
    "Add DNS Entry"
    "Remove DNS Entry"
    "Add new trusted computer"
    "Remove trusted computer"
    "View session history"
    "Check NSLOOKUP"
    "Start / Stop Bind9"
    "Help"
)
CALLS=(
    refreshdns
    searchDnsEntry
    addDnsEntry
    removeDnsEntry
    addNewTrust
    removeTrust
    viewsessionhistory
    checknslookup
    togglebindservice
    displayhelp
)

menusCount=${#MENUS[@]}

function printMenu
{
    for ((i=0; i < $menusCount; i++))
    do
        echo "$i) ${MENUS[i]}"
    done
}

while (( 1 == 1 ));
do
    domainsCount=0
    if [ -f $DNSToolsConfig ]; then
	    source $DNSToolsConfig
		IFS=',' read -ra DOMAINS <<< "$Domains"
		IFS=',' read -ra PATHS <<< "$Paths"
		IFS=',' read -ra ZONES <<< "$Zones"
		domainsCount=${#DOMAINS[@]}
	fi
    echo ""
    echo -e "\e[0;35m************** Bind9 DNS Tools **************\e[0m"
    echo ""
    echo -e "\e[1;33m--------- Registered zone files ---------\e[0m"
    echo " Status    Component"
    if [[ $domainsCount -eq 0 ]]; then
    	echo "Config file missing or not configured."
    	creatDnstoolsconffile
    else
    	checkfilereadystatus
	    echo -e "[ $optionsFileStatus ]  \e[1;34mnamed.conf.options\e[0m"
	    for ((i=0; i < $domainsCount; i++))
		do
			echo -e "[ ${STATUS[i]} ]  \e[1;34mdb.${DOMAINS[i]}\e[0m"
		done
    fi
    echo ""
    echo -e "\e[1;33m------------- System Status -------------\e[0m"
    checkBindService
    echo -n "Bind9 Service Status:         "
    echo -e "[ $bindStatus ]"
    echo -n "DNS Service Refresh Required: "
    echo -e "[ $UpdateRequired ]"
    echo ""
    echo -e "\e[1;33m--------------- Main Menu ---------------\e[0m"
    printMenu
    echo "x) Exit"
    echo ""
    echo -n "Enter Your Selection: "
    read -e TMP

    if [[ $TMP == "x" ]]; then
        abort
        break
    elif [[ $TMP == "0" ]]; then
    	if grep '^[[:digit:]]*$' <<< "$TMP";then
	        if [ -n "${CALLS[$TMP]}" ]; then
	            eval "${CALLS[$TMP]}"
	        fi
	    fi
    elif [[ $domainsCount -eq 0 ]]; then
    	echo ""
    	echo ""
    	echo -e "\e[1;31mTools are disabled until config file is correctly configured\e[0m"
    else
    	if grep '^[[:digit:]]*$' <<< "$TMP";then
	        if [ -n "${CALLS[$TMP]}" ]; then
	            eval "${CALLS[$TMP]}"
	        fi
	    fi
    fi
done

exit 0