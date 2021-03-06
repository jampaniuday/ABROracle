#!/bin/bash
# set -x
###############################
# Author: Adam Richards
# Description: wrapper for impdp 
###############################
# required variables 
PWFILE=/orabacklin/work/DBA/SAFE/pwfile
ODIR=DATA_PUMP_DIR_XA_SHARED
###############################
# run from the DATAPUMP dir
# get script directory
SWD=$(dirname ${0})
DPDIR="${SWD}"/../DATAPUMP
###############################
# process command line arguments
usage()
{
cat << EOF
usage: $0 options

Run oracle expdp based on template par file

OPTIONS:
   -h      Show this message
   -s      Oracle SID [required]
   -t      Parameter template file [required]
   -d      dump file match string [optional]
EOF
}

# initialize argument variables
TEMPLATEFILE=
SID=
DMPKEY=
# options with : after them expect an argument
while getopts “hs:t:d:” OPTION
do
     case $OPTION in
         h)
             usage
             exit 1
             ;;
         t)
             TEMPLATEFILE=$OPTARG
             ;;
         s)
             SID=$OPTARG
             ;;
         d)
             DMPKEY=$OPTARG
             ;;
         ?)
             usage
             exit
             ;;
     esac
done

if [[ -z $SID ]] || [[ -z $TEMPLATEFILE ]] 
then
     usage
     exit 1
fi
if [[ ! -f $TEMPLATEFILE ]]; then
     echo "Parameter file $TEMPLATEFILE does not exist."
     exit 1
fi
###############################
function convertsecs {
    h=$(($1/3600))
    m=$((($1/60)%60))
    s=$(($1%60))
    printf "%06d:%02d:%02d" $h $m $s
}
###############################
function validateSID()
{
# clear path with bad SID
export ORACLE_SID="BADBADBAD";export ORAENV_ASK=NO;. oraenv >/dev/null < /dev/null
# try passed in SID
export ORACLE_SID="${1}";export ORAENV_ASK=NO;. oraenv >/dev/null < /dev/null
which sqlplus 1> /dev/null 2>&1
OK=$?
printf "%d" "${OK}"
}
###############################
# get current directory
WD=$(pwd)
# get time stamp
TS=$(date +%F-%H-%M-%S|tr -d ' ')
###############################
# setup oracle envrionment using oraenv
VALID=$(validateSID "${SID}")

if [[ $VALID != 0 ]]; then
echo "Invalid SID ${SID}"
exit 1
fi

export ORACLE_SID=$SID;export ORAENV_ASK=NO;source oraenv 1> /dev/null < /dev/null
###############################
# get password for password file
PWD=
PWLIST=$(cat ${PWFILE} | tr '\r\n' ' ')
for PWREC in ${PWLIST}; do
	PSID=$(echo ${PWREC} | cut -d'|' -f2 )
	RE="${SID}?"
	if [[ $PSID =~ $RE  ]]; then
		PWD=$(echo ${PWREC} | cut -d'|' -f4 )
	fi
done
if [[ -z $PWD ]]; then
	echo "Unable to lookup password."
exit 1
fi
########################################################
# capture real path for oracle directory 
DIRPATH=$(sqlplus -S system/${PWD} << EOF
set heading off
select directory_path from dba_directories where directory_name = '${ODIR}';
exit
EOF
 2>&1)
OK=$(echo $DIRPATH | grep -c "ORA-")
if [[ $OK != 0 ]]; then
echo "Invalid SID ${SID} or instance has not been started."
exit 1
fi

DIRPATH=$(echo $DIRPATH | tr -d '\r\n')
OK=$(echo $DIRPATH | tr -d ' ')
if [[ -z $OK ]]; then
echo "Invalid oracle directory  ${ODIR}"
exit 1
fi
########################################################
# show DUMP file candidates
if [[ -z $DMPKEY ]]; then
echo "Listing of available DMP files in ${DIRPATH}"
DMPLIST=$(ls -c1 /orabacklin/datapump/*.DMP | xargs -I '{}' basename '{}' .DMP | sort)
for f in $DMPLIST; do
echo ${f}
done
read -p "Enter dump file match key: " DMPKEY
fi
########################################################
# Simple Associative Array implementation
function map_put
{
    alias "${1}$2"="$3"
}

# map_get map_name key
# @return value
#
function map_get
{
    alias "${1}$2" 2> /dev/null | awk -F"'" '{ print $2; }' 2> /dev/null
}

# map_keys map_name 
# @return map keys
#
function map_keys
{
    alias -p | grep $1 | cut -d'=' -f1 | awk -F"$1" '{print $2; }'
}
################################
DMPLIST=$(ls -c1 /orabacklin/datapump/*${DMPKEY}*.DMP | xargs -I '{}' basename '{}' .DMP | sort)
for f in $DMPLIST; do
	SETNAME=$(echo ${f} | perl -n -e 'if ($_=~m/^(.*)_\d\d$/) {print $1};')
	if [[ -z ${SETNAME} ]]; then
		SETNAME="${f}"
	else
		SETNAME="${SETNAME}_"
	fi
	V=$(map_get SETMAP "${SETNAME}")
	if [[ -z $V ]]; then
		V=0
	fi
	V=$(( $V+1 ))
	map_put SETMAP "${SETNAME}" $V
done

#######################################################
OK=0
while [[ $OK -eq 0 ]]; do
CNT=0
for K in $(map_keys SETMAP); do
	CNT=$(( $CNT +1 ))
	V=$(map_get SETMAP "${K}")
	printf "%2d. Key: %s Number of Files: %s \n" $CNT "$K" "$V"
done

printf "\n"
read -p "Select dump file set number [0 to abort]: " N

# test if integer
if [ $N -eq $N 2>/dev/null ] && ! [ -z $N ]; then
if (( $N == 0 )); then
	exit 1
fi
if (( $N > 0 )) && (( $N <= $CNT )); then
	OK=$N
else
	printf "  invalid selection %s\n" "${N}"
fi
else
	printf "  invalid integer %s\n" "${N}"
fi
done

CNT=0
for K in $(map_keys SETMAP); do
	CNT=$(( $CNT +1 ))
	V=$(map_get SETMAP "${K}")
	if (( $CNT == $OK)); then
		DMPFILE="${K}%U.DMP"
	fi	
done
########################################################
PARFILETEXT=$(cat ${TEMPLATEFILE})
# process substitutions
PARFILETEXT=$(echo "${PARFILETEXT}" | perl -pi -e "s/\\$\{TS\}/${TS}/g")
PARFILETEXT=$(echo "${PARFILETEXT}" | perl -pi -e "s/\\$\{ODIR\}/${ODIR}/g")
PARFILETEXT=$(echo "${PARFILETEXT}" | perl -pi -e "s/\\$\{SID\}/${SID}/g")
PARFILETEXT=$(echo "${PARFILETEXT}" | perl -pi -e "s/\\$\{DMPFILE\}/${DMPFILE}/g")
########################################################
printf "\nPreparing for import on SID: %s \n" "${SID}"
printf "PARFILE contents:\n\n"
printf "%s\n\n" "${PARFILETEXT}"
# confirm
read -p "Enter YES to proceed: " OK
if [[ "${OK}" != "YES" ]] || [[ -z ${OK} ]]; then
	printf "Exiting.\n"
	exit 1
fi
########################################################
# create output dir
OUTDIR=${DPDIR}/imports/${SID}/${SID}_export_${TS} 
mkdir -p ${OUTDIR}
BNAME=$(basename "${TEMPLATEFILE}" | tr ' ' '_' |tr '.' '_')
PARFILE=${OUTDIR}/${BNAME}_${TS}.par
echo "${PARFILETEXT}" > ${PARFILE}
echo "Starting import data pump"
#######################################################
STARTTIME=$(date +%s)
impdp system/${PWD} parfile=${PARFILE} 
OK=$?
if [[ ! $OK = 0 ]]; then
	echo "Error: impdp failed!"
	rm -rfv ${OUTDIR}
	exit $OK
fi
ENDTIME=$(date +%s)
ETIMESEC=$[ $ENDTIME - $STARTTIME ]
ETIMESTR=$(convertsecs ${ETIMESEC})
TIMESTR=$(echo "Elapsed Time HH:MM:SS ${ETIMESTR}  Total Seconds: ${ETIMESEC}")
echo ${TIMESTR} > ${OUTDIR}/export_info_${TS}.txt
########################################################
echo "Completed import data pump"
echo "Moving output to  ${OUTDIR}"
mv -v ${DIRPATH}/*${TS}* ${OUTDIR}
########################################################
printf "\n\nSummary:\n"
echo ${TIMESTR}
echo "Work directory:  ${OUTDIR}"
########################################################
exit 0
