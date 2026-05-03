require 'sequel'
# Use ||= so spec_helper can connect and run migrations before models load,
# without triggering a "already initialized constant" warning.
DB ||= Sequel.connect(ENV['DATABASE_URL'])