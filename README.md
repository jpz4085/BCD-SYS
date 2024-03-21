# BCD-SYS

BASH script utility to setup the Boot Configuration Data store and system files for the Windows Boot Manager (WBM) from a Linux or macOS environment. This can be used to add boot files after applying a Windows image with the wimlib tools, configure the computer to boot from a virtual hard disk (VHDX) file, add a Windows installation to the current boot menu or recreate a system partition that has been corrupted or formatted. Similar to the bcdboot utility.

<img align="center" src="https://raw.githubusercontent.com/jpz4085/BCD-SYS/main/Resources/windows_entry_physical.png"/>

Example 1: Copy boot files then create BCD store for a physical Windows installation.

<img align="center" src="https://raw.githubusercontent.com/jpz4085/BCD-SYS/main/Resources/windows_entry_virtual.png"/>

Example 2: Copy boot files then create BCD store for a Windows installation on a virtual hard disk.

## Usage

##### Show help

```
bcd-sys --help
```
##### Create a new Windows entry 

```
bcd-sys /media/user/mountpoint
```
##### Create a virtual hard disk entry

```
bcd-sys /media/user/mountpoint/images/windows.vhdx
```
##### Specify a system volume (no firmware entry)

```
bcd-sys /media/user/mountpoint -s /media/user/volname
```
##### Specify both UEFI and BIOS firmware

```
bcd-sys -f both /media/user/mountpoint
```
##### Add the WBM to the end of the UEFI boot order

```
bcd-sys -e /media/user/mountpoint
```
##### Specify a custom description

```
bcd-sys /media/user/mountpoint -n Windows\ 11\ Professional
```
##### Specify the locale parameter

```
bcd-sys -l en-us /media/user/mountpoint
```
##### Remove existing stores and create new entries

```
bcd-sys -c /media/user/mountpoint
```

## Installation

Download from Releases or clone the repository.
```
git clone https://github.com/jpz4085/bcd-sys.git
```

Enter the folder for your platform and run for temporary usage.
```
cd $(uname)
./bcdsys.sh /media/user/mountpoint
```

Install or uninstall using the setup script if desired.
```
./setup.sh install | uninstall
```

## Features

BCD-SYS has the following features and differences compared to bcdboot:

- Global objects and settings remain unchanged when modifiying an existing BCD.
- Any existing osloader objects for a Windows volume are replaced and not merged.
- The system BCD-Template is ignored and a Windows10/11 equivalent is used.
- The clean option will delete the existing configuration and create entries in new stores.
- The boot files will be copied by default to a system partition on the Windows device, the  
  current root device, or the first disk listed by the system if different from the previous.
- When specifying a virtual hard disk the script will present a list of partitions contained  
  in the file. Enter the device name of the volume which contains the Windows image.
- The position of the WBM entry in the UEFI boot order will be preserved when updating  
  an existing BCD. A new entry will only be created if missing or creating new stores.
- The description can be specified when creating a new Windows entry.

## Requirements

**Common Packages:** [hivexsh](https://www.libguestfs.org/hivexsh.1.html) and [hivexregedit](https://libguestfs.org/hivexregedit.1.html), ([readpe - PE Utils](https://github.com/mentebinaria/readpe)[^1]) [pev/peres](https://manpages.ubuntu.com/manpages/jammy/man1/peres.1.html)

**Linux Packages:** [attr/setfattr](https://man7.org/linux/man-pages/man1/setfattr.1.html) and [fatattr](https://manpages.ubuntu.com/manpages/jammy/man1/fatattr.1.html), VHDX Support: [qemu-utils](https://manpages.ubuntu.com/manpages/jammy/man8/qemu-nbd.8.html) and NBD client module.[^2]

**macOS Packages:** bash (above version 3.2), mtools, [bootoption](https://github.com/bootoption/bootoption)[^3], [signmbr](https://github.com/jpz4085/signmbr)[^4] and NTFS write support.[^5][^6]

**Legacy BIOS:** [ms-sys](https://github.com/jpz4085/ms-sys)[^7]

[^1]: Download and build from source when necessary.

[^2]: These are optional if only working with physical disks.

[^3]: This is optional and only tested on Hackintosh and VirtualBox.

[^4]: Create a Windows Disk Signature on MBR media before running the script.

[^5]: The script supports NTFS-3G as well as the commercial Tuxera and Paragon products.

[^6]: This is optional if not writing to any NTFS partitions (including system) from macOS.

[^7]: This is optional and not required if only using UEFI.
