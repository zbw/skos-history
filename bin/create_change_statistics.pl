#!/usr/bin/perl
# nbt, 6.11.2014

# Creates a csv table of change statistics
# for a set of skos file versions via sparql queries

# query parsing is based on whitespace recognition, minimal:
#   values ( ... ) { ( ... ) }

use strict;
use warnings;
use lib qw(lib);

use Data::Dumper;
use File::Slurp;
use RDF::Query::Client;
use String::Util qw/unquote/;
use URI::file;

our $endpoint = 'http://zbw.eu/beta/sparql/stwv/query';

# List of version and data structure for results

my @row_headers = qw / 8.06 8.08 8.10 8.12 8.14a /;
my %data = map { $_ => {} } @row_headers;

# List of queries and parameters for each statistics column

my @column_definitions = (
  {
    column     => 'added_labels_en',
    header     => 'Added labels (en)',
    query_file => '../sparql/count_added_labels.rq',
    replace    => {
      '?language' => '"en"',
    },
    result_variable => 'addedLabelCount',
  },
  {
    column     => 'added_labels_de',
    header     => 'Added labels (de)',
    query_file => '../sparql/count_added_labels.rq',
    replace    => {
      '?language' => '"de"',
    },
    result_variable => 'addedLabelCount',
  },
);

# Initialize csv table

# for each query, get column data and add to csv table

foreach my $columndef_ref (@column_definitions) {
  get_column( $columndef_ref, \%data );
}

# add to csv table

# output resulting table

print Dumper \%data;

#######################

sub get_column {
  my $columndef_ref = shift or die "param missing\n";
  my $data_ref      = shift or die "param missing\n";

  # read query from file (by command line argument)
  my $query = read_file( $$columndef_ref{query_file} ) or die "Can't read $!\n";

  # do replacements, if defined
  if ( $$columndef_ref{replace} ) {

    # parse VALUES clause
    my ( $variables_ref, $value_ref ) = parse_values($query);

    # replace values
    foreach my $variable ( keys %$value_ref ) {
      if ( defined( $$columndef_ref{replace}{$variable} ) ) {
        $$value_ref{$variable} = $$columndef_ref{replace}{$variable};
      }
    }
    $query = insert_modified_values( $query, $variables_ref, $value_ref );
  }

  # execute query
  my $q        = RDF::Query::Client->new($query);
  my $iterator = $q->execute($endpoint);

  # parse and add results
  while ( my $row = $iterator->next ) {
    my $version = unquote( $row->{version}->as_string );
    if ( defined $$data_ref{$version} ) {
      $$data_ref{$version}{ $$columndef_ref{column} } =
        unquote($row->{ $$columndef_ref{result_variable} }->as_string);
    }
  }
}

sub parse_values {
  my $query = shift or die "param missing\n";

  $query =~ m/ values \s+\(\s+ (.*?) \s+\)\s+\{ \s+\(\s+ (.*?) \s+\)\s+\} /ixms;

  my @variables  = split( /\s+/, $1 );
  my @values_tmp = split( /\s+/, $2 );
  my %value;
  for ( my $i = 0 ; $i < scalar(@variables) ; $i++ ) {
    $value{ $variables[$i] } = $values_tmp[$i];
  }
  return \@variables, \%value;
}

sub insert_modified_values {
  my $query         = shift or die "param missing\n";
  my $variables_ref = shift or die "param missing\n";
  my $value_ref     = shift or die "param missing\n";

  # create new values clause
  my @values;
  foreach my $variable (@$variables_ref) {
    push( @values, $$value_ref{$variable} );
  }
  my $values_clause =
      ' values ( '
    . join( ' ', @$variables_ref )
    . " ) {\n    ( "
    . join( ' ', @values )
    . " )\n  }";

  # insert into query
  $query =~ s/\svalues .*? \s+\)\s+\}/$values_clause/ixms;

  return $query;
}
