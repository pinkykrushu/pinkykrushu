# trp-ami-backup Cookbook

This cookbook provides functionality to backup AMIs with encrypted root volumes to an S3 bucket and restore them when needed. It specifically targets instances with names containing 'rhel-7', 'rhel8', or 'rhel-8'.

## Requirements

### Platforms
- Linux-based platforms with access to AWS EC2 metadata service

### Chef
- Chef 14.0 or later

### Dependencies
- `aws` cookbook
- `mail` cookbook

## Attributes

* `node['trp-ami-backup']['s3_bucket']` - S3 bucket name for storing AMI backups (default: 's3-trp-ami-backup')
* `node['trp-ami-backup']['retention_period']` - Number of days to retain backups (default: 180)
* `node['trp-ami-backup']['log_dir']` - Directory for storing logs (default: '/var/log/ami_backup')
* `node['trp-ami-backup']['email']['server']` - SMTP server for notifications
* `node['trp-ami-backup']['email']['port']` - SMTP port (default: 25)
* `node['trp-ami-backup']['email']['username']` - SMTP username
* `node['trp-ami-backup']['email']['password']` - SMTP password
* `node['trp-ami-backup']['email']['from']` - Sender email address
* `node['trp-ami-backup']['email']['to']` - Recipient email address
* `node['trp-ami-backup']['aws_region']` - AWS region (default: 'us-east-1')
* `node['trp-ami-backup']['proxy']['http']` - HTTP proxy URL
* `node['trp-ami-backup']['proxy']['https']` - HTTPS proxy URL
* `node['trp-ami-backup']['proxy']['no_proxy']` - Comma-separated list of domains to exclude from proxy
* `node['trp-ami-backup']['ami_name_patterns']` - List of name patterns to match for backup (default: ['rhel-7', 'rhel8', 'rhel-8'])

## Usage

### AWS Credentials

Create an encrypted data bag named 'aws' with an item 'credentials' containing:
```json
{
  "id": "credentials",
  "access_key_id": "YOUR_ACCESS_KEY",
  "secret_access_key": "YOUR_SECRET_KEY"
}
```

### Proxy Configuration

Configure proxy settings in your role or environment:
```ruby
default_attributes(
  'trp-ami-backup' => {
    'proxy' => {
      'http' => 'http://proxy.example.com:8080',
      'https' => 'http://proxy.example.com:8080',
      'no_proxy' => 'localhost,127.0.0.1'
    }
  }
)
```

### Email Configuration

The cookbook uses unauthenticated SMTP for email notifications. Configure in your role or environment:
```ruby
default_attributes(
  'trp-ami-backup' => {
    'email' => {
      'server' => 'smtp.example.com',
      'port' => 25,
      'from' => 'ami-backup@example.com',
      'to' => 'admin@example.com'
    }
  }
)
```

### Backing up an AMI

Include the backup recipe in your run list:
```ruby
include_recipe 'trp-ami-backup::backup'
```

This will:
1. Check if the instance name matches configured patterns (rhel-7, rhel8, or rhel-8)
2. Create an AMI if the name matches
3. Store the AMI in the specified S3 bucket
4. Create metadata about the AMI
5. Send an email notification
6. Clean up old backups based on retention period

### Restoring an AMI

To restore an AMI, set the AMI ID in the node attributes and include the restore recipe:

```ruby
node.default['trp-ami-backup']['restore_ami_id'] = 'ami-xxxxxxxx'
include_recipe 'trp-ami-backup::restore'
```

This will:
1. Fetch the AMI from S3
2. Import it as a new AMI
3. Apply the original tags from metadata
4. Send an email notification

## Metadata Storage

The cookbook stores the following metadata for each AMI:
- Creation date
- AMI ID and name
- Description
- Tags
- Root device information
- Block device mappings
- Virtualization type
- Architecture
- Platform details
- State

## Logging

All operations are logged to `/var/log/ami_backup/ami_backup.log` with daily rotation.

## License

All rights reserved.

## Author

Your Company Name 