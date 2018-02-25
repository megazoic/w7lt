require_relative '../config/sequel'
require 'bcrypt'

module MemberTracker
  class Auth_user < Sequel::Model
    TABLE_FIELDS = ['fname', 'lname', 'email', 'password', 'authority']
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
      #get auth_user, test password, if pass return auth_user Sequel dataset
      auth_user = Auth_user.find(email: auth_user_credentials['email'])
      if !auth_user.nil?
        if BCrypt::Password.new(auth_user.password) == auth_user_credentials['password']
          message['auth_user_id'] = auth_user.id
          message['auth_user_authority'] = auth_user.authority
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
      #test integrity of auth_user's data all fields but fname must not be empty
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
      message['auth_user_authority'] = auth_user.authority
      message
    end
  end
end
  