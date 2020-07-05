#!/usr/bin/perl
#
# This script initiates a ppp-ssh vpn connection.
#
use strict;

#
# Change the below variables
#


# The host name or IP address of the primary and secondary SSH server 
# that we are connecting to
my $primary_gateway = "xxx.xxx.xxx.xxx";
my $secondary_gateway = "xxx.xxx.xxx.xxx";

# The VPN username on the server
# For security reasons do not use root
# this user will iniate the PPP connection
my $vpn_user = "xxx";

# The IP address of the PPP interface on the server
my $server_ifipaddr = "192.168.x.2";

# The IP of the clientPPP interface
my $client_ifipaddr = "192.168.x.1";


# This is the port SSH is listening to on the server
# These ports have to be open on your firewall
my $primary_local_ssh_opts = "-p xxxx";
my $secondary_local_ssh_opts = "-p xxxx";

#
# The rest of the client should not need to be changed
# unless you are trying to port the client to a 
# different operating system
# 

#
# required commands...
#
my $pppd = "/usr/sbin/pppd";
my $ssh = "/usr/bin/ssh";

# command line arguments
my $argc = @ARGV;

if (-f $pppd) {
        if (-f $ssh) {
                if ($argc == 0) {
                        print "Usage: vpn {start|stop|config}\n"
                } elsif ($ARGV[0] =~ m/start/) {
                        vpn_start();
                } elsif ($ARGV[0] =~ m/stop/) {
                        vpn_stop();
                } elsif ($ARGV[0] =~ m/config/) {
                        vpn_config();
                } elsif ($ARGV[0] =~ m/status/) {
                        vpn_status();
                } else {
                        vpn_cmd_error();
                }
        } else {
                print "Can't find $ssh\n";
        }
} else {
        print "Can't find $pppd\n";
}

sub vpn_start {
        my $status;
        print "Starting vpn to $primary_gateway:\n";

        $status = vpn_connect();

        if ($status) {
                print "connected.\n";
                vpn_add_routes();
        } else {
                print "Failed to bring up the tunnel\n";
        }
}
sub vpn_stop {
        my $status;

        $status = vpn_disconnect();

        if ($status) {
                print "Stopping vpn to $primary_gateway:\n";
                print "disconnected.\n";
        } else {
                print "Failed to find PID for the connection\n";
        }
}
sub vpn_config {
        print "SERVER_HOSTNAME=$primary_gateway\n"; 
        print "SERVER_USERNAME=$vpn_user\n"; 
        print "SERVER_IFIPADDR=$server_ifipaddr\n"; 
        print "CLIENT_IFIPADDR=$client_ifipaddr\n"; 
}
sub vpn_status {
        vpn_get_status();
}
sub vpn_cmd_error {
        print "Error in command!!\n";
        print "Usage: vpn {start|stop|config}\n";
        print "$0 ";
        print "$ARGV[0]\n";
}
sub vpn_add_routes {
        my @routes =("192.168.1.0/24");
        my $ppp_interface;
        my $line;

        $ppp_interface = get_ppp_interface();

        print "Adding routes\n";

        foreach $line (@routes) {
                system "ip route add $line dev $ppp_interface";
        }
}
sub vpn_del_routes {
        my @routes =("192.168.1.0/24");
        my $ppp_interface;
        my $line;

        $ppp_interface = get_ppp_interface();

        print "Deleting routes\n";

        foreach $line (@routes) {
                system "ip route del $line";
        }
}
sub vpn_connect {
        my $vpn_cmd;
        my $status = 0;

        $vpn_cmd = "$pppd updetach noauth passive pty \"$ssh $primary_local_ssh_opts $primary_gateway -l$vpn_user -o Batchmode=yes sudo $pppd nodetach notty noauth\" ipparam vpn $client_ifipaddr:$server_ifipaddr";
        $status = 1;

        system "$vpn_cmd";

        return $status;
}
sub vpn_disconnect {
        my $vpn_pid_cmd;
        my $status = 0;
        my $line;
        my $pid;
        my @pid_data;

        $vpn_pid_cmd = "ps ax | grep \"$ssh $primary_local_ssh_opts $primary_gateway -l$vpn_user -o\" | grep -v ' passive ' | grep -v 'grep '";

        vpn_del_routes();

        open VPN_PID, "$vpn_pid_cmd |";
        foreach $line (<VPN_PID>) {
                chomp $line;

                $line = trim($line);
                #print "$line\n";
                @pid_data = split " ", $line;

                $pid = $pid_data[0];
                if ($pid =~ m//) {
                        print "Error, Invalid proscess id \"$pid\"\n";
                } else {
                        system "kill -9 $pid";
                        $status = 1;
                }
        }
        close VPN_PID;

        return $status;
}
sub vpn_get_status {
        my $ping_cmd = "ping";
        my $irterface_stat_cmd = "ip -s link list";
        my $ppp_interface;
        my $loss;
        my $line;

        $ppp_interface = get_ppp_interface();


        if ($ppp_interface =~ m/NULL/) {
                print "No ppp interface found, the tunnel is down\n";
        } else {
                print "$ppp_interface interface status\n";
                print "SERVER_HOSTNAME=$primary_gateway\n"; 
                print "SERVER_USERNAME=$vpn_user\n"; 
                print "SERVER_IFIPADDR=$server_ifipaddr\n"; 
                print "CLIENT_IFIPADDR=$client_ifipaddr\n"; 

                print "-=-=-=-=-=-=-=-=-=-=-=-=-\n";

                open PING_CMD, "$ping_cmd -I $ppp_interface -c5 $server_ifipaddr |";
                foreach $line (<PING_CMD>) {
                        chomp $line;

                        if ($line =~ m/packet loss/) {
                                $loss = get_packet_loss($line);
                                print "$loss% packet loss\n";
                        }
                }
                close PING_CMD;
                
                print "-=-=-=-=-=-=-=-=-=-=-=-=-\n";

                open STAT_CMD, "$irterface_stat_cmd $ppp_interface |"; 
                foreach $line (<STAT_CMD>) {
                        chomp $line;
                        $line = trim($line);
                        print "$line\n";
                }
                close STAT_CMD;
        }
}
sub get_packet_loss {
        my $loss_line = shift;
        my @loss_data;
        my $line;
        my $loss;

        @loss_data = split ",", $loss_line;

        foreach $line (@loss_data) {
                if ($line =~ m/packet loss/) {
                        $line =~ s/packet loss//;
                        $line =~ s/%//;

                        $loss = trim($line);
                }
        }

        return $loss;
}
sub get_ppp_interface {
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
sub trim {
        my $string = shift;

        $string =~ s/^\ \ *//;
        $string =~ s/\ \ *$//;

        return $string;
}
