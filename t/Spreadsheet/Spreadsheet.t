#!/usr/bin/env perl
use strict;
use warnings;
use Data::Dumper;
use Test::MockObject;
use VRTrack::VRTrack;
use File::Path qw(rmtree);


BEGIN { unshift(@INC, './lib') }
BEGIN {
  use Test::Most;
  use_ok('UpdatePipeline::Spreadsheet');
  
  my $ncbi_taxon_lookup = Test::MockObject->new();
  $ncbi_taxon_lookup->fake_module( 'NCBI::TaxonLookup', test => sub{1} );
  $ncbi_taxon_lookup->fake_new( 'NCBI::TaxonLookup' );
  $ncbi_taxon_lookup->mock('common_name', sub{ 'Some Common Name' });
}

my $vrtrack = initialse_test_setup();

ok my $spreadsheet = UpdatePipeline::Spreadsheet->new(
  filename                => 't/data/external_data_example.xls',
  _vrtrack                => $vrtrack,
  study_names             => [],
  dont_use_warehouse      => 1,
  common_name_required    => 0,
  pipeline_base_directory => 't/data/pipeline_base_directory',
  files_base_directory    => 't/data/path/to/sequencing',
  environment             => 'test'
), 'initialise spreadsheet driver class';
ok $spreadsheet->_files_metadata, 'generate the files metadata';

is $spreadsheet->_files_metadata->[0]->file_name,'myfile_1.fastq.gz', 'filename returned correctly';

is $spreadsheet->_files_metadata->[0]->study_ssid,   123, 'existing study ssid reused';
is $spreadsheet->_files_metadata->[0]->sample_ssid,  457, 'next sample ssid';
is $spreadsheet->_files_metadata->[0]->library_ssid, 790, 'next library ssid used';

is $spreadsheet->_files_metadata->[1]->study_ssid,   123, 'existing study ssid reused';
is $spreadsheet->_files_metadata->[1]->sample_ssid,  456, 'existing sample ssid';
is $spreadsheet->_files_metadata->[1]->library_ssid, 791, 'existing library ssid used';
is $spreadsheet->_files_metadata->[1]->file_type_number($spreadsheet->_files_metadata->[1]->file_type), 1, 'file type set to fastq';


is $spreadsheet->_files_metadata->[2]->study_ssid,   123, 'existing study ssid reused';
is $spreadsheet->_files_metadata->[2]->sample_ssid,  458, 'increment twice sample ssid';
is $spreadsheet->_files_metadata->[2]->library_ssid, 789, 'increment twice library ssid used';


# put in some tests here to check the state
ok $spreadsheet->update();

ok my $vlane = VRTrack::Lane->new_by_name( $vrtrack, 'myfile'), 'retrieve the lane object';
is $vlane->files->[0]->type, 1, 'file type set correctly';
is $vrtrack->hierarchy_path_of_lane($vlane,"genus:species-subspecies:TRACKING:projectssid:sample:technology:library:lane"), 'Some/Common_Name/TRACKING/123/1/SLX/L5_AB_12_2011/myfile', 'Lane path generated correctly indictating primary data in DB okay';
is $vlane->is_processed('import'), 0, 'import initially not set for lane';

ok $spreadsheet->import_sequencing_files_to_pipeline(),'copy the files into the correct location';
ok (-e 't/data/pipeline_base_directory/Some/Common_Name/TRACKING/123/1/SLX/L5_AB_12_2011/myfile/myfile_1.fastq.gz', 'target fastq exists myfile_1');
ok (-e 't/data/pipeline_base_directory/Some/Common_Name/TRACKING/123/2/SLX/EF_CD_12_2011/myotherfile_L3/myotherfile_L3_2.fastq.gz', 'target fastq exists myotherfile_L3_2');
ok (-e 't/data/pipeline_base_directory/Some/Common_Name/TRACKING/123/2/SLX/EF_CD_12_2011/myotherfile_L3/myotherfile_L3_1.fastq.gz', 'target fastq exists myotherfile_L3_1');
ok (-e 't/data/pipeline_base_directory/Some/Common_Name/TRACKING/123/4/SLX/XYZ45678/mysra_file/mysra_file_1.fastq.gz', 'target fastq exists mysra_file_1');
ok (-e 't/data/pipeline_base_directory/Some/Common_Name/TRACKING/123/4/SLX/XYZ45678/mysra_file/mysra_file_2.fastq.gz', 'target fastq exists mysra_file_2');

ok (-e 't/data/pipeline_base_directory/Some/Common_Name/TRACKING/123/1/SLX/L5_AB_12_2011/myfile/myfile_1.fastq.gz.md5', 'md5 hash file exists for myfile_1');
ok (-e 't/data/pipeline_base_directory/Some/Common_Name/TRACKING/123/2/SLX/EF_CD_12_2011/myotherfile_L3/myotherfile_L3_1.fastq.gz.md5', 'md5 hash file exists for myotherfile_L3_1');
ok (-e 't/data/pipeline_base_directory/Some/Common_Name/TRACKING/123/2/SLX/EF_CD_12_2011/myotherfile_L3/myotherfile_L3_2.fastq.gz.md5', 'md5 hash file exists for myotherfile_L3_2');
ok (-e 't/data/pipeline_base_directory/Some/Common_Name/TRACKING/123/3/SLX/ABC45678/yetanotherfile_L4/yetanotherfile_L4_1.fastq.gz.md5', 'md5 hash file exists for yetanotherfile_L4_1');
ok (-e 't/data/pipeline_base_directory/Some/Common_Name/TRACKING/123/4/SLX/XYZ45678/mysra_file/mysra_file_1.fastq.gz.md5', 'md5 hash file exists for mysra_file_1');
ok (-e 't/data/pipeline_base_directory/Some/Common_Name/TRACKING/123/4/SLX/XYZ45678/mysra_file/mysra_file_2.fastq.gz.md5', 'md5 hash file exists for mysra_file_2');

is `gunzip -c t/data/pipeline_base_directory/Some/Common_Name/TRACKING/123/4/SLX/XYZ45678/mysra_file/mysra_file_1.fastq.gz | head -1`, "\@SRR3530795.1/1\n", 'SRA fastq-dump header replaced';


# check that the files all have md5 hashes in the database
ok my $vfile_myfile_1 = VRTrack::File->new_by_name( $vrtrack, 'myfile_1.fastq.gz'), 'retrieve the updated file object myfile_1';
is($vfile_myfile_1->md5, "7bfa821c601bebc2a96f7b8dda141457", 'MD5 for myfile_1');
ok my $vfile_myotherfile_L3_2 = VRTrack::File->new_by_name( $vrtrack, 'myotherfile_L3_2.fastq.gz'), 'retrieve the updated file object myotherfile_L3_2';
is($vfile_myotherfile_L3_2->md5, "81b5693c5751dec6606faec306271061", 'MD5 for myotherfile_L3_2');
ok my $vfile_myotherfile_L3_1 = VRTrack::File->new_by_name( $vrtrack, 'myotherfile_L3_1.fastq.gz'), 'retrieve the updated file object myotherfile_L3_1';
is($vfile_myotherfile_L3_1->md5, "c1fb9ece9e438899c419999a6db75e63", 'MD5 for myotherfile_L3_1');
ok my $vfile_mysra_file_1 = VRTrack::File->new_by_name( $vrtrack, 'mysra_file_1.fastq.gz'), 'retrieve the updated file object mysra_file_1';
is($vfile_mysra_file_1->md5, "f4cf80f24538f20c43fd37c8a0ee0e1f", 'MD5 for mysra_file_1');
ok my $vfile_mysra_file_2 = VRTrack::File->new_by_name( $vrtrack, 'mysra_file_2.fastq.gz'), 'retrieve the updated file object mysra_file_2';
is($vfile_mysra_file_2->md5, "6ffd8c811d10a01d6ea77cb0ac0f720f", 'MD5 for mysra_file_2');

ok my $vlane_updated = VRTrack::Lane->new_by_name( $vrtrack, 'myfile'), 'retrieve the updated lane object';
is $vlane_updated->is_processed('import'), 1, 'import for lane after import';
ok my $vlane_updated_2 = VRTrack::Lane->new_by_name( $vrtrack, 'myotherfile_L3'), 'retrieve the updated lane object';
is $vlane_updated_2->is_processed('import'), 1, 'import for lane after import';
ok my $vlane_updated_3 = VRTrack::Lane->new_by_name( $vrtrack, 'mysra_file'), 'retrieve the updated lane object';
is $vlane_updated_3->is_processed('import'), 1, 'import for lane after import';

# Check readcount
is $vlane_updated->raw_reads,     2, 'single ended lane reads correct';
is $vlane_updated->raw_bases,   210, 'single ended lane bases correct';
is $vlane_updated->read_len,    105, 'single ended lane readlen correct';
is $vlane_updated_2->raw_reads,   5, 'paired ended lane reads correct';
is $vlane_updated_2->raw_bases, 525, 'paired ended lane bases correct';
is $vlane_updated_2->read_len,  105, 'paired ended lane readlen correct';
is $vlane_updated_3->raw_reads,   4, 'paired ended lane reads correct';
is $vlane_updated_3->raw_bases, 400, 'paired ended lane bases correct';
is $vlane_updated_3->read_len,  100, 'paired ended lane readlen correct';

rmtree('t/data/pipeline_base_directory');
delete_test_data($vrtrack);

###################################
$vrtrack = initialse_test_setup();

ok(my $spreadsheet_data_access_group = UpdatePipeline::Spreadsheet->new(
  filename                => 't/data/external_data_example.xls',
  _vrtrack                => $vrtrack,
  study_names             => [],
  dont_use_warehouse      => 1,
  common_name_required    => 0,
  pipeline_base_directory => 't/data/pipeline_base_directory',
  files_base_directory    => 't/data/path/to/sequencing',
  data_access_group       => 'unix_group_1',
  environment             => 'test'
), 'initialise spreadsheet driver class data access group');
ok($spreadsheet_data_access_group->_files_metadata, 'generate the files metadata');
is($spreadsheet_data_access_group->_files_metadata->[0]->data_access_group, 'unix_group_1', 'data access group returned');
ok $spreadsheet_data_access_group->update();
ok(my $vproject_access_group = VRTrack::Project->new_by_name( $vrtrack, 'My Study Name'), 'retrieve the project object');
is($vproject_access_group->data_access_group(), 'unix_group_1', 'check data access group on project');

done_testing();
rmtree('t/data/pipeline_base_directory');
delete_test_data($vrtrack);

sub initialse_test_setup
{
	my $vrtrack = VRTrack::VRTrack->new({database => "vrtrack_test",host => "localhost",port => 3306,user => "root",password => undef});
	delete_test_data($vrtrack);
	$vrtrack->{_dbh}->do("INSERT INTO `project` (`project_id`,`ssid`,`name`, `hierarchy_name`,`study_id`,`changed`,`latest`) VALUES	(1,123,'My Study Name','My_Study_Name',1,NOW(),1)");
	$vrtrack->{_dbh}->do("INSERT INTO `sample`  (`sample_id`, `ssid`,`name`, `hierarchy_name`,`changed`,`latest`) VALUES	(1,456,'2','2',NOW(),1)");
	$vrtrack->{_dbh}->do("INSERT INTO `library` (`library_id`,`ssid`,`name`, `hierarchy_name`,`changed`,`latest`) VALUES	(1,789,'ABC45678','ABC45678',NOW(),1)");
	return $vrtrack;
}

sub delete_test_data
{
  my $vrtrack = shift;
  $vrtrack->{_dbh}->do('delete from project where name="My Study Name"');
  $vrtrack->{_dbh}->do('delete from sample');
  $vrtrack->{_dbh}->do('delete from library');
  $vrtrack->{_dbh}->do('delete from lane');
  $vrtrack->{_dbh}->do('delete from file');
  $vrtrack->{_dbh}->do('delete from study');
  $vrtrack->{_dbh}->do('delete from individual');
}
