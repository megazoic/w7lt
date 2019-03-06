require_relative '../config/sequel'
require 'bcrypt'
require 'securerandom'

module MemberTracker
  class Auth_user < Sequel::Model
    many_to_many :roles, left_key: :user_id, right_key: :role_id, join_table: :roles_users
    many_to_one :member, key: :mbr_id
    one_to_many :logs, key: :a_user_id
    
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
      if mbrs.empty?
        message['error'] = 'no such user'
        return message
      end
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
          t = Time.now
          #give the new authorized user 2 days to login
          puts "time is #{auth_user.time_pwd_set}"
          if t - auth_user.time_pwd_set > 172800
            message['error'] = 'expired'
            #remove auth_user as time as expired
            auth_user.remove_all_roles
            auth_user.delete
          else
            #this is a new user that needs to change password
            #first get their roles
            au_roles = []
            auth_user.roles.each do |r|
              au_roles << r.name
            end
            message['auth_user_roles'] = au_roles
            message['error'] = 'new_user'
          end
          message['auth_user_id'] = auth_user.id
        elsif BCrypt::Password.new(auth_user.password) == auth_user_credentials['password']
          message['auth_user_id'] = auth_user.id
          #get roles
          au_roles = []
          auth_user.roles.each do |r|
            au_roles << r.name
          end
          message['auth_user_roles'] = au_roles
          #set last_login
          auth_user.last_login = Time.now
          auth_user.save
          #log this login
          l = Log.new(mbr_id: auth_user.mbr_id, a_user_id: auth_user.id, ts: Time.now, action_id: 6, notes: "login")
          l.save
          #check to see if this auth_user is active
          if auth_user.active == 0
            message['error'] = 'inactive'
          end
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
  end
end
  