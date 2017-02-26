#!/usr/bin/perl 

use strict;
use warnings;
use Getopt::Long qw(:config bundling); # cli params
use Pod::Usage;                        # cli params help
use Gtk2 '-init';

sub syntaxCheck{
	my %params = ( # default cli params
		'exit'     => undef,  # exit on reaching 0
		'format'   => '%.1f', # format of time
		'start'    => undef,  # immediate start
		'step'     => .1,     # time step to display
		'time'     => 60,     # save external links from id till id, using db
		'verbose'  => 1,      # trace; grade of verbosity
		'version'  => 0,      # diplay version and exit
	);
	GetOptions(\%params,
		'exit|e',
		'format|f=s',
		'start|s',
		'step=s',
		'time|t=i',
		'silent|quiet|q' => sub { $params{'verbose'} = 0;},
		'very-verbose' => sub { $params{'verbose'} = 2;},
		'verbose|v:+',
		# auto_version will not auto make use of 'V'
		'version|V' => sub { Getopt::Long::VersionMessage();},
		# auto_help will not auto make use of 'h'
		'help|?|h' => sub { Getopt::Long::HelpMessage(
				-verbose  => 99,
				-sections => 'NAME|SYNOPSIS|EXAMPLES');},
		'man' => sub { pod2usage(-exitval => 0, -verbose => 2);},
	) or pod2usage(-exitval => 2);
	$params{'verbose'} = 1 unless exists $params{'verbose'};
	my @additional_params = (0,0); # number of additional params (min, max);
	if(@ARGV < $additional_params[0] or 
		($additional_params[1] != -1 and @ARGV>$additional_params[1])){
		if($additional_params[0]==$additional_params[1]){
			print "error: number of arguments must be exactly $additional_params[0]," . 
				" but is ".(0+@ARGV).".\n";
		}else{
			print "error: number of arguments must be at least $additional_params[0]" . 
				" and at most " . 
				($additional_params[1] == -1 ? 'inf' : $additional_params[1]) . 
				", but is ".(0+@ARGV).".\n";
		}
		print "please use -h for help\n";
		exit 2;
	}
	return \%params;
}

{
	package Countdown;
	use Glib qw/TRUE FALSE/;
	use Gtk2;
	use Gtk2::Gdk::Keysyms;
	use Data::Dumper;
	sub new{
		my $class = shift;
		my $params = shift;
		my $self = bless {
			'start_time'   => $params->{'time'},
			'current_time' => $params->{'time'},
			'time_format'  => $params->{'format'},
			'time_step'    => 1. * $params->{'step'},
			'exit_on_zero' => $params->{'exit'},
			'win_width'    => undef,
			'win_height'   => undef,
			'timeout_id'   => undef,
			'fontsize'     => 50000,
			'time_label'   => Gtk2::Label->new(), 
			'window'       => Gtk2::Window->new('toplevel'),
			'vbox'         => Gtk2::VBox->new(FALSE, 1),
			'hbox'         => Gtk2::HBox->new(FALSE, 1),
			'reset_button' => Gtk2::Button->new("reset"),
			'start_button' => Gtk2::Button->new("start"),
		}, $class;
		$self->init_gui;
		$self->start_button_clicked if $params->{'start'};
		return $self;
	}

	sub init_gui{
		my $self = shift;
		# create a new window
		$self->{'window'}->set_size_request(400, 200); # w, h
		$self->{'window'}->set_position('center_always');
		$self->{'window'}->set_title("countdown");
		$self->{'window'}->signal_connect('delete_event' => sub { Gtk2->main_quit; FALSE; });
		$self->{'window'}->signal_connect('key-press-event' => \&key_handler, $self);
		$self->{'window'}->signal_connect('size-allocate' => \&resize_handler, $self);

		$self->{'window'}->add($self->{'vbox'});
		$self->{'vbox'}->show;

		$self->write_str_to_label($self->{'start_time'});
		$self->{'vbox'}->pack_start($self->{'time_label'}, TRUE, TRUE, 0);
		$self->{'time_label'}->show;

		$self->{'vbox'}->pack_start($self->{'hbox'}, FALSE, FALSE, 2);
		$self->{'hbox'}->show;

		$self->{'hbox'}->pack_start($self->{'reset_button'}, FALSE, FALSE, 0);
		$self->{'reset_button'}->show;

		$self->{'hbox'}->pack_start($self->{'start_button'}, FALSE, FALSE, 2);
		$self->{'start_button'}->show;

		$self->{'reset_button'}->signal_connect(
			clicked => sub { &reset_button_clicked($self)}
		);

		$self->{'start_button'}->signal_connect(
			clicked => sub { &start_button_clicked($self)}
		);

		# always display the window as the last step so it all splashes on
		# the screen at once.
		$self->{'window'}->show;
		return 1;
	}

	sub write_str_to_label{
		my $self = shift;
		my $str  = shift;
		$str = sprintf($self->{'time_format'}, $str) if $str =~ /^-?[0-9]+(?:\.[0-9]+)?\z/;
		$self->{'time_label'}->set_markup('<span size="' . $self->{'fontsize'} . '">' . $str . '</span>');
		return 1;
	}

	sub resize_handler{
		my ($window, $rect, $self) = @_;
		my @size = $window->get_size();
		unless(defined $self->{'win_width'} and defined $self->{'win_height'} and 
			$self->{'win_width'} == $size[0] and $self->{'win_height'} == $size[1]){
			($self->{'win_width'}, $self->{'win_height'}) = @size;
			my $w = $size[0] * 300;
			my $h = $size[1] * 800;
			$self->{'fontsize'} = ($w < $h) ? $w : $h;
			#print "".(join ', ', @size)." -> $self->{'fontsize'}\n";
			$self->resize_label;
		}
		return FALSE;
	}

	sub key_handler{
		my ($widget, $event, $self) = @_;
		return FALSE unless $event;
		my $key_nr = $event->keyval();
		if($key_nr == 65307){
			# escape
			Gtk2->main_quit;
		}elsif($key_nr == 43 or $key_nr == 65451){
			# [+]
			$self->{'fontsize'} += 1_000;
			$self->resize_label;
		}elsif($key_nr == 45 or $key_nr == 65453){
			# [-]
			$self->{'fontsize'} -= 1_000;
			$self->{'fontsize'} = 1 if $self->{'fontsize'} < 1;
			$self->resize_label;
		}elsif($key_nr == 42 or $key_nr == 65450){
			# [+]
			$self->{'fontsize'} += 10_000;
			$self->resize_label;
		}elsif($key_nr == 47 or $key_nr == 65455){
			# [-]
			$self->{'fontsize'} -= 10_000;
			$self->{'fontsize'} = 1 if $self->{'fontsize'} < 1;
			$self->resize_label;
		}elsif($key_nr == 99 or $key_nr == 67){
			# [cC]
		}elsif($key_nr == 112 or $key_nr == 80){
			# [pP]
		}elsif($key_nr == 114 or $key_nr == 82){
			# [rR]
			$self->reset_button_clicked();
		}elsif($key_nr == 115 or $key_nr == 83){
			# [sS]
			$self->start_button_clicked();
		}elsif($key_nr == 32){
			# space
		}elsif($key_nr == 65293 or $key_nr == 65421){
			# enter
		}
		#run trough the available key names, and get the values of each,
		#compare this with $event->keyval(), when you get a match exit the loop
		#for my $key(keys %Gtk2::Gdk::Keysyms){
		#	my $key_compare = $Gtk2::Gdk::Keysyms{$key};
		#	if($key_compare == $key_nr){
		#		print "key pressed: $key -> numeric value: $key_nr\n";
		#		last;
		#	}
		#}
		#good practice to let the event propagate, should we need it somewhere else
		return FALSE;
	}

	sub change{
		my $self = shift;
		if($self->{'current_time'} > $self->{'time_step'}){
			$self->{'current_time'} -= $self->{'time_step'};
			$self->write_str_to_label($self->{'current_time'});
			return TRUE;
		}else{
			$self->{'current_time'} = 0;
			$self->{'timeout_id'} = undef;
			exit if $self->{'exit_on_zero'};
			$self->write_str_to_label('over!');
			return FALSE;
		}
	}

	sub resize_label{
		my $self = shift;
		my $pango_size = new Gtk2::Pango::AttrSize($self->{'fontsize'});
		my $pango_list = new Gtk2::Pango::AttrList;
		$pango_list->insert($pango_size);
		$self->{'time_label'}->set_attributes($pango_list);
		return 1;
	}

	sub reset_button_clicked{
		my $self = shift;
		$self->write_str_to_label($self->{'start_time'});
		$self->{'start_button'}->set_label('start');
		$self->{'current_time'} = $self->{'start_time'};
		if(defined $self->{'timeout_id'}){
			Glib::Source->remove($self->{'timeout_id'});
			$self->{'timeout_id'} = undef;
		}
		return FALSE;
	}

	sub start_button_clicked{
		my $self = shift;
		if($self->{'start_button'}->get_label() eq 'pause'){
			if(defined $self->{'timeout_id'}){
				Glib::Source->remove($self->{'timeout_id'});
				$self->{'timeout_id'} = undef;
			}
			$self->{'start_button'}->set_label('continue');
		}else{
			$self->{'timeout_id'} = Glib::Timeout->add(1000*$self->{'time_step'}, sub{ &change($self) });
			$self->{'start_button'}->set_label('pause');
		}
		return FALSE;
	}

}

my $params = syntaxCheck(@ARGV);
my $cd = Countdown->new($params);
Gtk2->main;

__END__

=head1 NAME

countdown starts a gtk2-gui for a countdown

=head1 DESCRIPTION

this program lets you start a countdown timer.

=head1 SYNOPSIS

countdown [options]

(there are no mandatory options, only mandatory sub-options)

general options:

 -e, --exit                    exit on reaching zero
 -f, --format=s                time format to use for displaying
 -s, --start                   immediately start the countdown
     --step=f                  time step to diplay
 -t, --time=i                  don't change anything, just print possible changes

meta options:

 -V, --version                 display version and exit.
 -h, --help                    display brief help
     --man                     display long help (man page)
 -q, --silent                  same as --verbose=0
 -v, --verbose                 same as --verbose=1 (default)
 -vv,--very-verbose            same as --verbose=2
 -v, --verbose=x               grade of verbosity
                                x=0: no output
                                x=1: default output
                                x=2: much output

=head1 EXAMPLES

countdown
  starts the countdown gui with default start value

countdown --time=70
  starts the countdown gui with 70 seconds as start value

countdown -st 70
  starts the countdown gui with 70 seconds as start value and starts the timer

=head1 OPTIONS

=head2 GENERAL

=over 8

=item B<-e>, B<--exit>

=item B<-f>, B<--format>=I<format>

set time format to use for displaying

exit on reaching zero

=item B<-s>, B<--start>

immediately start the countdown

=item B<--step>=I<float>

use this time step in seconds in display

=item B<-t>, B<--time>=I<integer>

set start value in seconds, default = 60

=back

=head2 META

=over 8

=item B<--version>, B<-V>

prints version and exits.

=item B<--help>, B<-h>, B<-?>

prints a brief help message and exits.

=item B<--man>

prints the manual page and exits.

=item B<--verbose>=I<number>, B<-v> I<number>

set grade of verbosity to I<number>. if I<number>==0 then no output
will be given, except hard errors. the higher I<number> is, the more 
output will be printed. default: I<number> = 1.

=item B<--silent, --quiet, -q>

same as B<--verbose=0>.

=item B<--very-verbose, -vv>

same as B<--verbose=2>. you may use B<-vvv> for B<--verbose=3> a.s.o.

=item B<--verbose, -v>

same as B<--verbose=1>.

=back

=head1 LICENCE

Copyright (c) 2017, seth
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this
  list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

originally written by seth (see https://github.com/wp-seth)

=cut

