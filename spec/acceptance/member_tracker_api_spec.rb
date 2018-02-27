require 'rack/test'
require 'json'
require_relative '../../app/api'

module MemberTracker
  RSpec.describe 'Member Tracker API', :db do
    include Rack::Test::Methods
    
    def app
      MemberTracker::API.new
    end
    
    context 'with existing auth_user in db' do
      new_auth_user_data = {
        'fname' => 'first_name',
        'lname' => 'last_name',
        'authority' => 0,
        'email' => '456@789.com',
        'password' => 'ab*dEF4b'}
      before do
         post '/create_auth_user', JSON.generate(new_auth_user_data)
      end
      it 'authenticates (gets id and authority) for legit user' do
        auth_user_credentials = { 'email' => '456@789.com',
          'password' => 'ab*dEF4b' }
        post '/login', JSON.generate(auth_user_credentials)
        expect(last_response.status).to eq(302)
        expect(rack_mock_session.cookie_jar.to_hash['auth_user_id'].to_i).to\
        be_a_kind_of(Integer)
        expect(rack_mock_session.cookie_jar.to_hash['auth_user_authority'].to_i).to\
        be_a_kind_of(Integer)
      end
      it 'fails to authenticate illegit user' do
        auth_user_credentials = { 'email' => '456@789.com',
          'password' => 'test' }
        post '/login', JSON.generate(auth_user_credentials)
        expect(last_response.status).to eq(302)
        expect(rack_mock_session.cookie_jar.to_hash['auth_user_id']).to eq(nil)
        expect(last_response.location).to match("http://example.org/login")
      end
    end
    context 'when logged in with authority' do
      it 'records submitted members' do
        member_data = {
          'fname' => 'joe',
          'lname' => 'smith'
        }
        #, {},'HTTP_COOKIE' => 'auth_user_id=3'
        post '/members', JSON.generate(member_data)
        expect(last_response.status).to eq(200)
      
        parsed = JSON.parse(last_response.body)
        expect(parsed).to include('member_id' => a_kind_of(Integer))
      end
      #before do
        #need authority to test this so give it here
        #rack_mock_session.set_cookie('auth_user_id=1')
        #rack_mock_session.set_cookie('auth_user_authority=0')
        #end
      it 'creates new auth_user' do
      new_auth_user_data = { 'fname' => 'first_name',
        'lname' => 'last_name',
        'authority' => 0,
        'email' => '456@789.com',
        'password' => 'ab*dEF4b' }
      post '/create_auth_user', JSON.generate(new_auth_user_data)
      expect(last_response.status).to eq(200)
      parsed = JSON.parse(last_response.body)
      expect(parsed).to include('auth_user_id' => a_kind_of(Integer))
    end
      it 'reads auth_user'
      it 'updates and destroys auth_user'
      it 'displays members'
    end
  end
end