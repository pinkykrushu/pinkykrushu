include_recipe 'trp-ami-backup::default'

# Load the AMI helper library
::Chef::Recipe.send(:include, TrpAmiBackup)

# Restore AMI from backup
ruby_block 'restore_ami' do
  block do
    # Ensure AMI ID is provided
    unless node['trp-ami-backup']['restore_ami_id']
      Chef::Log.fatal('No AMI ID provided for restoration. Set node["trp-ami-backup"]["restore_ami_id"]')
      raise
    end

    helper = AmiHelper.new(node)
    
    # Perform restoration
    restored_ami_id = helper.restore_ami(node['trp-ami-backup']['restore_ami_id'])
    
    # Store the result in node attributes for potential future use
    node.run_state['ami_restore_result'] = restored_ami_id
    
    Chef::Log.info("AMI restored successfully. New AMI ID: #{restored_ami_id}")
  end
  action :run
end 