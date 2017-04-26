# Destination dirs
tests_basedir="jmeter_tests"
jmeter_dest_home="$tests_basedir/jmeter"
scenarios_dest_home="$tests_basedir/scenarios"
testresults_dest_home="$tests_basedir/results"
utils_dest_home="$tests_basedir/utils"

cfg_node_login=""
cfg_node_password=""

SNAPSHOT=XY
CFG_IP=

keystone_user=admin
keystone_password=password

echo "Starting stage-1 script"
echo "Connecting to $CFG_IP salt-master ..."
ssh-keygen -f ~/.ssh/known_hosts -R $CFG_IP

cfg_ssh_connection="sshpass -p $cfg_node_password ssh -o StrictHostKeyChecking=no $cfg_node_login@$CFG_IP"

# Getting address of host to deploy and run tests.
#jmeter_deployment_node_ip=$($cfg_ssh_connection "sudo salt 'cmp001*' grains.get ipv4" |\
#                                                  grep 172 | grep -oP '([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})') || exit 1
jmeter_deployment_node_ip=$($cfg_ssh_connection "sudo salt 'cmp001*' pillar.get '_param:linux_single_interface:address'" |\
                                                  grep -oP '([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})') || exit 1

echo "$jmeter_deployment_node_ip"
# Getting Keystone internal IP-address
#contoller_ip=$($cfg_ssh_connection "sudo salt 'ctl03*' grains.get ipv4" |\
#                                                  grep 172 | grep -oP '([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})') || exit 1
contoller_ip=$($cfg_ssh_connection "sudo salt 'ctl02*' pillar.get '_param:linux_single_interface:address'" |\
                                     grep -oP '([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})') || exit 1

echo "$contoller_ip"
keystone_internal_ip=$($cfg_ssh_connection sudo ssh $contoller_ip "cat keystonerc" | grep OS_AUTH_URL | \
                                                              grep -oP '([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})')
echo "Keystone internal IP: $keystone_internal_ip"

jmeter_node_ssh_connection="$cfg_ssh_connection sudo ssh $jmeter_deployment_node_ip "


# Create target directory
$jmeter_node_ssh_connection "'(rm -r $tests_basedir 2>/dev/null || echo > /dev/null) && mkdir $tests_basedir'" || exit 1

$jmeter_node_ssh_connection sh << 'EOF'
java_pkgs_number=$(dpkg-query -l *jre | grep ii | tr -s " " | cut -f 2 -d " " | wc -l)
echo "Pkg_number: $java_pkgs_number" > java_pkg.log
if [ $java_pkgs_number -lt 1 ]
  then
    echo "Installing java..."
    sudo apt-get update && sudo apt-get --yes --force-yes install openjdk-8-jre
  else
    echo "Java packages are already installed: $(dpkg-query -l *jre | grep ii | tr -s " " | cut -f 2 -d " ")"
fi
EOF

# Upload test infrastructure
echo "Uploading JMeter environment..."
#$jmeter_node_ssh_connection "git clone https://github.com/ppetrov-mirantis/mcp_keystone_perf_tests/ ~/$tests_basedir/"

echo "Starting stage-2 script"
$jmeter_node_ssh_connection sh << 'EOF'
  sed -i "s/SNAPSHOT=/SNAPSHOT=$SNAPSHOT/g" ~/$tests_basedir/run_jmeter_stage2.sh
  sed -i "s/CFG_IP=/CFG_IP=$CFG_IP/g" ~/$tests_basedir/run_jmeter_stage2.sh
  sed -i "s/jmeter_deployment_node_ip=/jmeter_deployment_node_ip=$jmeter_deployment_node_ip/g" ~/$tests_basedir/run_jmeter_stage2.sh
  sed -i "s/keystone_internal_ip=/keystone_internal_ip=$keystone_internal_ip/g" ~/$tests_basedir/run_jmeter_stage2.sh
  sed -i "s/keystone_user=/keystone_user=$keystone_user/g" ~/$tests_basedir/run_jmeter_stage2.sh
  sed -i "s/keystone_password=/keystone_password=$keystone_password$/g" ~/$tests_basedir/run_jmeter_stage2.sh
EOF

sshpass -p $cfg_node_password ssh -tt -o StrictHostKeyChecking=no $cfg_node_login@$CFG_IP "sudo ssh -tt $jmeter_deployment_node_ip '~/$tests_basedir/run_jmeter_stage2.sh'"
