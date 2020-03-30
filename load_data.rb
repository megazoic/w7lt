require 'csv'
require 'sinatra'
require 'sequel'

#DB = Sequel.sqlite("./db/development.db")
DB = Sequel.connect('postgres://dev-mbr:4hamD3v@localhost:5432/mbr-devdb')

@colnames = [:fname, :lname, :callsign, :license_class, :email, :gio_id, :phh, :phm_pub, 
:phw_pub, :phh_pub, :street, :city, :state, :zip, :paid_up]

dataType_string =[1,1,1,1,1,0,1,0,0,0,1,1,1,1,0]
@colData = []
arrayOfRecords = CSV.read("./db/2020-03-28_mbrs_tbl.csv")
arrayOfRecords.each do |record|
  temp = []
  count = 0
  record.each{|col|
    if dataType_string[count] == 1
      temp << "#{col}"
    else
      temp << col.to_i
    end
    count = count + 1
  }
  @colData << temp
end


#DB[:members].import(colnames, colData)
