require 'aws-sdk-ec2'
require 'aws-sdk-s3'
require 'json'
require 'logger'
require 'time'
require 'uri'
require 'net/http'

module TrpAmiBackup
  class AmiHelper
    TASK_TIMEOUT = 5400 # 90 minutes in seconds
    TASK_POLL_INTERVAL = 30 # 30 seconds between status checks
    AMI_MAX_AGE_DAYS = 180 # 6 months

    attr_reader :logger

    def initialize(aws_credentials, region, s3_bucket, log_dir = '/var/log/ami_backup', proxy_url = nil)
      @region = region
      @s3_bucket = s3_bucket
      @aws_credentials = aws_credentials
      setup_logging(log_dir)
      setup_aws_clients(proxy_url)
    end

    def setup_logging(log_dir)
      Dir.mkdir(log_dir) unless Dir.exist?(log_dir)
      @logger = Logger.new(File.join(log_dir, 'ami_backup.log'), 'daily')
      @logger.level = Logger::INFO
      @logger.formatter = proc do |severity, datetime, progname, msg|
        "[#{datetime}] #{severity}: #{msg}\n"
      end
    end

    def setup_aws_clients(proxy_url)
      # Common AWS client options
      client_options = {
        region: @region,
        credentials: Aws::Credentials.new(
          @aws_credentials[:access_key_id],
          @aws_credentials[:secret_access_key]
        )
      }

      # Add proxy configuration if provided
      if proxy_url
        proxy_uri = URI(proxy_url)
        client_options[:http_proxy] = {
          uri: proxy_uri
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
        {
          ami_id: ami_id,
          task_id: task.image_task_id,
          name: ami_details.name,
          creation_date: ami_details.creation_date,
          backup_date: Time.now.iso8601
        }
      rescue Aws::EC2::Errors::ServiceError => e
        @logger.error("AWS EC2 error while backing up AMI #{ami_id}: #{e.message}")
        raise
      end
    end

    private

    def matches_name_pattern?(name)
      patterns = ['RHEL-7', 'RHEL-8', 'RHEL-9']
      patterns.any? { |pattern| name.upcase.include?(pattern) }
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

    def create_store_image_task(ami_id, s3_tags)
      @logger.info("Creating store image task for AMI #{ami_id}")
      @logger.info("S3 tags to be applied: #{s3_tags}")

      @ec2_client.create_store_image_task({
        image_id: ami_id,
        bucket: @s3_bucket,
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
  end
end 