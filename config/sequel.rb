require 'sequel'
#DB = Sequel.sqlite("./db/#{ENV.fetch('RACK_ENV', 'development')}.db")
DB = Sequel.connect(ENV['DATABASE_URL'])
#for local use
#DB = Sequel.connect('postgres://user:password@localhost:5432/database')