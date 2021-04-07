#!/usr/bin/perl
use warnings;
use strict;

use Getopt::Long;
use Pod::Usage;
use Tk;
use Tk qw(:eventtypes);
use Tk::JPEG;
use Tk::LabFrame;
use Tk::Photo;
use MIME::Base64;
use File::Spec;
use Data::Dumper;
# libgd 2.0.33 or higher required for copyRotated
use GD 2.0.33;
GD::Image->trueColor(1);

my $pi = 3.14159265358979323846;
##############################################
my $rotator = bless {
    
	# MAINWINDOW AND PREVIEW
	mainwindow => new MainWindow(), 	# Tk mainwindow
    photowindow => undef,				# Tk photo window
    ratio => .25,						# ratio used to build the preview
    gdorig => undef,					# the original image loaded by GD
	gdres => undef, 					# the GD image used aas preview
	canvas => undef,					# Tk canvas used for the image preview
	tk_line => undef,  					# the Tk line drawn into the canvas
	tk_linecolor=> 'red', 				# the Tk color of the above line..
    tk_linewidth => 3, 					# ..and its width
	tk_circle => undef, 				# the Tk circle drawn into the canvas to mark the center
	tk_circlecolor => 'yellow', 		# the color of the circle
    tk_vertex => undef, 				# the Tk circle to mark the vertex of the triangle (debug)
	tk_photo => undef,					# the Tk::Photo shown in the canvas (to be cleared and reused)
    tk_description_label => undef, 		# the Tk label to display current processing of the list
	
	# POINTS OF THE IMAGES
	p1 => undef, 						# P1[x,y] set left clicking on the preview
	p2 => undef, 						# P2[x,y] set right clicking on the preview
	center => undef, 					# [x,y] the middle point between P1 and P2 in the preview
	ocenter => undef, 					# [x,y] coordinates of the center transposed in the original image
	vertex => undef,					# [x,y] vertex used to build the square triangle to compute angle
	hypotenuse => undef,				# distance in pixel from P1 to P2 in the preview
	ohypotenuse => undef,				# distance in pixel from P1 to P2 in the original image    
	rotation => undef, 					# rotation COUNTER clockwise to apply to the image
	
	# INPUT AND OUTPUT OPTIONS 
    directory => File::Spec->rel2abs( '.' ), 	# source directory containing jpg files
    out_directory => File::Spec->rel2abs( '.' ),# destination directory to write modified jpg files
    glob => '*.jpg',							# glob used to select files in the source directory 
	files => [], 								# the list of files to process
	fileindex => 0,								# current index in the above list
    out_file_prefix => 'r_',					# prefix to apply the output file name 
	out_file_number => 0,  						# starting number to increment and use to compose file name
	out_original_name => 1,						# specify if to use or not the original name to compose the output name
    
    # DEBUG
    debug => 0,							# output simple debug informations to the screen 
	devdebug => 0, 						# enabled via --devdebug switch force the basic debug
										# adding more output to it and writing debug images with 
										# red lines and points for each stage of processing
	
	# ROTATION
	enable_rotation => 1, 				# main switch to enable image rotation
    tk_force_angle => 0, 				# Tk checkbox to enable horizontal/vertical line
	tk_force_angle_lbl => undef,		# Tk label about forcing angle
	force_line_direction => 0, 			# used to force line to be [horizontal|vertical]
	tk_force_horizontal => undef, 		# Tk radiobutton for horizonatal
	tk_force_vertical => undef,			# Tk radiobutton for vertical
	
	# RESIZING
	enable_resize => 0,					# main switch to enable resizing
	tk_force_resize_lbl => undef,		# descriptive label	
	tk_force_resize_entry => undef, 	# entry for the wanted size
	forced_size => undef,				# the wanted size in..
	forced_size_unit => 'pixel',		# ..pixel or mm
	resize_ratio	=> undef,			# ratio used for resize and cropping
	tk_forced_size_px => undef,			# radio button for pixel
	tk_forced_size_mm => undef,			# radio button for mm
	enable_mm	=> 0,					# switch to enable mm measures (--enablemm in commandline)
	
	# CROPPING
	enable_cropping => 0,				# main switch to enable cropping
	tk_force_crop_lbl_a  => undef,		# first tk label
	tk_force_crop_entry_width => undef,	# the tk entry for width
	forced_crop_width => 1024,			# the forced crop width
	tk_force_crop_lbl_b => undef,		# the tk second label
	tk_force_crop_entry_height => undef,# the tk entry for height
	forced_crop_height => 768,			# the forced height
	    
}, 'main'; 

# system 'rm gd_0*.jpg';

GetOptions(
        
        'devdebug'     =>  \$rotator->{devdebug},
        'enablemm'     =>  \$rotator->{enable_mm},
        
    ) or pod2usage(-verbose => 0, -exitval => 1);

$rotator->{debug} = 1 if $rotator->{devdebug};

$rotator->{files} = [ glob File::Spec->catfile( $rotator->{directory},$rotator->{glob} ) ];

$rotator->fill_description_label();

$rotator->init_control_window();

$rotator->init_original_photo();

$rotator->{mainwindow}->MainLoop;


################################################################################
# Tk subs
################################################################################
sub fill_description_label{
    my $self = shift;
    if ( 0 == scalar @{$self->{files} } ){
        $self->{tk_description_label} = '(no file in the list)';
    }
    else{
        $self->{tk_description_label} = "file ".($self->{fileindex}+1).
                                    " of ".(scalar @{$self->{files}}).": ".
                                    ${$self->{files}}[ $self->{fileindex} ];
    }
}
################################################################################
sub init_control_window{
    my $self = shift;
    #$self->{mainwindow}->geometry("600x200+0+0");
    $self->{mainwindow}->title($0);
    $self->{mainwindow}->optionAdd('*font', 'Courier 10');
    $self->{mainwindow}->optionAdd('*Label.font', 'Courier 10');
    $self->{mainwindow}->optionAdd( '*Entry.background',   'lavender' );
    $self->{mainwindow}->optionAdd( '*Entry.font',   'Courier 12 bold'  );
    # TOP FRAME
    my $fr0 = $self->{mainwindow}->LabFrame(
                                    -label=> $0,
                                    -labelside => "acrosstop",   
    )->pack(-side=>'top',-padx=>5,-pady=>2,-fill=>'x');
    
    my $fr0a = $fr0->Frame(
        )->pack(-side=>'top', -pady=>0, -fill=>'x');
    
    $fr0a->Label(-text =>   "Set Point1 left clicking on the image, Point2 right clicking and\n".
                            "the central button of the mouse (or the space bar) to modify the\n".
                            "image using options available below."
        )->pack(-fill=>'x',-expand=>1,-side=>'left',-pady=>5);
    
    my $fr0b = $fr0->Frame(
        )->pack(-side=>'bottom', -pady=>5, -fill=>'x');
    
    $fr0b->Button(-text => "documentation",-borderwidth => 4,
            -command => \&help_me,
        )->pack(-side=>'left', -padx=>10);    
    
    $fr0b->Checkbutton(-variable =>\$self->{debug},
                      -command => sub { print "Debug output ",( $self->{debug} ? 'ENABLED' : 'DISABLED'),"\n" }
        )->pack(-side=>'right',-padx=>10);
    $fr0b->Label(-text => "enable debug output",
        )->pack(-side=>'right',-padx=>10);
    
    # CHOOSE FILES FRAME
    my  $fr2 = $self->{mainwindow}->LabFrame(
                                    -label=> "jpg files to process",
                                    -labelside => "acrosstop",   
		)->pack(-side=>'top',-padx=>5,-pady=>2,-fill=>'x');
    
	# frame 2a must not have -padx=>10 but pady! 
    my $fr2a = $fr2->Frame(
        )->pack(-side=>'top', -pady=>5, -fill=>'x');
    
    $fr2a->Label(-text => "    directory"
        )->pack(-side => 'left');
    
    $fr2a->Entry(-width => 35,-borderwidth => 4, -textvariable => \$self->{directory}
        )->pack(-side => 'left',-padx=>5);
     
    $fr2a->Button(  -text => "browse",
					-borderwidth => 4,
                    -command => sub{
                                    $self->{directory} = $self->{mainwindow}->chooseDirectory(
																-initialdir => $self->{directory},
																-title => 'Choose a folder',
                                    );
                    }
        )->pack(-side => 'right',-padx=>10);
    # frame 2b must not have -padx=>10,
    my $fr2b = $fr2->Frame(
        )->pack(-side=>'top',-fill=>'x');
    
    $fr2b->Label(-text => "         glob"
        )->pack(-side => 'left');
    
    $fr2b->Entry(-width => 10,-borderwidth => 4, -textvariable => \$self->{glob}
        )->pack(-side => 'left', -padx=>5);
        
    # right packed go in reverse order
    # DUMP LIST
    $fr2b->Button(  -text => "dump list",-borderwidth => 4,
                    -command => sub{
                                    print scalar @{$self->{files}}," files in the list:\n"
                                        ,(join "\n", @{$self->{files}}), "\n";
                    },                  
        )->pack(-side => 'right',-padx=>10);
    
	# CLEAR LIST
    $fr2b->Button(  -text => "clear list",-borderwidth => 4,
                    -command => sub{ 
                                    $self->{files} = [];
                                    print "cleared the list of files\n";
                                    $self->fill_description_label();
                                    $self->{fileindex} = 0;
                                    $self->{files} = [];
                                    $self->{photowindow}->withdraw;
                    },                  
        )->pack(-side => 'right',-padx=>10);
    
	# ADD TO LIST
    $fr2b->Button( 	-text => "add to list",
					-borderwidth => 4,
                    -command => sub{
                                    my @toadd = glob File::Spec->catfile( $self->{directory},$self->{glob} );
                                    my %already = map { $_ => 1 } @{$self->{files}};
                                    my $added;
                                    if ( 0 == @toadd ){
                                        print "no file found in $self->{directory}..\n";
                                        if ( 0 == scalar keys %already and $self->{fileindex} == 0 ){
                                            $self->{tk_description_label} = "(no files in the list - no file found in $self->{directory})";
                                        }
                                    }
                                    foreach my $new ( @toadd ){
                                        if ( exists $already{$new} ){
                                            print "skipping a duplicate entry: $new\n";
                                            next;
                                        }
                                        else{
                                            push @{$self->{files}}, $new;
                                            $added++;
                                        }               
                                    }
                                    print "added $added files to the list\n" if $added;
                                    $self->fill_description_label();
                                    # if the list was empty before adding files..
                                    if ( 0 == scalar keys %already and $self->{fileindex} == 0){
                                            $self->init_original_photo();
                                    }
                                    
                    },                  
        )->pack(-side => 'right',-padx=>10);

    #
    my $fr2c = $fr2->Frame(
        )->pack(-side=>'top',-fill=>'x');
    
    $fr2c->Label(-text => 'preview ratio'
        )->pack(-side => 'left');
    
    $fr2c->Entry(-width => 10,-borderwidth => 4, -textvariable => \$self->{ratio}
        )->pack(-side => 'left', -padx=>5);
    
    $fr2c->Button(  -text => "reload",-borderwidth => 4,
                    -command => sub{ $self->init_original_photo() },                    
        )->pack(-side => 'left',-padx=>10); 
        
    # last subframe must have pady 5!
    my $fr2d = $fr2->Frame(
        )->pack(-side=>'top',-fill=>'x',-pady=>5);
    
    $fr2d->Label(-textvariable => \$self->{tk_description_label}
        )->pack(-side => 'top');  
        
    # OUTPUT frame
    my $fr3 = $self->{mainwindow}->LabFrame(
                                    -label=> "output options",
                                    -labelside => "acrosstop",   
    )->pack(-side=>'top',-padx=>5,-pady=>2,-fill=>'x');
    
	# frame 2a must not have -padx=>10 but pady! 
    my $fr3a = $fr3->Frame(
        )->pack(-side=>'top', -pady=>5, -fill=>'x');
    
	$fr3a->Label(-text => "    directory"
        )->pack(-side => 'left');
    
    $fr3a->Entry(-width => 35,-borderwidth => 4, -textvariable => \$self->{out_directory}
        )->pack(-side => 'left',-padx=>5);
     
    $fr3a->Button(  -text => "browse",
					-borderwidth => 4,
                    -command => sub{
                                    $self->{out_directory} = $self->{mainwindow}->chooseDirectory(
                                        -initialdir => $self->{directory},
                                        -title => 'Choose a folder',
                                    );
                    }
    )->pack(-side => 'right',-padx=>10);
    
	# OUTPUT options
    my $fr3b = $fr3->Frame(
        )->pack(-side=>'top', -pady=>5, -fill=>'x');
    
	$fr3b->Label(-text => "  file prefix"
        )->pack(-side => 'left');
    
	$fr3b->Entry(-width => 8,-borderwidth => 4, -textvariable => \$self->{out_file_prefix}
        )->pack(-side => 'left',-padx=>5);
    
	$fr3b->Label(-text => "first number"
        )->pack(-side => 'left');
    
	$fr3b->Entry(-width => 3,-borderwidth => 4, -textvariable => \$self->{out_file_number}
        )->pack(-side => 'left',-padx=>5);
    
    $fr3b->Checkbutton(-variable =>\$self->{out_original_name},
        )->pack(-side => 'left');
                  
    $fr3b->Label(-text => "add original file name"
        )->pack(-side => 'left');                  
                       
    # TRANSFORMATION options	
    # ROTATION					
    my $fr4 = $self->{mainwindow}->LabFrame(
                                    -label=> "rotation",
                                    -labelside => "acrosstop",   
    )->pack(-side=>'top',-padx=>5,-pady=>2,-fill=>'x');
	
	my $fr4a = $fr4->Frame(
        )->pack(-side=>'top', -pady=>5, -fill=>'x');
		
	$fr4a->Checkbutton( -variable =>\$self->{enable_rotation},
						-command=> sub{
#print "FORCE LINE: ",($self->{force_line_direction}//'UNDEF'),"\n";
								if ( $self->{enable_rotation} ){
									$self->{tk_force_angle}->configure( -state=>'normal');
									$self->{tk_force_angle_lbl}->configure( -state=>'normal');
								}
								else{
									$self->{tk_force_angle}->configure( -state=>'disabled' );
									$self->{tk_force_angle_lbl}->configure( -state=>'disabled' );
									$self->{force_angle} = 0;
									$self->{tk_force_angle_lbl}->configure( -state=>'disabled' );
									$self->{force_line_direction} = undef;
									$self->{tk_force_horizontal}->configure( -state=>'disabled', );
									$self->{tk_force_vertical}->configure(-state=>'disabled', );
								}					
						},
        )->pack(-side => 'left');
                  
    $fr4a->Label( -text => "enable image rotation",
        )->pack(-side => 'left');   
    
	my $fr4b = $fr4->Frame(
        )->pack(-side=>'top', -pady=>5, -fill=>'x');
	
	$self->{tk_force_angle} = $fr4b->Checkbutton( 
						-variable =>\$self->{force_angle},
						-command => sub{
							if ( $self->{force_angle} ){
									$self->{tk_force_horizontal}->configure( -state=>'normal');
									$self->{tk_force_vertical}->configure( -state=>'normal');
									#$self->{force_line_direction}->configure( -state=>'normal');
								}
								else{
									$self->{tk_force_angle_lbl}->configure( -state=>'disabled' );
									$self->{force_line_direction} = undef;
									$self->{tk_force_horizontal}->configure(-state=>'disabled', );
									$self->{tk_force_vertical}->configure(-state=>'disabled', );
									
								}
						},
						-state => $self->{enable_rotation} ? 'normal' : 'disabled',
        )->pack(-side => 'left');
	
	$self->{tk_force_angle_lbl} = $fr4b->Label(
					-text => "force line to be",
					-state => $self->{enable_rotation} ? 'normal' : 'disabled',
        )->pack(-side => 'left');

	$self->{tk_force_horizontal} = $fr4b->Radiobutton(
					-text => "horizonatal",
					-variable => \$self->{force_line_direction}, 
					-value=>'horizontal',
					-state => ($self->{tk_force_angle} and $self->{enable_rotation}) ? 'normal' : 'disabled',
        )->pack(-side => 'left');
	
	$self->{tk_force_vertical} = $fr4b->Radiobutton(
					-text => "vertical",
					-variable => \$self->{force_line_direction}, 
					-value=>'vertical',
					-state => ($self->{tk_force_angle} and $self->{enable_rotation}) ? 'normal' : 'disabled',
        )->pack(-side => 'left');
	

	# RESIZE	
    my $fr5 = $self->{mainwindow}->LabFrame(
                                    -label=> "resize",
                                    -labelside => "acrosstop",   
    )->pack(-side=>'top',-padx=>5,-pady=>2,-fill=>'x');
    
    my $fr5a = $fr5->Frame(
        )->pack(-side=>'top', -pady=>5, -fill=>'x');
		
	$fr5a->Checkbutton( -variable =>\$self->{enable_resize},
						-command=> sub{

								if ( $self->{enable_resize} ){
									$self->{tk_force_resize_lbl}->configure( -state=>'normal' );
									$self->{tk_force_resize_entry}->configure( -state=>'normal' );
									$self->{tk_forced_size_px}->configure( -state=>'normal' );
									#$self->{tk_forced_size_mm}->configure( -state=>'normal' );
									# disabled until  $mw->screenmmheight; will be understood
									$self->{tk_forced_size_mm}->configure( -state=> $self->{enable_mm} ? 'normal' : 'disabled' );
									$self->{forced_size_unit} = 'pixel';
								}
								else{
									$self->{tk_force_resize_lbl}->configure( -state=>'disabled');
									$self->{tk_force_resize_entry}->configure( -state=>'disabled');
									$self->{tk_forced_size_px}->configure( -state=>'disabled');
									$self->{tk_forced_size_mm}->configure( -state=>'disabled');
									$self->{forced_size} = undef;
									$self->{forced_size_unit} = undef;
									$self->{resize_ratio} = undef;
								}					
						},
        )->pack(-side => 'left');
                  
    $fr5a->Label( -text => "enable image resizing",
        )->pack(-side => 'left');
	
	my $fr5b = $fr5->Frame(
        )->pack(-side=>'top', -pady=>5, -fill=>'x');
	
	$self->{tk_force_resize_lbl} = $fr5b->Label(
					-text => "force line to be exactly",
					-state => $self->{enable_rotation} ? 'normal' : 'disabled',
        )->pack(-side => 'left');

	$self->{tk_force_resize_entry} = $fr5b->Entry(	
					-width => 5,
					-borderwidth => 4, 
					-textvariable => \$self->{forced_size},
					-state => $self->{forced_size} ? 'normal' : 'disabled',
        )->pack(-side => 'left',-padx=>5);
	
	$self->{tk_forced_size_px} = $fr5b->Radiobutton(
					-text => "pixel",
					-variable => \$self->{forced_size_unit}, 
					-value=>'pixel',
					-state => $self->{forced_size} ? 'normal' : 'disabled',
        )->pack(-side => 'left');
	
	$self->{tk_forced_size_mm} = $fr5b->Radiobutton(
					-text => "mm",
					-variable => \$self->{forced_size_unit}, 
					-value=>'mm',
					-state =>  $self->{forced_size} ? 'normal' : 'disabled',
        )->pack(-side => 'left');
	
	
	# CROP enable_cropping tk_force_crop_lbl_a tk_force_crop_entry_width forced_crop_width tk_force_crop_lbl_b tk_force_crop_entry_height forced_crop_height 
    my $fr6 = $self->{mainwindow}->LabFrame(
                                    -label=> "crop",
                                    -labelside => "acrosstop",   
    )->pack(-side=>'top',-padx=>5,-pady=>2,-fill=>'x');
    
	my $fr6a = $fr6->Frame(
        )->pack(-side=>'top', -pady=>5, -fill=>'x');
	
    $fr6a->Checkbutton( -variable =>\$self->{enable_cropping},
						-command=> sub{

								if ( $self->{enable_cropping} ){
									$self->{tk_force_crop_lbl_a}->configure( -state=>'normal');
									$self->{tk_force_crop_entry_width}->configure( -state=>'normal');
									$self->{tk_force_crop_lbl_b}->configure( -state=>'normal');
									$self->{tk_force_crop_entry_height}->configure( -state=>'normal');
									# $self->{forced_crop_width} = 0;
									# $self->{forced_crop_height} = 0;
								}
								else{
									$self->{tk_force_crop_lbl_a}->configure( -state=>'disabled');
									$self->{tk_force_crop_entry_width}->configure( -state=>'disabled');
									$self->{tk_force_crop_lbl_b}->configure( -state=>'disabled');
									$self->{tk_force_crop_entry_height}->configure( -state=>'disabled');
									# $self->{forced_crop_width} = 0;
									# $self->{forced_crop_height} = 0;
								}					
						},
        )->pack(-side => 'left');
                  
    $fr6a->Label( -text => "enable image cropping (around given center)",
        )->pack(-side => 'left');
		
	my $fr6b = $fr6->Frame(
        )->pack(-side=>'top', -pady=>5, -fill=>'x');
		
	$self->{tk_force_crop_lbl_a} = $fr6b->Label(
					-text => "force output size in pixel (width x height) to",
					-state => $self->{enable_cropping} ? 'normal' : 'disabled',
        )->pack(-side => 'left');

	$self->{tk_force_crop_entry_width} = $fr6b->Entry(	
					-width => 5,
					-borderwidth => 4, 
					-textvariable => \$self->{forced_crop_width},
					-state => $self->{enable_cropping} ? 'normal' : 'disabled',
        )->pack(-side => 'left',-padx=>5);
		
	$self->{tk_force_crop_lbl_b} = $fr6b->Label(
					-text => " x ",
					-state => $self->{enable_cropping} ? 'normal' : 'disabled',
        )->pack(-side => 'left');
	
	$self->{tk_force_crop_entry_height} = $fr6b->Entry(	
					-width => 5,
					-borderwidth => 4, 
					-textvariable => \$self->{forced_crop_height},
					-state => $self->{enable_cropping} ? 'normal' : 'disabled',
        )->pack(-side => 'left',-padx=>5);
}
################################################################################
sub init_original_photo {
    my $self = shift;
    unless ( $self->{files}->[ $self->{fileindex} ] and -e $self->{files}->[ $self->{fileindex} ]){
        print "\nNO FILE TO LOAD..\n";
        $self->{fileindex} = 0;
        @{$self->{files}} = ();
        $self->fill_description_label();
        $self->{photowindow}->withdraw() if $self->{photowindow};
        return 0;
    }
    $self->cleanup();
    print "\nLOADING FILE ",$self->{fileindex} + 1," of ", scalar @{$self->{files}},"\n".
            "file path    : $self->{files}->[ $self->{fileindex} ]\n";
    $self->{tk_description_label} = "file ".($self->{fileindex} + 1)." of ".( scalar @{$self->{files}} ).
                                    ": $self->{files}->[ $self->{fileindex} ]";
    # USE THIS:
    # $tk_ph_image->configure( -file => undef,
                            # -data => MIME::Base64::encode($resized->jpeg())
    # );
    # # configure the Tk::Label to use the Tk::Photo as image
    # $photo_label->configure(-image => $tk_ph_image );
  
    $self->check_photowin();
    $self->{gdorig}->delete if $self->{gdorig} and $self->{gdorig}->blank;#??????????? wrong????????????
    $self->{gdorig} = get_ph_data( $self->{files}->[ $self->{fileindex} ] );
    die unless $self->{gdorig};
    print "original size: ",( join ' x ', $self->{gdorig}->width, $self->{gdorig}->height),"\n";
    
    $self->draw_preview();

}
################################################################################
sub check_photowin{
    my $self = shift;
    # window does not Exists
    if (! Exists( $self->{photowindow} )) {
        $self->{photowindow} =  $self->{mainwindow}->Toplevel();
        # (https://metacpan.org/pod/distribution/Tk/pod/Widget.pod)
		# If you need the true width immediately after creating a widget, invoke update to force the geometry manager to arrange it, 
		# or use $widget->reqwidth to get the window's requested width instead of its actual width.
		$self->{mainwindow}->update();
		
		# set photo windows to the right side of mainwindow
        my ($mwx,$mwy,$mwpx,$mwpy) = split /x|\+/, $self->{mainwindow}->geometry;
		$self->{photowindow}->geometry("0x0+".( $mwx + $mwpx + 10 )."+".$mwpy);
        $self->{photowindow}->title("left click to set P1, right click for P2, central click to rotate");
        $self->{canvas} = $self->{photowindow}->Canvas;
        
		# BINDINGS 
        $self->{canvas}->CanvasBind('<Button-1>', sub{ $self->set_rotation_points('1', Ev('x'), Ev('y')) }  );
        $self->{canvas}->CanvasBind('<Button-3>', sub{ $self->set_rotation_points('2', Ev('x'), Ev('y')) }  );
        $self->{canvas}->CanvasBind('<Button-2>',        sub{ $self->transform_image() } );
        $self->{photowindow}->bind('<KeyRelease-space>', sub{ $self->transform_image() } );
        $self->{photowindow}->bind('<KeyRelease-p>', sub{   
                                                            return if $self->{fileindex} == 0;
                                                            $self->{fileindex}--;
                                                            $self->init_original_photo() 
                                                        } 
        );
        $self->{photowindow}->bind('<KeyRelease-n>', sub{ 
                                                            return if $self->{fileindex} == scalar @{ $self->{files} };
                                                            $self->{fileindex}++;
                                                            $self->init_original_photo() 
                                                        } 
        );
        
		$self->{photowindow}->bind('<Control-KeyPress-d>', sub{ 
                                                            return unless $self->{devdebug};
                                                            $Data::Dumper::Quotekeys = 0;
															$Data::Dumper::Sortkeys = sub{[ qw(   
																		ratio p1 p2 center ocenter vertex hypotenuse 
																		ohypotenuse rotation directory  
																		out_directory glob files fileindex 
																		out_file_prefix out_file_number out_original_name 
																		debug devdebug enable_rotation force_line_direction 
																		enable_resize forced_size forced_size_unit 
																		resize_ratio enable_mm enable_cropping 
																		forced_crop_width forced_crop_height														
															)]};
															$Data::Dumper::Varname = 'JPEGROTATOR';
															print "#\n# dumping part of the current object\n#\n",Dumper $self;
                                                        } 
        );
        $self->{canvas}->pack(-expand => 1, -fill => 'both');
    }
    # window Exists
    else {
        # Not all window managers appear to know how to handle windows that are mapped in the withdrawn state. 
        # Note: it sometimes seems to be necessary to withdraw a window and then re-map it (e.g. with deiconify) 
        # to get some window managers to pay attention to changes in window attributes such as group.
        $self->{photowindow}->deiconify( ) ;#if $self->{photowindow}->state() eq 'iconic';
        $self->{photowindow}->raise( ) if $self->{photowindow}->state() eq 'withdrawn';
        # force resizing?
        #$self->{photowindow}->geometry("");
    }    
}
################################################################################
sub draw_preview{
    my $self = shift;
    $self->{tk_photo}->delete if $self->{tk_photo} and $self->{tk_photo}->blank;
    my $small_w = int( $self->{gdorig}->width * $self->{ratio} );
    my $small_h = int( $self->{gdorig}->height * $self->{ratio} );
    $self->{photowindow}->geometry( $small_w."x".$small_h);
    print "preview size : $small_w x $small_h\n" if $self->{debug};
    # create the resized but still empty GD image
    $self->{gdres} = GD::Image->new($small_w,$small_h);
    # copy from source into resized on
    $self->{gdres}->copyResampled(
                $self->{gdorig},
                0,0,0,0,
                $small_w,
                $small_h,
                $self->{gdorig}->width,
                $self->{gdorig}->height);

#$self->{canvas} = $self->{photowindow}->Canvas;
    $self->{tk_photo} = $self->{canvas}->Photo(-format => 'jpeg',-data => MIME::Base64::encode( $self->{gdres}->jpeg() )) or die $!;
    $self->{canvas}->createImage( $small_w/2,$small_h/2, #-file => undef,
                         -image => $self->{tk_photo} );
    
    # force resizing?
    #$self->{photowindow}->geometry("");
    $self->{photowindow}->focus();
    
}
################################################################################
sub set_rotation_points {
    my ( $self,  $point, $x, $y) = @_;
    # skip if only P2
	if ( $point == 2 ) { 
        return unless defined $self->{p1}->[0] and defined $self->{p1}->[1];
    }
    # P1
    if ( $point == 1 ){
        # clean elements
        $self->{canvas}->delete( $self->{tk_line}   ) and undef $self->{tk_line} if $self->{tk_line};
        $self->{canvas}->delete( $self->{tk_circle} ) and undef $self->{tk_line} if $self->{tk_circle};
        $self->{canvas}->delete( $self->{tk_vertex} ) and undef $self->{tk_vertex} if $self->{tk_vertex};
        # set it
        $self->{p1} = [$Tk::event->x, $Tk::event->y];
        return;
    }
    # P2
    else{ $self->{p2} = [$Tk::event->x, $Tk::event->y];  }

    # FORCE P2 if required
    if ( $self->{force_line_direction} and $self->{force_line_direction} eq 'horizontal' ){
        $self->{p2}->[1] = $self->{p1}->[1];
    }
    if ( $self->{force_line_direction} and $self->{force_line_direction} eq 'vertical' ){
        $self->{p2}->[0] = $self->{p1}->[0];
    }

    # if both P1 and P2 are set draw the line and points
    print "\nSETTING ROTATION POINTS:\n" if $self->{debug};

    # CENTER
    my $center;
    # P1 more on the left than P2
    if ( $self->{p2}->[0] > $self->{p1}->[0] ){
        $center->[0] = $self->{p1}->[0] + int( ($self->{p2}->[0] - $self->{p1}->[0]) / 2 );
        print "P1 more on the left than P2\n" if $self->{debug};
    }
    # P1 more on the right than P2
    else{
        $center->[0] = $self->{p1}->[0] - int( ($self->{p1}->[0] - $self->{p2}->[0]) / 2 );
        print "P1 more on the right than P2\n" if $self->{debug};
    }
    # P1 higher than P2 (Y coordinates are inverted in Tk and GD too)
    if ( $self->{p1}->[1] < $self->{p2}->[1] ){
        $center->[1] = $self->{p1}->[1] - int( ($self->{p1}->[1] - $self->{p2}->[1]) / 2 );
        print "P1 higher than P2\n" if $self->{debug};
    }
    # P1 lower than P2
    else{
        $center->[1] = $self->{p1}->[1] + int( ($self->{p2}->[1] - $self->{p1}->[1]) / 2 );
        print "P1 lower than P2\n" if $self->{debug};
    }
    
    
    
    $self->{tk_line} = $self->{canvas}->createLine(
                                    $self->{p1}->[0],$self->{p1}->[1], 
                                    $self->{p2}->[0],$self->{p2}->[1], 
                                    -arrow => "last", -fill => 'red', -width => 3
    ); 
    $self->{tk_circle} = $self->{canvas}->createOval(
                                    $center->[0]+3,$center->[1]+3,
                                    $center->[0]-3,$center->[1]-3, 
                                    -fill => 'yellow', 
    ); 

    
    # VERTEX
    # rotation in GD is always COUNTER clockwise
    my $adjacent;
    my $opposite;
    my $hypotenuse;
    # P1 and P2 are at the same X,Y
    if (
        $self->{p1}->[0] == $self->{p2}->[0]
        and
        $self->{p1}->[1] == $self->{p2}->[1]
        )
    {
        print "P1 and P2 are at same coordinates!\n" if $self->{debug};
        $self->{rotation} = 0;  
    }
    # P1 and P2 are at the same height Y
    # AND
    # P1 more on the left than P2
    elsif(
            $self->{p1}->[1] == $self->{p2}->[1]
            and
            $self->{p1}->[0] < $self->{p2}->[0]
        )
    {
        print "P1 and P2 have the same Y and P1 is more on the left than P2. No rotation needed\n" if $self->{debug};
        $self->{rotation} = 0;
    }
    # P1 and P2 are at the same height Y
    # AND
    # P1 more on the right than P2
    elsif(
            $self->{p1}->[1] == $self->{p2}->[1]
            and
            $self->{p1}->[0] > $self->{p2}->[0]
        )
    {
        print "P1 and P2 have the same Y and P1 is more on the right than P2\n" if $self->{debug};
        $self->{rotation} = 180;
    }
    
    # P1 and P2 are at the same width X
    # AND
    # P1 higher then P2
    elsif(
            $self->{p1}->[0] == $self->{p2}->[0]
            and
            $self->{p1}->[1] < $self->{p2}->[1]
        )
    {
        print "P1 and P2 have the same X and P1 is higher than P2\n" if $self->{debug};
        $self->{rotation} = 90;
    }
    # P1 and P2 are at the same width X
    # AND
    # P1 lower then P2
    elsif(
            $self->{p1}->[0] == $self->{p2}->[0]
            and
            $self->{p1}->[1] > $self->{p2}->[1]
        )
    {
        print "P1 and P2 have the same X and P1 is lower than P2\n" if $self->{debug};
        $self->{rotation} = 270;
    }
    # P1 more on the left than P2 
    # AND
    # P1 higher than P2 (Y coordinates are inverted in Tk and GD too)
    elsif   ( 
            $self->{p2}->[0] > $self->{p1}->[0]
            and
            $self->{p1}->[1] < $self->{p2}->[1]
        )
    {
        $self->{vertex}[0] = $self->{p1}->[0];
        $self->{vertex}[1] = $self->{p2}->[1];
        $adjacent = $self->{p2}->[0] - $self->{p1}->[0];
        $opposite = $self->{p2}->[1] - $self->{p1}->[1];
        $self->{rotation} = (atan2($opposite,$adjacent)/$pi*180);
        
    }
    # P1 more on the left than P2 
    # AND
    # P1 lower than P2 (Y coordinates are inverted in Tk and GD too)
    elsif   ( 
            $self->{p1}->[0] <= $self->{p2}->[0]
            and
            $self->{p1}->[1] >= $self->{p2}->[1]
        )
    {
        $self->{vertex}[0] = $self->{p2}->[0];
        $self->{vertex}[1] = $self->{p1}->[1];
        $adjacent = $self->{p2}->[0] - $self->{p1}->[0];
        $opposite = $self->{p1}->[1] - $self->{p2}->[1];
        $self->{rotation} = 360 - (atan2($opposite,$adjacent)/$pi*180);         
    }
    # P1 more on the right than P2
    # AND
    # P1 lower than P2
    elsif(
        $self->{p1}->[0] >= $self->{p2}->[0]
        and
        $self->{p1}->[1] >= $self->{p2}->[1]
    ) 
    
    {
        $self->{vertex}[0] = $self->{p2}->[0];
        $self->{vertex}[1] = $self->{p1}->[1];
        $adjacent = $self->{p1}->[0] - $self->{p2}->[0];
        $opposite = $self->{p1}->[1] - $self->{p2}->[1];
        $self->{rotation} = 180 + (atan2($opposite,$adjacent)/$pi*180);
        
    }
    # P1 more on the right than P2
    # AND                               
    # P1 higher than P2
    elsif(
        $self->{p1}->[0] >= $self->{p2}->[0]
        and
        $self->{p1}->[1] <= $self->{p2}->[1]
    ) 
    
    {
        $self->{vertex}[0] = $self->{p1}->[0];
        $self->{vertex}[1] = $self->{p2}->[1];
        $opposite = $self->{p1}->[0] - $self->{p2}->[0];
        $adjacent = $self->{p2}->[1] - $self->{p1}->[1];
        $self->{rotation} = 90 + (atan2($opposite,$adjacent)/$pi*180);
        
    }
    else{ die "Weird coordinates! P1: $self->{p1}->[0],$self->{p1}->[1] P2: $self->{p2}->[1],$self->{p2}->[1]."}
    
    
    # SET HYPOTHENUSE
    if ( defined $opposite and defined $adjacent ){
        $hypotenuse = sqrt( $opposite**2 + $adjacent**2 );
    }
    # no triangle: horizontal
    elsif ( $self->{p2}->[1] == $self->{p1}->[1] ) {
        $hypotenuse =   ( $self->{p2}->[0] > $self->{p1}->[0] ? $self->{p2}->[0] : $self->{p1}->[0] ) 
                        - 
                        ( $self->{p2}->[0] > $self->{p1}->[0] ? $self->{p1}->[0] : $self->{p2}->[0] );
    }
    # no triangle: vertical
    elsif ( $self->{p2}->[0] == $self->{p1}->[0] ) {
        $hypotenuse =   ( $self->{p2}->[1] > $self->{p1}->[1] ? $self->{p2}->[1] : $self->{p1}->[1] ) 
                        - 
                        ( $self->{p2}->[1] > $self->{p1}->[1] ? $self->{p1}->[1] : $self->{p2}->[1] );
    } 
    else{ die "Dunno how to set hypotenuse or P1 P2 distance!" }

    #print "--->HYPOTHENUSE: $hypotenuse\n";    

    # set global center
    $self->{center} = $center;
    
    # CALCULATE THE CENTER IN THE ORIGINAL IMAGE
    # X
    $self->{ocenter}->[0] =  $self->{center}->[0] * $self->{gdorig}->width() / ($self->{gdorig}->width() * $self->{ratio} );
    # Y
    $self->{ocenter}->[1] =  $self->{center}->[1] * $self->{gdorig}->height() / ($self->{gdorig}->height() * $self->{ratio} );
    # SET HYPOTHENUSE
    $self->{hypotenuse} = $hypotenuse;
    $self->{ohypotenuse} = $hypotenuse / $self->{ratio} ;
    
    # DEBUG OUTPUT
    if ( $self->{debug} ){
        print   "P1         : $self->{p1}->[0] - $self->{p1}->[1]\n",
                "P2         : $self->{p2}->[0] - $self->{p2}->[1]\n",
                "center     : $center->[0] - $center->[1]\n";
        if ( defined $hypotenuse and defined $self->{vertex}[0] ){
            print   "vertex     : $self->{vertex}[0] - $self->{vertex}[1]\n",
                    "hypotenuse : $hypotenuse\n";
            print   "angle      : ",(atan2($opposite,$adjacent)/$pi*180),"\n" if defined $opposite and defined $adjacent;
            $self->{tk_vertex} = $self->{canvas}->createOval(
                                    $self->{vertex}->[0]+3,$self->{vertex}->[1]+3,
                                    $self->{vertex}->[0]-3,$self->{vertex}->[1]-3, 
                                    -fill => 'yellow', 
            );
        }
        print   "rotation   : $self->{rotation}\n";
        print "choosen center in the original image: $self->{ocenter}->[0] - $self->{ocenter}->[1]\n";
        if ( $self->{devdebug} ){
            my $red = $self->{gdorig}->colorAllocate(255,0,0);
            my $temp_gdorig = $self->{gdorig}->clone();
            $temp_gdorig->filledEllipse($self->{ocenter}->[0],$self->{ocenter}->[1],5,5,$red);  
            write_image( $temp_gdorig, 'gd_02_choosen_center.jpg' );
            
        }
    }

	

	
}
################################################################################
sub crop_centered{
    my $self = shift;
    # CROPPING RECENTERED let the middle point between P1 and P2 be the
    # new center of the image. So..
    
    # FIRST calculate the coordinates of the rectangle with as center
    # the middle point between P1 and P2. For convenience width and height too.
    
    # X min
    my $src_min_x = $self->{ocenter}->[0]               # x of the center in the original image
                        -                               # minus
                        ($self->{gdorig}->width - $self->{ocenter}->[0]);   # center distance from the max X
    # set to 0 if we went outside the image borders
    $src_min_x = 0 if $src_min_x < 0;
    
    # X max
    my $src_max_x = $self->{ocenter}->[0]               # x of the center in the original image
                        +                               # minus
                        ($self->{gdorig}->width - $self->{ocenter}->[0]);   # center distance from the max X
    # set to 0 if we went outside the image borders
    $src_max_x = $self->{gdorig}->width() if $src_max_x > $self->{gdorig}->width();
    
    # ADJUST the value to the minimum (if we were outside of the image the center is no more in the middle)
    if ( ( $self->{ocenter}->[0] - $src_min_x ) >  ( $src_max_x - $self->{ocenter}->[0] ) ){
        $src_min_x = $self->{ocenter}->[0] - ( $src_max_x - $self->{ocenter}->[0] ); 
    }
    if ( ( $self->{ocenter}->[0] - $src_min_x ) <  ( $src_max_x - $self->{ocenter}->[0] ) ){
        $src_max_x = $self->{ocenter}->[0] + ( $self->{ocenter}->[0] - $src_min_x ); 
    }   
    
    
    # WIDTH
    my $src_width = $src_max_x - $src_min_x;
    
    # Y min
    my $src_min_y = $self->{ocenter}->[1]               # y of the center in the original image
                    -                                   # minus
                    ($self->{gdorig}->height - $self->{ocenter}->[1]);  # center distance from max Y
    # set to 0 if we went outside the image borders
    $src_min_y = 0 if $src_min_y < 0;
    
    # Y max
    my $src_max_y = $self->{ocenter}->[1]               # y of the center in the original image
                    +                                   # plus
                    ($self->{gdorig}->height - $self->{ocenter}->[1]);  # center distance from max Y
    # set to height if we went outside the image borders
    $src_max_y = $self->{gdorig}->height() if $src_max_y > $self->{gdorig}->height();
    
    # ADJUST the value to the minimum (if we were outside of the image the center is no more in the middle)
    if ( ( $self->{ocenter}->[1] - $src_min_y ) >  ( $src_max_y - $self->{ocenter}->[1] ) ){
        $src_min_y = $self->{ocenter}->[1] - ( $src_max_y - $self->{ocenter}->[1] ); 
    }
    if ( ( $self->{ocenter}->[1] - $src_min_y ) <  ( $src_max_y - $self->{ocenter}->[1] ) ){
        $src_max_y = $self->{ocenter}->[1] + ( $self->{ocenter}->[1] - $src_min_y ); 
    }       

    # HEIGHT
    my $src_height = $src_max_y - $src_min_y;
    
    # SECOND copy using the above points into a new image sized as
    # the original one.
    # GD wants coordinates of the upper left corner of the SRC and DST to copy
    # and paste. Then the width and height
    my $gd_off_center = GD::Image->new($self->{gdorig}->width,$self->{gdorig}->height);
    
    $gd_off_center->copy(
            $self->{gdorig},                                # srcX
            ($self->{gdorig}->width() - $src_width) / 2,    # destX
            ($self->{gdorig}->height() - $src_height) / 2,  # destY
            $src_min_x,     # srcX - X of upper left corner of a rectangle in the source image
            $src_min_y,     # srcY - Y of upper left corner of a rectangle in the source image
            $src_width,     # width of the region to copy
            $src_height,    # height of the region to copy  
    );
    
    
    if ( $self->{debug} ){
        print "\nCROPPING AT:\n",
                "top left corner    : $src_min_x - $src_min_y\n",
                "buttom right corner: $src_max_x - $src_max_y\n",
                "width              : $src_width\n",
                "height             : $src_height\n";
        # dont mess with images
        my $temp_gdorig = $self->{gdorig}->clone();     
        my $red = $self->{gdorig}->colorAllocate(255,0,0);
        $temp_gdorig->filledEllipse($self->{ocenter}->[0],$self->{ocenter}->[1],20,20,$red);
        # left vertical
        $temp_gdorig->line(
                                    $src_min_x,$src_min_y, 
                                    $src_min_x,$src_max_y, 
                                    $red
        );
        # right vertical
        $temp_gdorig->line(
                                    $src_max_x,$src_min_y, 
                                    $src_max_x,$src_max_y, 
                                    $red
        );
        # upper horizonatal
        $temp_gdorig->line(
                                    $src_min_x,$src_min_y, 
                                    $src_max_x,$src_min_y, 
                                    $red
        );
        # lower horizonatal
        $temp_gdorig->line(
                                    $src_min_x,$src_max_y, 
                                    $src_max_x,$src_max_y, 
                                    $red
        );
        write_image( $temp_gdorig, 'gd_03_cropping_points.jpg' ) if $self->{devdebug};        
    }
    
    # ADJUST THE CENTER AGAIN!!
    $self->{ocenter} = [
                        int($src_width/2) + (($self->{gdorig}->width() - $src_width) / 2)    , 
                        int($src_height/2) + (($self->{gdorig}->height() - $src_height) / 2)
    ];
    
    if ( $self->{devdebug} ){
        my $temp_offcenter = $gd_off_center->clone();
        my $red = $self->{gdorig}->colorAllocate(255,0,0);
        $temp_offcenter->filledEllipse($self->{ocenter}->[0],$self->{ocenter}->[1],20,20,$red);
        write_image( $temp_offcenter, 'gd_04_offcenter.jpg' );
    }

    $self->{gdorig} = $gd_off_center;
}
################################################################################
sub rotate_original{
    my $self = shift;
    unless ( $self->{p1} and $self->{p2} ){ return 0 } ###????
    # CUT
    $self->crop_centered();
    # CUT END
    
    # temporary GD image needed (dunno why)
    # copyRotateInterpolated is OK but create an image with different dimensions
    # $self->{gdres}=$self->{gdres}->copyRotateInterpolated( $self->{rotation}, 0 );
    my $off_center_rotated = GD::Image->new($self->{gdorig}->width,$self->{gdorig}->height);
        
    $off_center_rotated ->copyRotated(
    
                            $self->{gdorig} ,           # source
                            $self->{gdorig}->width / 2, # X center of the destination image
                            $self->{gdorig}->height / 2,# Y center of the destination image
                            0,                          # X specify the upper left corner of a rectangle in the source image
                            0,                          # Y specify the upper left corner of a rectangle in the source image
                            $self->{gdorig}->width,     # final width
                            $self->{gdorig}->height,    # final height
                            $self->{rotation}           # rotation angle COUNTER clockwise in degrees
    );
    
    print "center in the original image: $self->{ocenter}->[0] $self->{ocenter}->[1]\n".
            "preview CENTER: $self->{center}->[0] $self->{center}->[1]\n";
    
    $self->{gdorig} = $off_center_rotated;
    
    $self->{tk_photo}->configure( -format => 'jpeg',-data => MIME::Base64::encode( $self->{gdres}->jpeg()) );

    write_image( $self->{gdorig}, 'gd_05_after_rotation.jpg' ) if $self->{devdebug};
   
}
################################################################################
sub resize_original{
    my $self = shift;
	# CUSTOM RESIZING TO STREACH OR REDUCE HYPOTHENUSE TO A FIXED LENGHT
	# pixels                 maxpixel  mm   mm

	 my $name = $self->{mainwindow}->screen;
	 my $height = $self->{mainwindow}->screenheight; 
	 my $width = $self->{mainwindow}->screenwidth; 
	 my $scaling = $self->{mainwindow}->scaling;
	 my $heightmm = $self->{mainwindow}->screenmmheight; 
	 my $widthmm = $self->{mainwindow}->screenmmwidth;
	 if ( $self->{devdebug} ){
		print "name $name pixel width $width pixel height $height scaling $scaling mm width $widthmm  mm height $heightmm\n";
	}

	# RATIO 
	$self->{resize_ratio} =  $self->{forced_size} / $self->{ohypotenuse};
	
	# CHANGE CENTER X AND Y
	$self->{ocenter}->[0] = $self->{ocenter}->[0] * $self->{resize_ratio};
	$self->{ocenter}->[1] = $self->{ocenter}->[1] * $self->{resize_ratio};

	my $gdforcedsized = GD::Image->new(  $self->{gdorig}->width * $self->{resize_ratio} ,  $self->{gdorig}->height * $self->{resize_ratio} );
	# copy from source into resized on
	$gdforcedsized->copyResampled(
				$self->{gdorig}, # now is already rotated and recentered 
				0,0,0,0,
				int($self->{gdorig}->width * $self->{resize_ratio}),
				int($self->{gdorig}->height * $self->{resize_ratio}),
				$self->{gdorig}->width,
				$self->{gdorig}->height,
	);

	if ( $self->{debug}){
		print "\nCUSTOM RESEIZING:\n",
			"original hypotenuse: $self->{ohypotenuse}\n",
			"target hypotenuse  : ",$self->{ohypotenuse}* $self->{resize_ratio},"\n",
			"original width     : ",int($self->{gdorig}->width * $self->{resize_ratio}),"\n",
			"resized to         : ",int($self->{gdorig}->height * $self->{resize_ratio}),"\n",
			"using ratio        : $self->{resize_ratio}\n";
		
	}
	if ( $self->{devdebug} ){
		my $temp_gdorig = $gdforcedsized->clone();
		my $red = $temp_gdorig->colorAllocate(255,0,0);
		# $self->{gdorig}->filledEllipse($src_min_x,$src_min_y,20,20,$red);
		# $self->{gdorig}->filledEllipse($src_max_x,$src_max_y,20,20,$red);
		$temp_gdorig->filledEllipse($self->{ocenter}->[0],$self->{ocenter}->[1],40,40,$red);
		write_image( $temp_gdorig, 'gd_06_stretched.jpg' );   
	}
	
	$self->{gdorig} = $gdforcedsized;
	
}
################################################################################
sub crop_original{
	my $self = shift;
	# CROPPING to a a fixed size
	my ($forced_w, $forced_h) = ($self->{ forced_crop_width}, $self->{forced_crop_height} );
	my $gdcropped = GD::Image->new( $forced_w, $forced_h );
	my $topleft_x = int($self->{ocenter}->[0] - ( $forced_w / 2 ));
	my $topleft_y = int($self->{ocenter}->[1] - ( $forced_h / 2 ));
	$gdcropped->copy(
				#$gdforcedsized, # now is already rotated and recentered and streached
				$self->{gdorig}, # now is already rotated and recentered and streached
				0,              # dst X
				0,              # dst Y
				$topleft_x,     # src wanted X
				$topleft_y,     # src wanted Y
				$forced_w,      # src width
				$forced_h,      # src height
	);

	print "center of the original image was at: $self->{ocenter}->[0] - $self->{ocenter}->[1]\n" if $self->{debug};
	$self->{ocenter}->[0] = int($self->{ocenter}->[0] * $self->{resize_ratio} ? $self->{resize_ratio} : 1 );
	$self->{ocenter}->[1] = int($self->{ocenter}->[1] * $self->{resize_ratio} ? $self->{resize_ratio} : 1 );
	print "center of the original image is at : $self->{ocenter}->[0] - $self->{ocenter}->[1]\n" if $self->{debug};

	if ( $self->{debug} ){
		print "\nCUSTOM CROPPING AFTER STRETCHING:\n",
						"top left X         : $topleft_x\n",
						"top left Y         : $topleft_y\n",
						"forced width       : $forced_w\n",
						"forced height      : $forced_h\n";
	}

	write_image( $gdcropped, 'gd_07_cropped_after_stretching.jpg' ) if $self->{devdebug};

	$self->{gdorig} = $gdcropped;

}
################################################################################
sub transform_image{
    my $self = shift;
    
	$self->rotate_original() if $self->{enable_rotation};   	
	
	$self->resize_original() if $self->{enable_resize};
	
	$self->crop_original() if $self->{enable_cropping};
	
	if ( $self->{enable_rotation} or $self->{enable_resize} or $self->{enable_cropping} ){
		# SAVE the final result
		my (undef, undef, $orig_filename) =
					   File::Spec->splitpath( $self->{files}->[$self->{fileindex}] );
					   
		my $filename = File::Spec->catfile( $self->{out_directory}, 
			($self->{out_file_prefix} ? $self->{out_file_prefix} : '').
			($self->{out_file_number} ? ( sprintf '%03d',$self->{out_file_number} ) : '').
			($self->{out_original_name} ? $orig_filename : '.jpg')		
		);
		
		write_image( $self->{gdorig}, $filename );
		
		$self->{out_file_number}++ if defined $self->{out_file_number};	
	}
	else {
		print "Nothing to do. Skipping to next image..\n";
	}
	$self->{fileindex}++;
	$self->init_original_photo();
}
################################################################################
sub cleanup {
    my $self = shift;
    # avoid Photo memory leak
    if ( $self->{tk_photo} ){
        $self->{tk_photo}->delete if $self->{tk_photo}->blank;
    }
    # reset other object properties
    map { $self->{$_} = undef }
        qw( gdorig gdres tk_line tk_circle tk_vertex p1 p2p center vertex ocenter rotation hypotenuse ohypotenuse );    
}
################################################################################
# helper subs
################################################################################
sub get_ph_data {
   my $file = shift;
   return unless -e $file;
   # load original pic file in GD using general purpose method
   my $gd_image = GD::Image->new($file);
   # if not defined try newFromJpeg
   unless ($gd_image){
      warn"\tGD image not defined for [$file]".
              " retrying assuming it is JPEG";
      $gd_image = GD::Image->newFromJpeg($file);
   }
   # if it is still undefined...
   unless ($gd_image){
      warn "\tGD image UNAVAILABLE for [$file] $!\n";
            return undef;
   }
   #print "original size: ",( join ' x ', $gd_image->width, $gd_image->height),"\n";
  
   return $gd_image;
}
################################################################################
sub help_me{
    print "#\n#\n# Documentation of $0\n#\n#\n";
    print `perldoc $0`;
}
################################################################################
sub write_image{
    my ($gd, $filename) = @_;
    open my $out, '>', $filename or die $!;
    binmode $out;
    print $out $gd->jpeg();
    print "IMAGE WRITTEN: $filename\n";
}

__DATA__
=head1 NAME

Jpg custom rotation, crop and resize

=head1 KEY BINDINGS

Preview Window:

    Button-1    (left click)    set point1
    Button-3    (right click)   set point2
    space                       modify the photo and loads the next one
    Button-2    (middle click)  modify the photo and loads the next one
    p                           reload the previous photo
    n                           skip the current photo and load the next one


=head1 DEBUG

Beside normal verbose output activated by C<--debug> command line switch or by the dedicated check in the GUI, there is also a
C<--devdebug> switch that add more verbose output but also writes an image at each stage of the prcessing with points and lines
in the relevant positions. These images will have fixed names and will be ovewritten when a new jpeg is processed.
While C<--devdebug> is active the preview window has another binding: C< CRTL + d> which dumps on the 
screen the relevant part of the object.
	
	
=head1 BUGS AND LIMITATIONS

Resizing using millimeters instead of pixel is disabled by because Tk::Widget->screenmmheight is not behaving correctly everywhere.
If you are sure this measurement is working correctly in your system you can enable it via the command line switch C<--enablemm>



