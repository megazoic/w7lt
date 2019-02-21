require_relative '../config/sequel'
require 'bcrypt'
require 'securerandom'

module MemberTracker
  class Auth_user < Sequel::Model
    many_to_many :roles, left_key: :user_id, right_key: :role_id, join_table: :roles_users
    many_to_one :member, key: :mbr_id
    
    def authenticate(auth_user_credentials)
      #returns a hash with 'auth_user_id' and 'auth_user_authority' keys
      #if passed and 'error' key if fail
      message = Hash.new
      #test to see if auth_user_credentials have email and password keys
      ['email', 'password'].each do |f|
        unless auth_user_credentials.has_key?(f)
          message['error'] = 'missing field'
          return message
        end
      end
      #get auth_user, test password, if pass return array of [id, role1, role2, ...]
      #first, find member with this email, if more than one, need to iterate through :ids
      mbrs = Member.where(email: auth_user_credentials['email']).all
      mbr_id = 0
      if mbrs.count > 1
        mbrs.each do |m|
          #look through the auth_user table to find corresponding member
          auth_user = Auth_user.find(mbr_id: m.id)
          if !auth_user.nil?
            break
          end
        end
      else
        auth_user= Auth_user.find(mbr_id: mbrs[0].id)
      end
      if !auth_user.nil?
        #check to see if first time login
        if auth_user.new_login == 1
          message['error'] = 'new_user'
          message['auth_user_id'] = auth_user.id
        elsif BCrypt::Password.new(auth_user.password) == auth_user_credentials['password']
          message['auth_user_id'] = auth_user.id
          #get roles
          au_roles = []
          auth_user.roles.each do |r|
            au_roles << r.name
          end
          message['auth_user_roles'] = au_roles
        else
          message['error'] = 'password mismatch'
        end
      else #close !auth_user.nil?
        message['error'] = 'no such user'
      end
      message
    end
    def update(au_password, mbr_id)
      encrypted_pwd = BCrypt::Password.create(au_password).to_s
      au = Auth_user.where(mbr_id: mbr_id).update(password: encrypted_pwd, new_login: 0)
    end
    def create(mbr_id, roles, email)
      message = Hash.new
      password = SecureRandom.hex[0,6]
      encrypted_pwd = BCrypt::Password.create(password)
      #test for existing user with these credentials
      existing_auth_user = Auth_user.first(mbr_id: mbr_id)
      if !existing_auth_user.nil?
        message["success"] = false
        message["mbr_id"] = mbr_id
        message['message'] = 'this auth_user already exists, select update instead of create new'
        return message
      end
      #test for duplicate emails in members table for this user
      member_set = Member.select(:id, :fname, :lname, :callsign, :email).where(email: email).all
      if member_set.length > 1
        puts "there is more than one member with this email"
        member_set.each do |m|
          puts "#{m.fname}, #{m.lname}, #{m.callsign}, #{m.email}"
        end
        message["success"] = false
        message["mbr_id"] = mbr_id
        message['message'] = 'this auth_user shares an email which needs to be unique'
        return message
      end
       #all criteria are passing, go ahead and save this auth_user
      role_names = []
      begin
        auth_user = Auth_user.new(:password => encrypted_pwd, :mbr_id => mbr_id, :time_pwd_set => Time.now, :new_login => 1)
        auth_user.save
        #set the the roles for this user
        roles.each do |k,v|
          auth_user.add_role(Role[k.to_i])
        end
        auth_user.roles.each {|r| role_names << r.name}
        message["success"] = true
        message["mbr_id"] = mbr_id
        message["message"] = "temp password for member #{member_set[0].values[:callsign]} is #{password}"
      rescue StandardError => e
        message["success"] = false
        message["mbr_id"] = mbr_id
        message["message"] = "error: could not create authorized user.\n#{e}"
      end
      return message
    end
  end
end
  