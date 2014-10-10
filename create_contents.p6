# Perl 6 program to create a contents.pod from all pod files in the directory

my regex hs { ^\=head };
my regex head { ^ \=head 
  $<level>=(\d) 
  $<label>=(.*?) $$
  $<body>=( .* ) [\n]* <!before \= | . >  
};
my $str = '';
my $lvl;
my @opt;

@opt.push: "=begin pod", "=encoding utf8";

for <. S32-setting-library>.map( { IO::Path.new($_).contents } ).grep( { m/ .*\.pod $$ / and !m/ contents\.pod / } ).sort -> $f {
  $f.basename.say;
  for open($f).lines { 
	if m/ <?hs> / {
	  if $str ~~ m/ <head> / {
		$str = "$<head><body>";
		$lvl = +$<head><level>;
		given $<head><label> {
		  when m:i / TITLE / { 
			@opt.push: '' if +@opt; 
			@opt.push: "=head1 " ~ trim($str) ; 
			succeed 
		  }
		  when m:i / Document " " Description / { 
			@opt.push: trim($str) ; 
			@opt.push: "Chapter contents:" ;
			succeed 
		  }
		  when m:i / AUTHORS | VERSION / { succeed }
		  default { @opt.push: ("\t" x $lvl) ~ .trim }
		}
		$str = '';
	  } else { 
		$str =''
	  }
	}
	$str ~= "$_\n"
  }
}

@opt.push: '', "=end pod";

spurt('contents.pod', join("\n",@opt) );
