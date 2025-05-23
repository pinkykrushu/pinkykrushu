# Default attributes for AMI backup manager

# AWS Region
default['ami_backup_manager']['aws_region'] = 'us-east-1'

# S3 bucket for storing AMI backups and metadata
default['ami_backup_manager']['s3_bucket'] = 'your-ami-backup-bucket'

# Prefix for AMI names
default['ami_backup_manager']['ami_prefix'] = 'backup'

# Source AMI ID to backup
default['ami_backup_manager']['source_ami_id'] = nil

# AMI ID to restore (used by restore recipe)
default['ami_backup_manager']['ami_id_to_restore'] = nil

# Proxy Configuration
default['ami_backup_manager']['proxy']['host'] = nil
default['ami_backup_manager']['proxy']['port'] = nil
default['ami_backup_manager']['proxy']['protocol'] = 'https'  # http or https 