#!/usr/bin/env ruby

require_relative '../libraries/ami_helper'
require 'optparse'
require 'yaml'

# Parse command line options
options = {
  config_file: nil,
  region: 'us-east-1',
  log_dir: '/var/log/ami_backup'
}

OptionParser.new do |opts|
  opts.banner = "Usage: backup_amis.rb [options]"

  opts.on("-c", "--config FILE", "Configuration file path") do |file|
    options[:config_file] = file
  end

  opts.on("-r", "--region REGION", "AWS region") do |region|
    options[:region] = region
  end

  opts.on("-l", "--log-dir DIR", "Log directory") do |dir|
    options[:log_dir] = dir
  end

  opts.on("-h", "--help", "Show this help message") do
    puts opts
    exit
  end
end.parse!

# Load configuration
if options[:config_file]
  begin
    config = YAML.load_file(options[:config_file])
  rescue => e
    puts "Error loading configuration file: #{e.message}"
    exit 1
  end
else
  puts "Configuration file is required. Use -c or --config option."
  exit 1
end

begin
  # Initialize the AMI helper
  helper = TrpAmiBackup::AmiHelper.new(
    {
      access_key_id: config['aws']['access_key_id'],
      secret_access_key: config['aws']['secret_access_key']
    },
    options[:region],
    config['s3_bucket'],
    options[:log_dir],
    config['proxy_url']
  )

  # Find eligible AMIs
  eligible_amis = helper.find_eligible_amis
  helper.logger.info("Found #{eligible_amis.length} eligible AMIs:")
  eligible_amis.each do |ami|
    helper.logger.info("  - #{ami.image_id}: #{ami.name} (Created: #{ami.creation_date})")
  end

  # Backup all eligible AMIs
  results = helper.backup_all_eligible_amis

  # Output results
  helper.logger.info("\nBackup Results:")
  helper.logger.info("Successfully backed up #{results.length} AMIs:")
  results.each do |result|
    helper.logger.info("  - AMI ID: #{result[:ami_id]}")
    helper.logger.info("    Name: #{result[:name]}")
    helper.logger.info("    Task ID: #{result[:task_id]}")
    helper.logger.info("    Creation Date: #{result[:creation_date]}")
    helper.logger.info("    Backup Date: #{result[:backup_date]}")
  end

rescue StandardError => e
  puts "Error: #{e.message}"
  puts e.backtrace
  exit 1
end 