default['trp-ami-backup']['s3_bucket'] = 's3-trp-ami-backup'
default['trp-ami-backup']['retention_period'] = '180' # 6 months in days
default['trp-ami-backup']['log_dir'] = '/var/log/ami_backup'

# Email configuration (no authentication)
default['trp-ami-backup']['email'] = {
  'server' => 'smtp.example.com',
  'port' => 25,  # Standard SMTP port for no authentication
  'from' => 'ami-backup@example.com',
  'to' => 'admin@example.com'
}

# AWS region and proxy settings
default['trp-ami-backup']['aws_region'] = 'us-east-1'
default['trp-ami-backup']['proxy'] = {
  'http' => nil,  # e.g., 'http://proxy.example.com:8080'
  'https' => nil, # e.g., 'http://proxy.example.com:8080'
  'no_proxy' => nil # e.g., 'localhost,127.0.0.1'
}

# AMI name patterns to backup
default['trp-ami-backup']['ami_name_patterns'] = ['rhel-7', 'rhel8', 'rhel-8'] 