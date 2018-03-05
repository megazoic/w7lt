require 'csv'
require 'sinatra'
require 'sequel'

#DB = Sequel.sqlite("./db/development.db")
#DB = Sequel.connect('postgres://dev-mbr:4hamD3v@localhost:5432/mbr-devdb')

colnames = [:phw, :phw_pub, :phh, :phh_pub, :phm, :phm_pub, :fname, :lname, :email, 
:apt, :city, :street, :zip, :state, :callsign, :paid_up, :arrl, :ares, 
:net, :ve, :elmer, :arrl_expire, :license_class, :mbr_type]

dataType_string =[1,0,1,0,1,0,1,1,1,1,1,1,1,1,1,0,0,0,0,0,0,1,1,1]
colData = []
arrayOfRecords = CSV.read("./mydata.txt")
arrayOfRecords.each do |record|
  temp = []
  count = 0
  record.each{|col|
    if dataType_string[count] == 1
      #look for :arrl_expire date and change
      if count == 21 && col != ''
        temp << col.gsub(',','-')
      else
        temp << "#{col}"
      end
    else
      temp << col.to_i
    end
    count = count + 1
  }
  colData << temp
end


DB[:members].import(colnames, colData)
