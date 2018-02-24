require 'rack/test'
require 'json'
require_relative '../../app/api'

module MemberTracker
  RSpec.describe 'Member Tracker API', :db do
    include Rack::Test::Methods
    
    def app
      MemberTracker::API.new
    end
    
    it 'records submitted members' do
      member_data = {
        'fname' => 'joe',
        'lname' => 'smith'
      }
      
      post '/members', JSON.generate(member_data)
      expect(last_response.status).to eq(200)
      
      parsed = JSON.parse(last_response.body)
      expect(parsed).to include('member_id' => a_kind_of(Integer))
    end
    it 'authenticates legit user' do
      auth_user_credentials = {
        'auth_user_email' => 'abc@def.com',
        'auth_user_pass' => 'pass'
      }
      post '/login', JSON.generate(auth_user_credentials)
      expect(last_response.status).to eq(302)
      expect(rack_mock_session.cookie_jar.to_hash).to include("auth_user_id" => "24")
    end
    it 'fails to authenticate illegit user'
    it 'creates, updates and destroys user'
  end
end