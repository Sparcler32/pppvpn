#!/usr/bin/perl
#
# This script initiates a ppp-ssh vpn connection.
#
use strict;
use Sys::Syslog;
use Sys::Syslog qw(:standard :macros setlogsock);

#
# You will need to change these variables...
#

# The host name or IP address of the SSH server that we are
# sending the connection request to:
my $gateway = "149.56.176.57";
my $secondary_gateway = "192.99.87.167";

# The username on the VPN server that will run the tunnel.
# For security reasons, this should NOT be root.  (Any user
# that can use PPP can intitiate the connection on the client)
my $vpn_user = "vpn";
my $secondary_vpn_user = "vpn";

# The VPN network interface on the server should use this address:
my $server_ifipaddr = "192.168.3.2";
my $secondary_server_ifipaddr = "192.168.5.2";

# ...and on the client, this address:
my $client_ifipaddr = "192.168.3.1";
my $secondary_client_ifipaddr = "192.168.5.1";

# This tells ssh to use unprivileged high ports, even though it's
# running as root.  This way, you don't have to punch custom holes
# through your firewall.
my $local_ssh_opts = "-p 9352";
my $secondary_local_ssh_opts = "-p 4719";

# This tells the vpn client it's role
# This will be either gateway or client
# The vpn will be either site to site or client to site,
# if it is a site to site vpn the role will be gateway
# if it is a client to site the role will be client
# This will be used in determining the routing
my $role = "gateway";

# this tells the client to connect to either
# the primary or secondary gateway.
# This will be automated at some point
my $gateway = 2;

# syslog logging setup
# This tells the client what type of logging to do
# 1 = use, 0 do not use
# local syslog
my $use_syslog_local = 1;
# remote syslog
my $use_syslog_remote = 0;
# you need a working syslog server for this to work
# This should only be used when the client is running 
# as a gateway
my $syslog_ip = "10.150.10.5";
my $syslog_port = 514;

#
# The rest of this file should not need to be changed.
#

#
# required commands...
#
my $pppd = "/usr/sbin/pppd";
my $ssh = "/usr/bin/ssh";
my $argc = @ARGV;

if (-f $pppd) {
	if (-f $ssh) {
		if ($argc == 0) {
			send_log("Usage: pppvpn.pl {start|stop|config|status|debug}");
		} elsif ($ARGV[0] =~ m/start/) {
			vpn_start();
		} elsif ($ARGV[0] =~ m/stop/) {
			vpn_stop();
		} elsif ($ARGV[0] =~ m/config/) {
			vpn_config();
		} elsif ($ARGV[0] =~ m/status/) {
			vpn_status();
		} elsif ($ARGV[0] =~ m/debug/) {
			vpn_debug();
		} else {
			vpn_cmd_error();
		}
	} else {
		send_log("Can't find $ssh");
	}
} else {
	send_log("Can't find $pppd");
}

sub vpn_start {
	my $status;
	my $vpn_status;

	if ($gateway == 1) {
		send_log("Starting vpn to $gateway:");
	} elsif ($gateway == 2) {
		send_log("Starting vpn to $secondary_gateway:");
	}

	# check the status of the tunnel before trying to bring it up
	$vpn_status = vpn_check();

	# if ppp interface count is 0 try and bring up the tunnel
	if ($vpn_status) {
		$status = vpn_connect();

		if ($status) {
			send_log("connected.");
			vpn_add_routes();
		} else {
			send_log("Failed to bring up the tunnel");
		}
	} else {
		# if ppp interface count is anything other than 0
		# disconnect the tunnel before trying to bring it up
		$status = vpn_disconnect();

		if ($status) { 
			$status = vpn_connect();

			if ($status) {
				send_log("connected.");
				# add routes after brining up the tunnel
				vpn_add_routes();
			} else {
				send_log("Failed to bring up the tunnel");
			}
		} else {
			send_log("Failed to bring up the tunnel");
		}
	}
}
sub vpn_stop {
	my $status;

	if ($gateway == 1) {
		send_log_msg("Stopping vpn to $gateway:");
	} elsif ($gateway == 2) {
		send_log("Stopping vpn to $secondary_gateway:");
	}

	# call tunnel disconnect function
	$status = vpn_disconnect();

	if ($status) {
		send_log("disconnected.");
	} else {
		send_log("Failed to find PID for the connection");
	}
}
sub vpn_config {
	send_log("-=-=-=-[Start VPN Config]-=-=-=-=-=-=-=-=-=-"); 
	if ($gateway == 1) {
		send_log("SERVER_HOSTNAME=$gateway"); 
		send_log("SERVER_USERNAME=$vpn_user"); 
		send_log("SERVER_IFIPADDR=$server_ifipaddr"); 
		send_log("CLIENT_IFIPADDR=$client_ifipaddr");
	} elsif ($gateway == 2) {
		send_log("SERVER_HOSTNAME=$secondary_gateway:");
		send_log("SERVER_USERNAME=$secondary_vpn_user"); 
		send_log("SERVER_IFIPADDR=$secondary_server_ifipaddr"); 
		send_log("CLIENT_IFIPADDR=$secondary_client_ifipaddr");
	}
	send_log("-=-=-=-[End VPN Config]-=-=-=-=-=-=-=-=-=-"); 
}
sub vpn_status {
	vpn_get_status();
}
sub vpn_debug {
	my $pid;
	my $pid_count;
	my $pid_list;
	my $loss;
	my $ppp_interface;
	my $ppp_interface_count;
	my $ppp_interface_list;
	my $ppp_interface_ip;
	my $ppp_peer_ip;
	my $inet_line;
	my @pid_data;
	my @ppp_interface_data;

	$pid_count = get_tunnel_pid_count();
	$ppp_interface_count = get_ppp_interface_count(); 

	send_log("-=-=-=-[Start VPN Debug]-=-=-=-=-=-=-=-=-=-"); 
	send_log("PID Count: $pid_count");
	send_log("PPP Interface Count: $ppp_interface_count");


	if ($pid_count == 0) {
		send_log("No Active PID fount");
	} elsif ($pid_count == 1) {
		$pid = get_tunnel_pid();
		send_log("PID: $pid");
	} else {
		$pid_list = get_tunnel_pid_list();
		send_log("PID List: $pid_list");
	}

	if ($ppp_interface_count == 0) {
		send_log("No active PPP interfaces found");
	} elsif ($ppp_interface_count == 1) {
		$ppp_interface = get_ppp_interface();
		send_log("PPP Interface: $ppp_interface");
		$inet_line = get_ppp_interface_ip($ppp_interface);
		$ppp_interface_ip = get_ppp_ip($inet_line); 
		$ppp_peer_ip = get_peer_ip($inet_line);
		send_log("$ppp_interface: $ppp_interface_ip");
		send_log("$ppp_interface peer ip: $ppp_peer_ip");
	} else {
		$ppp_interface_list = get_ppp_interface_list();
		send_log("PPP Interface List: $ppp_interface_list ");
	}	

	send_log("-=-=-=-[End VPN Debug]-=-=-=-=-=-=-=-=-=-"); 
}
sub vpn_cmd_error {
	send_log("Error in command!!");
	send_log("Usage: pppvpn.pl {start|stop|config|status|debug}");
	send_log("$0 ");
	send_log("Invalid argument \"$ARGV[0]\"");
}
# route handeling functions
sub vpn_add_routes {
	my @routes;
	my $ppp_interface;
	my $line;

	if ($role =~ m/gateway/) {
		if ($gateway == 1) {
			@routes = ("192.168.4.0/24");
		} elsif ($gateway == 2) {
			@routes = ("192.168.6.0/24");
		}
	} elsif ($role =~ m/client/) {
		@routes = ("10.15.5.0/24", "10.15.40.0/24", "10.150.10.0/24", "192.168.1.0/24");
	}

	$ppp_interface = get_ppp_interface();

	send_log("Adding routes");

	foreach $line (@routes) {
		system "ip route add $line dev $ppp_interface";
	}
}
sub vpn_del_routes {
	my @routes;
	my $ppp_interface;
	my $line;

	if ($role =~ m/gateway/) {
		if ($gateway == 1) {
			@routes = ("192.168.4.0/24");
		} elsif ($gateway == 2) {
			@routes = ("192.168.6.0/24");
		}
	} elsif ($role =~ m/client/) {
		@routes = ("10.15.5.0/24", "10.15.40.0/24", "10.150.10.0/24", "192.168.1.0/24");
	}

	$ppp_interface = get_ppp_interface();

	send_log("Deleting routes");

	foreach $line (@routes) {
		system "ip route del $line";
	}
}
# tunnel connection handeling functions
sub vpn_connect {
	my $vpn_cmd;
	my $status = 0;
	my $state = 0;

	# decide what gateway to open the tunnel to
	if ($gateway == 1) {
		$vpn_cmd = "$pppd updetach noauth passive pty \"$ssh $local_ssh_opts $gateway -l$vpn_user -o Batchmode=yes sudo $pppd nodetach notty noauth\" ipparam vpn $client_ifipaddr:$server_ifipaddr";
	} elsif ($gateway == 2) {
		$vpn_cmd = "$pppd updetach noauth passive pty \"$ssh $secondary_local_ssh_opts $secondary_gateway -l$secondary_vpn_user -o Batchmode=yes sudo $pppd nodetach notty noauth\" ipparam vpn $secondary_client_ifipaddr:$secondary_server_ifipaddr";
	}

	# open the tunnel
	$state = system "$vpn_cmd";

	if ($state == 0) {
		$status = 1;
	} else {
		$status = 0;
	}

	return $status;
}
sub vpn_disconnect {
	my $vpn_pid_cmd;
	my $status = 0;
	my $state = 0;
	my $line;
	my $pid;
	my @pid_data;

	# command to find the ssh pid
	if ($gateway == 1) {
		$vpn_pid_cmd = "ps ax | grep \"$ssh $local_ssh_opts $gateway -l$vpn_user -o\" | grep -v ' passive ' | grep -v 'grep '";
	} elsif ($gateway ==2) {
		$vpn_pid_cmd = "ps ax | grep \"$ssh $secondary_local_ssh_opts $secondary_gateway -l$secondary_vpn_user -o\" | grep -v ' passive ' | grep -v 'grep '";
	}

	# delete routes before bringing down the tunnel
	vpn_del_routes();

	open VPN_PID, "$vpn_pid_cmd |";
	foreach $line (<VPN_PID>) {
		chomp $line;

		$line = trim($line);
		@pid_data = split " ", $line;

		$pid = $pid_data[0];
		if ($pid =~ m//) {
			send_log("Error, Invalid proscess id \"$pid\"");
		} else {
			$state = system "kill -9 $pid";

			if ($state == 0) {
				$status = 1;
			} else {
				$status = 0;
			}
		}
	}
	close VPN_PID;

	return $status;
}
sub vpn_check {
	my $status = 0;
	my $ppp_interface_count;

	$ppp_interface_count = get_ppp_interface_count();

	# check to see if there is more than 1 ppp interface
	if ($ppp_interface_count == 0) {
		$status = 1;
	} else {
		$status = 0;
	}

	return $status;
}
# tunnel status functions
sub get_tunnel_pid {
	my $vpn_pid_cmd;
	my $status;
	my $pid;
	my $line;

	if ($gateway == 1) {
		$vpn_pid_cmd = "ps ax | grep \"$ssh $local_ssh_opts $gateway -l$vpn_user -o\" | grep -v ' passive ' | grep -v 'grep '";
	} elsif ($gateway ==2) {
		$vpn_pid_cmd = "ps ax | grep \"$ssh $secondary_local_ssh_opts $secondary_gateway -l$secondary_vpn_user -o\" | grep -v ' passive ' | grep -v 'grep '";
	}

	open PID_CHK, "$vpn_pid_cmd |";
	foreach $line (<PID_CHK>) {
		chomp $line;

		send_log("$line");
	}
	close PID_CHK;

	return $pid;
}
sub get_tunnel_pid_list {
	my $vpn_pid_count = 0;
	my $vpn_pid_cmd;
	my $pid;
	my $pid_line;
	my $line;
	my @line_data;
	my @pid_list;

	if ($gateway == 1) {
		$vpn_pid_cmd = "ps ax | grep \"$ssh $local_ssh_opts $gateway -l$vpn_user -o\" | grep -v ' passive ' | grep -v 'grep '";
	} elsif ($gateway ==2) {
		$vpn_pid_cmd = "ps ax | grep \"$ssh $secondary_local_ssh_opts $secondary_gateway -l$secondary_vpn_user -o\" | grep -v ' passive ' | grep -v 'grep '";
	}

	open PID_CHK, "$vpn_pid_cmd |";
	foreach $line (<PID_CHK>) {
		chomp $line;
		$line = trim($line);
		$line =~ s/\ \ */,/g;
		@line_data = split ",", $line;
		$pid = shift @line_data;
		push @pid_list, $pid;
	}
	close PID_CHK;

	$pid_line = join ",", @pid_list;

	return $pid_line;
}
sub get_tunnel_pid_count {
	my $vpn_pid_count = 0;
	my $vpn_pid_cmd;
	my $status;
	my $pid;
	my $line;

	if ($gateway == 1) {
		$vpn_pid_cmd = "ps ax | grep \"$ssh $local_ssh_opts $gateway -l$vpn_user -o\" | grep -v ' passive ' | grep -v 'grep '";
	} elsif ($gateway ==2) {
		$vpn_pid_cmd = "ps ax | grep \"$ssh $secondary_local_ssh_opts $secondary_gateway -l$secondary_vpn_user -o\" | grep -v ' passive ' | grep -v 'grep '";
	}

	open PID_CHK, "$vpn_pid_cmd |";
	foreach $line (<PID_CHK>) {
		chomp $line;

		$vpn_pid_count++;
	}
	close PID_CHK;

	return $vpn_pid_count;
}
sub vpn_get_status {
	my $irterface_stat_cmd = "ip -s link list";
	my $ppp_interface;
	my $loss;
	my $line;

	$ppp_interface = get_ppp_interface();

	send_log("-=-=-=-[Start VPN Status]-=-=-=-=-=-=-=-=-=-"); 
	
	if ($ppp_interface =~ m/NULL/) {
		send_log("No ppp interface found, the tunnel is down");
	} else {
		print "$ppp_interface interface status\n";
		if ($gateway == 1) {
			send_log("SERVER_HOSTNAME=$gateway"); 
			send_log("SERVER_USERNAME=$vpn_user"); 
			send_log("SERVER_IFIPADDR=$server_ifipaddr"); 
			send_log("CLIENT_IFIPADDR=$client_ifipaddr"); 
		} elsif ($gateway == 2) {
			send_log("SERVER_HOSTNAME=$secondary_gateway"); 
			send_log("SERVER_USERNAME=$secondary_vpn_user"); 
			send_log("SERVER_IFIPADDR=$secondary_server_ifipaddr"); 
			send_log("CLIENT_IFIPADDR=$secondary_client_ifipaddr"); 
		}
		send_log("-=-=-=-=-=-=-=-=-=-=-=-=-");

		$loss = chk_packet_loss();
		send_log("$loss% packet loss");

		send_log("-=-=-=-=-=-=-=-=-=-=-=-=-");

		open STAT_CMD, "$irterface_stat_cmd $ppp_interface |"; 
		foreach $line (<STAT_CMD>) {
			chomp $line;
			$line = trim($line);
			send_log($line);
		}
		close STAT_CMD;
	}

	send_log("-=-=-=-[End VPN Status]-=-=-=-=-=-=-=-=-=-");
}
sub chk_packet_loss {
	my $ping_cmd;
	my $ppp_interface;
	my $line;
	my $loss;

	$ppp_interface = get_ppp_interface();

	if ($gateway == 1) {
		$ping_cmd = "ping -I $ppp_interface -c5 $server_ifipaddr";
	} elsif ($gateway == 2) {
		$ping_cmd = "ping -I $ppp_interface -c5 $secondary_server_ifipaddr";
	}

	open PING_CMD, "$ping_cmd |";
	foreach $line (<PING_CMD>) {
		chomp $line;

		if ($line =~ m/packet loss/) {
			$loss = get_packet_loss($line);
		}
	}
	close PING_CMD;

	return $loss;
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
sub get_ppp_interface_list {
	my $link_cmd = "ip link list";
	my $line;
	my $index;
	my $ppp_interface_list = "NULL";
	my @line_data;
	my @ppp_interface_array;

	open LINK_CMD, "$link_cmd |";
	foreach $line (<LINK_CMD>) {
		chomp $line;

		if ($line =~ m/ppp/) {
			@line_data = split ":", $line;

			foreach $index (@line_data) {
				if ($index =~ m/ppp[0-9][0-9]*/) {
					$index = trim($index);
					push @ppp_interface_array, $index;
				}
			}
		}
	}
	close LINK_CMD;

	$ppp_interface_list = join ",", @ppp_interface_array;

	return $ppp_interface_list;
}
sub get_ppp_interface_count {
	my $link_cmd = "ip link list";
	my $ppp_interface_count = 0;
	my $line;
	my $index;
	my @line_data;

	open LINK_CMD, "$link_cmd |";
	foreach $line (<LINK_CMD>) {
		chomp $line;

		if ($line =~ m/ppp/) {
			@line_data = split ":", $line;

			foreach $index (@line_data) {
				if ($index =~ m/ppp[0-9][0-9]*/) {
					$ppp_interface_count++;
				}
			}
		}
	}
	close LINK_CMD;

	return $ppp_interface_count;
}
sub get_ppp_interface_ip {
	my $ppp_interface = shift;
	my $line;
	my $interface_cmd;
	my $ppp_interface_ip;
	my $peer_ip;
	my $inet_line;

	$interface_cmd = "ip address list $ppp_interface";

	open IFCMD, "$interface_cmd |";
	foreach $line (<IFCMD>) {
		chomp $line;

		if ($line =~ m/inet/) {
			$line = trim($line);
			$ppp_interface_ip = $line;
			$peer_ip = $line;

			$ppp_interface_ip =~ s/peer\ .*$//;
			$ppp_interface_ip =~ s/^inet//;
			$ppp_interface_ip = trim($ppp_interface_ip);

			$peer_ip =~ s/scope\ .*$//;
			$peer_ip =~ s/^.*\ peer//;
			$peer_ip = trim($peer_ip);

			$inet_line = "ip:$ppp_interface_ip,peer:$peer_ip";
			#send_log("$ppp_interface_ip");
			#send_log("$peer_ip");
		}
	}
	close IFCMD;

	return $inet_line;
}	
sub get_ppp_ip {
	my $ip_line = shift;
	my ($ip, $peer);

	($ip, $peer) = split ",", $ip_line;
	($ip, $peer) = split ":", $ip;

	return $peer;
}
sub get_peer_ip {
	my $peer_line = shift;
	my ($ip, $peer);

	($ip, $peer) = split ",", $peer_line;
	($ip, $peer) = split ":", $peer;

	$peer =~ s/\/32$//;

	return $peer;
}
# syslog and logging functions
sub send_log {
	my $log_msg = shift;

	print "$log_msg\n";
	send_local_syslog_msg("$log_msg\n"); 
	send_remote_syslog_msg("$log_msg\n"); 
}
sub send_local_syslog_msg {
	my $syslog_msg = shift;
	my $syslog_options = "pid";
	my $syslog_facility = "local0";
}
sub send_remote_syslog_msg {
	my $syslog_msg = shift;
	my $syslog_options = "pid";
	my $syslog_facility = "local0";
	my $program_name = "pppvpn";
	my $sender_name = "$role";

	openlog("$program_name $sender_name", $syslog_options);
	setlogsock({ type => "udp", host => "$syslog_ip", port => "$syslog_port" });

	syslog('info', "$syslog_msg");

	closelog();
}
# string handeling functions
sub trim {
	my $string = shift;

	$string =~ s/^\ \ *//;
	$string =~ s/\ \ *$//;

	return $string;
}
