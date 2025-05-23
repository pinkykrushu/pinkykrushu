require 'aws-sdk-ec2'
require 'aws-sdk-s3'
require 'json'
require 'logger'
require 'mail'
require 'uri'
require 'net/http'
require 'time'

module TrpAmiBackup
  class AmiHelper
    TASK_TIMEOUT = 5400 # 90 minutes in seconds
    TASK_POLL_INTERVAL = 30 # 30 seconds between status checks
    AMI_MAX_AGE_DAYS = 180 # 6 months

    def initialize(node)
      @node = node
      setup_logging
      setup_proxy
      setup_aws_credentials
    end

    def setup_logging
      @logger = Logger.new(File.join(@node['trp-ami-backup']['log_dir'], 'ami_backup.log'), 'daily')
      @logger.level = Logger::INFO
    end

    def setup_proxy
      proxy_settings = @node['trp-ami-backup']['proxy']
      ENV['http_proxy'] = proxy_settings['http'] if proxy_settings['http']
      ENV['https_proxy'] = proxy_settings['https'] if proxy_settings['https']
      ENV['no_proxy'] = proxy_settings['no_proxy'] if proxy_settings['no_proxy']
    end

    def setup_aws_credentials
      # Fetch AWS credentials from Chef data bag
      aws_creds = Chef::EncryptedDataBagItem.load('aws', 'credentials')
      
      # Common AWS client options
      client_options = {
        region: @node['trp-ami-backup']['aws_region'],
        credentials: Aws::Credentials.new(
          aws_creds['access_key_id'],
          aws_creds['secret_access_key']
        )
      }

      # Add proxy configuration if set
      if @node['trp-ami-backup']['proxy']['https']
        proxy_uri = URI(@node['trp-ami-backup']['proxy']['https'])
        client_options[:http_proxy] = {
          uri: proxy_uri,
          user: proxy_uri.user,
          password: proxy_uri.password
        }
      end

      @ec2_client = Aws::EC2::Client.new(client_options)
      @s3_client = Aws::S3::Client.new(client_options)
    end

    def find_eligible_amis
      @logger.info("Searching for eligible AMIs")
      cutoff_date = (Time.now - (AMI_MAX_AGE_DAYS * 24 * 60 * 60))
      
      # Get all AMIs owned by this account
      response = @ec2_client.describe_images({
        owners: ['self'],
        filters: [
          {
            name: 'state',
            values: ['available']
          }
        ]
      })

      eligible_amis = response.images.select do |ami|
        creation_date = Time.parse(ami.creation_date)
        name = ami.name || ''
        
        # Check if AMI matches name patterns and age requirement
        matches_name_pattern?(name) && creation_date > cutoff_date
      end

      @logger.info("Found #{eligible_amis.length} eligible AMIs")
      eligible_amis
    end

    def backup_all_eligible_amis
      @logger.info("Starting backup process for all eligible AMIs")
      results = []
      
      find_eligible_amis.each do |ami|
        @logger.info("Processing AMI: #{ami.image_id} (#{ami.name})")
        begin
          result = backup_ami(ami.image_id)
          results << result if result
        rescue StandardError => e
          @logger.error("Failed to backup AMI #{ami.image_id}: #{e.message}")
          next
        end
      end

      @logger.info("Completed backup process. Successfully backed up #{results.length} AMIs")
      results
    end

    def backup_ami(ami_id)
      @logger.info("Starting backup process for AMI #{ami_id}")
      
      begin
        # Get AMI details
        ami_details = get_ami_details(ami_id)
        
        # Prepare S3 object tags
        s3_tags = prepare_s3_tags(ami_details)
        
        # Create store image task
        task = create_store_image_task(ami_id, s3_tags)
        
        # Monitor task completion
        monitor_task(task.image_task_id, ami_id)
        
        @logger.info("AMI backup completed successfully for #{ami_id}")
        {ami_id: ami_id, task_id: task.image_task_id}
      rescue Aws::EC2::Errors::ServiceError => e
        @logger.error("AWS EC2 error while backing up AMI #{ami_id}: #{e.message}")
        raise
      end
    end

    def create_metadata(ami_details)
      {
        creation_date: Time.now.iso8601,
        ami_id: ami_details.image_id,
        ami_name: ami_details.name,
        description: ami_details.description,
        tags: ami_details.tags,
        root_device_type: ami_details.root_device_type,
        root_device_name: ami_details.root_device_name,
        block_device_mappings: ami_details.block_device_mappings,
        virtualization_type: ami_details.virtualization_type,
        architecture: ami_details.architecture,
        platform: ami_details.platform,
        state: ami_details.state
      }
    end

    def create_store_image_task(ami_id, s3_tags)
      @logger.info("Creating store image task for AMI #{ami_id}")
      @logger.info("S3 tags to be applied: #{s3_tags}")

      @ec2_client.create_store_image_task({
        image_id: ami_id,
        bucket: @node['trp-ami-backup']['s3_bucket'],
        s3_object_tags: s3_tags
      })
    end

    def monitor_task(task_id, ami_id)
      @logger.info("Monitoring store image task #{task_id} for AMI #{ami_id}")
      start_time = Time.now

      loop do
        response = @ec2_client.describe_store_image_tasks({
          image_task_ids: [task_id]
        })

        task = response.image_task_results.first
        status = task.task_state
        progress = task.progress || 0

        @logger.info("Task #{task_id} status: #{status} - Progress: #{progress}%")

        case status.downcase
        when 'completed'
          @logger.info("Task #{task_id} completed successfully")
          break
        when 'failed'
          error_msg = "Task #{task_id} failed: #{task.status_message}"
          @logger.error(error_msg)
          raise error_msg
        else
          if Time.now - start_time > TASK_TIMEOUT
            error_msg = "Task #{task_id} timed out after #{TASK_TIMEOUT} seconds"
            @logger.error(error_msg)
            raise error_msg
          end
          sleep TASK_POLL_INTERVAL
        end
      end
    end

    def restore_ami(ami_id)
      @logger.info("Starting AMI restoration for #{ami_id}")
      
      # Get metadata from S3
      metadata = get_metadata_from_s3(ami_id)
      
      # Create import image task
      import_task = @ec2_client.import_image({
        description: "Restored from backup: #{ami_id}",
        disk_containers: [{
          format: 'RAW',
          user_bucket: {
            s3_bucket: @node['trp-ami-backup']['s3_bucket'],
            s3_key: "ami-backups/#{ami_id}/image.raw"
          }
        }]
      })

      # Monitor import task
      monitor_import_task(import_task.import_task_id)
      
      # Apply original tags
      if metadata && metadata[:tags]
        @ec2_client.create_tags({
          resources: [import_task.image_id],
          tags: metadata[:tags]
        })
      end

      @logger.info("AMI restoration completed successfully for #{ami_id}")
      import_task.image_id
    end

    def cleanup_old_backups
      @logger.info("Starting cleanup of old AMI backups")
      cutoff_date = (Time.now - (@node['trp-ami-backup']['retention_period'].to_i * 24 * 60 * 60))

      # List objects in S3 bucket
      @s3_client.list_objects_v2({
        bucket: @node['trp-ami-backup']['s3_bucket'],
        prefix: 'ami-backups/'
      }).contents.each do |object|
        if object.last_modified < cutoff_date
          @logger.info("Deleting old backup: #{object.key}")
          @s3_client.delete_object({
            bucket: @node['trp-ami-backup']['s3_bucket'],
            key: object.key
          })
        end
      end
    end

    private

    def matches_name_pattern?(name)
      patterns = ['RHEL-7', 'RHEL-8', 'RHEL-9']
      patterns.any? { |pattern| name.upcase.include?(pattern) }
    end

    def send_email_notification(ami_id, metadata)
      Mail.defaults do
        delivery_method :smtp, {
          address: @node['trp-ami-backup']['email']['server'],
          port: @node['trp-ami-backup']['email']['port'],
          enable_starttls_auto: false
        }
      end

      mail = Mail.new
      mail.from = @node['trp-ami-backup']['email']['from']
      mail.to = @node['trp-ami-backup']['email']['to']
      mail.subject = "AMI Backup Completed - #{ami_id}"
      mail.body = generate_email_body(ami_id, metadata)
      mail.deliver!
    end

    def generate_email_body(ami_id, metadata)
      <<-EMAIL
        AMI Backup Completed Successfully
        
        AMI ID: #{ami_id}
        Creation Date: #{metadata[:creation_date]}
        AMI Name: #{metadata[:ami_name]}
        
        Backup Location: s3://#{@node['trp-ami-backup']['s3_bucket']}/ami-backups/#{ami_id}/
        
        Additional Details:
        #{JSON.pretty_generate(metadata)}
      EMAIL
    end

    def get_metadata_from_s3(ami_id)
      begin
        response = @s3_client.get_object({
          bucket: @node['trp-ami-backup']['s3_bucket'],
          key: "ami-backups/#{ami_id}/metadata.json"
        })
        JSON.parse(response.body.read, symbolize_names: true)
      rescue Aws::S3::Errors::NoSuchKey
        @logger.warn("No metadata found for AMI #{ami_id}")
        nil
      end
    end

    def monitor_import_task(task_id)
      @logger.info("Monitoring import task #{task_id}")
      loop do
        response = @ec2_client.describe_import_image_tasks({
          import_task_ids: [task_id]
        })
        task = response.import_image_tasks.first
        
        @logger.info("Import task status: #{task.status} - Progress: #{task.progress}%")
        break if ['completed', 'deleted'].include?(task.status.downcase)
        sleep 30
      end
    end

    def get_ami_details(ami_id)
      @logger.info("Fetching details for AMI #{ami_id}")
      response = @ec2_client.describe_images(image_ids: [ami_id])
      
      if response.images.empty?
        @logger.error("AMI #{ami_id} not found")
        raise "AMI #{ami_id} not found"
      end
      
      response.images.first
    end

    def prepare_s3_tags(ami_details)
      tags = [
        { key: 'BackupDate', value: Time.now.iso8601 },
        { key: 'AMI_ID', value: ami_details.image_id },
        { key: 'AMI_Name', value: ami_details.name || 'N/A' },
        { key: 'AMI_CreationDate', value: ami_details.creation_date },
        { key: 'Platform', value: ami_details.platform || 'N/A' },
        { key: 'Architecture', value: ami_details.architecture || 'N/A' },
        { key: 'RootDeviceType', value: ami_details.root_device_type || 'N/A' },
        { key: 'VirtualizationType', value: ami_details.virtualization_type || 'N/A' }
      ]

      # Add AMI tags
      if ami_details.tags
        ami_details.tags.each do |tag|
          tags << { key: "AMI_Tag_#{tag.key}", value: tag.value }
        end
      end

      tags
    end
  end
end 