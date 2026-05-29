# SFTP repo config
- host: 192.168.xx.xx
- user: homelab-admin
- port: 22
- path: /home/kopia
- password: see SOPS .env (KOPIA_PASSWORD)
- Known Hosts Data: <see below>

# known host data
- open terminal of docker container
```
ssh homelab-admin@192.168.xx.xx
```
- enter password
- exit
- copy contents of:
```
cat /root/.ssh/known_hosts
```

# convention when connecting
- connect as: homelab-admin@<hostname>
- repository password: see SOPS .env (KOPIA_PASSWORD)
- repository description: kopia repository on Verona

# policy
- snapshot retention:
  - latest: 3
  - daily: 3
  - weekly: 3
  - monthly: 3
- scheduling:
  -times of day: 1:00(clementi) 2:00(bishan), 3:00(bedok)
