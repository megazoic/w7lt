require_relative '../../../app/api'
require 'rack/test'
require 'erb'

module MemberTracker
  
  RSpec.describe API do
    include Rack::Test::Methods
    
    def app
      API.new(member: member, auth_user: auth_user)
    end
    def parsedJSON
      JSON.parse(last_response.body)
    end
    def parsedHTML
      mbr_arry = JSON.parse(last_response.body)
      out = ERB.new(("<% mbr_arry.each do |m| %><li><a href=\"/member/<%=m[0]%>"+
      "\"><%=m[1]%> <%=m[2]%></a></li><%end%>"), nil, "%").result(binding)
      out
    end

    let(:member) {instance_double ('MemberTracker::Member')}
    let(:auth_user) {instance_double ('MemberTracker::Auth_user')}
    
    describe 'POST /login' do
      let(:auth_user_credentials) {{'some'=>'data', 'some_more'=>'data'}}
      context 'when the auth_user is successfully authorized' do
        before do
          allow(auth_user).to receive(:authenticate)
          .with(auth_user_credentials)
          .and_return(Hash['auth_user_id',0])
        end
        it 'responds with a 302 (Found)' do
          post '/login', JSON.generate(auth_user_credentials)
          expect(last_response.status).to eq(302)
        end
        it 'redirects to \'/\' the root route' do
          post '/login', JSON.generate(auth_user_credentials)
          #need to figure out how to set this
          expect(last_response.location).to match("http://example.org/")
        end
        it 'returns the authorized user\'s id' do
          post '/login', JSON.generate(auth_user_credentials)
          expect(rack_mock_session.cookie_jar.to_hash['auth_user_id'].to_i).to \
          be_a_kind_of(Integer)
        end
        it 'returns the authorized user\'s authority' do
          post '/login', JSON.generate(auth_user_credentials)
          expect(rack_mock_session.cookie_jar.to_hash['auth_user_authority'].to_i).to \
          be_a_kind_of(Integer)
        end
      end
      context 'when the auth_user is unsuccessfully authorized' do
        before do
          allow(auth_user).to receive(:authenticate)
          .with(auth_user_credentials)
          .and_return(Hash['error','an error'])
        end
        it 'responds with a 302 (Found)' do
          post '/login', JSON.generate(auth_user_credentials)
          expect(last_response.status).to eq(302)
        end
        it 'redirects to \'/login\'' do
          post '/login', JSON.generate(auth_user_credentials)
          #need to figure out how to set this
          expect(last_response.location).to match("http://example.org/login")
        end
      end
    end
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
          .and_return([[0, 'joe', 'smith'], [1, 'mary', 'smith']])
        end
          
        it 'returns a member as JSON' do
          get '/members/smith', {}, {'HTTP_ACCEPT' => 'application/json'}
          expect(parsedJSON).to eq([[0, 'joe', 'smith'], [1, 'mary', 'smith']])
        end
        it 'returns a member as HTML' do
          get '/members/smith', {}, {'HTTP_ACCEPT' => 'application/json'}
          test_str = "<li><a href=\"/member/0\">joe smith</a></li>"+
          "<li><a href=\"/member/1\">mary smith</a></li>"
          expect(parsedHTML).to match(test_str)
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
    describe 'POST /create_auth_user' do
      let(:auth_user_data) {{'some'=>'data'}}
      context 'when the auth_user is successfully created' do
        before do
          allow(auth_user).to receive(:create)
          .with(auth_user_data)
          .and_return({'auth_user_id' => 5, 'auth_user_authority'=>0})
        end
        it 'returns the auth_user id' do
          post '/create_auth_user', JSON.generate(auth_user_data)
          parsed = parsedJSON
          expect(parsed).to include('auth_user_id' => 5)
        end
        it 'responds with a 200 (OK)' do
          post '/create_auth_user', JSON.generate(auth_user_data)
          expect(last_response.status).to eq(200)
        end
        it 'returns the auth_user\'s authority' do
          post '/create_auth_user', JSON.generate(auth_user_data)
          parsed = parsedJSON
          expect(parsed).to include('auth_user_authority' => 0)
        end
      end
      context 'when the auth_user fails to be created' do
        before do
          allow(auth_user).to receive(:create)
          .with(auth_user_data)
          .and_return({'error' => 'incomplete'})
        end
        it 'returns error message' do
          post '/create_auth_user', JSON.generate(auth_user_data)
          parsed = parsedJSON
          expect(parsed).to have_key('error')
        end
        it 'responds with a 422 (Unprossable Entry)' do
          post '/create_auth_user', JSON.generate(auth_user_data)
          expect(last_response.status).to eq(422)
        end
      end
    end
  end
end