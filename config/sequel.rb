require 'sequel'
#for remote use Heroku
DB = Sequel.connect(ENV['DATABASE_URL'])
#for local use
#DB = Sequel.connect("#{ENV['PARCDBCONN']}")