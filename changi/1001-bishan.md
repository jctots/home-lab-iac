# bishan (1001) — Setup procedure

Hardware provisioning is handled by the generated script. Run it first:

```bash
bash changi/1001-bishan.sh
```

Then follow the manual steps below.

## 1. Add to DHCP and stop VM

Add a DHCP reservation for bishan in florence, then stop the VM:

```bash
qm stop 1001
```

## 2. Remove cloud-init drive and start VM

```bash
qm set 1001 --delete ide2 && qm start 1001
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

## 5. Add to Portainer

Add the VM as an environment in Portainer CE on clementi using the agent install command.

## 6. Install Pulse agent

Follow the Pulse agent install instructions from the Pulse dashboard.

## 7. Set up kopia backup

Configure kopia to back up Docker bind mounts to verona.
