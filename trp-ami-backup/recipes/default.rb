# Create log directory
directory node['trp-ami-backup']['log_dir'] do
  owner 'root'
  group 'root'
  mode '0755'
  recursive true
  action :create
end

# Install required gems
%w(aws-sdk-ec2 aws-sdk-s3 mail).each do |gem_name|
  chef_gem gem_name do
    compile_time true
    action :install
  end
end

# Ensure AWS credentials data bag exists
ruby_block 'verify_aws_credentials' do
  block do
    begin
      Chef::EncryptedDataBagItem.load('aws', 'credentials')
    rescue
      Chef::Log.fatal('AWS credentials data bag not found or cannot be decrypted')
      raise
    end
  end
  action :run
end 