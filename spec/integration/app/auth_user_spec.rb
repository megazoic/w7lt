require_relative '../../../app/auth_user'

module MemberTracker
  #:aggregate_failures allows muclitple failures to be recorded p87
  RSpec.describe AuthUser, :aggregate_failures, :db do
    let(:auth_user) {AuthUser.new}
    let(:auth_user_credentials) { {'email' => '456@789.com', 'password' => 'ab*dEF4b'} }
    let(:valid_new_auth_user_data) { { 'fname' => 'fname',
      'lname' => 'lname',
      'email' => '456@789.com',
      'password' => 'ab*dEF4b',
      'authority' => 0 } }
    describe '#authenticate' do
      it 'accepts a valid auth_user\'s credentials' do
        member = create_member(email: '456@789.com')
        create_auth_user(member: member, password: 'ab*dEF4b')
        test_user = auth_user.authenticate(auth_user_credentials)
        expect(test_user['auth_user_id'].to_i).to be_an_instance_of(Integer)
        expect(test_user['auth_user_roles']).to be_an_instance_of(Array)
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
  end
end
