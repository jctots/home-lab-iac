# 9001 linux-no-media — Setup procedure

A blank VM shell with no disk. Used as the base for importing cloud images into 9002.

## Create the VM

Run on changi as root:

```bash
qm create 9001 --name linux-no-media \
  --cores 1 \
  --memory 2048 \
  --balloon 0 \
  --cpu x86-64-v2-AES \
  --net0 virtio,bridge=vmbr0,firewall=1 \
  --scsihw virtio-scsi-single \
  --serial0 socket \
  --vga serial0 \
  --ostype l26 \
  --ide2 none,media=cdrom
```

## Convert to template

```bash
qm template 9001
```

This VM has no disk — disk import happens in the next step when creating 9002.
