$host = $facts['networking']['ip']
$metadata_secret = 'metadata_secret'
$auth_url = "http://${host}:5000"

class { 'apache':
  default_mods  => false,
  default_vhost => false,
}

class { 'memcached':
  max_memory => '10%',
  before     => [
    Anchor['keystone::service::begin'],
    Anchor['placement::service::begin'],
    Anchor['glance::service::begin'],
    Anchor['nova::service::begin'],
    Anchor['neutron::service::begin'],
  ]
}
class { 'mysql::server': }
class { 'rabbitmq':
  delete_guest_user     => true,
  repos_ensure          => false,
  manage_python         => false,
  node_ip_address       => '127.0.0.1',
  management_ip_address => '127.0.0.1',
}
rabbitmq_vhost { '/': }
rabbitmq_user { 'openstack':
  admin    => true,
  password => 'mqpass',
}
rabbitmq_user_permissions { 'openstack@/':
  configure_permission => '.*',
  write_permission     => '.*',
  read_permission      => '.*',
  before               => [
    Anchor['neutron::service::begin'],
    Anchor['nova::service::begin'],
  ],
}

$transport_url = os_transport_url({
  'transport' => 'rabbit',
  'host'      => '127.0.0.1',
  'port'      => '5672',
  'username'  => 'openstack',
  'password'  => 'mqpass',
})

# openvswitch
class { 'vswitch::ovs': }
-> package { 'NetworkManager-ovs':
  ensure => 'present'
}
~> exec { 'systemctl-daemon-reload-ovs':
  command     => ['systemctl', 'daemon-reload'],
  path        => ['/bin', '/sbin', '/usr/bin', '/usr/sbin'],
  refreshonly => true,
}
~> service { 'NetworkManager':
  ensure => 'running',
  enable => true,
}
-> exec { 'create-bridge':
  command => ['nmcli', 'con', 'add', 'type', 'ovs-bridge', 'con-name', 'br-ex', 'conn.interface', 'br-ex'],
  path    => ['/bin', '/sbin', '/usr/bin', '/usr/sbin'],
  unless  => 'nmcli con show br-ex',
  require => Class['vswitch::ovs']
} ~> exec { 'create-port':
  command     => [
    'nmcli', 'con', 'add', 'type', 'ovs-port', 'con-name', 'port0',
    'conn.interface', 'port0', 'master', 'br-ex'
  ],
  path        => ['/bin', '/sbin', '/usr/bin', '/usr/sbin'],
  refreshonly => true,
} ~> exec { 'create-interface':
  command     => [
    'nmcli', 'con', 'add', 'type', 'ovs-interface', 'con-name', 'iface0',
    'slave-type', 'ovs-port', 'conn.interface', 'br-ex', 'master', 'port0',
    'ipv4.method', 'manual', 'ipv4.address', '172.24.5.1/24',
    'ipv6.method', 'disabled'
  ],
  path        => ['/bin', '/sbin', '/usr/bin', '/usr/sbin'],
  refreshonly => true,
  before      => Anchor['neutron::service::begin']
}

# horizon
class { 'horizon':
  secret_key       => 'secretkey',
  cache_backend    => 'django.core.cache.backends.memcached.PyMemcacheCache',
  cache_server_url => ['127.0.0.1:11211'],
  allowed_hosts    => '*',
  wsgi_processes   => 2,
  keystone_url     => $auth_url,
  log_level        => 'DEBUG',
}
class { 'horizon::policy': }

# keystone
class { 'keystone::db::mysql':
  password => 'keystonedbpass',
  host     => '127.0.0.1',
}
class { 'keystone::db':
  database_connection => os_database_connection({
    'dialect'  => 'mysql+pymysql',
    'host'     => '127.0.0.1',
    'username' => 'keystone',
    'password' => 'keystonedbpass',
    'database' => 'keystone',
    'charset'  => 'utf8',
  }),
}
class { 'keystone::logging':
  debug => true,
}
class { 'keystone::cache':
  backend          => 'dogpile.cache.pymemcache',
  enabled          => true,
  memcache_servers => ['127.0.0.1:11211'],
}
class { 'keystone':
  service_name => 'httpd',
}
class { 'keystone::wsgi::apache':
  bind_host => $host,
  workers   => 2,
}
class { 'keystone::bootstrap':
  password   => 'adminpass',
  public_url => $auth_url,
  admin_url  => $auth_url,
}

# placement
class { 'placement::client': }
class { 'placement::db::mysql':
  password => 'placementdbpass'
}
class { 'placement::db':
  database_connection => os_database_connection({
    'dialect'  => 'mysql+pymysql',
    'host'     => '127.0.0.1',
    'username' => 'placement',
    'password' => 'placementdbpass',
    'database' => 'placement',
    'charset'  => 'utf8',
  }),
}
class { 'placement::db::sync': }
class { 'placement::keystone::auth':
  password     => 'placementpass',
  public_url   => "http://${host}:8778",
  internal_url => "http://${host}:8778",
  admin_url    => "http://${host}:8778",
}
class { 'placement::keystone::authtoken':
  password             => 'placementpass',
  auth_url             => $auth_url,
  www_authenticate_uri => $auth_url,
  memcached_servers    => ['127.0.0.1:11211'],
}
class { 'placement::logging':
  debug => true
}
class { 'placement::api':
  api_service_name => 'httpd',
}
class { 'placement::wsgi::apache':
  bind_host => $host,
  workers   => 2,
}

# glance
class { 'glance::db::mysql':
  password => 'glancedbpass',
}
class { 'glance': }
class { 'glance::api::db':
  database_connection => os_database_connection({
    'dialect'  => 'mysql+pymysql',
    'host'     => '127.0.0.1',
    'username' => 'glance',
    'password' => 'glancedbpass',
    'database' => 'glance',
    'charset'  => 'utf8',
  }),
}
class { 'glance::api::logging':
  debug => false
}
class { 'glance::keystone::auth':
  password     => 'glancepass',
  public_url   => "http://${host}:9292",
  internal_url => "http://${host}:9292",
  admin_url    => "http://${host}:9292",
}
class { 'glance::api::authtoken':
  password             => 'glancepass',
  auth_url             => $auth_url,
  www_authenticate_uri => $auth_url,
  memcached_servers    => ['127.0.0.1:11211'],
}
class { 'glance::api':
  enabled_backends => ['file1:file'],
  default_backend  => 'file1',
  service_name     => 'httpd',
}
class { 'glance::wsgi::apache':
  bind_host => $host,
  workers   => 2,
}
glance::backend::multistore::file { 'file1': }

# neutron
class { 'neutron::db::mysql':
  password => 'neutrondbpass'
}
class { 'neutron::db':
  database_connection => os_database_connection({
    'dialect'  => 'mysql+pymysql',
    'host'     => '127.0.0.1',
    'username' => 'neutron',
    'password' => 'neutrondbpass',
    'database' => 'neutron',
    'charset'  => 'utf8',
  }),
}
class { 'neutron::logging':
  debug => true,
}
class { 'neutron':
  default_transport_url => $transport_url,
  core_plugin           => 'ml2',
  bind_host             => $host,
  service_plugins       => ['router', 'qos'],
}
class { 'neutron::keystone::auth':
  password     => 'neutronpass',
  public_url   => "http://${host}:9696",
  internal_url => "http://${host}:9696",
  admin_url    => "http://${host}:9696",
}
class { 'neutron::keystone::authtoken':
  password             => 'neutronpass',
  auth_url             => $auth_url,
  www_authenticate_uri => $auth_url,
  memcached_servers    => ['127.0.0.1:11211'],
}
class { 'neutron::server':
  sync_db     => true,
  api_workers => 2,
  rpc_workers => 2,
}
class { 'neutron::plugins::ml2':
  type_drivers         => ['vxlan', 'vlan', 'flat'],
  tenant_network_types => ['vxlan'],
  extension_drivers    => ['port_security', 'qos'],
  mechanism_drivers    => ['openvswitch'],
  network_vlan_ranges  => 'external:1000:2999',
}
class { 'neutron::agents::ml2::ovs':
  local_ip        => $facts['networking']['ip'],
  tunnel_types    => ['vxlan'],
  bridge_mappings => ['external:br-ex'],
  manage_vswitch  => false,
  firewall_driver => 'openvswitch',
}
class { 'neutron::agents::metadata':
  debug            => true,
  shared_secret    => $metadata_secret,
  metadata_workers => 2,
  metadata_host    => $host,
}
class { 'neutron::agents::l3':
  debug            => true,
  interface_driver => 'openvswitch'
}
class { 'neutron::agents::dhcp':
  debug            => true,
  interface_driver => 'openvswitch'
}
class { 'neutron::server::notifications': }
class { 'neutron::server::notifications::nova':
  auth_url => $auth_url,
  password => 'novapass'
}
class { 'neutron::server::placement':
  auth_url => $auth_url,
  password => 'placementpass'
}

# nova
class { 'nova::db::mysql':
  password => 'novadbpass',
}
class { 'nova::db::mysql_api':
  password => 'novadbpass',
}
class { 'nova::db':
  database_connection     => os_database_connection({
    'dialect'  => 'mysql+pymysql',
    'host'     => '127.0.0.1',
    'username' => 'nova',
    'password' => 'novadbpass',
    'database' => 'nova',
    'charset'  => 'utf8',
  }),
  api_database_connection => os_database_connection({
    'dialect'  => 'mysql+pymysql',
    'host'     => '127.0.0.1',
    'username' => 'nova_api',
    'password' => 'novadbpass',
    'database' => 'nova_api',
    'charset'  => 'utf8',
  }),
}
class { 'nova::db::sync': }
class { 'nova::db::sync_api': }
class { 'nova::logging':
  debug => true,
}
class { 'nova::cell_v2::simple_setup': }
exec { 'wait-for-compute-registration':
  command     => ['sleep', '60'],
  path        => ['/bin', '/usr/bin'],
  refreshonly => true,
  notify      => Class['nova::cell_v2::discover_hosts'],
  subscribe   => Anchor['nova::service::end'],
}
class { 'nova::keystone::auth':
  password     => 'novapass',
  public_url   => "http://${host}:8774/v2.1",
  internal_url => "http://${host}:8774/v2.1",
  admin_url    => "http://${host}:8774/v2.1",
  roles        => ['admin', 'service']
}
class { 'nova::keystone::authtoken':
  password             => 'novapass',
  auth_url             => $auth_url,
  www_authenticate_uri => $auth_url,
  memcached_servers    => ['127.0.0.1:11211'],
}
class { 'nova::keystone::service_user':
  send_service_user_token => true,
  password                => 'novapass',
  auth_url                => $auth_url,
}
class { 'nova':
  default_transport_url => $transport_url,
}
class { 'nova::api':
  service_name => 'httpd',
}
class { 'nova::metadata':
  neutron_metadata_proxy_shared_secret => $metadata_secret,
}
class { 'nova::wsgi::apache_api':
  bind_host => $host,
  workers   => 2,
}
class { 'nova::wsgi::apache_metadata':
  bind_host => $host,
  workers   => 2,
}
class { 'nova::cache':
  backend          => 'dogpile.cache.pymemcache',
  enabled          => true,
  memcache_servers => ['127.0.0.1:11211'],
}
class { 'nova::placement':
  auth_url => $auth_url,
  password => 'placementpass',
}
class { 'nova::conductor':
  workers => 2,
}
class { 'nova::scheduler':
  workers => 2,
}
class { 'nova::scheduler::filter': }
class { 'nova::vncproxy':
  host => $host,
}
class { 'nova::network::neutron':
  auth_url              => $auth_url,
  password              => 'neutronpass',
  default_floating_pool => 'public',
}
class { 'nova::cinder':
  auth_url  => $auth_url,
  password  => 'cinderpass',
  auth_type => 'password'
}
class { 'nova::compute':
  vnc_enabled   => true,
  vncproxy_host => $host,
}
class { 'nova::migration::libvirt':
  transport      => 'tcp',
  listen_address => $host,
}
class { 'nova::compute::libvirt':
  virt_type               => 'kvm',
  manage_libvirt_services => false,
}
class { 'nova::compute::libvirt::services': }
class { 'nova::compute::libvirt::networks': }

Anchor['placement::service::end'] -> Service['nova-compute']
Anchor['placement::service::end'] -> Service['nova-conductor']

Keystone_endpoint <||> -> Service['nova-compute']
Keystone_service <||> -> Service['nova-compute']
Keystone_endpoint <||> -> Service['nova-conductor']
Keystone_service <||> -> Service['nova-conductor']
Keystone_endpoint <||> -> Service['nova-scheduler']
Keystone_service <||> -> Service['nova-scheduler']

# resources

nova_flavor { 'm1.nano':
  ensure => present,
  id     => '42',
  ram    => '128',
  disk   => '2',
  vcpus  => '1',
}
nova_flavor { 'm1.micro':
  ensure => present,
  id     => '84',
  ram    => '128',
  disk   => '2',
  vcpus  => '1',
}

glance_image { 'cirros':
  container_format => 'bare',
  disk_format      => 'qcow2',
  is_public        => 'yes',
  source           => 'http://download.cirros-cloud.net/0.6.3/cirros-0.6.3-x86_64-disk.img'
}

neutron_network { 'public':
  router_external           => true,
  provider_physical_network => 'external',
  provider_network_type     => 'flat'
}
neutron_subnet { 'public-subnet':
  cidr             => '172.24.5.0/24',
  ip_version       => '4',
  allocation_pools => ['start=172.24.5.10,end=172.24.5.200'],
  gateway_ip       => '172.24.5.1',
  enable_dhcp      => false,
  network_name     => 'public',
}

file { '/root/.config':
  ensure => directory,
  mode   => '0755',
  owner  => 'root',
  group  => 'root',
}
file { '/root/.config/openstack':
  ensure => directory,
  mode   => '0755',
  owner  => 'root',
  group  => 'root',
}
file { '/root/.config/openstack/clouds.yaml':
  ensure    => present,
  mode      => '0600',
  owner     => 'root',
  group     => 'root',
  show_diff => false,
  content   => to_yaml({
    'clouds' => {
      'admin' => {
        'auth'        => {
          'auth_url'            => $auth_url,
          'password'            => 'adminpass',
          'username'            => 'admin',
          'user_domain_name'    => 'Default',
          'project_name'        => 'admin',
          'project_domain_name' => 'Default',
        },
        'interface'   => 'public',
        'region_name' => 'RegionOne'
      }
    }
  })
}
file { '/tmp/motd-openstack':
  ensure  => present,
  mode    => '0644',
  owner   => 'root',
  group   => 'root',
  content => "=============== OpenStack All-in-one ===============
Dashboard is available at: http://${host}/
  Login user    : admin
  Login password: adminpass

Use openstack command to interact with APIs by CLI.
  example.
    \$ openstack server list
    \$ openstack network list"
}
