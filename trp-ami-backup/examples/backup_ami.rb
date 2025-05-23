#!/usr/bin/env ruby

require_relative '../libraries/ami_helper'

# Configuration
region = 'us-east-1'
s3_bucket = 's3-trp-ami-backup'
log_dir = '/var/log/ami_backup'
proxy_url = 'http://proxy.example.com:8080' # Set to nil if no proxy is needed

# Initialize the AMI helper
helper = TrpAmiBackup::AmiHelper.new(region, s3_bucket, log_dir, proxy_url)

begin
  # Find all eligible AMIs (RHEL-7, RHEL-8, RHEL-9 created within last 6 months)
  eligible_amis = helper.find_eligible_amis
  
  puts "Found #{eligible_amis.length} eligible AMIs:"
  eligible_amis.each do |ami|
    puts "- #{ami.image_id}: #{ami.name} (Created: #{ami.creation_date})"
  end

  # Backup all eligible AMIs
  results = helper.backup_all_eligible_amis
  
  puts "\nBackup Results:"
  puts "Successfully backed up #{results.length} AMIs:"
  results.each do |result|
    puts "- AMI ID: #{result[:ami_id]}"
    puts "  Task ID: #{result[:task_id]}"
  end

rescue StandardError => e
  puts "Error during backup process: #{e.message}"
  exit 1
end 