# braddell (1003) — Setup procedure

Hardware provisioning is handled by the generated script. Run it first:

```bash
bash changi/1003-braddell.sh
```

Requires IOMMU enabled on changi. Verify before running:

```bash
dmesg | grep -e DMAR -e IOMMU | head -5
```

Then follow the manual steps below.

## 1. Add to DHCP and stop VM

Add a DHCP reservation for braddell in florence, then stop the VM:

```bash
qm stop 1003
```

## 2. Remove cloud-init drive and start VM

```bash
qm set 1003 --delete ide2 && qm start 1003
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
lsblk   # verify
sudo cp -a /home.old/. /home/
```

## 5. Install NVIDIA drivers

```bash
sudo sed -i 's/Components: main/Components: main contrib non-free non-free-firmware/g' \
  /etc/apt/sources.list.d/debian.sources && \
sudo apt update && \
sudo apt install -y linux-headers-$(uname -r) nvidia-driver && \
sudo reboot
```

Verify after reboot:

```bash
nvidia-smi
```

## 6. Install NVIDIA Container Toolkit

Follow the official guide:
https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html

## 7. Add to Portainer

Add the VM as an environment in Portainer CE on clementi using the agent install command.

## 8. Install Pulse agent

Follow the Pulse agent install instructions from the Pulse dashboard.

## 9. Set up kopia backup

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
