#!/usr/bin/perl -w
use 5.030;
use Path::Tiny;


## turning things to Path::Tiny
# decode paths

my $path1 = Path::Tiny->cwd;

my %vars = (

  to_images    => path( $path1, "images" ),
  eng_captions => path( $path1, "captions" ),

);

my $rvars = \%vars;

$DB::single = 1;    # put a break point here
## this function is to be debugged using the perl debugger
my $return2 = make_initial_captions($rvars);
say "return2 is $return2";

sub make_initial_captions {
 
  use Path::Tiny;


  my $rvars = shift;
  my %vars  = %$rvars;

  my $image_path   = $vars{"to_images"};
  my $caption_path = $vars{"eng_captions"};

  my $counter = 1;
  my $iter    = $image_path->iterator;
  while ( my $next = $iter->() ) {

    my $suffix = sprintf( "%03d", $counter );
    my $text   = $next;
    my $base = $next->basename;
    my ($ext) = $base =~ /(\.[^.]+)$/;

    # rename image file
    my $new_image = "image" . "$counter" . "$ext";
    my $move_path = path( $image_path, $new_image );

    #say "move path is $move_path";
    path($next)->move($move_path);

    # create caption file
    my $new_caption = "caption" . "$counter" . ".txt";
    my $path_caps   = path( $caption_path, $new_caption );

    #say "path caps is $path_caps";
    path($path_caps)->touch;
    $DB::single = 1;    # put a break point here
    path($path_caps)->spew_utf8($text);
 
    $counter++;
  }
  return "nothing yet";
}

__END__ 

