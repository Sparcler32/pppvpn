# pppvpn
A ssh pppp vpn clinet and utilities

A ssh ppp vpn is a Virtual Private Network that runs a PPP link through an SSH tunel.
This version is intended to setup and maintain a site to site tunnal.
The original document on how to set up a ssh ppp vpn can be found here
http://www.tldp.org/HOWTO/text/ppp-ssh

This implementation was written perl. There are 3 files 
pppvpn.pl
route-add.pl
tunelkeep.pl

The proscess for seting up the VPN server is the same as what is listed in the TLDP file.
The client was rewriten and is file pppvpn.pl

The file route-add.pl is the route add utility for the server and is called by the client

The file tunelkeep.pl is the tunnel keep alive utility and is run on the client

It would not be that hard to use this to create a client to site tunnel. In this
implementation the addresses of the PPP interfaces are assigned staticly. 
