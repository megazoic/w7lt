require 'sequel'
#for remote use Heroku
#DB = Sequel.connect(ENV['DATABASE_URL'])
#for local use
DB = Sequel.connect('postgres://dev-mbr:4hamD3v@localhost:5432/mbr-devdb')