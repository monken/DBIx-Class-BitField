{
package
  Schema::Item;
  
use base 'DBIx::Class';

__PACKAGE__->load_components(qw(BitField Core));

__PACKAGE__->table('item');

__PACKAGE__->add_columns(
  id => { data_type => 'integer' },
  bitfield => { data_type => 'integer', bitfield => [qw(status1 status2 status3)] },
  bitfield2 => { data_type => 'integer', 
                 bitfield => [qw(status1 status2 status3)], 
                 bitfield_prefix => 'status_', 
                 accessor => '__bitfield2',
                 is_nullable => 1 },

);

__PACKAGE__->set_primary_key('id');

__PACKAGE__->resultset_class('DBIx::Class::ResultSet::BitField');

}


{ 
package 
  Schema;

use base 'DBIx::Class::Schema';

__PACKAGE__->load_classes('Item');

sub connect {
  my $class = shift;
  my $schema = $class->next::method('dbi:SQLite::memory:');
  $schema->deploy;
  return $schema;
}

}

1;

