package Device::Quasar3108;

################
#
# Device::Quasar3108 - Quasar Electronics Kit Number 3108
#
# Nicholas Humfrey
# njh@ecs.soton.ac.uk
#
# See the bottom of this file for the POD documentation. 
#


use strict;
use vars qw/$VERSION $DEFAULT_TIMEOUT $DEFAULT_PERIOD/;

use Device::SerialPort;
use Time::HiRes qw( time sleep alarm );
use Carp;

$VERSION="0.01";
$DEFAULT_TIMEOUT=5;		# Default timeout is 5 seconds
$DEFAULT_PERIOD=0.25;	# Default flash period



sub new {
    my $class = shift;
    my ($portname, $timeout) = @_;
    
    # Defaults
	$portname = '/dev/ttyS0' unless (defined $portname);
	$timeout = $DEFAULT_TIMEOUT unless (defined $timeout);


    # Create serial port object
	my $port = new Device::SerialPort( $portname )
		|| croak "Can't open serial port ($portname): $!\n";


	# Check serial port features
	croak "ioctl isn't available for serial port: $portname"
	unless ($port->can_ioctl());
	croak "status isn't available for serial port: $portname"
	unless ($port->can_status());
	croak "write_done isn't available for serial port: $portname"
	unless ($port->can_write_done());


	# Configure the serial port
	$port->baudrate(9600)    || croak ("Failed to set baud rate");
	$port->parity("none")    || croak ("Failed to set parity");
	$port->databits(8)       || croak ("Failed to set data bits");
	$port->stopbits(1)       || croak ("Failed to set stop bits");
	$port->handshake("none") || croak ("Failed to set hardware handshaking");
	$port->write_settings()  || croak ("Failed to write settings");
	$port->read_char_time(0);     # don't wait for each character
	$port->read_const_time(1000); # 1 second per unfulfilled "read" call



	# Bless me
    my $self = {
    	port => $port,
    	timeout => $timeout,
    	debug => 0,
    };
    bless $self, $class;

    return $self;
}


## Version of the hardware firmware
sub firmware_version {
    my $self=shift;
	
	$self->serial_write( '?' );
	
	return $self->serial_read();
}




## Version of perl module
sub version {
    return $VERSION;
}


## Check module is still there
sub ping {
    my $self=shift;
	
	$self->serial_write( '' );
	my $ok = $self->serial_read( 1 );
	if ($ok eq '#') { return 1; } # Success
	else { return 0; }  # Failed
}


## Turn specified relay on
sub relay_on {
	my $self=shift;
	my ($num) = @_;
	croak('Usage: relay_on( $num );') unless (defined $num);
	
	$self->serial_write( 'N'.int($num) );
	my $ok = $self->serial_read( 1 );
	if ($ok eq '#') { return 1; } # Success
	else { return 0; }  # Failed
}


## Turn specified relay off
sub relay_off {
	my $self=shift;
	my ($num) = @_;
	croak('Usage: relay_off( $num );') unless (defined $num);

	$self->serial_write( 'F'.int($num) );
	my $ok = $self->serial_read( 1 );
	if ($ok eq '#') { return 1; } # Success
	else { return 0; }  # Failed
}

## Toggle specified relay
sub relay_toggle {
	my $self=shift;
	my ($num) = @_;
	croak('Usage: relay_toggle( $num );') unless (defined $num);

	$self->serial_write( 'T'.int($num) );
	my $ok = $self->serial_read( 1 );
	if ($ok eq '#') { return 1; } # Success
	else { return 0; }  # Failed
}


## Toggle relay on and then off again
sub relay_flash {
	my $self=shift;
	my ($num,$period) = @_;
	croak('Usage: relay_flash( $num, [$period] );') unless (defined $num);

	# Use default period if none given
	$period = $DEFAULT_PERIOD unless (defined $period);
	
	# Turn relay on, sleep for period, turn relay off again
	$self->relay_on( $num ) || return 0;
	sleep( $period );
	$self->relay_off( $num ) || return 0;

	# Success
	return 1;
}


## Set all relays to specified value
sub relay_set {
	my $self=shift;
	my ($value) = @_;
	croak('Usage: relay_set( $value );') unless (defined $value);

	$self->serial_write( 'R'.sprintf("%2.2x",$value) );
	my $ok = $self->serial_read( 1 );
	if ($ok eq '#') { return 1; } # Success
	else { return 0; }  # Failed
}


## Get state of specified relay
sub relay_status {
	my $self=shift;
	my ($num) = @_;
	$num = 0 unless defined ($num);
	
	$self->serial_write( 'S'.$num );
	return $self->serial_read();
}

## Get state of specified input
sub input_status {
	my $self=shift;
	my ($num) = @_;
	$num = 0 unless defined ($num);
	
	$self->serial_write( 'I'.$num );
	return $self->serial_read();
}



sub serial_write {
    my $self=shift;
	my ($string) = @_;
	my $bytes = 0;

	# if it doesn't end with a '\r' then append one
	$string .= "\r\n" if ($string !~ /\r\n?$/);

	
	eval {
		local $SIG{ALRM} = sub { die "Timed out."; };
		alarm($self->{timeout});
		
		# Send it
		$bytes = $self->{port}->write( $string );
		
		# Block until it is sent
		while(($self->{port}->write_done(0))[0] == 0) {}
		
		alarm 0;
	};
	
	if ($@) {
		die unless $@ eq "Timed out.\n";   # propagate unexpected errors
		# timed out
		carp "Timed out while writing to serial port.\n";
 	}
 	
 	
	# Debugging: display what was read in
	if ($self->{debug}) {
		my $serial_debug = $string;
		$serial_debug=~s/([^\040-\176])/sprintf("{0x%02X}",ord($1))/ge;
		print "written ->$serial_debug<- ($bytes)\n";
	}

 	# Read in the echoed back characters
 	my $echo = $self->serial_read( length($string) );
	### FIXME: Could do error checking here ###
}

sub serial_read
{
    my $self=shift;
    my ($bytes_wanted) = @_;
	my ($string, $bytes) = ('', 0);
	
	# Default bytes wanted is 255
	$bytes_wanted=255 unless (defined $bytes_wanted);
	

	eval {
		local $SIG{ALRM} = sub { die "Timed out."; };
		alarm($self->{timeout});
		
		while (1) {
			my ($count,$got)=$self->{port}->read($bytes_wanted);
			$string.=$got;
			$bytes+=$count;
			
			## All commands end in the command prompt '#'
			last if ($string =~ /#$/ or $bytes>=$bytes_wanted);
		}
		
		alarm 0;
	};
	
	if ($@) {
		die unless $@ eq "Timed out.\n";   # propagate unexpected errors
		# timed out
		carp "Timed out while reading from serial port.\n";
 	}
 
	# Debugging: display what was read in
	if ($self->{debug}) {
		my $debug_str = $string;
		$debug_str=~s/([^\040-\176])/sprintf("{0x%02X}",ord($1))/ge;
		print "saw ->$debug_str<- ($bytes) (wanted=$bytes_wanted)\n";
	}
 
 
 	# Clean up response
 	if ($bytes_wanted == 1) {
 		return $string;
 	} else {
 		# Remove whitespace from start and end
		($string) = ($string =~ /^\s*(.*)\s*\#$/);
 		return $string;
 	}
 	
	return $string;
}


sub DESTROY {
    my $self=shift;
    
    $self->{port}->close || carp "close serial port failed";
}
