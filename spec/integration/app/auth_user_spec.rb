require_relative '../../../app/auth_user'

module MemberTracker
  #:aggregate_failures allows muclitple failures to be recorded p87
  RSpec.describe Auth_user, :aggregate_failures, :db do
    let(:auth_user) {Auth_user.new}
    let(:real_auth_user_credentials) { ['123@456.com', 'test'] }
    let(:bad_pass_auth_user_credentials) { ['123@456.com', 'pest'] }
    let(:bad_email_auth_user_credentials) { ['13@456.com', 'test'] }
    
    describe '#authenticate' do
      it 'successfully tests a auth_user\'s credentials' do
        expect(auth_user.authenticate(real_auth_user_credentials)).to eq(true)
      end
      it 'rejects a bad password' do
        expect(auth_user.authenticate(bad_pass_auth_user_credentials)).to eq(false)
      end
      it 'rejects a email' do
        expect(auth_user.authenticate(bad_email_auth_user_credentials)).to eq(false)
      end
    end
  end
end
