package UpdatePipeline::PB::StudyFilesMetaData;

# ABSTRACT: Take in the name of a study and produce a metadata object for each experiment file

=head1 SYNOPSIS

Take in the name of a study and produce a metadata object for each experiment file. Lookup the warehouse, look for files in irods, look for metadata on each file.
   use UpdatePipeline::PB::StudyFilesMetaData;

   my $obj = UpdatePipeline::PB::StudyFilesMetaData->new(
       study_name        => 'ABC',
       dbh               => $dbh
     );
   $obj->files_metadata();

=cut

use Moose;
use Warehouse::LibraryAliquots;
use IRODS::Sample;
use IRODS::File;
use IRODS::PBStudy;
use UpdatePipeline::PB::FileMetaData;

has 'study_name'         => ( is => 'ro', isa      => 'Str', required => 1 );
has 'dbh'                => ( is => 'ro', required => 1 );
has 'files_metadata'     => ( is => 'ro', isa      => 'ArrayRef', lazy => 1, builder => '_build_files_metadata' );


sub _build_files_metadata {
    my ( $self ) = @_;
    
    my @merged_files_metadata;
    my $file_locations = IRODS::PBStudy->new( name => $self->study_name )->file_locations();
    for my $file_location ( @{$file_locations} ) {
        my $irods_file_metadata = IRODS::File->new( file_location => $file_location )->file_attributes;

        next if(defined($irods_file_metadata->{type}) && $irods_file_metadata->{type} eq "bam");
        
        my $lane_name = $irods_file_metadata->{sample_name};
        if(defined($irods_file_metadata->{run}) && defined($irods_file_metadata->{well}))
        {
           $lane_name = $irods_file_metadata->{run} . '_' . $irods_file_metadata->{well};
        }
        
        # Denormalise
        my $merged_file_metadata = UpdatePipeline::PB::FileMetaData->new(
            study_name              => $irods_file_metadata->{study_name}             ,
            study_accession_number  => $irods_file_metadata->{study_accession_number} ,
            library_name            => $irods_file_metadata->{library_name}           ,
            library_ssid            => $irods_file_metadata->{library_id}             ,
            sample_name             => $irods_file_metadata->{sample_name}            ,
            sample_accession_number => $irods_file_metadata->{sample_accession_number},
            sample_common_name      => $irods_file_metadata->{sample_common_name}     ,
            supplier_name           => $irods_file_metadata->{sample}                 ,
            study_ssid              => $irods_file_metadata->{study_id}               ,
            sample_ssid             => $irods_file_metadata->{sample_id}              ,
            lane_name               => $lane_name,
            md5                     => $irods_file_metadata->{md5},
            file_location           => $file_location
        );
        push(@merged_files_metadata, $merged_file_metadata);
    }
    return \@merged_files_metadata;
}

__PACKAGE__->meta->make_immutable;
no Moose;
1;
