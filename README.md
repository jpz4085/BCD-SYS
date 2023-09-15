# BCD-SYS

BASH script utility to setup the Boot Configuration Data store and system files for the Windows Boot Manager (WBM) from a Linux environment. This can be used to add boot files after applying a Windows image with the wimlib tools, add a Windows installation to the current boot menu or recreate a system partition that has been corrupted or formatted. Similar to the bcdboot utility.

<p align="center">
<img src="https://raw.githubusercontent.com/jpz4085/BCD-SYS/main/create_entries.png" alt="bcd-sys screenshot" />
</p

Example: Copy boot files then create or update BCD store for three Windows installations.

## Usage

##### Show help

```
bcd-sys --help
```
##### Create a new Windows entry 

```
bcd-sys /media/user/mountpoint
```
##### Specify a system volume (no firmware entry)

```
bcd-sys /media/user/mountpoint -s /media/user/volname
```
##### Specify both UEFI and BIOS firmware

```
bcd-sys -f both /media/user/mountpoint
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
- The WBM firmware entry is always created in the first position when applicable.
- The description can be specified when creating a new Windows entry.

## Requirements

**libguestfs tools:** [hivexsh](https://www.libguestfs.org/hivexsh.1.html) and [hivexregedit](https://libguestfs.org/hivexregedit.1.html)

**File Attributes:** [attr/setfattr](https://man7.org/linux/man-pages/man1/setfattr.1.html) and [fatattr](https://manpages.ubuntu.com/manpages/jammy/man1/fatattr.1.html)

**PE Utils:** [pev/peres](https://manpages.ubuntu.com/manpages/jammy/man1/peres.1.html)

**Legacy BIOS[^1]:** [ms-sys](https://github.com/jpz4085/ms-sys)

[^1]: This is optional and not required if only using UEFI.

