1. clone 9001 -> 9002

1. in node shell:

```
wget https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2
```

```
qm importdisk 9002 debian-13-generic-amd64.qcow2 local-lvm
```

1. in new vm -> hardware -> select unused disk -> edit -> add

1. in new vm -> hardware -> select hard disk -> disk action -> resize (to 8GB)

1. remove cd rom

1. in new vm -> options -> boot order -> enable scsi0, disable others

1. in new vm -> hardware -> add -> cloud initdrive -> defaults -> ok

1. in new vm -> cloud-init -> add username, password, SSH public key from bitwarden, ip = dhcp -> ok

1. start vm -> console -> login

1. in node shell:

```
apt-get install qemu-guest-agent
```

1. shutdown, copy notes

1. convert to template