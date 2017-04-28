
# to be automatically replaced by the "stage1" script
SNAPSHOT=
CFG_IP=
TEST_DURATION=
TEST_TARGET_RPS=

jmeter_deployment_node_ip=
keystone_internal_ip=
keystone_user=
keystone_password=

testrail_user=
testrail_password=

# Destination dirs
tests_basedir="$(echo ~/)jmeter_tests"
jmeter_dest_home="$tests_basedir/jmeter"
scenarios_dest_home="$tests_basedir/scenarios"
testresults_dest_home="$tests_basedir/results"
utils_dest_home="$tests_basedir/utils"

jmeter_results_storage="$(echo ~/)jmeter_test_results_bkp"

echo "Unpacking JMeter environment..."
tar -zxf $jmeter_dest_home/jmeter_w_plugins.tar.gz -C $jmeter_dest_home && chmod 755 $tests_basedir -R || exit 1

# clear results dir (for case when this script was run manually)
rm $testresults_dest_home/*

# Run Jmeter tests for current Keystone configuration
for jmx_file in $(ls $scenarios_dest_home | grep .jmx || exit 1); do
  
  # obtaining fullpath for each *.jtl-file
  jtl_filename=$testresults_dest_home/$(echo $jmx_file | cut -f 1 -d ".").jtl

  echo "\nExecuting scenario '$jmx_file' saving results to '$jtl_filename'"
  scen_exec_string="timeout --kill-after=5s --signal=9 $((TEST_DURATION+10)) \
                    $jmeter_dest_home/bin/jmeter -n -t $scenarios_dest_home/$jmx_file \
                                                 -JKEYSTONE_IP="$keystone_internal_ip" \
                                                 -Jload_duration="$TEST_DURATION" \
                                                 -Jtarget_load_rps="$TEST_TARGET_RPS" \
                                                 -Jusername=$keystone_user \
                                                 -Jpassword=$keystone_password\
                                                 -Jjtl_logfile=$jtl_filename"
  echo $scen_exec_string
  $scen_exec_string
  echo "Scenario '$jmx_file' is finished."

  echo "Building report for scenario "$jmx_file""
  percentilles_report_file="$(echo $jmx_file | cut -f 1 -d ".")_percentilles_report.csv"
  synthesis_report_file="$(echo $jmx_file | cut -f 1 -d ".")_synthesis_report.csv"
  java -jar $jmeter_dest_home/lib/ext/CMDRunner.jar --tool Reporter --generate-csv $testresults_dest_home/$percentilles_report_file \
                                                    --input-jtl $jtl_filename --plugin-type ResponseTimesPercentiles --start-offset 20
  java -jar $jmeter_dest_home/lib/ext/CMDRunner.jar --tool Reporter --generate-csv $testresults_dest_home/$synthesis_report_file \
                                                    --input-jtl $jtl_filename --plugin-type SynthesisReport --start-offset 20
done

# Save results to a local directory 
mkdir -p $jmeter_results_storage || exit 1
results_storage_dir=$jmeter_results_storage/$(printf "keystone_perf_testrun_results_$(date +%d.%m.%Y_%H-%M-%S)") || exit 1
mkdir $results_storage_dir || exit 1
cp -r --copy-contents $testresults_dest_home/* $results_storage_dir/ || exit 1

# Save results to a remote host 
# target host and target dir to upload the results need to be clarified
#echo "Saving result files to $testresults_remote_dir directory on the Jenkins node"
#scp -r -o StrictHostKeyChecking=no $results_storage_dir/* $remote_host_user@$remote_storage_host:~/$testresults_remote_dir/"

# send stats to TestRail (uncomment when necessary)
# echo "Saving results to TestRail. . ."
#python ~/$utils_dest_home/jmeter_reports_parser.py ~/$testresults_dest_home/ ~/$scenarios_dest_home/ $estimated_test_duration $SNAPSHOT $CFG_IP $jmeter_deployment_node_ip $testrail_user $testrail_password
