# bedok (1002) — Setup procedure

Hardware provisioning is handled by the generated script. Run it first:

```bash
bash changi/1002-bedok.sh
```

Then follow the manual steps below.

## 1. Add to DHCP and stop VM

Add a DHCP reservation for bedok in florence, then stop the VM:

```bash
qm stop 1002
```

## 2. Remove cloud-init drive and start VM

```bash
qm set 1002 --delete ide2 && qm start 1002
```

## 3. Initialize second disk as /home

SSH into the VM, then:

```bash
sudo fdisk /dev/sdb
# g, n, enter, enter, enter, p, w
sudo mkfs.ext4 /dev/sdb1
```

## 4. Mount as /home

```bash
sudo blkid /dev/sdb1   # copy UUID
sudo mv /home /home.old
sudo mkdir /home
sudo nano /etc/fstab   # add: UUID=<uuid> /home ext4 defaults,nofail 0 2
sudo mount -a
systemctl daemon-reload
sudo cp -a /home.old/. /home/
```

## 5. Pass through SATA disk and mount as /mnt/share

From the changi node shell, attach the SATA disk:

```bash
qm set 1002 --scsi2 /dev/disk/by-id/ata-CT1000BX500SSD1_2507E9A7967C
```

Uncheck the backup option for this disk in Proxmox hardware settings.

In the VM, initialize and mount the disk:

```bash
sudo fdisk /dev/sdc
# g, n, enter, enter, enter, p, w
sudo mkfs.ext4 /dev/sdc1

sudo blkid /dev/sdc1   # copy UUID
sudo mkdir /mnt/share
sudo nano /etc/fstab   # add: UUID=<uuid> /mnt/share ext4 defaults,nofail 0 2
sudo mount -a
systemctl daemon-reload
```

## 6. Add to Portainer

Add the VM as an environment in Portainer CE on clementi using the agent install command.

## 7. Install Pulse agent

Follow the Pulse agent install instructions from the Pulse dashboard.

## 8. Set up kopia backup

Configure kopia to back up Docker bind mounts to verona.

---

## Expanding file storage

To grow the /home disk after resizing from Proxmox:

```bash
lsblk   # confirm device name, e.g. sdb
sudo growpart /dev/sdb 1
sudo resize2fs /dev/sdb1
lsblk   # verify
```
