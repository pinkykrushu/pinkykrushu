# RHEL Image Builder - CIS Compliant AMIs

This repository contains blueprints and scripts for creating RHEL 7, 8, and 9 AMIs using RHEL Image Builder with specific disk layout and security configurations.

## Prerequisites

1. RHEL system with Image Builder installed:
```bash
# For RHEL 8/9
dnf install -y osbuild-composer composer-cli

# For RHEL 7
yum install -y lorax-composer composer-cli
```

2. AWS CLI configured with appropriate credentials
3. Image Builder service started and enabled:
```bash
# For RHEL 8/9
systemctl enable --now osbuild-composer.socket

# For RHEL 7
systemctl enable --now lorax-composer
```

## Directory Structure

```
.
├── blueprints/
│   ├── rhel7-cis.toml
│   ├── rhel8-cis.toml
│   └── rhel9-cis.toml
├── scripts/
│   └── cleanup.sh
└── docs/
```

## Usage

1. Copy the cleanup script to the system:
```bash
sudo cp scripts/cleanup.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/cleanup.sh
```

2. Replace the placeholder values in the blueprints:
   - Replace `%ROOT_PASSWORD%` with your desired root password
   - Replace `%AUTHORIZED_KEY%` with your SSH public key

3. Push the blueprint to Image Builder:
```bash
# For RHEL 9
composer-cli blueprints push blueprints/rhel9-cis.toml

# For RHEL 8
composer-cli blueprints push blueprints/rhel8-cis.toml

# For RHEL 7
composer-cli blueprints push blueprints/rhel7-cis.toml
```

4. Create the image:
```bash
# Replace RHEL_VERSION with 7, 8, or 9
composer-cli compose start-ostree rhel${RHEL_VERSION}-cis ami
```

5. Monitor the build:
```bash
composer-cli compose status
```

6. Once complete, download the image:
```bash
composer-cli compose image UUID
```

7. Upload to AWS as an AMI:
```bash
aws ec2 import-image --description "RHEL ${RHEL_VERSION}" --disk-containers "Format=vmdk,UserBucket={S3Bucket=my-bucket,S3Key=path/to/image}"
```

## System Configuration

The generated images include the following configurations:

### Disk Layout
- /boot: 1GB (XFS)
- LVM Configuration:
  - Root VG: vg_root
  - Logical Volumes:
    - lv_root (/): 10GB
    - lv_var (/var): 5GB
    - lv_tmp (/tmp): 2GB
    - lv_home (/home): 1GB
  - All volumes use XFS filesystem with appropriate labels

### Security Configuration
- Root login enabled with password authentication
- Firewall disabled
- SELinux enabled and enforcing
- Basic audit rules configured
- Password policies configured
- Legacy services disabled

## Customization

To customize the blueprints:

1. Modify the appropriate blueprint file in the `blueprints/` directory
2. Update the disk layout, services, or security configurations as needed
3. Push the updated blueprint using `composer-cli blueprints push`

## Important Notes

- Replace the placeholder values (%ROOT_PASSWORD%, %AUTHORIZED_KEY%) before building
- The cleanup script removes sensitive information and prepares the image for AMI creation
- Always test the generated AMIs in a development environment before production use
- Disk sizes can be adjusted in the blueprint files as needed 