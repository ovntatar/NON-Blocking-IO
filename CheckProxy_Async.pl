use strict;
use Fcntl;
use Errno qw(EINPROGRESS EALREADY EISCONN);
use Socket;
use Time::HiRes qw ( time sleep );
use Carp qw(croak);
use DDP;

my @hosts = (
'37.114.201.3:8080',
'110.208.26.38:9000',
'61.156.235.170:9999',
'46.16.108.34:5555',
'202.77.123.38:5555',
'210.39.18.236:1080',
'61.53.64.37:8080',
'186.94.81.67:8080',
'121.52.229.51:3128',
'46.209.248.1:82',
'121.11.167.246:9999',
'41.211.125.136:8080',
'218.36.254.166:8888',
'121.11.167.26:999911',
'94.184.245.9:8080',
'1.179.139.148:8080',
'120.203.214.161:80',
'85.185.45.202:80'
);

my $connected = parallel_connect(hosts => \@hosts, minimum => 1, timeout => 2);

p ($connected);
exit 0;

sub parallel_connect {
    my %opts = @_;
    my $hosts   = delete $opts{hosts} or croak "No hosts specified";
    my $timeout = delete $opts{timeout} || 2.0;
    my $minimum = delete $opts{minimum} || 1;
    croak "Unknown options: @{[ sort keys %opts ]}" if %opts;

    my $end_time = time() + $timeout;
    my $poll_delay = 0.01;
    my $proto = getprotobyname('tcp');
    my %socks = map {
        my $socket;
        my $flags = 0;
        socket($socket, PF_INET, SOCK_STREAM, $proto) || die ("socket: $!");
        fcntl($socket, F_GETFL, $flags)               || die ("fcntl: $!");
        fcntl($socket, F_SETFL, $flags | O_NONBLOCK)  || die ("fcntl: $!");

        my ($ip, $port) = split /:/, $_;
        my %sockinfo = ( socket => $socket, ip => $ip, $port => $port );
        my $inet_aton = inet_aton($ip) || die ("inet_aton $ip: $!");
        $sockinfo{sockaddr}  = sockaddr_in($port, $inet_aton);
        ($_ => \%sockinfo)
    } @$hosts;

	my $count = keys %socks;
    p $count;
    my %connected;
    while (%socks) {
        while ( my ($host, $sockinfo) = each %socks ) {
            connect($sockinfo->{socket}, $sockinfo->{sockaddr})
                and next; # let EISCONN below handle this (rare) race 'hazard'

            if ($! == EINPROGRESS() || $! == EALREADY()) {
                next; # still connecting
            }

            delete $socks{$host};

            if ($! == EISCONN()) {
                delete $sockinfo->{sockaddr};
                $connected{$host} = $sockinfo;
            }
            else {
                warn "Unable to connect to $host: $! ".($!+0);
            }
        }

        last if time() > $end_time;

        sleep $poll_delay;
    }

    return undef unless %connected;
    return \%connected;
}
