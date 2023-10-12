# BCD-SYS

BASH script utility to setup the Boot Configuration Data store and system files for the Windows Boot Manager (WBM) from a Linux environment. This can be used to add boot files after applying a Windows image with the wimlib tools, configure the computer to boot from a virtual hard disk (VHDX) file, add a Windows installation to the current boot menu or recreate a system partition that has been corrupted or formatted. Similar to the bcdboot utility.

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

Run from the local directory for temporary usage.
```
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
- The boot files will be copied to a system partition on either the same or the first disk.
- When specifying a virtual hard disk the script will present a list of partitions contained  
  in the file. Enter the device name of the volume which contains the Windows image.
- The position of the WBM entry in the UEFI boot order will be preserved when updating  
  an existing BCD. A new entry will only be created if missing or creating new stores.
- The description can be specified when creating a new Windows entry.

## Requirements

**libguestfs tools:** [hivexsh](https://www.libguestfs.org/hivexsh.1.html) and [hivexregedit](https://libguestfs.org/hivexregedit.1.html)

**File Attributes:** [attr/setfattr](https://man7.org/linux/man-pages/man1/setfattr.1.html) and [fatattr](https://manpages.ubuntu.com/manpages/jammy/man1/fatattr.1.html)

**PE Utils:** [pev/peres](https://manpages.ubuntu.com/manpages/jammy/man1/peres.1.html)

**Virtual Hard Disks[^1]:** [qemu-utils](https://manpages.ubuntu.com/manpages/jammy/man8/qemu-nbd.8.html) and NBD module

**Legacy BIOS[^2]:** [ms-sys](https://github.com/jpz4085/ms-sys)

[^1]: This is optional if only working with physical disks.

[^2]: This is optional and not required if only using UEFI.

