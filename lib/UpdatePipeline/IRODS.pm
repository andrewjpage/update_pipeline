package UpdatePipeline::IRODS;

# ABSTRACT: Take in a set of Studies, lookup all files in IRODS,  Create FileMetaData for each, populate the metadata from IRODS and the Warehouse.

=head1 SYNOPSIS

use UpdatePipeline::IRODS;
my $update_pipeline_irods = UpdatePipeline::IRODS->new(
  study_names => ['StudyA', 'StudyB'],
  environment => 'test',
  );

my @files_metadata = $update_pipeline_irods->files_metadata();

=cut

use Moose;
use IRODS::Study;
use IRODS::File;
use Warehouse::Database;
use UpdatePipeline::FileMetaData;
use Warehouse::FileMetaDataPopulation;
use GCLPWarehouse::FileMetaDataPopulation;

has 'study_names'    => ( is => 'rw', isa => 'ArrayRef[Str]', required   => 1 );
has 'files_metadata' => ( is => 'rw', isa => 'ArrayRef',      lazy_build => 1 );
has 'number_of_files_to_return' => ( is => 'rw', isa => 'Maybe[Int]' );

has '_irods_studies'   => ( is => 'rw', isa => 'ArrayRef', lazy_build => 1 );
has '_warehouse_dbh'   => ( is => 'rw', required => 1 );
has '_gclp_warehouse_dbh' => ( is => 'rw', required => 1 );
has 'no_pending_lanes' => ( is => 'ro', default  => 0, isa => 'Bool' );
has 'specific_min_run' => ( is => 'ro', default  => 0, isa => 'Int' );
has 'file_type'        => ( is => 'ro', default  => 'bam', isa => 'Str' );
has 'verbose_output'   => ( is => 'rw', default  => 0,     isa => 'Bool');

sub _build__irods_studies {
    my ($self) = @_;
    my @irods_studies;

    for my $study_name ( @{ $self->study_names } ) {
        push(
            @irods_studies,
            IRODS::Study->new(
                name             => $study_name,
                specific_min_run => $self->specific_min_run,
                no_pending_lanes => $self->no_pending_lanes,
                file_type        => $self->file_type
            )
        );
    }

    return \@irods_studies;
}

sub _build_files_metadata {
    my ($self) = @_;
    my @files_metadata;

    my @irods_files_metadata = @{ $self->_get_irods_file_metadata_for_studies() };

    for my $irods_file_metadata (@irods_files_metadata) {
        my $file_metadata;
        next if ( $irods_file_metadata->{id_run} < $self->specific_min_run );
	
        if(defined($irods_file_metadata->{library_id}) && ! defined($irods_file_metadata->{library_name}) )
        {
           $irods_file_metadata->{library_name} = $irods_file_metadata->{library_id}; 
        }
	
        if(defined($irods_file_metadata->{sample}) && ! defined($irods_file_metadata->{sample_public_name}) )
        {
           $irods_file_metadata->{sample_public_name} = $irods_file_metadata->{sample}; 
        }
	
        eval {
            $file_metadata = UpdatePipeline::FileMetaData->new(
                study_name                  => $irods_file_metadata->{study},
                study_accession_number      => $irods_file_metadata->{study_accession_number},
                file_md5                    => $irods_file_metadata->{md5},
                file_type                   => $irods_file_metadata->{type},
                file_name                   => $irods_file_metadata->{file_name},
                file_name_without_extension => $irods_file_metadata->{file_name_without_extension},
                id_run                      => $irods_file_metadata->{id_run},
                library_name                => $irods_file_metadata->{library},
                library_ssid                => $irods_file_metadata->{library_id},
                total_reads                 => $irods_file_metadata->{total_reads},
                sample_name                 => $irods_file_metadata->{sample},
                sample_accession_number     => $irods_file_metadata->{sample_accession_number},
                lane_is_paired_read         => $irods_file_metadata->{is_paired_read},
                lane_manual_qc              => $irods_file_metadata->{manual_qc},
                sample_common_name          => $irods_file_metadata->{sample_common_name},
                sample_ssid                 => $irods_file_metadata->{sample_id},
                study_ssid                  => $irods_file_metadata->{study_id},
                ebi_run_acc                 => $irods_file_metadata->{ebi_run_acc},
                reference                   => $irods_file_metadata->{reference},
            );
        };
        if ($@) {
            # An error occured while trying to get data from IRODs, usually a transient error which will probably be fixed next time its run
            next;
        }

        # fill in the blanks with data from the warehouse
        Warehouse::FileMetaDataPopulation->new( file_meta_data => $file_metadata, _dbh => $self->_warehouse_dbh )->populate();
		
        # fill in the blanks with data from the GCLP warehouse
        GCLPWarehouse::FileMetaDataPopulation->new( file_meta_data => $file_metadata, _dbh => $self->_gclp_warehouse_dbh )->populate();

        push( @files_metadata, $file_metadata );
    }

    my @sorted_files_metadata = reverse( ( sort ( sort_by_file_name @files_metadata ) ) );

    return \@sorted_files_metadata;
}

sub _get_irods_file_metadata_for_studies {
    my ($self) = @_;
    my @files_metadata;
    my @unsorted_file_locations;
    my @sorted_file_locations;

    for my $irods_study ( @{ $self->_irods_studies } ) {
        for my $file_metadata ( @{ $irods_study->file_locations() } ) {
            push( @unsorted_file_locations, $file_metadata );
        }
    }

    # Allows you to only check the latest X runs.
    @sorted_file_locations = ( sort ( sort_by_id_run @unsorted_file_locations ) );
    $self->_limit_returned_results( \@sorted_file_locations );
    for my $file_location ( @sorted_file_locations ) {
        print "Syncing file: $file_location\n" if($self->verbose_output);
        push( @files_metadata, IRODS::File->new( file_location => $file_location )->file_attributes );
    }

    return \@files_metadata;
}

sub print_file_metadata {
    my ($self) = @_;

    for my $file_metadata ( @{ $self->files_metadata } ) {
        print( ( $file_metadata->study_name              ? $file_metadata->study_name              : '' ) . ', ' );
        print( ( $file_metadata->study_accession_number  ? $file_metadata->study_accession_number  : '' ) . ', ' );
        print( ( $file_metadata->file_md5                ? $file_metadata->file_md5                : '' ) . ', ' );
        print( ( $file_metadata->file_type               ? $file_metadata->file_type               : '' ) . ', ' );
        print( ( $file_metadata->file_name               ? $file_metadata->file_name               : '' ) . ', ' );
        print( ( $file_metadata->id_run                  ? $file_metadata->id_run                  : '' ) . ', ' );
        print( ( $file_metadata->library_name            ? $file_metadata->library_name            : '' ) . ', ' );
        print( ( $file_metadata->library_ssid            ? $file_metadata->library_ssid            : '' ) . ', ' );
        print( ( $file_metadata->total_reads             ? $file_metadata->total_reads             : '' ) . ', ' );
        print( ( $file_metadata->sample_name             ? $file_metadata->sample_name             : '' ) . ', ' );
        print( ( $file_metadata->sample_accession_number ? $file_metadata->sample_accession_number : '' ) . "\n" );
    }
}

sub _filter_file_locations_by_min_run_id {
    my ( $self, $files_metadata ) = @_;

    my $filtered_files_metadata;
    if ( defined( $self->specific_min_run ) && @{$files_metadata} > 0 && $files_metadata->[0] =~ /\/seq\/[\d]+\// ) {
        for my $file_metadata ( @{$files_metadata} ) {
            my @file_path = split( '/', $file_metadata );
            if ( $file_path[2] >= $self->specific_min_run ) {
                push( @{$filtered_files_metadata}, $file_metadata );
            }
        }
        $files_metadata = $filtered_files_metadata;
    }
    return $files_metadata;
}

sub _limit_returned_results {
    my ( $self, $files_metadata ) = @_;

    if ( defined( $self->number_of_files_to_return ) && $self->number_of_files_to_return > 0 && $self->number_of_files_to_return + 1 < @{$files_metadata} ) {
        splice @{$files_metadata}, $self->number_of_files_to_return;
    }
    1;
}

# Input /seq/2657/2657_1.bam
sub sort_by_id_run {
    my @a = split( /\//, $a );
    my @b = split( /\//, $b );

    $b[2] <=> $a[2] || $b[3] cmp $a[3];
}

sub sort_by_file_name {
    my @a = split( /\_|\#/, $a->file_name_without_extension() );
    my @b = split( /\_|\#/, $b->file_name_without_extension() );

    $a[0] <=> $b[0] || $a[1] <=> $b[1] || $a[2] <=> $b[2];
}

__PACKAGE__->meta->make_immutable;

no Moose;

1;
