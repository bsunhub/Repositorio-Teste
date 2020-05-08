
package Nextis::CQQueryBuilder;

# This package is used to build queries for ClearQuest

use strict;
use Carp;

use Data::Dumper;

our $AUTOLOAD;

BEGIN {
    use Exporter();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
    
    $VERSION     = 1.00;
    
    @ISA         = qw(Exporter);
    @EXPORT      = qw();
    %EXPORT_TAGS = ();
    @EXPORT_OK   = qw();
}

# Create a new [<cc>]Nextis::CQQueryBuilder[</cc>].
sub new
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = {};

    my $session = shift;
    my $proxy = shift || undef;

    $self->{'session'} = undef;
    $self->{'proxy'} = undef;
    bless($self, $class);

    $self->{'session'} = $session;
    $self->{'proxy'} = $proxy;

    return $self;
}

sub _get_cmp_op
{
    my $self = shift;
    my $cmp_op = shift;

    $cmp_op = "\L$cmp_op";
    ($cmp_op eq '='           ) && do { return 1; };
    ($cmp_op eq '<>'          ) && do { return 2; };
    ($cmp_op eq '<'           ) && do { return 3; };
    ($cmp_op eq '<='          ) && do { return 4; };
    ($cmp_op eq '>'           ) && do { return 5; };
    ($cmp_op eq '>='          ) && do { return 6; };
    ($cmp_op eq 'like'        ) && do { return 7; };
    ($cmp_op eq 'not_like'    ) && do { return 8; };
    ($cmp_op eq 'between'     ) && do { return 9; };
    ($cmp_op eq 'not_between' ) && do { return 10; };
    ($cmp_op eq 'is_null'     ) && do { return 11; };
    ($cmp_op eq 'is_not_null' ) && do { return 12; };
    ($cmp_op eq 'in'          ) && do { return 13; };
    ($cmp_op eq 'not_in'      ) && do { return 14; };
    return 1;
}

sub parse_filter_value
{
    my $self = shift;
    my $value = shift;
    my $vars = shift;

    #my $orig_value = $value;

    return [ '' ] if (! defined($value));

    $value =~ s/^\s+//;
    $value =~ s/\s+$//;

    return [ '' ] if ($value eq '');

    if ($value !~ /^\"(.*)\"$/) {
        #print STDERR "UNSUPPORTED FIELD REFERENCE IN QUERY FILTER\n";
        return [ $value ];   # field
    }

    my @ret = ();
    while ($value =~ s/^,?\s*\"(.*?)\"\s*//) {
        my $v = $1;
        my ($p1, $p2);

        # unqualified variable reference
        if ($v =~ /^\$\{([^\.]+)\}$/) {
            $p1 = $vars->{'*default*'};
            $p2 = $1;
        }

        # qualified variable reference
        if ($v =~ /^\$\{([^\.]+)\.([^\.]+)\}$/) {
            $p1 = $1;
            $p2 = $2;
        }

        # variable
        if (defined($p1) && defined($p2)) {
            if (! exists($vars->{"\L$p1"})
                || ! exists($vars->{"\L$p1"}->{"\L$p2"})) {
                push @ret, '';
            }
            my $v = $vars->{"\L$p1"}->{"\L$p2"};
            if (ref($v) eq 'ARRAY') {
                push @ret, @{$v};  # will this be used???
            } else {
                push @ret, $v;
            }
        } else {
            push @ret, $v;
        }
    }

    if ($value =~ /[^\s]/) {
        while ($value =~ s/\s\s/ /g) {}
        print STDERR "WARNING: garbage after variable value: '$value'\n";
    }

    #print STDERR "$orig_value => " . Dumper([ @ret ]) . "\n";

    return [ @ret ];
}

sub _make_query_filter_tree
{
    my $self = shift;
    my $q = shift;
    my $root = shift;
    my $filters = shift;
    my $vars = shift;

    if (! defined($filters)
        || ref($filters) ne 'ARRAY'
        || scalar(@{$filters}) < 1
        || ! defined($filters->[0])) {
        print STDERR "WARNING: bad filter: $filters\n";
        print STDERR Dumper($filters) if (ref($filters) ne '');
        return undef;
    }

    for ($filters->[0]) {
        # AND operator
        /^and$/i && do {
            my $op = $root->BuildFilterOperator($CQPerlExt::CQ_BOOL_OP_AND);
            for (my $i = 1; $i < scalar(@{$filters}); $i++) {
                next unless (ref($filters->[$i]) eq 'ARRAY');
                $self->_make_query_filter_tree($q, $op, $filters->[$i], $vars);
            }
            return $op;
        };

        # OR operator
        /^or$/i && do {
            my $op = $root->BuildFilterOperator($CQPerlExt::CQ_BOOL_OP_OR);
            for (my $i = 1; $i < scalar(@{$filters}); $i++) {
                next unless (ref($filters->[$i]) eq 'ARRAY');
                $self->_make_query_filter_tree($q, $op, $filters->[$i], $vars);
            }
            return $op;
        };

        # some filter
        if ($root == $q) {
            # in the query: must create the top-level filter
            $root = $q->BuildFilterOperator($CQPerlExt::CQ_BOOL_OP_AND);
        }
        $root->BuildFilter($filters->[1],
                           $self->_get_cmp_op($filters->[0]),
                           $self->parse_filter_value($filters->[2], $vars));
    }
}

# Get a line from the query result set.  You should not mix calls to
# this and to [<cc>]fetch_line()[</cc>].
sub fetch_array
{
    my $self = shift;
    my $q = shift;

    # build result set and execute it
    if (! defined($q->{'rs'})) {
        $q->{'rs'} = $self->{'session'}->BuildResultSet($q->{'query'});
        return undef unless $q->{'rs'};
        $q->{'rs'}->Execute();
    }

    # get more lines
    if (scalar(@{$q->{'buffer'}}) == 0) {
        $q->{'buffer'} = $self->{'proxy'}->fast_call('fetch_rs_lines_with_names',
                                                     $q->{'rs'},
                                                     100);
    }

    # return a line
    return shift @{$q->{'buffer'}};
}

# Get a line from the query result set.  You should not mix calls to
# this and to [<cc>]fetch_array()[</cc>].
sub fetch_line
{
    my $self = shift;
    my $q = shift;

    # build result set and execute it
    if (! defined($q->{'rs'})) {
        $q->{'rs'} = $self->{'session'}->BuildResultSet($q->{'query'});
        return undef unless $q->{'rs'};
        $q->{'rs'}->Execute();
    }

    # get more lines
    if (scalar(@{$q->{'buffer'}}) == 0) {
        $q->{'buffer'} = $self->{'proxy'}->fast_call('fetch_rs_lines',
                                                     $q->{'rs'},
                                                     100);
    }

    # return a line
    return shift @{$q->{'buffer'}};
}

sub _get_order_id
{
    my $self = shift;
    my $name = shift;

    return $CQPerlExt::CQ_SORT_ASC if (! defined($name));

    for ($name) {
        /^asc/i && do { return $CQPerlExt::CQ_SORT_ASC; };
        /^desc/i && do { return $CQPerlExt::CQ_SORT_DESC; };
    }
    print STDERR "CQQueryBuilder::_get_order_id(): bad order specification: '$name'\n";
    return $CQPerlExt::CQ_SORT_ASC;
}

# Build a new query.
sub query
{
    my $self = shift;
    my $entity_def_name = shift;
    my $fields = shift;
    my $filters = shift;
    my $vars = shift;

    my $proxy = $self->{'proxy'};
    my $session = $self->{'session'};

    my $q = $session->BuildQuery($entity_def_name);

    # build fields
    my $cur_order_num = 1;
    my @fields = ();
    for my $field (@{$fields}) {
        if (ref($field) eq 'ARRAY') {
            push @fields, $field->[0];
            $q->BuildField($field->[0]);
            my $qfd = $q->GetQueryFieldDefs()->ItemByName($field->[0]);
            $qfd->SetSortType($self->_get_order_id($field->[1]));
            $qfd->SetSortOrder($field->[2] || $cur_order_num++);
        } else {
            push @fields, $field;
            $q->BuildField($field);
        }
    }

    # build filters
    $self->_make_query_filter_tree($q, $q, $filters, $vars) if ($filters);

    return {
        'fields' => \@fields,
        'query' => $q,
        'rs' => undef,
        'buffer' => [],
    };
}

1;
