#!/usr/bin/perl
#
use strict;

my $packet_loss;

$packet_loss = chk_tunel();

if ($packet_loss > 20) {
        print "Packet loss is greater than 20%, loss = $packet_loss\n";
        print "Restarting the tunnel\n";        
        tunel_flap();
        #add_routing(); 
} else {
        print "Packet loss is less than 20%, loss = $packet_loss\n"; 
        print "The tunnel is up and passing traffic\n";
}

ub chk_tunel {
        my $keep_ip = "192.168.x.2";
        my $keep_cmd = "ping -c5";
        my $line;
        my @ping_data;
        my $data;
        my $ploss = 100;

        open PING_CMD, "$keep_cmd $keep_ip |";
        foreach $line (<PING_CMD>) {
                chomp $line;

                if ($line =~ m/packet loss/) {
                        @ping_data = split ",", $line;

                        foreach $data (@ping_data) {
                                if ($data =~ m/packet loss/) {
                                        $data =~ s/packet loss//;
                                        $data =~ s/%//;
                                        $data = trim($data);
                                        $ploss = $data;
                                }
                        }
                }
        }
        close PING_CMD;

        return $ploss;
}
ub tunel_flap {
        my $vpn_cmd = "/usr/local/sbin/pppvpn.sh";

        print "Reseting the tunnel\n";
        system "$vpn_cmd stop";
        system "$vpn_cmd start";
        #system "/usr/local/sbin/route_add.sh";
}
sub add_routing {
        #my $route_add_cmd = "ssh -p 9352 vpn\@vps1 sudo /usr/local/sbin/route-list.pl";
        my $route_add_cmd = "ssh -p 4719 vpn\@vps2 sudo /usr/local/sbin/route-add.sh";

        print "Adding routes to the VPN\n";
        system "$route_add_cmd";
}
# string functions
sub trim {
        my $string = shift;

        $string =~ s/^\ \ *//;
        $string =~ s/\ \ *$//;

        return $string;
}
