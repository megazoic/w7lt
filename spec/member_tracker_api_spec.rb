require 'rack/test'
require 'json'
require_relative '../app/api'

module MemberTracker
  RSpec.describe 'Member Tracker API' do
    include Rack::Test::Methods
    
    def app
      MemberTracker::API.new
    end
    
    it 'records submitted members' do
      member = {
        'name' => 'nick',
        'call' => 'KI7PTT',
        'email' => 'nick@nicksit.com'
      }
      
      post '/members', JSON.generate(member)
      expect(last_response.status).to eq(200)
      
      parsed = JSON.parse(last_response.body)
      expect(parsed).to include('member_id' => a_kind_of(Integer))
    end
  end
end