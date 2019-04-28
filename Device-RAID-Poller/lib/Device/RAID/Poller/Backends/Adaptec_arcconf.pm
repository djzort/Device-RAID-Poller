package Device::RAID::Poller::Backends::Adaptec_arcconf;

use 5.006;
use strict;
use warnings;

=head1 NAME

Device::RAID::Poller::Backends::Adaptec_arcconf - Handles polling using the Adaptec arcconf utility.

=head1 VERSION

Version 0.0.0

=cut

our $VERSION = '0.0.0';


=head1 SYNOPSIS

    use Device::RAID::Poller::Backends::Adaptec_arcconf;
    
    my $backend = Device::RAID::Poller::Backends::Adaptec_arcconf->new;
    
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

    my $backend = Device::RAID::Poller::Backends::Adaptec_arcconf->new;

=cut

sub new {
	my $self = {
				usable=>0,
				adapters=>0,
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

	$return_hash{status}=1;

	# get a list of devices
	my $raw=`mdadm --detail --scan`;
	my @raw_split=split(/\n/, $raw);
	my @devs;
	foreach my $line (@raw_split){
		if ( $line =~ /^ARRAY/ ){
			my @line_split=split(/[\t ]+/, $line);
			push(@devs, $line_split[1]);
		}
	}

	# Process each md device that exists.
	foreach my $dev (@devs){
		$return_hash{devices}{$dev}={
									 'backend'=>'Linux_mdadm',
									 'name'=>$dev,
									 'good'=>[],
									 'bad'=>[],
									 'spare'=>[],
									 'type'=>'mdadm',
									 'BBUstatus'=>'na',
									 'status'=>'unknown',
									 };

		# check device and break it appart
		$raw=`mdadm --detail $dev`;
		@raw_split=split(/\n/, $raw);
		my $number_found=0;
		my $process=0;
		foreach my $line (@raw_split){
			chomp($line);

			if ( $line =~ /[\t ]*Number/ ){
				$number_found=1;
			}elsif( $number_found ){
				$process=1;
			}

			if ( $process ){
				# good disk...
				# active
				# rebuilding
				# bad disk...
				# removed
				# spare disks...
				# spare

				# spare rebuilding = good, rebuilding... in the process of becoming not a spare

				my $disk_status='good';
				if (
					( $line =~ /active/ ) ||
					( $line =~ /rebuilding/ )
					){
					$disk_status='good';
				}

				if ( $line =~ /spare/ ){
					$disk_status='spare';
				}

				if (
					( $line =~ /spare/ ) &&
					( $line =~ /rebuilding/ )
					){
					$disk_status='good';
				}

				if ( $line =~ /removed/ ){
					$disk_status='bad';
				}

				$line=~s/^.*[\t ]//;
				push(@{ $return_hash{devices}{$dev}{$disk_status} }, $line);
			}{
				if ( $line =~ /^[\t ]*State/ ){
					# good states...
					# clean
					# active
					# bad states...
					# degraded
					# inactive
					# rebuilding states...
					# resyncing
					# recovering

					# clean, degraded = degraded
					# clean, degraded, recovering = rebuilding

					if (
						( $line =~ /clean/ ) ||
						( $line =~ /active/ )
						){
						$return_hash{devices}{$dev}{status}='good';
					}

					if ( $line =~ /degraded/ ){
						$return_hash{devices}{$dev}{status}='bad';
					}

					if (
						( $line =~ /recovering/ ) ||
						( $line =~ /resyncing/ )
						){
						$return_hash{devices}{$dev}{status}='rebuilding';
					}

					if ( $line =~ /inactive/ ){
						$return_hash{devices}{$dev}{status}='bad';
					}

				}elsif( $line =~ /^[\t ]*Raid\ Level[\t ]*\:[\t ]*/ ){
					$line=~s/^[\t ]*Raid\ Level[\t ]*\:[\t ]*//;
					$return_hash{devices}{$dev}{type}=$line;
				}
			}

		}
	}

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
		( $^O !~ 'linux' ) ||
		( $^O !~ 'freebsd' )
		){
		$self->{usable}=0;
		return 0;
	}

	# make sure we can locate mdadm
	my $mdadm_bin=`which arcconf`;
	if ( $? != 0 ){
		$self->{usable}=0;
        return 0;
	}

	# make sure we have atleast one device
	my $raw=`arcconf LIST`;
	if ( $? != 0 ){
		$self->{usable}=0;
        return 0;
	}
	my @raw_split=split(/\n/, $raw);
	my @found_lines=grep(/Controllers\ found/, @raw_split);
	if (defined( $found_lines[0] )){
		# grab the first and should be online line, which should be formatted like below...
		# Controllers found: 1
		my $found=$found_lines[0];
		chomp($found);
		$found=~s/.*\:[\t ]*//;
		if (
			( $found =~ /[0123456789]+/ ) &&
			( $found > 0 )
			){
			$self->{adapters}=$found;
		}else{
			# either contains extra characters or zero
			$self->{usable}=0;
			return 0;
		}
	}else{
		# Command errored in some way or output changed.
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
