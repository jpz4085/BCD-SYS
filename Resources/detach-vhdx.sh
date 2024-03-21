#!/usr/bin/env bash

# detach-vhdx.sh - disconnect virtual disk and unload nbd module
# 
# Copyright (C) 2024 Joseph P. Zeller
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

rmnbdmod="false"

usage () {
echo "Usage: $(basename $0) [options] <device>"
echo
echo "<device>    	Block device to disconnect."
echo "-u, --unload	Unload the NBD kernel module."
exit
}

if   [[ $(uname) == "Linux" ]]; then
     if [[ $# -eq 0 ]]; then usage; fi

     shopt -s nocasematch
     while (( "$#" )); do
	     case "$1" in
	         -u | --unload )
	            rmnbdmod="true"
	            shift
	            ;;
	         * )
	           nbdpath="$1"
	           shift
	           ;;
	     esac
     done
     shopt -u nocasematch

     if  [[ ! -e "$nbdpath" ]]; then
         echo "Invalid device path: $nbdpath"
         exit 1
     else
         echo "Detach virtual disk (sudo required)..."
         sudo qemu-nbd -d "$nbdpath"
         if [[ "$rmnbdmod" == "true" ]]; then
            echo "Unload nbd kernel module..."
            sleep 1 && sudo rmmod nbd
         fi
     fi
elif [[ $(uname) == "Darwin" ]]; then
     echo "Use hdiutil to detach the virtual disk."
     exit
fi
