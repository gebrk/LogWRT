# LogWRT

LogWRT is a customised OpenWRT image designed for syslog and netflow collection. LogWRT images can be built for `x86_64` and all Raspberry Pi generations.

Logs are stored on a seperate partition, which can be on the same disk as the root partition, and so are not afftected by OpenWRT sysupgrades.
LogWRT is intended to be used as an "appliance" type system - there should be little need to interact with it once configured, and it is upgraded using firmware images.

LogWRT should be run on dedicated hardware - either a Raspberry Pi or small x86 box - and should have a good root passphrase with no ssh allowed_keys. Running log and netflow collection on a dedicated box provides some protection from log tampering compared to running in a VM where access to the host OS may allow trivial tampering. LogWRT does not need internet access - though NTP is important for accurate logging.

LogWRT is not a log analysis platform - but could be a "good enough" solution to keeping logs off-box (e.g. in a homelab) or as a stepping stone to a full log analysis platform which could be swapped in at the same IP without reconfiguring everything else.

## Usage

1. Install the [prerequisites for imagebuilder](https://openwrt.org/docs/guide-user/additional-software/imagebuilder) (note - these may be out of date) and [`just`](https://github.com/casey/just#readme)
1. Build the LogWRT image for `x86_64`

    ```
    $ just buildimage
    ```
    or Raspberry Pi (Pi4 shown here)
    ```
    $ just buildfor rpi-4 buildimage
    ```

3. Write the appropriate image (see notes below) from the `openwrt-imagebuilder*/bin/targets` folder to an SD card or drive for the LogWRT box.
4. Create a partition for log storage on the same or a seperate disk. This needs to be an ext4 filesystem with the filesystem label `logstore`. If using the same disk as the root partition it is best to leave a good margin after that partition and record a dump of the partition layout as is *possible* for a sysupgrade to change the size of the root partion and remove the record of the additional partition. Most sysupgrades should be safe in this respect unless the OpenWRT project change the defaults.
5. Boot the new LogWRT box, by default it will request an IP address using DHCP.
6. Connect by serial console, webui, or ssh. Login as root and set a new root passphrase and configure.

### Image files
Imagebuilder builds a few varients of the base image by default. Both architectures have `-ext4` or `-squashfs` varients - the squashfs version should support factory resets, but apart from that there should be no difference for LogWRT use.

Raspberry Pi images come in a `-factory.img.gz` version which is extracted used for new installations and a `-sysupgrade.img.gz` version which is used directly when upgrading.

For `x86_64`, use a `-combined` image, with `-efi.img.gz` if on an EFI system or without for BIOS boot. The same image type is used for new installations and for upgrading.

### Emulation
There is a builtin recipe to run the `x86_64` version of LogWRT in a throwawy Qemu session.
```
$ just emulate
```
This will require `sudo` access the first time it is run as it needs to use loop devices to build the virtual logstore disk. This virtual disk will be reused for future runs and changes to it are discarded between emulation runs.

## Configuration
Basic system configuration - IP address etc - can be done using the OpenWRT webui.

For LogWRT, the log and netflow data retention times should be checked and configured appropriately using the command line.

Netflow retention is configured using uci (see [nfexpire man page](https://manpages.debian.org/bullseye/nfdump/nfexpire.1.en.html#s) for supported units):
```
root@logbox:~# uci show nfcapd.nfexpire
nfcapd.nfexpire=nfexpire
nfcapd.nfexpire.max_age='12w'
nfcapd.nfexpire.max_space='500M'
root@logbox:~# uci set nfcapd.nfexpire.max_space='1G'
root@logbox:~# uci set nfcapd.nfexpire.max_age='52w'
root@logbox:~# uci commit
root@logbox:~# /etc/init.d/nfcapd restart
Force rebuild requested by stat record in /mnt/logstore/flowdata
Scanning files in /mnt/logstore/flowdata .. done.
First:     2023-05-29 20:27:41
Last:      2023-05-29 20:27:41
Lifetime:  0 sec
Numfiles:  0
Filesize:  0 B
Max Size:  1073741824 = 1.0 GB
Max Life:  31449600 = 52.0 weeks
Watermark: 0%
Status:    Force rebuild
```

Logfile retention is configured in the Logrotate config file `/etc/logrotate.d/rsyslog.conf`. Edit that file (`nano` is installed) and change the `daily` and `rotate 7` values as needed. There is nothing to restart as logrotate is run from cron.

## Differences from OpenWRT base images

* Rsyslog and nfcapd installed and running by default.
* Rsyslog and nfcapd run as their own users instead of root.
* Logrotate installed and configured to run from cron and rotate the remote syslogs.
* WAN interface and zone removed from default networking config.
* A selection of helpful shell utilities installed by default, including bash as the root shell.
