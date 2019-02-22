#!/bin/bash

_args=$@
_required=("fold", "tr", "head", "cat", "xtrabackup", "pmm-admin", "pv")
XTRABACKUP="xtrabackup"
#PV="pv --bytes --numeric --interval=1 -L100K"
PV="pv --bytes --numeric --interval=1"
WAIT_TIME=5

base_regexp="^[[:digit:]]+ [[:digit:]]{2}:[[:digit:]]{2}:[[:digit:]]{2}";
copying_regexp="${base_regexp} \[([[:digit:]]+?)\] (Copying|Streaming) .\/([0-9a-zA-Z@.\-\/\_]+)"
done_regexp="${base_regexp} \[([[:digit:]]+?)\] .* ...done$"
log_scanned_regexp="${base_regexp} >> log scanned up to \(([[:digit:]]+?)\)"
declare -a out


[ -f /etc/default/pxb ] && source /etc/default/pxb

if [ -z "$PMM" ]; then
	echo "PMM address needs to be specified"
	exit 1;
fi;

_pxbArgs() {
	[[ "${_args}" =~ "$1" ]] && return;
	false;
}


_pxbInstr() {
	if [ -z "$4" ]; then
		echo "{\"value\": \"$2\", \"uuid\": \"$3\"}" | curl -XPUT -s -q --data-binary @- ${PMM}/api/v1/metric/$1/$3 2>&1 > /dev/null
	else
		echo "{\"value\": \"$2\", \"uuid\": \"$3\", \"u1\": \"$4\"}" | curl -XPUT -s -q --data-binary @- ${PMM}/api/v1/metric/$1/$3/$4 2>&1 > /dev/null

	fi
}


pxbResources() {

	_wait=1
	_maxwait=50 # 10 seconds

	while [ ${_wait} -gt 0 ]; do
		[ ${_wait} -gt ${_maxwait} ] && false

		#_ppid=$( pgrep -P $PPID )
		#[ -z "${_ppid}" ] && false

		pxbPID=$(pgrep -P $$ -f xtrabackup)

		[ ! -z "${pxbPID}" ] && _wait=0
		sleep 0.2
	done;

	procIO="/proc/${pxbPID}/io"

	while [ -f "${procIO}" ]; do
		_OLDIFS=$IFS

		IFS=$'\n';for line in $(<$procIO); do
			IFS=$_OLDIFS; _line=(${line/:})
			_pxbInstr "backup_${_line[0]}" "${_line[1]}" "$UUID"
		done;
		IFS=$_OLDIFS

		_ps=($( ps -o pmem,%cpu,rss,vsz  -p "${pxbPID}" --no-headers ))

		i=0
		for part in memory_percentage cpu_percentage rss vsz; do
			_pxbInstr "backup_${part}" "${_ps[$i]}" "$UUID"
			i=$(($i+1))
		done;

		sleep 1
	done;

}
INSTANCE="$(hostname)"


sighnldr() {
	echo "Terminated"
	kill ${_pxbResourcesPid} > /dev/null 2>&1
	
	date_stop_hr=$(date +%m.%d.%Y\_%H:%M\_%z)
	date_stop_epoch=$(date +%s000)

	_pxbInstr "backup" 3 "${UUID}" "${INSTANCE}"

	sleep $WAIT_TIME
	pmm-admin annotate "Backup finished (terminated)" > /dev/null	
}

trap sighnldr SIGINT SIGTERM

if _pxbArgs "--backup"; then

	if _pxbArgs "--inc"; then
		_TYPE="incremental"
	else
		_TYPE="full"
	fi

	if _pxbArgs "--stream"; then
		_STORE="stream"
	else
		_STORE="local"
	fi;

	UUID=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)

	pmm-admin annotate "Started ${_STORE} ${_TYPE} backup on ${INSTANCE}" > /dev/null

	#workaround for Grafana time rendering bug

	date_start_hr=$(date +%m.%d.%Y\_%H:%M\_%z)
	date_start_epoch=$(date +%s000)

	_pxbInstr "backup" 1 "${UUID}" "${INSTANCE}"

	# coproc monitoring
	# ps -o pmem,%cpu,rss,vsz  -p "$$" --no-headers
	# /proc/pid/io


	coproc $(pxbResources)
	_pxbResourcesPid=${COPROC_PID}
	tmpfile=$(mktemp)

	$XTRABACKUP $@ 2> >( 
		IFS=$'\n'; while read line; do 

		>&2 echo "$line";
		echo "$line" >> $tmpfile
		
		if [[ $line =~ $copying_regexp ]]; then
			threadNo=$((10#${BASH_REMATCH[1]}))
			out[$threadNo]="$( echo ${BASH_REMATCH[3]} | tr '/' '.')"

		fi;

		if [[ $line =~ $done_regexp ]]; then
			threadNo=$((10#${BASH_REMATCH[1]}))
			unset out[$((10#${BASH_REMATCH[1]}))]
		fi;

		if [[ $line =~ $log_scanned_regexp ]]; then
		  	_pxbInstr "backup_lsn" "${BASH_REMATCH[1]}" "${UUID}"
		fi;


		for out_ in ${!out[@]}; do
			_pxbInstr "backup_tables" ${out_} "${UUID}" "${out[$out_]}"
		done;


	done ) | {
		if [ "${_STORE}" == "stream" ]; then
			s1=0
			s2=0
			$PV 2>&1 1>&3 3>&- | while read speed; do 
				s2=${speed}
				_pxbInstr "backup_speed" "$(($s2-$s1))" "${UUID}" 
				s1=$s2
			done;
		fi;
	} 3>&1 1>&2

	#sleep 60
	sleep 1

	curl  -X POST --data-binary @$tmpfile $PMM/api/v1/blob/${UUID} -s -q >/dev/null 2>&1

else
	$XTRABACKUP $@
fi;

rc=$?


if [ "x$rc" == "x0" ]; then
	_pxbInstr "backup" 2 "${UUID}" "${INSTANCE}"
	pmm-admin annotate "Backup ${_STORE} ${_TYPE} finished successfully on ${INSTANCE}" > /dev/null
else
	_pxbInstr "backup" 3 "${UUID}" "${INSTANCE}"
	pmm-admin annotate "Backup ${_STORE} ${_TYPE} failed on ${INSTANCE}" > /dev/null
fi
kill ${_pxbResourcesPid} > /dev/null 2>&1

sleep $WAIT_TIME

echo "OK"