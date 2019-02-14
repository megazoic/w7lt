require_relative '../config/sequel'
require 'bcrypt'

module MemberTracker
  class Auth_user < Sequel::Model
    many_to_many :roles, left_key: :user_id, right_key: :role_id, join_table: :roles_users
    many_to_one :member, key: :mbr_id
    
    TABLE_FIELDS = ['password', 'mbr_id', 'role']
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
        if BCrypt::Password.new(auth_user.password) == auth_user_credentials['password']
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
      else
        message['error'] = 'no such user'
      end
      message
    end
    def create(auth_user_data)
      message = Hash.new
      #check new password for strength move this to javascript
      #password must have one or more each of Caps, Lowercase, number and
      #be between 8 and 24 characters
      regex = /^(?=.*[A-Z]+)(?=.*[0-9]+)(?=.*[a-z]+).{8,24}$/
      temp_password = auth_user_data['password']
      if regex.match(temp_password)
        auth_user_data['password'] = BCrypt::Password.create(temp_password).to_s
      else
        message['error'] = 'password too weak'
        return message
      end
      #test integrity of auth_user's data: there can be no 2 or more auth_users with the same email addr
      TABLE_FIELDS.each do |f|
        unless auth_user_data.has_key?(f)
          message['error'] = 'all fields must be present'
          return message
        end
      end
      auth_user_data.each do |key, value|
        if key != 'fname'
          if value == ''
            message['error'] = 'one or more required fields are empty'
            return message
          end
        end
      end
      #test for existing user with these credentials
      existing_auth_user = Auth_user.find(:email => auth_user_data['email'])
      if !existing_auth_user.nil?
        auth_user_data['password'] = BCrypt::Password.new(existing_auth_user.password)
        message['error'] = 'this auth_user already exists'
        return message
      end
      #test for out of range authority value
      if !(0..3).include?(auth_user_data['authority'])
        message['error'] = 'authorization value out of range'
        return message
      end
      #all criteria are passing, go ahead and save this auth_user
      auth_user = Auth_user.new(auth_user_data)
      auth_user.save
      message['auth_user_id'] = auth_user.id
      message['auth_user_roles'] = auth_user.roles
      message
    end
  end
end
  