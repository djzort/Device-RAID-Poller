
package Device::RAID::Poller::Backends::FBSD_graid;

use 5.006;
use strict;
use warnings;

=head1 NAME

Device::RAID::Poller::Backends::FBSD_graid - FreeBSD GEOM RAID backend.

=head1 VERSION

Version 0.0.0

=cut

our $VERSION = '0.0.0';


=head1 SYNOPSIS

    use Device::RAID::Poller::Backends::FBSD_graid;
    
    my $backend = Device::RAID::Poller::Backends::FBSD_graid->new;
    
    my $usable=$backend->usable;
    my %return_hash;
    if ( $usable ){
        %return_hash=$backend->run;
        my %status=$backend->run;
        use Data::Dumper;
        print Dumper( \%status );
    }

=head1 METHODS

=head2 new

Initiates the backend object.

    my $backend = Device::RAID::Poller::Backends::FBSD_graid->new;

=cut

sub new {
	my $self = {
				usable=>0,
				};
    bless $self;

    return $self;
}

=head2 run

Runs the poller backend and report the results.

If nothing is nothing is loaded, load will be called.

    my %status=$backend->run;
    use Data::Dumper;
    print Dumper( \%status );

=cut

sub run {
	my $self=$_[0];

	my %return_hash=(
					 'status'=>0,
					 'devices'=>{},
					 );

	# if not usable, no point in continuing
	if ( ! $self->{usable} ){
		return %return_hash;
	}

	# Fetch the raw gmirror status.
	my $raw=`/sbin/graid status`;
	if ( $? != 0 ){
		return %return_hash;
	}

	my @raw_split=split( /\n/, $raw );

	# The first line contains nothing of interest.
	shift @raw_split;

	my $dev=undef;
	foreach my $line (@raw_split){
		my @line_split=split( /[\t ]+/, $line );

		# lines starting with mirror mean we have a new dev
		if ( $line_split[0] =~ /^raid/ ){
			$dev=$line_split[0];

			# attempt to find the RAID level for the current device
			my $raid_name=$dev;
			$raid_name=~s/^raid\///;
			my $level='unknown';
			my $list_raw=~`/sbin/graid list $raid_name`;
			if ( $? == 0 ){
				my @list_split=split(/\n/, $list_raw);
				my @levels=grep(/RAIDLevel\:/, @list_split);
				if ( defined( $levels[0] ) ){
					my $level=$levels[0];
					chomp($level);
					$level=~s/[\t ]*RAIDLevel\:[\t ]*//;
				}
			}

			#create the device if needed in the return hash
			if ( ! defined( $return_hash{$dev} ) ){
				$return_hash{devices}{$dev}={
									'backend'=>'FBSD_graid',
									'name'=>$dev,
									'good'=>[],
									'bad'=>[],
									'spare'=>[],
									'type'=>$level,
									'BBUstatus'=>'na',
									'status'=>'unknown',
									};
			}

			# Check known mirror status values.
			if ( $line_split[1] =~ /OPTIMAL/ ){
				$return_hash{devices}{$dev}{status}='good';
			}elsif( $line_split[1] =~ /DEGRADED/ ){
				$return_hash{devices}{$dev}{status}='bad';
			}elsif( $line_split[1] =~ /BROKEN/ ){
				$return_hash{devices}{$dev}{status}='bad';
			}

			# Check known disk status values.
			if ( $line_split[3] =~ /REBUILD/ ){
				$return_hash{devices}{$dev}{status}='rebuilding';
				push( @{ $return_hash{devices}{$dev}{good} }, $line_split[2] );
			}elsif( $line_split[3] =~ /ACTIVE/ ){
				push( @{ $return_hash{devices}{$dev}{good} }, $line_split[2] );
			}else{
				push( @{ $return_hash{devices}{$dev}{bad} }, $line_split[2] );
			}

		}else{
			# Check known disk status values.
			# Values pulled from sys/geom/mirror/g_mirror.c
			if ( $line_split[2] =~ /REBUILD/ ){
				$return_hash{$dev}{status}='rebuilding';
				push( @{ $return_hash{devices}{$dev}{good} }, $line_split[1] );
			}elsif( $line_split[2] =~ /ACTIVE/ ){
				push( @{ $return_hash{devices}{$dev}{good} }, $line_split[1] );
			}else{
				push( @{ $return_hash{devices}{$dev}{bad} }, $line_split[1] );
			}
		}
	}

	$return_hash{status}=1;

	return %return_hash;
}

=head2 usable

Returns a perl boolean for if it is usable or not.

    my $usable=$backend->usable;
    if ( ! $usable ){
        print "This backend is not usable.\n";
    }

=cut

sub usable {
	my $self=$_[0];

	if (
		( $^O !~ 'freebsd' ) &&
		( ! -x '/sbin/graid' )
		){
		$self->{usable}=0;
		return 0;
	}

	# Test for it this way as '/sbin/kldstat -q -n geom_raid3' will error
	# if it is compiled in.
	system('/sbin/sysctl -q kern.geom.raid.enable > /dev/null');
	if ( $? != 0 ){
		$self->{usable}=0;
        return 0;
	}

	$self->{usable}=1;
	return 1;
}

=head1 AUTHOR

Zane C. Bowers-Hadley, C<< <vvelox at vvelox.net> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-device-raid-poller at rt.cpan.org>, or through
the web interface at L<https://rt.cpan.org/NoAuth/ReportBug.html?Queue=Device-RAID-Poller>.  I will be
notified, and then you'll automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Device::RAID::Poller


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<https://rt.cpan.org/NoAuth/Bugs.html?Dist=Device-RAID-Poller>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Device-RAID-Poller>

=item * CPAN Ratings

L<https://cpanratings.perl.org/d/Device-RAID-Poller>

=item * Search CPAN

L<https://metacpan.org/release/Device-RAID-Poller>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

This software is Copyright (c) 2019 by Zane C. Bowers-Hadley.

This is free software, licensed under:

  The Artistic License 2.0 (GPL Compatible)


=cut

1; # End of Device::RAID::Poller
