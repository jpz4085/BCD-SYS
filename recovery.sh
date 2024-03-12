#!/usr/bin/bash

# recovery.sh - windows recovery entries
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

destpath="$1"
createbcd="$2"
locale="$3"
resdir="."
recbcdpath="$destpath/EFI/Microsoft/Recovery/BCD"
locscript="cd Objects\\{9dea862c-5cdd-4e70-acc1-f32b344d4795}\\\Elements\\\12000005\nlsval Element\nunload\n"

if [[ "$createbcd" == "false" ]]; then
   wbmlocale=$(printf "$locscript" | sudo hivexsh "$recbcdpath")
fi

### Windows Boot Manager Entry ###
printf "cd \Objects\n"
printf "cd {9dea862c-5cdd-4e70-acc1-f32b344d4795}\n"
printf "cd Elements\n"
if [[ "$createbcd" == "true" ]]; then
   printf "cd 11000001\n"
   printf "setval 1\n"
   printf "Element\n"
   $resdir/update_device.sh "$destpath"
   printf "cd ..\n"
fi
if [[ "$createbcd" == "true" || "$wbmlocale" != "$locale" ]]; then
   printf "cd 12000005\n"
   printf "setval 1\n"
   printf "Element\n"
   printf "string:%s\n" "$locale"
   printf "commit\n"
fi
printf "unload\n"

