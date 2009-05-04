use inc::Module::Install;

# Define metadata
name 'DBIx-Class-BitField';
all_from 'lib/DBIx/Class/BitField.pm';

repository 'http://github.com/monken/DBIx-Class-BitField/tree/master';

# Specific dependencies
requires 'DBIx::Class' => '0.08102';

test_requires 'Test::More'     => '0.42';
test_requires 'DBD::SQLite';

WriteAll;
