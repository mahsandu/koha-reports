#!/usr/bin/perl

use strict;
use warnings;
use 5.010;

use Koha::Script -cron;
use C4::Context;
use C4::Overdues qw(Getoverdues CalcFine UpdateFine);
use Getopt::Long qw(GetOptions);
use Carp qw(carp croak);
use File::Spec;
use Try::Tiny qw(catch try);

use Koha::Calendar;
use Koha::DateUtils qw(dt_from_string output_pref);
use Koha::Patrons;
use C4::Log qw(cronlogaction);

my $help;
my $verbose;
my $output_dir;
my $log;
my $maxdays;

my $command_line_options = join(" ", @ARGV);

GetOptions(
    'h|help'      => \$help,
    'v|verbose'   => \$verbose,
    'l|log'       => \$log,
    'o|out:s'     => \$output_dir,
    'm|maxdays:i' => \$maxdays,
);
my $usage = << 'ENDUSAGE';

This script calculates and charges overdue fines
to patron accounts. The Koha system preference 'finesMode' controls
whether the fines are calculated and charged to the patron accounts ("Calculate and charge");
or not calculated ("Don't calculate").

This script has the following parameters :
    -h --help: this message
    -l --log: log the output to a file (optional if the -o parameter is given)
    -o --out:  ouput directory for logs (defaults to env or /tmp if !exist)
    -v --verbose
    -m --maxdays: how many days back of overdues to process

ENDUSAGE

if ($help) {
    print $usage;
    exit;
}

my $script_handler = Koha::Script->new({ script => $0 });

try {
    $script_handler->lock_exec;
}
catch {
    my $message = "Skipping execution of $0 ($_)";
    print STDERR "$message\n"
        if $verbose;
    cronlogaction({ info => $message });
    exit;
};

cronlogaction({ info => $command_line_options });

my @borrower_fields =
    qw(cardnumber categorycode surname firstname email phone address citystate);
my @item_fields = qw(itemnumber barcode date_due);
my @other_fields = qw(days_overdue fine);
my $libname      = C4::Context->preference('LibraryName');
my $control      = C4::Context->preference('CircControl');
my $branch_type  = C4::Context->preference('HomeOrHoldingBranch') || 'homebranch';
my $mode         = C4::Context->preference('finesMode');
my $delim = "\t";    # ?  C4::Context->preference('CSVDelimiter') || "\t";

my %is_holiday;
my $today = dt_from_string();
my $filename;
if ($log or $output_dir) {
    $filename = get_filename($output_dir);
}

my $fh;
if ($filename) {
    open $fh, '>>', $filename or croak "Cannot write file $filename: $!";
    print {$fh} join $delim, ( @borrower_fields, @item_fields, @other_fields );
    print {$fh} "\n";
}
my $counted = 0;
my $updated = 0;
my $params;
$params->{maximumdays} = $maxdays if $maxdays;
my $overdues = Getoverdues($params);

for my $overdue (@{$overdues}) {
    next if $overdue->{itemlost};

    if (!defined $overdue->{borrowernumber}) {
        carp "ERROR in Getoverdues : issues.borrowernumber IS NULL.  Repair 'issues' table now!  Skipping record.\n";
        next;
    }
    my $patron = Koha::Patrons->find($overdue->{borrowernumber});
    my $branchcode =
        ($control eq 'ItemHomeLibrary') ? $overdue->{$branch_type}
      : ($control eq 'PatronLibrary')   ? $patron->branchcode
      :                                    $overdue->{branchcode};

    # In the final case, CircControl must be PickupLibrary. (branchcode comes from issues table here).
    if (!exists $is_holiday{$branchcode}) {
        $is_holiday{$branchcode} = set_holiday($branchcode, $today);
    }

    my $datedue = dt_from_string($overdue->{date_due});
    if (DateTime->compare($datedue, $today) == 1) {
        next;    # not overdue
    }
    ++$counted;

    my $days_overdue = $today->delta_days($datedue)->in_units('days');
    my $fine = calculate_fine($days_overdue);

    # Don't update the fine if today is a holiday.
    # This ensures that dropbox mode will remove the correct amount of fine.
    if (
        $mode eq 'production'
        && (!$is_holiday{$branchcode} || C4::Context->preference('ChargeFinesOnClosedDays'))
        && ($fine && $fine > 0)
    ) {
        UpdateFine(
            {
                issue_id       => $overdue->{issue_id},
                itemnumber     => $overdue->{itemnumber},
                borrowernumber => $overdue->{borrowernumber},
                amount         => $fine,
                due            => $datedue,
            }
        );
        $updated++;
    }
    my $borrower = $patron->unblessed;
    if ($filename) {
        my @cells;
        push @cells, map { defined $borrower->{$_} ? $borrower->{$_} : q{} } @borrower_fields;
        push @cells, map { $overdue->{$_} } @item_fields;
        push @cells, $days_overdue, $fine;
        say {$fh} join $delim, @cells;
    }
}
if ($filename) {
    close $fh;
}

if ($verbose) {
    my $overdue_items = @{$overdues};
    print <<"EOM";
Fines assessment -- $today
EOM
    if ($filename) {
        say "Saved to $filename";
    }
    print <<"EOM";
Number of Overdue Items:
     counted $overdue_items
     reported $counted
     updated $updated

EOM
}

cronlogaction({ action => 'End', info => "COMPLETED" });

sub set_holiday {
    my ($branch, $dt) = @_;

    my $calendar = Koha::Calendar->new(branchcode => $branch);
    return $calendar->is_holiday($dt);
}

sub get_filename {
    my $directory = shift;
    if (!$directory) {
        $directory = C4::Context::temporary_directory;
    }
    if (!-d $directory) {
        carp "Could not write to $directory ... does not exist!";
    }
    my $name = C4::Context->config('database');
    $name =~ s/\W//;
    $name .= join q{}, q{_}, $today->ymd(), '.log';
    $name = File::Spec->catfile($directory, $name);
    if ($verbose && $log) {
        say "writing to $name";
    }
    return $name;
}

sub calculate_fine {
    my ($days_overdue) = @_;

    my $fine = 0;

    if ($days_overdue >= 1 && $days_overdue <= 15) {
        $fine = $days_overdue * 1;  # 1 tk per day for 1-15 days
    } elsif ($days_overdue >= 16 && $days_overdue <= 45) {
        $fine = $days_overdue * 2;  # 2 tk per day for 16-45 days
    } else {
        $fine = $days_overdue * 5;  # 5 tk per day for 46+ days
    }

    return $fine;
}
