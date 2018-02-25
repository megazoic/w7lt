require_relative '../../../app/auth_user'

module MemberTracker
  #:aggregate_failures allows muclitple failures to be recorded p87
  RSpec.describe Auth_user, :aggregate_failures, :db do
    let(:auth_user) {Auth_user.new}
    let(:auth_user_credentials) { {'email' => '456@789.com', 'password' => 'ab*dEF4b'} }
    let(:valid_new_auth_user_data) { { 'fname' => 'fname',
      'lname' => 'lname',
      'email' => '456@789.com',
      'password' => 'ab*dEF4b',
      'authority' => 0 } }
    describe '#authenticate' do
      it 'accepts a valid auth_user\'s credentials' do
        #first, save an auth_user with this email
        valid_user = auth_user.create(valid_new_auth_user_data)
        #then test auth_user_credentials using the new id returned
        test_user = auth_user.authenticate(auth_user_credentials)
        expect(test_user['auth_user_id'].to_i).to be_an_instance_of(Integer)
        expect(test_user['auth_user_authority'].to_i).to eq(0)
      end
      it 'rejects a bad password' do
        bad_pass = auth_user_credentials
        bad_pass['password'] = 'bad'
        expect(auth_user.authenticate(bad_pass).has_key?('error')).to be(true)
      end
      it 'rejects a bad email' do
         bad_email = auth_user_credentials
         bad_email['email'] = 'bad'
        expect(auth_user.authenticate(bad_email).has_key?('error')).to be(true)
      end
      it 'rejects credentials with missing field' do
        bad_credentials = auth_user_credentials
        bad_credentials.delete('email')
        expect(auth_user.authenticate(bad_credentials).has_key?('error')).to be(true)
      end
    end
    describe '#create' do
      it 'successfully saves a new auth_user with valid fields' do
        #all fields except fname need to be present
        #password must have one or more each of Caps, Lowercase, number and
        #be between 8 and 24 characters
        result = auth_user.create(valid_new_auth_user_data)
        expect(result).to have_key('auth_user_id')
      end
      context 'is expected to fail because it' do
        it 'has an empty string for a required field' do
          invalid_data = valid_new_auth_user_data
          invalid_data['email'] = ''
          result = auth_user.create(invalid_data)
          expect(result['error']).to eq('one or more required fields are empty')
        end
        it 'is missing a required field' do
          invalid_data = valid_new_auth_user_data
          invalid_data.delete('email')
          result = auth_user.create(invalid_data)
          expect(result['error']).to eq('all fields must be present')
        end
        it 'has a weak password' do
          invalid_data = valid_new_auth_user_data
          invalid_data['password'] = 'test'
          result = auth_user.create(invalid_data)
          expect(result['error']).to eq('password too weak')
        end
        it 'already has an auth_user with this email' do
          #first, save an auth_user with this email
          auth_user.create(valid_new_auth_user_data)
          #then try to save on top of this but need to reset password first
          valid_new_auth_user_data['password'] = 'ab*dEF4b'
          result = auth_user.create(valid_new_auth_user_data)
          expect(result['error']).to eq('this auth_user already exists')
        end
        it 'has an out of bounds authority value' do
          invalid_data = valid_new_auth_user_data
          invalid_data['authority'] = 5
          result = auth_user.create(invalid_data)
          expect(result['error']).to eq('authorization value out of range')
        end
      end
    end
  end
end
