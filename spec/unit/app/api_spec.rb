require_relative '../../../app/api'
require 'rack/test'

module MemberTracker
  
  RSpec.describe API do
    include Rack::Test::Methods
    
    def app
      API.new(member: member)
    end
    def parsedJSON
      JSON.parse(last_response.body)
    end

    let(:member) {instance_double ('MemberTracker::Member')}
    
    describe 'POST /members' do
      let(:member_data) {{'some'=>'data'}}
      context 'when the member is successfully recorded' do
        before do
          allow(member).to receive(:record)
          .with(member_data)
          .and_return(RecordResult.new(true, 417, nil))
        end
          
        it 'returns the member id' do
          post '/members', JSON.generate(member_data)
          parsed = parsedJSON
          expect(parsed).to include('member_id' => 417)
        end
        it 'responds with a 200 (OK)' do
          post '/members', JSON.generate(member_data)
          expect(last_response.status).to eq(200)
        end
      end
      context 'when the member fails validation' do
        before do
          allow(member).to receive(:record)
          .with(member_data)
          .and_return(RecordResult.new(false, 417, 'member incomplete'))
        end
        it 'returns an error message' do
          post '/members', JSON.generate(member_data)
          parsed = parsedJSON
          expect(parsed).to include('error' => 'member incomplete')
        end
        it 'responds with a 422 (Unprocessable entity)' do
          post '/members', JSON.generate(member_data)
          expect(last_response.status).to eq(422)
        end
      end
    end
    describe 'GET /members/:name' do
      context 'when a member is present' do
        before do
          query_name = 'smith' 
          allow(member).to receive(:members_with_lastname)
          .with(query_name)
          .and_return([['joe', 'smith'], ['mary', 'smith']])
        end
          
        it 'returns a member as JSON' do
          get '/members/smith'
          expect(parsedJSON).to eq([['joe', 'smith'], ['mary', 'smith']])
        end
        it 'responds with a 200 (OK)' do
          get '/members/smith'
          expect(last_response.status).to eq(200)
        end
      end
      context 'when a member is not present' do
        before do
          query_name = 'smith' 
          allow(member).to receive(:members_with_lastname)
          .with(query_name)
          .and_return([])
        end
        it 'returns an empty array as JSON' do
          get '/members/smith'
          expect(parsedJSON).to eq([])
        end
        it 'responds with a 200 (OK)' do
          get '/members/smith'
          expect(last_response.status).to eq(200)
        end
      end
    end
  end
end