# Recipe to restore AMI from S3 backup

# Initialize AWS SDK
require 'aws-sdk-ec2'
require 'aws-sdk-s3'
require 'json'
require 'net/http'
require 'uri'

# Configure proxy if specified
if node['ami_backup_manager']['proxy']['host']
  proxy_uri = URI.parse("#{node['ami_backup_manager']['proxy']['protocol']}://#{node['ami_backup_manager']['proxy']['host']}:#{node['ami_backup_manager']['proxy']['port']}")
  
  Aws.config.update(
    region: node['ami_backup_manager']['aws_region'],
    http_proxy: proxy_uri.to_s
  )
else
  Aws.config.update(
    region: node['ami_backup_manager']['aws_region']
  )
end

# Initialize AWS clients with instance profile credentials
ec2_client = Aws::EC2::Client.new
s3_client = Aws::S3::Client.new

ami_id = node['ami_backup_manager']['ami_id_to_restore']
unless ami_id
  Chef::Log.error("AMI ID to restore not specified")
  raise "AMI ID must be specified in node attributes"
end

begin
  # List metadata files to find the latest backup for this AMI
  response = s3_client.list_objects_v2(
    bucket: node['ami_backup_manager']['s3_bucket'],
    prefix: "ami-metadata/#{ami_id}"
  )
  
  latest_metadata = response.contents.sort_by(&:last_modified).last
  unless latest_metadata
    Chef::Log.error("No backup metadata found for AMI #{ami_id}")
    raise "No backup metadata found"
  end
  
  # Get the metadata file
  metadata_obj = s3_client.get_object(
    bucket: node['ami_backup_manager']['s3_bucket'],
    key: latest_metadata.key
  )
  
  metadata = JSON.parse(metadata_obj.body.read)
  Chef::Log.info("Found metadata for AMI #{ami_id}")
  
  # Create AMI restore task
  restore_task = ec2_client.create_restore_image_task(
    bucket: node['ami_backup_manager']['s3_bucket'],
    object_key: metadata['backup_task_id'],
    name: "#{metadata['new_ami_name']}-restored"
  )
  
  # Wait for the AMI to be available
  ruby_block 'wait_for_restored_ami' do
    block do
      Chef::Log.info("Waiting for restored AMI to be available...")
      ec2_client.wait_until(:image_available, image_ids: [restore_task.image_id])
    end
  end
  
  # Apply original tags to the restored AMI
  if metadata['tags']
    tags = metadata['tags'].map { |tag_hash| tag_hash.first }.map do |key, value|
      { key: key, value: value }
    end
    
    ec2_client.create_tags(
      resources: [restore_task.image_id],
      tags: tags
    )
  end
  
  Chef::Log.info("AMI restoration completed. New AMI ID: #{restore_task.image_id}")
  Chef::Log.info("Original metadata: #{JSON.pretty_generate(metadata)}")
rescue Aws::S3::Errors::ServiceError, Aws::EC2::Errors::ServiceError => e
  Chef::Log.error("Failed to restore AMI: #{e.message}")
  raise
end 