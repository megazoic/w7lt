module MemberTracker
  #AuthorizeResult = Struct.new(:success?, :auth_user_id, :error_message)
  class Auth_user
    def authenticate(auth_user_credentials)
      #get auth_user's password, test password, if pass return auth_user_id
      #BCrypt::Password.new(hash) == password
      #believe that auth_user_credentials is a
      #hash {'email' => '123@456.com', 'password' => 'test'}
      #auth_user = DB[:auth_users].where(email: '123@456.com').first
      passed = false
      auth_user = DB[:auth_users].where(email: auth_user_credentials[0]).first
      if !auth_user.nil?
        #there is an auth_user with this email, test password
        if auth_user_credentials[1] == auth_user[:password]
          passed = true
        end
      end
      passed
    end
    def hash_password(password)
      #BCrypt::Password.create(password).to_s
    end
  end
end
  