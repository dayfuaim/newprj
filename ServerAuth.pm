package ServerAuth;

# we will need to manage Header information to get a ticket
@ServerAuth::ISA = qw(SOAP::Server::Parameters);
# $SOAP::Constants::DO_NOT_USE_XML_PARSER = 1;

# ----------------------------------------------------------------------
# private functions
# ----------------------------------------------------------------------

use Digest::MD5 qw(md5 md5_hex);
use File::Basename;
use File::Find;
use MIME::Base64::URLSafe;

my $calculateAuthInfo = sub {
        return md5_hex(join '', 'something unique for your implementation', @_);
};

my $checkAuthInfo = sub {
        my $authInfo = shift;
        my $signature = $calculateAuthInfo->($authInfo->valueof('//login'),$authInfo->valueof('//time'));
        die "Authentication information is not valid" if $signature ne $authInfo->valueof('//signature');
        die "Authentication information is expired" if time() > $authInfo->valueof('//time');
        return $authInfo->valueof('//login');
};

my $makeAuthInfo = sub {
        my $login = shift;
        my $time = time()+20*60; # signature will be valid for 20 minutes
        my $signature = $calculateAuthInfo->($login, $time);
        return +{time => $time, login => $login, signature => $signature};
};


# ----------------------------------------------------------------------
# public functions
# ----------------------------------------------------------------------

sub login {
        my $self = shift;
        pop; # last parameter is envelope, don't count it
        die "Wrong parameter(s): login(login, password) [".scalar @_."]" unless @_ == 2;
        my ($login, $password) = @_;
        # check credentials, write your own is_valid() function
        die "Credentials are wrong [$login, $password]" unless $self->is_valid($login, $password);
        # create and return ticket if everything is ok
        return $makeAuthInfo->($login);
}

sub is_valid {
        my $self = shift;
        my $yourhash = md5_hex(@_);
        my $ourhash = md5_hex($sitemodules::Settings::c{soap}{login},$sitemodules::Settings::c{soap}{passwd});
        return ($yourhash==$ourhash)
}

sub protected {
        my $self = shift;
        my $authInfo = pop;
    my $login = $checkAuthInfo->($authInfo);
        # do something, user is already authenticated
        my $method = shift;
        return $self->$method(@_)
}

sub getQuery {
        my $self = shift;
        my $authInfo = pop;
        die qq{Unauthorized access!!!} unless $checkAuthInfo->($authInfo);
        my $q = shift;
        die qq{Empty QUERY!} unless $q;
        $q =~ s/&lt;/</g;
        $q =~ s/&amp;/&/g;
        my @out;
        if ($q =~ /^(insert|update|delete|alter|change|drop)/i) {
                return $self->doQuery($q)
        } else {
                my $sth = $sitemodules::DBfunctions::dbh->prepare($q);
                die qq{$DBI::error: $DBI::errstr} if $DBI::error;
                $sth->execute();
                if ($sth->rows) {
                        push @out, @{$sth->fetchall_arrayref};
                        unshift @out, $out[0]->[0]
                }
                return @out
        }
}

sub getQueryHash {
        my $self = shift;
        my $authInfo = pop;
        die qq{Unauthorized access!!!} unless $checkAuthInfo->($authInfo);
        my $q = shift;
        die qq{Empty QUERY!} unless $q;
        $q =~ s/&lt;/</g;
        $q =~ s/&amp;/&/g;
        my @out;
        if ($q =~ /^(insert|update|delete|alter|change|drop)/i) {
                return $self->doQuery($q)
        } else {
                my $sth = $sitemodules::DBfunctions::dbh->prepare($q);
                die qq{$DBI::error: $DBI::errstr} if $DBI::error;
                $sth->execute();
                if ($sth->rows) {
                        push @out, $sth->{NUM_OF_FIELDS};
                        while (my $row = $sth->fetchrow_hashref) {
                                push @out, $row;
                        }
                }
                return @out
        }
}

sub doQuery {
        my $self = shift;
        my $authInfo = pop;
        die qq{Unauthorized access!!!} unless $checkAuthInfo->($authInfo);
        my $q = shift;
        die qq{Empty QUERY!} unless $q;
        $q =~ s/&lt;/</g;
        $q =~ s/&amp;/&/g;
        my $out;
        if ($q =~ /^(insert|update|delete|alter|change|drop)/i) {
                $sitemodules::DBfunctions::dbh->do($q);
                return $sitemodules::DBfunctions::dbh->selectrow_array("SELECT LAST_INSERT_ID()") if $q =~ /^insert/i;
                die qq{$DBI::error: $DBI::errstr} if $DBI::error
        } else {
                return $self->getQuery($q)
        }
        return 0
}

sub batchUpdate {
        my $self = shift;
        my $authInfo = pop;
        die qq{Unauthorized access!!!} unless $checkAuthInfo->($authInfo);
        my $parm = shift;
        my @p = @$parm;
        my $tbl = shift @p;                     # [0] table
        my %d = %{ shift @p };          # [1] data hash
        $tbl =~ /(.+?)_tbl/;
        my $id = $1."_id";
        foreach (keys %d) {
                my %data = %{$d{$_}};
                my $sql = "UPDATE $tbl SET ";
                my @f;
                while (my ($f,$v) = each %data) {
                        push @f, qq{$f='$v'}
                }
                $sql .= join ", "=>@f;
                $sql .= " WHERE $id=$_";
                $sitemodules::DBfunctions::dbh->do($sql)
        }
}

sub getColumns {
        my $self = shift;
        my $authInfo = pop;
        die qq{Unauthorized access!!!} unless $checkAuthInfo->($authInfo);
        my $table = shift;
        my %h;
        foreach my $t (@$table)  {
                my $sth = $sitemodules::DBfunctions::dbh->prepare("SHOW COLUMNS FROM $t");
                $sth->execute();
                while (my @row = $sth->fetchrow_array) {
                        push @{$h{$t}}, $row[0]
                }
        }
        return \%h;
}

sub doDBUpdate {
        my $self = shift;
        my $authInfo = pop;
        die qq{Unauthorized access!!!} unless $checkAuthInfo->($authInfo);
        my ($db,$pass,$sql) = @{$_[0]};
		$sql = urlsafe_b64decode($sql);
        open (MYSQL,">$sitemodules::Settings::c{dir}{htdocs}/mysql_dump") or die "Can't open DB: $!";
        print MYSQL $sql;
        close(MYSQL);
        my $str = "mysql -u root -p$pass -D $db < $sitemodules::Settings::c{dir}{htdocs}/mysql_dump";
        my $res = system($str);
        if ($res==0) {
#               unlink "$sitemodules::Settings::c{dir}{htdocs}/mysql_dump";
                return $res
        } else {
                my $ex_val = $? >> 8;
                my $ex_signal = $? & 127;
                my $ex_core = $? & 128;
                die "ERROR: [$ex_val] ($db) $!"
        }
}

sub doBackupDB {
        my $self = shift;
        my $authInfo = pop;
        die qq{Unauthorized access!!!} unless $checkAuthInfo->($authInfo);
        my ($db,$pass,@tabs) = @{$_[0]};
        my ($d,$m,$y,@t) = (localtime)[3..5,0..2];
        $m++; $y += 1900;
        my $date = sprintf "%d%02d%02d-%02d%02d%02d",$y,$m,$d,reverse @t;
        my $sql = "$sitemodules::Settings::c{dir}{htdocs}/../db_backup/dump_$date.sql";
        $sql =~ s!(?:([^/]+)/\.\./)!!g;
        my $zip = "$sitemodules::Settings::c{dir}{htdocs}/../db_backup/dump_$date.zip";
        $zip =~ s!(?:([^/]+)/\.\./)!!g;
        my $cd = "$sitemodules::Settings::c{dir}{htdocs}/../db_backup";
        $cd =~ s!(?:([^/]+)/\.\./)!!g;
        my $cmd = "mysqldump -u root -p$pass $db ".join(' ',@tabs)." > $sql";
        system $cmd;
#       qx{cd $cd; zip -m9 ./dump_$date.sql ./dump_$date.zip};
#       $self->{r}->setResult($zip);
#       $self->{r}->setParams();
        return $cmd
}

sub getBackupList {
        my $self = shift;
        my $authInfo = pop;
        die qq{Unauthorized access!!!} unless $checkAuthInfo->($authInfo);
        my $path = "$sitemodules::Settings::c{dir}{htdocs}/../db_backup";
        $path =~ s!(?:([^/]+)/\.\./)!!g;
        my @flist = glob "$path/dump_*.sql";
        my %bl;
        foreach my $f (@flist) {
                my @t = sort grep { s/^.+`([^`]+)`.+$/$1/; chomp } qx{grep 'CREATE TAB' $f};
                $f = (split '/'=>$f)[-1];
                $bl{$f} = [ @t ]
        }
		my @r = %bl;
        return ($path,@r)
}

sub doRestore {
        my $self = shift;
        my $authInfo = pop;
        die qq{Unauthorized access!!!} unless $checkAuthInfo->($authInfo);
        my ($db,$pass,$file) = @{$_[0]};
        # my $file = shift;
        my $path = "$sitemodules::Settings::c{dir}{htdocs}/../db_backup";
        $path =~ s!(?:([^/]+)/\.\./)!!g;
        $path .= "/$file";
        my $str = qq{/usr/bin/mysql -D $db -u root}.($pass?" --password=$pass":'').qq{ < $path};
        my $res = qx{$str};
        return ($str,$res)
}

sub getFile {
        my $self = shift;
        my $authInfo = pop;
        die qq{Unauthorized access!!!} unless $checkAuthInfo->($authInfo);
        my $path = shift;
        $path = $self->_cleanPath($path);
        die qq{File error: Non-existent file '$sitemodules::Settings::c{dir}{htdocs}/$path'!!!} unless -e $sitemodules::Settings::c{dir}{htdocs}.'/'.$path;
        my @file;
        push @file, $path;
        open (IN, "<"."$sitemodules::Settings::c{dir}{htdocs}/$path");
        push @file, <IN>;
        close(IN);
        return @file
}

sub getFileEx {
        my $self = shift;
        my $authInfo = pop;
        die qq{Unauthorized access!!!} unless $checkAuthInfo->($authInfo);
        my $path = shift;
        die qq{File error: Non-existent file '$path'!!!} unless -e $path;
        my @file;
        push @file, $path;
        open (IN, "<"."$path");
        push @file, <IN>;
        close(IN);
        return @file
}

sub putFile {
        my $self = shift;
        my $authInfo = pop;
        die qq{Unauthorized access!!!} unless $checkAuthInfo->($authInfo);
        my ($path,$content,$mod) = @{$_[0]};
		$content = urlsafe_b64decode($content) if $path =~ /\.s?html?$/;
        _putFile($path,$content);
        return "OK"
}


sub putXMLFile {
        my $self = shift;
        my $authInfo = pop;
        die qq{Unauthorized access!!!} unless $checkAuthInfo->($authInfo);
        my ($path,$content,$mod) = @{$_[0]};
        $content =~ s/\r//g; 
        $content =~ s/&amp;/&/g; 
        $content =~ s/&lt;/</g; 
        $content =~ s/&gt;/>/g; 
        $content =~ s/&quot;/"/g;
        $content =~ s/&#xd;//g;
        _putFile($path,$content);
        return "OK"
}

sub _putFile {
        my ($path,$content) = @_;
        my $d = dirname($path);
        if ($d =~ /\//) {
                my @d = split /\//,dirname($path);
                foreach (0..$#d) {
                        my $td = join "/"=>@d[0..$_];
                        my $fulldir = $sitemodules::Settings::c{dir}{htdocs}.'/'.$td;
                        mkdir $fulldir,0775 unless -e $fulldir;
                }
        }
        open (IN, ">"."$sitemodules::Settings::c{dir}{htdocs}/$path") or die "Can't write to $sitemodules::Settings::c{dir}{htdocs}/$path";
        binmode IN;
        print IN $content;
        close(IN);
        my $f = "$sitemodules::Settings::c{dir}{htdocs}/$path";
        my $m = $mod==1?'0674':'0664';
        `chmod $m $f`;
}

sub putFileEx {
        my $self = shift;
        my $authInfo = pop;
        die qq{Unauthorized access!!!} unless $checkAuthInfo->($authInfo);
        my ($path,$content) = @{$_[0]};
        my $d = dirname($path);
        if ($d =~ /\//) {
                my @d = split /\//,dirname($path);
                foreach (0..$#d) {
                        my $td = join "/"=>@d[0..$_];
                        my $fulldir = $sitemodules::Settings::c{dir}{htdocs}.'/../'.$td;
                        mkdir $fulldir,0775 unless -e $fulldir;
                }
        }
        open (IN, ">"."$sitemodules::Settings::c{dir}{htdocs}/../$path") or die "Can't write to $sitemodules::Settings::c{dir}{htdocs}/../$path";
        binmode IN;
        print IN $content;
        close(IN);
        return "OK"
}

sub unlinkFile {
        my @out;
        my $self = shift;
        my $authInfo = pop;
        die qq{Unauthorized access!!!} unless $checkAuthInfo->($authInfo);
        my $path = shift;
        unlink "$sitemodules::Settings::c{dir}{htdocs}$path";
        my @d = split /\//,dirname($self->_cleanPath($path));
        if (scalar @d) {
                my $fulldir = $sitemodules::Settings::c{dir}{htdocs}.'/'.$d[0];
                find {
                        bydepth  => 1,
                        no_chdir => 1,
                        wanted   => sub {
                                                        if (!-l && -d _) {
                                                                rmdir
                                                        }
                                                }
                } => ($fulldir);
                push @out,$fulldir;
                push @out,@d;
        }
        return @out
}

sub unlinkFileEx {
        my @out;
        my $self = shift;
        my $path = shift;
        unlink "$path";
        my @d = split /\//,dirname($self->_cleanPath($path));
        if (scalar @d) {
                my $fulldir = $sitemodules::Settings::c{dir}{htdocs}.'/'.$d[0];
                find {
                        bydepth  => 1,
                        no_chdir => 1,
                        wanted   => sub {
                                                        if (!-l && -d _) {
                                                                rmdir
                                                        }
                                                }
                } => ($fulldir);
                push @out,$fulldir;
                push @out,@d;
        }
        return @out
}

sub fileExists {
        my $self = shift;
        my $authInfo = pop;
        die qq{Unauthorized access!!!} unless $checkAuthInfo->($authInfo);
        my $ra = shift;
        my $path = $sitemodules::Settings::c{dir}{htdocs};
        my @out;
        foreach (@$ra) {
            my @f = split /\|/;
            if (-e $path.$f[0]) {
                        push @out,qq{$f[0]|$f[1]|1}
            } else {
                        push @out,qq{$f[0]|$f[1]|0}
            }
        }
        unshift @out, $out[0];
        return @out
}

sub getStat {
        my $self = shift;
        my $authInfo = pop;
        die qq{Unauthorized access!!!} unless $checkAuthInfo->($authInfo);
        my $path = shift;
        my @out = stat $sitemodules::Settings::c{dir}{htdocs}.$path;
        return @out
}

sub _cleanPath {
        my $self = shift;
        my $path = shift;
        $path =~ s!^/?(.+?)/?$!$1!;
        return $path
}

sub getFileList {
        my $self = shift;
        my $authInfo = pop;
        die qq{Unauthorized access!!!} unless $checkAuthInfo->($authInfo);
        my ($dir,$type) = @{$_[0]};
        my $pat = qr/\.($type)/i;
        my $home = $sitemodules::Settings::c{dir}{htdocs};
        opendir(DIR, $home.$dir); # || die "can't opendir $dir: $!";
                my @dir = readdir(DIR);
        closedir DIR;
        @dir = sort { $a cmp $b } @dir;
        my @out;
        my @dirs;
        my @files;
        foreach (@dir) {
                next if /^\.$/;
                if (-d qq{$home$dir/$_}) {
                        push @dirs, ['d',$_]
                } else {
                        my $t = (/$pat$/)?'_':'f';
                        push @files, [$t,$_]
                }
        }
        @out = (@dirs,@files);
        return @out
}

sub getFileListEx {
        my $self = shift;
        my ($dir,$type) = @{$_[0]};
        my $pat = qr/\.($type)/i;
        opendir(DIR, $dir) || die "can't opendir $dir: $!";
                my @dir = readdir(DIR);
        closedir DIR;
        @dir = sort { $a cmp $b } @dir;
        my @out;
        my @dirs;
        my @files;
        foreach (@dir) {
                next if /^\.$/;
                if (-d qq{$dir/$_}) {
                        push @dirs, ['d',$_]
                } else {
                        my $t = (/$pat$/)?'_':'f';
                        push @files, [$t,$_]
                }
        }
        @out = (@dirs,@files);
        return @out
}

sub fixPerm {
        my $self = shift;
        my $authInfo = pop;
        my ($url,$lm) = @{$_[0]};
        my $home = $sitemodules::Settings::c{dir}{htdocs};
        my $file = qq{$home/$url};
        my $res = qx{stat $file | grep 'Access: ('};
        my ($perm) = $res =~ /^Access:\s\((\d+)/;
                my $r;
        if ($perm) {
                if ($perm eq '0674') {
                        $r = 'OK';
                        unless ($lm) {
                                qx{chmod 0664 $file};
                                $r .= qq{, FIXED $perm to 0664}
                        }
                } else {
                        $r = qq{OK, FIXED $perm to };
                        my $pp = ($lm)?'0674':'0664';
                        qx{chmod $pp $file};
                        $r .= $pp
                }
        } else {
                $r = 'NOT OK, Non-existent file'
        }
        return $r
}

sub verifyFiles {
    my $self = shift;
	my $authInfo = pop;
	my @out;
	my ($path,$fl) = @{$_[0]};
	my $home = $sitemodules::Settings::c{dir}{htdocs};
	my @nx = ();
	foreach my $f (sort {$a cmp $b} keys %$fl) {
		my @s = stat qq{$home$path$f};
		if (my @s = stat qq{$home$path$f}) {
			push @nx=>$f if $fl->{$f}!=$s[7]
		} else {
			push @nx=>$f
		}
	}
	return (scalar @nx,@nx)
}
															
#sub getFont {
#       use Font::TTFMetrics;
#       my $self = shift;
#       my $authInfo = pop;
#       die qq{Unauthorized access!!!} unless $checkAuthInfo->($authInfo);
#       my $name = $_[0];
#       my $metrics = Font::TTFMetrics->new($sitemodules::Settings::c{dir}{htdocs}.'/fonts/'.$name);
#       return $metrics->get_font_family()
#}

1;
