# bash script with embedded perl script
# Author: Adam Richards
date
perl << 'EOT'
my $cmd="free -m";
my @output = `$cmd`;    
chomp @output;
=for comment
foreach my $line (@output)
{
    print "$line\n";
}
=cut
my($data)= "$output[1]\n";
my($junk, $total, $used, $free, $shared, $buffers, $cached) = unpack("A4A14A11A11A11A11A11",$data);
my $result = ($free+$buffers+$cached)/$total;
my $host = `hostname`;
chomp $host;
print sprintf("%s:Free Memory %%:  %.2f\n",$host,100*$result);
EOT
