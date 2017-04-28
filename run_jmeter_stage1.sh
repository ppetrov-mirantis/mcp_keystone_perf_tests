# Destination dirs
tests_basedir="jmeter_tests"
jmeter_dest_home="$tests_basedir/jmeter"
scenarios_dest_home="$tests_basedir/scenarios"
testresults_dest_home="$tests_basedir/results"
utils_dest_home="$tests_basedir/utils"

cfg_node_login=
cfg_node_password=

SNAPSHOT=
CFG_IP=
# test duration (sec.)
TEST_DURATION=

keystone_user=
keystone_password=

# TestRail reporting credentials
testrail_user=
testrail_password=

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

# Install Java if necessary
$jmeter_node_ssh_connection sh << 'EOF'
java_pkgs_number=$(dpkg-query -l *jre | grep ii | tr -s " " | cut -f 2 -d " " | wc -l)
if [ $java_pkgs_number -lt 1 ]
  then
    echo "Installing java..."
    sudo apt-get update && sudo apt-get --yes --force-yes install openjdk-8-jre
  else
    echo "Java packages are already installed: $(dpkg-query -l *jre | grep ii | tr -s " " | cut -f 2 -d " ")"
fi
EOF

# Create target directory
$jmeter_node_ssh_connection "'(rm -r $tests_basedir 2>/dev/null || echo > /dev/null) && mkdir $tests_basedir'" || exit 1

# Upload test infrastructure
# !!!!! Repo address string should be replaced after merging to the internal performace-qa repo !!!!!
echo "Uploading JMeter environment..."
$jmeter_node_ssh_connection "'git clone https://github.com/ppetrov-mirantis/mcp_keystone_perf_tests/ ~/$tests_basedir/'"

echo "Starting stage-2 script"
$jmeter_node_ssh_connection "'sed -i "-e s/SNAPSHOT=$/SNAPSHOT=$SNAPSHOT/g \
                                      -e s/CFG_IP=$/CFG_IP=$CFG_IP/g \
                                      -e s/TEST_DURATION=$/TEST_DURATION=$TEST_DURATION/g \
                                      -e s/jmeter_deployment_node_ip=$/jmeter_deployment_node_ip=$jmeter_deployment_node_ip/g \
                                      -e s/keystone_internal_ip=$/keystone_internal_ip=$keystone_internal_ip/g \
                                      -e s/keystone_user=$/keystone_user=$keystone_user/g \
                                      -e s/keystone_password=$/keystone_password=$keystone_password/g \
                                      -e s/testrail_user=$/testrail_user=$testrail_user/g \
                                      -e s/testrail_password=$/testrail_password=$testrail_password/g" \
                                         ~/$tests_basedir/run_jmeter_stage2.sh'"

sshpass -p $cfg_node_password ssh -tt -o StrictHostKeyChecking=no $cfg_node_login@$CFG_IP "sudo ssh -tt $jmeter_deployment_node_ip '~/$tests_basedir/run_jmeter_stage2.sh'"
