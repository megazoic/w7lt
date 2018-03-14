=begin
Will need to find best way to display discrepancies (where emails don't
match). Handle members who are not located in PARC-mbr cms
#https://api.groups.io/v1/login?email=nick@nicksit.com&password=24jimmyj12" -u 123456
#newuri = URI::HTTP.build({:host => 'www.example.com', :path => '/foo/bar',
  #:query =>'need example'})

#uri = URI("https://api.groups.io/v1/getmembers?group_name=W7LT")
steps to pull groups.io member id, email and full_name
  create instance of GroupsioData
  call setToken method
  call getMbrData

steps to compare records from groups with PARC-mbr data
#require 'sinatra'
#require 'sequel'

#DB = Sequel.connect('postgres://dev-mbr:4hamD3v@localhost:5432/mbr-devdb')

class Member < Sequel::Model
end

@mbrs = Member.select(:id, :fname, :lname, :callsign, :email)


=end

require 'net/http'
#for testing only
#require 'json'
#require 'sinatra'
#require 'sequel'
#for testing purposes only
#DB = Sequel.connect('postgres://dev-mbr:4hamD3v@localhost:5432/mbr-devdb')
#class Member < Sequel::Model
#end
module MemberTracker
  class GroupsioData
    attr_reader :unmatched, :groupsIOError
    def initialize( api_key = '123456' )
      @api_key = api_key
      @has_more = true
      @api_token = ''
      #changes depending on whether need to get token
      @auth = ''
      @page_token = nil
      @mbr_array = [] #array of hashes holding [groups.io_id, full_name, email]
      @resStatus = 200
      @body = ''
      #array of arrays [{parc-mbr hash}:, {groups.io hash}]
      #where the groups.io hash has keys "gio_id" "gio_fn" "gio_email"
      #where the parc_mbr hash has keys "id"", "fname", "lname", "callsign", "email"
      @unmatched = []
      @groupsIOError = {"errorCode" => 0, "errorMsg" => "success"}
    end
  
    def setURI
      query = ''
      path = ''
      if @auth != ''
        # use AUTH_TOKEN
        path = '/v1/getmembers'
        query = 'group_name=W7LT'
        @auth = @api_token
      else
        #call login, use api_key and get AUTH_TOKEN
        path = '/v1/login'
        query = 'email=nick@nicksit.com&password=24jimmyj12'
        @auth = @api_key
      end
      if @page_token.nil? == false
        #include page_token in request
        query << "&page_token=#{@page_token}"
      end
      URI::HTTPS.build({:host => 'api.groups.io', :path => path,
        :query => query})
    end
    def extractMbrData(jsonResp)
      #return an array of hashes containing groups.io
      #id, full_name, email held in @mbr_array
    
      mbrRaw = JSON.parse(jsonResp)
      #first build out vars for next request
      if mbrRaw["has_more"] == true
        @page_token = mbrRaw["next_page_token"]
      else
        @has_more = false
      end
      #build out array of groups.io member hashes
      mbrRaw["data"].each {|mbr|
        gio_hash = {"gio_id" => mbr["id"], "gio_fn" => mbr["full_name"], "gio_email" => mbr["email"]}
        @mbr_array << gio_hash
      }
    end
    def setToken
      uri = setURI
      req = Net::HTTP::Get.new(uri)
      req.basic_auth @auth, ''

      res = Net::HTTP.start(uri.hostname, uri.port, :use_ssl => true) {|http|
        http.request(req)
      }
      if res.code.to_i < 400
        parsedRes = JSON.parse(res.body)
        @api_token = parsedRes["token"]
        return 0
      else
        @groupsIOError["errorCode"] = 1
        @groupsIOError["errorMsg"] = "unable to get API Token from Groups.io"
      end
    end
    def getMbrData
      while @has_more == true && @resStatus < 400
        uri = setURI
        req = Net::HTTP::Get.new(uri)
        req.basic_auth @auth, ''

        res = Net::HTTP.start(uri.hostname, 443, :use_ssl => true) {|http|
          http.request(req)
        }
        @resStatus = res.code.to_i
        if @resStatus >= 400
          @groupsIOError["errorCode"] = 1
          @groupsIOError["errorMsg"] = "more data to get but Groups.io returned #{@resStatus}"
          break
        end
        extractMbrData(res.body)
      end
      #need to remove these elements
      @mbr_array.delete_if {|gio_hash| gio_hash["gio_fn"] == 'PARC mod'}
      @mbr_array.delete_if {|gio_hash| gio_hash["gio_fn"] == 'admin mod'}
      @mbr_array.delete_if {|gio_hash| gio_hash["gio_email"] == 'scmods_2000@yahoo.com'}
      if @groupsIOError["errorCode"] = 0
        return 0
      else
        return 1
      end
    end
    def compareEmails
      #get only the members we need
      @mbr_array.each{|gio_hash|
        #find member in parc database with the same groups.io id (stored in gio_id field)
        parc_mbr = Member.select(:id, :fname, :lname, :callsign, :email).first(gio_id: gio_hash["gio_id"])
        if parc_mbr.nil?
          @unmatched << [nil, gio_hash]
        else
          if parc_mbr.email != gio_hash["gio_email"]
            @unmatched << [parc_mbr.values, gio_hash]
          end
        end
      }
    end
    private :extractMbrData, :setURI
  end #close the class GroupsioData
end #close the module MemberTracker


