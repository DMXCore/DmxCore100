# Init Scripts

Update Balena HostOS with the following command to automatically detect the base board version:

```bash
curl -s -L https://github.com/DMXCore/DmxCore100/raw/refs/heads/main/init-scripts/update-hostos.sh | sudo bash
```

To force a specific base board version (e.g., `v1` or `v2`), use the `-v` option:

```bash
curl -s -L https://github.com/DMXCore/DmxCore100/raw/refs/heads/main/init-scripts/update-hostos.sh | sudo bash -s -v v1
```

or

```bash
curl -s -L https://github.com/DMXCore/DmxCore100/raw/refs/heads/main/init-scripts/update-hostos.sh | sudo bash -s -v v2
```

To display usage information, use the `-h` option:

```bash
curl -s -L https://github.com/DMXCore/DmxCore100/raw/refs/heads/main/init-scripts/update-hostos.sh | sudo bash -s -h
```

**Note**: The script must be run as root (using `sudo`), as it modifies system files, and you have to reboot after to have the changes take affect.
