require_relative '../config/sequel'
require 'bcrypt'
require 'securerandom'

#the administrator (auth_user) has to have the role with the lowest id in the Roles table

module MemberTracker
  class Auth_user < Sequel::Model
    many_to_many :roles, :class=>"MemberTracker::Role", left_key: :user_id, right_key: :role_id, join_table: :roles_users
    many_to_one :member, :class=>"MemberTracker::Member", key: :mbr_id
    one_to_many :logs, :class=>"MemberTracker::Log", key: :a_user_id
    one_to_many :unit_types, :class=>"MemberTracker::UnitType", key: :a_user_id
    
    def authenticate(auth_user_credentials)
      #auth_user_credentials are :email, :password
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
          auth_user = Auth_user.first(mbr_id: m.id)
          if !auth_user.nil?
            break
          end
        end
      else
        auth_user = Auth_user.first(mbr_id: mbrs[0].id)
      end
      if !auth_user.nil?
        #check to see if first time login
        if auth_user.new_login == 1
          t = Time.now
          #give the new authorized user 2 days to login
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
          auth_user.get_roles("authenticate").each do |r|
            au_roles << r
          end
          #check to see if this auth_user is active ('inactive' only present when it is the users role)
          if au_roles.include?('inactive')
            message['error'] = 'inactive'
          end
          message['auth_user_roles'] = au_roles
          #set last_login
          auth_user.last_login = Time.now
          auth_user.save
          #log this login
          #get action id
          action_id = nil
          Action.select(:id, :type).map(){|x|
            if x.type == "login"
              action_id = x.id
            end
          }
          #remove old login logs, keeping first and last two
          login_log_ids = Log.where(a_user_id: auth_user.id, action_id: action_id).map(:id).sort
          if login_log_ids.length > 3
            login_log_ids.shift
            login_log_ids.pop(2)
            Log.where(id: login_log_ids).delete
          end
          #add new
          l = Log.new(mbr_id: auth_user.mbr_id, a_user_id: auth_user.id, ts: Time.now, action_id: action_id, notes: "login")
          l.save
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
    def get_roles(type = "default")
      #returns an array [[role_id, role_description],[]]
      au_role = self.roles.first
      roles = Role.map(){|x| [x.rank, x.id, x.description, x.name]}
      roles.sort!
      #if this user has a role different from 'inactive' need to pull last element (the 'inactive' one)
      if au_role.name != 'inactive'
        roles.pop
      end
      au_roles = []
      roles.each do |r|
        if r[0] >= au_role.rank
          if type == "default"
            au_roles << r[1,2]
          elsif type == "authenticate"
            #just need the name
            au_roles << r[3]
          end
        end
      end
      return au_roles
    end
    
  end
end
  