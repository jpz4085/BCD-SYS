#!/usr/bin/env bash

# bcd-sys.sh - main script
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

firmware="uefi"
setfwmod="false"
createbcd="true"
prewbmdef="false"
setwbmlast="false"
locale="en-us"
clean="false"
virtual="false"
rmsysmnt="false"
verbose="false"
resdir="."
tmpdir="."

RED='\033[1;31m'
BGTYELLOW='\033[1;93m'
NC='\033[0m' # No Color

# Show basic usage.
usage () {
echo "Usage: $(basename $0) <source> [options] <system>"
echo
echo "<source>	  Path to Windows volume or VHDX file."
echo "<system>	  Mount point of the system partition."
echo
echo "-h, --help        Display full usage information."
exit 1
}

# Show full help.
help () {
echo "Usage: $(basename $0) <source> [options] <system>"
echo
cat $resdir/Resources/help-page.txt
echo
exit
}

endian () {
v=$1
i=${#v}

while [ $i -gt 0 ]
do
    i=$[$i-2]
    echo -n ${v:$i:2}
done
echo
}

# Remove existing boot loader and resume entries for matching device (11000001).
remove_duplicates () {
if   [[ "$3" == "uefi" ]]; then
     bcdpath="$2/EFI/Microsoft/Boot/BCD"
elif [[ "$3" == "bios" ]]; then
     bcdpath="$2/Boot/BCD"
fi
if   [[ "$virtual" == "true" ]]; then
     newdevstr=$($resdir/update_device.sh "$4" "$1" "$5" | sed 's/.*://;')
elif [[ "$virtual" == "false" ]]; then
     newdevstr=$($resdir/update_device.sh "$1" | sed 's/.*://;')
fi
newdevstr=${newdevstr,,}
ordscript="cd Objects\\{9dea862c-5cdd-4e70-acc1-f32b344d4795}\\\Elements\\\24000001\n"
rldrscript="cd Objects\\{9dea862c-5cdd-4e70-acc1-f32b344d4795}\\\Elements\\\23000006\n"

readarray -t objects <<< $(printf "cd Objects\nls\nq\n" | hivexsh "$bcdpath")

for key in "${!objects[@]}"
do
	curdevstr=$(printf "cd Objects\\${objects[$key]}\\\Elements\\\11000001\nlsval\nq" | hivexsh "$bcdpath" 2> /dev/null | sed 's/.*://;')
	if [[ "$curdevstr" == "$newdevstr" ]]; then
	   if [[ "$verbose" == "true" ]]; then echo "Remove entry at ${objects[$key]}"; fi
	   printf "cd Objects\\${objects[$key]}\ndel\ncommit\nunload\n" | hivexsh -w "$bcdpath"
	   wbmdsporder=$(printf "$ordscript""lsval\nunload\n" | hivexsh "$bcdpath" | sed 's/.*://;s/,//g')
	   guidstr=$(printf '%s\0' "${objects[$key]}" | hexdump -ve '/1 "%02x\0\0"')
	   if [[ "$wbmdsporder" == *"$guidstr"* ]]; then
	      if [[ "$verbose" == "true" ]]; then echo "Remove ${objects[$key]} from WBM display order."; fi
	      newdsporder=$(printf "%s" "$wbmdsporder" | sed "s/$guidstr//")
	      printf "$ordscript""setval 1\nElement\nhex:7:%s\ncommit\nunload\n" "$newdsporder" | hivexsh -w "$bcdpath"
	   fi
	   wbmresldr=$(printf "$rldrscript""lsval\nunload\n" | hivexsh "$bcdpath" | sed 's/.*=//;s/"//g')
	   if [[ "$wbmresldr" == "${objects[$key]}" ]]; then
	      if [[ "$verbose" == "true" ]]; then echo "Remove ${objects[$key]} from WBM resume object."; fi
	      printf "$rldrscript""setval 0\ncommit\nunload\n" | hivexsh -w "$bcdpath"
	   fi	   
	fi
done
}

# Build main and recovery stores using blank BCD-NEW file and reg templates.
build_stores () {
if [[ "$verbose" == "true" ]]; then echo "Build the main BCD store..."; fi
$resdir/winload.sh "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "${10}" "${11}" "${12}" > $tmpdir/winload.txt
cp $resdir/Templates/BCD-NEW $tmpdir/BCD-Windows
hivexregedit --merge --prefix BCD00000001 $tmpdir/BCD-Windows $resdir/Templates/winload.reg
hivexsh -w -f $tmpdir/winload.txt $tmpdir/BCD-Windows
if   [[ "$3" == "uefi" ]]; then
     if [[ "$verbose" == "true" ]]; then echo "Build the recovery BCD store..."; fi
     $resdir/recovery.sh "$2" "$5" "$8" > $tmpdir/recovery.txt
     cp $resdir/Templates/BCD-NEW $tmpdir/BCD-Recovery
     hivexregedit --merge --prefix BCD00000001 $tmpdir/BCD-Recovery $resdir/Templates/recovery.reg
     hivexsh -w -f $tmpdir/recovery.txt $tmpdir/BCD-Recovery
     if [[ "$verbose" == "true" ]]; then echo "Copy the BCD hives to the ESP folders..."; fi
     cp $tmpdir/BCD-Windows "$2"/EFI/Microsoft/Boot/BCD
     cp $tmpdir/BCD-Recovery "$2"/EFI/Microsoft/Recovery/BCD
elif [[ "$3" == "bios" ]]; then
     if [[ "$verbose" == "true" ]]; then echo "Copy the main BCD hive to the boot folder..."; fi
     cp $tmpdir/BCD-Windows "$2"/Boot/BCD
fi
}

# Build new Windows entry and update existing BCD stores.
update_winload () {
remove_duplicates "$1" "$2" "$3" "${11}" "${12}"
if [[ "$verbose" == "true" ]]; then echo "Update main BCD hive with new entries..."; fi
$resdir/winload.sh "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "${10}" "${11}" "${12}" > $tmpdir/winload.txt
if   [[ "$3" == "uefi" ]]; then
     hivexsh -w -f $tmpdir/winload.txt "$2/EFI/Microsoft/Boot/BCD"
     if [[ "$verbose" == "true" ]]; then echo "Update recovery BCD hive with new entries..."; fi
     $resdir/recovery.sh "$2" "$5" "$8" > $tmpdir/recovery.txt
     hivexsh -w -f $tmpdir/recovery.txt "$2/EFI/Microsoft/Recovery/BCD" 
elif [[ "$3" == "bios" ]]; then
     hivexsh -w -f $tmpdir/winload.txt "$2/Boot/BCD"
fi
}

# Copy the WBM files for the specified firmware and set the file attributes the same as bcdboot.
copy_bootmgr () {
if   [[ "$3" == "uefi" ]]; then
     if [[ "$verbose" == "true" ]]; then echo "Copy the EFI boot files to the ESP..."; fi
     mkdir -p "$2"/EFI/Microsoft/Recovery
     cp -r "$1"/Windows/Boot/EFI "$2"/EFI/Microsoft/Boot
     cp -r "$1"/Windows/Boot/Fonts "$2"/EFI/Microsoft/Boot
     cp -r "$1"/Windows/Boot/Resources "$2"/EFI/Microsoft/Boot
elif [[ "$3" == "bios" ]]; then
     if [[ "$verbose" == "true" ]]; then echo "Copy the BIOS boot files to the system partition..."; fi
     cp -r "$1"/Windows/Boot/PCAT "$2"/Boot
     cp -r "$1"/Windows/Boot/Fonts "$2"/Boot
     cp -r "$1"/Windows/Boot/Resources "$2"/Boot
     mv "$2"/Boot/bootmgr "$2" && mv "$2"/Boot/bootnxt "$2"/BOOTNXT
     # Only MS-DOS, Tuxera and NTFS-3G file system attributes supported.
     if [[ "$4" == "NTFS" ]]; then
        if [[ "$verbose" == "true" ]]; then echo "Set extended NTFS attributes (Hidden/System/Read Only)..."; fi
        if   [[ "$sysfsvendor" == "Tuxera" ]]; then
             tntfs setflags "$2"/bootmgr hidden=1 system=1 readonly=1
             tntfs setflags "$2"/BOOTNXT hidden=1 system=1
             tntfs setflags "$2"/Boot hidden=1 system=1
        elif [[ ! -z $(command -v ntfs-3g) ]]; then
             xattr -wx system.ntfs_attrib_be 00000027 "$2"/bootmgr
             xattr -wx system.ntfs_attrib_be 00000026 "$2"/BOOTNXT
             xattr -wx system.ntfs_attrib_be 00000006 "$2"/Boot
        fi
     fi
     if [[ "$4" == "MS-DOS" ]]; then
        if [[ "$verbose" == "true" ]]; then echo "Set filesystem attributes (Hidden/System/Read Only)..."; fi
        mtoolscfg="/tmp/mtools-bcdsys"
        export MTOOLSRC=$mtoolscfg
        echo "drive s: file=\"$syspart\"" > $mtoolscfg
        echo "mtools_skip_check=1" >> $mtoolscfg
        diskutil unmount $syspart > /dev/null
        sudo -E mattrib +s +h +r S:/bootmgr
        sudo -E mattrib +s +h S:/BOOTNXT
        sudo -E mattrib +s +h S:/Boot
        diskutil mount $syspart > /dev/null
     fi
fi
}

# Used when no syspath is specified in the arguments.
# Look for an ESP or active primary partition on the Windows disk.
# The startup disk should always be GPT/UEFI scheme under macOS.
get_syspath () {
firmware="$1"
windisk="$2"

if   [[ "$firmware" == "uefi" ]]; then
     echo "Checking block devices for ESP (sudo required)..."
     if [[ "$wptscheme" == "FDisk_partition_scheme" ]]; then
        checkmbr_signature $windisk
     fi
     if [[ "$virtual" == "true" && "$vptscheme" == "FDisk_partition_scheme" ]]; then
        checkmbr_signature $vrtdisk
     fi
     efipart=$(diskutil list "$windisk" | grep "EFI" | awk '{print $NF}')
     if [[ -z "$efipart" ]]; then
        rootfstype=$(diskutil info / | grep "Type (Bundle):" | awk '{print $NF}')
        if   [[ "$rootfstype" == "apfs" ]]; then
             macdisk=$(diskutil info / | grep "APFS Physical Store:" | awk '{print $NF}' | sed 's/s[0-9]*$//')
        elif [[ "$rootfstype" == "hfs" ]]; then
             macdisk=$(diskutil info / | grep "Part of Whole:" | awk '{print $NF}')
        fi
        efipart=$(diskutil list $macdisk | grep "EFI" | awk '{print $NF}')
        if [[ ! -z "$efipart" && ! -z $(csrutil status | grep "Filesystem Protections: enabled") ||
              ! -z $(csrutil status | grep -Fx "System Integrity Protection status: enabled.") ]]; then
           if [[ "$virtual" == "true" ]]; then umount_vpart; fi
           echo "No ESP found on the Windows media ($windisk)"
           echo -e "${RED}Unable to get device information from startup disk.${NC}"
           echo "Disable SIP filesystem protections or specify a system volume."
           exit 1
        fi
     fi
     if [[ -z "$efipart" ]]; then
        echo -e "${RED}Unable to locate ESP on $windisk or /dev/$macdisk.${NC}"
        echo "Use the --syspath option to specify a volume."
        if [[ "$virtual" == "true" ]]; then umount_vpart; fi
        exit 1
     fi
     efifsvendor=$(diskutil info $efipart | grep "File System Personality:" | awk '{print $(NF - 1)}')
     efifstype=$(diskutil info $efipart | grep "File System Personality:" | awk '{print $NF}')
     syspath=$(diskutil info $efipart | grep "Mount Point:" | awk -v n=3 '{ for (i=n; i<=NF; i++) printf "%s%s", $i, (i<NF ? OFS : ORS)}')
     if   [[ -z "$syspath" ]]; then
          if [[ "$verbose" == "true" ]]; then echo "Mounting ESP on $efipart"; fi
          rmsysmnt="true"
          if   [[ "$efifsvendor" == "MS-DOS" || "$efifsvendor" == "Tuxera" || "$efifstype" == "UFSD_NTFS" ]]; then
               sudo diskutil mount $efipart > /dev/null
          elif [[ "$efifstype" == "NTFS" ]]; then
               if   [[ ! -z $(command -v ntfs-3g) ]]; then
                    mount_ntfs3g $efipart
               else
                    echo -e "${BGTYELLOW}NTFS write support required to access $efipart${NC}"
               fi
          fi
          syspath=$(diskutil info $efipart | grep "Mount Point:" | awk -v n=3 '{ for (i=n; i<=NF; i++) printf "%s%s", $i, (i<NF ? OFS : ORS)}')
          espvolronly=$(diskutil info $efipart | grep "Volume Read-Only:" | awk '{print $3}')
          if [[ -z "$syspath" || "$espvolronly" == "Yes" ]]; then
               echo -e "${RED}Unable to mount ESP for write access.${NC}"
               if [[ "$virtual" == "true" ]]; then umount_vpart; fi
               exit 1
          fi
     elif [[ ! -z "$syspath" && "$efifstype" == "NTFS" ]]; then
          espvolronly=$(diskutil info $efipart | grep "Volume Read-Only:" | awk '{print $3}')
          if [[ "$espvolronly" == "Yes" ]]; then
             rmsysmnt="true"
             diskutil unmount $efipart > /dev/null
             if   [[ "$efifsvendor" == "Tuxera" || "$efifstype" == "UFSD_NTFS" ]]; then
                  sudo diskutil mount $efipart > /dev/null
             elif [[ ! -z $(command -v ntfs-3g) ]]; then
                  mount_ntfs3g $efipart
             else
                  echo -e "${BGTYELLOW}NTFS write support required to access $efipart${NC}"
             fi
             syspath=$(diskutil info $efipart | grep "Mount Point:" | awk -v n=3 '{ for (i=n; i<=NF; i++) printf "%s%s", $i, (i<NF ? OFS : ORS)}')
             espvolronly=$(diskutil info $efipart | grep "Volume Read-Only:" | awk '{print $3}')
             if [[ -z "$syspath" || "$espvolronly" == "Yes" ]]; then
                echo -e "${RED}Unable to remount ESP for write access.${NC}"
                if [[ "$virtual" == "true" ]]; then umount_vpart; fi
                exit 1
             fi
          fi
     fi
elif [[ "$firmware" == "bios" || "$firmware" == "both" ]]; then
     echo "Checking block devices for active partition (sudo required)..."
     if [[ "$wptscheme" == "FDisk_partition_scheme" ]]; then
        checkmbr_signature $windisk
        actpnum=$(sudo fdisk "$windisk" | grep -E '\*[0-9]' | awk '{print $1}' | sed 's/\*//;s/\://')
        if [[ ! -z "$actpnum" ]]; then
           syspart="$windisk"s"$actpnum"
        fi
     elif [[ "$wptscheme" == "GUID_partition_scheme" ]]; then
        echo -e "${BGTYELLOW}Windows disk $windisk is using GPT partition scheme.${NC}"
     fi
     if [[ "$virtual" == "true" && "$vptscheme" == "FDisk_partition_scheme" ]]; then
        checkmbr_signature $vrtdisk
     fi
     # Don't bother checking the startup disk for an active partition that shouldn't exist.
     if [[ -z "$syspart" ]]; then
        echo -e "${RED}No active partition found on the Windows media.${NC}"
        echo "Use the --syspath option to specify a volume."
        if [[ "$virtual" == "true" ]]; then umount_vpart; fi
        exit 1
     fi
     sysfsvendor=$(diskutil info $syspart | grep "File System Personality:" | awk '{print $(NF - 1)}')
     sysfstype=$(diskutil info $syspart | grep "File System Personality:" | awk '{print $NF}')
     syspath=$(diskutil info $syspart | grep "Mount Point:" | awk -v n=3 '{ for (i=n; i<=NF; i++) printf "%s%s", $i, (i<NF ? OFS : ORS)}')
     if   [[ -z "$syspath" ]]; then
          if [[ "$verbose" == "true" ]]; then echo "Mounting active partition on $syspart"; fi
          rmsysmnt="true"
          if   [[ "$sysfsvendor" == "MS-DOS" || "$sysfsvendor" == "Tuxera" || "$sysfstype" == "UFSD_NTFS" ]]; then
               diskutil mount $syspart > /dev/null
          elif [[ "$sysfstype" == "NTFS" ]]; then
               if   [[ ! -z $(command -v ntfs-3g) ]]; then
                    mount_ntfs3g $syspart
               else
                    echo -e "${BGTYELLOW}NTFS write support required to access $syspart${NC}"
               fi
          fi
          syspath=$(diskutil info $syspart | grep "Mount Point:" | awk -v n=3 '{ for (i=n; i<=NF; i++) printf "%s%s", $i, (i<NF ? OFS : ORS)}')
          sysvolronly=$(diskutil info $syspart | grep "Volume Read-Only:" | awk '{print $3}')
          if [[ -z "$syspath" || "$sysvolronly" == "Yes" ]]; then
               echo -e "${RED}Unable to mount active partition for write access.${NC}"
               if [[ "$virtual" == "true" ]]; then umount_vpart; fi
               exit 1
          fi
     elif [[ ! -z "$syspath" && "$sysfstype" == "NTFS" ]]; then
          sysvolronly=$(diskutil info $syspart | grep "Volume Read-Only:" | awk '{print $3}')
          if  [[ "$sysvolronly" == "Yes" ]]; then
              rmsysmnt="true"
              diskutil unmount $syspart > /dev/null
              if   [[ "$sysfsvendor" == "Tuxera" || "$sysfstype" == "UFSD_NTFS" ]]; then
                   diskutil mount $syspart > /dev/null
              elif [[ ! -z $(command -v ntfs-3g) ]]; then
                   mount_ntfs3g $syspart
              else
                   echo -e "${BGTYELLOW}NTFS write support required to access $syspart${NC}"
              fi
              syspath=$(diskutil info $syspart | grep "Mount Point:" | awk -v n=3 '{ for (i=n; i<=NF; i++) printf "%s%s", $i, (i<NF ? OFS : ORS)}')
              sysvolronly=$(diskutil info $syspart | grep "Volume Read-Only:" | awk '{print $3}')
              if [[ -z "$syspath" || "$sysvolronly" == "Yes" ]]; then
                 echo -e "${RED}Unable to remount active partition for write access.${NC}"
                 if [[ "$virtual" == "true" ]]; then umount_vpart; fi
                 exit 1
              fi
          fi
     fi
     if [[ "$firmware" == "both" ]]; then
        efipart="$syspart"
        efifsvendor="$sysfsvendor"
        efifstype="$sysfstype"
     fi
fi
}

# Used when a syspath is provided in the arguments.
# Find the block device (and active partition if BIOS/BOTH) for the specified mount point.
get_device () {
firmware="$1"
syspath="$2"

if   [[ "$firmware" == "uefi" ]]; then
     echo "Get block device for mount point (sudo required)..."
     if [[ "$wptscheme" == "FDisk_partition_scheme" ]]; then
        checkmbr_signature $windisk
     fi
     if [[ "$virtual" == "true" && "$vptscheme" == "FDisk_partition_scheme" ]]; then
        checkmbr_signature $vrtdisk
     fi
     efipart=$(diskutil info "$(basename "$syspath")" | grep "Device Node:" | awk '{print $3}')
     efidisk=$(printf "$efipart" | sed 's/s[0-9]*$//')
     if [[ "$efidisk" != "$windisk" ]]; then
        sptscheme=$(diskutil info $efidisk | grep "Content (IOContent):" | awk '{print $3}')
        if [[ "$sptscheme" == "FDisk_partition_scheme" ]]; then checkmbr_signature $efidisk; fi
     fi
     efifsvendor=$(diskutil info $efipart | grep "File System Personality:" | awk '{print $(NF - 1)}')
     efifstype=$(diskutil info $efipart | grep "File System Personality:" | awk '{print $NF}')
     if [[ "$efifstype" == "NTFS" ]]; then
        espvolronly=$(diskutil info $efipart | grep "Volume Read-Only:" | awk '{print $3}')
        if  [[ "$espvolronly" == "Yes" && ! -z $(command -v ntfs-3g) ]]; then
            rmsysmnt="true"
            diskutil unmount $efipart > /dev/null
            mount_ntfs3g $efipart
        else
            echo -e "${BGTYELLOW}NTFS write support required to access $efipart${NC}"
            echo -e "${RED}Please remount ESP for write access.${NC}"
            if [[ "$virtual" == "true" ]]; then umount_vpart; fi
            exit 1
        fi
     fi
elif [[ "$firmware" == "bios" || "$firmware" == "both" ]]; then
     syspart=$(diskutil info "$(basename "$syspath")" | grep "Device Node:" | awk '{print $3}')
     sysdisk=$(printf "$syspart" | sed 's/s[0-9]*$//')
     echo "Checking block device for active partition (sudo required)..."
     if [[ "$wptscheme" == "FDisk_partition_scheme" ]]; then
        checkmbr_signature $windisk
     fi
     if [[ "$virtual" == "true" && "$vptscheme" == "FDisk_partition_scheme" ]]; then
        checkmbr_signature $vrtdisk
     fi
     if [[ "$sysdisk" != "$windisk" ]]; then
        sptscheme=$(diskutil info $sysdisk | grep "Content (IOContent):" | awk '{print $3}')
        if [[ "$sptscheme" == "FDisk_partition_scheme" ]]; then checkmbr_signature $sysdisk; fi
     fi
     actpnum=$(sudo fdisk "$sysdisk" | grep -E '\*[0-9]' | awk '{print $1}' | sed 's/\*//;s/\://')
     if [[ -z "$actpnum" ]]; then
        echo -e "${RED}No active partition on $sysdisk.${NC}"
        if [[ "$virtual" == "true" ]]; then umount_vpart; fi
        exit 1
     fi
     actpart="$sysdisk"s"$actpnum"
     if [[ "$syspart" != "$actpart" ]]; then
        echo -e "${RED}The volume $syspath on $syspart is not the active partition.${NC}"
        if [[ "$virtual" == "true" ]]; then umount_vpart; fi
        exit 1
     fi
     sysfsvendor=$(diskutil info $syspart | grep "File System Personality:" | awk '{print $(NF - 1)}')
     sysfstype=$(diskutil info $syspart | grep "File System Personality:" | awk '{print $NF}')
     if [[ "$sysfstype" == "NTFS" ]]; then
        sysvolronly=$(diskutil info $syspart | grep "Volume Read-Only:" | awk '{print $3}')
        if  [[ "$sysvolronly" == "Yes" && ! -z $(command -v ntfs-3g) ]]; then
            rmsysmnt="true"
            diskutil unmount $syspart > /dev/null
            mount_ntfs3g $syspart
        else
            echo -e "${BGTYELLOW}NTFS write support required to access $syspart${NC}"
            echo -e "${RED}Please remount active partition for write access.${NC}"
            if [[ "$virtual" == "true" ]]; then umount_vpart; fi
            exit 1
        fi
     fi
     if [[ "$firmware" == "both" ]]; then
        efipart="$syspart"
        efifsvendor="$sysfsvendor"
        efifstype="$sysfstype"
     fi
fi
}

# Find sector offset of the first payload block and attach virtual disk.
# Get partition scheme then display partitions and mount the specified volume.
attach_vdisk () {
offsetbat=$(endian $(xxd -ps -s 196640 -l 8 "$imgpath"))
offsetmeta=$(endian $(xxd -ps -s 196672 -l 8 "$imgpath"))
metaentries=$(endian $(xxd -ps -s "$((0x$offsetmeta + 0xA))" -l 2 "$imgpath"))
blockzero=$(endian $(xxd -ps -s "0x$offsetbat" -l 8 "$imgpath" | sed 's/^\([0-9]\)[0-7]/\10/'))
offmetavdisk=$(xxd -c 32 -s "$((0x$offsetmeta + 0x20))" -l "$((0x20 * 0x$metaentries))" "$imgpath" | grep '2442 a52f 1bcd 7648 b211 5dbe d83b f4b8' | awk '{print $1}' | sed 's/://')
offmetalsect=$(xxd -c 32 -s "$((0x$offsetmeta + 0x20))" -l "$((0x20 * 0x$metaentries))" "$imgpath" | grep '1dbf 4181 6fa9 0947 ba47 f233 a8fa ab5f' | awk '{print $1}' | sed 's/://')
offvdisksz=$(endian $(xxd -ps -s "$((0x$offmetavdisk + 0x10))" -l 4 "$imgpath"))
offlsectsz=$(endian $(xxd -ps -s "$((0x$offmetalsect + 0x10))" -l 4 "$imgpath"))
vdisksize=$(endian $(xxd -ps -s "$((0x$offvdisksz + 0x$offsetmeta))" -l 8 "$imgpath"))
lsectsize=$(endian $(xxd -ps -s "$((0x$offlsectsz + 0x$offsetmeta))" -l 4 "$imgpath"))
offsetimage=$((0x$blockzero / 0x$lsectsize))
filesize=$(stat -f %z "$imgpath")

if   [[ $filesize -lt 0x$vdisksize ]]; then
     echo "Virtual disk size is greater than the image file."
     echo "Dynamically expanding VHDX files are not supported."
     exit 1
else
     vrtdisk=$(hdiutil attach -nomount -imagekey diskimage-class=CRawDiskImage -section $offsetimage "$imgpath" | head -n 1 | awk '{print $1}')
     vptscheme=$(diskutil info $vrtdisk | grep "Content (IOContent):" | awk '{print $3}')
fi

echo "Partition table on: $imgpath"
echo
diskutil list $vrtdisk | tail -n +2
echo
read -p "Enter device containing the Windows volume [disk#s#]:" vtwinpart
while [[ "$vtwinpart" != *"disk"* || ! -e "/dev/$vtwinpart" ]]; do
      echo -e "${BGTYELLOW}Invalid partition specified. Please try again.${NC}"
      read -p "Enter device containing the Windows volume [disk#s#]:" vtwinpart
done
diskutil mount $vtwinpart > /dev/null && sleep 1
vrtpath=$(diskutil info $vtwinpart | grep "Mount Point:" | awk -v n=3 '{ for (i=n; i<=NF; i++) printf "%s%s", $i, (i<NF ? OFS : ORS)}')
}

# Unmount volume and detach virtual disk.
umount_vpart () {
if [[ "$verbose" == "true" ]]; then echo "Unmount volume and detach virtual disk..."; fi
hdiutil detach $vrtdisk > /dev/null
}

# Mount a Windows volume using NTFS-3G if available.
# Mount options support Windows extended attributes only and dot file are hidden.
mount_ntfs3g () {
volname=$(sudo ntfslabel $1 2>&1 | head -n 1)
userid=$(id | awk '{print $1}' | cut -f1 -d'(')
groupid=$(id | awk '{print $2}' | cut -f1 -d'(')

if [[ "$verbose" == "true" ]]; then echo "Mount $1 using ntfs-3g..."; fi
sudo ntfs-3g -ovolname="$volname",local,streams_interface=openxattr,hide_dot_files,noapplexattr \
             -onoappledouble,windows_names,$userid,$groupid,allow_other $1 /Volumes/"$volname"
}

# Unmount the EFI or Windows System Partition mounted automatically by get_syspath.
umount_system () {
if   [[ "$firmware" == "uefi" ]]; then
     if [[ "$verbose" == "true" ]]; then echo "Unmounting the EFI System Partition..."; fi
     diskutil unmount $efipart > /dev/null
else
     if [[ "$verbose" == "true" ]]; then echo "Unmounting the Windows System Partition..."; fi
     diskutil unmount $syspart > /dev/null
fi
}

# Check for a Windows Disk Signature on the target disk when using MBR partition scheme.
checkmbr_signature () {
sigbytes=$(sudo xxd -u -p -s 440 -l 4 "$1")
if [[ "$sigbytes" == "00000000" || -z "$sigbytes" ]]; then
   if [[ "$virtual" == "true" ]]; then umount_vpart; fi
   if [[ "$1" == "$windisk" ]]; then target="Windows"; fi
   if [[ "$1" == "$efidisk" || "$1" == "$sysdisk" ]]; then target="system"; fi
   if [[ "$1" == "$vrtdisk" ]]; then target="virtual"; fi
   echo -e "${RED}No disk signature found on the $target disk.${NC}"
   echo "Create a Windows Disk Signature using signmbr or ms-sys."
   exit 1
fi
}

# Check for the WBM in the current firmware boot options.
get_wbmoption () {
wbmoptnum=$(bootoption list | grep "Windows Boot Manager" | awk '{print $2}' | sed 's/Boot//')
}

# Update the WBM firmware option and device data in the BCD entry.
create_wbmfwvar () {
if [[ "$verbose" == "true" ]]; then echo "Update main BCD with current WBM firmware variable..."; fi
$resdir/wbmfwvar.sh $1 > $tmpdir/wbmfwvar.txt
hivexsh -w -f $tmpdir/wbmfwvar.txt "$2/EFI/Microsoft/Boot/BCD"
}

# Remove hivexsh scripts and BCD files created during the build process.
cleanup () {
if [[ "$verbose" == "true" ]]; then echo "Clean up temporary files..."; fi
rm -f $tmpdir/winload.txt $tmpdir/recovery.txt $tmpdir/wbmfwvar.txt $tmpdir/BCD-Windows $tmpdir/BCD-Recovery $mtoolscfg
}

requirements_message () {
if [[ ! -z "$missing" ]]; then
   echo "The following packages are required: $missing"
   exit 1
fi
}

# Script starts here.
if [[ $(uname) != "Darwin" ]]; then echo "Unsupported platform detected."; exit 1; fi

if [[ $# -eq 0 ]]; then
usage
fi

bashver=$(bash --version | head -n 1 | awk '{print $4}' | cut -f1 -d'(')

# Check for required packages that are missing.
if [ "$(printf '%s\n' "3.2.57" "$bashver" | sort -rV | head -n1)" == "3.2.57" ]; then missing+=" bash(>$bashver)"; fi
if [[ -z $(command -v hivexsh) ]]; then missing+=" hivex"; fi
if [[ -z $(command -v hivexregedit) ]]; then missing+=" hivexregedit"; fi
if [[ -z $(command -v mtools) ]]; then missing+=" mtools"; fi
if [[ -z $(command -v peres) ]]; then missing+=" pev/peres"; fi
if [[ -z $(command -v xxd) ]]; then missing+=" xxd"; fi
requirements_message

# Create symlinks to Resources and Templates folder if needed.
if [[ "$resdir" == "." ]]; then
   if [[ ! -d "$resdir/Resources" && ! -d "$resdir/Templates" ]]; then
      ln -s ../Resources && ln -s ../Templates
   fi
fi

shopt -s nocasematch
while (( "$#" )); do
	case "$1" in
	    -f | --firmware )
	       shift
	       firmware="$1"
	       firmware=${firmware,,}
	       shift
	       ;;
	    -s | --syspath )
	       shift
	       syspath=$(echo "$1"| sed 's/\/*$//')
	       setfwmod="true"
	       shift
	       ;;
	    -d | --wbmdefault )
	       prewbmdef="true"
	       shift
	       ;;
	    -n | --prodname )
	       shift
	       prodname="$1"
	       shift
	       ;;
	    -l | --locale )
	       shift
	       locale="$1"
	       locale=${locale,,}
	       shift
	       ;;
	    -e | --addtoend )
	       setwbmlast="true"
	       shift
	       ;;
	    -v | --verbose )
	       verbose="true"
	       shift
	       ;;
	    -c | --clean )
	       clean="true"
	       shift
	       ;;
	    -h | --help )
	       help
	       ;;
	    * )
	       winpath=$(echo "$1"| sed 's/\/\+$//')
	       shift
	       ;;
	esac
done
shopt -u nocasematch

# Check if source is a virtual disk file.
if [[ "$winpath" == *".vhdx"* && -f "$winpath" ]];then
   virtual="true"
   imgpath="$winpath"
   attach_vdisk
fi

# Check source for path to the WBM files then get the block device.
# Get the mount point, file path and block device that contains the virtual disk file.
if   [[ -d "$winpath/Windows/Boot" ]]; then
     windisk=$(diskutil info "$(basename "$winpath")" | grep "Device Node:" | awk '{print $3}' | sed 's/s[0-9]*$//')
elif [[ "$virtual" == "true" && -d "$vrtpath/Windows/Boot" ]]; then
     winpath=$(echo "$winpath" | cut -d/ -f1-3)
     windisk=$(diskutil info "$(basename "$winpath")" | grep "Device Node:" | awk '{print $3}' | sed 's/s[0-9]*$//')
     imgstring=$(echo "$imgpath" | cut -d/ -f4- | sed 's/^/\\/;s/\//\\/g')
else
    echo -e "${RED}Invalid source path please try again.${NC}"
    if  [[ "$virtual" == "true" ]]; then umount_vpart; fi
    exit 1
fi

# Get the partition scheme of media containing a Windows installation or VHDX file.
wptscheme=$(diskutil info $windisk | grep "Content (IOContent):" | awk '{print $3}')

# Perform the actions appropriate for the specified firmware type.
# Compare the WBM product versions of the source and system volumes.
# Copy the boot files if missing or older than the source version.
# Create new BCD stores or update existing ones with new entries.
# Create a WBM firmware entry in the first or last position when needed.
# Unmount the virtual disk and remove the temporary hive scripts/files.
if  [[ "$firmware" != "uefi" && "$firmware" != "bios" && "$firmware" != "both" ]]; then
    echo -e "${RED}Unsupport firmware: Only UEFI, BIOS or BOTH.${NC}"
    if  [[ "$virtual" == "true" ]]; then umount_vpart; fi
    exit 1
else
    if [[ "$firmware" == "uefi" || "$firmware" == "both" ]]; then
       if  [[ -z "$syspath" ]]; then
           get_syspath "$firmware" "$windisk"
       elif [[ ! -z "$syspath" && -d "$syspath" ]]; then
            get_device "$firmware" "$syspath"
       else
            echo -e "${RED}Invalid ESP path please try again.${NC}"
            if  [[ "$virtual" == "true" ]]; then umount_vpart; fi
            exit 1
       fi
       fwmode="uefi"
       efibootvars="false"
       defbootpath="$syspath/EFI/BOOT/BOOTX64.efi"
       syswbmpath="$syspath/EFI/Microsoft/Boot/bootmgfw.efi"
       if  [[ "$virtual" == "true" ]]; then
           localwbmpath="$vrtpath/Windows/Boot/EFI/bootmgfw.efi"
       else
           localwbmpath="$winpath/Windows/Boot/EFI/bootmgfw.efi"
       fi
       if [[ "$efifsvendor" != "MS-DOS" ]]; then
          echo "Partition at $efipart is $efifstype format."
          if  [[ "$efifstype" == "NTFS" || "$efifstype" == "UFSD_NTFS" ]]; then
              echo -e "${BGTYELLOW}Disk may not be UEFI bootable on all systems.${NC}"
          else
              echo -e "${RED}ESP must be FAT or NTFS format.${NC}"
              if [[ "$virtual" == "true" ]]; then umount_vpart; fi
              if [[ "$rmsysmnt" == "true" ]]; then umount_system; fi
              exit 1
          fi
       fi
       if [[ -f "$defbootpath" ]]; then
          defbootver=$(peres -v "$defbootpath" 2> /dev/null | grep 'Product Version:' | awk '{print $3}')
       fi
       if [[ -f "$syswbmpath" && -f "$localwbmpath" ]]; then
          syswbmver=$(peres -v "$syswbmpath" 2> /dev/null | grep 'Product Version:' | awk '{print $3}')
          localwbmver=$(peres -v "$localwbmpath" 2> /dev/null | grep 'Product Version:' | awk '{print $3}')
       fi
       if [[ ! -z $(command -v bootoption) && ! -z $(csrutil status | grep "NVRAM Protections: disabled") ]]; then
          get_wbmoption && efibootvars="true"
          wbmefipath="$syspath/EFI/Microsoft/Boot/bootmgfw.efi"
       fi
       if   [[ ! -f "$localwbmpath" ]]; then
            if  [[ "$virtual" == "true" ]]; then
                echo -e "${RED}Unable to find the EFI boot files at $vrtpath${NC}"
                umount_vpart
            else
                echo -e "${RED}Unable to find the EFI boot files at $winpath${NC}"
            fi
            if [[ "$rmsysmnt" == "true" ]]; then umount_system; fi
            exit 1
       elif [[ ! -f "$syswbmpath" ]]; then
            if  [[ "$virtual" == "true" ]]; then
                copy_bootmgr "$vrtpath" "$syspath" "$fwmode"
            else
                copy_bootmgr "$winpath" "$syspath" "$fwmode"
            fi
            build_stores "$winpath" "$syspath" "$fwmode" "$setfwmod" "$createbcd" "$prewbmdef" \
                         "$prodname" "$locale" "$verbose" "$virtual" "$vrtpath" "$imgstring"
            if [[ "$setfwmod" == "false" && "$efibootvars" == "true" ]]; then
               if [[ ! -z "$wbmoptnum" ]]; then
                  if [[ "$verbose" == "true" ]]; then echo "Remove the current Windows Boot Manager option..."; fi
                  sudo bootoption delete -n Boot"$wbmoptnum" > /dev/null
               fi
               if [[ "$verbose" == "true" ]]; then echo "Add the Windows Boot Manager to the firmware..."; fi
               sudo bootoption create -l "$wbmefipath" -d "Windows Boot Manager" -@ $resdir/Templates/wbmoptdata.bin > /dev/null
               get_wbmoption && create_wbmfwvar "$wbmoptnum" "$syspath"
               if [[ "$setwbmlast" == "true" ]]; then
                  maxbtnum=$(bootoption list | grep -E "[0-9]:" | sort -rn | awk 'NR==1{print $1}' | sed 's/://')
                  sudo bootoption order 1 $maxbtnum > /dev/null
               fi
            fi
       elif [[ -f "$syswbmpath" && "$clean" == "true" ]]; then
            if [[ "$verbose" == "true" ]]; then echo "Remove current main and recovery BCD stores..."; fi
               rm -f "$syspath"/EFI/Microsoft/Boot/BCD
               rm -f "$syspath"/EFI/Microsoft/Recovery/BCD
            if [[ "$syswbmver" != "$localwbmver" && $(printf "$syswbmver\n$localwbmver\n" | sort -rV | head -1) == "$localwbmver" ]]; then
               if [[ -f "$defbootpath" && "$defbootver" == "$syswbmver" ]]; then
                  rm "$defbootpath"
               fi
               rm -rf "$syspath/EFI/Microsoft"
               if  [[ "$virtual" == "true" ]]; then
                   copy_bootmgr "$vrtpath" "$syspath" "$fwmode"
               else
                   copy_bootmgr "$winpath" "$syspath" "$fwmode"
               fi
            fi
            build_stores "$winpath" "$syspath" "$fwmode" "$setfwmod" "$createbcd" "$prewbmdef" \
                         "$prodname" "$locale" "$verbose" "$virtual" "$vrtpath" "$imgstring"
            if [[ "$setfwmod" == "false" && "$efibootvars" == "true" ]]; then
               if [[ -z "$wbmoptnum" ]]; then
                  if [[ "$verbose" == "true" ]]; then echo "Add the Windows Boot Manager to the firmware..."; fi
                  sudo bootoption create -l "$wbmefipath" -d "Windows Boot Manager" -@ $resdir/Templates/wbmoptdata.bin > /dev/null
                  get_wbmoption
                  if [[ "$setwbmlast" == "true" ]]; then
                     maxbtnum=$(bootoption list | grep -E "[0-9]:" | sort -rn | awk 'NR==1{print $1}' | sed 's/://')
                     sudo bootoption order 1 $maxbtnum > /dev/null
                  fi
               fi
               create_wbmfwvar "$wbmoptnum" "$syspath"
            fi
       else
            createbcd="false"
            if [[ "$syswbmver" != "$localwbmver" && $(printf "$syswbmver\n$localwbmver\n" | sort -rV | head -1) == "$localwbmver" ]]; then
               if [[ -f "$defbootpath" && "$defbootver" == "$syswbmver" ]]; then rm "$defbootpath"; fi
               if [[ "$verbose" == "true" ]]; then echo "Backup current BCD files before update..."; fi
               mv "$syspath/EFI/Microsoft/Boot/BCD" "$syspath/EFI/BCD-BOOT"
               mv "$syspath/EFI/Microsoft/Recovery/BCD" "$syspath/EFI/BCD-RECOVERY"
               rm -rf "$syspath/EFI/Microsoft"
               if  [[ "$virtual" == "true" ]]; then
                   copy_bootmgr "$vrtpath" "$syspath" "$fwmode"
               else
                   copy_bootmgr "$winpath" "$syspath" "$fwmode"
               fi
               if [[ "$verbose" == "true" ]]; then echo "Restore current BCD files after update..."; fi
               mv "$syspath/EFI/BCD-BOOT" "$syspath/EFI/Microsoft/Boot/BCD"
               mv "$syspath/EFI/BCD-RECOVERY" "$syspath/EFI/Microsoft/Recovery/BCD"
            fi
            update_winload "$winpath" "$syspath" "$fwmode" "$setfwmod" "$createbcd" "$prewbmdef" \
                           "$prodname" "$locale" "$verbose" "$virtual" "$vrtpath" "$imgstring"
            if [[ "$setfwmod" == "false" && "$efibootvars" == "true" && -z "$wbmoptnum" ]]; then
               if [[ "$verbose" == "true" ]]; then echo "Add the Windows Boot Manager to the firmware..."; fi
               sudo bootoption create -l "$wbmefipath" -d "Windows Boot Manager" -@ $resdir/Templates/wbmoptdata.bin > /dev/null
               get_wbmoption && create_wbmfwvar "$wbmoptnum" "$syspath"
               if [[ "$setwbmlast" == "true" ]]; then
                  maxbtnum=$(bootoption list | grep -E "[0-9]:" | sort -rn | awk 'NR==1{print $1}' | sed 's/://')
                  sudo bootoption order 1 $maxbtnum > /dev/null
               fi
            fi
       fi
       if [[ ! -f "$defbootpath" ]]; then
          if [[ "$verbose" == "true" ]]; then echo "Copy bootmgfw.efi to default boot path..."; fi
          mkdir -p "$syspath"/EFI/BOOT
          cp "$localwbmpath" "$defbootpath"
       fi
       if [[ "$rmsysmnt" == "true" && "$firmware" == "uefi" ]]; then umount_system; fi
       if [[ "$virtual" == "true" && "$firmware" == "uefi" ]]; then umount_vpart; fi
       cleanup
       echo "Finished configuring UEFI boot files."
    fi
    if [[ "$firmware" == "bios" || "$firmware" == "both" ]]; then
       if   [[ -z "$syspath" ]]; then
            get_syspath "$firmware" "$windisk"
       elif [[ ! -z "$syspath" && -d "$syspath" ]]; then
            if [[ "$firmware" == "bios" ]]; then
               get_device "$firmware" "$syspath"
            fi
       else
            echo -e "${RED}Invalid system path please try again.${NC}"
            if  [[ "$virtual" == "true" ]]; then umount_vpart; fi
            exit 1
       fi
       fwmode="bios"
       sysbtmgr="false"
       sysuwfpath="$syspath/Boot/bootuwf.dll"
       sysvhdpath="$syspath/Boot/bootvhd.dll"
       if  [[ "$virtual" == "true" ]]; then
           localuwfpath="$vrtpath/Windows/Boot/PCAT/bootuwf.dll"
           localvhdpath="$vrtpath/Windows/Boot/PCAT/bootvhd.dll"
       else
           localuwfpath="$winpath/Windows/Boot/PCAT/bootuwf.dll"
           localvhdpath="$winpath/Windows/Boot/PCAT/bootvhd.dll"
       fi
       if [[ "$sysfsvendor" != "MS-DOS" ]]; then
          if [[ "$sysfstype" != "NTFS" && "$sysfstype" != "UFSD_NTFS" ]]; then
              echo "Active partition $syspart is $sysfstype format."
              echo -e "${RED}System partition must be FAT or NTFS format.${NC}"
              if [[ "$virtual" == "true" ]]; then umount_vpart; fi
              if [[ "$rmsysmnt" == "true" ]]; then umount_system; fi
              exit 1
          fi
       fi
       if  [[ -f "$localuwfpath" && -f "$localvhdpath" ]]; then
           localuwfver=$(peres -v "$localuwfpath" | grep 'Product Version:' | awk '{print $3}')
           localvhdver=$(peres -v "$localvhdpath" | grep 'Product Version:' | awk '{print $3}')
       else
           if  [[ "$virtual" == "true" ]]; then
               echo -e "${RED}Unable to find the BIOS boot files at $vrtpath${NC}"
               umount_vpart
           else
               echo -e "${RED}Unable to find the BIOS boot files at $winpath${NC}"
           fi
           if [[ "$rmsysmnt" == "true" ]]; then umount_system; fi
           exit 1
       fi
       if [[ -f "$sysuwfpath" && -f "$sysvhdpath" ]]; then
          sysuwfver=$(peres -v "$sysuwfpath" | grep 'Product Version:' | awk '{print $3}')
          sysvhdver=$(peres -v "$sysvhdpath" | grep 'Product Version:' | awk '{print $3}')
          sysbtmgr="true"
       fi
       if [[ ! -f "$sysuwfpath" && ! -f "$sysvhdpath" ]]; then
          if  [[ "$virtual" == "true" ]]; then
              copy_bootmgr "$vrtpath" "$syspath" "$fwmode" "$sysfstype"
          else
              copy_bootmgr "$winpath" "$syspath" "$fwmode" "$sysfstype"
          fi
          build_stores "$winpath" "$syspath" "$fwmode" "$setfwmod" "$createbcd" "$prewbmdef" \
                       "$prodname" "$locale" "$verbose" "$virtual" "$vrtpath" "$imgstring"
       elif [[ "$sysbtmgr" == "true" && "$clean" == "true" ]]; then
            if [[ "$verbose" == "true" ]]; then echo "Remove current BCD store..."; fi
            rm -f "$syspath"/Boot/BCD
            if [[ "$sysuwfver" != "$localuwfver" || "$sysvhdver" != "$localvhdver" ]]; then
               if [[ $(printf "$sysuwfver\n$localuwfver\n" | sort -rV | head -1) == "$localuwfver" ||
                     $(printf "$sysvhdver\n$localvhdver\n" | sort -rV | head -1) == "$localvhdver" ]]; then
                  rm -rf "$syspath/Boot" && rm -f "$syspath/bootmgr $syspath/bootnxt"
                  if  [[ "$virtual" == "true" ]]; then
                      copy_bootmgr "$vrtpath" "$syspath" "$fwmode" "$sysfstype"
                  else
                      copy_bootmgr "$winpath" "$syspath" "$fwmode" "$sysfstype"
                  fi
               fi
            fi
            build_stores "$winpath" "$syspath" "$fwmode" "$setfwmod" "$createbcd" "$prewbmdef" \
                         "$prodname" "$locale" "$verbose" "$virtual" "$vrtpath" "$imgstring"
       else
            createbcd="false"
            if [[ "$sysuwfver" != "$localuwfver" || "$sysvhdver" != "$localvhdver" ]]; then
               if [[ $(printf "$sysuwfver\n$localuwfver\n" | sort -rV | head -1) == "$localuwfver" ||
                     $(printf "$sysvhdver\n$localvhdver\n" | sort -rV | head -1) == "$localvhdver" ]]; then
                  if [[ "$verbose" == "true" ]]; then echo "Backup current BCD store before update..."; fi
                  mv "$syspath/Boot/BCD" "$syspath"
                  rm -rf "$syspath/Boot" && rm -f "$syspath/bootmgr $syspath/bootnxt"
                  if  [[ "$virtual" == "true" ]]; then
                      copy_bootmgr "$vrtpath" "$syspath" "$fwmode" "$sysfstype"
                  else
                      copy_bootmgr "$winpath" "$syspath" "$fwmode" "$sysfstype"
                  fi
                  if [[ "$verbose" == "true" ]]; then echo "Restore current BCD store after update..."; fi
                  mv "$syspath/BCD" "$syspath/Boot"
               fi
            fi
            update_winload "$winpath" "$syspath" "$fwmode" "$setfwmod" "$createbcd" "$prewbmdef" \
                           "$prodname" "$locale" "$verbose" "$virtual" "$vrtpath" "$imgstring"
       fi
       if [[ "$rmsysmnt" == "true" ]]; then umount_system; fi
       if [[ "$virtual" == "true" ]]; then umount_vpart; fi
       cleanup
       echo "Finished configuring BIOS boot files."
    fi
fi
