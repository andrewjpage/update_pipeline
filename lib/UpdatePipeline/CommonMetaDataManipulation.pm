package UpdatePipeline::CommonMetaDataManipulation;

# ABSTRACT: Common meta data manipulation

use Moose;

has '_files_metadata'           => ( is => 'rw', isa => 'ArrayRef', lazy_build => 1 );
has 'number_of_files_to_return' => ( is => 'rw', isa => 'Maybe[Int]');
has 'study_names'               => ( is => 'rw', isa => 'ArrayRef', required   => 1 );
has 'no_pending_lanes'      => ( is => 'ro', default    => 0,            isa => 'Bool');
has 'specific_min_run'      => ( is => 'ro', default    => 0,            isa => 'Int');
has 'file_type'             => ( is => 'ro', default    => 'bam',        isa => 'Str');
has 'verbose_output'        => ( is => 'rw', default    => 0,            isa => 'Bool');

sub _build__files_metadata
{
  my ($self) = @_;
  my $irods_files_metadata = UpdatePipeline::IRODS->new(
    study_names               => $self->study_names,
    number_of_files_to_return => $self->number_of_files_to_return,
    no_pending_lanes          => $self->no_pending_lanes,
    ml_warehouse_dbh          => $self->ml_warehouse_dbh,
    specific_min_run          => $self->specific_min_run,
    file_type                 => $self->file_type,
    verbose_output            => $self->verbose_output
    )->files_metadata();
  return $irods_files_metadata;
}

sub get_lane_metadata
{
  my ($self, $file_name_without_extension) = @_;
  return  UpdatePipeline::VRTrack::LaneMetaData->new(
      name => $file_name_without_extension, 
      _vrtrack => $self->_vrtrack
    )->lane_attributes();
}

__PACKAGE__->meta->make_immutable;

no Moose;

1;
