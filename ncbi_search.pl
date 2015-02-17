#!/usr/bin/perl
#FILE: ncbi_search.pl
#AUTH: Paul Stothard (paul.stothard@gmail.com)
#Downloaded from http://www.bioinformatics-made-simple.com/

#use warnings;
#use strict;
use Getopt::Long;
use LWP::Simple;
use URI::Escape;

use LWP::UserAgent;
use HTTP::Request::Common;

my %param = (
    query      => undef,
    outputFile => undef,
    database   => undef,
    returnType => undef,
    maxRecords => undef,
    format     => undef,
    verbose    => undef,
    url        => 'http://www.ncbi.nlm.nih.gov/entrez/eutils',
    retries    => 0,
    maxRetries => 5,
    help       => undef
);

Getopt::Long::Configure('bundling');
GetOptions(
    'q|query=s'       => \$param{query},
    'o|output_file=s' => \$param{outputFile},
    'd|database=s'    => \$param{database},
    'r|return_type=s' => \$param{returnType},
    'm|max_records=i' => \$param{maxRecords},
    'verbose|v'       => \$param{verbose},
    'h|help'          => \$param{help}
);

if ( defined( $param{help} ) ) {
    print_usage();
    exit(0);
}

if (   !( defined( $param{query} ) )
    or !( defined( $param{outputFile} ) )
    or !( defined( $param{database} ) )
    or !( defined( $param{returnType} ) ) )
{
    print_usage();
    exit(1);
}

$param{returnType} = lc( $param{returnType} );

$param{query} = uri_escape( $param{query} );

_doSearch(%param);

sub _doSearch {
    my %param = @_;

    my $esearch = "$param{url}/esearch.fcgi?db=$param{database}"
        . "&retmax=1&usehistory=y&term=$param{query}";
    my $esearch_result = get($esearch);

    while (
        ( !defined($esearch_result) )
        || (!(  $esearch_result
                =~ m/<Count>(\d+)<\/Count>.*<QueryKey>(\d+)<\/QueryKey>.*<WebEnv>(\S+)<\/WebEnv>/s
            )
        )
        )
    {
        if ($esearch_result =~ m/<ERROR>(.*)<\/ERROR>/is) {
            die("ESearch returned an error: $1");
        }
        message( $param{verbose},
            "ESearch results could not be parsed. Resubmitting query.\n" );
        sleep(10);
        if ( $param{retries} >= $param{maxRetries} ) {
            die("Too many failures--giving up search.");
        }

        $esearch_result = get($esearch);
        $param{retries}++;
    }

    $param{retries} = 0;

    $esearch_result
        =~ m/<Count>(\d+)<\/Count>.*<QueryKey>(\d+)<\/QueryKey>.*<WebEnv>(\S+)<\/WebEnv>/s;

    my $count     = $1;
    my $query_key = $2;
    my $web_env   = $3;

    if ( defined( $param{maxRecords} ) ) {
        if ( $count > $param{maxRecords} ) {
            message( $param{verbose},
                "Retrieving $param{maxRecords} records out of $count available records.\n"
            );
            $count = $param{maxRecords};
        }
        else {
            message( $param{verbose},
                "Retrieving $count records out of $count available records.\n"
            );
        }
    }
    else {
        message( $param{verbose},
            "Retrieving $count records out of $count available records.\n" );
    }

    my $retmax = 500;
    if ( $retmax > $count ) {
        $retmax = $count;
    }

    open( my $OUTFILE, ">" . $param{outputFile} )
        or die("Error: Cannot open $param{outputFile} : $!");

    for (
        my $retstart = 0;
        $retstart < $count;
        $retstart = $retstart + $retmax
        )
    {
        message( $param{verbose},
                  "Downloading records "
                . ( $retstart + 1 ) . " to "
                . ( $retstart + $retmax )
                . "\n" );
        my $efetch
            = "$param{url}/efetch.fcgi?rettype=$param{returnType}&retmode=text&retstart=$retstart&retmax=$retmax&db=$param{database}&query_key=$query_key&WebEnv=$web_env";
        my $efetch_result = get($efetch);

        while ( !defined($efetch_result) ) {
            message( $param{verbose},
                "EFetch results could not be parsed. Resubmitting query.\n" );
            sleep(10);
            if ( $param{retries} >= $param{maxRetries} ) {
                die("Too many failures--giving up search.");
            }

            $efetch_result = get($efetch);
            $param{retries}++;
        }

        print( $OUTFILE $efetch_result );

        unless (
            ( defined( $param{maxRecords} ) && ( $param{maxRecords} == 1 ) ) )
        {
            sleep(3);
        }
    }

    close($OUTFILE) or die("Error: Cannot close $param{outputFile} file: $!");
}

sub message {
    my $verbose = shift;
    my $message = shift;
    if ($verbose) {
        print $message;
    }
}

sub print_usage {
    print <<BLOCK;
USAGE:
   perl ncbi_search.pl -q STRING -o FILE -d STRING -r STRING [Options]

DESCRIPTION:
   Uses NCBI's eSearch to download collections of sequences.

REQUIRED ARGUMENTS:
   -q, --query [STRING]
      Raw query text.
   -o, --output [FILE]
      Output file to create.
   -d, --database [STRING]
      Name of the NCBI database to search, such as 'nucleotide', 'protein',
      or 'gene'.
   -r, --return_type [STRING]
      The type of information requested. For sequences 'fasta' is often used.
      The accepted formats vary depending on the database being queried.
   -m, --max_records [INTEGER]
      The maximum number of records to return (default is to return all matches
      satisfying the query).
   -v, --verbose
      Provide progress messages.
   -h, --help
      Show this message.

EXAMPLE:
perl ncbi_search.pl -q '(((("Phenyl-trna" synthetase OR "phenilalanine-trna ligase" OR "pheRS")  NOT "mitochondrial") NOT "mitochondrial-like") AND "eukaryotes"[porgn]) AND "refseq"[Filter]' -o Fasta.txt -d protein -r fasta -m 800

perl ncbi_search.pl -q '((((mitochondrial "Phenyl-trna" synthetase OR mitochondrial-like "phenilalanine-trna ligase") OR mitochondrial "pheRS" NOT Cytoplasmic NOT Nuclear AND "eukaryotes"[porgn]) AND "refseq"[Filter]' -o Fasta.txt -d protein -r fasta -m 800

#None Refseq

perl ncbi_search.pl -q '(((("Phenyl-trna" synthetase OR "phenilalanine-trna ligase" OR "pheRS")  NOT "mitochondrial") NOT "mitochondrial-like") AND "eukaryotes"[porgn])' -o Fasta.txt -d protein -r fasta -m 800

perl ncbi_search.pl -q '((((mitochondrial "Phenyl-trna" synthetase OR mitochondrial-like "phenilalanine-trna ligase") OR mitochondrial "pheRS" NOT Cytoplasmic NOT Nuclear AND "eukaryotes"[porgn])' -o Fasta.txt -d protein -r fasta -m 800


BLOCK
}

