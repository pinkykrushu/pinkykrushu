# AMI Backup Manager Cookbook

This Chef cookbook manages AWS AMI backups with encrypted root volumes to S3 and provides restoration capabilities.

## Features

- Creates AMI backups with encrypted root volumes
- Stores AMI metadata in S3 for easy tracking
- Uses AWS create-store-image-task for efficient AMI storage
- Supports AMI restoration from S3
- Preserves all instance tags and metadata
- Secure credential management using Chef data bags

## Prerequisites

- Chef 14.0 or later
- AWS credentials configured in a data bag
- S3 bucket for storing AMI backups and metadata
- Appropriate AWS IAM permissions

## Required AWS Permissions

The AWS credentials used must have the following permissions:
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:CreateImage",
                "ec2:CreateTags",
                "ec2:DescribeImages",
                "ec2:DescribeInstances",
                "ec2:CreateStoreImageTask",
                "ec2:CreateRestoreImageTask",
                "s3:PutObject",
                "s3:GetObject"
            ],
            "Resource": "*"
        }
    ]
}
```

## Data Bag Configuration

Create an AWS credentials data bag item:

```json
{
    "id": "credentials",
    "aws_access_key_id": "YOUR_ACCESS_KEY",
    "aws_secret_access_key": "YOUR_SECRET_KEY"
}
```

Save this as `data_bags/aws/credentials.json` and encrypt it using:
```bash
knife data bag create aws credentials --secret-file /path/to/secret
```

## Attributes

| Attribute | Description | Default |
|-----------|-------------|---------|
| `['ami_backup_manager']['aws_region']` | AWS region | 'us-east-1' |
| `['ami_backup_manager']['s3_bucket']` | S3 bucket for backups | 'your-ami-backup-bucket' |
| `['ami_backup_manager']['ami_prefix']` | Prefix for AMI names | 'backup' |
| `['ami_backup_manager']['ami_id_to_restore']` | AMI ID to restore | nil |

## Usage

### Taking a Backup

Include the backup recipe in your run list:

```json
{
    "run_list": [
        "recipe[ami_backup_manager::backup]"
    ]
}
```

### Restoring an AMI

Set the AMI ID to restore in your node attributes:

```json
{
    "ami_backup_manager": {
        "ami_id_to_restore": "ami-xxxxxxxx"
    },
    "run_list": [
        "recipe[ami_backup_manager::restore]"
    ]
}
```

## Metadata Storage

The cookbook stores comprehensive metadata about each AMI backup, including:
- AMI ID and name
- Creation date
- Source instance details
- VPC and subnet information
- Platform and architecture
- Encryption details
- Original tags
- Block device mappings

This metadata is stored in the S3 bucket under the `ami-metadata/` prefix.

## Backup Process

1. Creates an AMI from the instance
2. Waits for AMI creation to complete
3. Collects comprehensive metadata
4. Stores metadata in S3
5. Creates a store image task to save AMI to S3

## Restoration Process

1. Retrieves metadata from S3
2. Creates restore image task from S3
3. Waits for restoration to complete
4. Applies original tags to the restored AMI

## Error Handling

The cookbook includes error handling for:
- Missing AWS credentials
- Failed AMI creation
- Missing metadata
- S3 access issues
- AMI restoration failures

## License

All Rights Reserved

## Author

Your Organization 