#!/bin/bash

DESCRIPTION="Check OS Release..."
SCRIPT_TYPE="parallel"

# Currently supported releases:
## https://docs.weka.io/support/prerequisites-and-compatibility

distro_not_found=0
version_not_found=0
unsupported_distro=0
unsupported_version=0
client_only=0

case $ID in
	'centos')
		case $VERSION_ID in
			'7.'[2-9]) ;;
			'8.'[0-5]) ;;
			'') version_not_found=1 ;;
			*) unsupported_version=1 ;;
		esac
		;;

	'rhel')
		case $VERSION_ID in 
			'7.'[2-9]) ;;
			'8.'[0-6]) ;;
			'') version_not_found=1 ;;
			*) unsupported_version=1 ;;
		esac
		;;

	'rocky')
		case $VERSION_ID in 
			'8.6') ;;
			'') version_not_found=1 ;;
			*) unsupported_version=1 ;;
		esac
		;;

	# SLES Service Packs are registered as point releases, i.e. SLES 12 SP5 becomes "12.5"
	'sles')
		case $VERSION_ID in
			'12.5') client_only=1 ;;
			'15.2') client_only=1 ;;
			'') version_not_found=1 ;;
			*) unsupported_version=1 ;;
		esac
		;;

	'ubuntu')
		case $VERSION_ID in
			'18.04.'[0-6]) ;;
			'20.04.'[0-3]) ;;
			'') version_not_found=1 ;;
			*) unsupported_version=1 ;;
		esac
		;;

	'') distro_not_found=1 ;;
	*) unsupported_distro=1 ;;
esac

if [ "$distro_not_found" -eq 1 ]; then
	write_log 'Distribution not found'
	exit 1
elif [ "$version_not_found" -eq 1 ]; then
	write_log "$NAME detected but version not found"
	exit 1
elif [ "$unsupported_distro" -eq 1 ]; then
	write_log "$NAME is not a supported distribution"
	exit 1
elif [ "$unsupported_version" -eq 1 ]; then
	write_log "$NAME $VERSION_ID is not a supported version of $NAME"
	exit 1
else
	if [ "$client_only" -eq 1 ]; then
		write_log "$NAME $VERSION_ID is supported (for client only)"
		exit 254
	else
		write_log "$NAME $VERSION_ID is supported"
		exit 0
	fi
fi
