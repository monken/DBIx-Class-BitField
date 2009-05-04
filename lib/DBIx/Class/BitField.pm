package DBIx::Class::BitField;

use strict;
use warnings;

use Carp;

use base 'DBIx::Class';

sub register_column {
  my ($self, $column, $info, @rest) = @_;
  
  return $self->next::method($column, $info, @rest)
    unless($self->__is_bitfield($info));
    
  $info->{accessor} ||= '_'.$column;
  $info->{default_value} = 0;
  
  $self->next::method($column, $info, @rest);
  
  my $prefix = $info->{bitfield_prefix} || q{};
  
  my @fields = @{$info->{bitfield}};
  
  
  {
    my $i = 0;
    no strict qw(refs);
    foreach my $field (@fields) {
      if($self->can($prefix.$field)) {
        carp 'Bitfield accessor '.$prefix.$field.' cannot be created since there is an accessor of that name already';
        $i++;
        next;
      }
      my $bit = 2**$i;
      *{$prefix.$field} = sub { shift->__bitfield_item($field, $bit, $info->{accessor}, @_) };
      $i++;
    }
    
    *{$column} = sub { shift->__bitfield($column, $info->{accessor}, \@fields, @_) };
  }
  
  
}

sub __is_bitfield {
  my ($self, $info) = @_;
  return defined $info->{data_type} && $info->{data_type} =~ /^int/xsmi && ref $info->{bitfield} eq "ARRAY";
}


sub __is_bitfield_item {
  my ($self, $column) = @_;
  return if($self->has_column($column));# || $self->is_relationship($column));
  foreach my $c ($self->columns) {
    my $info = $self->column_info($c);
    next unless($self->__is_bitfield($info));
    return $c if(grep { $_ eq $column } @{$info->{bitfield} || []});
    my $prefix = $info->{bitfield_prefix} || '';
    return $c if(grep { $prefix.$_ eq $column } @{$info->{bitfield} || []});
  }
  return;
}

sub store_column {
  my ($self, $column, $value) = @_;
  my $info= $self->column_info($column);
  if($self->__is_bitfield($info) && ($value !~ /^\d+$/ || int($value) ne $value)) {
    if(ref $value eq 'ARRAY') {
      foreach my $bit (@{$value || []}) {
        $self->can($bit) ? $self->$bit(1) : croak qq(bitfield item '$bit' does not exist);
      }
    } else {
      $self->can($value) ? $self->$value(1) : croak qq(bitfield item '$value' does not exist);
    }
    my $accessor = $info->{accessor};
    $value = $self->$accessor;
  }
  $self->next::method($column, $value);
}

sub __bitfield_item {
  my ($self, $field, $bit, $accessor, $set) = @_;
  my $value = $self->$accessor || 0;
  return ($value | $bit) == $value ? 1 : 0 unless defined $set;
  
  $self->$accessor($set ? $value | $bit | $bit : $value - ($value & $bit));
  return $set;
}

sub __bitfield {
  my ($self, $column, $accessor, $fields) = @_;
  
  my $value = $self->$accessor || return [];
  
  my @fields = ();
  my $i = 0;
  foreach my $field (@{$fields}) {
    push(@fields, $field) if(($value | 2**$i) == $value);
    $i++;
  }
  
  return \@fields;
}

sub new {
    my ($self, $data, @rest) = @_;
    my $bits = {};
    while(my ($column, $value) = each %{$data || {}}) {
        next unless(my $bitfield = $self->__is_bitfield_item($column));
        $bits->{$column} = $value;
        delete $data->{$column};
    }
    my $row = $self->next::method($data, @rest);
    
    while(my ($column, $value) = each %{$bits || {}}) {
        $row->$column($value);
    }
    
    
    return $row;
}

1;

__END__

=head1 NAME

DBIx::Class::BitField - Store multiple boolean fields in one integer field

=head1 SYNOPSIS

  package MySchema::Item;

  use base 'DBIx::Class';

  __PACKAGE__->load_components(qw(BitField Core));

  __PACKAGE__->table('item');

  __PACKAGE__->add_columns(
    id     =>   { data_type => 'integer' },
    status =>   { data_type => 'integer', 
                  bitfield => [qw(active inactive foo bar)] 
    },
    advanced_status => { data_type => 'integer', 
                         bitfield => [qw(1 2 3 4)], 
                         bitfield_prefix => 'status_', 
                         accessor => '_foobar',
                         is_nullable => 1
    },

  );

  __PACKAGE__->set_primary_key('id');

  __PACKAGE__->resultset_class('DBIx::Class::ResultSet::BitField');

  1;


Somewhere in your code:

  my $rs = $schema->resultset('Item');
  my $item = $rs->create({
      status          => [qw(active foo)],
      advanced_status => [qw(status_1 status_3)],
  });
  
  $item2 = $rs->create({
        active   => 1,
        foo      => 1,
        status_1 => 1,
        status_3 => 1,
  });
  
  # $item->active   == 1
  # $item->foo      == 1
  # $item->status   == ['active', 'foo']
  # $item->_status  == 5
  # $item->status_1 == 1
  # $item->status_3 == 1
  
  $item->foo(0);
  $item->update;

=head1 DESCRIPTION

This module is useful if you manage data which has a lot of on/off attributes like I<active, inactive, deleted, important, etc.>. 
If you do not want to add an extra column for each of those attributes you can easily specify them in one C<integer> column.

A bit field is a way to store multiple bit values on one integer field.

=for html <p>Read <a href="http://en.wikipedia.org/wiki/Bit_field">this wikipedia article</a> for more information on that topic.</p>

The main benefit from this module is that you can add additional attributes to your result class whithout the need to 
deploy or change the schema on the data base.

=head2 Example

A bit field C<status> with C<data_type> set to C<int> or C<integer> (case insensitive) and C<active, inactive, deleted> will create
the following accessors:

=over

=item C<< $row->status >>

This is B<not> the value which is stored in the database. This accessor returns the status as an array ref. Even if there is
only one value in it. You can set them as well:

  $row->status(['active', 'inactive']);
  # $row->status == ['active', 'inactive']

=item C<< $row->active >>, C<< $row->inactive >>, C<< $row->deleted >>

These accessors return either C<1> or C<0>. It will act like normal column accessors if you add a parameter by returning that value.

  $row->active(1);
  # $row->active == 1
  # $row->status == ['active']

=item C<< $row->_status >>

This accessor will hold the internal integer representation if the bit field.

  $row->status(['active', 'inactive']);
  # $row->_status == 3
  
You can change the name of the accessor via the C<accessor> attribute:

__PACKAGE__->add_columns(
  status =>   { data_type => 'integer', 
                bitfield  => [qw(active inactive deleted)],
                accessor  => '_status_accessor',
  },

=back

=head2 ResultSet operations

In order to use result set operations like C<search> or C<update> you need to set the result set class to
C<DBIx::Class::ResultSet::BitField> or to a class which inherits from it.

=head3 update

  $rs->update({ status => ['active'] });

This will update the status of all items in the result set to C<active>. This will use a single SQL query only.

=head3 search_bitfield

=head1 AUTHOR

Moritz Onken, C<< onken@netcubed.de >>

=head1 LICENSE

Copyright 2009 Moritz Onken, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.