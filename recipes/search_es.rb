#
# Cookbook:: backend_search_cluster
# Recipe:: search_es.rb
#
# Copyright:: 2017, The Authors, All Rights Reserved.

include_recipe 'sysctl::apply'

include_recipe 'java'

elasticsearch_user 'elasticsearch'

directory '/var/run/elasticsearch' do
  action :create
  recursive true
  owner 'elasticsearch'
  group 'elasticsearch'
end

elasticsearch_config = {
  'cluster.name' => node['elasticsearch']['cluster_name'] || 'elasticsearch',
  'node.name' => node['hostname'],
  'network.host' => node['ipaddress'],
  'discovery.type' => 'ec2',
  'cloud.aws.region' => node['aws']['region'],
  'http.max_content_length': '1gb',
}

elasticsearch_install 'elasticsearch' do
  type :tarball # type of install
  dir tarball: '/opt/' # where to install
  download_url 'https://download.elastic.co/elasticsearch/release/org/elasticsearch/distribution/tar/elasticsearch/2.4.1/elasticsearch-2.4.1.tar.gz'
  download_checksum '23a369ef42955c19aaaf9e34891eea3a055ed217d7fbe76da0998a7a54bbe167'
  action :install # could be :remove as well
end

half_system_ram = (node['memory']['total'].to_i * 0.5).floor / 1024

elasticsearch_configure 'elasticsearch' do
  # if you override one of these, you probably want to override all
  path_home     tarball: '/opt/elasticsearch'
  path_conf     tarball: '/etc/elasticsearch'
  path_data     tarball: '/var/opt/elasticsearch'
  path_logs     tarball: '/var/log/elasticsearch'
  path_pid      tarball: '/var/run/elasticsearch'
  path_plugins  tarball: '/opt/elasticsearch/plugins'
  path_bin      tarball: '/opt/elasticsearch/bin'
  logging(action: 'INFO')
  thread_stack_size '512k'
  gc_settings <<-CONFIG
              -XX:+UseParNewGC
              -XX:+UseConcMarkSweepGC
              -XX:CMSInitiatingOccupancyFraction=75
              -XX:+UseCMSInitiatingOccupancyOnly
              -XX:+HeapDumpOnOutOfMemoryError
              -XX:+PrintGCDetails
            CONFIG

  configuration elasticsearch_config
  action :manage
  notifies :restart, 'service[elasticsearch]', :delayed
end

%w(/opt/elasticsearch/plugins /opt/elasticsearch/plugins/cloud-aws).each do |dir|
  directory dir do
    owner 'elasticsearch'
    group 'elasticsearch'
  end
end

remote_file 'cloud-aws-2.4.1.zip' do
  source 'https://download.elastic.co/elasticsearch/release/org/elasticsearch/plugin/cloud-aws/2.4.1/cloud-aws-2.4.1.zip'
  path '/tmp/cloud-aws-2.4.1.zip'
  notifies :run, 'execute[unzip cloud-aws]', :immediately
end

execute 'unzip cloud-aws' do
  command 'unzip /tmp/cloud-aws-2.4.1.zip -d /opt/elasticsearch/plugins/cloud-aws'
  action :nothing
end

link '/opt/elasticsearch/elasticsearch' do
  to '/etc/sysconfig/elasticsearch'
end

elasticsearch_service 'elasticsearch' do
  action :nothing
end

template '/usr/lib/systemd/system/elasticsearch.service' do
  owner 'root'
  mode '0644'
  source 'systemd_unit.erb'
  variables(
    # we need to include something about #{progname} fixed in here.
    program_name: 'elasticsearch',
    default_dir: '/opt/elasticsearch',
    path_home: '/opt/elasticsearch',
    es_user: 'elasticsearch',
    es_group: 'elasticsearch',
    nofile_limit: '65536'
  )
  notifies :restart, 'service[elasticsearch]', :immediately
end

service 'elasticsearch' do
  action [:enable, :start]
end
