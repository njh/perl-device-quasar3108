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
use vars qw/$VERSION/;

use Device::SerialPort;
use Carp;

$VERSION="0.01";



sub new {
    my $class = shift;
    
    # Create serial port
	my $port = new Device::SerialPort( @_ );
		|| croak "Can't open serial port: $!\n";


	# Configure the serial port
	$port->baudrate(9600)    || croak ("Failed to set baud rate");
	$port->parity("none")    || croak ("Failed to set parity");
	$port->databits(8)       || croak ("Failed to set data bits");
	$port->stopbits(1)       || croak ("Failed to set stop bits");
	$port->handshake("none") || croak ("Failed to set hardware handshaking");


	# Bless me
    my $self = { port => $port };
    bless $self, $class;

    return $self;
}


sub DESTROY {
    my $self=shift;
    
    $self->{port}->close || carp "close serial port failed";
}
