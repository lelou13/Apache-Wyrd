#!/usr/bin/perl

use strict;
use warnings;
package Apache::Wyrd::Interfaces::Dater;
use Date::Calc qw(Add_Delta_Days Add_Delta_YMD);

sub _this_year {
	my ($self, $year) = @_;
	my @localtime = localtime;
	return ($localtime[5]+1900);
}

sub _num_today {
	my ($self) = @_;
	return $self->_num_year($self->_ymd_today);
}

sub _add_ymd {
	my $self = shift;
	my ($by, $bm, $bd, $ay, $am, $ad) = @_;
	if (scalar(@_) == 3) {
		($ay, $am, $ad) = ($by, $bm, $bd);
		($by, $bm, $bd) = $self->_ymd_today;
	} elsif (scalar(@_) == 4) {
		my $date = $by;
		($ay, $am, $ad) = ($bm, $bd, $ay);
		($by, $bm, $bd) = $self->_ymd_year($date);
	} elsif (scalar(@_) == 6) {
		#already OK, do nothing
	} else {
		$self->_raise_exception("Could not make any sense of input to _add_ymd: " . join ', ', @_);
	}
	return Add_Delta_YMD($by, $bm, $bd, $ay, $am, $ad);
}

sub _num_add_ymd {
	my $self = shift;
	my ($y, $m, $d) = $self->_add_ymd(@_);
	return $self->_num_year($y, $m, $d);
}

sub _num_yesterday {
	my ($self) = @_;
	my ($year, $month, $day) = $self->_ymd_today;
	($year, $month, $day) = Add_Delta_Days($year, $month, $day, -1);
	return $self->_num_year($year, $month, $day);
}

sub _num_tomorrow {
	my ($self) = @_;
	my ($year, $month, $day) = $self->_ymd_today;
	($year, $month, $day) = Add_Delta_Days($year, $month, $day, 1);
	return $self->_num_year($year, $month, $day);
}

sub _ymd_today {
	my ($self) = @_;
	my @localtime = localtime;
	$localtime[4]++;
	return $localtime[5], $localtime[4], $localtime[3];
}

sub _ymd_year {
	my ($self, $date) = @_;
	$self->_raise_exception("_ymd_year requires an 8 digit argument")
		unless(length($date) == 8);
	my $y = substr($date, 0, 4) + 0;
	my $m = substr($date, 4, 2) + 0;
	my $d = substr($date, 6, 2) + 0;
	return ($y, $m, $d);
}

sub _num_year {
	my ($self, $year, $month, $day) = @_;
	$year = $self->_normalize_year($year);
	return substr('0000' . $year, -4) . substr('00' . $month, -2) . substr('00' . $day, -2);
}

sub _yy2yyyy {
	my ($self, $year) = @_;
	return $self->_normalize_year($year);
}

sub _normalize_year {
	my ($self, $year) = @_;
	if ($year >= 100 and $year < 199) {
		#assume a perl localtime year
		$year += 1900;
	} elsif ($year =~ /^\d{4}$/) {
		$self->_error("Year $year seems out of range") if ($year < 1900 or $year > 2100);
	} elsif ($year > 0) {
		my @localtime = localtime;
		my $two_digit_year = substr($localtime[5], -2);
		if ($two_digit_year > ($year + 50)) {
			$year += 1900;
		} else {
			$year += 2000;
		}
	} else {
		$self->_error("Couldn't make sense of this year: $year");
	}
	return $year;
}

sub _mmddyy2mysql {
	#For dates up to this year, assumes a past date
	my ($self, $value) = @_;
	my ($month, $day, $year) = split('/',$value);
	$year = $self->_normalize_year($year);
	return $self->_mysql_year($year, $month, $day);
}

sub _yyyy2mysql {
	my ($self, $year) = @_;
	return $self->_mysql_year($year);
}

sub _mmddyyyy2mysql {
	my ($self, $value) = @_;
	my ($month, $day, $year) = split('/',$value);
	return $self->_mysql_year($year, $month, $day);
}

sub _mysql_year {
	#don't call this directly.  It assumes OK dates.
	my ($self, $year, $month, $day) = @_;
	return substr('0000' . $year, -4) . '-' . substr('00' . $month, -2) . '-' . substr('00' . $day, -2);
}

sub _date_string {
	my ($self, $begin, $end) = @_;
	my $date = '';
	my %month=('1'=>'January','2'=>'February','3'=>'March','4'=>'April','5'=>'May','6'=>'June','7'=>'July','8'=>'August','9'=>'September','10'=>'October','11'=>'November','12'=>'December');
	$end = $begin unless ($end);
	(($end, $begin) = ($begin, $end)) if ($end and (($begin+0) > ($end+0)));
	no warnings;
	my $year = substr($begin, 0, 4) + 0;
	my $month = substr($begin, 4, 2) + 0;
	my $day = substr($begin, 6, 2) + 0;
	$day =~ s/^0+//;
	if ($end eq $begin) {
		$date = "$year" if $year;
		$date = "$month{$month}&nbsp;$year" if $month;
		$date = "$month{$month}&nbsp;$day,&nbsp;$year" if $day;
		return $date ;
	}
	my $year2 = substr($end, 0, 4) + 0;
	my $month2 = substr($end, 4, 2) + 0;
	my $day2 = substr($end, 6, 2) + 0;
	unless ($year and $month and $day and $year2 and $month2 and $day2) {
		#if any of the dates are unconventional, use the composite form
		my $begin_date = $year;
		my $end_date = $year2;
		$begin_date = "$month{$month}&nbsp;$year" if ($month);
		$end_date = "$month{$month2}&nbsp;$year2" if ($month2);
		$begin_date = "$month{$month}&nbsp;$day,&nbsp;$year" if ($day);
		$end_date = "$month{$month2}&nbsp;$day2,&nbsp;$year2" if ($day2);
		return $begin_date . '&#150;' . $end_date;
	}
	my $dyear = $year2 - $year;
	my $dmonth = $month2 - $month;
	my $dday = $day2 - $day;
	#warn ("$year $month $day $year2 $month2 $day2 $dyear $dmonth $dday");
	$day2 =~ s/^0+//;
	$date = "$month{$month}&nbsp;$day&#150;$day2,&nbsp;$year";
	#if months are different, include them
	$date = "$month{$month}&nbsp;$day,&nbsp;&#150;$month{$month2}&nbsp;$day2,&nbsp;$year" if ($dmonth);
	#if years are different, use full form
	$date = "$month{$month}&nbsp;$day,&nbsp;$year&#150;$month{$month2}&nbsp;$day2,&nbsp;$year2" if ($dyear);
	return $date;
}

1;