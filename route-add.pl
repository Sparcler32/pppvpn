#!/usr/bin/perl
# route-add.pl version 0.0.1
# adds routes across the pppssh vpn, called by client when the vpn is brought up
#
use strict;

my $ppp_link;

if (chk_cfg()) { 
        $ppp_link = find_ppp_link();

        if ($ppp_link =~ m/NULL/) {
                print "No PPP connections, Exiting\n";
        } else {
                if (read_cfg($ppp_link)) {
                        print "Routes installed on interface ";
                        print "$ppp_link\n";
                } else {
                        print "Not ready, exiting\n";
                }
        }
} else {
        print "Route instalation not configured, Exiting\n";
}

sub find_ppp_link {
        my $link_cmd = "ip link list";
        my $line;
        my $index;
        my $ppp_interface = "NULL";
        my @line_data;

        open LINK_CMD, "$link_cmd |";
        foreach $line (<LINK_CMD>) {
                chomp $line;

                if ($line =~ m/ppp/) {
                        @line_data = split ":", $line;

                        foreach $index (@line_data) {
                                if ($index =~ m/ppp[0-9][0-9]*/) {
                                        $index = trim($index);
                                        $ppp_interface = $index;
                                }
                        }
                }
        }
        close LINK_CMD;

        return $ppp_interface;
}
sub chk_cfg {
        my $cfg_file = "/usr/local/etc/pppvpn-routes.cfg";
        my $status = 0;

        if (-f $cfg_file) {
                $status = 1;
        } else {
                $status = 0;
        }

        return $status;
}
sub read_cfg {
        my $ppp_interface = shift;
        my $cfg_file = "/usr/local/etc/pppvpn-routes.cfg";
        my $line;
        my $status = 0;

        open CFG_FILE, "<", $cfg_file;
        foreach $line (<CFG_FILE>) {
                chomp $line;

                if ($line =~ m/ready:/) {
                        $status = cfg_chk_ready($line);
                } elsif ($line =~ m/^#/) {
                        # Line is a comment do nothing
                } elsif (($line =~ m/route:/) && ($status)) {
                        read_route($line, $ppp_interface);
                }
        }
        close CFG_FILE;

        return $status;
}
sub cfg_chk_ready {
        my $cfg_line = shift;
        my $status = 0;
        my ($state, $line);

        ($status, $line) = split ":", $cfg_line;

        if ($line =~ m/true/) {
                $status = 1;
        } elsif ($line =~ m/TRUE/) {
                $status = 1;
        } elsif ($line =~ m/True/) {
                $status = 1;
        } elsif ($line =~ m/false/) {
                $status = 0;
        } elsif ($line =~ m/false/) {
                $status = 0;
        } elsif ($line =~ m/false/) {
                $status = 0;
        } else {
                $status = 0;
        }

        return $status;
}
sub read_route {
        my $route_line = shift;
        my $ppp_interface = shift;
        my ($state, $line);
        my ($ip, $mask);
        my $route_cmd = "";

        ($state, $line) = split ":", $route_line;

        if ($line =~ m/\//) {
                ($ip, $mask) = split "/", $line;

                if (($mask >= 0) && ($mask <= 32)) {
                        if ($ip =~ m/[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*/) {
                                # route to install
                                chk_route($ip, $mask, $ppp_interface);
                        }
                }
        } else {
                print "Error in route\n";
        }
}
sub chk_route {
        my $route = shift;
        my $mask = shift;
        my $ppp_interface = shift;
        my $route_cmd = "ip route list";
        my $route_line;
        my $line;
        my $status = 1;

        $route_line = "$route/$mask dev $ppp_interface";
        open ROUTE_CMD, "$route_cmd $route_line|";
        foreach $line (<ROUTE_CMD>) {
                chomp $line;
                if ($line =~ m/$route\/$mask scope link/) {
                        #print "Route already in the table, not adding\n";
                        $status = 0;
                }
        }
        close ROUTE_CMD;

        if ($status == 1) {
                #print "Route not in the table adding it\n";
                #print "$route/$mask dev $ppp_interface\n";
                install_route($route, $mask, $ppp_interface);
        } else {
                #print "Route must already be in the table\n";
        }
}
sub install_route {
        my $route = shift;
        my $mask = shift;
        my $ppp_interface = shift;
        my $route_cmd;

        $route_cmd = "ip route add $route/$mask dev $ppp_interface";

        #print "$route_cmd\n";
        system "$route_cmd";
}
# string functions
sub trim {
        my $string = shift;

        $string =~ s/^\ \ *//;
        $string =~ s/\ \ *$//;

        return $string;
}
