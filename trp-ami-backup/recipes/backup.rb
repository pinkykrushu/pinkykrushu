include_recipe 'trp-ami-backup::default'

# Load the AMI helper library
::Chef::Recipe.send(:include, TrpAmiBackup)

require_relative '../libraries/ami_helper'

# Create log directory
directory node['trp-ami-backup']['log_dir'] do
  owner 'root'
  group 'root'
  mode '0755'
  recursive true
  action :create
end

# Backup eligible AMIs
ruby_block 'backup_eligible_amis' do
  block do
    # Initialize AMI helper
    helper = TrpAmiBackup::AmiHelper.new(
      node['trp-ami-backup']['aws_region'],
      node['trp-ami-backup']['s3_bucket'],
      node['trp-ami-backup']['log_dir'],
      node['trp-ami-backup']['proxy']['https']
    )

    # Find and backup eligible AMIs
    begin
      eligible_amis = helper.find_eligible_amis
      Chef::Log.info("Found #{eligible_amis.length} eligible AMIs for backup")
      
      eligible_amis.each do |ami|
        Chef::Log.info("Found eligible AMI: #{ami.image_id} (#{ami.name})")
      end

      results = helper.backup_all_eligible_amis
      
      # Store results in node for potential future use
      node.run_state['ami_backup_results'] = results
      
      Chef::Log.info("Successfully backed up #{results.length} AMIs")
      results.each do |result|
        Chef::Log.info("Backed up AMI #{result[:ami_id]} with task #{result[:task_id]}")
      end
    rescue StandardError => e
      Chef::Log.error("Error during AMI backup process: #{e.message}")
      Chef::Log.error(e.backtrace.join("\n"))
      raise
    end
  end
  action :run
end

# Cleanup old backups
ruby_block 'cleanup_old_backups' do
  block do
    helper = AmiHelper.new(node)
    helper.cleanup_old_backups
  end
  action :run
  only_if { node['trp-ami-backup']['retention_period'] }
end 